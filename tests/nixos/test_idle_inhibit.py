"""Production SysInfo in a private, windowless Quickshell with fake inhibitors.

No live desktop, logind inhibitor, power preference or user service is changed.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
QS = shutil.which('qs')


@unittest.skipUnless(QS, 'Quickshell required for the real QML regression')
class IdleInhibitTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cy-idle.', dir='/tmp')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.shell = self.base / 'shell'
        common = self.shell / 'Common'
        common.mkdir(parents=True)
        for name in ('SysInfo.qml', 'ProcHelpers.js', 'SettingsHelpers.js', 'SysInfoHelpers.js'):
            shutil.copy2(ROOT / 'desktop/quickshell/Common' / name, common / name)
        (common / 'qmldir').write_text(''.join(
            f'singleton {name} {name}.qml\n' for name in ('SysInfo', 'Settings', 'Startup', 'Battery')))
        (common / 'Settings.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool loaded: true
    property string idleInhibitMode: Quickshell.env("TEST_IDLE_MODE") || "off"
    property double idleInhibitUntilMs: Number(Quickshell.env("TEST_IDLE_UNTIL"))
    property bool nightLight: false
    property int warmth: 4000
    property string lastPersistedText: "{}"
    property var modOpts: ({indicators: {
        idleStartup: Quickshell.env("TEST_IDLE_STARTUP") || "off",
        idleDefaultMode: "always", nightLightStartup: "off"
    }})
    function set(key, value) { this[key] = value; }
}
''')
        (common / 'Startup.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool ready: true
    property bool firstStart: Quickshell.env("TEST_IDLE_RELOAD") !== "1"
}
''')
        (common / 'Battery.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool isLaptop: true
    property bool pluggedIn: true
}
''')
        (self.shell / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "Common"
ShellRoot {
    readonly property bool startupApplied: SysInfo.startupApplied
    IpcHandler {
        target: "idle-test"
        function status(): string {
            return JSON.stringify({mode: SysInfo.idleInhibitMode,
                enabled: SysInfo.idleInhibited, effective: SysInfo.idleInhibitEffective,
                pending: SysInfo.idleInhibitPending, error: SysInfo.idleInhibitError,
                lifecycle: SysInfo.idleInhibitLifecycle, applied: SysInfo.startupApplied});
        }
        function mode(value: string): void { SysInfo.setIdleInhibitMode(value); }
        function savedMode(value: string): void { Settings.set("idleInhibitMode", value); }
        function unplug(): void { Battery.pluggedIn = false; }
        function expire(): void { Settings.set("idleInhibitUntilMs", Date.now() + 100); }
        function reenable(): void {
            SysInfo.setIdleInhibitMode("off");
            SysInfo.setIdleInhibitMode("always");
        }
    }
}
''')
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.active = self.base / 'active'
        self.active.mkdir()
        inhibitor = self.bin / 'systemd-inhibit'
        inhibitor.write_text(f'#!{sys.executable}\n' + '''import os
from pathlib import Path
import signal
import time
base = Path(os.environ['TEST_IDLE_ROOT'])
active = base / 'active' / str(os.getpid())
def stop(*args):
    active.unlink(missing_ok=True)
    raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
active.write_text(' '.join(__import__('sys').argv[1:]))
with (base / 'starts').open('a') as log:
    log.write(str(os.getpid()) + '\\n')
while True:
    time.sleep(1)
''')
        inhibitor.chmod(0o755)
        # Any accidental service restart is intercepted too.
        systemctl = self.bin / 'systemctl'
        systemctl.write_text(f'#!{sys.executable}\nraise SystemExit(0)\n')
        systemctl.chmod(0o755)
        runtime = self.base / 'xdg'
        runtime.mkdir(mode=0o700)
        self.environment = os.environ | {
            'HOME': str(self.base / 'home'), 'XDG_RUNTIME_DIR': str(runtime),
            'XDG_CONFIG_HOME': str(self.base / 'config'),
            'XDG_DATA_HOME': str(self.base / 'data'),
            'XDG_CACHE_HOME': str(self.base / 'cache'),
            'XDG_STATE_HOME': str(self.base / 'state'),
            'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
            'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
            'TEST_IDLE_ROOT': str(self.base),
        }
        for name in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE',
                     'DBUS_SESSION_BUS_ADDRESS'):
            self.environment.pop(name, None)

    def launch(self, *, mode='off', policy='off', reload=False, until=0):
        environment = self.environment | {
            'TEST_IDLE_MODE': mode, 'TEST_IDLE_STARTUP': policy,
            'TEST_IDLE_RELOAD': '1' if reload else '0', 'TEST_IDLE_UNTIL': str(until),
        }
        self.log = tempfile.TemporaryFile(mode='w+')
        self.addCleanup(self.log.close)
        self.process = subprocess.Popen([QS, '-p', str(self.shell)], env=environment,
                                        stdout=self.log, stderr=subprocess.STDOUT,
                                        start_new_session=True)
        self.addCleanup(self.stop)
        return self.wait(lambda value: value['applied'])

    def stop(self):
        # Only the private fixture's process group, including its fake helper.
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait(timeout=5)
        for path in self.active.iterdir():
            self.assertFalse(Path('/proc', path.name).exists(), 'Fixture helper leaked: ' + path.name)

    def call(self, method, *arguments):
        return subprocess.run([QS, 'ipc', '--pid', str(self.process.pid), 'call',
                               'idle-test', method, *arguments], env=self.environment,
                              capture_output=True, text=True, timeout=5)

    def wait(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            result = self.call('status')
            if result.returncode == 0:
                last = json.loads(result.stdout)
                if predicate(last):
                    return last
            if self.process.poll() is not None:
                break
            time.sleep(.03)
        self.log.seek(0)
        self.fail(f'Idle state did not settle: {last}\n{self.log.read()}')

    def assert_off(self):
        state = self.wait(lambda value: value['mode'] == 'off'
                          and value['lifecycle'] == 'stopped' and not list(self.active.iterdir()))
        self.assertFalse(state['enabled'])
        self.assertFalse(state['effective'])
        self.assertFalse(state['pending'])
        self.assertEqual(state['error'], '')

    def assert_on(self, mode='always'):
        state = self.wait(lambda value: value['mode'] == mode and value['effective']
                          and value['lifecycle'] == 'running' and not value['pending']
                          and len(list(self.active.iterdir())) == 1)
        self.assertTrue(state['enabled'])
        self.assertFalse(state['pending'])
        self.assertEqual(state['error'], '')

    def test_off_startup_does_not_launch_an_inhibitor(self):
        self.launch()
        self.assert_off()
        self.assertFalse((self.base / 'starts').exists())

    def test_off_startup_clears_a_remembered_request(self):
        self.launch(mode='always')
        self.assert_off()
        self.assertFalse((self.base / 'starts').exists())

    def test_toggles_external_edits_expiry_and_unplug_release_the_inhibitor(self):
        self.launch(policy='on')
        self.assert_on()
        for method in ('mode', 'savedMode'):
            with self.subTest(method=method):
                self.invoke(method, 'off')
                self.assert_off()
                self.invoke(method, 'always')
                self.assert_on()
        self.invoke('mode', '30m')
        self.assert_on('30m')
        self.invoke('expire')
        self.assert_off()
        self.invoke('mode', 'unplugged')
        self.assert_on('unplugged')
        self.invoke('unplug')
        self.assert_off()

    def invoke(self, method, *arguments):
        result = self.call(method, *arguments)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reenabled_request_survives_an_in_flight_stop(self):
        self.launch(policy='on')
        self.assert_on()
        self.invoke('reenable')
        self.assert_on()
        self.invoke('mode', 'off')
        self.assert_off()

    def test_shell_reload_resumes_an_unexpired_request(self):
        self.launch(mode='1h', reload=True, until=int(time.time() * 1000) + 60000)
        self.assert_on('1h')

    def test_shell_reload_drops_an_expired_request(self):
        self.launch(mode='30m', reload=True, until=1)
        self.assert_off()
        self.assertFalse((self.base / 'starts').exists())


if __name__ == '__main__':
    unittest.main()
