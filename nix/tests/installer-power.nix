# Exercise the real installerd socket and systemd shutdown in a disposable VM.
# Only the disk worker is replaced: no disk is erased, and the daemon's power
# command, logind, inhibitor and reboot/poweroff paths remain real.
{ pkgs }:
let
  fixture = pkgs.writeText "installer-power-fixture.py" ''
    import asyncio, importlib.machinery, importlib.util
    from pathlib import Path
    loader = importlib.machinery.SourceFileLoader('installerd', '${../../installer/cybexos-installerd}')
    spec = importlib.util.spec_from_loader(loader.name, loader)
    daemon = importlib.util.module_from_spec(spec)
    loader.exec_module(daemon)

    class Fixture(daemon.Daemon):
        async def start_worker(self):
            phase = Path('/run/installer-phase')
            self.update(phase=phase.read_text().strip() if phase.exists() else 'complete',
                        result={'username': 'tester', 'hostname': 'machine', 'encrypted': True})

    asyncio.run(Fixture(network_helper="").serve())
  '';
  client = pkgs.writeText "installer-power-client.py" ''
    import json, socket, sys
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(20)
        connection.connect('/run/cybexos-installer/control.sock')
        stream = connection.makefile('rwb', buffering=0)
        # Consume the initial messages before sending the action.
        while True:
            initial = json.loads(stream.readline())
            if initial['type'] == 'state':
                break
        if sys.argv[1] == 'status':
            print(json.dumps({'phase': initial['phase'], 'power': initial['power']}), flush=True)
            sys.exit(0)
        stream.write((json.dumps({'action': 'power', 'kind': sys.argv[1]}) + '\n').encode())
        while True:
            message = json.loads(stream.readline())
            if message['type'] == 'state' and (message['power']['busy'] or message['power']['error']):
                print(json.dumps({'phase': message['phase'], 'power': message['power']}), flush=True)
                break
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-installer-power";
  nodes.machine = {
    systemd.services.installer-power-fixture = {
      wantedBy = [ "multi-user.target" ];
      environment = {
        PYTHONPATH = "${../../lifecycle}";
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
        CYBEXOS_INSTALLER_SOFTWARE = "${../../desktop/software}";
      };
      path = [ pkgs.systemd pkgs.coreutils ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -B ${fixture}";
    };
    # A real shutdown blocker models another live session/application.
    systemd.services.shutdown-blocker = {
      serviceConfig.ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=shutdown --mode=block --who=installer-test ${pkgs.coreutils}/bin/sleep infinity";
    };
    environment.systemPackages = [ pkgs.python3 ];
    virtualisation = { memorySize = 1024; cores = 2; qemu.options = [ "-no-user-config" ]; };
    system.stateVersion = "26.05";
  };
  testScript = ''
    import datetime as dt
    import json

    def shutdown(kind):
        machine.log(str(machine.execute("python3 ${client} " + kind)))
        try:
            machine.wait_for_shutdown(timeout=dt.timedelta(seconds=45))
        except Exception:
            machine.log(machine.succeed("python3 ${client} status"))
            machine.log(machine.succeed("journalctl -b -u installer-power-fixture -u systemd-logind --no-pager; systemd-inhibit --list --no-pager"))
            raise

    machine.start()
    machine.wait_for_unit("installer-power-fixture.service")
    machine.wait_until_succeeds("test -S /run/cybexos-installer/control.sock")

    # The service's guard refuses all shutdown actions during disk writing.
    machine.succeed("echo installing > /run/installer-phase; systemctl restart installer-power-fixture.service")
    machine.wait_until_succeeds("test -S /run/cybexos-installer/control.sock")
    for kind in ("reboot", "poweroff", "firmware"):
        state = json.loads(machine.succeed("python3 ${client} " + kind))
        assert state["phase"] == "installing" and not state["power"]["busy"], state
        assert "Installation is in progress" in state["power"]["error"], state

    machine.succeed("echo complete > /run/installer-phase; systemctl restart installer-power-fixture.service")
    machine.wait_until_succeeds("test -S /run/cybexos-installer/control.sock")
    machine.succeed("systemctl start shutdown-blocker.service")
    machine.wait_until_succeeds("systemd-inhibit --list --no-pager | grep installer-test")
    before = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    shutdown("reboot")
    machine.start()
    machine.wait_for_unit("installer-power-fixture.service")
    assert machine.succeed("cat /proc/sys/kernel/random/boot_id").strip() != before

    machine.wait_until_succeeds("test -S /run/cybexos-installer/control.sock")
    machine.succeed("systemctl start shutdown-blocker.service")
    machine.wait_until_succeeds("systemd-inhibit --list --no-pager | grep installer-test")
    shutdown("poweroff")
  '';
}
