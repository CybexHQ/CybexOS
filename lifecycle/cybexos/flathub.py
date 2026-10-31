"""Flathub apps for one account: search, app pages, install, update, remove.

NixOS packages are Software's first source: part of the system, staged and
rolled back with it. Flathub is the second: sandboxed Flatpak apps installed
for this account only (`flatpak --user`), right away, without authorization or
a restart. They live in ~/.local/share/flatpak, outside system generations,
and update separately, from Software's Updates tab.

Metadata comes from Flathub's public API when someone searches or opens an
app's page. It is untrusted: fields are type-checked, descriptions reduced to
plain paragraphs, and media URLs must be https on dl.flathub.org. The remote
itself is added from the copy of Flathub's repository file that ships here
(signing key 6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE), never
downloaded. Installs, updates and removals run in a transient user service,
so closing Software or restarting the shell does not interrupt them.
"""
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.request
import uuid

from .common import CommandFailure, Failure, Runner, atomic, locked, read

API = 'https://flathub.org/api/v2/'
REMOTE = 'flathub'
REPOSITORY = Path(__file__).with_name('flathub.flatpakrepo')
PROPRIETARY = Path('/etc/cybexos/proprietary-enabled')
ENABLED = Path('/etc/cybexos/flathub-enabled')
# Flatpak application IDs: reverse-DNS, at least three elements.
APP_ID = re.compile(r'[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+){2,}')
TASK_ID = re.compile(r'[a-f0-9]{32}')
MEDIA = re.compile(r'https://dl\.flathub\.org/media/[A-Za-z0-9._~/@%+-]+\.(?:png|jpe?g|webp|svg)')
HOMEPAGE = re.compile(r'https://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/[^\s"<>]*)?')
COLOUR = re.compile(r'#[0-9a-fA-F]{6}')
UNREACHABLE = "Flathub couldn't be reached. Check your internet connection and try again."
ACTIONS = ('install', 'remove', 'update')
SEARCH_LIMIT = 48
# Exported icon sizes, largest useful first.
ICON_SIZES = ('128x128', 'scalable', '256x256', '512x512', '64x64', '48x48')


def valid_id(value):
    return isinstance(value, str) and len(value) <= 255 and APP_ID.fullmatch(value) is not None


def app_ids(values, *, allow_empty=False):
    values = list(values or [])
    if (not allow_empty and not values) or len(values) > 64 or len(set(values)) != len(values) \
            or not all(valid_id(value) for value in values):
        raise Failure('Choose up to 64 distinct Flathub app IDs.')
    return values


def proprietary_allowed(path=PROPRIETARY):
    return Path(path).exists()


def enabled(path=ENABLED):
    """`cybexos.features.flathub`: whether Software offers Flathub here."""
    return Path(path).exists()


def architecture():
    machine = platform.machine()
    return {'amd64': 'x86_64', 'arm64': 'aarch64'}.get(machine, machine)


def state_directory(state=None):
    path = Path(state or (Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'cybexos/software'))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


# ---- Flathub's API ----------------------------------------------------------

def fetch(url, body=None, limit=2 * 1024 * 1024):
    """A JSON document from Flathub's API; None when it has no such entry."""
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, headers={
        'User-Agent': 'cybexos-software/1', 'Accept': 'application/json',
        **({'Content-Type': 'application/json'} if data is not None else {})})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read(limit + 1)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise Failure(UNREACHABLE) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise Failure(UNREACHABLE) from None
    if len(raw) > limit:
        raise Failure('Flathub returned an unexpectedly large answer.')
    try:
        return json.loads(raw)
    except ValueError:
        raise Failure('Flathub returned an invalid answer. Try again later.') from None


def text(value, limit):
    return re.sub(r'\s+', ' ', html.unescape(value)).strip()[:limit] if isinstance(value, str) else ''


def media(url):
    return url if isinstance(url, str) and MEDIA.fullmatch(url) else ''


class Paragraphs(HTMLParser):
    """AppStream description markup reduced to paragraphs and list items."""
    def __init__(self):
        super().__init__()
        self.blocks, self.current, self.item = [], [], False

    def flush(self):
        value = re.sub(r'\s+', ' ', ''.join(self.current)).strip()
        if value:
            self.blocks.append(('• ' if self.item else '') + value)
        self.current = []

    def handle_starttag(self, tag, attrs):
        if tag in ('p', 'li'):
            self.flush()
            self.item = tag == 'li'

    def handle_endtag(self, tag):
        if tag in ('p', 'li', 'ul', 'ol'):
            self.flush()
            self.item = False

    def handle_data(self, data):
        self.current.append(data)


def description(markup):
    """Paragraphs for the app page; Flathub's own packaging notes stay in."""
    if not isinstance(markup, str):
        return []
    parser = Paragraphs()
    parser.feed(markup)
    parser.close()
    parser.flush()
    blocks, size = [], 0
    for block in parser.blocks:
        block = html.unescape(block)[:600]
        if size + len(block) > 2400:
            break
        blocks.append(block)
        size += len(block)
    return blocks


def screenshots(data):
    result = []
    shots = data.get('screenshots') if isinstance(data.get('screenshots'), list) else []
    for shot in shots:
        sizes = shot.get('sizes') if isinstance(shot, dict) and isinstance(shot.get('sizes'), list) else []
        sizes = [size for size in sizes if isinstance(size, dict) and media(size.get('src'))]
        preferred = [size['src'] for size in sizes if size.get('width') in ('752', '1248')] or [size['src'] for size in sizes]
        if preferred:
            result.append(preferred[0])
    return result[:6]


def brand(data):
    result = {}
    branding = data.get('branding')
    for entry in branding if isinstance(branding, list) else []:
        if (isinstance(entry, dict) and entry.get('type') == 'primary' and isinstance(entry.get('value'), str)
                and COLOUR.fullmatch(entry['value']) and entry.get('scheme_preference') in ('light', 'dark')):
            result[entry['scheme_preference']] = entry['value']
    return result


def permissions(metadata):
    """The sandbox holes worth showing before an install, as stable keys."""
    granted = (metadata or {}).get('permissions') if isinstance(metadata, dict) else None
    if not isinstance(granted, dict):
        return []
    filesystems = [value for value in granted.get('filesystems') or [] if isinstance(value, str)] \
        if isinstance(granted.get('filesystems'), list) else []
    listed = lambda key: [value for value in granted.get(key) or [] if isinstance(value, str)] \
        if isinstance(granted.get(key), list) else []
    result = []
    if any(value.split(':')[0] in ('host', 'host-os', 'host-etc') for value in filesystems):
        result.append('files-all')
    elif any(value.split(':')[0] in ('home', '~') for value in filesystems):
        result.append('files-home')
    elif filesystems:
        result.append('files-some')
    if 'network' in listed('shared'):
        result.append('network')
    if 'all' in listed('devices'):
        result.append('devices')
    if any(value in ('x11', 'fallback-x11') for value in listed('sockets')) and 'wayland' not in listed('sockets'):
        result.append('x11')
    talk = granted.get('session-bus', {}).get('talk') if isinstance(granted.get('session-bus'), dict) else None
    if isinstance(talk, list) and 'org.freedesktop.Flatpak' in talk:
        result.append('host-commands')
    return result


def hit(row, allowed):
    """One search result, or None for what this computer cannot run."""
    if not isinstance(row, dict) or not valid_id(row.get('app_id')) or row.get('type') != 'desktop-application':
        return None
    arches = row.get('arches')
    if isinstance(arches, list) and arches and architecture() not in arches:
        return None
    free = row.get('is_free_license') is True
    installs = row.get('installs_last_month')
    return {
        'id': row['app_id'], 'name': text(row.get('name'), 60) or row['app_id'],
        'summary': text(row.get('summary'), 160), 'developer': text(row.get('developer_name'), 80),
        'icon': media(row.get('icon')), 'license': text(row.get('project_license'), 120), 'free': free,
        'verified': row.get('verification_verified') is True,
        'installs': installs if isinstance(installs, int) and installs >= 0 else 0,
        'unavailable': '' if free or allowed else 'unfree',
    }


# ---- this account's Flatpak installation -------------------------------------

def exports(installation):
    if installation == 'user':
        return Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'flatpak/exports/share'
    return Path('/var/lib/flatpak/exports/share')


def icon_path(app_id, installation):
    base = exports(installation) / 'icons/hicolor'
    for size in ICON_SIZES:
        for suffix in ('.png', '.svg'):
            path = base / size / 'apps' / (app_id + suffix)
            if path.is_file():
                return str(path)
    return ''


def installed(run):
    """Flatpak apps in this account's and the system's installations."""
    try:
        output = run('flatpak', 'list', '--app', '--columns=application,name,version,branch,origin,installation',
                     timeout=60, sensitive=True)
    except (CommandFailure, OSError):
        return []
    rows, seen = [], set()
    for line in output.splitlines():
        fields = line.split('\t')
        if len(fields) < 6 or not valid_id(fields[0]) or fields[5] not in ('user', 'system'):
            continue
        key = (fields[0], fields[5])
        if key in seen:
            continue
        seen.add(key)
        desktop = exports(fields[5]) / 'applications' / (fields[0] + '.desktop')
        rows.append({'id': fields[0], 'name': text(fields[1], 60) or fields[0], 'version': text(fields[2], 64),
                     'branch': text(fields[3], 64), 'origin': text(fields[4], 64), 'installation': fields[5],
                     'icon': icon_path(fields[0], fields[5]), 'desktop': desktop.is_file()})
    return sorted(rows, key=lambda row: (row['name'].casefold(), row['installation']))


def has_remote(run):
    try:
        output = run('flatpak', 'remotes', '--user', '--columns=name', timeout=30, sensitive=True)
    except (CommandFailure, OSError):
        return False
    return REMOTE in [line.strip() for line in output.splitlines()]


def ensure_remote(run):
    """Flathub for this account, from the shipped repository file.

    An existing `flathub` remote is the person's own and is left as it is.
    """
    run('flatpak', 'remote-add', '--user', '--if-not-exists', REMOTE, str(REPOSITORY), timeout=60, sensitive=True)


def available():
    return shutil.which('flatpak') is not None


# ---- what Software asks ------------------------------------------------------

def search(query, *, run=None, get=None, allowed=None):
    if not isinstance(query, str) or len(query) > 200:
        raise Failure('Search is limited to 200 characters.')
    wanted = query.strip()
    allowed = proprietary_allowed() if allowed is None else allowed
    if wanted == '':
        return {'query': '', 'total': 0, 'results': [], 'proprietary': allowed}
    data = (get or fetch)(API + 'search', {'query': wanted, 'hits_per_page': SEARCH_LIMIT, 'page': 1})
    if not isinstance(data, dict) or not isinstance(data.get('hits'), list):
        raise Failure('Flathub returned an invalid answer. Try again later.')
    mine = {row['id'] for row in installed(run or Runner())}
    results = []
    for row in data['hits']:
        value = hit(row, allowed)
        if value:
            results.append(value | {'installed': value['id'] in mine})
    total = data.get('totalHits')
    return {'query': wanted, 'total': total if isinstance(total, int) and total >= 0 else len(results),
            'results': results[:SEARCH_LIMIT], 'proprietary': allowed}


def details(app_id, *, run=None, get=None, allowed=None):
    """Everything an app page shows, from Flathub, plus what is installed here."""
    if not valid_id(app_id):
        raise Failure('Invalid Flathub app ID.')
    get = get or fetch
    allowed = proprietary_allowed() if allowed is None else allowed
    data = get(API + 'appstream/' + app_id)
    if data is None:
        raise Failure("Flathub doesn't have this app.")
    if not isinstance(data, dict) or data.get('id') != app_id:
        raise Failure('Flathub returned an invalid answer. Try again later.')
    summary = get(API + 'summary/' + app_id) or {}
    summary = summary if isinstance(summary, dict) else {}
    try:
        verification = get(API + 'verification/' + app_id + '/status') or {}
    except Failure:
        verification = {}
    releases = data.get('releases') if isinstance(data.get('releases'), list) else []
    release = next((row for row in releases if isinstance(row, dict) and isinstance(row.get('version'), str)), {})
    urls = data.get('urls') if isinstance(data.get('urls'), dict) else {}
    homepage = urls.get('homepage') if isinstance(urls.get('homepage'), str) and HOMEPAGE.fullmatch(urls['homepage']) else ''
    arches = summary.get('arches')
    metadata = summary.get('metadata') if isinstance(summary.get('metadata'), dict) else {}
    size = lambda value: value if isinstance(value, int) and value >= 0 else 0
    free = data.get('is_free_license') is True
    here = [row for row in installed(run or Runner()) if row['id'] == app_id]
    return {
        'id': app_id, 'name': text(data.get('name'), 60) or app_id, 'summary': text(data.get('summary'), 160),
        'description': description(data.get('description')), 'developer': text(data.get('developer_name'), 80),
        'license': text(data.get('project_license'), 120), 'free': free, 'icon': media(data.get('icon')),
        'screenshots': screenshots(data), 'brand': brand(data), 'homepage': homepage,
        'version': text(release.get('version'), 64), 'verified': isinstance(verification, dict) and verification.get('verified') is True,
        'downloadBytes': size(summary.get('download_size')), 'installedBytes': size(summary.get('installed_size')),
        'runtime': text(metadata.get('runtimeName') or metadata.get('runtime'), 80),
        'permissions': permissions(metadata), 'eol': data.get('is_eol') is True,
        'supported': not isinstance(arches, list) or not arches or architecture() in arches,
        'unavailable': '' if free or allowed else 'unfree',
        'installed': here[0] if here else None,
    }


def updates(*, run=None):
    """This account's Flathub apps with a newer version (contacts Flathub)."""
    run = run or Runner()
    mine = {row['id']: row for row in installed(run) if row['installation'] == 'user'}
    if not mine:
        return {'updates': []}
    try:
        output = run('flatpak', 'remote-ls', '--user', '--updates', '--app', '--columns=application,version',
                     timeout=120, sensitive=True)
    except CommandFailure:
        raise Failure(UNREACHABLE) from None
    rows = []
    for line in output.splitlines():
        fields = line.split('\t')
        if fields and fields[0] in mine:
            current = mine[fields[0]]
            rows.append({'id': current['id'], 'name': current['name'], 'icon': current['icon'],
                         'before': current['version'], 'after': text(fields[1], 64) if len(fields) > 1 else ''})
    return {'updates': sorted(rows, key=lambda row: row['name'].casefold())}


# ---- changes, run as a transient user service ---------------------------------

def task_path(state=None):
    return state_directory(state) / 'flathub-task.json'


def unit_active(unit):
    try:
        result = subprocess.run(['systemctl', '--user', 'is-active', unit], text=True, capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() in ('active', 'activating', 'reloading')


def current_task(state=None, *, active=unit_active):
    """The latest change, with a worker that died before reporting marked failed."""
    task = read(task_path(state))
    if not isinstance(task, dict) or task.get('schema') != 1:
        return None
    if task.get('state') in ('queued', 'running') and time.time() - float(task.get('updatedAt', 0) or 0) > 10:
        if active(task.get('unit', '')) is False:
            task = task | {'state': 'failed', 'error': 'The change stopped before it finished. Try again.'}
    return {key: task.get(key) for key in ('id', 'action', 'ids', 'names', 'state', 'error', 'createdAt', 'finishedAt')}


def status(*, run=None, state=None, allowed=None, active=unit_active, present=None, on=None):
    """What Software shows without contacting Flathub."""
    run = run or Runner()
    present = available() if present is None else present
    return {'schema': 1, 'enabled': enabled() if on is None else on, 'available': present,
            'remote': has_remote(run) if present else False,
            'proprietary': proprietary_allowed() if allowed is None else allowed,
            'task': current_task(state, active=active),
            'installed': installed(run) if present else []}


def cybex():
    return shutil.which('cybex') or '/run/current-system/sw/bin/cybex'


def start(action, ids, *, names=None, run=None, state=None, get=None, allowed=None, spawn=subprocess.run,
          active=unit_active, on=None):
    """Begin an install, update or removal; returns its task ID at once."""
    if action not in ACTIONS:
        raise Failure('Invalid Flathub action.')
    if action != 'remove' and not (enabled() if on is None else on):
        raise Failure('Flathub is turned off on this computer.')
    ids = app_ids(ids, allow_empty=action == 'update')
    names = names if isinstance(names, dict) else {}
    allowed = proprietary_allowed() if allowed is None else allowed
    if action == 'install' and not allowed:
        for app_id in ids:
            data = (get or fetch)(API + 'appstream/' + app_id)
            if not isinstance(data, dict) or data.get('is_free_license') is not True:
                raise Failure('Proprietary apps are turned off on this computer.')
    path = task_path(state)
    with locked(path.with_suffix('.lock')):
        previous = current_task(state, active=active)
        if previous and previous['state'] in ('queued', 'running'):
            raise Failure('Software is already changing a Flathub app. Wait for it to finish.')
        identifier = uuid.uuid4().hex
        unit = f'cybexos-flathub-{identifier}.service'
        now = time.time()
        atomic(path, {'schema': 1, 'id': identifier, 'action': action, 'ids': ids,
                      'names': {key: text(value, 60) for key, value in names.items() if key in ids and isinstance(value, str)},
                      'state': 'queued', 'error': '', 'unit': unit, 'createdAt': now, 'updatedAt': now})
    try:
        # The worker sees the caller's programs, flatpak included; a user
        # manager's own PATH need not contain the system profile.
        spawn(['systemd-run', '--user', '--collect', '--quiet', '--unit', unit,
               '--description', 'Cybex OS Software: Flathub ' + action,
               '--setenv', 'PATH=' + os.environ.get('PATH', '/run/current-system/sw/bin'),
               cybex(), 'software', 'flathub', 'run', identifier], check=True, timeout=30,
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        task = read(path) or {}
        atomic(path, task | {'state': 'failed', 'error': "Software couldn't start the change. Try again.",
                             'updatedAt': time.time(), 'finishedAt': time.time()})
        raise Failure("Software couldn't start the change. Try again.") from None
    return {'accepted': True, 'task': identifier}


def explain(action, output):
    """A plain reason for a failed Flatpak command; its output stays private."""
    lowered = (output or '').lower()
    if any(sign in lowered for sign in ('could not resolve', "couldn't resolve", 'timeout was reached',
                                        'could not connect', 'failed to connect', 'network is unreachable')):
        return UNREACHABLE
    if 'no space left' in lowered or 'not enough disk space' in lowered:
        return "There isn't enough free disk space. Free some space and try again."
    if 'no remote refs found' in lowered or 'nothing matches' in lowered or 'unable to find' in lowered:
        return "Flathub doesn't offer this app for this computer."
    return {'install': "Flathub couldn't install the app. Try again.",
            'remove': "The app couldn't be removed. Try again.",
            'update': "Flathub couldn't update your apps. Try again."}[action]


def work(identifier, *, run=None, state=None):
    """The transient service's body: one Flatpak transaction, then a record."""
    if not TASK_ID.fullmatch(identifier or ''):
        raise Failure('Invalid Flathub task.')
    path = task_path(state)
    log = state_directory(state) / 'flathub.log'
    with locked(path.with_suffix('.run.lock')):
        task = read(path)
        if not isinstance(task, dict) or task.get('id') != identifier or task.get('state') != 'queued':
            raise Failure('This Flathub change is not waiting to run.')
        action, ids = task['action'], app_ids(task.get('ids'), allow_empty=task.get('action') == 'update')
        atomic(path, task | {'state': 'running', 'updatedAt': time.time()})
        if log.exists() and log.stat().st_size > 1024 * 1024:
            log.unlink()
        run = run or Runner(log=log)
        try:
            if action in ('install', 'update'):
                ensure_remote(run)
            if action == 'install':
                run('flatpak', 'install', '--user', '--noninteractive', '-y', '--or-update', REMOTE, *ids, timeout=7200)
            elif action == 'update':
                run('flatpak', 'update', '--user', '--noninteractive', '-y', *ids, timeout=7200)
            else:
                try:
                    run('flatpak', 'uninstall', '--user', '--noninteractive', '-y', *ids, timeout=600)
                except CommandFailure as error:
                    # Already gone: what was asked for is true.
                    lowered = (error.output or '').lower()
                    if 'not installed' not in lowered and 'no installed refs' not in lowered:
                        raise
                # Runtimes nothing uses any more; their removal is housekeeping.
                try:
                    run('flatpak', 'uninstall', '--user', '--unused', '--noninteractive', '-y', timeout=600)
                except CommandFailure:
                    pass
        except CommandFailure as error:
            result = {'state': 'failed', 'error': explain(action, error.output)}
        except Failure as error:
            result = {'state': 'failed', 'error': str(error)}
        else:
            result = {'state': 'done', 'error': ''}
        now = time.time()
        atomic(path, (read(path) or task) | result | {'updatedAt': now, 'finishedAt': now})
    return result
