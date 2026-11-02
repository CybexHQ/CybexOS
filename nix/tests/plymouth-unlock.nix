# The disk unlock screen of an installed system: the packaged Plymouth theme
# in a real systemd initrd, asked for a passphrase by systemd-cryptsetup
# through Plymouth's own password agent, typed on the VM's keyboard. A LUKS
# volume is formatted on the first boot and unlocked in the initrd of the
# second, after a wrong passphrase first. The screenshots show the field 40
# pixels under the logo with nothing drawn between them or beside it (no
# character stands on the field), bullets appearing as the passphrase is
# typed, and the same at double scale, through plymouthd and `plymouth
# ask-for-password` in the booted system, as nix/tests/lifecycle.nix runs it.
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

    PASSPHRASE = "cybex-unlocks-this"
    # On the 1280x800 display the logo (189x44) is centred 38% down, so it
    # ends at y 326; the field (286x48) starts 40 pixels lower, at 497..783 x
    # 366..414. At double scale every logical pixel is two: the logo ends at
    # y 348 and the field spans 354..926 x 428..524.
    GAP, FIELD, BELOW = (480, 330, 800, 362), (497, 366, 783, 414), (300, 330, 980, 800)
    GAP2, FIELD2, BELOW2 = (340, 352, 940, 424), (354, 428, 926, 524), (300, 352, 980, 800)

    def crop(name, box):
        return Image.open(machine.out_dir / f"{name}.png").convert("RGB").crop(box).tobytes()

    def lit(a):
        """Pixels that are not the black background."""
        return sum(1 for i in range(0, len(a), 3) if max(a[i:i + 3]) > 24)

    def changed(a, b):
        """How many pixels of two crops differ."""
        return sum(1 for i in range(0, len(a), 3) if a[i:i + 3] != b[i:i + 3])

    def brand_red(a):
        """Pixels of the brand red that Wiz's hat band used: none may remain."""
        return sum(1 for i in range(0, len(a), 3)
                   if abs(a[i] - 0xDC) <= 40 and abs(a[i + 1] - 0x1E) <= 40 and abs(a[i + 2] - 0x37) <= 40)

    def plain_field(name, gap=GAP, field=FIELD, below=BELOW):
        assert lit(crop(name, field)) > 500, f"{name}: the passphrase field is missing"
        assert lit(crop(name, gap)) == 0, f"{name}: something is drawn between the logo and the field"
        assert brand_red(crop(name, below)) == 0, f"{name}: a picture is drawn by the field"

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
    machine.screenshot("01-empty")
    machine.send_chars("not-the-passphrase")
    time.sleep(1)
    machine.screenshot("02-typing")
    machine.send_key("ret")
    time.sleep(0.3)
    machine.screenshot("03-checking")
    machine.wait_for_console_text("Passphrase incorrect")
    time.sleep(2)
    machine.screenshot("04-asked-again")
    machine.send_chars(PASSPHRASE)
    machine.send_key("ret")
    machine.wait_for_console_text("Finished Cryptography Setup for cryptdata")
    machine.wait_for_unit("multi-user.target")
    for name in ("01-empty", "02-typing", "04-asked-again"):
        plain_field(name)
    # While the passphrase is checked the field gives way to the progress bar;
    # nothing appears above it.
    assert lit(crop("03-checking", GAP)) == 0, "03-checking: something is drawn under the logo"
    assert changed(crop("01-empty", FIELD), crop("02-typing", FIELD)) > 100, "typing shows no bullets"
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
    machine.screenshot("09-double-scale-empty")
    machine.send_chars("double")
    time.sleep(1)
    machine.screenshot("10-double-scale-typing")
    machine.send_key("ret")
    machine.wait_until_succeeds("grep -q double /run/cybexos-plymouth-answer", timeout=30)
    # What systemd sends when a cryptsetup unit has started.
    machine.succeed("plymouth update --status=systemd-cryptsetup@check.service")
    time.sleep(0.5)
    machine.screenshot("11-double-scale-unlocked")
    machine.succeed("plymouth quit")
    for name in ("09-double-scale-empty", "10-double-scale-typing"):
        plain_field(name, GAP2, FIELD2, BELOW2)
    assert lit(crop("11-double-scale-unlocked", GAP2)) == 0, "something appeared under the logo after the unlock"
    assert changed(crop("09-double-scale-empty", FIELD2), crop("10-double-scale-typing", FIELD2)) > 100, \
        "typing shows no bullets at double scale"
    debug_log = machine.succeed("cat /run/cybexos-plymouth.log")
    (machine.out_dir / "plymouth-double-scale.log").write_text(debug_log)
    machine.fail("journalctl --no-pager -u cybexos-plymouth-test | grep -i 'parser error'")
    machine.fail("grep -Ei 'parser error|failed to load.*cybexos' /run/cybexos-plymouth.log")
  '';
}
