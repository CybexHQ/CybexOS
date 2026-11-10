"""Nixpkgs revisions Cybex OS has verified for a release.

Machines don't take the newest nixos-unstable revision as it is. NixOS moves
the channel on while packages it couldn't build are still missing (codex and
tectonic on 2026-11-10), and each machine would be the first to try that
Nixpkgs with its own Cybex OS release. The daily Nixpkgs canary
(scripts/nixpkgs-canary --verified) checks each published release against the
channel and records the revisions where it evaluates, needs nothing NixOS
hasn't built and builds every expected local build. An update moves a
machine's Nixpkgs only to the newest revision verified for the release it
will run, never backwards (owner decision, 2026-11-10).

The record is `nixpkgs/verified.json` on the repository's `nixpkgs-verified`
branch, read through the same GitHub API as releases: the repository is the
trust root (trust.py). Nix checks the revision's content against the recorded
NAR hash when it fetches it.
"""
import re

from .common import Failure, parse
from .trust import GITHUB_API, EndpointNotFound, version

BRANCH = 'nixpkgs-verified'
PATH = 'nixpkgs/verified.json'
URL = f'{GITHUB_API}/contents/{PATH}?ref={BRANCH}'
REVISION = re.compile('[0-9a-f]{40}')
NAR_HASH = re.compile(r'sha256-[A-Za-z0-9+/]{43}=')
FIELDS = ('rev', 'narHash', 'lastModified', 'releases')


def entries(fetch, branch):
    """The revisions of a Nixpkgs branch verified so far, newest first.

    None before the first verification. Any other problem reading the record
    is a Failure: a machine never moves Nixpkgs on a record it can't read.
    """
    try:
        data = parse(fetch.get(URL, limit=1024 * 1024, accept='application/vnd.github.raw+json'))
    except EndpointNotFound:
        return []
    return validate(data, branch)


def validate(data, branch):
    if not isinstance(data, dict) or data.get('schema') != 1 or not isinstance(data.get('branches'), dict):
        raise Failure('The verified Nixpkgs record is invalid.')
    found = data['branches'].get(branch, [])
    if not isinstance(found, list):
        raise Failure('The verified Nixpkgs record is invalid.')
    result = []
    for item in found:
        if (not isinstance(item, dict) or not isinstance(item.get('rev'), str) or not REVISION.fullmatch(item['rev'])
                or not isinstance(item.get('narHash'), str) or not NAR_HASH.fullmatch(item['narHash'])
                or type(item.get('lastModified')) is not int or item['lastModified'] <= 0
                or not isinstance(item.get('releases'), list) or not item['releases']):
            raise Failure('The verified Nixpkgs record is invalid.')
        for release in item['releases']:
            version(release)
        result.append({key: item[key] for key in FIELDS})
    return sorted(result, key=lambda item: item['lastModified'], reverse=True)


def newest(found, release, installed):
    """The newest revision verified for `release` that is newer than `installed`.

    `installed` is the machine lock's locked Nixpkgs; None when nothing newer
    has been verified for this release.
    """
    current = installed.get('lastModified')
    current = current if type(current) is int else 0
    for item in found:
        if release in item['releases'] and item['lastModified'] > current and item['rev'] != installed.get('rev'):
            return item
    return None


def locked(entry):
    """The lock node's `locked` for a verified revision."""
    return {'type': 'github', 'owner': 'NixOS', 'repo': 'nixpkgs', 'rev': entry['rev'],
            'narHash': entry['narHash'], 'lastModified': entry['lastModified']}
