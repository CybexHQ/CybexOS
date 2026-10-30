# The disk unlock screen of an installed system: the packaged Plymouth theme
# in a real systemd initrd, asked for a passphrase by systemd-cryptsetup
# through Plymouth's own password agent, typed on the VM's keyboard. A LUKS
# volume is formatted on the first boot and unlocked in the initrd of the
# second. The screenshots show Wiz on the empty field (asleep), while typing
# (listening), while a wrong passphrase is checked and after it (sorry), and
# once the volume unlocked (happy). Last, the same theme at double scale,
# through plymouthd and `plymouth ask-for-password` in the booted system, as
# nix/tests/lifecycle.nix runs it, with the status systemd sends for a started
# cryptsetup unit, after which Wiz leaves. Each pose is checked in its
# screenshot: there, and different from or the same as the others.
#
# Only the theme and the installed systems' quiet kernel parameters are taken
# from the Cybex OS module (nix/modules/default.nix). Plymouth keeps to its
# graphical splash with the instrumentation's serial console; journald copies
# the initrd's messages to it, so the test knows when a passphrase is asked
# for and how it was answered. This is VM qualification of the theme and its
# callbacks, not of physical displays or keyboards.
{ pkgs, plymouth }:
pkgs.testers.runNixOSTest {
  name = "cybexos-plymouth-unlock";
  extraPythonPackages = p: [ p.pillow ];
  # The console waits have no timeouts of their own.
  globalTimeout = 1200;
  nodes.machine = { lib, ... }: {
    boot.initrd.systemd.enable = true;
    boot.plymouth = { enable = true; theme = "cybexos"; themePackages = [ plymouth ]; };
    boot.kernelParams = [
      "quiet" "udev.log_level=3" "rd.udev.log_level=3"
      "systemd.show_status=false" "rd.systemd.show_status=false" "vt.global_cursor_default=0"
      "plymouth.ignore-serial-consoles" "systemd.journald.forward_to_kmsg=1" "printk.devkmsg=on"
    ];
    # The VM module empties boot.initrd.luks.devices; mkVMOverride wins.
    boot.initrd.luks.devices = lib.mkVMOverride { cryptdata.device = "/dev/vdb"; };
    # An installed system's root file system needs its volume in the initrd.
    # Nothing needs this one: the initrd waits for it, but only wants it, so
    # the first boot continues past the blank disk.
    boot.initrd.systemd.targets.cryptsetup.wantedBy = [ "initrd.target" ];
    boot.initrd.systemd.targets.initrd.after = [ "cryptsetup.target" ];
    environment.systemPackages = [ pkgs.cryptsetup ];
    virtualisation = {
      memorySize = 2048;
      emptyDiskImages = [ 64 ];
      graphics = true;
      # The installation harness's display.
      qemu.options = [ "-no-user-config" "-device virtio-vga,xres=1280,yres=800" ];
    };
    system.stateVersion = "26.05";
  };
  testScript = let
    sink = pkgs.writeShellScript "cybexos-plymouth-answer" ''
      ${pkgs.coreutils}/bin/cat > /run/cybexos-plymouth-answer
    '';
  in ''
    import time
    from PIL import Image

    PASSPHRASE = "wiz-unlocks-this"
    # Wiz's box above the field on the 1280x800 display, below the logo
    # (centred 38% down, 44 high) and his 16-pixel gap: at one and at double
    # scale. The field and its bullets stay outside.
    WIZ = (590, 336, 690, 418)
    WIZ_DOUBLE = (540, 372, 740, 532)

    def wiz(name, box=WIZ):
        return Image.open(machine.out_dir / f"{name}.png").convert("RGB").crop(box).tobytes()

    def changed(a, b):
        """How many pixels of two crops differ."""
        return sum(1 for i in range(0, len(a), 3) if a[i:i + 3] != b[i:i + 3])

    def hat_band(a):
        """Pixels of his hat's brand red: he is there."""
        return sum(1 for i in range(0, len(a), 3)
                   if abs(a[i] - 0xDC) <= 40 and abs(a[i + 1] - 0x1E) <= 40 and abs(a[i + 2] - 0x37) <= 40)

    def same_pose(a, b):
        assert changed(wiz(a), wiz(b)) < 20, f"{a} and {b} should show the same pose"

    def other_pose(a, b, box=WIZ):
        assert changed(wiz(a, box), wiz(b, box)) > 100, f"{a} and {b} should show different poses"

    machine.start()
    machine.wait_for_unit("multi-user.target")
    # PBKDF2 for a second, so the check of a passphrase can be seen.
    machine.succeed(f"echo -n {PASSPHRASE} | cryptsetup luksFormat -q --type luks2 --pbkdf pbkdf2 --iter-time 1000 /dev/vdb -")
    # Consume the first boot's console, so the second boot's lines are new.
    machine.succeed("echo cybexos-first-boot-done > /dev/ttyS0")
    machine.wait_for_console_text("cybexos-first-boot-done")
    machine.shutdown()

    machine.start()
    machine.wait_for_console_text("Starting Cryptography Setup for cryptdata")
    time.sleep(5)
    machine.screenshot("01-asleep")
    machine.send_chars("not-the-passphrase")
    time.sleep(1)
    machine.screenshot("02-listening")
    machine.send_key("ret")
    time.sleep(0.3)
    machine.screenshot("03-checking")
    machine.wait_for_console_text("Passphrase incorrect")
    time.sleep(2)
    machine.screenshot("04-sorry")
    machine.send_chars("wiz")
    time.sleep(1)
    machine.screenshot("05-listening-again")
    for _ in "wiz":
        machine.send_key("backspace")
    time.sleep(1)
    machine.screenshot("06-sorry-cleared")
    machine.send_chars(PASSPHRASE)
    machine.send_key("ret")
    machine.wait_for_console_text("Finished Cryptography Setup for cryptdata")
    # systemd tells Plymouth the unit started just after logging it; he is
    # happy for two seconds.
    time.sleep(0.7)
    machine.screenshot("07-happy")
    machine.wait_for_unit("multi-user.target")
    for name in ("01-asleep", "02-listening", "04-sorry", "07-happy"):
        assert hat_band(wiz(name)) > 10, f"{name}: Wiz is missing above the field"
    other_pose("01-asleep", "02-listening")
    # He keeps listening while the passphrase is checked, and again later.
    same_pose("02-listening", "03-checking")
    same_pose("02-listening", "05-listening-again")
    other_pose("04-sorry", "01-asleep")
    other_pose("04-sorry", "02-listening")
    # Still sorry once the retry's field is empty again.
    same_pose("04-sorry", "06-sorry-cleared")
    other_pose("07-happy", "02-listening")
    machine.succeed("test -b /dev/mapper/cryptdata")
    # Script errors fail silently on screen; Plymouth reports them on stderr.
    machine.fail("journalctl -b --no-pager -u plymouth-start.service | grep -i 'parser error'")

    # The same theme at double scale: the script plugin draws every picture at
    # one pixel per logical pixel, so Plymouth enlarges them.
    machine.succeed("systemd-run --unit=cybexos-plymouth-test --service-type=exec -- $(command -v plymouthd) --no-daemon --mode=boot --tty=/dev/tty2 --kernel-command-line='quiet splash plymouth.ignore-serial-consoles plymouth.force-scale=2' --debug --debug-file=/run/cybexos-plymouth.log")
    machine.wait_until_succeeds("plymouth --ping", timeout=30)
    machine.succeed("plymouth --show-splash; chvt 2")
    machine.succeed("systemd-run --unit=cybexos-plymouth-ask --service-type=exec -- $(command -v plymouth) ask-for-password --prompt='Unlock Cybex OS qualification disk' --command=${sink}")
    time.sleep(2)
    machine.screenshot("09-double-scale-asleep")
    machine.send_chars("double")
    time.sleep(1)
    machine.screenshot("10-double-scale-listening")
    machine.send_key("ret")
    machine.wait_until_succeeds("grep -q double /run/cybexos-plymouth-answer", timeout=30)
    # What systemd sends when a cryptsetup unit has started.
    machine.succeed("plymouth update --status=systemd-cryptsetup@check.service")
    time.sleep(0.5)
    machine.screenshot("11-double-scale-happy")
    # Then he leaves.
    time.sleep(2.5)
    machine.screenshot("12-double-scale-gone")
    machine.succeed("plymouth quit")
    for name in ("09-double-scale-asleep", "10-double-scale-listening", "11-double-scale-happy"):
        assert hat_band(wiz(name, WIZ_DOUBLE)) > 40, f"{name}: Wiz is missing above the field"
    other_pose("09-double-scale-asleep", "10-double-scale-listening", WIZ_DOUBLE)
    other_pose("10-double-scale-listening", "11-double-scale-happy", WIZ_DOUBLE)
    assert hat_band(wiz("12-double-scale-gone", WIZ_DOUBLE)) == 0, "Wiz stayed after the unlock"
    debug_log = machine.succeed("cat /run/cybexos-plymouth.log")
    (machine.out_dir / "plymouth-double-scale.log").write_text(debug_log)
    machine.fail("journalctl --no-pager -u cybexos-plymouth-test | grep -i 'parser error'")
    machine.fail("grep -Ei 'parser error|failed to load.*cybexos' /run/cybexos-plymouth.log")
  '';
}
