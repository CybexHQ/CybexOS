# What NixOS activation restarts in a signed-in Cybex OS desktop.
#
# Installing or removing apps must leave the shell (quickshell.service) and
# the assistant (cybexos-assistant.service) running: their MainPIDs stay the
# same and a newly installed program is on their PATH at once. A change to
# either service still reaches it: activation restarts a changed shell, and a
# changed assistant restarts itself once idle, never during an answer.
#
# The changes are switched with the same switch-to-configuration `test` the
# updater's apply runs, between specialisations of one system:
#   app        adds a program (hello) and nothing else;
#   desktop    the same, with a changed quickshell.service;
#   assistant  the same again, with a changed cybexos-assistant.service too.
# switch-to-configuration decides from the unit files alone, so a marker in
# the unit stands in for a new desktop or assistant build; the review and the
# activation see the same difference either way. The review is the updater's
# own Engine.session_restarts on the two built systems. Staging and applying
# through `cybex update` with a candidate built in the VM is covered by
# nix/tests/lifecycle.nix (staging) and is not repeated here.
#
# The assistant answers through a scripted stand-in for Claude Code that
# holds its answer open until the test has switched the system, then reports
# whether the newly installed program is there: the answer an update would
# report after the assistant applied it.
#
# Test-only settings: SDDM signs the user in directly (Cybex OS's own automatic
# login requires verified LUKS), and Claude Code is the stand-in above.
{ pkgs, module }:
let
  marker = "/run/cybexos-qualification/switched";
  # Claude Code's stream-json protocol, as far as the assistant uses it.
  fakeClaude = pkgs.writers.writePython3Bin "claude" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys
    import time

    if sys.argv[1:2] == ["auth"]:
        sys.exit(0)


    def emit(message):
        sys.stdout.write(json.dumps(message) + "\n")
        sys.stdout.flush()


    def say(text):
        emit({"type": "stream_event", "event": {"type": "content_block_delta",
                                                "delta": {"type": "text_delta", "text": text}}})


    emit({"type": "system", "subtype": "init", "session_id": "sess-vm"})
    for line in sys.stdin:
        message = json.loads(line)
        if message.get("type") != "user":
            continue
        emit({"type": "stream_event", "event": {"type": "message_start"}})
        say("Installing hello. ")
        while not os.path.exists("${marker}"):
            time.sleep(0.5)
        found = os.path.exists("/run/current-system/sw/bin/hello")
        text = "hello is installed." if found else "hello is missing."
        say(text)
        emit({"type": "result", "subtype": "success", "is_error": False, "result": text, "session_id": "sess-vm"})
  '';
  # The updater's own comparison of two built systems, through its runner.
  review = pkgs.writeText "cybexos-session-review.py" ''
    import json, sys
    from types import SimpleNamespace
    from cybexos.common import Runner
    from cybexos.engine import Engine
    from cybexos.review import session_notice
    rows = Engine.session_restarts(SimpleNamespace(run=Runner()), sys.argv[1], sys.argv[2])
    print(json.dumps({"rows": rows, "notice": session_notice(rows)}))
  '';
  sleeper = pkgs.makeDesktopItem {
    name = "cxo-sleeper";
    desktopName = "Qualification sleeper";
    exec = "${pkgs.coreutils}/bin/sleep 1777";
  };
in pkgs.testers.runNixOSTest ({ nodes, ... }: {
  name = "cybexos-session-restarts";
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    cybexos = { enable = true; primaryUser = "tester"; features = { proprietary = false; steam = false; docker = false; }; };
    networking.hostName = "machine";
    users.users.tester.initialPassword = "qualification-only";
    services.displayManager.autoLogin = { enable = true; user = "tester"; };
    environment.systemPackages = [ fakeClaude sleeper ];
    specialisation = let
      app = { environment.systemPackages = [ pkgs.hello ]; };
      desktop = lib.recursiveUpdate app {
        systemd.user.services.quickshell.environment.CYBEXOS_QUALIFICATION_REVISION = "desktop-2";
      };
      assistant = lib.recursiveUpdate desktop {
        systemd.user.services.cybexos-assistant.environment.CYBEXOS_QUALIFICATION_REVISION = "assistant-2";
      };
    in {
      app.configuration = app;
      desktop.configuration = desktop;
      assistant.configuration = assistant;
    };
    virtualisation = {
      memorySize = 6144;
      cores = 4;
      graphics = true;
      diskSize = 4096;
      qemu.options = [ "-no-user-config" ];
    };
    system.stateVersion = "26.05";
    boot.loader.systemd-boot.enable = lib.mkForce false;
  };
  testScript = ''
    import json
    import time

    machine.start()
    machine.wait_for_unit("display-manager.service")
    uid = machine.succeed("id -u tester").strip()
    session = f"XDG_RUNTIME_DIR=/run/user/{uid} HOME=/home/tester DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
    base = machine.succeed("readlink -f /run/current-system").strip()
    updater = "${nodes.machine.cybexos.updaterPackage}"

    def user(command):
        return machine.succeed(f"runuser -u tester -- env {session} {command}")

    def pid(unit):
        return int(user(f"systemctl --user show -p MainPID --value {unit}").strip())

    def shell_pids():
        return {name: pid(name) for name in ("quickshell.service", "cybexos-assistant.service")}

    def unit_environment(process):
        return dict(line.split("=", 1) for line in
                    machine.succeed(f"tr '\\0' '\\n' < /proc/{process}/environ").splitlines() if "=" in line)

    def cursor():
        return machine.succeed("journalctl -n 0 --show-cursor -q").strip().split("cursor: ", 1)[-1]

    def reviewed(before, after):
        return json.loads(machine.succeed(f"PYTHONPATH={updater}/lib ${pkgs.python3.interpreter} ${review} {before} {after}"))

    def switch(name):
        output = machine.succeed(f"{base}/specialisation/{name}/bin/switch-to-configuration test 2>&1")
        machine.log(output)
        return output

    def healthy():
        # The updater's own checks after activation, as apply and confirmation run them.
        machine.succeed("/run/current-system/sw/bin/cybexos-health system")
        machine.succeed("/run/current-system/sw/bin/cybexos-health desktop-required")

    def assistant_ready():
        machine.wait_until_succeeds(f"runuser -u tester -- env {session} cybexos-runtime ipc assistant status | grep -q available", timeout=120)

    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
    assistant_ready()
    machine.succeed("install -d -m 0755 /run/cybexos-qualification")
    healthy()

    # ---- an app alone ------------------------------------------------------
    app = f"{base}/specialisation/app"
    plan = reviewed(base, app)
    assert plan == {"rows": [], "notice": ""}, plan
    before = shell_pids()
    shell_path = unit_environment(before["quickshell.service"])["PATH"]
    # cybexos-runtime puts the desktop's own tools first; the machine's packages follow.
    assert "/run/current-system/sw/bin" in shell_path.split(":") and "system-path" not in shell_path, shell_path
    # Observation only: an app the shell starts, as the launcher and shortcuts
    # do, and whether it outlives a restart of the shell below.
    launched = user("cybexos-runtime ipc launcher launchDesktop cxo-sleeper.desktop").strip()
    machine.log(f"launcher answered {launched!r}")
    sleeper = None
    for _ in range(30):
        found, pids = machine.execute("pgrep -u tester -f '^${pkgs.coreutils}/bin/sleep 1777'")
        if found == 0:
            sleeper = pids.split()[0]
            machine.log("app started by the shell runs in " + machine.succeed(f"cat /proc/{sleeper}/cgroup"))
            break
        time.sleep(1)
    else:
        machine.log("the shell started no app process within 30 s")

    # The assistant is answering; its agent waits for the switch to finish.
    machine.succeed(f"runuser -u tester -- env {session} sh -c 'cybexos-assistant ask --agent claude install hello > /tmp/answer 2>&1; echo $? > /tmp/answer.status' >/dev/null 2>&1 &")
    machine.wait_until_succeeds("grep -q 'Installing hello' /tmp/answer", timeout=60)
    since = cursor()
    switch("app")
    machine.succeed("touch ${marker}")
    machine.succeed("test -x /run/current-system/sw/bin/hello")
    machine.wait_until_succeeds("test -e /tmp/answer.status", timeout=60)
    answer = machine.succeed("cat /tmp/answer")
    assert machine.succeed("cat /tmp/answer.status").strip() == "0", answer
    assert "hello is installed." in answer, answer
    time.sleep(10)
    after = shell_pids()
    assert after == before, (before, after)
    # The user manager logs its jobs with USER_UNIT=; none ran for either.
    jobs = machine.succeed(f"journalctl USER_UNIT=quickshell.service USER_UNIT=cybexos-assistant.service -b --no-pager -q --after-cursor='{since}' || true")
    assert not jobs.strip(), jobs
    # The new program is on both services' PATH right away.
    for process in after.values():
        machine.succeed(f"env PATH={unit_environment(process)['PATH']} sh -c 'command -v hello'")
    healthy()

    # ---- the desktop itself changed --------------------------------------------
    plan = reviewed(app, f"{base}/specialisation/desktop")
    assert plan["rows"] == [{"id": "desktop", "unit": "quickshell.service", "when": "apply"}], plan
    assert "restarts the desktop shell" in plan["notice"], plan
    switch("desktop")
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=60)
    restarted = shell_pids()
    assert restarted["quickshell.service"] not in (0, before["quickshell.service"]), restarted
    assert restarted["cybexos-assistant.service"] == before["cybexos-assistant.service"], restarted
    assert unit_environment(restarted["quickshell.service"]).get("CYBEXOS_QUALIFICATION_REVISION") == "desktop-2"
    if sleeper:
        survived = machine.succeed(f"test -e /proc/{sleeper} && echo running || echo ended").strip()
        machine.log(f"an app the shell had started {survived} after the shell restarted")
    assistant_ready()
    healthy()

    # ---- the assistant itself changed ----------------------------------------
    plan = reviewed(f"{base}/specialisation/desktop", f"{base}/specialisation/assistant")
    assert plan["rows"] == [{"id": "assistant", "unit": "cybexos-assistant.service", "when": "idle"}], plan
    assert "idle" in plan["notice"] and "desktop shell" not in plan["notice"], plan
    since = cursor()
    output = switch("assistant")
    # Activation leaves it running and does not restart the shell again ...
    assert pid("quickshell.service") == restarted["quickshell.service"]
    assert "NOT restarting the following user units: cybexos-assistant.service" in output, output
    # ... and the idle service restarts itself into the new unit.
    machine.wait_until_succeeds(f"journalctl _SYSTEMD_USER_UNIT=cybexos-assistant.service -b --no-pager --after-cursor='{since}' | grep -q 'restarting into it'", timeout=120)
    machine.wait_until_succeeds(f"test \"$(runuser -u tester -- env {session} systemctl --user show -p MainPID --value cybexos-assistant.service)\" -gt 0", timeout=60)
    renewed = pid("cybexos-assistant.service")
    assert renewed != before["cybexos-assistant.service"], renewed
    assert unit_environment(renewed).get("CYBEXOS_QUALIFICATION_REVISION") == "assistant-2"
    assert user("systemctl --user show -p Result --value cybexos-assistant.service").strip() == "success"
    assert pid("quickshell.service") == restarted["quickshell.service"]
    assistant_ready()
    # The answer given before the restart is still the box's last answer.
    status = json.loads(user("cybexos-assistant status"))
    assert status["turn"] and "hello is installed." in status["turn"]["text"], status["turn"]
    healthy()
    machine.fail("journalctl _SYSTEMD_USER_UNIT=quickshell.service -b --no-pager | grep -E 'TypeError|ReferenceError|is not a type'")
  '';
})
