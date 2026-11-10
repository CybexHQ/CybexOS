# Screenshots in a real Hyprland session (docs/keyboard-shortcuts.md#capture):
# the Print keys reach Omasnap through the Cybex OS bindings, a click on a
# window captures exactly that window, and the capture is saved, copied and
# previewed. Shift+Print saves the screen at once and announces it through
# Omasnap's notification adapter, and a click on that notification opens
# the editor. The shortcut pressed again closes the overlay, and the
# scrolling capture opens its picker. Omasnap's controls use the shell's
# theme colours.
#
# Keys are QEMU key events and the pointer is QEMU's USB tablet through QMP,
# as in hyprland-pointer.nix. SDDM signs the user in directly and the display
# is fixed at 1280×800. This is VM qualification on Hyprland's software
# renderer, not of a physical display or GPU.
{ pkgs, module }:
let
  # A window with something to capture, floating at a known place.
  content = pkgs.writeShellScript "cybexos-screenshots-content" ''
    printf 'Cybex OS\nScreenshot test\n'
    exec ${pkgs.coreutils}/bin/sleep 9999
  '';
  launchWindow = pkgs.writeShellScript "cybexos-screenshots-window" ''
    exec hyprctl -i 0 dispatch 'hl.dsp.exec_cmd("${pkgs.kitty}/bin/kitty --class cxo-shot -o font_size=18 ${content}", { float = true, size = { 480, 320 }, move = "200 200" })'
  '';
  arrangeWindow = pkgs.writeShellScript "cybexos-screenshots-arrange" ''
    hyprctl -i 0 dispatch 'hl.dsp.window.float({ action = "set", window = "class:cxo-shot" })'
    hyprctl -i 0 dispatch 'hl.dsp.window.resize({ x = 480, y = 320, window = "class:cxo-shot" })'
    hyprctl -i 0 dispatch 'hl.dsp.window.move({ x = 200, y = 200, window = "class:cxo-shot" })'
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-screenshots";
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    cybexos = { enable = true; primaryUser = "tester"; features = { proprietary = false; steam = false; docker = false; }; };
    networking.hostName = "machine";
    users.users.tester.initialPassword = "qualification-only";
    services.displayManager.autoLogin = { enable = true; user = "tester"; };
    virtualisation = {
      memorySize = 8192;
      cores = 8;
      graphics = true;
      diskSize = 4096;
      qemu.options = [ "-no-user-config" "-device virtio-vga,xres=1280,yres=800" ];
    };
    system.stateVersion = "26.05";
    boot.loader.systemd-boot.enable = lib.mkForce false;
  };
  testScript = ''
    import json
    import re
    import time
    from typing import Any

    QML_ERRORS = re.compile(r"TypeError|ReferenceError|Binding loop|is not a type|Type \w+ unavailable"
                            r"|Cannot assign|Unable to assign|Illegal method name|Failed to load configuration")
    SHOTS = "/home/tester/Pictures/Screenshots"
    out = machine.out_dir

    machine.start()
    machine.wait_for_unit("display-manager.service")
    uid = machine.succeed("id -u tester").strip()
    session = f"XDG_RUNTIME_DIR=/run/user/{uid} HOME=/home/tester DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"

    def user(command):
        return machine.succeed(f"runuser -u tester -- env {session} {command}")

    def hypr(*query):
        return json.loads(user("hyprctl -i 0 -j " + " ".join(query)))

    def wait(predicate, timeout=10):
        deadline = time.monotonic() + timeout
        while True:
            value = predicate()
            if value or time.monotonic() >= deadline:
                return value
            time.sleep(0.25)

    def layers(namespace):
        return [layer for monitor in hypr("layers").values() for level in monitor.get("levels", {}).values()
                for layer in level if layer.get("namespace") == namespace]

    def shots():
        return machine.succeed(f"find {SHOTS} -maxdepth 1 -name '*.png' -printf '%f\\n' 2>/dev/null | sort || true").split()

    def png_size(name):
        size = machine.succeed(f"python3 -c 'import struct,sys; d=open(sys.argv[1],\"rb\").read(24); "
                               f"assert d[:8]==b\"\\x89PNG\\r\\n\\x1a\\n\"; print(*struct.unpack(\">II\", d[16:24]))' '{SHOTS}/{name}'")
        return tuple(int(value) for value in size.split())

    def send(*events):
        assert machine.qmp_client is not None
        arguments: Any = {"events": list(events)}
        machine.qmp_client.send("input-send-event", arguments)

    def axis(name, value, extent):
        return {"type": "abs", "data": {"axis": name, "value": max(0, min(32767, round(value * 32767 / (extent - 1))))}}

    def move(x, y, pause=0.05):
        send(axis("x", x, 1280), axis("y", y, 800))
        time.sleep(pause)

    def click(x, y):
        move(x, y, 0.3)
        send({"type": "btn", "data": {"down": True, "button": "left"}})
        time.sleep(0.1)
        send({"type": "btn", "data": {"down": False, "button": "left"}})
        time.sleep(0.3)

    def omasnap_clients():
        return [client for client in hypr("clients") if client.get("class") == "omasnap"]

    # ---- the session ------------------------------------------------------
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
    # The first sign-in shows the welcome guide over everything.
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} cybexos-runtime ipc welcome status", timeout=300)
    assert wait(lambda: json.loads(user("cybexos-runtime ipc welcome status"))["open"], 60)
    user("cybexos-runtime ipc welcome close")
    assert wait(lambda: not layers("qs-welcome"), 30)
    shell_pid = user("systemctl --user show quickshell.service -p MainPID --value").strip()
    shell_env = dict(line.split("=", 1) for line in machine.succeed(f"tr '\\0' '\\n' < /proc/{shell_pid}/environ").splitlines() if "=" in line)
    wayland = f"WAYLAND_DISPLAY={shell_env['WAYLAND_DISPLAY']}"

    # Omasnap's controls take the shell's colours.
    machine.wait_until_succeeds("test -s /home/tester/.local/state/cybexos/theme/omasnap/colors.toml", timeout=60)
    theme = machine.succeed("cat /home/tester/.local/state/cybexos/theme/omasnap/colors.toml")
    assert re.search(r'^accent = "#[0-9a-f]{6}"$', theme, re.M) and "[popups]" in theme, theme

    user("${launchWindow}")
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} hyprctl -i 0 -j clients | grep -q cxo-shot", timeout=60)
    window = next(c for c in hypr("clients") if c["class"] == "cxo-shot")
    if not window["floating"] or tuple(window["size"]) != (480, 320):
        user("${arrangeWindow}")
        time.sleep(1)
        window = next(c for c in hypr("clients") if c["class"] == "cxo-shot")
    # The welcome guide's notifications leave first.
    time.sleep(8)
    move(1100, 700, 0.5)
    machine.screenshot("desktop")

    # ---- Print: pick a window ----------------------------------------------
    machine.send_key("print")
    assert wait(lambda: layers("omasnap"), 15), "Print did not open Omasnap"
    time.sleep(1)
    machine.screenshot("picker")
    centre = (window["at"][0] + window["size"][0] // 2, window["at"][1] + window["size"][1] // 2)
    move(centre[0] - 40, centre[1])
    move(*centre, 0.8)
    machine.screenshot("picker-window")
    click(*centre)
    assert wait(lambda: len(shots()) == 1, 15), shots()
    first = shots()[0]
    assert png_size(first) == tuple(window["size"]), (png_size(first), window)
    assert "image/png" in user(f"env {wayland} wl-paste --list-types").split(), "the capture is not on the clipboard"
    assert wait(lambda: not layers("omasnap"), 10), "the overlay stayed open"
    assert wait(lambda: omasnap_clients(), 10), "no preview after the capture"
    preview = omasnap_clients()[0]
    machine.screenshot("preview")
    move(preview["at"][0] + preview["size"][0] // 2, preview["at"][1] + preview["size"][1] // 2, 0.8)
    machine.screenshot("preview-hover")
    move(1100, 120, 0.3)
    # The preview leaves by itself after 7 seconds without the pointer.
    assert wait(lambda: not omasnap_clients(), 20), omasnap_clients()

    # ---- the shortcut again closes the overlay ----------------------------
    machine.send_key("print")
    assert wait(lambda: layers("omasnap"), 15)
    time.sleep(1)
    machine.send_key("print")
    assert wait(lambda: not layers("omasnap"), 10), "a second Print did not close the overlay"
    assert len(shots()) == 1, shots()

    # ---- Shift+Print: the whole screen, announced ---------------------------
    machine.send_key("shift-print")
    assert wait(lambda: len(shots()) == 2, 15), shots()
    second = next(name for name in shots() if name != first)
    assert png_size(second) == (1280, 800), png_size(second)
    assert wait(lambda: layers("qs-notifications"), 10), "no notification"
    time.sleep(1)
    machine.screenshot("fullscreen-notification")
    toast = layers("qs-notifications")[0]
    # The card's body is its default action: edit the capture.
    click(toast["x"] + toast["w"] // 2, toast["y"] + 56)
    assert wait(lambda: layers("omasnap") or omasnap_clients(), 15), "the notification did not open the editor"
    time.sleep(1.5)
    machine.screenshot("editor")
    machine.send_key("esc")
    assert wait(lambda: not layers("omasnap") and not omasnap_clients(), 10), "the editor stayed open"

    # ---- the scrolling capture's picker -------------------------------------
    machine.send_key("alt-print")
    assert wait(lambda: layers("omasnap"), 15), "Alt+Print did not open Omasnap"
    time.sleep(1)
    machine.screenshot("scroll-picker")
    machine.send_key("esc")
    assert wait(lambda: not layers("omasnap"), 10)
    assert len(shots()) == 2, shots()

    # The captures themselves, for review: the window without the pointer, and the screen.
    machine.copy_from_machine(f"{SHOTS}/{first}", "captures")
    machine.copy_from_machine(f"{SHOTS}/{second}", "captures")
    shell_log = machine.succeed("journalctl _SYSTEMD_USER_UNIT=quickshell.service -b --no-pager -o short-monotonic")
    (out / "quickshell.log").write_text(shell_log)
    session_log = machine.succeed(f"journalctl _UID={uid} -b --no-pager -o short-monotonic")
    (out / "session.log").write_text(session_log)
    assert "Could not start omarchy-notification-send" not in session_log
    # The menubar files this change touched must be clean.
    errors = [line for line in shell_log.splitlines() if QML_ERRORS.search(line) and re.search(r"Recorder|Indicators", line)]
    assert not errors, "\n".join(errors)
  '';
}
