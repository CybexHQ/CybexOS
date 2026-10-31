#!/usr/bin/env python3
"""Real Software app with a scripted cybex boundary and a private Sway.

Run through nix develop (qs, sway, grim, wtype, cmake). The production QML,
finite subprocesses, window and controls run unchanged from a private copy
of this checkout with one test-only IPC target injected. `cybex` is a
fixture: its catalogue answers come from the real lifecycle merge
(cybexos.software.catalogue) over fixture inventories, with only `nix eval`
and desktop-entry reads faked; checks, staging, the worker's status and
apply are scripted. Nothing authenticates, builds, contacts Nix caches or
changes the host. Screenshots load from Flathub when its media server is
reachable, as on a real system; nothing depends on them.

    nix develop -c python3 -B tests/software-app.py --screenshots /tmp/cybex-software-shots
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lifecycle'))
from cybexos import software  # noqa: E402
from cybexos.common import atomic  # noqa: E402


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tests' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


welcome = load('welcome-guide')
updates = load('update-flow')

VERSIONS = {'gimp': '3.0.6', 'krita': '5.2.13', 'blender': '4.5.3', 'inkscape': '1.4.2', 'darktable': '5.2.1',
            'firefox': '144.0.2', 'libreoffice': '25.8.2.2', 'pinta': '3.0.4', 'mpv': '0.40.0',
            'localsend': '1.17.0', 'obs-studio': '32.0.1', 'spotify': '1.2.74', 'zed-editor': '0.208.4'}


def store(name, letter='a'):
    return '/nix/store/' + letter * 32 + '-' + name


# A default installation's apps (Cybex OS), one personal app and some tools.
BASE = [
    ('firefox', 'cybexos', [('firefox.desktop', 'Firefox', 'firefox')], 'b'),
    ('libreoffice', 'cybexos', [('startcenter.desktop', 'LibreOffice', 'libreoffice-startcenter'),
                                ('writer.desktop', 'LibreOffice Writer', 'libreoffice-writer')], 'c'),
    ('pinta', 'cybexos', [('com.github.PintaProject.Pinta.desktop', 'Pinta', 'pinta')], 'd'),
    ('inkscape', 'cybexos', [('org.inkscape.Inkscape.desktop', 'Inkscape', 'org.inkscape.Inkscape')], 'e'),
    ('mpv', 'cybexos', [('mpv.desktop', 'mpv Media Player', 'mpv')], 'f'),
    ('localsend', 'cybexos', [('LocalSend.desktop', 'LocalSend', 'localsend')], 'g'),
    ('kitty', 'cybexos', [('kitty.desktop', 'kitty', 'kitty')], 'h'),
    ('nautilus', 'cybexos', [('org.gnome.Nautilus.desktop', 'Files', 'org.gnome.Nautilus')], 'i'),
    ('obs-studio', 'personal', [('com.obsproject.Studio.desktop', 'OBS Studio', 'com.obsproject.Studio')], 'j'),
    ('coreutils', 'nixos', [], 'k'), ('git', 'cybexos', [], 'l'), ('ripgrep', 'cybexos', [], 'm'),
    ('htop', 'personal', [], 'n')]
GIMP = ('gimp', 'software', [('gimp.desktop', 'GIMP', 'gimp')], 'o')
HELLO = ('hello', 'software', [], 'p')


def inventory(rows):
    packages, entries = [], {}
    for name, origin, apps, letter in rows:
        path = store(name + '-' + VERSIONS.get(name, '1.0'), letter)
        attributes = [name] if origin == 'software' else []
        packages.append({'path': path, 'name': name, 'version': VERSIONS.get(name, '1.0'),
                         'description': 'The ' + name + ' package', 'attributes': attributes,
                         'origins': [origin], 'managedElsewhere': origin != 'software'})
        entries[path] = [{'id': ident, 'name': title, 'icon': icon} for ident, title, icon in apps]
    return packages, entries


def metadata(*args, **kwargs):
    """`nix eval` of software-catalogue.nix: every attribute exists."""
    import re
    names = [json.loads(name) for name in re.search(r'attributes = \[ (.*) \];', args[-1])[1].split()]
    rows = []
    for name in names:
        unfree = name in ('spotify', 'discord', 'slack', 'zoom-us', 'obsidian', 'vscode', 'google-chrome',
                          'vivaldi', 'postman')
        rows.append({'attribute': name, 'exists': True, 'pname': name.split('.')[-1],
                     'version': VERSIONS.get(name, '2.1.0'), 'unfree': unfree, 'available': True, 'broken': False})
    return json.dumps({'allowUnfree': True, 'packages': rows})


def merged(base, selected):
    """The real `cybex software catalogue` merge over a fixture machine."""
    config = base / 'machine'
    atomic(config / 'local/software.json', {'schema': 1, 'packages': sorted(selected)}, 0o644)
    rows = BASE + [row for row in (GIMP, HELLO) if row[0] in selected]
    packages, entries = inventory(rows)
    installed = base / 'inventory.json'
    atomic(installed, {'schema': 1, 'selected': sorted(selected), 'packages': packages})
    with patch.object(software, 'desktop_entries', side_effect=lambda path, limit=24: entries.get(path, [])):
        return software.catalogue(config=config, installed=installed, source=ROOT / 'desktop/software',
                                  cache=base / 'catalogue-cache', run=metadata)


FAKE = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ['XDG_RUNTIME_DIR'])
args = sys.argv[1:]
fixture = json.loads((root / 'fixture.json').read_text())
def record(call):
    with (root / 'calls.jsonl').open('a') as stream:
        stream.write(json.dumps(call) + '\n')
def status():
    return json.loads((root / 'status.json').read_text())
def publish(value):
    (root / 'status.json').write_text(json.dumps(value))
if args[:2] == ['software', 'catalogue']:
    if fixture.get('catalogueError'):
        print(json.dumps({'error': fixture['catalogueError']}), file=sys.stderr); sys.exit(1)
    print((root / fixture.get('catalogue', 'catalogue.json')).read_text())
elif args[:2] == ['software', 'check']:
    record(args)
    time.sleep(fixture.get('checkDelay', 0.2))
    verdicts = fixture.get('verdicts', {})
    packages, total = {}, 0
    for name in args[2:]:
        row = verdicts.get(name, {'state': 'prebuilt', 'downloadBytes': 50000000})
        total += row.get('downloadBytes', 0)
        packages[name] = {'state': row['state'], 'reason': row.get('reason', ''), 'compiles': row.get('compiles', []),
                          'vendor': row.get('vendor', False), 'version': row.get('version', '1.0')}
    print(json.dumps({'prebuilt': all(p['state'] == 'prebuilt' for p in packages.values()),
                      'downloadBytes': total, 'compiles': sorted({c for p in packages.values() for c in p['compiles']}),
                      'packages': packages}))
elif args[:2] == ['software', 'search']:
    query = args[2].casefold()
    rows = [row for row in fixture.get('search', []) if query in (row['attribute'] + ' ' + row['description']).casefold()]
    print(json.dumps({'total': len(rows), 'results': rows}))
elif args[:2] == ['software', 'stage']:
    record(args[:2] + [json.loads(args[2])])
    if fixture.get('cancelStage'):
        sys.exit(126)
    identifier = 'c' * 32
    (root / 'request.json').write_text(json.dumps({'state': 'running', 'createdAt': time.time()}))
    request = json.loads(args[2])
    publish({'state': 'building', 'changeKind': 'software', 'requestId': identifier, 'transaction': 'a' * 32,
             'phase': 'Downloading inputs and building the complete system', 'installedIdentity': 'installed-lock',
             'automatic': {'prepare': False, 'confirm': True}, 'stagedSoftware': request,
             'progress': {'schema': 1, 'active': True, 'step': 'downloading',
                          'downloads': {'doneBytes': 96000000, 'expectedBytes': 230000000, 'active': 2, 'totalKnown': True},
                          'builds': {'done': 0, 'expected': 0, 'active': 0}, 'components': []}})
    print(json.dumps({'accepted': True, 'requestId': identifier, 'unit': 'cybexos-software@' + identifier + '.service'}))
elif args[:2] == ['software', 'request']:
    path = root / 'request.json'
    print(path.read_text() if path.exists() else json.dumps({'state': 'running', 'createdAt': time.time()}))
elif args[:2] == ['software', 'flathub']:
    # This account's installation and the latest change, settled lazily: a
    # change finishes `flathubDelay` seconds after it started.
    path = root / 'flathub.json'
    state = json.loads(path.read_text()) if path.exists() else {'installed': [], 'task': None}
    task = state.get('task')
    if task and task['state'] == 'running' and time.time() - task['startedAt'] > fixture.get('flathubDelay', 1.5):
        if fixture.get('flathubFail'):
            task.update(state='failed', error=fixture['flathubFail'])
        else:
            if task['action'] == 'install':
                state['installed'] += [{'id': app, 'name': task['names'].get(app, app), 'version': '1.0', 'branch': 'stable',
                                        'origin': 'flathub', 'installation': 'user', 'icon': '', 'desktop': False}
                                       for app in task['ids']]
            elif task['action'] == 'remove':
                state['installed'] = [row for row in state['installed'] if row['id'] not in task['ids']]
            task['state'] = 'done'
        path.write_text(json.dumps(state))
    action = args[2]
    if action == 'status':
        public = {key: task.get(key) for key in ('id', 'action', 'ids', 'names', 'state', 'error')} if task else None
        print(json.dumps({'schema': 1, 'enabled': True, 'available': True, 'remote': True, 'proprietary': True,
                          'task': public, 'installed': state['installed']}))
    elif action == 'search':
        record(args)
        time.sleep(fixture.get('flathubSearchDelay', 0.3))
        query = args[3].casefold()
        rows = [row for row in fixture.get('flathubSearch', []) if query in (row['name'] + ' ' + row['summary']).casefold()]
        print(json.dumps({'query': args[3], 'total': len(rows), 'results': rows, 'proprietary': True}))
    elif action == 'app':
        record(args)
        apps = fixture.get('flathubApps', {})
        if args[3] not in apps:
            print(json.dumps({'error': "Flathub doesn't have this app."}), file=sys.stderr); sys.exit(1)
        mine = [row for row in state['installed'] if row['id'] == args[3]]
        print(json.dumps(apps[args[3]] | {'installed': mine[0] if mine else None}))
    elif action == 'updates':
        record(args)
        print(json.dumps({'updates': fixture.get('flathubUpdates', [])}))
    elif action in ('install', 'remove', 'update'):
        record(args)
        names = json.loads(args[args.index('--names') + 1])
        ids = args[args.index('--names') + 2:]
        state['task'] = {'id': 'f' * 32, 'action': action, 'ids': ids, 'names': names, 'state': 'running',
                         'error': '', 'startedAt': time.time()}
        path.write_text(json.dumps(state))
        print(json.dumps({'accepted': True, 'task': 'f' * 32}))
    else:
        sys.exit(127)
elif args[:2] == ['update', 'check']:
    print(json.dumps(fixture['sources']))
elif args[:2] == ['update', 'status']:
    print((root / 'status.json').read_text())
elif args[:1] == ['update']:
    record(args)
    if fixture.get('cancelUpdate'):
        sys.exit(126)
    state = status()
    request = {'id': 'd' * 32, 'state': 'done', 'action': args[1], 'createdAt': time.time()}
    if args[1] == 'apply':
        assert args[2:] == ['a' * 32, 'b' * 64], args
        state.update(state='activating', phase='Activating under supervision', reviewToken=None)
        publish(state | {'request': request})
        time.sleep(fixture.get('activation', 1.5))
        state.update(state='awaiting-boot', phase='Activation passed. Reboot when ready.')
        fixture['catalogue'] = 'catalogue-after.json'
        (root / 'fixture.json').write_text(json.dumps(fixture))
        (root / 'request.json').write_text(json.dumps({'state': 'done', 'createdAt': time.time()}))
    elif args[1] == 'discard':
        state = {'state': 'idle', 'automatic': state.get('automatic', {})}
    publish(state | {'request': request, 'installedIdentity': 'installed-lock'})
    print(json.dumps({'accepted': True, 'requestId': request['id']}))
else:
    sys.exit(127)
'''

THUNDERBIRD_MEDIA = 'https://dl.flathub.org/media/org/mozilla/thunderbird/23751bbaeddad88ad5452bd277389f14/'
FLATHUB_SEARCH = [
    {'id': 'org.mozilla.thunderbird', 'name': 'Thunderbird', 'summary': 'Email, newsfeed, chat and calendaring client',
     'developer': 'MZLA Technologies', 'icon': 'https://dl.flathub.org/media//org/mozilla/thunderbird/23751bbaeddad88ad5452bd277389f14/icons/128x128/org.mozilla.thunderbird.png',
     'license': 'MPL-2.0', 'free': True, 'verified': True, 'installs': 29077, 'unavailable': '', 'installed': False},
    {'id': 'eu.betterbird.Betterbird', 'name': 'Betterbird', 'summary': 'A fine-tuned mail client based on Thunderbird',
     'developer': 'Betterbird Project', 'icon': '', 'license': 'MPL-2.0', 'free': True, 'verified': False, 'installs': 3000,
     'unavailable': '', 'installed': False},
    # The catalogue already shows GIMP; Flathub's copy is not listed twice.
    {'id': 'org.gimp.GIMP', 'name': 'GIMP mail plugin test', 'summary': 'Mail', 'developer': '', 'icon': '', 'license': '',
     'free': True, 'verified': True, 'installs': 1, 'unavailable': '', 'installed': False}]
FLATHUB_APPS = {'org.mozilla.thunderbird': {
    'id': 'org.mozilla.thunderbird', 'name': 'Thunderbird', 'summary': 'Email, newsfeed, chat and calendaring client',
    'description': ['Thunderbird is a free and open source email, newsfeed, chat and calendaring client that is easy to set up and customize.',
                    '• Calendars and contacts', '• Encrypted mail with OpenPGP'],
    'developer': 'MZLA Technologies', 'license': 'MPL-2.0', 'free': True, 'icon': FLATHUB_SEARCH[0]['icon'],
    'screenshots': [THUNDERBIRD_MEDIA + 'screenshots/image-1_752x470@1.png', THUNDERBIRD_MEDIA + 'screenshots/image-2_752x470@1.png'],
    'brand': {}, 'homepage': 'https://www.thunderbird.net/', 'version': '159.0', 'verified': True,
    'downloadBytes': 126212325, 'installedBytes': 343719424, 'runtime': 'Freedesktop Platform version 25.08',
    'permissions': ['files-home', 'devices', 'network'], 'eol': False, 'supported': True, 'unavailable': ''}}

LAUNCHED = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with (Path(os.environ['HOME']) / 'launched.jsonl').open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\n')
'''

IPC = '''
    property var softwareTestWindow: null
    // Only shown items count: pages under the current one stay alive.
    function softwareFind(item, name, skip) {
        if (!item || item.visible === false) return null;
        if (item.objectName === name) {
            if (skip.n === 0) return item;
            skip.n--;
        }
        for (const child of item.children || []) {
            const found = shell.softwareFind(child, name, skip);
            if (found) return found;
        }
        return null;
    }
    function softwareCount(item, name) {
        if (!item || item.visible === false) return 0;
        let count = item.objectName === name ? 1 : 0;
        for (const child of item.children || []) count += shell.softwareCount(child, name);
        return count;
    }
    function softwareRoot() {
        return softwareTestWindow && softwareTestWindow.visible ? softwareTestWindow.contentItem : null;
    }
    function softwareItem(name, index) {
        return shell.softwareFind(shell.softwareRoot(), name, {n: index || 0});
    }
    function softwareText(name) {
        const item = shell.softwareItem(name);
        return item ? String(item.text) : null;
    }
    IpcHandler {
        target: "software-test"
        function refresh(): void { Updates.refreshStatus(); Updates.check(); }
        function tab(name: string): void { Software.selectTab(name); }
        function category(id: string): void { Software.openCategory(id); }
        function sub(id: string): void { Software.setSubcategory(id); }
        function app(id: string): void { Software.openApp(id); }
        function flathub(id: string): void { Software.openFlathub(id, null); }
        function flathubRefresh(): void { Software.refreshFlathub(); }
        function back(): void { Software.back(); }
        function search(text: string): void { Software.search(text); }
        function press(name: string, index: int): string {
            const item = shell.softwareItem(name, index);
            if (!item || !item.enabled) return "false";
            item.triggered();
            return "true";
        }
        function scrollTo(name: string, fraction: real): void {
            const page = shell.softwareItem(name);
            if (page) page.contentY = Math.max(0, (page.contentHeight - page.height) * fraction);
        }
        function state(): string {
            const primary = shell.softwareItem("softwareQueuePrimary");
            const appPrimary = shell.softwareItem("softwareAppPrimary");
            const root = shell.softwareRoot();
            return JSON.stringify({open: Software.open, window: !!root, loaded: Software.loaded,
                loadError: Software.loadError, view: Software.view, tab: Software.tab, page: Software.page,
                phase: Software.phase, blockReason: Software.blockReason, flowError: Software.flowError,
                failure: Software.failure, query: Software.query,
                queue: Software.queue.map(row => row.attribute + ":" + row.action),
                checks: Object.keys(Software.checks).reduce((all, key) => Object.assign(all, {[key]: Software.checks[key].state}), {}),
                updates: Software.updates.length, appResults: Software.appResults.length,
                more: Software.morePackages.length, dark: Theme.dark, deployment: Updates.deployment.state,
                requestFailure: Updates.requestFailure, focusSearch: !!shell.softwareItem("softwareSearch")
                    && shell.softwareItem("softwareSearch").activeFocus,
                title: shell.softwareText("softwareQueueTitle"), detail: shell.softwareText("softwareQueueDetail"),
                bar: !!shell.softwareItem("softwareQueueBar"),
                primary: primary ? {text: primary.text, enabled: primary.enabled} : null,
                appPrimary: appPrimary ? {text: appPrimary.text, enabled: appPrimary.enabled} : null,
                download: shell.softwareText("softwareAppDownload"), appName: shell.softwareText("softwareAppName"),
                flathubOn: Software.flathubOn, flathubHits: Software.flathubHits.length,
                flathubInstalled: Software.flathubInstalled.length,
                flathubTask: Software.flathubTask ? Software.flathubTask.state : "",
                flathubName: shell.softwareText("softwareFlathubName"),
                flathubDownload: shell.softwareText("softwareFlathubDownload"),
                flathubPrimary: shell.softwareItem("softwareFlathubPrimary") ? {text: shell.softwareItem("softwareFlathubPrimary").text,
                    enabled: shell.softwareItem("softwareFlathubPrimary").enabled} : null,
                flathubError: !!shell.softwareItem("softwareFlathubError"),
                flathubUpdateState: shell.softwareText("softwareFlathubUpdateState"),
                appFlathub: !!shell.softwareItem("softwareAppFlathub"),
                categoryTitle: shell.softwareText("softwareCategoryTitle"),
                badge: shell.softwareText("softwareUpdatesBadge") !== null,
                counts: {hero: shell.softwareCount(root, "softwareHero"), categories: shell.softwareCount(root, "softwareCategory"),
                    popular: shell.softwareCount(root, "softwarePopularApp"), rows: shell.softwareCount(root, "softwareAppRow"),
                    subcategories: shell.softwareCount(root, "softwareSubcategory"),
                    mine: shell.softwareCount(root, "softwareInstalledMine"), vendor: shell.softwareCount(root, "softwareInstalledVendor"),
                    personal: shell.softwareCount(root, "softwareInstalledPersonal"), other: shell.softwareCount(root, "softwareInstalledOther"),
                    updateRows: shell.softwareCount(root, "softwareUpdateRow"), upToDate: shell.softwareCount(root, "softwareUpToDate"),
                    screenshots: shell.softwareCount(root, "softwareScreenshot"),
                    searchApps: shell.softwareCount(root, "softwareSearchApp"), packages: shell.softwareCount(root, "softwarePackageResult"),
                    flathubResults: shell.softwareCount(root, "softwareFlathubResult"),
                    flathubPermissions: shell.softwareCount(root, "softwareFlathubPermission"),
                    installedFlathub: shell.softwareCount(root, "softwareInstalledFlathub"),
                    flathubUpdateRows: shell.softwareCount(root, "softwareFlathubUpdateRow")}});
        }
    }
'''


class Session(welcome.Session):
    def copy_source(self):
        self.source.mkdir()
        for name in ('desktop', 'assets'):
            shutil.copytree(ROOT / name, self.source / name, ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copyfile(ROOT / 'VERSION', self.source / 'VERSION')
        subprocess.run(['git', 'init', '-q', str(self.source)], check=True)
        entry = self.source / 'desktop/quickshell/shell.qml'
        text = entry.read_text().replace('    id: shell', '    id: shell\n' + IPC, 1)
        assert text.count('    SoftwareWindow {}\n') == 1
        text = text.replace('    SoftwareWindow {}\n',
            '    SoftwareWindow { id: softwareWindow; Component.onCompleted: shell.softwareTestWindow = softwareWindow }\n')
        entry.write_text(text)

    def state(self):
        return self.json_call('software-test', 'state')

    def probe(self):
        return self.state()

    def fixture(self, **values):
        path = self.runtime / 'fixture.json'
        value = json.loads(path.read_text()) if path.exists() else {}
        path.write_text(json.dumps(value | values))

    def flathub_state(self, installed, task=None):
        (self.runtime / 'flathub.json').write_text(json.dumps({'installed': installed, 'task': task}))
        self.call('software-test', 'flathubRefresh')

    def status(self, **values):
        values.setdefault('automatic', {'prepare': False, 'confirm': True})
        (self.runtime / 'status.json').write_text(json.dumps({'installedIdentity': 'installed-lock', **values}))
        self.call('software-test', 'refresh')

    def press(self, name, index=0):
        return self.call('software-test', 'press', name, str(index)) == 'true'

    def calls(self):
        path = self.runtime / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def window_rect(self):
        tree = json.loads(self.sway('-t', 'get_tree'))
        stack = [tree]
        while stack:
            node = stack.pop()
            if node.get('name') == 'Cybex OS Software' and node.get('visible'):
                return node['rect']
            stack.extend(node.get('nodes', []) + node.get('floating_nodes', []))
        return None

    def shot(self, directory, name, settle=1.0):
        if directory is None:
            return
        from PIL import Image
        path = self.capture(directory, name, settle)
        rect = self.window_rect()
        if rect:
            Image.open(path).crop((rect['x'], rect['y'], rect['x'] + rect['width'], rect['y'] + rect['height'])).save(path)
        print('screenshot', path)

    def themed(self, directory, name, settle=1.0):
        for mode in ('light', 'dark'):
            self.patch_settings(themeMode=mode)
            self.wait(lambda: self.state().get('dark') == (mode == 'dark'), mode + ' theme')
            self.shot(directory, f'{name}-{mode}.png', settle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screenshots', type=Path)
    args = parser.parse_args()
    for executable in ('qs', 'sway', 'grim', 'wtype', 'cmake', 'git'):
        if not shutil.which(executable):
            raise SystemExit(f'{executable} is required; use nix develop')
    shots = args.screenshots
    if shots:
        shots.mkdir(parents=True, exist_ok=True)
    updates.process_guard()
    with tempfile.TemporaryDirectory(prefix='cxs-') as temporary:
        base = Path(temporary)
        native = base / 'native'
        subprocess.run(['cmake', '-S', str(ROOT / 'desktop/notification-images'), '-B', str(native),
                        '-DBUILD_TESTING=OFF'], check=True, capture_output=True)
        subprocess.run(['cmake', '--build', str(native), '--parallel', '2'], check=True, capture_output=True)
        session = Session(base, native / 'qml')
        session.env.update(CYBEXOS_WELCOME='0', CYBEXOS_ASSISTANT='0')
        for name, body in (('cybex', FAKE), ('systemctl', updates.SYSTEMCTL.replace('REAL', repr(shutil.which('systemctl')))),
                           ('fake-gimp', LAUNCHED), ('flatpak', LAUNCHED)):
            (base / 'bin' / name).write_text(body)
            (base / 'bin' / name).chmod(0o700)
        applications = session.home / '.local/share/applications'
        applications.mkdir(parents=True, exist_ok=True)
        (applications / 'gimp.desktop').write_text('[Desktop Entry]\nType=Application\nName=GIMP\nIcon=gimp\n'
                                                  f'Exec={base / "bin/fake-gimp"} %U\n')
        # Real merges: before, and after installing GIMP and hello.
        before = merged(base / 'fixture-before', [])
        after = merged(base / 'fixture-after', ['gimp', 'hello'])
        (session.runtime / 'catalogue.json').write_text(json.dumps(before))
        (session.runtime / 'catalogue-after.json').write_text(json.dumps(after))
        assert {app['id']: app['owner'] for app in before['apps'] if app['installed']} == \
            {'firefox': 'cybexos', 'libreoffice': 'cybexos', 'pinta': 'cybexos', 'inkscape': 'cybexos',
             'mpv': 'cybexos', 'localsend': 'cybexos', 'obs': 'personal'}, before['apps']
        sources = {'installedIdentity': 'installed-lock', 'upstream': {'state': 'current'}, 'cybexos': {'state': 'current'}}
        session.fixture(sources=sources, catalogue='catalogue.json',
                        verdicts={'gimp': {'state': 'prebuilt', 'downloadBytes': 181815830},
                                  'blender': {'state': 'compiles', 'compiles': ['blender-4.5.3']},
                                  'krita': {'state': 'prebuilt', 'downloadBytes': 400748336},
                                  'hello': {'state': 'prebuilt', 'downloadBytes': 56000}},
                        flathubSearch=FLATHUB_SEARCH, flathubApps=FLATHUB_APPS,
                        search=[{'attribute': 'hello', 'name': 'hello', 'version': '2.12.2',
                                 'description': 'A program that produces a familiar, friendly greeting'},
                                {'attribute': 'gimp', 'name': 'gimp', 'version': '3.0.6', 'description': 'GNU Image Manipulation Program'},
                                {'attribute': 'cowsay', 'name': 'cowsay', 'version': '3.8.4',
                                 'description': 'A program which generates ASCII pictures of a cow with a message'}])
        session.status(state='idle')
        try:
            conf = base / 'sway.conf'
            conf.write_text('output HEADLESS-1 mode 1440x900\nseat seat0 fallback true\n'
                            'for_window [title="Cybex OS Software"] floating enable, move position center\n'
                            'for_window [title="Software Update"] floating enable, move position center\n')
            sway = base / 'sway'
            shutil.copyfile(os.environ.get('CYBEXOS_SWAY_BINARY') or shutil.which('sway'), sway)
            sway.chmod(0o700)
            session.start([str(sway), '-c', str(conf)], 'sway.log')
            sockets = session.wait(lambda: [p for p in session.runtime.glob('wayland-*') if p.is_socket()], 'compositor')
            session.env['WAYLAND_DISPLAY'] = sockets[0].name
            session.env['SWAYSOCK'] = str(session.wait(lambda: next(session.runtime.glob('sway-ipc.*.sock'), None), 'compositor IPC'))
            session.start_shell('qs-first.log')
            state = session.state
            wait = session.wait

            # ---- Explore ---------------------------------------------------
            session.call('software', 'open')
            wait(lambda: state().get('window') and state().get('loaded') and state()['counts']['categories'] == 8, 'Explore')
            current = state()
            assert current['view'] == 'explore' and current['counts']['hero'] == 1, current
            assert current['counts']['popular'] == 8, current
            assert not session.calls(), 'opening Software checks or stages nothing'
            session.themed(shots, 'software-explore')
            session.call('software-test', 'scrollTo', 'softwareExplorePage', '1')
            session.themed(shots, 'software-explore-collections')

            # ---- a category ------------------------------------------------
            session.call('software-test', 'category', 'create')
            wait(lambda: state().get('view') == 'category' and state().get('categoryTitle') == 'Create', 'category page')
            current = state()
            assert current['counts']['subcategories'] == 6 and current['counts']['rows'] >= 10, current
            session.themed(shots, 'software-category')
            session.call('software-test', 'sub', 'photo')
            wait(lambda: (state().get('page') or {}).get('sub') == 'photo', 'subcategory')
            assert state()['counts']['rows'] < current['counts']['rows'], state()

            # ---- an app page: checked on demand ----------------------------
            session.call('software-test', 'app', 'gimp')
            wait(lambda: state().get('appName') == 'GIMP' and state()['checks'].get('gimp') == 'prebuilt', 'GIMP page and check')
            wait(lambda: state().get('download') == 'Download ≈ 182 MB · nothing to compile', 'exact download')
            assert session.calls()[-1] == ['software', 'check', 'gimp'], session.calls()
            assert state()['counts']['screenshots'] == 3, state()
            assert state()['appPrimary'] == {'text': 'Install', 'enabled': True}, state()
            session.themed(shots, 'software-app', settle=3.0)
            # Escape goes back one page, to the category.
            session.key('-k', 'Escape')
            wait(lambda: state().get('view') == 'category', 'Escape goes back')
            session.call('software-test', 'app', 'gimp')
            wait(lambda: state().get('appName') == 'GIMP', 'GIMP page again')

            # ---- the queue -------------------------------------------------
            assert session.press('softwareAppPrimary')
            wait(lambda: state().get('queue') == ['gimp:install'] and state().get('appPrimary', {}).get('text') == 'Added', 'GIMP added')
            wait(lambda: 'all prebuilt, nothing to compile' in (state().get('detail') or ''), 'queue bar summary')
            # A package from the full search, checked before Install is offered.
            session.call('software-test', 'search', 'hello')
            wait(lambda: state().get('view') == 'search' and state()['counts']['packages'] == 1, 'more packages')
            assert session.press('softwarePackageAction')
            wait(lambda: state()['checks'].get('hello') == 'prebuilt', 'hello checked')
            assert session.press('softwarePackageAction')
            wait(lambda: state().get('queue') == ['gimp:install', 'hello:install'], 'hello added')
            session.themed(shots, 'software-search')
            # Typing anywhere searches; Escape clears the search.
            session.key('-k', 'Escape')
            wait(lambda: state().get('view') == 'explore' and state().get('query') == '', 'Escape leaves search')
            session.key('krita')
            wait(lambda: state().get('query') == 'krita' and state()['appResults'] == 1, 'typing searches')
            session.key('-k', 'Escape')
            wait(lambda: state().get('query') == '', 'search cleared')
            # Blender would compile: blocked calmly, the rest still installs.
            session.call('software-test', 'app', 'blender')
            wait(lambda: state()['checks'].get('blender') == 'compiles', 'blender checked')
            wait(lambda: "hasn't finished building" in (state().get('download') or ''), 'compile explanation')
            assert state()['appPrimary'] == {'text': 'Not ready yet', 'enabled': False}, state()
            session.shot(shots, 'software-app-not-prebuilt-dark.png')
            session.call('software-test', 'back')
            session.themed(shots, 'software-queue')

            # Authorization cancelled: nothing changed, the list comes back.
            session.fixture(cancelStage=True)
            assert session.press('softwareQueuePrimary')
            wait(lambda: 'cancelled' in (state().get('detail') or '') and state().get('phase') == 'idle', 'cancelled authorization')
            assert state()['queue'] == ['gimp:install', 'hello:install'], state()
            assert session.calls()[-2][:2] == ['software', 'check'] and sorted(session.calls()[-2][2:]) == ['gimp', 'hello'], session.calls()

            # Another system change in progress blocks a new one.
            session.status(state='building', changeKind='update', transaction='e' * 32, phase='Building')
            wait(lambda: state().get('blockReason') == 'busy' and state().get('primary', {}).get('enabled') is False, 'blocked by an update')
            assert 'Another system change' in state()['detail'], state()
            session.status(state='idle')
            wait(lambda: state().get('blockReason') == '' and state().get('primary', {}).get('enabled'), 'unblocked')

            # ---- install: check, stage, prepare, ready, install, open ------
            session.fixture(cancelStage=False)
            assert session.press('softwareQueuePrimary')
            wait(lambda: state().get('phase') == 'preparing', 'preparing the change')
            stage = next(call for call in reversed(session.calls()) if call[:2] == ['software', 'stage'])
            assert stage[2] == {'packages': ['gimp', 'hello'], 'previous': []}, stage
            wait(lambda: 'Downloading prebuilt packages · 96 MB of 230 MB' == state().get('detail'), 'download progress')
            session.shot(shots, 'software-installing-dark.png')
            software_change = {'packages': ['gimp', 'hello'], 'previous': []}
            session.status(state='ready', changeKind='software', requestId='c' * 32, transaction='a' * 32,
                           reviewToken='b' * 64, changes='gimp: ∅ → 3.0.6', packageChanges=[], software=software_change,
                           phase='Built and checked; review changes before applying')
            wait(lambda: state().get('phase') == 'ready' and state().get('primary', {}).get('text') == 'Install now', 'ready to install')
            assert state()['title'] == 'Ready to install GIMP, hello', state()
            session.themed(shots, 'software-ready')
            # A cancelled authorization keeps the prepared change.
            session.fixture(cancelUpdate=True)
            assert session.press('softwareQueuePrimary')
            wait(lambda: 'cancelled' in (state().get('requestFailure') or ''), 'apply authorization cancelled')
            assert state()['phase'] == 'ready', state()
            session.fixture(cancelUpdate=False)
            assert session.press('softwareQueuePrimary')
            wait(lambda: state().get('phase') == 'done', 'installed', timeout=40)
            assert ['update', 'apply', 'a' * 32, 'b' * 64] in session.calls(), session.calls()
            wait(lambda: state().get('primary', {}).get('text') == 'Open GIMP', 'open the installed app')
            assert state()['title'] == 'GIMP, hello installed', state()
            session.themed(shots, 'software-installed-bar')
            assert session.press('softwareQueuePrimary')
            wait(lambda: (session.home / 'launched.jsonl').exists(), 'GIMP opened through its desktop entry')
            assert session.press('softwareQueueDismiss')
            wait(lambda: not state().get('bar') and state().get('blockReason') == 'restart', 'dismissed; restart pending')

            # ---- Installed -------------------------------------------------
            session.call('software-test', 'tab', 'installed')
            wait(lambda: state().get('view') == 'installed' and state()['counts']['mine'] == 1, 'Installed tab')
            current = state()['counts']
            assert current['vendor'] >= 7 and current['personal'] == 1 and current['other'] == 0, current
            session.themed(shots, 'software-installed-tab')
            # Removing goes through the same list; the pending restart blocks it calmly.
            assert session.press('softwareInstalledRemove')
            wait(lambda: state().get('queue') == ['gimp:remove'], 'removal queued')
            assert state()['title'] == '1 app to remove: GIMP' and 'Restart your computer' in state()['detail'], state()
            assert state()['primary']['enabled'] is False, state()
            session.shot(shots, 'software-remove-blocked-dark.png')
            assert session.press('softwareQueueClear')
            wait(lambda: not state().get('bar'), 'list cleared')

            # ---- Updates ---------------------------------------------------
            highlights = {'schema': 1, 'components': [{'id': 'kernel', 'before': '6.12.55', 'after': '6.12.58'}],
                          'apps': [{'name': 'firefox', 'title': 'Firefox', 'icon': 'firefox', 'kind': 'updated', 'before': '144.0.2', 'after': '145.0'},
                                   {'name': 'gimp', 'title': 'GIMP', 'icon': 'gimp', 'kind': 'updated', 'before': '3.0.6', 'after': '3.0.8'}],
                          'tools': [], 'background': 212, 'sizeChange': 40000000}
            session.fixture(sources={**sources, 'upstream': {'state': 'available', 'available': 'new-revision'}})
            session.status(state='ready', changeKind='update', scope='upstream', transaction='f' * 32, reviewToken='e' * 64,
                           changes='', packageChanges=[], highlights=highlights)
            session.call('software-test', 'tab', 'updates')
            wait(lambda: state().get('updates') == 2 and state()['counts']['updateRows'] == 2 and state().get('badge'), 'apps in the update')
            session.themed(shots, 'software-updates')
            session.fixture(sources=sources)
            session.status(state='idle')
            wait(lambda: state()['counts']['upToDate'] == 1 and not state().get('badge'), 'up to date')
            session.themed(shots, 'software-updates-current')

            # ---- a worker failure ------------------------------------------
            session.call('software-test', 'tab', 'explore')
            session.call('software-test', 'app', 'krita')
            wait(lambda: state()['checks'].get('krita') == 'prebuilt', 'krita checked')
            assert session.press('softwareAppPrimary')
            assert session.press('softwareQueuePrimary')
            wait(lambda: state().get('phase') == 'preparing', 'preparing krita')
            session.status(state='failed', changeKind='software', requestId='c' * 32, transaction='a' * 32,
                           error='Nix could not download krita. Check your connection.')
            wait(lambda: state().get('phase') == 'failed' and 'could not download' in (state().get('detail') or ''), 'failure shown')
            assert state()['primary']['text'] == 'Try again', state()
            session.shot(shots, 'software-failed-dark.png')
            assert session.press('softwareQueueDismiss')
            wait(lambda: state().get('phase') == 'idle' and state().get('queue') == ['krita:install'], 'failure dismissed, list kept')

            # Screenshots that app pages loaded may now illustrate the hero
            # (Blender is first) and Editor's choice; nothing else fetched them.
            session.call('software-test', 'tab', 'explore')
            session.call('software-test', 'scrollTo', 'softwareExplorePage', '0')
            session.themed(shots, 'software-explore-after-browsing', settle=2.0)
            session.call('software-test', 'category', 'create')
            wait(lambda: state().get('view') == 'category', 'category again')
            session.themed(shots, 'software-category-after-browsing', settle=2.0)

            # ---- Flathub ---------------------------------------------------
            wait(lambda: state().get('flathubOn'), 'Flathub available')
            session.call('software-test', 'search', 'mail')
            wait(lambda: state()['counts']['flathubResults'] == 2, 'Flathub results, without the catalogue duplicate')
            assert ['software', 'flathub', 'search', 'mail'] in session.calls(), session.calls()
            session.themed(shots, 'software-search-flathub', settle=2.0)
            session.call('software-test', 'flathub', 'org.mozilla.thunderbird')
            wait(lambda: state().get('flathubName') == 'Thunderbird' and state()['counts']['flathubPermissions'] == 3,
                 'Flathub app page with its sandbox')
            assert state()['flathubPrimary'] == {'text': 'Install', 'enabled': True}, state()
            assert state()['flathubDownload'] == 'Download ≈ 126 MB · installs right away, for your account', state()
            session.themed(shots, 'software-flathub-app', settle=3.0)
            assert session.press('softwareFlathubPrimary')
            wait(lambda: (state().get('flathubPrimary') or {}).get('text') == 'Installing…', 'installing from Flathub')
            install = next(call for call in reversed(session.calls()) if call[:3] == ['software', 'flathub', 'install'])
            assert install[3:] == ['--names', '{"org.mozilla.thunderbird":"Thunderbird"}', 'org.mozilla.thunderbird'], install
            assert state()['queue'] == ['krita:install'] and state()['phase'] == 'idle', 'no system change is involved'
            session.shot(shots, 'software-flathub-installing-dark.png')
            wait(lambda: (state().get('flathubPrimary') or {}).get('text') == 'Open', 'installed from Flathub', timeout=20)
            assert state()['flathubDownload'] == 'Installed for you from Flathub', state()
            session.themed(shots, 'software-flathub-installed')
            assert session.press('softwareFlathubPrimary')
            wait(lambda: '["run", "org.mozilla.thunderbird"]' in (session.home / 'launched.jsonl').read_text(),
                 'opened with flatpak run')
            session.call('software-test', 'tab', 'installed')
            wait(lambda: state()['counts']['installedFlathub'] == 1, 'Installed lists Flathub apps')
            session.themed(shots, 'software-installed-flathub')
            # Removal is immediate, so the first press asks again.
            assert session.press('softwareInstalledFlathubRemove')
            assert not any(call[:3] == ['software', 'flathub', 'remove'] for call in session.calls())
            assert session.press('softwareInstalledFlathubRemove')
            wait(lambda: state()['counts']['installedFlathub'] == 0, 'removed from Flathub', timeout=20)
            # Updates: this account's Flathub apps, checked when the tab opens.
            vim = {'id': 'org.vim.Vim', 'name': 'Vim', 'version': '9.1', 'branch': 'stable', 'origin': 'flathub',
                   'installation': 'user', 'icon': '', 'desktop': False}
            session.fixture(flathubUpdates=[{'id': 'org.vim.Vim', 'name': 'Vim', 'icon': '', 'before': '9.1', 'after': '9.2'}])
            session.flathub_state([vim])
            wait(lambda: state().get('flathubInstalled') == 1, 'Vim from Flathub')
            session.call('software-test', 'tab', 'explore')
            session.call('software-test', 'tab', 'updates')
            wait(lambda: state()['counts']['flathubUpdateRows'] == 1, 'a Flathub update')
            session.themed(shots, 'software-updates-flathub')
            assert session.press('softwareFlathubUpdateAll')
            wait(lambda: state()['counts']['flathubUpdateRows'] == 0
                 and state().get('flathubUpdateState') == 'Your Flathub apps are up to date.', 'Flathub apps updated', timeout=20)
            update = next(call for call in reversed(session.calls()) if call[:3] == ['software', 'flathub', 'update'])
            assert update[-1] == 'org.vim.Vim', update
            # A catalogue app NixOS can't install yet points to Flathub; one
            # Flathub lacks says so on its page.
            session.call('software-test', 'tab', 'explore')
            session.call('software-test', 'app', 'blender')
            wait(lambda: state().get('appFlathub'), 'Flathub offered for a blocked app')
            session.shot(shots, 'software-app-flathub-offer-dark.png')
            assert session.press('softwareAppFlathubOpen')
            wait(lambda: state().get('flathubError'), "Flathub's answer shown on the page")
            session.call('software-test', 'back')
            session.call('software-test', 'app', 'gimp')
            wait(lambda: state().get('appName') == 'GIMP', 'GIMP page')
            assert not state().get('appFlathub'), 'an installable app is not sent elsewhere'

            # Escape from a tab root closes the window.
            session.call('software-test', 'tab', 'explore')
            session.key('-k', 'Escape')
            wait(lambda: not state().get('open'), 'Escape closes Software')

            # Software's own files only: unrelated widgets warn on this host.
            mine = ('@Software/', 'Software.qml', 'SoftwareWindow.qml', 'SoftwareHelpers.js')
            for log in session.logs:
                if log.name.startswith('qs-'):
                    errors = [line for line in log.read_text(errors='replace').splitlines()
                              if ('WARN' in line or 'ERROR' in line or welcome.ERRORS.search(line))
                              and any(name in line for name in mine)]
                    assert not errors, '\n'.join(errors)
            print('PASS: Explore (hero, categories, collections, popular), a category and subcategory, an app page '
                  'checked on demand with screenshots, a blocked app that would compile, search with a checked package, '
                  'keyboard back/search/close, cancelled authorization, another change blocking, queue → check → stage → '
                  'progress → ready → install → open, Installed groups and removal blocked by a pending restart, '
                  'Updates with a prepared update and up to date, a worker failure, and Flathub: search, an app page '
                  'with its sandbox, install → open, Installed and a confirmed removal, updates, and the offer on a blocked app')
        except BaseException:
            for log in session.logs:
                if log.exists():
                    print(log.name, log.read_text(errors='replace')[-12000:])
            raise
        finally:
            session.stop()
            for pid in welcome.own_processes(session.runtime):
                try:
                    os.kill(pid, 15)
                except ProcessLookupError:
                    pass
            time.sleep(.2)
            updates.process_guard(session.runtime)
            assert not welcome.own_processes(session.runtime)


if __name__ == '__main__':
    main()
