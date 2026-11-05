# Spotify on a 2× display: through XWayland as before, then natively on
# Wayland as the session now starts it (NIXOS_OZONE_WL, nix/modules/desktop.nix).
#
# Both runs start after Settings has chosen Bibata Modern Ice, a white arrow,
# in place of the installation's black Bibata Modern Classic. Each must show
# the chosen arrow over Spotify's window: through XWayland because GTK, which
# Chromium asks for the theme, reads it from XSETTINGS
# (cybexos-xsettings.service); natively because Hyprland draws it.
#
# How sharp each run renders is measured in Hyprland's own screen copy. An
# XWayland window is drawn at 1× and doubled with nearest-neighbour filtering,
# so neighbouring pixels in each 2×2 block are equal and every change of
# colour falls between blocks. A window drawn at the display's scale changes
# colour within blocks as often as between them.
#
# Test-only settings: SDDM signs the user in directly, the display is fixed at
# 2560×1600 at scale 2 and Hyprland draws the pointer in software (user.lua)
# so screen copies include it. There is no network, so Spotify shows what it
# shows offline. This is VM qualification, not of physical displays.
{ pkgs, module }:
let
  python = pkgs.python3.withPackages (p: [ p.pillow ]);
  # Sharpness inside a window, and the share of light pixels in the pointer.
  measure = pkgs.writeText "cybexos-wayland-scale-measure.py" ''
    import json, sys
    from PIL import Image
    command = sys.argv[1]
    if command == "sharpness":
        image = Image.open(sys.argv[2]).convert("RGB")
        x0, y0, x1, y1 = (int(value) for value in sys.argv[3:7])
        x0, y0 = x0 + (x0 & 1), y0 + (y0 & 1)
        pixels = image.load()
        def differ(a, b):
            return max(abs(p - q) for p, q in zip(a, b)) > 8
        inside = between = 0
        for y in range(y0, y1 - 2):
            for x in range(x0, x1 - 2):
                horizontal = differ(pixels[x, y], pixels[x + 1, y])
                vertical = differ(pixels[x, y], pixels[x, y + 1])
                # A pair within a 2×2 block, or one across its edge.
                inside += ((x - x0) % 2 == 0 and horizontal) + ((y - y0) % 2 == 0 and vertical)
                between += ((x - x0) % 2 == 1 and horizontal) + ((y - y0) % 2 == 1 and vertical)
        print(json.dumps({"inside": inside, "between": between,
                          "ratio": round(inside / between, 3) if between else None}))
    else:
        shown, hidden = (Image.open(path).convert("RGB") for path in sys.argv[2:4])
        x, y = int(sys.argv[4]), int(sys.argv[5])
        box = (x - 20, y - 20, x + 120, y + 120)
        pointer = [p for p, q in zip(shown.crop(box).getdata(), hidden.crop(box).getdata())
                   if max(abs(a - b) for a, b in zip(p, q)) > 12]
        light = [p for p in pointer if 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2] > 160]
        print(json.dumps({"pixels": len(pointer), "light": round(len(light) / len(pointer), 3) if pointer else None}))
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-wayland-scale";
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    cybexos = { enable = true; primaryUser = "tester"; features = { proprietary = false; steam = false; docker = false; }; };
    environment.systemPackages = [ pkgs.spotify ];
    networking.hostName = "machine";
    users.users.tester.initialPassword = "qualification-only";
    services.displayManager.autoLogin = { enable = true; user = "tester"; };
    systemd.tmpfiles.rules = [
      "d /home/tester/.config 0700 tester users -"
      "d /home/tester/.config/cybexos 0700 tester users -"
      ''f /home/tester/.config/cybexos/shell.json 0600 tester users - {"v":31,"assistantShown":false}''
      "d /home/tester/.config/cybexos/hypr 0700 tester users -"
      ''f /home/tester/.config/cybexos/hypr/user.lua 0600 tester users - hl.config({ cursor = { no_hardware_cursors = true } }) hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })''
    ];
    virtualisation = {
      memorySize = 8192;
      cores = 8;
      graphics = true;
      diskSize = 8192;
      qemu.options = [ "-no-user-config" "-device virtio-vga,xres=2560,yres=1600" ];
    };
    system.stateVersion = "26.05";
    boot.loader.systemd-boot.enable = lib.mkForce false;
  };
  testScript = ''
    import json
    import shlex
    import time
    from typing import Any

    HOME = "/home/tester"
    out = machine.out_dir
    results: dict[str, Any] = {}

    machine.start()
    machine.wait_for_unit("display-manager.service")
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

    def signature():
        environment = dict(line.split("=", 1) for line in user("systemctl --user show-environment").splitlines() if "=" in line)
        return environment["HYPRLAND_INSTANCE_SIGNATURE"]

    def hyprctl(arguments):
        return user(f"env HYPRLAND_INSTANCE_SIGNATURE={signature()} hyprctl {arguments}")

    def pointer():
        status, output = machine.execute(f"runuser -u tester -- env {session} cybexos-runtime ipc pointer status")
        try:
            return json.loads(output) if status == 0 else {}
        except ValueError:
            return {}

    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
    assert wait(lambda: pointer().get("loaded"), 180), pointer()
    status, opened = machine.execute(f"runuser -u tester -- env {session} cybexos-runtime ipc welcome status")
    if status == 0 and json.loads(opened).get("open"):
        user("cybexos-runtime ipc welcome close")
    monitors = json.loads(hyprctl("-j monitors"))
    assert [(m["width"], m["height"], m["scale"]) for m in monitors] == [(2560, 1600, 2.0)], monitors

    assert user("cybexos-runtime ipc pointer use Bibata-Modern-Ice").strip() == "ok"
    assert wait(lambda: pointer().get("applied") == "Bibata-Modern-Ice 24 explicit", 60), pointer()

    # ---- real pointer input and what Hyprland draws -----------------------
    def move(x, y):
        assert machine.qmp_client is not None
        arguments: Any = {"events": [{"type": "abs", "data": {"axis": axis, "value": round(value * 32767 / (extent - 1))}}
                                     for axis, value, extent in (("x", x, 1280), ("y", y, 800))]}
        machine.qmp_client.send("input-send-event", arguments)
        time.sleep(0.5)

    def grim(path):
        socket = machine.succeed(f"ls /run/user/{uid} | grep -m1 '^wayland-[0-9]*$'").strip()
        machine.succeed(f"runuser -u tester -- env {session} WAYLAND_DISPLAY={socket} ${pkgs.grim}/bin/grim -c {path}")

    def spotify():
        clients = json.loads(hyprctl("-j clients"))
        return next((c for c in clients if c["class"].lower() == "spotify" and c["mapped"] and c["size"][0] > 200), None)

    def prompts():
        return [c for c in json.loads(hyprctl("-j clients")) if c["class"] == "gcr-prompter"]

    def run(name, command, xwayland):
        hyprctl("dispatch " + shlex.quote(f'hl.dsp.exec_cmd("{command}")'))
        window = wait(spotify, 120)
        assert window, json.loads(hyprctl("-j clients"))
        assert window["xwayland"] is xwayland, window
        # Offline, Spotify settles on what it can show; give it time to draw.
        # Signed in without a password, the session has no keyring, and
        # Spotify asks for one to be made: declined, as a person could.
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if prompts():
                hyprctl("dispatch " + shlex.quote('hl.dsp.window.close({ window = "class:gcr-prompter" })'))
            time.sleep(1)
        assert not prompts(), prompts()
        time.sleep(3)
        window = spotify()
        (x, y), (w, h) = window["at"], window["size"]
        results[name + "-window"] = window
        # Over the window's middle, then away from it.
        cx, cy = x + w // 2, y + h // 2
        move(cx - 40, cy - 40)
        move(cx, cy)
        time.sleep(1.5)
        grim(f"/tmp/{name}-shown.png")
        move(cx + 300 if cx + 300 < 1270 else cx - 300, cy + 200 if cy + 200 < 790 else cy - 200)
        time.sleep(1.5)
        grim(f"/tmp/{name}-hidden.png")
        sharp = json.loads(machine.succeed(f"${python}/bin/python3 ${measure} sharpness /tmp/{name}-hidden.png "
                                           f"{2 * x + 16} {2 * y + 16} {2 * (x + w) - 16} {2 * (y + h) - 16}"))
        drawn = json.loads(machine.succeed(f"${python}/bin/python3 ${measure} pointer /tmp/{name}-shown.png "
                                           f"/tmp/{name}-hidden.png {2 * cx} {2 * cy}"))
        results[name] = {"sharpness": sharp, "pointer": drawn}
        machine.log(f"{name}: {json.dumps(results[name])}")
        for shot in ("shown", "hidden"):
            machine.copy_from_machine(f"/tmp/{name}-{shot}.png", "")
        machine.screenshot(name)
        # The wrapper execs share/spotify/.spotify-wrapped.
        machine.succeed("pkill -u tester -f '[s]hare/spotify/' || true")
        machine.wait_until_fails("pgrep -u tester -f '[s]hare/spotify/'", timeout=60)
        assert wait(lambda: spotify() is None, 30)
        return results[name]

    # Through XWayland, as Spotify ran before this session's switch.
    x11 = run("xwayland", "env -u NIXOS_OZONE_WL spotify", True)
    wayland = run("wayland", "spotify", False)
    (out / "wayland-scale-results.json").write_text(json.dumps(results, indent=2) + "\n")

    assert x11["sharpness"]["between"] > 2000 and wayland["sharpness"]["between"] > 2000, results
    assert x11["sharpness"]["ratio"] < 0.1, "XWayland doubles a 1× picture"
    assert wayland["sharpness"]["ratio"] > 0.5, "natively, Spotify draws at the display's scale"
    # The chosen white arrow in both, not the installation's black one.
    for measured in (x11["pointer"], wayland["pointer"]):
        assert measured["pixels"] > 150 and measured["light"] > 0.55, results
  '';
}
