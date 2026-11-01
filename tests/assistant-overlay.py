#!/usr/bin/env python3
"""Drive the real shell and assistant service with a scripted agent.

The actual Quickshell engine loads the whole shell under a private headless
Sway, the actual cybexos-assistant service runs beside it, and a fake
`claude` speaks Claude Code's stream-json and permission protocol. Questions
go in through the shell's `assistant` IPC target, as `cybex assistant ask`
sends them; approvals are answered over the service socket, as the card's
buttons do. What a turn left behind (Undo, a new widget) is checked on disk
and in the service's snapshot, and the shell's log must stay free of QML
errors throughout.

The launcher's Ask Wiz row is typed into with wtype: a query nothing matches
reaches the assistant once the launcher has closed, kept behind sign-in while
no agent is signed in. With --screenshots DIR (grim, and the installed
desktop's fonts from tests/shell_fonts.py), that row and the empty
notification centre, with Do Not Disturb off and on, are saved there. Those
runs draw with OpenGL on Mesa's llvmpipe (CYBEXOS_TEST_MESA, or the flake's
nixpkgs#mesa): the software scene graph cannot draw the launcher's
ClippingRectangle, so its card would be missing from the picture.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
DBUS = ["dbus-run-session", *(["--config-file", os.environ["CYBEXOS_DBUS_SESSION_CONFIG"]]
                              if os.environ.get("CYBEXOS_DBUS_SESSION_CONFIG") else []), "--"]
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]
QML_ERRORS = re.compile(r"TypeError|ReferenceError|Binding loop|is not a type|Type \w+ unavailable"
                        r"|Cannot assign|Unable to assign|Illegal method name|Failed to load configuration")

FAKE_CLAUDE = r'''
import json, os, sys, time
from pathlib import Path

args = sys.argv[1:]
home = Path(os.environ["HOME"])
if "--resume" in args:
    session = args[args.index("--resume") + 1]
else:
    # A new session each time, as Claude Code starts one.
    counter = home.parent / "claude-sessions"
    number = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(number))
    session = f"overlay-session-{number}"
if args[:1] == ["-p"]:
    with (home.parent / "claude-argv.jsonl").open("a") as stream:
        stream.write(json.dumps(args) + "\n")
signed_out = home / 'signed-out-claude'
if args == ['auth', 'status']:
    sys.exit(int(signed_out.exists()))
if args == ['auth', 'login']:
    (home / 'login-argv.json').write_text(json.dumps(sys.argv))
    signed_out.unlink(missing_ok=True)
    sys.exit(0)

def emit(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()

def read():
    line = sys.stdin.readline()
    if not line:
        sys.exit(0)
    return json.loads(line)

def ask(request_id, tool, tool_input):
    emit({"type": "control_request", "request_id": request_id,
          "request": {"subtype": "can_use_tool", "tool_name": tool, "input": tool_input,
                      "tool_use_id": "tu-" + request_id}})
    while True:
        message = read()
        if message.get("type") == "control_response" and message["response"]["request_id"] == request_id:
            return message["response"]["response"]

def reply(text):
    emit({"type": "stream_event", "event": {"type": "message_start"}})
    for word in text.split(" "):
        emit({"type": "stream_event", "event": {"type": "content_block_delta",
                                                "delta": {"type": "text_delta", "text": word + " "}}})
    emit({"type": "result", "subtype": "success", "is_error": False, "result": text, "session_id": session})

emit({"type": "system", "subtype": "init", "session_id": session})
while True:
    message = read()
    if message.get("type") != "user":
        continue
    text = message["message"]["content"][0]["text"].lower()
    if "transparent" in text:
        target = home / ".config/cybexos/shell.json"
        emit({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "x", "name": "Read", "input": {"file_path": str(target)}}]}})
        if ask("r1", "Edit", {"file_path": str(target), "old_string": "a", "new_string": "b"})["behavior"] == "allow":
            data = json.loads(target.read_text())
            data["glassEnabled"] = True
            target.write_text(json.dumps(data, indent=2) + "\n")
        reply("The menubar is transparent now.")
    elif "clean" in text:
        answer = ask("r1", "Bash", {"command": "rm -rf ~/Downloads/old-isos"})
        time.sleep(0.2)
        reply("Removed it." if answer["behavior"] == "allow" else "Okay, I left it alone.")
    elif "widget" in text:
        target = home / ".local/share/cybexos/plugins/personal.cputemp/manifest.json"
        if ask("r1", "Write", {"file_path": str(target), "content": "{}"})["behavior"] == "allow":
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps({"id": "personal.cputemp", "name": "CPU temperature",
                                          "version": "1.0.0", "apiVersion": 1, "entrypoint": "Widget.qml"}))
        reply("I made a CPU temperature widget. It is off until you add it to the bar.")
    else:
        reply("I can help with Cybex OS.")
'''


def opengl():
    """The environment that renders with OpenGL on Mesa's llvmpipe."""
    mesa = os.environ.get("CYBEXOS_TEST_MESA") or subprocess.run(
        NIX + ["build", "--no-link", "--print-out-paths", "--inputs-from", str(ROOT), "nixpkgs#mesa"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()[0]
    return {"__EGL_VENDOR_LIBRARY_FILENAMES": f"{mesa}/share/glvnd/egl_vendor.d/50_mesa.json",
            "LIBGL_DRIVERS_PATH": f"{mesa}/lib/dri"}


class VirtualPointer:
    """Real headless-compositor input via wlr-virtual-pointer v1.

    Sway's cursor IPC reports success without delivering events when its
    headless seat has no pointer. This creates a pointer device on that seat.
    The tiny client only binds the registry and sends motion/button/frame.
    """
    def __init__(self, env, width, height):
        self.width, self.height = width, height
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(5)
        self.socket.connect(str(Path(env['XDG_RUNTIME_DIR']) / env['WAYLAND_DISPLAY']))
        self.buffer = bytearray()
        self.send(1, 1, 2)  # wl_display.get_registry(new_id=2)
        self.send(1, 0, 3)  # wl_display.sync(callback=3)
        manager = None
        while True:
            identifier, opcode, payload = self.receive()
            if identifier == 2 and opcode == 0:
                name, length = struct.unpack_from('II', payload)
                interface = payload[8:8 + length - 1].decode()
                if interface == 'zwlr_virtual_pointer_manager_v1':
                    manager = name
            if identifier == 3:
                break
        assert manager is not None, 'The isolated compositor has no virtual pointer protocol'
        interface = b'zwlr_virtual_pointer_manager_v1\0'
        interface += b'\0' * (-len(interface) % 4)
        payload = struct.pack('II', manager, len(b'zwlr_virtual_pointer_manager_v1\0')) + interface + struct.pack('II', 1, 4)
        self.frame(2, 0, payload)  # wl_registry.bind(manager v1, new_id=4)
        self.send(4, 0, 0, 5)  # manager.create_virtual_pointer(default seat, new_id=5)

    def frame(self, identifier, opcode, payload=b''):
        self.socket.sendall(struct.pack('II', identifier, ((len(payload) + 8) << 16) | opcode) + payload)

    def send(self, identifier, opcode, *values):
        self.frame(identifier, opcode, struct.pack('I' * len(values), *values))

    def receive(self):
        while len(self.buffer) < 8 or len(self.buffer) < struct.unpack_from('II', self.buffer)[1] >> 16:
            data = self.socket.recv(4096)
            assert data, 'The compositor closed the pointer connection'
            self.buffer.extend(data)
        identifier, header = struct.unpack_from('II', self.buffer)
        size, opcode = header >> 16, header & 0xffff
        payload = bytes(self.buffer[8:size])
        del self.buffer[:size]
        assert not (identifier == 1 and opcode == 0), f'Wayland protocol error: {payload!r}'
        return identifier, opcode, payload

    def move(self, x, y):
        self.send(5, 1, int(time.monotonic() * 1000) & 0xffffffff, round(x), round(y), self.width, self.height)
        self.send(5, 4)
        time.sleep(0.04)

    def button(self, pressed):
        self.send(5, 2, int(time.monotonic() * 1000) & 0xffffffff, 0x110, int(pressed))
        self.send(5, 4)
        time.sleep(0.04)

    def close(self):
        self.socket.close()


class Session:
    def __init__(self, base):
        self.base = base
        self.runtime = base / "run"
        self.runtime.mkdir(mode=0o700)
        self.home = base / "home"
        (self.home / ".config/cybexos").mkdir(parents=True)
        self.preferences = self.home / ".config/cybexos/shell.json"
        self.preferences.write_text(json.dumps({"v": 30, "assistantShown": True,
                                               "assistantX": 1000, "assistantY": 120}, indent=2) + "\n")
        (self.home / 'signed-out-claude').touch()
        self.shell = base / "shell"
        shutil.copytree(ROOT / "desktop/quickshell", self.shell)
        shell_entry = self.shell / 'shell.qml'
        shell_entry.write_text(shell_entry.read_text().replace('target: "assistant"',
            'target: "assistant"\n        function signIn(agent: string): void { Assistant.signIn(agent); }'
            '\n        function draft(): string { return Assistant.draft; }'
            '\n        function dnd(on: bool): void { Notifs.setDnd(on); }'
            '\n        function notifications(): string {'
            ' return JSON.stringify({count: Notifs.count, dnd: Notifs.dnd}); }'
            '\n        function launcher(): string { const rows = LauncherProviders.rows;'
            ' return JSON.stringify({open: Launcher.open, query: LauncherProviders.query,'
            ' kinds: rows.slice(0, 3).map(row => row.kind),'
            ' question: rows.length > 0 ? rows[0].question || "" : ""}); }'))
        fake = base / "claude"
        fake.write_text(f"#!{sys.executable}\n" + FAKE_CLAUDE)
        fake.chmod(0o700)
        launchers = base / 'bin'
        launchers.mkdir()
        # A terminal, which the sign-in must not open.
        terminal = launchers / 'cybexos-apps'
        # Only its terminal is recorded: the shell also asks it for the default
        # applications (`cybexos-apps status`), which this fake declines.
        terminal.write_text(f'#!{sys.executable}\nimport json,os,sys\nfrom pathlib import Path\n'
            'if sys.argv[1:2] != ["terminal"]:\n    sys.exit(1)\n'
            'Path(os.environ["HOME"]).joinpath("terminal-argv.json").write_text(json.dumps(sys.argv[1:]))\n'
            'command=sys.argv[sys.argv.index("--")+1:]\nos.execv(command[0], command)\n')
        terminal.chmod(0o700)
        self.env = {**os.environ, "HOME": str(self.home), "XDG_RUNTIME_DIR": str(self.runtime),
                    "XDG_CONFIG_HOME": str(self.home / ".config"),
                    "XDG_DATA_HOME": str(self.home / ".local/share"),
                    "XDG_STATE_HOME": str(self.home / ".local/state"), "QT_QPA_PLATFORM": "wayland",
                    "QT_QUICK_BACKEND": "software", "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman",
                    "WLR_LIBINPUT_NO_DEVICES": "1", "CYBEXOS_ASSISTANT": "1",
                    # A fresh HOME would open the full-screen welcome guide over the character.
                    "CYBEXOS_WELCOME": "0",
                    "CYBEXOS_CONNECTED_WIDGETS": "0", "CYBEXOS_DEVELOPER_TOOLS": "0",
                    "QML_IMPORT_PATH": os.environ.get("CYBEXOS_QML_IMPORT_PATH", ""),
                    "PATH": str(launchers) + os.pathsep + os.environ.get('PATH', '')}
        for name in ("DISPLAY", "WAYLAND_DISPLAY"):
            self.env.pop(name, None)
        self.service_env = {"PYTHONPATH": str(ROOT / "desktop/assistant"), "PYTHONDONTWRITEBYTECODE": "1",
                            "CYBEXOS_ASSISTANT_CLAUDE": str(fake),
                            "CYBEXOS_ASSISTANT_CODEX": str(base / "no-codex"),
                            "CYBEXOS_ASSISTANT_STATUS": str(base / "no-status.json")}
        self.processes = []
        self.pointer = None
        self.screenshots = None

    def start(self, argv, log, extra=None):
        process = subprocess.Popen(argv, env={**self.env, **(extra or {})}, stdout=(self.base / log).open("w"),
                                   stderr=subprocess.STDOUT, start_new_session=True)
        self.processes.append(process)
        return process

    def stop(self):
        if self.pointer is not None:
            self.pointer.close()
        for process in reversed(self.processes):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for process in reversed(self.processes):
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()

    def ipc(self, *args):
        result = subprocess.run(["qs", "ipc", "-p", str(self.shell), "call", "assistant", *args],
                                env=self.env, capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            print(f"qs ipc call assistant {' '.join(args)} failed: {result.stderr.strip()}", file=sys.stderr)
        return result.stdout.strip()

    def shell_state(self):
        try:
            return json.loads(self.ipc("status") or "{}")
        except (json.JSONDecodeError, subprocess.TimeoutExpired):
            return {}

    def launcher_state(self):
        try:
            return json.loads(self.ipc("launcher") or "{}")
        except (json.JSONDecodeError, subprocess.TimeoutExpired):
            return {}

    def press(self, *args):
        """Keys through a virtual keyboard, to whichever surface holds focus."""
        subprocess.run(["wtype", "-s", "200", "-d", "12", *args, "-s", "100"], env=self.env,
                       check=True, timeout=20)

    def ask_from_launcher(self, query, screenshot=None):
        """Super+Space, a query nothing matches, and its one row: Ask Wiz."""
        subprocess.run(["qs", "ipc", "-p", str(self.shell), "call", "launcher", "toggle"],
                       env=self.env, capture_output=True, timeout=10, check=True)
        self.wait(lambda: self.launcher_state().get("open"), "the launcher")
        self.press(query)
        row = self.wait(lambda: (lambda s: s if s.get("kinds") == ["ask"] else None)(self.launcher_state()),
                        f"the Ask Wiz row for {query!r}")
        assert row["question"] == query.strip(), row
        if screenshot:
            self.screenshot(screenshot)
        self.press("-k", "Return")
        self.wait(lambda: self.launcher_state().get("open") is False, "the launcher to close")

    def screenshot(self, name):
        if self.screenshots is not None:
            # Past the surface's entry motion and Wiz's pose blend.
            time.sleep(0.8)
            subprocess.run(["grim", str(self.screenshots / name)], env=self.env, check=True, timeout=15)

    def call(self, method, params):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(10)
            client.connect(str(self.runtime / "cybexos/assistant.sock"))
            client.sendall((json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
                            + "\n").encode())
            buffer = b""
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    raise AssertionError(f"the service closed the connection during {method}")
                buffer += chunk
                *lines, buffer = buffer.split(b"\n")
                for line in lines:
                    message = json.loads(line)
                    if message.get("id") == 1:
                        return message

    def turn(self):
        return self.call("hello", {"client": "overlay-test", "protocol": 1})["result"]["turn"]

    def wait(self, predicate, what, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(0.2)
        raise AssertionError(f"timed out waiting for {what}\n{self.log()}")

    def finished(self, prompt):
        def done():
            turn = self.turn()
            return turn if turn and turn["prompt"] == prompt and turn["status"] in ("completed", "failed") else None
        return self.wait(done, f"the answer to {prompt!r}")

    def log(self):
        path = self.base / "qs.log"
        return path.read_text(errors="replace") if path.exists() else ""

    def drag(self, x, y, dx, dy, dwell=0, held=None):
        self.pointer.move(x, y)
        # Resting on the character first opens its box, as a person's
        # pointer does on the way to a drag.
        time.sleep(dwell)
        self.pointer.button(True)
        for step in range(1, 21):
            self.pointer.move(x + dx * step / 20, y + dy * step / 20)
            if step == 10 and held:
                held()
        self.pointer.button(False)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--screenshots", type=Path,
                        help="save the Ask Wiz row and the empty notification centre here")
    options = parser.parse_args()
    if not shutil.which("qs") or any(subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', name],
            stdout=subprocess.DEVNULL).returncode == 0 for name in ('qs', '.quickshell-wra')):
        print("Assistant overlay test deferred to isolated CI")
        return
    for executable in ("wtype", *(("grim",) if options.screenshots else ())):
        if not shutil.which(executable):
            raise SystemExit(f"{executable} is required; use nix develop")
    with tempfile.TemporaryDirectory(prefix="cybexos-assistant-overlay-") as temporary:
        session = Session(Path(temporary))
        try:
            if options.screenshots:
                import shell_fonts
                options.screenshots.mkdir(parents=True, exist_ok=True)
                session.screenshots = options.screenshots
                session.env.update(shell_fonts.fontconfig(session.base))
                del session.env["QT_QUICK_BACKEND"]
                session.env.update(opengl())
            (session.base / "sway.conf").write_text("output HEADLESS-1 mode 1440x900\nseat seat0 fallback true\n")
            sway = session.base / "sway"
            shutil.copyfile(shutil.which("sway"), sway)
            sway.chmod(0o700)
            session.start([str(sway), "-c", str(session.base / "sway.conf")], "sway.log")
            sockets = session.wait(lambda: [p for p in session.runtime.glob("wayland-*") if p.is_socket()],
                                   "the compositor", timeout=10)
            session.env["WAYLAND_DISPLAY"] = sockets[0].name
            session.pointer = VirtualPointer(session.env, 1440, 900)
            session.start([sys.executable, "-B", "-m", "cybexos_assistant", "serve"], "service.log",
                          session.service_env)
            session.start([*DBUS, "qs", "--no-color", "-p", str(session.shell)], "qs.log")

            state = session.wait(lambda: session.shell_state().get("connected") and session.shell_state(),
                                 "the shell to connect to the service", timeout=45)
            assert state["shown"] and state["screen"] == "HEADLESS-1", state

            # A fresh account sees onboarding before a model process is used.
            assert state['setupRequired'] and not state['agentReady'], state
            session.ipc('ask', 'Keep this first question')
            session.wait(lambda: session.shell_state().get('composing') and session.shell_state().get('hasDraft'),
                         'sign-in onboarding with the saved question')
            # Wiz listens while the box is open.
            assert session.shell_state()['pose'] == 'listening', session.shell_state()
            assert session.turn() is None
            session.wait(lambda: not session.shell_state().get('authChecking'), 'the initial sign-in check')

            # The launcher offers a query nothing matches to Wiz. Signed out,
            # it waits in the box behind the sign-in prompt, as a typed one
            # does; the hidden character comes back for it.
            session.ipc('hide')
            session.wait(lambda: session.shell_state().get('shown') is False, 'the character to hide')
            session.ask_from_launcher('connect my printer', 'launcher-ask-wiz.png')
            session.wait(lambda: (lambda s: s.get('shown') and s.get('composing'))(session.shell_state()),
                         'the box with the launcher\'s question')
            assert session.ipc('draft') == 'connect my printer', session.ipc('draft')
            assert session.turn() is None, 'a signed-out question never reaches a model'
            # Prefixes and whitespace are not questions.
            subprocess.run(["qs", "ipc", "-p", str(session.shell), "call", "launcher", "toggle"],
                           env=session.env, capture_output=True, timeout=10, check=True)
            session.wait(lambda: session.launcher_state().get('open'), 'the launcher again')
            for typed in ('   ', ':zzqxv', '=', '/', '!zzqxv'):
                session.press(typed)
                state = session.wait(lambda: (lambda s: s if s.get('query') == typed else None)(
                    session.launcher_state()), f'the query {typed!r}')
                assert 'ask' not in state['kinds'], state
                session.press('-k', 'Escape')
                session.wait(lambda: session.launcher_state().get('query') == '', 'the cleared query')
            session.press('-k', 'Escape')
            session.wait(lambda: session.launcher_state().get('open') is False, 'the launcher to close')

            session.ipc('signIn', 'claude')
            session.wait(lambda: session.shell_state().get('agentReady') and session.shell_state().get('hasDraft'),
                         'automatic sign-in detection with the saved question')
            argv = json.loads((session.home / 'login-argv.json').read_text())
            assert argv == [str(session.base / 'claude'), 'auth', 'login'], argv
            opened = session.home / 'terminal-argv.json'
            assert not opened.exists(), f'the sign-in opened a terminal: {opened.read_text()}'

            # Send real compositor pointer events. Repeated movement must cover
            # the full distance despite the character's scale/rotation/mask.
            # The last drag starts with the box open from hovering: the drag
            # hides it, and must neither lose the pointer nor change the
            # surface's keyboard mode while the button is held.
            for dx, dy, dwell in ((-300, 200, 0), (180, -120, 0), (-400, 330, 0), (260, -180, 0.8)):
                before = session.shell_state()
                size = before['size']
                if dwell:
                    session.pointer.move(before['x'] + size / 2, before['y'] + size / 2)
                    session.wait(lambda: session.shell_state().get('composing'), 'the box opened by hovering')
                held = []
                session.drag(before['x'] + size / 2, before['y'] + size / 2, dx, dy, dwell,
                             lambda: held.append(session.shell_state().get('pose')))
                try:
                    after = session.wait(lambda: (lambda s: s if abs(s.get('x', -9999) - before['x'] - dx) <= 3
                        and abs(s.get('y', -9999) - before['y'] - dy) <= 3 else None)(session.shell_state()),
                        'the full drag distance', timeout=3)
                except AssertionError as error:
                    raise AssertionError(f'{before=} wanted {dx=}, {dy=}; actual={session.shell_state()}\n{error}') from error
                assert after['screen'] == 'HEADLESS-1'
                # Wiz is carried while held and lands when dropped.
                assert held == ['carried'], held
                session.wait(lambda: session.shell_state().get('pose') not in (None, 'carried'), 'Wiz to land')

            # Signed in, the launcher's question is asked straight away, with
            # nothing of the screen.
            session.ask_from_launcher('connect my printer')
            asked = session.finished('connect my printer')
            assert asked['status'] == 'completed' and asked['text'] == 'I can help with Cybex OS.', asked
            assert asked['screenshot'] is False, asked
            session.wait(lambda: session.shell_state().get('turn') == 'completed', "the launcher question's reply")
            assert session.ipc('draft') == '', session.ipc('draft')

            # A preference edit is allowed without a card and comes back with Undo.
            session.ipc("ask", "Make the menubar transparent")
            turn = session.finished("Make the menubar transparent")
            assert turn["status"] == "completed" and turn["text"].startswith("The menubar"), turn
            assert turn["undo"] == ["~/.config/cybexos/shell.json"], turn
            assert json.loads(session.preferences.read_text())["glassEnabled"] is True
            session.wait(lambda: session.shell_state().get("turn") == "completed", "the shell's reply")
            undone = session.call("turn.undo", {"id": turn["id"]})["result"]
            assert undone == {"restored": ["~/.config/cybexos/shell.json"], "skipped": []}, undone
            assert "glassEnabled" not in json.loads(session.preferences.read_text())

            # Ordinary commands proceed with the fresh-install default.
            session.ipc("ask", "Clean up these downloads")
            allowed = session.finished("Clean up these downloads")
            assert allowed["status"] == "completed" and allowed["text"] == "Removed it.", allowed
            assert allowed["approvals"] == [], allowed
            # A finished turn is celebrated for a moment, then Wiz rests.
            session.wait(lambda: session.shell_state().get("pose") == "finished", "Wiz's celebration")
            session.wait(lambda: session.shell_state().get("pose") != "finished", "the end of the celebration")

            # Ask first takes effect on the next question without a service restart.
            preferences = json.loads(session.preferences.read_text())
            preferences["assistantApprovalPolicy"] = "ask"
            session.preferences.write_text(json.dumps(preferences) + "\n")
            session.ipc("ask", "Clean up my old downloads")
            waiting = session.wait(lambda: (lambda t: t if t and t["approvals"] else None)(session.turn()),
                                   "the command card")
            card = waiting["approvals"][0]
            assert waiting["status"] == "waiting" and card["kind"] == "command", waiting
            assert card["command"] == "rm -rf ~/Downloads/old-isos", card
            session.wait(lambda: session.shell_state().get("turn") == "waiting", "the shell to show the card")
            assert session.shell_state()["pose"] == "needs-input", session.shell_state()
            assert session.call("approval.respond", {"id": card["id"], "decision": "deny"})["result"] == {"ok": True}
            denied = session.finished("Clean up my old downloads")
            assert denied["text"] == "Okay, I left it alone.", denied

            # A widget lands disabled, and the reply offers it.
            session.ipc("ask", "Create a CPU temperature widget")
            made = session.finished("Create a CPU temperature widget")
            assert made["plugins"] == [{"id": "personal.cputemp", "name": "CPU temperature"}], made

            # Hiding takes the character away and reports it; the service keeps the conversation.
            session.ipc("hide")
            session.wait(lambda: session.shell_state().get("shown") is False, "the character to hide")
            # Settings are saved shortly after they change.
            session.wait(lambda: json.loads(session.preferences.read_text()).get("assistantShown") is False,
                         "the hidden state to be saved")
            hello = session.call("hello", {"client": "overlay-test", "protocol": 1})["result"]
            assert hello["turn"]["resumable"] is True, hello
            rows = hello["conversations"]
            # Every question so far was asked in a box of its own: each is a
            # conversation, newest first.
            assert [row["title"] for row in rows] == [
                "Create a CPU temperature widget", "Clean up my old downloads", "Clean up these downloads",
                "Make the menubar transparent", "connect my printer"], rows

            # History. Shown again, the character is clicked (Super+I's tap
            # does the same): a new conversation, with the recent ones under
            # the suggestions.
            # `qs ipc call assistant show` lists the target instead of calling it.
            session.ipc("toggle")
            session.wait(lambda: session.shell_state().get("shown"), "the character to come back")
            session.wait(lambda: session.shell_state().get("conversations") == len(rows), "the shell's list")
            session.ipc("compose")
            session.wait(lambda: (lambda s: s.get("composing") and s.get("continuing") == ""
                                  and not s.get("historyOpen"))(session.shell_state()), "a new conversation")
            session.screenshot("assistant-new-conversation.png")
            session.ipc("history")
            session.wait(lambda: session.shell_state().get("historyOpen"), "History")
            session.screenshot("assistant-history.png")
            # A conversation opened from History is shown and continued.
            older = rows[2]
            session.ipc("open", older["id"])
            session.wait(lambda: (lambda s: s.get("composing") and s.get("continuing") == older["id"]
                                  and not s.get("historyOpen"))(session.shell_state()), "the opened conversation")
            session.screenshot("assistant-conversation.png")
            session.press("Tell me more")
            session.press("-k", "Return")
            more = session.finished("Tell me more")
            assert more["conversation"] == older["id"] and more["resumable"], more
            opened = session.call("conversation.open", {"id": older["id"]})["result"]["conversation"]
            assert [turn["prompt"] for turn in opened["turns"]] == ["Clean up these downloads", "Tell me more"], opened
            # Claude Code resumed that conversation's own session.
            stored = json.loads((session.home / ".local/state/cybexos/assistant/conversations"
                                 / (older["id"] + ".json")).read_text())
            argv = [json.loads(line) for line in (session.base / "claude-argv.jsonl").read_text().splitlines()][-1]
            assert "--resume" in argv and argv[argv.index("--resume") + 1] == stored["session"], (argv, stored)
            session.wait(lambda: session.shell_state().get("turn") == "completed", "the continued answer")
            # Clicked again, with a real pointer click on Wiz, after the box
            # closed: a new conversation, not the last one.
            state = session.wait(lambda: (lambda s: s if s.get("composing") is False else None)(
                session.shell_state()), "the box to close for the answer")
            session.pointer.move(state["x"] + state["size"] / 2, state["y"] + state["size"] / 2)
            time.sleep(0.4)
            session.pointer.button(True)
            session.pointer.button(False)
            session.wait(lambda: (lambda s: s.get("composing") and s.get("continuing") == "")(session.shell_state()),
                         "a new conversation after the last one")
            session.pointer.move(20, 880)
            session.press("-k", "Escape")
            session.wait(lambda: not session.shell_state().get("composing"), "the box to close")
            # Deleting and clearing, here over the service socket as the
            # History buttons do; the shell follows.
            assert session.call("conversation.delete", {"id": rows[0]["id"]})["result"] == {"ok": True}
            session.wait(lambda: session.shell_state().get("conversations") == len(rows) - 1, "one fewer")
            assert session.call("conversation.restore", {"id": rows[0]["id"]})["result"]["conversation"]["id"] == rows[0]["id"]
            session.wait(lambda: session.shell_state().get("conversations") == len(rows), "the restored one")
            assert session.call("conversation.clear", {})["result"] == {"ok": True}
            session.wait(lambda: (lambda s: s.get("conversations") == 0 and s.get("turn") == "")(session.shell_state()),
                         "the cleared history")
            assert not list((session.home / ".local/state/cybexos/assistant/conversations").glob("c-*.json"))
            session.ipc("history")
            session.wait(lambda: session.shell_state().get("historyOpen"), "the empty History")
            session.screenshot("assistant-history-empty.png")
            session.ipc("hide")
            session.wait(lambda: session.shell_state().get("shown") is False, "the character to hide again")

            # The empty notification centre: Wiz idle, asleep under Do Not
            # Disturb. Loading him there must not log a QML error either.
            assert json.loads(session.ipc("notifications")) == {"count": 0, "dnd": False}
            subprocess.run(["qs", "ipc", "-p", str(session.shell), "call", "popouts", "open", "notifications"],
                           env=session.env, capture_output=True, timeout=10, check=True)
            time.sleep(0.4)
            session.screenshot("notifications-empty.png")
            session.ipc("dnd", "true")
            assert json.loads(session.ipc("notifications")) == {"count": 0, "dnd": True}
            session.screenshot("notifications-empty-dnd.png")
            session.ipc("dnd", "false")

            output = session.log()
            errors = [line for line in output.splitlines() if QML_ERRORS.search(line)]
            assert not errors, "\n".join(errors)
            print("Assistant onboarding/draft preservation, Ask Wiz from the launcher (signed out and in), repeated pointer dragging, default automatic approvals, Ask first, Undo, widget hand-off, Wiz's poses (carried while dragged), hiding, conversation history (new by default, open and continue, delete, restore, clear) and the empty notification centre passed")
        finally:
            session.stop()


if __name__ == "__main__":
    if os.geteuid() == 0:
        raise SystemExit(subprocess.call(["runuser", "-u", "nobody", "--", sys.executable, __file__, *sys.argv[1:]]))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    main()
