"""Native package choices in the machine's single, locked package universe.

Software installs prebuilt packages only. `catalogue` merges the app
catalogue shipped with Cybex OS with this machine's state; `check` asks Nix,
without building anything, whether chosen packages would compile here.
"""
import hashlib
import json
import os
from pathlib import Path
import re

from . import prebuilt
from .common import CommandFailure, Failure, Runner, atomic, locked, parse, read

ATTRIBUTE = re.compile(r'[A-Za-z0-9_][A-Za-z0-9_+-]*(?:\.[A-Za-z0-9_][A-Za-z0-9_+-]*)*')
APP_ID = re.compile(r'[a-z0-9]{2,32}')
DESKTOP_ID = re.compile(r'[A-Za-z0-9_@.+-]{1,200}\.desktop')
STORE_PATH = re.compile(r'/nix/store/[a-z0-9]{32}-[^/]+')
# Follows the selected system generation, like the shell's own runtime.
SHIPPED = Path('/run/current-system/sw/share/cybexos/software')
EXPRESSION = Path(__file__).with_name('software-catalogue.nix')
CHECK_LIMIT = 64
# Who put a package on this computer. Software's own choices can be removed
# there; Cybex OS's (and the NixOS modules it enables) and personal modules'
# stay with their owners.
OWNERS = ('cybexos', 'personal', 'software')


def packages(value):
    if (not isinstance(value, list) or len(value) > 512
            or any(not isinstance(p, str) or len(p) > 200 or not ATTRIBUTE.fullmatch(p) for p in value)
            or len(set(value)) != len(value)):
        raise Failure('Choose up to 512 distinct package attributes from the catalogue.')
    return sorted(value)


def document(config):
    path = Path(config) / 'local/software.json'
    value = read(path)
    if (path.is_symlink() or not isinstance(value, dict) or set(value) != {'schema', 'packages'}
            or value['schema'] != 1):
        raise Failure('The machine-owned local/software.json declaration is missing or unsupported. Preserve personal modules.')
    return {'schema': 1, 'packages': packages(value['packages'])}


def prepare(config, request):
    if not isinstance(request, dict) or set(request) != {'packages', 'previous'}:
        raise Failure('Invalid software request')
    current = document(config)
    if packages(request['previous']) != current['packages']:
        raise Failure('Package choices changed. Refresh Software before previewing again.')
    wanted = packages(request['packages'])
    atomic(Path(config) / 'local/software.json', {'schema': 1, 'packages': wanted}, 0o644)
    return {'packages': wanted, 'previous': current['packages']}


def inventory(path='/etc/cybexos/software.json', config='/etc/nixos'):
    result = read(path)
    if not isinstance(result, dict) or result.get('schema') != 1:
        raise Failure('The installed software inventory is unavailable.')
    desired = document(config)['packages']
    return result | {'desired': desired, 'configurationChanged': desired != result['selected']}


def owner(package):
    """Who installed an inventory package; read-only owners win.

    Older inventories have no `origins`: anything declared outside Software
    is reported as Cybex OS's, which is equally read-only here.
    """
    origins = package.get('origins')
    if not isinstance(origins, list):
        origins = (['software'] if package.get('attributes') else []) + (['cybexos'] if package.get('managedElsewhere') else [])
    if 'cybexos' in origins or 'nixos' in origins:
        return 'cybexos'
    if 'personal' in origins:
        return 'personal'
    return 'software' if 'software' in origins or package.get('attributes') else 'cybexos'


def desktop_entries(path, limit=24):
    """Visible application entries a package installs: id, name and icon."""
    if not isinstance(path, str) or not STORE_PATH.fullmatch(path):
        return []
    try:
        files = sorted(Path(path, 'share', 'applications').glob('*.desktop'))[:64]
    except OSError:
        return []
    entries = []
    for file in files:
        if not DESKTOP_ID.fullmatch(file.name):
            continue
        try:
            text = file.read_text(errors='replace')[:65536]
        except OSError:
            continue
        section, values = None, {}
        for line in text.splitlines():
            line = line.strip()
            if line.startswith('['):
                section = line
            elif section == '[Desktop Entry]' and '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                values.setdefault(key.strip(), value.strip())
        if (values.get('Type') == 'Application' and values.get('Name')
                and values.get('NoDisplay', '').lower() != 'true' and values.get('Hidden', '').lower() != 'true'):
            entries.append({'id': file.name, 'name': values['Name'][:128], 'icon': values.get('Icon', '')[:512]})
        if len(entries) >= limit:
            break
    return entries


def cache_directory(cache=None):
    path = Path(cache or (Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'cybexos/software'))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def evaluate(run, config, attributes, *, derivations=False):
    """Offline metadata for validated attributes in the machine's own packages."""
    if any(not ATTRIBUTE.fullmatch(attribute) for attribute in attributes):
        raise Failure('Invalid package attribute')
    expression = ('import (builtins.toPath ' + json.dumps(str(EXPRESSION)) + ') { machine = '
                  + json.dumps('path:' + str(config)) + '; attributes = [ '
                  + ' '.join(json.dumps(attribute) for attribute in attributes) + ' ]; derivations = '
                  + ('true' if derivations else 'false') + '; }')
    try:
        data = parse(run('nix', 'eval', '--json', '--offline', '--no-update-lock-file',
                         '--impure', '--expr', expression, timeout=600, sensitive=True))
    except CommandFailure:
        raise Failure("Software couldn't read this computer's package set. Check your configuration and refresh.") from None
    if (not isinstance(data, dict) or not isinstance(data.get('packages'), list)
            or not isinstance(data.get('allowUnfree'), bool)):
        raise Failure('Nix returned invalid package metadata.')
    rows = {}
    for meta in data['packages']:
        if not isinstance(meta, dict) or meta.get('attribute') not in attributes:
            continue
        drv = meta.get('drvPath')
        rows[meta['attribute']] = {
            'exists': meta.get('exists') is True,
            'pname': str(meta.get('pname', ''))[:200],
            'version': str(meta.get('version', ''))[:128],
            'unfree': meta.get('unfree') is True,
            'available': meta.get('exists') is True and meta.get('available') is not False,
            'broken': meta.get('broken') is True,
            'drvPath': drv if isinstance(drv, str) and STORE_PATH.fullmatch(drv) and drv.endswith('.drv') else None,
        }
    return {'allowUnfree': data['allowUnfree'], 'packages': rows}


def unavailable(meta, allow_unfree):
    """Why a package cannot be installed here, or '' when it can."""
    if not meta or not meta['exists']:
        return 'missing'
    if meta['available']:
        return ''
    if meta['unfree'] and not allow_unfree:
        return 'unfree'
    return 'broken' if meta['broken'] else 'unsupported'


def shipped_catalogue(source):
    data = read(Path(source) / 'catalogue.json')
    if (not isinstance(data, dict) or data.get('schema') != 1
            or not all(isinstance(data.get(key), list) for key in ('categories', 'profiles', 'featured', 'apps'))):
        raise Failure("The app catalogue that ships with Cybex OS is missing or unsupported.")
    apps = [app for app in data['apps'] if isinstance(app, dict) and isinstance(app.get('id'), str)
            and APP_ID.fullmatch(app['id']) and isinstance(app.get('attribute'), str)
            and len(app['attribute']) <= 200 and ATTRIBUTE.fullmatch(app['attribute'])]
    return data, apps


def catalogue(*, config='/etc/nixos', installed='/etc/cybexos/software.json', source=SHIPPED, cache=None, run=None):
    """The shipped app catalogue with this machine's state.

    Each app says whether it is installed and by whom, its version in the
    machine's own locked Nixpkgs, and whether it is unavailable here (for
    instance unfree while proprietary apps are disabled). Inventory packages
    carry their visible desktop entries, so the shell can tell apps apart.
    Metadata is evaluated offline once per configuration identity.
    """
    from .engine import config_digest
    config = Path(config).resolve()
    data, apps = shipped_catalogue(source)
    attributes = sorted({app['attribute'] for app in apps})
    before = config_digest(config)
    identity = hashlib.sha256((before + '\0' + '\0'.join(attributes)).encode()).hexdigest()
    cache = cache_directory(cache)
    run = run or Runner()
    with locked(cache / 'apps.lock'):
        try:
            index = read(cache / 'apps.json', {})
        except Failure:
            index = {}
        if (not isinstance(index, dict) or index.get('identity') != identity
                or not isinstance(index.get('packages'), dict) or not isinstance(index.get('allowUnfree'), bool)):
            index = evaluate(run, config, attributes) | {'identity': identity}
            if config_digest(config) != before:
                raise Failure('The machine configuration changed while indexing. Refresh Software.')
            atomic(cache / 'apps.json', index)
    current = inventory(installed, config)
    if config_digest(config) != before:
        raise Failure('The machine configuration changed. Refresh Software.')
    rows, by_attribute, by_desktop, by_name = [], {}, {}, {}
    for package in current.get('packages') or []:
        if not isinstance(package, dict) or not isinstance(package.get('name'), str):
            continue
        row = package | {'owner': owner(package), 'apps': desktop_entries(package.get('path'))}
        rows.append(row)
        for attribute in row.get('attributes') or []:
            by_attribute.setdefault(attribute, row)
        for entry in row['apps']:
            by_desktop.setdefault(entry['id'], row)
        by_name.setdefault(row['name'], []).append(row)
    selected, desired = set(current['selected']), set(current['desired'])
    allow_unfree = index['allowUnfree']
    merged = []
    for app in apps:
        meta = index['packages'].get(app['attribute'])
        matches = ([by_attribute[app['attribute']]] if app['attribute'] in by_attribute else []) + [
            by_desktop[name] for name in app.get('desktopIds') or [] if isinstance(name, str) and name in by_desktop]
        if not matches and meta and meta['pname']:
            matches = by_name.get(meta['pname'], [])
        match = min(matches, key=lambda row: OWNERS.index(row['owner'])) if matches else None
        merged.append(app | {
            'installed': match is not None,
            'owner': match['owner'] if match else '',
            'installedVersion': match.get('version', '') if match else '',
            'version': meta['version'] if meta else '',
            'unavailable': unavailable(meta, allow_unfree),
            'selected': app['attribute'] in selected,
            'desired': app['attribute'] in desired,
        })
    return {'schema': 1, 'identity': before, 'nixpkgs': data.get('nixpkgs', ''),
            'icons': str(Path(source) / 'icons'), 'allowUnfree': allow_unfree,
            'categories': data['categories'], 'profiles': data['profiles'],
            'featured': [name for name in data['featured'] if isinstance(name, str)],
            'apps': merged, 'packages': rows,
            'selected': current['selected'], 'desired': current['desired'],
            'configurationChanged': current['configurationChanged']}


def attributes_to_check(value):
    if (not isinstance(value, (list, tuple)) or not 0 < len(value) <= CHECK_LIMIT
            or any(not isinstance(p, str) or len(p) > 200 or not ATTRIBUTE.fullmatch(p) for p in value)
            or len(set(value)) != len(value)):
        raise Failure(f'Check between 1 and {CHECK_LIMIT} distinct package attributes.')
    return list(value)


class Remembered:
    """One `nix derivation show` per check, however many roots ask for it."""
    def __init__(self, run):
        self.run, self.answers = run, {}

    def __call__(self, *args, **kwargs):
        key = (args, tuple(sorted(kwargs.items())))
        if key not in self.answers:
            self.answers[key] = self.run(*args, **kwargs)
        return self.answers[key]


def check(attributes, *, config='/etc/nixos', run=None):
    """Would installing these packages compile anything on this computer?

    A dry run of the machine's own packages (the same universe as search)
    against its store and configured caches; nothing is built. Unfree vendor
    packages are never in the NixOS cache: unpacking their download is
    expected, and so is anything needed only to build them.
    """
    wanted = attributes_to_check(attributes)
    config = Path(config).resolve()
    run = run or Runner()
    meta = evaluate(run, config, wanted, derivations=True)
    result, roots = {}, {}
    for attribute in wanted:
        info = meta['packages'].get(attribute)
        reason = unavailable(info, meta['allowUnfree']) or ('' if info['drvPath'] else 'unsupported')
        row = {'state': 'unavailable' if reason else 'checking', 'reason': reason, 'compiles': [],
               'vendor': bool(info and info['unfree']), 'version': info['version'] if info else ''}
        result[attribute] = row
        if not reason:
            roots[attribute] = info['drvPath']
    plan = {'build': [], 'fetch': [], 'downloadBytes': 0}
    if roots:
        machine = 'path:' + str(config) + '#nixosConfigurations.cybexos.pkgs.'
        try:
            # The lock is never refreshed.
            plan = prebuilt.dry_run(run, *[machine + attribute for attribute in roots], options=('--no-update-lock-file',))
            shared = Remembered(run)
            expected = [root for attribute, root in roots.items() if result[attribute]['vendor']]
            for attribute, root in roots.items():
                found = prebuilt.compiles(shared, plan['build'], root=root, expected=expected) if plan['build'] else []
                result[attribute] |= {'state': 'compiles' if found else 'prebuilt', 'compiles': found}
        except CommandFailure:
            raise Failure("Software couldn't check NixOS's package cache. Check your internet connection and try again.") from None
    compiles = sorted({name for row in result.values() for name in row['compiles']})
    return {'prebuilt': all(row['state'] == 'prebuilt' for row in result.values()),
            'downloadBytes': plan['downloadBytes'], 'compiles': compiles, 'packages': result}


def search(query='', *, config='/etc/nixos', installed='/etc/cybexos/software.json', cache=None, run=None):
    from .engine import config_digest
    if not isinstance(query, str) or len(query) > 200:
        raise Failure('Search is limited to 200 characters.')
    config = Path(config).resolve()
    before = config_digest(config)
    cache = cache_directory(cache)
    run = run or Runner()
    with locked(cache / 'catalogue.lock'):
        index = read(cache / 'catalogue.json', {})
        if index.get('identity') != before:
            # Includes machine overlays; neither discovery nor lock refresh.
            expression = 'import (builtins.toPath ' + json.dumps(str(EXPRESSION)) + ') { machine = ' + json.dumps('path:' + str(config)) + '; }'
            data = parse(run('nix', 'eval', '--json', '--offline', '--no-update-lock-file',
                             '--impure', '--expr', expression, timeout=600, sensitive=True))
            if not isinstance(data, list):
                raise Failure('Nix returned an invalid package catalogue.')
            rows = []
            for meta in data:
                if not isinstance(meta, dict) or not ATTRIBUTE.fullmatch(meta.get('attribute', '')):
                    continue
                rows.append({'attribute': meta['attribute'], 'name': str(meta.get('name', meta['attribute'])),
                             'version': str(meta.get('version', '')),
                             'description': str(meta.get('description', ''))[:2048]})
            if config_digest(config) != before:
                raise Failure('The machine configuration changed while indexing. Refresh Software.')
            index = {'identity': before, 'packages': rows}
            atomic(cache / 'catalogue.json', index)
    current = inventory(installed, config)
    if config_digest(config) != before:
        raise Failure('The machine configuration changed. Refresh Software.')
    terms = query.casefold().split()
    rows = [p for p in index['packages'] if all(term in
            (p['attribute'] + ' ' + p['name'] + ' ' + p['description']).casefold() for term in terms)]
    rows.sort(key=lambda p: (p['attribute'].casefold() != query.casefold(),
                            not p['name'].casefold().startswith(query.casefold()), p['attribute']))
    return current | {'identity': before, 'total': len(rows), 'results': rows[:200]}
