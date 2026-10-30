#!/usr/bin/env python3
"""Real Software Update app with a scripted cybex boundary and private Sway.

The production QML, finite subprocesses, window routing and controls run
unchanged. The fake helpers never authenticate, contact update sources, start
system units, reboot or change the host. Backend worker/build/activation
coverage belongs to NixOS qualification.
"""
import importlib.util
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tests' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


welcome = load('welcome-guide')
pointer = load('assistant-overlay')

HIGHLIGHTS = {'schema': 1,
    'components': [{'id': 'kernel', 'before': '6.12.55', 'after': '6.12.58'},
                   {'id': 'nixos', 'before': '26.05.20261024.abcdef1', 'after': '26.05.20261027.1234567'},
                   {'id': 'firmware', 'before': '20260917', 'after': '20261014'}],
    'apps': [{'name': 'firefox', 'title': 'Firefox', 'icon': 'firefox', 'kind': 'updated', 'before': '143.0.4', 'after': '144.0.1'}],
    'tools': [{'name': 'hello', 'kind': 'updated', 'before': '1', 'after': '2'}],
    'background': 213, 'sizeChange': 40000000}
# A kept Cybex OS release as the worker's completed record keeps it.
NOTES = ('## Highlights\n- **Wiz** now shows how an update is going.\n'
         '- Software Update opens [What\'s New](https://example.com/notes) after an update is kept.\n'
         '![screenshot](https://example.com/never-fetched.png)\n\n'
         '## Fixes\n- The menubar clock no longer skips a minute.')
def release(before, after, transaction):
    return {'transaction': transaction, 'scope': 'both', 'changeKind': 'update', 'notes': NOTES,
            'installedVersion': before, 'availableVersion': after,
            'highlights': {'schema': 1, 'components': [{'id': 'cybexos', 'before': before, 'after': after}]
                + HIGHLIGHTS['components'][:2], 'apps': [], 'tools': [], 'background': 12, 'sizeChange': 0}}

FAKE = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ['XDG_RUNTIME_DIR'])
args = sys.argv[1:]
if args[:1] != ['update']:
    sys.exit(1)
fixture = json.loads((root / 'fixture.json').read_text())
if args[1:] == ['check']:
    time.sleep(fixture.get('checkDelay', 0))
    print(json.dumps(fixture['sources']))
elif args[1:] == ['status']:
    print((root / 'status.json').read_text())
else:
    with (root / 'calls.jsonl').open('a') as stream:
        stream.write(json.dumps(args[1:]) + '\n')
    if fixture.get('cancel'):
        sys.exit(126)
    state = json.loads((root / 'status.json').read_text())
    if args[1] == 'automatic':
        state['automatic'][args[2]] = args[3] == 'on'
        (root / 'status.json').write_text(json.dumps(state))
        print(json.dumps({'automatic': state['automatic']}))
        sys.exit(0)
    request = {'id':'c'*32, 'state':'done', 'action':args[1], 'createdAt':time.time()}
    if fixture.get('reject'):
        request.update(state='failed',error='The worker rejected this request before starting.')
    elif args[1] == 'stage':
        state = {'state':'ready','transaction':'a'*32,'reviewToken':'b'*64,
            'scope':args[2], 'changeKind':'update', 'changes':'hello: 1 → 2',
            'packageChanges':[{'name':'hello','kind':'updated','before':'1','after':'2'}],
            'highlights':HIGHLIGHTS, 'automatic':state['automatic']}
        if fixture.get('firmware'):
            state['firmware'] = fixture['firmware']
    elif args[1] == 'apply':
        assert args[2:] == ['a'*32, 'b'*64]
        state.update(state='awaiting-boot',reviewToken=None)
    elif args[1] == 'discard':
        state = {'state':'idle', 'automatic':state['automatic']}
    elif args[1] == 'confirm':
        state.update(state='done')
    elif args[1] == 'rollback':
        state.update(state='rolled-back')
    state.update(request=request,installedIdentity='installed-lock')
    (root / 'status.json').write_text(json.dumps(state))
    print(json.dumps({'accepted':True,'requestId':request['id']}))
'''.replace('HIGHLIGHTS', repr(HIGHLIGHTS))

# System units and session actions are recorded, never performed. The user
# manager stays real: the shell's own services use it.
SYSTEMCTL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if '--user' in args:
    os.execv(REAL, [REAL] + args)
with (Path(os.environ['XDG_RUNTIME_DIR']) / 'units.jsonl').open('a') as stream:
    stream.write(json.dumps(args) + '\n')
'''
# Toasts are recorded. One with actions waits, as notify-send does, until the
# test answers with the action the person chose (or two minutes: dismissed).
NOTIFY_SEND = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ['XDG_RUNTIME_DIR'])
with (root / 'notify.jsonl').open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\n')
if any(arg.startswith('--action=') for arg in sys.argv[1:]):
    answer = root / 'notify-answer'
    for _ in range(600):
        if answer.exists():
            print(answer.read_text().strip(), flush=True)
            answer.unlink()
            break
        time.sleep(.2)
'''
SESSION_ACTION = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with (Path(os.environ['XDG_RUNTIME_DIR']) / 'session.jsonl').open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\n')
'''

IPC = '''
    property var updateTestBar: null
    property var updateTestPopout: null
    property var updateTestWindow: null
    // Only shown items count: the review and the status page share names.
    function updateFind(item, name) {
        if (!item || item.visible === false) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = shell.updateFind(child, name);
            if (found) return found;
        }
        return null;
    }
    function updateCount(item, name) {
        if (!item || item.visible === false) return 0;
        let count = item.objectName === name ? 1 : 0;
        for (const child of item.children || []) count += shell.updateCount(child, name);
        return count;
    }
    function updateItem(name) {
        return shell.updateFind(updateTestWindow && updateTestWindow.visible ? updateTestWindow.contentItem : null, name)
            || shell.updateFind(updateTestBar ? updateTestBar.contentItem : null, name)
            || shell.updateFind(updateTestPopout ? updateTestPopout.contentItem : null, name);
    }
    IpcHandler {
        target: "update-test"
        function refresh(): void { Updates.refreshStatus(); Updates.check(); }
        function trigger(name: string): void {
            const item = shell.updateItem(name);
            if (item && item.enabled) item.triggered();
        }
        function toggle(name: string, value: string): void {
            const item = shell.updateItem(name);
            if (item && item.enabled) item.toggled(value === "true");
        }
        function state(): string {
            const primary = shell.updateItem("updatePrimary");
            const title = shell.updateItem("updateTitle");
            const failure = shell.updateItem("updateRequestError");
            const activity = shell.updateItem("updateActivity");
            const elapsed = shell.updateItem("updateElapsed");
            const progress = shell.updateItem("updateProgress");
            const view = shell.updateItem("updateView");
            const wiz = shell.updateItem("updateWiz");
            const notes = shell.updateItem("updateReleaseNotes");
            const chip = shell.updateItem("updateTestIndicator");
            const rect = chip ? chip.mapToItem(null, 0, 0) : null;
            const content = updateTestWindow && updateTestWindow.visible ? updateTestWindow.contentItem : null;
            return JSON.stringify({loaded: Updates.statusLoaded && Updates.sourcesLoaded,
                indicator: Updates.showIndicator, hasUpdates: Updates.hasUpdates,
                state: Updates.deployment.state, error: Updates.error, failure: Updates.requestFailure,
                page: Updates.page, open: Updates.appOpen, window: !!content,
                actions: Updates.actions, scope: Updates.selectedScope, automatic: Updates.automatic,
                popout: Popouts.open, panel: Popouts.currentName,
                title: title ? {text: title.text, color: title.color.toString(), expected: Theme.textHi.toString(),
                    dark: Theme.dark} : null,
                primary: primary ? {label: primary.text, enabled: primary.enabled, amber: primary.attention} : null,
                wiz: wiz ? {pose: wiz.pose, unread: wiz.unread} : null,
                stance: view ? view.wiz.pose : null, celebrated: view ? view.celebrated : null,
                whatsNew: Updates.whatsNew ? Updates.whatsNew.version : null, announced: Updates.announced,
                notes: notes ? notes.text : null, back: !!shell.updateItem("updateBack"),
                failureText: failure ? failure.text : null,
                activity: activity ? activity.text : null, elapsed: elapsed ? elapsed.text : null,
                progress: progress ? progress.Accessible.description : null,
                buildLog: !!shell.updateItem("updateBuildLog"),
                components: shell.updateCount(content, "updateComponent"),
                firmwareDevices: shell.updateCount(content, "updateFirmwareDevice"),
                firmwareRequests: shell.updateCount(content, "updateFirmwareRequest"),
                apps: shell.updateCount(content, "updateApp"),
                details: !!shell.updateItem("updateChanges"),
                automaticToggle: !!shell.updateItem("updateAutomatic"),
                chip: rect ? {x:rect.x+chip.width/2,y:rect.y+chip.height/2} : null});
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
        shell = self.source / 'desktop/quickshell'
        entry = shell / 'shell.qml'
        text = entry.read_text().replace('    id: shell', '    id: shell\n' + IPC, 1)
        text = text.replace('Component.onCompleted: outputName = output ? output.name : ""',
            'Component.onCompleted: { outputName = output ? output.name : ""; shell.updateTestBar = bar; shell.updateTestPopout = updatePopup; }', 1)
        text = text.replace('            BarPopoutWindow {\n                bar: bar',
            '            BarPopoutWindow {\n                id: updatePopup\n                bar: bar', 1)
        assert text.count('    SoftwareUpdateWindow {}\n') == 1
        text = text.replace('    SoftwareUpdateWindow {}\n',
            '    SoftwareUpdateWindow { id: updateWindow; Component.onCompleted: shell.updateTestWindow = updateWindow }\n')
        entry.write_text(text)
        chip = shell / 'Bar/Modules/Updates.qml'
        chip.write_text(chip.read_text().replace('        id: chip', '        id: chip\n        objectName: "updateTestIndicator"', 1))

    def state(self):
        return self.json_call('update-test', 'state')

    def probe(self):
        return self.state()

    def fixture(self, **values):
        path = self.runtime / 'fixture.json'
        value = json.loads(path.read_text()) if path.exists() else {}
        path.write_text(json.dumps(value | values))

    def status(self, **values):
        values.setdefault('automatic', {'prepare': False, 'confirm': True})
        (self.runtime / 'status.json').write_text(json.dumps({'installedIdentity':'installed-lock', **values}))
        self.call('update-test', 'refresh')

    def trigger(self, name):
        self.call('update-test', 'trigger', name)

    def records(self, name):
        path = self.runtime / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def calls(self):
        return self.records('calls.jsonl')

    def units(self):
        return self.records('units.jsonl')

    def toasts(self):
        return self.records('notify.jsonl')

    def pose(self):
        wiz = self.state().get('wiz') or {}
        return wiz.get('pose'), wiz.get('unread')


def process_guard(runtime=None):
    main = subprocess.run(['systemctl','--user','show','quickshell.service','-p','MainPID','--value'], capture_output=True, text=True).stdout.strip()
    pids = set()
    for name in ('qs', '.quickshell-wra'):
        pids.update(subprocess.run(['pgrep','-u',str(os.getuid()),'-x',name],capture_output=True,text=True).stdout.split())
    for pid in pids:
        path = Path('/proc') / pid
        try:
            print('Quickshell', pid, 'MainPID', main, (path/'cmdline').read_bytes(), (path/'cgroup').read_text())
            env = (path/'environ').read_bytes().split(b'\0')
            assert runtime is None or ('XDG_RUNTIME_DIR='+str(runtime)).encode() not in env
        except FileNotFoundError:
            pass
    assert main in ('', '0'), 'Run private shell tests on a host without an active managed desktop'
    if runtime is None:
        assert not pids, 'Another Quickshell is active; preserve it and run this test separately'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--screenshots', type=Path)
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    process_guard()
    with tempfile.TemporaryDirectory(prefix='cxu-') as temporary:
        base = Path(temporary)
        native = base/'native'
        subprocess.run(['cmake','-S',str(ROOT/'desktop/notification-images'),'-B',str(native),'-DBUILD_TESTING=OFF'],check=True,capture_output=True)
        subprocess.run(['cmake','--build',str(native),'--parallel','2'],check=True,capture_output=True)
        session = Session(base, native/'qml')
        session.env.update(CYBEXOS_WELCOME='0', CYBEXOS_ASSISTANT='0')
        session.patch_settings(drawerOverview={'updates':True,'processes':False,'media':False})
        for name, body in (('cybex', FAKE), ('systemctl', SYSTEMCTL.replace('REAL', repr(shutil.which('systemctl')))),
                           ('cybexos-session-action', SESSION_ACTION), ('notify-send', NOTIFY_SEND)):
            (base/'bin'/name).write_text(body)
            (base/'bin'/name).chmod(0o700)
        sources = {'installedIdentity':'installed-lock', 'upstream':{'state':'available','available':'new-revision'},
                   'cybexos':{'state':'unpublished'}}
        session.fixture(sources=sources)
        session.status(state='idle')
        mouse = None
        shot = lambda name: args.screenshots and session.capture(args.screenshots, name)
        try:
            conf = base/'sway.conf'
            conf.write_text('output HEADLESS-1 mode 1440x900\nseat seat0 fallback true\n'
                            'for_window [title="Software Update"] floating enable, move position center\n')
            sway = base/'sway'
            shutil.copyfile(os.environ.get('CYBEXOS_SWAY_BINARY') or shutil.which('sway'), sway)
            sway.chmod(0o700)
            session.start([str(sway),'-c',str(conf)],'sway.log')
            sockets = session.wait(lambda:[p for p in session.runtime.glob('wayland-*') if p.is_socket()],'compositor')
            session.env['WAYLAND_DISPLAY']=sockets[0].name
            session.env['SWAYSOCK']=str(session.wait(lambda:next(session.runtime.glob('sway-ipc.*.sock'),None),'compositor IPC'))
            session.start_shell('qs-first.log')
            session.wait(lambda:session.state().get('loaded') and session.state().get('chip'),'available update indicator')
            assert session.state()['scope']=='upstream', session.state()

            # The menubar indicator opens the app; nothing is requested yet.
            mouse = pointer.VirtualPointer(session.env,1440,900)
            chip=session.state()['chip']
            mouse.move(chip['x'],chip['y'])
            mouse.button(True); mouse.button(False)
            session.wait(lambda:session.state().get('window') and session.state().get('page')=='available'
                and session.state().get('primary'),'Software Update from the menubar')
            assert session.state()['primary']['label']=='Prepare Update', session.state()
            assert not session.state()['popout'], 'the indicator opens a window, not a panel'
            assert not session.calls() and not session.units(), (session.calls(), session.units())
            assert session.state()['error'] == '', session.state()
            for mode in ('dark', 'light', 'dark'):
                session.patch_settings(themeMode=mode)
                session.wait(lambda: (title := session.state().get('title'))
                    and title['dark'] == (mode == 'dark') and title['color'] == title['expected'],
                    mode + ' readable title')
                shot('software-update-available-' + mode + '.png')
            # Something new: Wiz idles with the unread pip; the accent button.
            assert session.pose()==('idle',True) and not session.state()['primary']['amber'], session.state()

            # Checking: Wiz thinks while the sources are checked.
            session.fixture(checkDelay=8)
            session.status(state='idle', installedIdentity='moved-lock')
            session.wait(lambda:session.state().get('page')=='checking','checking for updates')
            assert session.pose()==('thinking',False), session.state()
            shot('software-update-checking.png')
            session.fixture(checkDelay=0)
            session.status(state='idle')
            session.wait(lambda:session.state().get('page')=='available' and session.state().get('loaded'),'checked again')

            # Control Center's Review closes the drawer and opens the same app.
            session.call('updates','close')
            session.wait(lambda:not session.state().get('window'),'closed app')
            mouse.move(100, 700)
            session.call('popouts','open','control')
            session.wait(lambda:session.state().get('panel')=='control','control center')
            session.trigger('overviewUpdateReview')
            session.wait(lambda:session.state().get('window') and not session.state().get('popout'),
                'shared review from control center')
            assert not session.calls(), session.calls()

            session.fixture(cancel=True)
            session.trigger('updatePrimary')
            session.wait(lambda:'cancelled' in session.state().get('failure',''),'authorization cancellation')
            time.sleep(2.2)
            assert 'cancelled' in (session.state()['failureText'] or ''), session.state()
            session.fixture(cancel=False,reject=True)
            session.trigger('updatePrimary')
            session.wait(lambda:'worker rejected' in session.state().get('failure',''),'worker failure')
            session.start_shell('qs-reloaded.log')
            session.wait(lambda:'worker rejected' in session.state().get('failure',''),'durable failure after shell restart')
            session.wait(lambda:session.state().get('window'),'open app restored after shell restart')
            session.call('updates','open')
            session.wait(lambda:'worker rejected' in (session.state().get('failureText') or ''),'durable failure in the app')

            # Real QML presents concurrent compilation truthfully and retains
            # progress/log access after closing and reopening the window.
            telemetry = {'schema':1, 'active':True, 'step':'building',
                'downloads':{'doneBytes':25000000,'expectedBytes':100000000,'active':1,'totalKnown':True},
                'builds':{'done':3,'expected':9,'active':1}, 'components':['window-manager']}
            session.status(state='building',transaction='a'*32,elapsedSeconds=294,progress=telemetry)
            session.wait(lambda:session.state().get('activity')=='Compiling window manager','compilation progress')
            assert session.state()['elapsed']=='Elapsed: 4:54', session.state()
            assert session.pose()==('working',False), session.state()
            assert session.state()['progress']=='In progress' and session.state()['buildLog'], session.state()
            session.call('updates','close')
            session.wait(lambda:not session.state().get('window'),'preparing app closed')
            session.call('updates','open')
            session.wait(lambda:session.state().get('activity')=='Compiling window manager','preparing app reopened')
            telemetry['builds']['active'] = 0
            telemetry['components'] = []
            session.status(state='building',transaction='a'*32,elapsedSeconds=300,progress=telemetry)
            session.wait(lambda:session.state().get('progress')=='25%','measured download progress')
            shot('software-update-progress.png')
            session.status(state='idle')
            session.wait(lambda:session.state().get('page')=='available','preparation fixture reset')

            # Preparation shows the review people read first.
            session.fixture(reject=False)
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('page')=='ready' and session.state().get('components')==3,'readable review')
            state = session.state()
            assert state['apps'] == 1 and state['primary']['label']=='Install Update', state
            assert state['title']['text'] == 'An update is ready to install', state
            assert session.calls()[-1]==['stage','upstream'], session.calls()
            assert not state['details'], 'technical details start collapsed'
            assert state['wiz'] is None, 'the review of what changes has no character'
            shot('software-update-ready.png')
            session.trigger('updatePrimary')
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('page')=='restart','reviewed installation')
            assert sum(call[0]=='apply' for call in session.calls())==1, session.calls()
            assert session.calls()[-1]==['apply','a'*32,'b'*64], session.calls()
            assert session.state()['primary']['label']=='Restart Now', session.state()
            assert not session.state()['indicator']
            assert session.pose()==('needs-input',False) and session.state()['primary']['amber'], session.state()
            # Activation restarts the shell with its changed user unit. The app
            # reopens in the replacement shell and follows the update to its result.
            session.status(state='activating',transaction='a'*32,phase='Activating under supervision')
            session.wait(lambda:session.state().get('page')=='installing','installing')
            assert session.pose()==('working',False), session.state()
            shot('software-update-installing.png')
            session.start_shell('qs-activation.log')
            session.wait(lambda:session.state().get('window') and session.state().get('page')=='installing',
                'app reopened during activation')
            session.status(state='awaiting-boot',transaction='a'*32)
            session.wait(lambda:session.state().get('page')=='restart','result after the shell restart')
            assert session.state()['primary']=={'label':'Restart Now','enabled':True,'amber':True}, session.state()
            shot('software-update-restart.png')
            session.trigger('updatePrimary')
            session.wait(lambda:session.records('session.jsonl')==[['reboot']],'restart requested through the session action')

            # After the restart the signed-in desktop confirms automatically.
            session.status(state='awaiting-login',transaction='a'*32)
            session.wait(lambda:session.state().get('page')=='finishing','automatic confirmation')
            assert session.pose()==('thinking',False), session.state()
            session.wait(lambda:['--no-ask-password','start','--no-block','cybexos-update-confirm.service'] in session.units(),
                'confirmation unit started', timeout=40)
            failed = {'id':'d'*32,'action':'confirm','state':'failed','error':'Hyprland health failed'}
            session.status(state='awaiting-login',transaction='a'*32,request=failed)
            session.wait(lambda:session.state().get('page')=='confirm','failed confirmation asks')
            assert session.state()['primary']['label']=='Keep This Version', session.state()
            assert session.pose()==('needs-input',False) and session.state()['primary']['amber'], session.state()
            shot('software-update-confirm.png')
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('state')=='done','manual confirmation')
            assert session.calls()[-1]==['confirm'], session.calls()
            assert session.units().count(['--no-ask-password','start','--no-block','cybexos-update-confirm.service'])==1
            session.status(state='awaiting-login',transaction='a'*32,automatic={'prepare':False,'confirm':False})
            session.wait(lambda:session.state().get('page')=='confirm','manual confirmation policy')
            assert session.pose()==('listening',False) and not session.state()['primary']['amber'], session.state()
            shot('software-update-confirm-ask.png')
            # A kept change without a new Cybex OS version reports itself with
            # the plain completion toast.
            assert [toast for toast in session.toasts() if toast[-1]=='Everything passed its checks after the restart.'
                and not any(arg.startswith('--action=') for arg in toast)], session.toasts()

            # Kept with the app open: the up-to-date page names the release and
            # offers What's New. Wiz celebrates once, then settles. No toast.
            current = {'upstream':{'state':'current'},'cybexos':{'state':'current'}}
            session.fixture(sources=current)
            toasts = len(session.toasts())
            kept = release('1.0.0-beta.20', '1.0.0-beta.21', 'e'*32)
            session.status(state='awaiting-login', automatic={'prepare':False,'confirm':False}, **kept)
            session.wait(lambda:session.state().get('page')=='confirm' and not session.state().get('hasUpdates'),
                'asked to keep the release')
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('page')=='current'
                and (session.state().get('title') or {}).get('text')=="You're on Cybex OS 1.0.0-beta.21", 'kept release')
            state = session.state()
            assert state['primary']=={'label':"What's New",'enabled':True,'amber':False}, state
            assert state['stance']=='finished', state
            session.wait(lambda:session.state().get('celebrated')=='kept 1.0.0-beta.21','Wiz celebrates the kept release')
            session.wait(lambda:session.pose()==('happy',False),'Wiz settles into happy')
            assert len(session.toasts())==toasts, ('an open app shows the kept release, not a toast', session.toasts()[toasts:])
            record = session.home/'.local/state/cybexos/software-update.json'
            assert json.loads(record.read_text())=={'schema':1,'announced':'1.0.0-beta.21'}, record.read_text()
            shot('software-update-kept.png')

            # What's New: the release notes and important changes, in the app.
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('whatsNew')=='1.0.0-beta.21' and session.state().get('components')==3,
                "What's New")
            state = session.state()
            assert state['title']['text']=="What's new in Cybex OS 1.0.0-beta.21" and state['back'], state
            assert state['stance']=='finished' and 'Wiz' in state['notes'] and 'https://example.com/notes' in state['notes'], state
            assert 'never-fetched' not in state['notes'], 'release notes never load images'
            session.wait(lambda:session.state().get('celebrated')=='whats-new 1.0.0-beta.21' and session.pose()==('happy',False),
                "Wiz celebrates What's New")
            shot('software-update-whats-new.png')
            session.trigger('updateBack')
            session.wait(lambda:not session.state().get('whatsNew') and session.state().get('page')=='current',
                "back from What's New")
            assert session.state()['primary']['label']=="What's New", session.state()

            # Kept while the app is closed: one plain toast, whose action opens
            # What's New. The release is never announced again.
            session.call('updates','close')
            session.wait(lambda:not session.state().get('window'),'closed app')
            later = release('1.0.0-beta.21', '1.0.0-beta.22', 'f'*32)
            session.status(state='awaiting-login', **later)
            session.wait(lambda:session.state().get('state')=='awaiting-login','trial boot of the next release')
            session.status(state='done', **later)
            ready = ['--app-name=Software Update','--icon=cybexos',"--action=default=What's New",
                "--action=whats-new=What's New",'Cybex OS 1.0.0-beta.22 is ready',"See what's new."]
            session.wait(lambda:ready in session.toasts(),'one toast for the kept release')
            assert session.toasts()[toasts:]==[ready], session.toasts()[toasts:]
            assert not session.state()['window'], 'the toast does not open the app by itself'
            (session.runtime/'notify-answer').write_text('whats-new\n')
            session.wait(lambda:session.state().get('window') and session.state().get('whatsNew')=='1.0.0-beta.22'
                and session.state().get('components')==3, "the toast's action opens What's New")
            session.start_shell('qs-announced.log')
            session.wait(lambda:session.state().get('loaded') and session.state().get('announced')=='1.0.0-beta.22'
                and session.state().get('page')=='current', 'announcement remembered across a shell restart')
            time.sleep(2)
            assert session.toasts()[toasts:]==[ready], session.toasts()[toasts:]

            # Up to date: the automatic download choice is a machine policy.
            session.fixture(sources={'upstream':{'state':'current'},'cybexos':{'state':'current'}})
            session.status(state='done',changeKind='update',scope='upstream',transaction='a'*32,
                installedVersion='1.0.0-beta.22',availableVersion='1.0.0-beta.22',notes='')
            session.wait(lambda:session.state().get('page')=='current' and not session.state().get('hasUpdates')
                and (session.state().get('title') or {}).get('text')=='Your system is up to date','up to date')
            assert not session.state()['indicator'] and session.state()['automaticToggle'], session.state()
            assert session.state()['primary'] is None, 'NixOS packages alone have no What\'s New'
            assert session.pose()==('happy',False) and session.state()['stance']=='happy', session.state()
            shot('software-update-current.png')
            session.call('update-test','toggle','updateAutomatic','true')
            session.wait(lambda:session.state().get('automatic',{}).get('prepare') is True,'automatic downloads chosen')
            assert session.calls()[-1]==['automatic','prepare','on'], session.calls()
            # Background work waits for the session to settle; checking now is
            # the person's explicit go-ahead.
            session.fixture(sources=sources)
            session.call('update-test','refresh')
            time.sleep(2)
            assert ['--no-ask-password','start','--no-block','cybexos-update-auto.service'] not in session.units()
            session.wait(lambda:session.state().get('hasUpdates'),'update found')
            session.status(state='done',changeKind='update',automatic={'prepare':True,'confirm':True})
            session.wait(lambda:session.state().get('page')=='available','available again')
            session.call('updates','check')
            session.wait(lambda:['--no-ask-password','start','--no-block','cybexos-update-auto.service'] in session.units(),
                'background preparation requested')
            for _ in range(3):
                session.call('update-test','refresh'); time.sleep(1)
            assert session.units().count(['--no-ask-password','start','--no-block','cybexos-update-auto.service'])==1, session.units()

            session.fixture(sources={'upstream':{'state':'unreachable','error':'offline'},'cybexos':{'state':'unavailable'}})
            session.call('update-test','refresh')
            session.wait(lambda:session.state().get('page')=='problem' and 'offline' in session.state().get('error',''),'discovery error')
            assert not session.state()['indicator']
            assert session.state()['title']['text']=="Couldn't check for updates", session.state()
            assert session.pose()==('sorry',False), session.state()
            session.status(state='recovery-failed',transaction='a'*32,error='Recovery interrupted')
            session.wait(lambda:session.state().get('state')=='recovery-failed','recovery action')
            assert session.state()['primary']['label']=='Try Restoring Again', session.state()
            assert session.pose()==('sorry',False) and session.state()['primary']['amber'], session.state()
            session.status(state='rolled-back',transaction='a'*32,error='Trial boot failed system health')
            session.wait(lambda:session.state().get('state')=='rolled-back','rolled back')
            assert session.state()['primary']['label']=='OK', session.state()
            assert session.pose()==('sorry',False) and session.state()['primary']['amber'], session.state()
            shot('software-update-rolled-back.png')
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('state')=='idle','dismissed')
            assert session.calls()[-1]==['discard','a'*32], session.calls()
            # An interrupted or outdated preparation waits for the person.
            for name in ('stale', 'interrupted'):
                session.status(state=name, transaction='a'*32)
                session.wait(lambda:session.state().get('state')==name and session.state().get('primary'), name)
                assert session.pose()==('needs-input',False) and session.state()['primary']['amber'], session.state()
            shot('software-update-interrupted.png')
            session.status(state='unavailable', available=False)
            session.wait(lambda:session.state().get('page')=='unavailable','updates after installation')
            assert session.pose()==('asleep',False), session.state()
            shot('software-update-unavailable.png')

            # Firmware uses the same review/install flow, including when the
            # Nix sources are current. Device actions stay inside the app.
            device = {'id':'bios', 'name':'System Firmware', 'vendor':'Example',
                'from':'1', 'to':'2', 'needsReboot':True, 'affectsFde':True}
            firmware = {'state':'available', 'devices':[device]}
            session.fixture(sources={'upstream':{'state':'current'},'cybexos':{'state':'current'},
                'firmware':firmware}, firmware=firmware)
            session.status(state='idle')
            session.wait(lambda:session.state().get('page')=='available' and session.state().get('scope')=='firmware',
                'firmware-only update discovered')
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('page')=='ready' and session.state().get('firmwareDevices')==1,
                'firmware in the regular review')
            assert session.state()['primary']['label']=='Install Update', session.state()
            assert session.calls()[-1]==['stage','firmware'], session.calls()
            session.trigger('updatePrimary')
            session.wait(lambda:session.state().get('page')=='restart','firmware uses ordinary install')
            session.status(state='firmware',firmware={**firmware, 'state':'installing', 'current':'bios',
                'percent':42, 'requests':[{'id':'bios','kind':'immediate','message':'Reconnect the device.'}]})
            session.wait(lambda:session.state().get('page')=='installing' and session.state().get('firmwareRequests')==1
                and session.state().get('progress')=='42%', 'firmware progress and instructions inside the app')
            assert session.pose()==('working',False), session.state()
            session.start_shell('qs-firmware.log')
            session.wait(lambda:session.state().get('window') and session.state().get('firmwareRequests')==1,
                'firmware instructions survive shell restart')
            session.status(state='done',firmware={**firmware,'state':'done','needsReboot':True, 'needsShutdown':True})
            session.wait(lambda:session.state().get('page')=='restart' and session.state().get('primary',{}).get('label')=='Shut Down Now',
                'firmware full shutdown requirement')
            assert not session.state()['indicator'], session.state()
            assert session.pose()==('needs-input',False) and session.state()['primary']['amber'], session.state()

            # Closing the app forgets it: neither a later shell restart nor
            # another session's marker reopens it.
            marker = session.runtime/'cybexos-software-update-open'
            assert marker.read_text().strip(), 'the open app is remembered for this session'
            session.call('updates','close')
            session.wait(lambda:not session.state().get('window'),'closed app')
            assert marker.read_text()=='', repr(marker.read_text())
            session.start_shell('qs-closed.log')
            time.sleep(2)
            assert not session.state()['open'], session.state()
            marker.write_text('another-session\n')
            session.start_shell('qs-other-session.log')
            time.sleep(2)
            assert not session.state()['open'], session.state()
            for log in session.logs:
                if log.name.startswith('qs-'):
                    errors=[line for line in log.read_text(errors='replace').splitlines() if welcome.ERRORS.search(line)]
                    assert not errors, '\n'.join(errors)
            print('PASS: menubar and Control Center open the app, authorization cancellation, durable worker errors, '
                  'shell restart, readable review, install once, reopening after the activation restart, restart, '
                  'automatic and manual confirmation, Wiz\'s pose on every status page, a kept release with Wiz '
                  'celebrating and What\'s New, one toast whose action opens What\'s New and is never repeated, '
                  'NixOS packages alone just up to date, '
                  'automatic download policy and single background request, discovery error, recovery, dismissal '
                  'firmware-only review, graphical device progress, instructions and shutdown requirement, '
                  'and no reopening once closed or in another session')
        except BaseException:
            for log in session.logs:
                if log.exists(): print(log.name, log.read_text(errors='replace')[-16000:])
            raise
        finally:
            if mouse: mouse.close()
            session.stop()
            for pid in welcome.own_processes(session.runtime):
                try: os.kill(pid,15)
                except ProcessLookupError: pass
            time.sleep(.2)
            process_guard(session.runtime)
            assert not welcome.own_processes(session.runtime)


if __name__=='__main__':
    main()
