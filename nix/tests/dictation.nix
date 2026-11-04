# Dictation end to end on a booted Cybex OS desktop (docs/dictation.md): F9
# through Hyprland's binding and the shell's global shortcut, the real Voxtype
# daemon recording PipeWire's default source, the live words in the dictation
# pill while speech plays, and the finished words typed into the focused
# window with wtype, which keeps its focus throughout.
#
# Then the first-use offer, live text off (the words arrive at the end), a
# second language, and the enhanced model as a finished download leaves it
# (there is no network; tests/nixos/test_dictation_helper.py covers the
# download): English and Dutch, told apart by Whisper, with live text off.
# Every typed dictation lands in the history, which opens from its shortcut;
# a correction rewrites a word, Polish without an agent falls back to basic
# tidy-up, and a kept recording sits beside its entry. Last, Parakeet (Fast &
# accurate), streaming through the sliding window with live words, in English
# and Dutch without being told which.
#
# The microphone is a PipeWire null sink's monitor fed with espeak-ng speech,
# and recognition runs on the VM's CPU (AVX2; a pass takes seconds): this
# qualifies the session's dictation flow, not a physical microphone, a GPU, or
# recognition quality on real voices.
{ pkgs, module }:
let
  python = pkgs.python3.interpreter;
  speech = pkgs.runCommand "cybexos-dictation-speech" { nativeBuildInputs = [ pkgs.espeak-ng ]; } ''
    mkdir $out
    espeak-ng -v en-us -s 140 -w $out/english.wav "Good morning. This is a dictation test on Cybex. The weather is nice today."
    espeak-ng -v nl -s 130 -w $out/dutch.wav "Goedemorgen. Dit is een test van het dicteren. Het weer is mooi vandaag."
  '';
  # The enhanced model as the download leaves it (same pinned file and hash).
  enhanced = pkgs.fetchurl {
    name = "ggml-large-v3-turbo-q8_0.bin";
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin";
    sha256 = "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1";
  };
  # Parakeet v3 as the download leaves it: its files in one directory.
  parakeetFile = name: sha256: pkgs.fetchurl {
    inherit name sha256;
    url = "https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce/${name}";
  };
  parakeet = pkgs.linkFarm "parakeet-tdt-0.6b-v3-int8" [
    { name = "encoder-model.int8.onnx"; path = parakeetFile "encoder-model.int8.onnx" "6139d2fa7e1b086097b277c7149725edbab89cc7c7ae64b23c741be4055aff09"; }
    { name = "decoder_joint-model.int8.onnx"; path = parakeetFile "decoder_joint-model.int8.onnx" "eea7483ee3d1a30375daedc8ed83e3960c91b098812127a0d99d1c8977667a70"; }
    { name = "vocab.txt"; path = parakeetFile "vocab.txt" "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d"; }
    { name = "config.json"; path = parakeetFile "config.json" "666903c76b9798caf2c210afd4f6cd60b08a8dbf9800ec8d7a3bc0d2148ac466"; }
  ];
  # A terminal program that records every byte it receives: what wtype typed.
  probe = pkgs.writeText "cybexos-dictation-probe.py" ''
    import os, sys, tty
    log = open(sys.argv[1], "ab", buffering=0)
    tty.setraw(0)
    open(sys.argv[1] + ".ready", "w").close()
    while True:
        data = os.read(0, 1024)
        if not data:
            break
        log.write(data)
  '';
  launchProbe = pkgs.writeShellScript "cybexos-dictation-probe-launch" ''
    exec hyprctl -i 0 dispatch 'hl.dsp.exec_cmd("${pkgs.kitty}/bin/kitty --class cxo-typed ${python} ${probe} /home/tester/typed.txt")'
  '';
in pkgs.testers.runNixOSTest {
  name = "cybexos-dictation";
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
    import json
    import re
    import time

    QML_ERRORS = re.compile(r"TypeError|ReferenceError|Binding loop|is not a type|Type \w+ unavailable"
                            r"|Cannot assign|Unable to assign|Illegal method name|Failed to load configuration")

    machine.start()
    machine.wait_for_unit("display-manager.service")
    uid = machine.succeed("id -u tester").strip()
    session = f"XDG_RUNTIME_DIR=/run/user/{uid} HOME=/home/tester DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"

    def user(command):
        return machine.succeed(f"runuser -u tester -- env {session} {command}")

    def dictation():
        return json.loads(user("cybexos-runtime ipc dictation status"))

    def ipc(call):
        user(f"cybexos-runtime ipc dictation {call}")

    def wait(predicate, timeout=30, what="condition"):
        deadline = time.monotonic() + timeout
        while True:
            value = predicate()
            if value:
                return value
            if time.monotonic() >= deadline:
                raise AssertionError(f"timed out waiting for {what}: {dictation()}")
            time.sleep(0.25)

    def typed():
        return machine.succeed("cat /home/tester/typed.txt 2>/dev/null || true")

    def config():
        return machine.succeed("cat /home/tester/.config/voxtype/config.toml")

    def voxtype_pid():
        return user("systemctl --user show voxtype.service -p MainPID --value").strip()

    def wait_ready(previous_pid=None):
        # A restarted daemon has loaded its model when its state file says idle.
        machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active voxtype.service", timeout=120)
        if previous_pid is not None:
            wait(lambda: voxtype_pid() not in ("0", previous_pid), 60, "a restarted daemon")
        machine.wait_until_succeeds(f"grep -qx idle /run/user/{uid}/voxtype/state", timeout=240)

    def dictate(wav, label, expect_live=True):
        before = typed()
        machine.send_key("f9")
        wait(lambda: dictation()["phase"] == "listening", 30, f"{label}: listening")
        time.sleep(0.5)
        user(f"pw-play --target cxmic {wav}")
        if expect_live:
            live = wait(lambda: dictation()["liveText"], 60, f"{label}: live words")
            machine.screenshot(f"{label}-live")
        time.sleep(1)
        machine.send_key("f9")
        wait(lambda: dictation()["phase"] not in ("finishing", "tidying", "typing"), 180, f"{label}: finished")
        status = dictation()
        assert status["phase"] in ("", "done") and status["failure"] == "", f"{label}: {status}"
        result = typed()[len(before):]
        print(f"{label}: typed {result!r}" + (f", live {live!r}" if expect_live else ""))
        active = json.loads(user("hyprctl -i 0 -j activewindow"))
        assert active.get("class") == "cxo-typed", f"the dictated window kept its focus: {active}"
        return result.lower()

    # ---- the session ---------------------------------------------------------------
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} systemctl --user is-active quickshell.service", timeout=600)
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} cybexos-runtime ipc dictation status | grep -q available", timeout=300)
    cursor = machine.succeed("journalctl -n 0 --show-cursor -q").strip().split("cursor: ", 1)[-1]
    status = dictation()
    assert status["available"] and status["model"] == "base" and status["languages"] == "en", status
    assert status["liveTextEnabled"] and not status["enhancedInstalled"], status

    # A fresh account's Voxtype streams with the built-in model, kept loaded.
    seeded = config()
    for line in ('model = "base"', 'language = "en"', "streaming = true", "on_demand_loading = false",
                 "revision_mode = true", 'backend = "energy"'):
        assert line in seeded, f"{line} in the seeded config.toml"
    wait_ready()

    # The microphone: a null sink whose monitor is the default source.
    user("pactl load-module module-null-sink sink_name=cxmic sink_properties=device.description=cxmic")
    user("pactl set-default-source cxmic.monitor")

    machine.succeed(f"runuser -u tester -- env {session} ${launchProbe}")
    machine.wait_for_file("/home/tester/typed.txt.ready", timeout=60)
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} hyprctl -i 0 -j activewindow | grep -q cxo-typed", timeout=30)

    # ---- dictation with the built-in model --------------------------------------------
    english = dictate("${speech}/english.wav", "base-english")
    assert "morning" in english and "test" in english, english

    # It is in the history, as typed, with the app it went to.
    def history():
        return json.loads(machine.succeed("cat /home/tester/.local/state/cybexos/dictation/history.json"))["entries"]
    entry = history()[0]
    assert entry["status"] == "typed" and entry["text"].lower() in english, entry
    assert machine.succeed("stat -c %a /home/tester/.local/state/cybexos/dictation/history.json").strip() == "600"

    # The first dictation that typed words offers the model that suits its
    # languages (Parakeet for English), once.
    wait(lambda: dictation()["offerShown"], 15, "the offer")
    assert dictation()["recommendedModel"] == "parakeet", dictation()
    machine.screenshot("offer")
    machine.succeed("grep -q '\"dictationPrompted\": *true' /home/tester/.config/cybexos/shell.json")
    layers = json.loads(user("hyprctl -i 0 -j layers"))
    names = {layer.get("namespace") for monitor in layers.values()
             for level in monitor.get("levels", {}).values() for layer in level}
    assert "qs-dictation-offer" in names, names

    ipc("dismissOffer")

    # The history opens from its shortcut, takes the keyboard, and closes on Escape.
    machine.send_key("meta_l-ctrl-shift-x")
    wait(lambda: dictation()["historyOpen"] and dictation()["historyCount"] >= 1, 15, "the history")
    time.sleep(1)
    machine.screenshot("history")
    layers = json.loads(user("hyprctl -i 0 -j layers"))
    names = {layer.get("namespace") for monitor in layers.values()
             for level in monitor.get("levels", {}).values() for layer in level}
    assert "qs-dictation-history" in names, names
    machine.send_key("esc")
    wait(lambda: not dictation()["historyOpen"], 15, "the history closed")
    machine.wait_until_succeeds(f"runuser -u tester -- env {session} hyprctl -i 0 -j activewindow | grep -q cxo-typed", timeout=30)

    # A correction rewrites a word, live and typed; a kept recording sits
    # beside its entry; Polish without an agent types basic tidy-up.
    ipc("addCorrection test trial")
    ipc("keepRecordings true")
    ipc("tidy polish")
    wait(lambda: "trial" in machine.succeed("cat /home/tester/.config/cybexos/shell.json"), 15, "the correction saved")
    corrected = dictate("${speech}/english.wav", "corrected-english")
    assert "trial" in corrected and not re.search(r"\btest\b", corrected), corrected
    result = dictation()["lastResult"]
    assert result["polishFailed"] and result["tidy"] == "basic", result
    entry = history()[0]
    assert entry["audio"] is True, entry
    machine.succeed(f"test -s /home/tester/.local/state/cybexos/dictation/recordings/{entry['id']}.wav")
    machine.succeed(f"test ! -e /run/user/{uid}/cybexos-dictation/transcript.txt.wav")
    ipc("tidy basic")
    ipc("keepRecordings false")
    ipc("removeCorrection test")

    # Live text off: the model loads on demand and the words come at the end.
    pid = voxtype_pid()
    ipc("liveText false")
    wait(lambda: "streaming = false" in config() and "on_demand_loading = true" in config(), 30, "live text off")
    wait_ready(pid)
    english = dictate("${speech}/english.wav", "batch-english", expect_live=False)
    assert "morning" in english and "test" in english, english
    pid = voxtype_pid()
    ipc("liveText true")
    wait(lambda: "streaming = true" in config() and "on_demand_loading = false" in config(), 30, "live text on")
    wait_ready(pid)

    # A second language from the offer: Voxtype detects between the two.
    pid = voxtype_pid()
    ipc("language nl")
    wait(lambda: 'language = "en,nl"' in config(), 30, "the language list in config.toml")
    wait_ready(pid)

    # The enhanced model, as a finished download leaves it, chosen and loaded.
    user("mkdir -p /home/tester/.local/share/voxtype/models")
    user("ln -sf ${enhanced} /home/tester/.local/share/voxtype/models/ggml-large-v3-turbo-q8_0.bin")
    ipc("refreshModel")
    wait(lambda: dictation()["enhancedInstalled"], 15, "the enhanced model")
    pid = voxtype_pid()
    ipc("model large-v3-turbo")
    wait(lambda: 'model = "ggml-large-v3-turbo-q8_0.bin"' in config(), 30, "the enhanced model in config.toml")
    ipc("dismissOffer")
    wait_ready(pid)
    wait(lambda: dictation()["applied"].get("model") == "enhanced", 30, "the enhanced model applied")
    # The page with dictation's choices opens; the journal check below covers
    # the group (it sits below the fold of a 1280×800 screen).
    ipc("settings")
    time.sleep(4)
    machine.screenshot("settings")
    user("cybexos-runtime ipc settings close")
    machine.succeed("journalctl _SYSTEMD_USER_UNIT=voxtype.service -b --no-pager | grep -Eq 'n_audio_layer += 32'")

    # English and Dutch with it, one key: Whisper picks between the two. Live
    # text off, so each sentence is one pass of the large model on this CPU.
    pid = voxtype_pid()
    ipc("liveText false")
    wait(lambda: "streaming = false" in config(), 30, "live text off")
    wait_ready(pid)
    english = dictate("${speech}/english.wav", "enhanced-english", expect_live=False)
    assert "morning" in english and "weather" in english, english
    dutch = dictate("${speech}/dutch.wav", "enhanced-dutch", expect_live=False)
    assert "goedemorgen" in dutch and "vandaag" in dutch, dutch
    ipc("liveText true")

    # Parakeet, as a finished download leaves it, chosen: Voxtype gets its
    # section, then the engine, and streams it through the sliding window.
    user("ln -sfn ${parakeet} /home/tester/.local/share/voxtype/models/parakeet-tdt-0.6b-v3-int8")
    ipc("refreshModel")
    wait(lambda: dictation()["parakeetInstalled"], 15, "the Parakeet model")
    pid = voxtype_pid()
    ipc("model parakeet")
    wait(lambda: 'engine = "parakeet"' in config() and 'model = "parakeet-tdt-0.6b-v3-int8"' in config(), 30, "Parakeet in config.toml")
    wait_ready(pid)
    wait(lambda: dictation()["applied"].get("model") == "parakeet", 30, "Parakeet applied")
    english = dictate("${speech}/english.wav", "parakeet-english")
    assert "morning" in english and "weather" in english, english
    # Dutch, which it recognises by itself. Its last words vary on this
    # synthetic voice through PipeWire ("van haar" for "vandaag").
    dutch = dictate("${speech}/dutch.wav", "parakeet-dutch")
    assert "goedemorgen" in dutch and "mooi" in dutch, dutch

    # Back to the built-in model.
    pid = voxtype_pid()
    ipc("model base")
    wait(lambda: 'model = "base"' in config() and 'engine = "whisper"' in config(), 30, "the built-in model again")
    wait_ready(pid)

    # Nothing in the shell's journal went wrong.
    journal = machine.succeed(f"journalctl _SYSTEMD_USER_UNIT=quickshell.service -b --no-pager --after-cursor='{cursor}'")
    errors = [line for line in journal.splitlines() if QML_ERRORS.search(line)]
    assert not errors, "\n".join(errors)
    print(machine.succeed("journalctl _SYSTEMD_USER_UNIT=voxtype.service -b --no-pager | tail -n 80"))
  '';
}
