# Settings -> Security -> Sudo without password (docs/sudo.md) on a booted
# Cybex OS system: the Settings bridge asks Polkit, pkexec runs the declared
# helper as root, and the real sudo stops and starts asking for the password,
# across a restart. A test-only Polkit rule answers the administrator prompt
# for the primary user; ISO qualification types the password into the
# desktop's own agent instead (scripts/qualify-installations).
{ pkgs, module }:
pkgs.testers.runNixOSTest {
  name = "cybexos-passwordless-sudo";
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    cybexos = {
      enable = true; primaryUser = "tester";
      features = { proprietary = false; steam = false; docker = false; };
    };
    users.users.tester.initialPassword = "qualification-only";
    users.users.other = { isNormalUser = true; initialPassword = "qualification-only"; };
    networking.hostName = "machine";
    boot.loader.systemd-boot.enable = lib.mkForce false;
    system.stateVersion = "26.05";
    virtualisation = { memorySize = 4096; cores = 4; qemu.options = [ "-no-user-config" ]; };
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.cybexos.passwordless-sudo" && subject.user == "tester")
          return polkit.Result.YES;
      });
    '';
  };
  testScript = ''
    import json, shlex

    def settings(user, request):
        # The shell's own bridge, with the clean environment a desktop gives it.
        script = machine.succeed("cybexos-runtime path quickshell").strip() + "/scripts/system-settings.py"
        command = f"echo {shlex.quote(json.dumps(request))} | runuser -u {user} -- env -i PATH=/run/wrappers/bin:/run/current-system/sw/bin python3 -B {script} passwordless-sudo"
        return json.loads(machine.succeed(command))

    def passwordless():
        return machine.execute("runuser -u tester -- sudo -n true")[0] == 0

    machine.start()
    machine.wait_for_unit("multi-user.target")
    # Off on a fresh system: sudo asks, and the declared rule directory is empty.
    snapshot = settings("tester", {"action": "snapshot"})
    assert snapshot == {"success": True, "available": True, "passwordRequired": True,
                        "enabled": False, "user": "tester"}, snapshot
    assert not passwordless()
    machine.succeed("test \"$(stat -c '%a %U' /var/lib/cybexos/passwordless-sudo)\" = '755 root'")
    machine.succeed("tail -n 2 /etc/sudoers | grep -qx '@includedir /var/lib/cybexos/passwordless-sudo'")
    # pkexec runs exactly the helper the Polkit action names.
    helper = machine.succeed("realpath /run/current-system/sw/bin/cybexos-passwordless-sudo").strip()
    machine.succeed(f"pkaction --action-id org.cybexos.passwordless-sudo --verbose | grep -F 'org.freedesktop.policykit.exec.path -> {helper}'")
    # Without an approved prompt nothing changes.
    denied = settings("other", {"action": "set-enabled", "enabled": True})
    assert not denied["success"] and "cancelled or denied" in denied["error"], denied
    assert not passwordless()

    enabled = settings("tester", {"action": "set-enabled", "enabled": True})
    assert enabled["success"] and enabled["enabled"], enabled
    assert passwordless()
    assert machine.succeed("runuser -u tester -- sudo -n id -u").strip() == "0"
    # The wheel rule's SETENV still holds, and nobody else gained anything.
    assert machine.succeed("runuser -u tester -- sudo -n CYBEX_SUDO=kept printenv CYBEX_SUDO").strip() == "kept"
    machine.fail("runuser -u other -- sudo -n true")
    machine.succeed("visudo -c")
    machine.succeed("test \"$(stat -c '%a %U' /var/lib/cybexos/passwordless-sudo/rule)\" = '440 root'")
    assert machine.succeed("ls -A /var/lib/cybexos/passwordless-sudo").split() == ["operation.lock", "rule"]

    # The choice is state, not a generation: it survives a restart.
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    assert settings("tester", {"action": "snapshot"})["enabled"]
    assert passwordless()

    disabled = settings("tester", {"action": "set-enabled", "enabled": False})
    assert disabled["success"] and not disabled["enabled"], disabled
    assert not passwordless()
    machine.succeed("test ! -e /var/lib/cybexos/passwordless-sudo/rule")
  '';
}
