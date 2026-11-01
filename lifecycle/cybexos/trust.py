"""Release discovery. The GitHub repository is the trust root.

A Cybex OS release is a published GitHub release of REPO with a semantic tag.
There are no publisher signatures: HTTPS to GitHub and the repository's own
access control authenticate a release. Staging pins the tag's exact commit
and the content hash of what it downloads, and a release's own source declares
its version and requirements. No Nix evaluation or privilege escalation here.
"""
import hashlib
import http.client
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

from .common import Failure, atomic, parse, read

API = 1
REPO = 'CybexHQ/CybexOS'
# The Nixpkgs branch a release follows: release.json's "nixos" and an entry of
# a release's release/compatibility.json "nixos" list. A branch, not a version.
NIXOS = 'unstable'
GITHUB_API = f'https://api.github.com/repos/{REPO}'
HOSTS = {'api.github.com'}
SEMVER = re.compile(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(beta|rc)\.([1-9][0-9]*))?$')
COMPATIBILITY = {'schema', 'configurationApi', 'pluginApi', 'minUpdater', 'architectures', 'nixos'}


class EndpointNotFound(Failure):
    """An HTTP 404, distinguished from rate limits and network failures."""


class NoPublishedRelease(Failure):
    """No release has been published for this channel yet."""


def version(value):
    match = SEMVER.fullmatch(value) if isinstance(value, str) else None
    if not match:
        raise Failure('Invalid semantic release version')
    a, b, c, pre, number = match.groups()
    return int(a), int(b), int(c), {'beta': 0, 'rc': 1, None: 2}[pre], int(number or 0)


def https(url, hosts):
    p = urllib.parse.urlsplit(url)
    if p.scheme != 'https' or p.hostname not in hosts or p.username or p.password or p.fragment:
        raise Failure('Release URL is outside the trusted GitHub endpoints')
    return url


class Fetcher:
    def __init__(self, cache):
        self.cache = Path(cache)
        self.cache.mkdir(parents=True, exist_ok=True)

    def get(self, url, limit=2 * 1024 * 1024, accept='application/vnd.github+json'):
        https(url, HOSTS)
        name = hashlib.sha256((accept + ' ' + url).encode()).hexdigest()
        body, meta = self.cache / name, self.cache / (name + '.json')
        old = read(meta, {})
        headers = {'User-Agent': 'CybexOS-updater/1', 'Accept': accept, 'X-GitHub-Api-Version': '2022-11-28'}
        if old.get('etag') and body.exists():
            # GitHub does not count a 304 against the anonymous rate limit.
            headers['If-None-Match'] = old['etag']
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
                https(response.url, HOSTS)
                data = response.read(limit + 1)
                if len(data) > limit:
                    raise Failure('Release response exceeds its size limit')
                atomic(body, data)
                atomic(meta, {'etag': response.headers.get('ETag', '')})
                return data
        except urllib.error.HTTPError as error:
            if error.code == 304 and body.exists():
                return body.read_bytes()
            if error.code == 404:
                raise EndpointNotFound('Release endpoint unavailable (HTTP 404); its status is unknown.') from error
            if error.code in (403, 429):
                raise Failure('GitHub rate limit reached. Retry later; no account or token is required.') from error
            raise Failure(f'Release endpoint unavailable (HTTP {error.code}); its status is unknown.') from error
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
            raise Failure('Release endpoint unreachable; its status is unknown. Retry when connected.') from error


def discover(fetch, channel, installed):
    """The newest published release on a channel: its version, exact commit and notes.

    Stable is the newest release that is neither marked as a prerelease nor
    has a prerelease version; beta is the newest of all published releases.
    Drafts and tags that are not semantic versions are ignored.
    """
    if channel not in ('stable', 'beta'):
        raise Failure('Unknown release channel')
    try:
        listing = parse(fetch.get(f'{GITHUB_API}/releases?per_page=100'))
    except EndpointNotFound as error:
        raise Failure('The Cybex OS release repository is unavailable (HTTP 404).') from error
    if not isinstance(listing, list):
        raise Failure('Invalid release listing')
    eligible = []
    for item in listing:
        if not isinstance(item, dict) or item.get('draft') is not False:
            continue
        tag = item.get('tag_name')
        try:
            key = version(tag[1:]) if isinstance(tag, str) and tag.startswith('v') else None
        except Failure:
            key = None
        if key is None:
            continue
        if not isinstance(item.get('prerelease'), bool):
            raise Failure('Invalid release listing')
        if channel == 'stable' and (item['prerelease'] or '-' in tag):
            continue
        notes = item.get('body') if isinstance(item.get('body'), str) else ''
        eligible.append((key, tag, notes[:100000]))
    if not eligible:
        raise NoPublishedRelease('No Cybex OS release has been published for this channel yet.')
    key, tag, notes = max(eligible)
    if key < version(installed):
        raise Failure('Channel downgrade rejected. Use explicit generation rollback instead.')
    revision = fetch.get(f'{GITHUB_API}/commits/{urllib.parse.quote(tag)}', limit=64,
                         accept='application/vnd.github.sha').decode('ascii', 'replace').strip()
    if not re.fullmatch('[0-9a-f]{40}', revision):
        raise Failure('Release tag does not name an exact Git commit')
    return {'version': tag[1:], 'revision': revision, 'notes': notes}


def validate_source(version_text, compatibility, release, installed):
    """A release's own source declares its version and what it requires."""
    if not isinstance(version_text, str) or version_text.strip() != release['version']:
        raise Failure('Release tag and its VERSION file disagree')
    if not isinstance(compatibility, dict) or set(compatibility) != COMPATIBILITY:
        raise Failure('Unsupported or incomplete release compatibility metadata')
    for name in ('schema', 'configurationApi', 'pluginApi', 'minUpdater'):
        if type(compatibility[name]) is not int or compatibility[name] < 1:
            raise Failure('Invalid release API metadata type')
    for name in ('architectures', 'nixos'):
        if (not isinstance(compatibility[name], list) or not compatibility[name]
                or any(not isinstance(x, str) for x in compatibility[name])):
            raise Failure('Invalid supported platform metadata')
    if (compatibility['schema'] != 1 or compatibility['configurationApi'] != 1 or compatibility['pluginApi'] != 1
            or compatibility['minUpdater'] > API):
        raise Failure('Release requires a newer updater or incompatible configuration/plugin API')
    if installed['architecture'] not in compatibility['architectures'] or installed['nixos'] not in compatibility['nixos']:
        raise Failure('Release does not support this architecture or NixOS branch')
