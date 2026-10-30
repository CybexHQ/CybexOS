#!/usr/bin/env python3
"""Settings -> Appearance -> Pointer: the themes, their downloads, the choice.

usage: pointer.py list
       pointer.py download THEME
       pointer.py remove THEME
       pointer.py apply THEME SIZE [--explicit]

Each command prints one JSON object; `success` is false with an `error` when
it could not do what was asked, and a `detail` when a tool said why.

The catalogue (assets/pointers/catalogue.json) names the themes the gallery
offers. The bundled ones are part of every installation. The others are
downloaded on demand: the machine's configuration records each package's
exact store path at its own Nixpkgs (/etc/cybexos/pointers.json), and
`download` asks Nix to substitute that path from the configured binary cache,
which checks its signature, under a garbage-collector root in
~/.local/state/cybexos/pointer/roots. Nothing is compiled: a path the cache
does not have fails instead. The theme is then linked into
~/.local/share/icons, where every toolkit looks; a name already taken there is
the person's own and is left alone. `remove` takes the links and the root
away again, and Nix frees the space at its next collection.

Themes outside the catalogue on XCURSOR_PATH are listed too, as the person's
own ("yours", under their home) or another package's ("system"). Their
previews are drawn on first sight into ~/.cache/cybexos/pointer-previews.

`apply` gives Hyprland the pointer at once (hyprctl setcursor), sets GTK's
gsettings keys and the systemd/D-Bus activation environment, so applications
started later inherit it. With --explicit it also records the choice in
~/.local/state/cybexos/pointer/session.env, which cybexos-session reads at the
next login before Hyprland starts; without, that record goes and the
installation's own default applies again.
"""
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

import pointer_xcursor

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(HERE), 'assets', 'pointers')
MACHINE = os.environ.get('CYBEXOS_POINTER_MACHINE', '/etc/cybexos/pointers.json')
FALLBACK_DEFAULT = {'theme': 'Bibata-Modern-Classic', 'size': 24}
STORE_PATH = re.compile(r'^/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+$')
PACKAGE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$')
MIN_SIZE, MAX_SIZE = 16, 128
MAX_EXTRA = 48
DOWNLOAD_TIMEOUT = 900
STEP_TIMEOUT = 15
SCHEMA = 'org.gnome.desktop.interface'


class PointerError(Exception):
    """A sentence for the person, and optionally the tool's own reason."""

    def __init__(self, message, detail=''):
        super().__init__(message)
        self.detail = detail


def home():
    return os.environ.get('HOME') or os.path.expanduser('~')


def state_dir():
    return os.path.join(os.environ.get('XDG_STATE_HOME') or os.path.join(home(), '.local/state'),
                        'cybexos', 'pointer')


def icons_dir():
    return os.path.join(os.environ.get('XDG_DATA_HOME') or os.path.join(home(), '.local/share'), 'icons')


def cache_dir():
    return os.path.join(os.environ.get('XDG_CACHE_HOME') or os.path.join(home(), '.cache'),
                        'cybexos', 'pointer-previews')


def roots_dir():
    return os.path.join(state_dir(), 'roots')


def read_json(path, limit=1 << 20):
    try:
        with open(path, encoding='utf-8') as handle:
            return json.loads(handle.read(limit))
    except (OSError, ValueError):
        return None


def catalogue():
    data = read_json(os.path.join(ASSETS, 'catalogue.json')) or {}
    themes = []
    for theme in data.get('themes', []):
        if (isinstance(theme, dict) and pointer_xcursor.valid_name(theme.get('id'))
                and isinstance(theme.get('name'), str) and PACKAGE.match(str(theme.get('package', '')))):
            left = theme.get('left')
            themes.append({'id': theme['id'], 'name': theme['name'], 'package': theme['package'],
                           'bundled': theme.get('bundled') is True,
                           'left': left if pointer_xcursor.valid_name(left) else None})
    return themes


def machine():
    """The installation's default pointer and its downloadable store paths."""
    data = read_json(MACHINE)
    if not isinstance(data, dict):
        return dict(FALLBACK_DEFAULT), {}, False
    default = data.get('default') if isinstance(data.get('default'), dict) else {}
    theme = default.get('theme') if pointer_xcursor.valid_name(default.get('theme')) else FALLBACK_DEFAULT['theme']
    size = default.get('size')
    size = int(size) if str(size).isdigit() and MIN_SIZE <= int(size) <= MAX_SIZE else FALLBACK_DEFAULT['size']
    downloads = {package: path for package, path in (data.get('downloads') or {}).items()
                 if isinstance(package, str) and PACKAGE.match(package)
                 and isinstance(path, str) and STORE_PATH.match(path)}
    return {'theme': theme, 'size': size}, downloads, True


def root_name(package):
    return re.sub(r'[^A-Za-z0-9._-]', '-', package)


def managed(name):
    """Whether ~/.local/share/icons/NAME is this helper's link to a download."""
    path = os.path.join(icons_dir(), name)
    if not os.path.islink(path):
        return False
    target = os.readlink(path)
    return os.path.isabs(target) and os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(target)))) == roots_dir()


def installed(name, dirs):
    directory = pointer_xcursor.theme_dir(name, dirs)
    return directory is not None and pointer_xcursor.has_cursors(directory)


def catalogue_previews():
    index = (read_json(os.path.join(ASSETS, 'previews', 'index.json')) or {}).get('themes', {})
    return index if isinstance(index, dict) else {}


def preview_entry(directory, meta):
    shapes = [shape for shape in meta.get('shapes', []) if shape in pointer_xcursor.SHAPES]
    return {
        'previews': {shape: os.path.join(directory, shape + '.png') for shape in shapes},
        'busyFrames': int(meta.get('busyFrames') or 1),
        'busyDuration': int(meta.get('busyDuration') or 0),
        'sizes': [int(size) for size in meta.get('sizes', []) if isinstance(size, int)],
    }


def extra_preview(name, directory, dirs):
    """Previews of a theme outside the catalogue, drawn once per change."""
    try:
        stamp = os.stat(os.path.join(directory, 'cursors')).st_mtime_ns
    except OSError:
        stamp = 0
    key = hashlib.sha256(f'{os.path.realpath(directory)}\0{stamp}'.encode()).hexdigest()[:16]
    base = cache_dir()
    target = os.path.join(base, f'{name}-{key}')
    meta = read_json(os.path.join(target, 'meta.json'))
    if not isinstance(meta, dict):
        try:
            for stale in os.listdir(base):
                if stale.startswith(name + '-') and stale != os.path.basename(target):
                    shutil.rmtree(os.path.join(base, stale), ignore_errors=True)
        except OSError:
            pass
        try:
            meta = pointer_xcursor.render(name, dirs, target)
        except (pointer_xcursor.CursorError, OSError):
            meta = {'shapes': []}
        try:
            with open(os.path.join(target, 'meta.json'), 'w', encoding='utf-8') as handle:
                json.dump(meta, handle)
        except OSError:
            pass
    return preview_entry(target, meta)


def list_themes():
    default, downloads, configured = machine()
    dirs = pointer_xcursor.search_path()
    previews = catalogue_previews()
    themes, known = [], set()
    for theme in catalogue():
        known.update(filter(None, (theme['id'], theme['left'])))
        downloadable = not theme['bundled'] and theme['package'] in downloads
        entry = {
            'id': theme['id'], 'name': theme['name'], 'package': theme['package'],
            'source': 'bundled' if theme['bundled'] else 'download',
            'installed': installed(theme['id'], dirs),
            'downloadable': downloadable,
            'removable': not theme['bundled'] and managed(theme['id']),
            'left': theme['left'],
            'leftInstalled': bool(theme['left']) and installed(theme['left'], dirs),
        }
        entry.update(preview_entry(os.path.join(ASSETS, 'previews', theme['id']), previews.get(theme['id'], {})))
        themes.append(entry)
    extras, user_home = [], home().rstrip('/') + '/'
    for base in dirs:
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for name in names:
            if len(extras) >= MAX_EXTRA:
                break
            if name in known or name == 'default' or not pointer_xcursor.valid_name(name):
                continue
            directory = os.path.join(base, name)
            if not pointer_xcursor.has_cursors(directory):
                continue
            known.add(name)
            entry = {
                'id': name, 'name': pointer_xcursor.index_value(directory, 'Name')[:64] or name,
                'package': None, 'source': 'yours' if directory.startswith(user_home) else 'system',
                'installed': True, 'downloadable': False, 'removable': False,
                'left': None, 'leftInstalled': False,
            }
            entry.update(extra_preview(name, directory, dirs))
            extras.append(entry)
    return {'success': True, 'v': 1, 'default': default, 'downloads': configured, 'themes': themes + extras}


def catalogue_theme(name):
    theme = next((theme for theme in catalogue() if theme['id'] == name), None)
    if theme is None:
        raise PointerError(f'{name} is not in the pointer catalogue')
    return theme


def link(name, package):
    """Points ~/.local/share/icons/NAME at the download, unless the name is taken."""
    source = os.path.join(roots_dir(), root_name(package), 'share', 'icons', name)
    if not os.path.isdir(source):
        return
    target = os.path.join(icons_dir(), name)
    if os.path.lexists(target) and not managed(name):
        return
    os.makedirs(icons_dir(), exist_ok=True)
    temporary = os.path.join(icons_dir(), f'.{name}.cybexos-pointer')
    if os.path.lexists(temporary):
        os.unlink(temporary)
    os.symlink(source, temporary)
    os.replace(temporary, target)


def nix_store():
    return shutil.which('nix-store') or '/run/current-system/sw/bin/nix-store'


def download(name):
    theme = catalogue_theme(name)
    if theme['bundled']:
        return {'success': True}
    _default, downloads, _configured = machine()
    store = downloads.get(theme['package'])
    if store is None:
        raise PointerError(f"{theme['name']} cannot be downloaded on this computer")
    os.makedirs(roots_dir(), exist_ok=True)
    root = os.path.join(roots_dir(), root_name(theme['package']))
    try:
        result = subprocess.run([nix_store(), '--realise', store, '--add-root', root],
                                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=DOWNLOAD_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise PointerError(f"Downloading {theme['name']} took too long. Try again later.") from None
    except OSError as error:
        raise PointerError(f"Could not download {theme['name']}", f'nix-store: {error.strerror}') from None
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]
        raise PointerError(f"Could not download {theme['name']}. Check the internet connection and try again.",
                           (lines[-1] if lines else f'nix-store exited with {result.returncode}')[:300])
    if not os.path.isdir(os.path.join(store, 'share', 'icons', name, 'cursors')):
        raise PointerError(f"The download has no {theme['name']} pointer")
    for other in catalogue():
        if other['package'] == theme['package']:
            for variant in filter(None, (other['id'], other['left'])):
                link(variant, theme['package'])
    return {'success': True}


def remove(name):
    theme = catalogue_theme(name)
    if theme['bundled']:
        raise PointerError(f"{theme['name']} is part of Cybex OS")
    for other in catalogue():
        if other['package'] == theme['package']:
            for variant in filter(None, (other['id'], other['left'])):
                if managed(variant):
                    os.unlink(os.path.join(icons_dir(), variant))
    root = os.path.join(roots_dir(), root_name(theme['package']))
    if os.path.islink(root):
        os.unlink(root)
    return {'success': True}


def run_step(command):
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=STEP_TIMEOUT)
    except subprocess.TimeoutExpired:
        return f'{command[0]} timed out'
    except OSError as error:
        return f'could not run {command[0]}: {error.strerror}'
    if result.returncode != 0:
        lines = (result.stderr or result.stdout).strip().splitlines()
        return (lines[-1] if lines else f'{command[0]} exited with {result.returncode}')[:300]
    return None


def write_session(theme, size, explicit):
    path = os.path.join(state_dir(), 'session.env')
    if not explicit:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        return
    os.makedirs(state_dir(), exist_ok=True)
    with open(path + '.part', 'w', encoding='utf-8') as handle:
        handle.write(f'XCURSOR_THEME={theme}\nXCURSOR_SIZE={size}\n')
    os.replace(path + '.part', path)


def apply(theme, size, explicit):
    if not pointer_xcursor.valid_name(theme):
        raise PointerError('not a pointer theme name')
    if not size.isdigit() or not MIN_SIZE <= int(size) <= MAX_SIZE:
        raise PointerError(f'the size must be {MIN_SIZE} to {MAX_SIZE}')
    if not installed(theme, pointer_xcursor.search_path()):
        raise PointerError(f'{theme} is not installed')
    steps = {}
    if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        steps['hyprland'] = run_step(['hyprctl', 'setcursor', theme, size])
    if shutil.which('gsettings'):
        steps['gsettings'] = (run_step(['gsettings', 'set', SCHEMA, 'cursor-theme', theme])
                              or run_step(['gsettings', 'set', SCHEMA, 'cursor-size', size]))
    variables = [f'XCURSOR_THEME={theme}', f'XCURSOR_SIZE={size}']
    if shutil.which('dbus-update-activation-environment'):
        steps['environment'] = run_step(['dbus-update-activation-environment', '--systemd'] + variables)
    elif shutil.which('systemctl'):
        steps['environment'] = run_step(['systemctl', '--user', 'set-environment'] + variables)
    try:
        write_session(theme, size, explicit)
        steps['session'] = None
    except OSError as error:
        steps['session'] = f'could not record the pointer for the next login: {error.strerror}'
    failed = [f'{step}: {error}' for step, error in steps.items() if error]
    report = {'success': not failed, 'steps': {step: error or 'ok' for step, error in steps.items()}}
    if failed:
        report['error'] = '; '.join(failed)
    return report


def main(argv):
    command, arguments = (argv[1], argv[2:]) if len(argv) > 1 else ('', [])
    try:
        if command == 'list' and not arguments:
            report = list_themes()
        elif command in ('download', 'remove') and len(arguments) == 1:
            os.makedirs(state_dir(), exist_ok=True)
            with open(os.path.join(state_dir(), '.lock'), 'w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                report = (download if command == 'download' else remove)(arguments[0])
        elif command == 'apply' and len(arguments) in (2, 3) and arguments[2:] in ([], ['--explicit']):
            report = apply(arguments[0], arguments[1], arguments[2:] == ['--explicit'])
        else:
            print(json.dumps({'success': False, 'error': __doc__.split('\n\n')[1].strip()}))
            return 2
    except PointerError as error:
        report = {'success': False, 'error': str(error)}
        if error.detail:
            report['detail'] = error.detail
    except OSError as error:
        report = {'success': False, 'error': f'{error.strerror}: {error.filename}'}
    print(json.dumps(report))
    return 0 if report.get('success') else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
