# Settings -> Appearance -> Pointer in a real Hyprland session, with a real
# download (docs/settings.md#pointer).
#
# The machine's catalogue records Hackneyed's exact store path at this
# Nixpkgs, as every installation does, but the path is not on the machine.
# A local binary cache holds it (nix/tests/pointer-cache.py: the real NAR,
# unsigned, encoded so the cache does not depend on the path), standing in
# for cache.nixos.org. Choosing Hackneyed through the shell must substitute
# it as the user under a garbage-collector root, link it into
# ~/.local/share/icons and hand it to Hyprland, GTK and the activation
# environment. A size and the hiding options are then edited into shell.json
# and the shell restarted, which applies the difference; signing out and in
# again must start Hyprland with that pointer (cybexos-session) and leave the
# shell nothing to apply. Choosing Bibata again and removing the download
# frees the path for Nix to collect.
#
# What Hyprland draws is checked in its own screen copy with the pointer
# composited (grim -c): most of Hackneyed's arrow is white, most of Bibata
# Modern Classic's black.
#
# Test-only settings: SDDM signs the user in directly and again after a
# sign-out, the display is fixed at 1280×800, Hyprland draws the pointer in
# software (user.lua) so screen copies include it, and Nix trusts the
# unsigned local cache (require-sigs off). Signature checking itself is Nix's and is
# not what this exercises. This is VM qualification, not physical hardware.
{ pkgs, module }:
let
  python = pkgs.python3.withPackages (p: [ p.pillow ]);
  theme = pkgs.hackneyed;
  storePath = builtins.unsafeDiscardStringContext theme.outPath;
  cache = pkgs.runCommand "cybexos-pointer-test-cache" { } ''
    ${pkgs.python3.interpreter} -B ${./pointer-cache.py} ${theme} $out
  '';
  # The share of light pixels in the pointer drawn at (640, 400), either hand: a screen
  # copy with it there against one with it moved away. Hyprland leaves the
  # pointer out of a region's copy, so whole screens are compared.
  sample = pkgs.writeText "cybexos-pointer-sample.py" ''
    import json, sys
    from PIL import Image
    shown, hidden = (Image.open(path).convert("RGB").crop((580, 380, 700, 500)) for path in sys.argv[1:3])
    pointer = [p for p, q in zip(shown.getdata(), hidden.getdata()) if max(abs(a - b) for a, b in zip(p, q)) > 12]
    light = [p for p in pointer if 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2] > 160]
    print(json.dumps({"pixels": len(pointer), "light": round(len(light) / len(pointer), 3) if pointer else None}))
  '';
  # Edits the pointer settings while the shell is stopped; it reads
  # shell.json as it starts. Every other preference is left alone.
  edit = pkgs.writeText "cybexos-pointer-edit.py" ''
    import json, os, sys
    path = os.path.expanduser("~/.config/cybexos/shell.json")
    with open(path) as source:
        data = json.load(source)
    data.update(json.loads(sys.argv[1]))
    with open(path + ".pointer-test", "w") as target:
        json.dump(data, target, indent=2)
    os.replace(path + ".pointer-test", path)
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-pointer";
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    cybexos = { enable = true; primaryUser = "tester"; features = { proprietary = false; steam = false; docker = false; }; };
    networking.hostName = "machine";
    users.users.tester.initialPassword = "qualification-only";
    services.displayManager.autoLogin = { enable = true; user = "tester"; };
    services.displayManager.sddm.autoLogin.relogin = lib.mkForce true;
    nix.settings = { substituters = lib.mkForce [ "file:///var/lib/pointer-cache" ]; require-sigs = false; };
    system.extraDependencies = [ cache ];
    systemd.tmpfiles.rules = [
      "d /home/tester/.config 0700 tester users -"
      "d /home/tester/.config/cybexos 0700 tester users -"
      ''f /home/tester/.config/cybexos/shell.json 0600 tester users - {"v":31,"assistantShown":false}''
      # The VM's display has a hardware cursor plane, which screen copies
      # leave out; drawn in software, the pointer is in them.
      "d /home/tester/.config/cybexos/hypr 0700 tester users -"
      ''f /home/tester/.config/cybexos/hypr/user.lua 0600 tester users - hl.config({ cursor = { no_hardware_cursors = true } })''
    ];
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
    import base64
    import json
    import re
    import shlex
    import time
    from typing import Any

    QML_ERRORS = re.compile(r"TypeError|ReferenceError|Binding loop|is not a type|Type \w+ unavailable"
                            r"|Cannot assign|Unable to assign|Illegal method name|Failed to load configuration")
    STORE = "${storePath}"
    HOME = "/home/tester"
    ROOT = f"{HOME}/.local/state/cybexos/pointer/roots/hackneyed"
    RECORD = f"{HOME}/.local/state/cybexos/pointer/session.env"
    out = machine.out_dir
    results: dict[str, Any] = {}

    machine.start()
    machine.wait_for_unit("display-manager.service")
    # The theme's cache, standing in for cache.nixos.org.
    entry = json.loads(base64.b64decode(machine.succeed("cat ${cache}/narinfo.b64")))
    machine.succeed("mkdir -p /var/lib/pointer-cache && cp -r ${cache}/nar ${cache}/nix-cache-info /var/lib/pointer-cache/")
    machine.succeed(f"printf %s {shlex.quote(entry['text'])} > /var/lib/pointer-cache/{entry['name']}")
    status, _ = machine.execute(f"nix-store --check-validity {STORE}")
    assert status != 0, "the download must not be part of the system"

    uid = machine.succeed("id -u tester").strip()
    session = f"XDG_RUNTIME_DIR=/run/user/{uid} HOME={HOME} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"

    def user(command):
        return machine.succeed(f"runuser -u tester -- env {session} {command}")

    def wait(predicate, timeout=30):
        deadline = time.monotonic() + timeout
        while True:
            value = predicate()
            if value or time.monotonic() >= deadline:
                return value
            time.sleep(0.5)

    def pointer():
        status, output = machine.execute(f"runuser -u tester -- env {session} cybexos-runtime ipc pointer status")
        try:
            return json.loads(output) if status == 0 else {}
        except ValueError:
            return {}

    def gsetting(key):
        return user(f"systemd-run --user --wait --pipe --quiet gsettings get org.gnome.desktop.interface {key}").strip()

    def hyprland_pid():
        return machine.succeed("pgrep -u tester -f '[H]yprland.*--config' | head -n1").strip()

    def hyprland_environment():
        pid = hyprland_pid()
        variables = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ").splitlines()
        return pid, {k: v for k, v in (line.split("=", 1) for line in variables if "=" in line)
                     if k in ("XCURSOR_THEME", "XCURSOR_SIZE")}

    def signature():
        """The Hyprland instance this session's shell talks to."""
        environment = dict(line.split("=", 1) for line in user("systemctl --user show-environment").splitlines() if "=" in line)
        return environment["HYPRLAND_INSTANCE_SIGNATURE"]

    def option(name):
        data = json.loads(user(f"env HYPRLAND_INSTANCE_SIGNATURE={signature()} hyprctl -j getoption {name}"))
        return next((data[key] for key in ("bool", "int", "float") if key in data), data)

    def session_ready():
        machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
        ready = wait(lambda: (lambda s: s if s.get("loaded") and s.get("applied") == s.get("wanted") else None)(pointer()), 180)
        assert ready, pointer()
        status, opened = machine.execute(f"runuser -u tester -- env {session} cybexos-runtime ipc welcome status")
        if status == 0 and json.loads(opened).get("open"):
            user("cybexos-runtime ipc welcome close")
        return ready

    # ---- real pointer input and what Hyprland draws -----------------------
    def send(*events):
        assert machine.qmp_client is not None
        arguments: Any = {"events": list(events)}
        machine.qmp_client.send("input-send-event", arguments)

    def move(x, y):
        send(*({"type": "abs", "data": {"axis": axis, "value": round(value * 32767 / (extent - 1))}}
               for axis, value, extent in (("x", x, 1280), ("y", y, 800))))
        time.sleep(0.5)

    def grim(*arguments):
        socket = machine.succeed(f"ls /run/user/{uid} | grep -m1 '^wayland-[0-9]*$'").strip()
        machine.succeed(f"runuser -u tester -- env {session} WAYLAND_DISPLAY={socket} ${pkgs.grim}/bin/grim "
                        + " ".join(shlex.quote(argument) for argument in arguments))

    def drawn(name):
        """The share of light pixels in the pointer Hyprland draws at (640, 400).

        Hyprland keeps the image it shows until a surface sets the pointer
        again, as the pointer entering one does, so it passes over the bar
        on the way, as a person's would.
        """
        move(640, 14)
        move(600, 380)
        move(640, 400)
        time.sleep(1)
        results[name + "-cursorpos"] = user("hyprctl -i 0 cursorpos").strip()
        grim("-c", f"/tmp/{name}-shown.png")
        move(200, 650)
        time.sleep(1)
        grim("-c", f"/tmp/{name}-hidden.png")
        measured = json.loads(machine.succeed(f"${python}/bin/python3 ${sample} /tmp/{name}-shown.png /tmp/{name}-hidden.png"))
        machine.copy_from_machine(f"/tmp/{name}-shown.png", "")
        results[name] = measured
        machine.log(f"{name}: {json.dumps(measured)} at {results[name + '-cursorpos']}")
        assert measured["pixels"] > 40, measured
        return measured["light"]

    # ---- the installation's pointer ----------------------------------------
    first = session_ready()
    assert first["resolved"]["chosen"] == "Bibata-Modern-Classic" and not first["resolved"]["explicit"], first
    assert first["applied"] == "Bibata-Modern-Classic 24", "the session started with it; nothing to apply"
    themes = {t["id"]: t for t in first["themes"]}
    assert first["downloadsAvailable"] and themes["Hackneyed"]["downloadable"] and not themes["Hackneyed"]["installed"], themes
    assert themes["Bibata-Modern-Ice"]["installed"] and themes["Adwaita"]["installed"], themes
    assert hyprland_environment()[1] == {"XCURSOR_THEME": "Bibata-Modern-Classic", "XCURSOR_SIZE": "24"}
    assert gsetting("cursor-theme") == "'Bibata-Modern-Classic'"
    assert drawn("bibata") < 0.45, results
    machine.screenshot("bibata")

    # ---- a download, chosen in the shell ----------------------------------
    assert user("cybexos-runtime ipc pointer use Hackneyed").strip() == "ok"
    chosen = wait(lambda: (lambda s: s if s.get("applied") == "Hackneyed 24 explicit" else None)(pointer()), 300)
    assert chosen and not chosen["failure"] and not chosen["applyError"], pointer()
    machine.succeed(f"nix-store --check-validity {STORE}")
    assert machine.succeed(f"readlink {ROOT}").strip() == STORE
    assert f"{ROOT} -> {STORE}" in machine.succeed(f"nix-store -q --roots {STORE}"), "a root of the garbage collector"
    assert machine.succeed(f"readlink {HOME}/.local/share/icons/Hackneyed").strip() == f"{ROOT}/share/icons/Hackneyed"
    assert machine.succeed(f"stat -c %U {ROOT}").strip() == "tester"
    assert gsetting("cursor-theme") == "'Hackneyed'" and gsetting("cursor-size") == "24"
    assert "XCURSOR_THEME=Hackneyed" in user("systemctl --user show-environment")
    assert machine.succeed(f"cat {RECORD}") == "XCURSOR_THEME=Hackneyed\nXCURSOR_SIZE=24\n"
    assert drawn("hackneyed") > 0.55, results
    machine.screenshot("hackneyed")

    # ---- a size and the hiding options, edited while the shell is stopped -----
    user("systemctl --user stop quickshell.service")
    user("${python}/bin/python3 ${edit} " + shlex.quote(json.dumps(
        {"pointerSize": "larger", "pointerLeftHanded": True, "pointerHideTyping": True, "pointerHideIdle": 3})))
    user("systemctl --user start quickshell.service")
    edited = wait(lambda: (lambda s: s if s.get("applied") == "Hackneyed 48 explicit" else None)(pointer()), 120)
    assert edited, pointer()
    assert edited["resolved"]["theme"] == "Hackneyed", "Hackneyed has no left-handed version"
    assert gsetting("cursor-size") == "48"
    assert wait(lambda: option("cursor:hide_on_key_press") in (1, True)), option("cursor:hide_on_key_press")
    assert float(option("cursor:inactive_timeout")) == 3.0, option("cursor:inactive_timeout")

    # ---- the next login ------------------------------------------------------
    old_pid = hyprland_pid()
    # Signing out as the session menu does; SDDM then signs in again.
    user(f"env HYPRLAND_INSTANCE_SIGNATURE={signature()} cybexos-session-action logout")
    machine.wait_until_succeeds(f"pgrep -u tester -f '[H]yprland.*--config' | grep -vx {old_pid}", timeout=300)
    relogged = session_ready()
    assert relogged["applied"] == "Hackneyed 48 explicit", relogged
    assert hyprland_environment()[1] == {"XCURSOR_THEME": "Hackneyed", "XCURSOR_SIZE": "48"}, hyprland_environment()
    assert option("cursor:hide_on_key_press") in (1, True), "looknfeel.lua read the stored choice"
    assert float(option("cursor:inactive_timeout")) == 3.0
    assert drawn("hackneyed-relogin") > 0.55, results
    machine.screenshot("relogin")

    # ---- back to Bibata, and the download removed --------------------------
    # Left-handed was asked for above; Bibata has a mirrored version.
    assert user("cybexos-runtime ipc pointer use Bibata-Modern-Classic").strip() == "ok"
    assert wait(lambda: pointer().get("applied") == "Bibata-Modern-Classic-Right 48 explicit", 60), pointer()
    assert gsetting("cursor-theme") == "'Bibata-Modern-Classic-Right'"
    assert user("cybexos-runtime ipc pointer remove Hackneyed").strip() == "ok"
    removed = wait(lambda: (lambda s: s if not s.get("removing") and not {t["id"]: t for t in s["themes"]}["Hackneyed"]["installed"] else None)(pointer()), 60)
    assert removed and not removed["failure"], pointer()
    machine.fail(f"test -e {ROOT} -o -L {ROOT}")
    machine.fail(f"test -L {HOME}/.local/share/icons/Hackneyed")
    assert "cybexos/pointer" not in machine.succeed(f"nix-store -q --roots {STORE}")
    machine.succeed(f"nix-store --delete {STORE}")
    assert drawn("bibata-again") < 0.45, results

    journal = machine.succeed("journalctl _SYSTEMD_USER_UNIT=quickshell.service -b --no-pager -o cat")
    (out / "quickshell.log").write_text(journal)
    (out / "pointer-results.json").write_text(json.dumps(results, indent=2) + "\n")
    errors = [line for line in journal.splitlines() if QML_ERRORS.search(line) and "Pointer" in line]
    assert not errors, "\n".join(errors)
    warnings = [line for line in journal.splitlines() if "pointer:" in line]
    assert not warnings, "\n".join(warnings)
  '';
}
