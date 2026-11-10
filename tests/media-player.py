#!/usr/bin/env python3
"""Exercise the menubar music player (2026-11 redesign) in the real shell,
under a private headless Sway and D-Bus session. Never touches a session, the
user's config or the host.

Run through nix develop, e.g.
  nix develop -c python3 -B tests/media-player.py

Three fake MPRIS players share the session bus with the shell: a music app
that plays (with covers), a browser YouTube web app that is paused on a live
stream (no length, no seeking, no shuffle or repeat), and a video player with
no cover. Real pointer input drives the chip's play button, a middle click,
the wheel (which sets the player's own volume, here over MPRIS since the test
has no PipeWire), the panel's seek bar, shuffle, repeat and its list of other
players; the keyboard drives the panel's shortcuts. Every action is checked
against what the fake player received. Only the PNG screenshots survive, and
only in CYBEXOS_MEDIA_SCREENSHOTS when it is set.
"""
from __future__ import annotations
import atexit
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time

from PIL import Image, ImageChops, ImageDraw

import shell_fonts

ROOT = Path(__file__).resolve().parents[1]
KEEP = os.environ.get('CYBEXOS_MEDIA_SCREENSHOTS')
OUTPUT = Path(KEEP) if KEEP else Path(tempfile.mkdtemp(prefix='cxm-'))
if not KEEP:
    atexit.register(shutil.rmtree, OUTPUT, True)
QML_ERRORS = re.compile(r'TypeError|ReferenceError|Binding loop|is not a type|Type \w+ unavailable'
                        r'|Cannot assign|Unable to assign|Illegal method name|Failed to load configuration'
                        r'|Cannot anchor|Cannot specify anchors|Duplicate|non-existent')

_spec = importlib.util.spec_from_file_location('shortcut_editor', Path(__file__).with_name('shortcut-editor.py'))
EDITOR = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(EDITOR)
_spec = importlib.util.spec_from_file_location('assistant_overlay', Path(__file__).with_name('assistant-overlay.py'))
OVERLAY = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(OVERLAY)


class Pointer(OVERLAY.VirtualPointer):
    """The overlay test's virtual pointer, with any button and the wheel."""
    BUTTONS = {'left': 0x110, 'right': 0x111, 'middle': 0x112}

    def press(self, name, pressed):
        self.send(5, 2, int(time.monotonic() * 1000) & 0xffffffff, self.BUTTONS[name], int(pressed))
        self.send(5, 4)
        time.sleep(0.04)

    def scroll(self, steps):
        # axis_source(wheel), axis_discrete(vertical, 15 units and one step
        # per notch; negative is up), frame. Qt reports this pointer with no
        # device type, which a WheelHandler's default filter drops.
        stamp = int(time.monotonic() * 1000) & 0xffffffff
        self.send(5, 5, 0)
        self.frame(5, 7, struct.pack('IIii', stamp, 0, round(15 * steps * 256), steps))
        self.send(5, 4)
        time.sleep(0.04)

TEST_IPC = '''
    IpcHandler {
        target: "media-test"
        function state(): string {
            const p = Media.player;
            const a = Popouts.anchorRect;
            return JSON.stringify({ player: p ? p.identity : "", playing: Media.playing,
                pinned: Media.pinnedKey, others: Media.others.map(o => o.identity),
                volume: Media.volume, volumeAvailable: Media.volumeAvailable,
                position: Media.position, length: Media.length, title: p ? p.trackTitle : "",
                shuffle: p ? p.shuffle : false, loop: p ? p.loopState : -1,
                popout: Popouts.open ? Popouts.currentName : "", anchor: [a.x, a.y, a.width, a.height],
                art: p ? p.trackArtUrl : "",
                osd: Osd.active ? Osd.kind : "" });
        }
    }
'''

# A minimal MPRIS player per bus name. Every call the shell makes is logged
# as one JSON line, so the test checks what the player was actually asked.
FAKE_PLAYERS = r'''
import json, sys, time
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
LOG = sys.argv[1]
SPECS = json.loads(sys.argv[2])
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"


class Player(dbus.service.Object):
    def __init__(self, bus, spec):
        self.spec = spec
        self.bus_name = dbus.service.BusName("org.mpris.MediaPlayer2." + spec["bus"], bus)
        super().__init__(self.bus_name, "/org/mpris/MediaPlayer2")
        self.status = spec["status"]
        self.track = 0
        self.volume = spec.get("volume", 0.6)
        self.shuffle = False
        self.loop = "None"
        self.pos = spec.get("position", 0) * 1_000_000
        self.stamp = time.monotonic()

    def log(self, call, **extra):
        with open(LOG, "a") as handle:
            handle.write(json.dumps({"player": self.spec["bus"], "call": call, **extra}) + "\n")

    def position(self):
        if self.status == "Playing":
            return int(self.pos + (time.monotonic() - self.stamp) * 1_000_000)
        return int(self.pos)

    def settle(self, to=None):
        self.pos = self.position() if to is None else max(0, to)
        self.stamp = time.monotonic()

    def metadata(self):
        track = self.spec["tracks"][self.track]
        data = {"mpris:trackid": dbus.ObjectPath("/track/%d" % self.track),
                "xesam:title": track["title"],
                "xesam:artist": dbus.Array(track.get("artist", []), signature="s"),
                "xesam:album": track.get("album", "")}
        if track.get("length"):
            data["mpris:length"] = dbus.Int64(track["length"] * 1_000_000)
        if track.get("art"):
            data["mpris:artUrl"] = track["art"]
        if track.get("url"):
            data["xesam:url"] = track["url"]
        return dbus.Dictionary(data, signature="sv")

    def player_props(self):
        props = {"PlaybackStatus": self.status, "Rate": dbus.Double(1.0), "Metadata": self.metadata(),
                 "Volume": dbus.Double(self.volume), "Position": dbus.Int64(self.position()),
                 "MinimumRate": dbus.Double(1.0), "MaximumRate": dbus.Double(1.0),
                 "CanGoNext": True, "CanGoPrevious": True, "CanPlay": True, "CanPause": True,
                 "CanSeek": self.spec.get("seek", True), "CanControl": True}
        if self.spec.get("modifiers", True):
            props["Shuffle"] = self.shuffle
            props["LoopStatus"] = self.loop
        return props

    def root_props(self):
        return {"CanQuit": False, "CanRaise": False, "HasTrackList": False,
                "Identity": self.spec["identity"], "DesktopEntry": self.spec.get("entry", ""),
                "SupportedUriSchemes": dbus.Array([], signature="s"),
                "SupportedMimeTypes": dbus.Array([], signature="s")}

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.GetAll(interface)[name]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self.root_props() if interface == ROOT_IFACE else self.player_props(),
                               signature="sv")

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, interface, name, value):
        if name == "Volume":
            self.volume = float(value)
            value = round(float(value), 3)
        elif name == "Shuffle":
            self.shuffle = bool(value)
            value = bool(value)
        elif name == "LoopStatus":
            self.loop = str(value)
            value = str(value)
        self.log("Set", name=name, value=value)
        self.changed(name)

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    @dbus.service.signal(PLAYER_IFACE, signature="x")
    def Seeked(self, position):
        pass

    def changed(self, *names):
        props = self.player_props()
        self.PropertiesChanged(PLAYER_IFACE, dbus.Dictionary({n: props[n] for n in names}, signature="sv"),
                               dbus.Array([], signature="s"))

    def set_status(self, status):
        self.settle()
        self.status = status
        self.changed("PlaybackStatus")

    @dbus.service.method(PLAYER_IFACE)
    def PlayPause(self):
        self.log("PlayPause")
        self.set_status("Paused" if self.status == "Playing" else "Playing")

    @dbus.service.method(PLAYER_IFACE)
    def Play(self):
        self.log("Play")
        self.set_status("Playing")

    @dbus.service.method(PLAYER_IFACE)
    def Pause(self):
        self.log("Pause")
        self.set_status("Paused")

    @dbus.service.method(PLAYER_IFACE)
    def Stop(self):
        self.log("Stop")
        self.set_status("Stopped")

    def skip(self, step):
        self.track = (self.track + step) % len(self.spec["tracks"])
        self.settle(0)
        self.status = "Playing"
        self.changed("Metadata", "PlaybackStatus")
        self.Seeked(dbus.Int64(0))

    @dbus.service.method(PLAYER_IFACE)
    def Next(self):
        self.log("Next")
        self.skip(1)

    @dbus.service.method(PLAYER_IFACE)
    def Previous(self):
        self.log("Previous")
        self.skip(-1)

    @dbus.service.method(PLAYER_IFACE, in_signature="x")
    def Seek(self, offset):
        self.log("Seek", offset=int(offset) // 1_000_000)
        self.settle(self.position() + int(offset))
        self.Seeked(dbus.Int64(self.position()))

    @dbus.service.method(PLAYER_IFACE, in_signature="ox")
    def SetPosition(self, track, position):
        self.log("SetPosition", position=int(position) // 1_000_000)
        self.settle(int(position))
        self.Seeked(dbus.Int64(self.position()))

    @dbus.service.method(PLAYER_IFACE, in_signature="s")
    def OpenUri(self, uri):
        pass

    @dbus.service.method(ROOT_IFACE)
    def Raise(self):
        self.log("Raise")

    @dbus.service.method(ROOT_IFACE)
    def Quit(self):
        pass


# One connection each: a connection serves one object per path.
players = [Player(dbus.SessionBus(private=True), spec) for spec in SPECS]
GLib.MainLoop().run()
'''


def cover(path: Path, top: tuple, bottom: tuple, sun: tuple | None = None):
    image = Image.new('RGB', (256, 256))
    draw = ImageDraw.Draw(image)
    for y in range(256):
        t = y / 255
        draw.line([(0, y), (255, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    if sun:
        draw.ellipse((150, 50, 210, 110), fill=sun)
    image.save(path)
    return 'file://' + str(path)


def main():
    for executable in ('qs', 'sway', 'grim', 'wtype', 'cmake', 'node', 'dbus-send', 'swaymsg'):
        if not shutil.which(executable):
            raise SystemExit(f'{executable} is required; use nix develop')
    lua = next((name for name in (os.environ.get('CYBEXOS_TEST_LUA'), 'lua', 'lua5.4', 'luajit')
                if name and shutil.which(name)), None)
    if not lua:
        raise SystemExit('Lua is required; use nix develop')
    EDITOR.process_guard()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    processes = []
    with tempfile.TemporaryDirectory(prefix='p-', dir=OUTPUT) as temporary:
        base = Path(temporary)
        runtime, home = base / 'run', base / 'home'
        runtime.mkdir(mode=0o700)
        (runtime / 'cybexos').mkdir()
        (home / '.config/cybexos/hypr').mkdir(parents=True)
        # CYBEXOS_MEDIA_THEME=light takes the same screenshots in the light theme.
        (home / '.config/cybexos/shell.json').write_text(json.dumps({
            'v': 33, 'wall': '', 'assistantShown': False,
            'themeMode': os.environ.get('CYBEXOS_MEDIA_THEME', 'dark')}))
        shell = base / 'runtime/quickshell'
        shutil.copytree(ROOT / 'desktop/quickshell', shell)
        native = base / 'native'
        with (base / 'native.log').open('w') as build_log:
            subprocess.run(['cmake', '-S', str(ROOT / 'desktop/notification-images'), '-B', str(native),
                            '-DBUILD_TESTING=OFF'], stdout=build_log, stderr=subprocess.STDOUT, check=True)
            subprocess.run(['cmake', '--build', str(native), '--parallel', '2'],
                           stdout=build_log, stderr=subprocess.STDOUT, check=True)
        entry = shell / 'shell.qml'
        source = entry.read_text()
        source = source.replace('    id: shell', '    id: shell' + TEST_IPC, 1)
        assert 'media-test' in source
        entry.write_text(source)

        stub = subprocess.run(['node', '-e', "process.stdout.write(require(process.argv[1]).stub)",
                               str(ROOT / 'tests/quickshell/keybindings-support.cjs')],
                              capture_output=True, text=True, check=True).stdout
        resolver = base / 'resolve.lua'
        resolver.write_text(f'package.path = {json.dumps(str(ROOT / "desktop/hypr/?.lua"))} .. ";" .. package.path\n'
                            'package.preload.features = function() return {} end\n'
                            + stub + "\nrequire('bindings')\nrequire('keybinding_preferences')\n")
        (base / 'bin').mkdir()
        hyprctl = base / 'bin/hyprctl'
        hyprctl.write_text(EDITOR.FAKE_HYPRCTL)
        hyprctl.chmod(0o700)

        covers = base / 'covers'
        covers.mkdir()
        specs = [
            {'bus': 'spotify', 'identity': 'Spotify', 'entry': 'spotify', 'status': 'Playing', 'volume': 0.6,
             'position': 102, 'tracks': [
                 {'title': 'Glass Harbour', 'artist': ['Northbound Lights'], 'album': 'Low Tide Radio', 'length': 238,
                  'art': cover(covers / 'c1.png', (255, 122, 89), (59, 29, 110), (255, 210, 122))},
                 {'title': 'Paper Satellites Over the Old Observatory', 'artist': ['Mira Okonkwo'],
                  'album': 'Field Recordings, Vol. 2', 'length': 301,
                  'art': cover(covers / 'c2.png', (127, 209, 255), (27, 31, 58))},
                 {'title': 'Salt Road', 'artist': ['Hollis Fern'], 'album': 'Shoreline', 'length': 196,
                  'art': cover(covers / 'c3.png', (232, 226, 208), (150, 140, 110))}]},
            {'bus': 'chromium.instance4242', 'identity': 'Google Chrome', 'entry': 'google-chrome', 'status': 'Paused',
             'seek': False, 'modifiers': False, 'volume': 1.0, 'tracks': [
                 {'title': 'Lo-fi beats to refactor to (24/7 stream)', 'artist': ['Quiet Desk'],
                  'url': 'https://www.youtube.com/watch?v=live',
                  'art': cover(covers / 'c4.png', (159, 216, 200), (22, 60, 67))}]},
            {'bus': 'mpv', 'identity': 'mpv', 'entry': 'mpv', 'status': 'Paused', 'modifiers': False,
             'position': 1290, 'tracks': [
                 {'title': 'lecture-03-distributed-systems.mkv', 'length': 3412}]},
        ]
        calls_log = base / 'calls.jsonl'
        players = base / 'players.py'
        players.write_text(FAKE_PLAYERS)

        env = {**os.environ, 'HOME': str(home), 'XDG_RUNTIME_DIR': str(runtime),
               'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_DATA_HOME': str(home / '.local/share'),
               'XDG_STATE_HOME': str(home / '.local/state'), 'XDG_CACHE_HOME': str(home / '.cache'),
               'QT_QPA_PLATFORM': 'wayland', 'WLR_BACKENDS': 'headless',
               'WLR_RENDERER': 'pixman', 'WLR_LIBINPUT_NO_DEVICES': '1', 'CYBEXOS_ASSISTANT': '0',
               'CYBEXOS_CONNECTED_WIDGETS': '0', 'CYBEXOS_DEVELOPER_TOOLS': '0', 'CYBEXOS_WELCOME': '0',
               'CYBEXOS_LANG': os.environ.get('CYBEXOS_LANG', 'en'),
               'CYBEXOS_TEST_LUA': shutil.which(lua), 'CYBEXOS_TEST_RESOLVER': str(resolver),
               'PATH': str(base / 'bin') + os.pathsep + os.environ['PATH'],
               'QT_PLUGIN_PATH': subprocess.check_output(['qtpaths', '--query', 'QT_INSTALL_PLUGINS'], text=True).strip(),
               'QML_IMPORT_PATH': str(native / 'qml') + ':' + os.environ.get('CYBEXOS_QML_IMPORT_PATH', ''),
               'PYTHONDONTWRITEBYTECODE': '1', 'GSETTINGS_BACKEND': 'memory',
               **shell_fonts.fontconfig(base),
               # OpenGL on llvmpipe: the software backend draws no MultiEffect,
               # which is what rounds and tints every cover.
               **OVERLAY.opengl()}
        for name in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'SWAYSOCK',
                     'DBUS_SESSION_BUS_ADDRESS', 'XCURSOR_THEME', 'XCURSOR_SIZE', 'QT_QUICK_BACKEND'):
            env.pop(name, None)

        def start(argv, log):
            handle = (base / log).open('w')
            proc = subprocess.Popen(argv, env=env, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
            handle.close()
            processes.append(proc)
            return proc

        def ipc(target, method, *args):
            try:
                result = subprocess.run(['qs', 'ipc', '-p', str(shell), 'call', target, method, *args],
                                        env=env, capture_output=True, text=True, timeout=10)
            except subprocess.TimeoutExpired:
                return 'ipc-timeout'
            return result.stdout.strip() if result.returncode == 0 else 'ipc-unavailable'

        def state():
            try:
                return json.loads(ipc('media-test', 'state'))
            except json.JSONDecodeError:
                return {}

        def wait(predicate, label, seconds=20):
            until = time.monotonic() + seconds
            while time.monotonic() < until:
                value = predicate()
                if value:
                    return value
                time.sleep(0.15)
            raise AssertionError(f'Timeout: {label}\n{json.dumps(state(), indent=1)}\n{calls()[-12:]}')

        def calls():
            if not calls_log.exists():
                return []
            return [json.loads(line) for line in calls_log.read_text().splitlines()]

        def called(player, call, **extra):
            return any(c['player'] == player and c['call'] == call
                       and all(c.get(k) == v for k, v in extra.items()) for c in calls())

        pointer = None

        def click(x, y, button='left'):
            pointer.move(x, y)
            time.sleep(0.25)
            pointer.press(button, True)
            pointer.press(button, False)
            time.sleep(0.4)

        def hover(x, y):
            pointer.move(x, y)
            time.sleep(0.6)

        def keys(*argv):
            subprocess.run(['wtype', *argv], env=env, check=True, capture_output=True)
            time.sleep(0.4)

        def grab(name=None, region=None):
            target = base / 'shot.png' if name is None else OUTPUT / name
            argv = ['grim'] + (['-g', region] if region else []) + [str(target)]
            subprocess.run(argv, env=env, check=True, timeout=10)
            return target

        try:
            (base / 'sway.conf').write_text('output HEADLESS-1 mode 1440x900\nseat seat0 fallback true\n'
                                            'output * bg #3a3550 solid_color\n')
            sway_binary = base / 'sway'
            shutil.copyfile(os.environ.get('CYBEXOS_SWAY_BINARY') or shutil.which('sway'), sway_binary)
            sway_binary.chmod(0o700)
            start([str(sway_binary), '-c', str(base / 'sway.conf')], 'sway.log')
            sockets = wait(lambda: [p for p in runtime.glob('wayland-*') if p.is_socket()], 'Sway')
            env['WAYLAND_DISPLAY'] = sockets[0].name
            env['SWAYSOCK'] = str(wait(lambda: next(runtime.glob('sway-ipc.*.sock'), None), 'Sway IPC'))
            bus_file = base / 'bus'
            dbus = ['dbus-run-session']
            if env.get('CYBEXOS_DBUS_SESSION_CONFIG'):
                dbus += ['--config-file', env['CYBEXOS_DBUS_SESSION_CONFIG']]
            start([*dbus, '--', 'sh', '-c',
                   'printf %s "$DBUS_SESSION_BUS_ADDRESS" > "$1"; python3 "$2" "$3" "$4" & exec qs --no-color -p "$5"',
                   'sh', str(bus_file), str(players), str(calls_log), json.dumps(specs), str(shell)], 'qs.log')
            start(['wtype', '-s', '600000'], 'seat-keyboard.log')
            bus = wait(lambda: bus_file.exists() and bus_file.read_text(), 'the session bus')
            pointer = Pointer(env, 1440, 900)

            def player_call(name, method):
                subprocess.run(['dbus-send', '--session', '--type=method_call',
                                '--dest=org.mpris.MediaPlayer2.' + name, '/org/mpris/MediaPlayer2',
                                'org.mpris.MediaPlayer2.Player.' + method],
                               env={**env, 'DBUS_SESSION_BUS_ADDRESS': bus}, check=True, capture_output=True)

            # The playing app is the shell's player; the others wait in the list.
            first = wait(lambda: (s := state()).get('player') == 'Spotify' and len(s['others']) == 2 and s,
                         'the playing player and two others')
            assert first['playing'] and sorted(first['others']) == ['Google Chrome', 'mpv'], first
            assert first['volumeAvailable'] and abs(first['volume'] - 0.6) < 0.01, first
            # The position moves on its own while playing.
            before = first['position']
            wait(lambda: state()['position'] >= before + 1.5, 'the position advancing')

            # Where the chip is: the panel's anchor.
            ipc('popouts', 'open', 'media')
            opened = wait(lambda: (s := state())['popout'] == 'media' and s['anchor'][2] > 0 and s, 'the panel')
            ipc('popouts', 'close')
            wait(lambda: state()['popout'] == '', 'the panel closed')
            ax, ay, aw, ah = opened['anchor']
            chip_y = ay + ah / 2
            play = (ax + aw - 3 - 12, chip_y)
            body = (ax + 40, chip_y)
            hover(700, 600)
            time.sleep(1)
            grab('01-chip-playing.png', f'0,0 {round(ax + aw + 80)}x40')
            # The chip never changes width under the pointer.
            hover(*body)
            ipc('popouts', 'close')
            time.sleep(0.6)
            grab('02-chip-hover.png', f'0,0 {round(ax + aw + 80)}x40')
            hover(700, 600)

            # Its button plays and pauses without opening the panel.
            click(*play)
            wait(lambda: called('spotify', 'Pause') and not state()['playing'], 'paused from the chip')
            assert state()['popout'] == '', 'the play button opened the panel'
            hover(700, 600)
            time.sleep(1)
            grab('03-chip-paused.png', f'0,0 {round(ax + aw + 80)}x40')
            # A middle click skips, and the next track plays.
            click(*body, button='middle')
            wait(lambda: called('spotify', 'Next') and state()['title'].startswith('Paper Satellites'),
                 'next track from a middle click')
            assert state()['playing'] and state()['popout'] == ''
            time.sleep(0.8)
            grab('04-chip-next-long-title.png', f'0,0 {round(ax + aw + 160)}x40')
            # The wheel sets this player's own volume and shows whose it is.
            hover(*body)
            pointer.scroll(-1)
            wait(lambda: called('spotify', 'Set', name='Volume', value=0.65), 'volume up from the wheel')
            wait(lambda: state()['osd'] == 'player', 'the player volume OSD')
            grab('05-osd-player-volume.png')

            # A click on the chip opens the panel.
            hover(700, 600)
            time.sleep(1.6)
            empty = Image.open(grab()).convert('RGB')
            click(*body)
            wait(lambda: state()['popout'] == 'media', 'the panel from the chip')
            time.sleep(1.2)
            shot = Image.open(grab('06-panel.png')).convert('RGB')
            box = ImageChops.difference(empty.crop((0, 40, 1440, 900)), shot.crop((0, 40, 1440, 900))).getbbox()
            assert box, 'the panel did not draw'
            left, top, right, bottom = box[0], box[1] + 40, box[2], box[3] + 40
            width = right - left
            centre = left + width / 2
            shot.crop((max(0, left - 20), 0, min(1440, right + 20), min(900, bottom + 20))).save(OUTPUT / '06-panel.png')

            # Seek: hovering shows the time, a click seeks there.
            track_y = top + 44 + 104 + 24
            hover(left + 14 + (width - 28) * 0.5, track_y)
            grab('07-panel-seek-hover.png', f'{left - 20},0 {width + 40}x{bottom + 20}')
            click(left + 14 + (width - 28) * 0.5, track_y)
            wait(lambda: any(c['call'] == 'SetPosition' and abs(c['position'] - 150) <= 4 for c in calls()),
                 'a seek to the middle of the track')
            # Shuffle and repeat, either side of the transport.
            transport_y = top + 44 + 104 + 52 + 34
            click(centre - 110, transport_y)
            wait(lambda: called('spotify', 'Set', name='Shuffle', value=True) and state()['shuffle'], 'shuffle on')
            click(centre + 110, transport_y)
            click(centre + 110, transport_y)
            wait(lambda: called('spotify', 'Set', name='LoopStatus', value='Track'), 'repeat one track')
            # The volume row is this player's.
            volume_y = transport_y + 34 + 20
            click(left + 14 + 36 + 6 + 10, volume_y)
            wait(lambda: any(c['call'] == 'Set' and c.get('name') == 'Volume' and c['value'] < 0.2
                             for c in calls()), 'the volume slider')
            hover(centre, transport_y)
            time.sleep(0.6)
            grab('08-panel-modifiers.png', f'{left - 20},0 {width + 40}x{bottom + 20}')

            # The keyboard: arrows seek, Shift skips, Space plays and pauses.
            # The volume slider took focus with the click and keeps its own
            # arrows, so Tab on to the list first.
            keys('-k', 'Tab')
            keys('-k', 'Right')
            wait(lambda: called('spotify', 'SetPosition') and len([c for c in calls()
                 if c['call'] == 'SetPosition']) >= 2, 'Right seeks forward')
            keys('-M', 'shift', '-k', 'Right', '-m', 'shift')
            wait(lambda: len([c for c in calls() if c['call'] == 'Next']) >= 2, 'Shift+Right skips')
            # Space on a listed player plays it where it is: the player on top
            # keeps its place while it plays.
            row_player = 'mpv' if state()['others'][0] == 'mpv' else 'chromium.instance4242'
            keys('-k', 'space')
            wait(lambda: called(row_player, 'Play'), 'Space plays the focused row')
            time.sleep(1)
            assert state()['player'] == 'Spotify' and state()['playing'], state()
            keys('-k', 'space')
            wait(lambda: called(row_player, 'Pause'), 'Space pauses it again')
            # A panel opens with focus on play: Space plays and pauses the
            # player on top.
            keys('-k', 'Escape')
            wait(lambda: state()['popout'] == '', 'Escape closes the panel')
            click(*body)
            wait(lambda: state()['popout'] == 'media', 'the panel again')
            time.sleep(0.8)
            keys('-k', 'space')
            wait(lambda: not state()['playing'], 'Space pauses the player on top')
            keys('-k', 'space')
            wait(lambda: state()['playing'], 'Space plays it again')

            # Another player from the list: it is pinned while Spotify plays on.
            rows_y = top + 44 + 104 + 52 + 68 + 40 + 10 + 1 + 31 + 24
            click(left + 80, rows_y + 48 * state()['others'].index('Google Chrome'))
            wait(lambda: (s := state())['player'] == 'Google Chrome' and s['pinned'] != '', 'the browser picked')
            time.sleep(1.5)
            assert state()['player'] == 'Google Chrome', 'the pick did not hold while Spotify played'
            assert state()['others'][0] == 'Spotify', state()
            time.sleep(0.6)
            shot = Image.open(grab()).convert('RGB')
            shot.crop((max(0, left - 20), 0, min(1440, right + 20), 900)).save(OUTPUT / '09-panel-live-pinned.png')
            # Its row button plays another player where it is.
            hover(700, 860)
            time.sleep(0.3)

            # A player that starts playing takes over from the pick.
            player_call('mpv', 'Play')
            wait(lambda: state()['pinned'] == '', 'a newly started player clears the pick')
            assert state()['player'] in ('Spotify', 'mpv'), state()

            keys('-k', 'Escape')
            wait(lambda: state()['popout'] == '', 'Escape closes the panel')

            # Pause everything except mpv, which has no cover: the chip shows its mark.
            player_call('spotify', 'Pause')
            wait(lambda: (s := state())['player'] == 'mpv' and s['playing'], 'the video player alone playing')
            time.sleep(1)
            grab('10-chip-no-cover-two-players.png', f'0,0 {round(ax + aw + 160)}x40')

            log = (base / 'qs.log').read_text()
            problems = [line for line in log.splitlines() if QML_ERRORS.search(line)]
            assert not problems, '\n'.join(problems[:40])
            print('media player: all checks passed')
        except BaseException:
            for name in ('qs.log', 'sway.log'):
                path = base / name
                if path.exists():
                    print(f'--- {name}\n' + path.read_text()[-12000:])
            raise
        finally:
            if pointer is not None:
                pointer.close()
            for proc in reversed(processes):
                try:
                    os.killpg(proc.pid, 15)
                except ProcessLookupError:
                    pass
            for proc in processes:
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, 9)
    EDITOR.process_guard(runtime)


if __name__ == '__main__':
    main()
