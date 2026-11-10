# Connects the browsers to the 1Password desktop app as on a fresh
# installation: the welcome guide's Connect step opens the real 1Password,
# then Google Chrome (the browser with proprietary applications) and Brave
# Origin (installed through Software's selection, `brave-origin`) each start
# an extension with 1Password's extension id and ask for 1Password's native
# messaging host.
#
# 1Password writes that host into the browser profiles it knows, Chrome's,
# and Origin's only since 8.12.42. Cybex OS puts the same entry in Chrome's
# system directory and in Chromium's, which Origin reads. Chrome must find
# its system entry with its profile's own one removed, Origin either; the
# host must start through the NixOS setgid helper, accept each browser's
# executable and reach the running app, and the entries must match the ones
# this 1Password writes. Chrome, Chromium and Brave read the same policy
# file: 1Password installed for good, Claude in Chrome and ChatGPT added
# and free to turn off, and Chrome's own policy page lists it.
#
# The guide's 1Password card counts the accounts in 1Password's own database:
# there are none before a sign-in, so it shows no tick. With 1Password
# stopped, the check then adds an account row, and the card must show one.
#
# The guide finds 1Password by its desktop entry, com.onepassword.OnePassword
# since 8.12.42, although its windows keep the app id 1password. Coming back
# to the guide from 1Password closes 1Password's window, so it does not cover
# the assistant sign-in that follows. That sign-in runs in the background and
# opens only Chrome, no terminal. Chrome's first start shows Google's
# Additional Terms of Service before any page, in a window without an app id;
# it counts as Chrome's by its process. Leaving the guide then closes what Connect
# opened, while a window the person opened stays. The guide stays up until
# they are gone.
#
# Test-only settings: SDDM signs the user in directly; once the shipped
# policy is checked, the browsers get it without 1Password's forced install
# (the VM has no network for the store extension), and the probe carries the
# store extension's public key, which gives an unpacked extension the same
# id. Google Chrome ignores --load-extension, so the probe reaches it through
# the DevTools pipe, as browser automation loads one.
# 1Password is not signed in, and its main window does not draw in this
# VM; the browser link needs neither. Started again after the check stopped
# it, 1Password shows its crash reporter, a window of its own process, and
# that is the window Resume closes. Past it, the added row stops 1Password
# with a dialog saying it cannot start.
# Claude Code is a script that opens its sign-in page with xdg-open, as the
# real one does, and is signed in once the check says so. The added row is
# not a real account. This is VM qualification of the browser link and of
# the guide's reading of the database, not of a 1Password account, of
# autofill or of a Claude sign-in.
{ pkgs, module }:
let
  # The `key` of 1Password's Chrome Web Store manifest: its public key, whose
  # hash is the id aeblfdkhhhdcdjpifhhbdiojplfjncoa.
  key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnHpaUll4uWujpAdbIXOQY2WE6hk8PllsYsnoUaj5qHXwv4IB6A9pONqGaTL2KL20u6E6XVhncY6Ae6SQSBQqiIkgjPsiG0NDNsDlju/kzBnfimKFC/bpzOrqFqbhswQHifnet5uHlpG97whTzLO3ka0M5aqB9V9mD/0qVXvNgAVVnSTULH254YqpeCcAhmsKiFZSL6OrOZmCp8kZ/OeOUK9iYWYylL7VcOXVrZf10EPrlaCNXzVk7K35dPuQ7svhA0Pgju3kngB4RLa5Iojhw3IT+B5+m8pisjOSd1oKMrRmhGs7rDhF5IEtAiVxqVp7uOOMPQj3vrbMDAzf7vqLtQIDAQAB";
  probe = pkgs.linkFarm "cybexos-1password-probe" {
    "manifest.json" = pkgs.writeText "manifest.json" (builtins.toJSON {
      manifest_version = 3;
      name = "Cybex OS 1Password probe";
      version = "1";
      inherit key;
      permissions = [ "nativeMessaging" ];
      background.service_worker = "probe.js";
    });
    # Holds the host open as the extension does, and reports whether it stayed.
    "probe.js" = pkgs.writeText "probe.js" ''
      const port = chrome.runtime.connectNative("com.1password.1password");
      let open = true;
      port.onDisconnect.addListener(() => {
        open = false;
        console.log("CXO-PROBE closed: " + (chrome.runtime.lastError && chrome.runtime.lastError.message));
      });
      setTimeout(() => { if (open) console.log("CXO-PROBE open"); }, 8000);
    '';
  };
  launchBrave = pkgs.writeShellScript "cybexos-1password-brave" ''
    exec brave --no-first-run --disable-features=DisableLoadExtensionCommandLineSwitch \
      --load-extension=${probe} --enable-logging=stderr about:blank > /home/tester/brave.log 2>&1
  '';
  # Chrome with the probe, loaded through its DevTools pipe (fds 3 and 4,
  # Extensions.loadUnpacked), and the policies its chrome://policy page shows;
  # it keeps reading the pipe until Chrome exits. A profile of its own makes
  # it a new Chrome that can only find 1Password's host in the system
  # directory; its passwords stay out of this VM's keyring, which has none.
  launchChrome = pkgs.writeScript "cybexos-1password-chrome" ''
    #!${pkgs.python3.interpreter}
    import json
    import os
    import select
    import subprocess
    import time

    TO_CHROME, FROM_CHROME = os.pipe(), os.pipe()
    os.dup2(TO_CHROME[0], 100)
    os.dup2(FROM_CHROME[1], 101)
    # The page's text that shows, shadow roots included.
    VISIBLE = ('(function walk(n) { let t = ""; if (n.shadowRoot) t += walk(n.shadowRoot);'
               ' for (const c of n.childNodes) { if (c.nodeType === 3) {'
               ' if (c.parentElement && c.parentElement.checkVisibility()) t += c.textContent + " "; }'
               ' else t += walk(c); } return t; })(document.body)')


    def pipe():
        os.dup2(100, 3)
        os.dup2(101, 4)


    with open("/home/tester/chrome.log", "wb") as log:
        chrome = subprocess.Popen(["google-chrome-stable", "--no-first-run", "--remote-debugging-pipe",
                                   "--enable-unsafe-extension-debugging", "--enable-logging=stderr",
                                   "--user-data-dir=/home/tester/chrome-probe", "--password-store=basic",
                                   "about:blank"],
                                  stdout=log, stderr=log, close_fds=False, preexec_fn=pipe)
    for fd in (TO_CHROME[0], FROM_CHROME[1], 100, 101):
        os.close(fd)
    received = b""
    sent = 0


    def call(method, params=None, session=None):
        global received, sent
        sent += 1
        message = {"id": sent, "method": method, "params": params or {}}
        if session:
            message["sessionId"] = session
        with open("/home/tester/chrome-cdp.log", "a") as steps:
            steps.write("-> " + method + "\n")
        os.write(TO_CHROME[1], json.dumps(message).encode() + b"\0")
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            while b"\0" in received:
                raw, received = received.split(b"\0", 1)
                reply = json.loads(raw)
                if reply.get("id") == sent:
                    with open("/home/tester/chrome-cdp.log", "a") as steps:
                        steps.write(method + " " + json.dumps(reply)[:400] + "\n")
                    return reply
            if select.select([FROM_CHROME[0]], [], [], 1)[0]:
                received += os.read(FROM_CHROME[0], 1 << 20)
        raise SystemExit("Chrome did not answer " + method)


    loaded = call("Extensions.loadUnpacked", {"path": "${probe}"})
    target = call("Target.createTarget", {"url": "chrome://policy"})["result"]["targetId"]
    session = call("Target.attachToTarget", {"targetId": target, "flatten": True})["result"]["sessionId"]
    text = ""
    for _ in range(60):
        time.sleep(1)
        reply = call("Runtime.evaluate", {"expression": VISIBLE, "returnByValue": True}, session)
        text = " ".join((reply.get("result", {}).get("result", {}).get("value") or "").split())
        if "ExtensionSettings" in text:
            break
    with open("/home/tester/chrome-probe.json", "w") as out:
        json.dump({"loaded": loaded, "policy": text}, out)
    while chrome.poll() is None:
        if select.select([FROM_CHROME[0]], [], [], 1)[0] and not os.read(FROM_CHROME[0], 1 << 20):
            break
    chrome.wait()
  '';
  # A row in 1Password's own accounts table; its data is not a real account.
  addAccount = pkgs.writeText "cybexos-1password-account.py" ''
    import sqlite3
    db = sqlite3.connect("/home/tester/.config/1Password/1password.sqlite")
    db.execute("INSERT INTO accounts VALUES (?, ?)", ("cybexos-test", b"{}"))
    db.commit()
  '';
  # Claude Code's sign-in as the guide runs it: its page opens in the default
  # browser, and the person finishing it there is the check's approval.
  claude = pkgs.writeShellScript "cybexos-claude-sign-in" ''
    state=/home/tester/claude-sign-in
    case "$*" in
      "auth status") test -e "$state/signed-in" ;;
      "auth login")
        mkdir -p "$state"
        # Detached, as Claude Code starts it.
        setsid -f xdg-open "https://claude.ai/oauth/authorize?code=true" >/dev/null 2>&1
        until test -e "$state/approved"; do sleep 0.2; done
        touch "$state/signed-in"
        echo "Login successful." ;;
      *) exit 2 ;;
    esac
  '';
  ownWindow = pkgs.writeShellScript "cybexos-own-window" ''
    exec ${pkgs.kitty}/bin/kitty --class cxo-own ${pkgs.coreutils}/bin/sleep 1555
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-browser-1password";
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    cybexos = { enable = true; primaryUser = "tester"; features = { proprietary = true; steam = false; docker = false; }; };
    # Brave Origin as Software installs it.
    cybexos.software.packages = [ "brave-origin" ];
    systemd.user.services.cybexos-assistant.environment.CYBEXOS_ASSISTANT_CLAUDE = "${claude}";
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
    import shlex

    HOST = "com.1password.1password.json"
    CLAUDE_HOST = "com.anthropic.claude_code_browser_extension.json"
    WEB_STORE = "https://clients2.google.com/service/update2/crx"
    ONEPASSWORD = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    # Claude in Chrome and ChatGPT.
    AGENTS = ("fcoeoabgfenejglbffodgkkbkcdhcgfn", "hehggadaopoacecdllhhajmbjkdcmajg")
    POLICY_ROOTS = ("opt/chrome", "chromium", "brave")
    # What 1Password 8.12.42's windows are called, Wayland and XWayland alike.
    APP_ID = "1password"
    LOGS = "/home/tester/.config/1Password/logs"

    machine.start()
    machine.wait_for_unit("display-manager.service")
    uid = machine.succeed("id -u tester").strip()
    # The software-rendered shell can take more than the interactive 2 s
    # IPC limit to open the full-screen guide; allow it a minute here.
    session = (f"XDG_RUNTIME_DIR=/run/user/{uid} HOME=/home/tester DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
               " CYBEXOS_IPC_TIMEOUT=60")

    def user(command):
        return machine.succeed(f"runuser -u tester -- env {session} {command}")

    def welcome():
        return json.loads(user("cybexos-runtime ipc welcome status"))

    def clients():
        """Window classes by address; a window without one by its process's name."""
        return {c["address"].removeprefix("0x"): c["class"] or machine.execute(f"cat /proc/{c['pid']}/comm")[1].strip()
                for c in json.loads(user("hyprctl -i 0 -j clients"))}

    def layers():
        return {layer.get("namespace") for monitor in json.loads(user("hyprctl -i 0 -j layers")).values()
                for level in monitor.get("levels", {}).values() for layer in level}

    def kind(name):
        """Chrome's class is google-chrome on Wayland, Google-chrome on X11; Brave's is its launcher's."""
        name = name.lower()
        return "brave" if "brave" in name else "chrome" if "chrome" in name else name

    def kinds(addresses, windows):
        return sorted(kind(windows[a]) for a in addresses)

    def classes():
        windows = clients()
        return set(kinds(windows, windows))

    def run(script):
        user(f"hyprctl -i 0 dispatch 'hl.dsp.exec_cmd(\"{script}\")'")

    def host(path):
        entry = json.loads(machine.succeed(f"cat {path}"))
        return {**entry, "allowed_origins": sorted(entry["allowed_origins"])}

    def default_browser():
        defaults = user("XDG_CONFIG_DIRS=/etc/xdg XDG_DATA_DIRS=/run/current-system/sw/share cybexos-apps effective-defaults")
        return json.loads(defaults)["browser"]

    def verified():
        """The helper's verifications and desktop-app connections, across its logs (each helper starts a new one)."""
        return [int(machine.succeed(f"cat {LOGS}/BrowserSupport/* | grep -c '{text}' || true").strip())
                for text in ("verified successfully", "Connected to the desktop app")]

    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} cybexos-runtime ipc welcome status", timeout=300)

    # Chrome is the browser; Brave Origin is installed through Software's selection.
    assert default_browser() == "google-chrome.desktop", default_browser()
    machine.succeed("test -e /run/current-system/sw/share/applications/brave-browser.desktop")
    assert "brave-origin" in json.loads(machine.succeed("cat /etc/cybexos/software.json"))["selected"]

    # One policy file for Chrome, Chromium and Brave: 1Password is installed
    # for good, Claude in Chrome and ChatGPT arrive and can be turned off.
    policies = [json.loads(machine.succeed(f"cat /etc/{root}/policies/managed/cybexos.json")) for root in POLICY_ROOTS]
    assert policies[0] == policies[1] == policies[2], policies
    policy = policies[0]
    assert policy["ExtensionInstallForcelist"] == [f"{ONEPASSWORD};{WEB_STORE}"], policy
    assert policy["ExtensionSettings"] == {
        extension: {"installation_mode": "normal_installed", "update_url": WEB_STORE} for extension in AGENTS}, policy
    assert (policy["DefaultBrowserSettingEnabled"], policy["RestoreOnStartup"], policy["SpellcheckLanguage"]) == (False, 1, ["en"]), policy

    # The guide's Connect step opens 1Password from its desktop entry.
    assert user("cybexos-runtime ipc welcome open connect").strip() == "ok"
    assert user("cybexos-runtime ipc welcome connect password").strip() == "ok"
    machine.wait_until_succeeds(f"grep -q 'Starting IPC listener on 1Password-BrowserSupport' {LOGS}/1Password_rCURRENT.log", timeout=180)

    # 1Password's own entries, Chrome's and Origin's among them; the system ones are the same entry.
    ours = host(f"/etc/opt/chrome/native-messaging-hosts/{HOST}")
    assert ours == host(f"/etc/chromium/native-messaging-hosts/{HOST}"), ours
    for profile in ("google-chrome", "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Origin"):
        theirs = host(f"/home/tester/.config/{profile}/NativeMessagingHosts/{HOST}")
        assert ours == theirs, (profile, ours, theirs)
    machine.succeed("test -g /run/wrappers/bin/1Password-BrowserSupport")

    # Claude in Chrome reaches Claude Code through the same system entry in both directories.
    claude = host(f"/etc/opt/chrome/native-messaging-hosts/{CLAUDE_HOST}")
    assert claude == host(f"/etc/chromium/native-messaging-hosts/{CLAUDE_HOST}"), claude
    assert claude["allowed_origins"] == ["chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn/"], claude
    assert "--chrome-native-host" in machine.succeed(f"cat {claude['path']}"), claude

    # The probe takes the store extension's id, which the VM cannot fetch:
    # from here on the browsers get the policy without the forced install.
    probe_policy = json.dumps({key: value for key, value in policy.items() if key != "ExtensionInstallForcelist"})
    for root in POLICY_ROOTS:
        machine.succeed(f"rm /etc/{root}/policies/managed/cybexos.json"
                        f" && echo {shlex.quote(probe_policy)} > /etc/{root}/policies/managed/cybexos.json")

    # Brave Origin finds the host, 1Password accepts the browser, and the app answers.
    user("hyprctl -i 0 dispatch 'hl.dsp.exec_cmd(\"${launchBrave}\")'")
    machine.wait_until_succeeds("grep -aq CXO-PROBE /home/tester/brave.log", timeout=180)
    probe = machine.succeed("grep -a CXO-PROBE /home/tester/brave.log")
    assert "CXO-PROBE open" in probe, probe
    # The kernel shortens the helper's command name, so match its arguments.
    helper = machine.succeed("ps -eo egid=,args= | grep '[1]Password-BrowserSupport chrome-extension'")
    assert "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/" in helper, helper
    assert helper.split()[0] == machine.succeed("getent group onepassword | cut -d: -f3").strip(), helper
    support = machine.succeed(f"cat {LOGS}/BrowserSupport/1Password_rCURRENT.log")
    assert "brave-origin" in support and "verified successfully" in support, support
    assert "Connected to the desktop app" in support, support
    machine.succeed(f"grep -q 'Extension connecting' {LOGS}/1Password_rCURRENT.log")
    machine.screenshot("brave")
    # The policy leaves the default browser to Software and Settings.
    assert default_browser() == "google-chrome.desktop", default_browser()
    machine.succeed("pkill -u tester -x brave")
    machine.wait_until_fails("pgrep -u tester -x brave", timeout=60)

    # Chrome finds its system entry, and 1Password accepts Chrome's
    # executable; chrome://policy lists the policy.
    before = verified()
    run("${launchChrome}")
    try:
        machine.wait_until_succeeds("grep -aq CXO-PROBE /home/tester/chrome.log", timeout=180)
    except Exception:
        machine.screenshot("chrome-failed")
        machine.log(machine.execute("cat /home/tester/chrome-cdp.log; tail -n 80 /home/tester/chrome.log;"
                                    " ps -eo pid,args | grep -i [c]hrome | cut -c1-300 2>&1")[1])
        machine.log("windows: " + json.dumps(clients()))
        raise
    probe = machine.succeed("grep -a CXO-PROBE /home/tester/chrome.log")
    assert "CXO-PROBE open" in probe, probe
    loaded = json.loads(machine.succeed("cat /home/tester/chrome-probe.json"))
    assert loaded["loaded"]["result"]["id"] == ONEPASSWORD, loaded
    for name in ("DefaultBrowserSettingEnabled", "ExtensionSettings", "RestoreOnStartup", "SpellcheckLanguage"):
        assert name in loaded["policy"], (name, loaded["policy"])
    assert "Chrome Policies No policies set" not in loaded["policy"], loaded["policy"]
    helper = machine.succeed("ps -eo egid=,args= | grep '[1]Password-BrowserSupport chrome-extension'")
    assert f"chrome-extension://{ONEPASSWORD}/" in helper, helper
    after = verified()
    assert after[0] > before[0] and after[1] > before[1], (before, after)
    machine.log(machine.succeed(f"cat {LOGS}/BrowserSupport/* | grep -i 'verified successfully' | tail -n 2"))
    machine.screenshot("chrome")
    assert default_browser() == "google-chrome.desktop", default_browser()
    machine.succeed("pkill -u tester -x chrome")
    machine.wait_until_fails("pgrep -u tester -x chrome", timeout=60)

    # This 1Password's database, with no account yet: the card has no tick.
    assert welcome()["connect"]["password"] == "opened", welcome()
    machine.succeed("pkill -u tester -x 1password")
    machine.wait_until_fails("pgrep -u tester -x 1password", timeout=60)
    user("${pkgs.python3.interpreter} ${addAccount}")
    assert user("cybexos-runtime ipc welcome open connect").strip() == "ok"
    retry(lambda _: welcome()["connect"]["password"] == "ready", timeout_seconds=30)
    machine.screenshot("connect-signed-in")

    # 1Password again, left open: coming back to the guide closes the window it opened.
    assert user("cybexos-runtime ipc welcome connect password").strip() == "ok"
    retry(lambda _: APP_ID in classes(), timeout_seconds=120)
    reporter = welcome()["connectWindows"]
    machine.log("windows: " + json.dumps(clients()) + ", the guide's: " + json.dumps(reporter))
    assert reporter and all(clients().get(address) == APP_ID for address in reporter), (reporter, clients())
    machine.screenshot("connect-1password")
    assert user("cybexos-runtime ipc welcome open connect").strip() == "ok"
    # 1Password then goes on starting, and its dialog about the added row
    # steps the guide aside as any new window does.
    retry(lambda _: not set(reporter) & set(clients()) and APP_ID in classes(), timeout_seconds=30)
    assert user("cybexos-runtime ipc welcome open connect").strip() == "ok"
    retry(lambda _: not welcome()["aside"], timeout_seconds=15)
    # A window the person opens while the guide shows is theirs.
    run("${ownWindow}")
    retry(lambda _: "cxo-own" in classes(), timeout_seconds=60)
    assert user("cybexos-runtime ipc welcome open connect").strip() == "ok"
    retry(lambda _: not welcome()["aside"], timeout_seconds=15)

    # The sign-in runs in the background and opens Chrome, no terminal.
    retry(lambda _: user("cybexos-runtime ipc welcome connect claude").strip() == "ok", timeout_seconds=60)
    retry(lambda _: "chrome" in classes(), timeout_seconds=120)
    assert "kitty" not in classes(), clients()
    assert welcome()["aside"] and welcome()["connect"]["assistant"] == "signing-in", welcome()
    machine.screenshot("sign-in")
    user("touch /home/tester/claude-sign-in/approved")
    retry(lambda _: not welcome()["aside"] and welcome()["connect"]["assistant"] == "ready", timeout_seconds=60)
    opened = welcome()["connectWindows"]
    windows = clients()
    machine.log("windows: " + json.dumps(windows) + ", the guide's: " + json.dumps(opened))
    # The real 1Password may show a window too. The keyring prompt Chrome
    # raises is this VM's: its sign-in leaves the keyring locked.
    assert {"chrome"} <= set(kinds(opened, windows)) <= {APP_ID, "chrome", "gcr-prompter"}, (opened, windows)

    # Leaving closes them before the desktop shows; the person's own stays.
    user("cybexos-runtime ipc welcome close")
    retry(lambda _: not layers() & {"qs-welcome", "qs-welcome-resume"}, timeout_seconds=30)
    windows = clients()
    assert not set(opened) & set(windows), (opened, windows)
    assert "cxo-own" in windows.values(), windows
    machine.screenshot("desktop")
  '';
}
