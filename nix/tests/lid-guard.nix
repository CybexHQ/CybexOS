# Real logind, DRM udev events and a virtual input lid in a disposable VM.
# Only DRM status files and the final sleep operation are fixtures: no physical
# display, firmware sleep or desktop lock qualification is claimed here.
{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.evdev ]);
  lid = pkgs.writeText "cybexos-test-lid.py" ''
    import os
    from evdev import UInput, ecodes
    with UInput({ecodes.EV_SW: [ecodes.SW_LID]}, name='Cybex OS test lid') as device:
        os.mkfifo('/run/test-lid', 0o600)
        with os.fdopen(os.open('/run/test-lid', os.O_RDWR)) as commands:
            for command in commands:
                device.write(ecodes.EV_SW, ecodes.SW_LID, int(command.strip()))
                device.syn()
  '';
  sleep = pkgs.writeShellScript "cybexos-test-sleep" ''
    echo sleep >> /run/test-sleeps
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-lid-guard";
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/power.nix ];
    options.cybexos = {
      enable = lib.mkEnableOption "Cybex OS test policy";
      updates.additionalHealthServices = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    };
    config = {
      cybexos.enable = true;
      boot.kernelModules = [ "uinput" ];
      services.logind.settings.Login.HoldoffTimeoutSec = 1;
      systemd.tmpfiles.rules = [
        "d /run/test-drm/card1-DP-1 0755 root root -"
        "f /run/test-drm/card1-DP-1/status 0644 root root - connected"
        "f /run/test-drm/card1-DP-1/enabled 0644 root root - disabled"
      ];
      systemd.services.cybexos-lid-guard = {
        # Mount the fixture only into the guard. logind and udev remain real.
        serviceConfig.BindReadOnlyPaths = [ "/run/test-drm:/sys/class/drm" ];
      };
      systemd.services.test-lid = {
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-logind.service" ];
        serviceConfig.ExecStart = "${python}/bin/python3 ${lid}";
      };
      systemd.services.systemd-suspend.serviceConfig.ExecStart = lib.mkForce [ "" "${sleep}" ];
      virtualisation = { memorySize = 1024; cores = 2; graphics = true; qemu.options = [ "-no-user-config" ]; };
      system.stateVersion = "26.05";
    };
  };
  testScript = ''
    import time

    def lid(closed):
        machine.succeed("echo " + str(int(closed)) + " > /run/test-lid")
        expected = "true" if closed else "false"
        machine.wait_until_succeeds("busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed | grep -w " + expected)

    def output(status):
        machine.succeed("echo " + status + " > /run/test-drm/card1-DP-1/status")
        machine.succeed("udevadm trigger --action=change --subsystem-match=drm; udevadm settle")

    def sleeps():
        return int(machine.succeed("if test -f /run/test-sleeps; then wc -l < /run/test-sleeps; else echo 0; fi").strip())

    def inhibited():
        return machine.execute("systemd-inhibit --list --no-pager | grep -F 'Cybex OS external display'")[0] == 0

    machine.start()
    machine.wait_for_unit("cybexos-lid-guard.service")
    machine.wait_for_unit("test-lid.service")
    machine.wait_until_succeeds("test -p /run/test-lid")
    machine.wait_until_succeeds("journalctl -b -u systemd-logind --no-pager | grep -F 'Cybex OS test lid'")
    # Ensure this test has an actual DRM device/event source to trigger.
    machine.succeed("test -n \"$(find /sys/class/drm -name card0 -print)\"")
    assert inhibited()
    lid(True)
    time.sleep(4)
    assert sleeps() == 0, 'DPMS-disabled connected output must keep lid handling inhibited'

    # The updater must be able to restart the guard while the lid is closed
    # and the external output is disabled, with no inhibitor gap.
    before = machine.succeed("systemctl show cybexos-lid-guard -p MainPID --value")
    machine.succeed("systemctl restart cybexos-lid-guard.service")
    after = machine.succeed("systemctl show cybexos-lid-guard -p MainPID --value")
    assert before != after and inhibited()
    time.sleep(4)
    assert sleeps() == 0, 'service restart exposed logind to the closed lid'

    output('disconnected')
    time.sleep(0.6)
    output('connected')
    time.sleep(4)
    assert inhibited() and sleeps() == 0, 'subsecond dropout caused suspend'

    start = time.monotonic()
    output('disconnected')
    time.sleep(1)
    assert inhibited() and sleeps() == 0, 'disconnect was not debounced'
    machine.wait_until_succeeds("test -s /run/test-sleeps", timeout=10)
    elapsed = time.monotonic() - start
    lid(False)
    assert elapsed >= 3, elapsed
    assert not inhibited(), 'sustained disconnect must restore logind lid handling'

    # No external connection: a fresh lid close must not wait for the grace.
    previous = sleeps()
    start = time.monotonic()
    lid(True)
    machine.wait_until_succeeds("test $(wc -l < /run/test-sleeps) -gt " + str(previous), timeout=5)
    elapsed = time.monotonic() - start
    lid(False)
    assert elapsed < 3, elapsed

    # The inhibitor covers only lid handling: explicit sleep still works.
    output('connected')
    machine.wait_until_succeeds("systemd-inhibit --list --no-pager | grep -F 'Cybex OS external display'")
    previous = sleeps()
    machine.succeed("systemctl suspend")
    machine.wait_until_succeeds("test $(wc -l < /run/test-sleeps) -gt " + str(previous), timeout=5)
    assert sleeps() > previous and inhibited()

    machine.succeed("systemctl restart systemd-logind.service")
    machine.wait_for_unit("cybexos-lid-guard.service")
    machine.wait_until_succeeds("systemd-inhibit --list --no-pager | grep -F 'Cybex OS external display'")
    machine.succeed("systemctl stop cybexos-lid-guard.service")
    assert not inhibited(), 'stopping the guard leaked its stored inhibitor'
    machine.succeed("systemctl start cybexos-lid-guard.service")
    assert inhibited()
    machine.fail("journalctl -b -u cybexos-lid-guard --no-pager | grep -E 'Traceback|Failed to store|Failed to remove'")
  '';
}
