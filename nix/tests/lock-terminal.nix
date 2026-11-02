# A signed-in Cybex OS desktop: the lock screen shows no Wiz beside its
# password field, and Wiz is in kitty, the default terminal, when fastfetch is
# typed at its fish prompt.
#
# The session locks as it does itself (cybexos-session-lock.service runs
# `cybexos-runtime exec hyprlock`), first with the lock screen the shell's
# system theme rendered, then with the vendor file, and is unlocked with the
# password each time. kitty is started through Hyprland, so its shell is
# kitty's own child, as on a desktop.
#
# Test-only settings: SDDM signs the user in directly (Cybex OS's own
# automatic login requires verified LUKS) and the display is fixed at
# 1280×800. This is VM qualification, not of physical displays.
{ pkgs, module }:
pkgs.testers.runNixOSTest {
  name = "cybexos-lock-terminal";
  extraPythonPackages = p: [ p.pillow ];
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
    import time
    from PIL import Image

    out = machine.out_dir

    machine.start()
    machine.wait_for_unit("display-manager.service")
    uid = machine.succeed("id -u tester").strip()
    session = f"XDG_RUNTIME_DIR=/run/user/{uid} HOME=/home/tester DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"

    def user(command):
        return machine.succeed(f"runuser -u tester -- env {session} {command}")

    def locked():
        return machine.execute(f"runuser -u tester -- env {session} hyprctl -i 0 locked")[1].strip() == "true"

    def wait(predicate, timeout):
        deadline = time.monotonic() + timeout
        while not predicate():
            assert time.monotonic() < deadline, "timed out"
            time.sleep(0.5)

    def pixels(name, box, colour, tolerance):
        """How many pixels in `box` of a screenshot are within `tolerance` of `colour`."""
        data = Image.open(out / f"{name}.png").convert("RGB").crop(box).tobytes()
        return sum(1 for i in range(0, len(data), 3)
                   if all(abs(data[i + c] - colour[c]) <= tolerance for c in range(3)))

    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} cybexos-runtime ipc welcome status", timeout=300)
    # The first sign-in's welcome guide would cover the terminal.
    time.sleep(5)
    user("cybexos-runtime ipc welcome close")
    machine.fail("test -e /run/current-system/sw/share/cybexos/wiz/lock")
    machine.succeed("test -s /run/current-system/sw/share/cybexos/wiz/terminal/idle.png")

    # ---- the lock screen ---------------------------------------------------
    # Right of the field, where Wiz used to sleep: the field ends at x 790 in
    # a 1280x800 output. Nothing there may be his hat band's brand red.
    WIZ = (790, 360, 875, 460)
    RED = (0xDC, 0x1E, 0x37)
    themed = "/home/tester/.local/state/cybexos/theme/hyprlock.conf"
    machine.wait_until_succeeds(f"test -s {themed}", timeout=120)

    def lock(name):
        machine.execute(f"runuser -u tester -- env {session} systemctl --user reset-failed cybexos-session-lock.service")
        user("systemctl --user start cybexos-session-lock.service")
        wait(locked, 30)
        time.sleep(3)
        machine.screenshot(name)
        rendered = machine.succeed(f"cat /run/user/{uid}/cybexos/hyprlock.conf")
        (out / f"{name}.conf").write_text(rendered)
        assert "image {" not in rendered and "wiz" not in rendered.lower(), rendered
        band = pixels(name, WIZ, RED, 40)
        machine.log(f"{name}: {band} hat band pixels right of the field")
        assert band == 0, f"{name}: Wiz is still beside the field ({band} pixels)"
        machine.send_chars("qualification-only\n")
        wait(lambda: not locked(), 30)
        time.sleep(1)

    lock("lock-themed")
    machine.succeed(f"head -n1 /run/user/{uid}/cybexos/hyprlock.conf | grep -F 'theme_hyprlock.py'")
    machine.succeed(f"rm {themed}")
    lock("lock-vendor")
    machine.fail(f"grep -F 'theme_hyprlock.py' /run/user/{uid}/cybexos/hyprlock.conf")

    # ---- the terminal --------------------------------------------------------
    user("hyprctl -i 0 dispatch 'hl.dsp.exec_cmd(\"kitty\")'")
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} hyprctl -i 0 -j clients | grep -q '\"class\": \"kitty\"'", timeout=60)
    time.sleep(5)

    # ---- the prompt icon -------------------------------------------------------
    # The shell writes the Control Center button's icon for fish, by default
    # the Cybex OS mark, which only Cybex OS Symbols has; kitty reaches it
    # through fontconfig. Switched to "os", the next prompt shows NixOS's.
    icon_file = "/home/tester/.local/state/cybexos/prompt-icon"
    machine.wait_until_succeeds(f"test -s {icon_file}", timeout=60)
    assert machine.succeed(f"cat {icon_file}") == "\U001000CB\n", machine.succeed(f"od -c {icon_file}")
    machine.succeed("fc-list ':charset=1000cb' family | grep -Fx 'Cybex OS Symbols'")
    PROMPT = (0, 40, 400, 120)
    machine.send_chars("clear\n")
    time.sleep(2)
    machine.screenshot("prompt-cybexos")
    machine.succeed(f"runuser -u tester -- sh -c 'printf \"os\\n\" > {icon_file}'")
    machine.send_chars("clear\n")
    time.sleep(2)
    machine.screenshot("prompt-os")
    mark, logo = (Image.open(out / f"{name}.png").convert("RGB").crop(PROMPT).tobytes()
                  for name in ("prompt-cybexos", "prompt-os"))
    differ = sum(1 for i in range(0, len(mark), 3) if mark[i:i + 3] != logo[i:i + 3])
    machine.log(f"prompt icon: {differ} pixels changed between the Cybex OS and NixOS icons")
    assert differ > 20, f"the prompt did not follow its icon file ({differ} pixels)"
    machine.send_chars("clear\n")
    time.sleep(1)
    machine.send_chars("fastfetch\n")
    time.sleep(8)
    machine.screenshot("terminal-kitty")
    # Wiz's hat crown, a colour the braille logo does not use, in the left
    # part of the window, where the logo is.
    crown = pixels("terminal-kitty", (0, 0, 640, 800), (0x35, 0x3A, 0x43), 6)
    machine.log(f"terminal-kitty: {crown} hat crown pixels")
    assert crown > 200, f"Wiz is not in kitty's fastfetch ({crown} pixels)"
  '';
}
