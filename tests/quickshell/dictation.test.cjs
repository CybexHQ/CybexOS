const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, untranslated } = require("./shell.cjs");

const repo = path.resolve(shellDir, "../..");

function read(relative) {
    return untranslated(fs.readFileSync(path.join(shellDir, relative), "utf8"));
}

const dictation = read("Common/Dictation.qml");
const pill = read("DictationPill.qml");
const offer = read("DictationOffer.qml");
const history = read("DictationHistory.qml");
const page = read("Settings/DictationPage.qml");

test("the shell's dictations record to a file and type the finished words once", () => {
    // Settings gives Voxtype the model and languages: a per-recording --model
    // would run a separate, non-streaming transcriber, and --language never
    // reached the daemon at all.
    for (const [label, source] of [["Dictation", dictation], ["Assistant", read("Common/Assistant.qml")]]) {
        assert.match(source, /exec voxtype record start --file="\$2"/, label);
        assert.doesNotMatch(source, /voxtype --(?:model|language)|record start[^\n]*--(?:model|language)/, label);
        assert.match(source, /rm -f -- "\$2" "\$2\.done" "\$2\.live" "\$2\.wav"/,
            `${label} clears the last session's transcript, outcome, live words and recording`);
    }
    assert.match(dictation, /path: root\.sessionActive \? root\.transcriptPath \+ "\.live" : ""/);
    assert.match(dictation, /path: root\.transcriptPath \+ "\.done"/);
    // Corrections, tidy-up, typing and history happen in one helper run.
    assert.match(dictation, /deliverProc\.command = \["python3", root\.script, "deliver", root\.transcriptPath,\s*"--options", JSON\.stringify\(deliveryOptions\(\)\)\];/);
    for (const key of ["dictationCorrections", "dictationTidy", "dictationPolishAgent",
        "dictationTidyCode", "dictationHistory", "dictationKeepAudio"])
        assert.match(dictation.slice(dictation.indexOf("function deliveryOptions()")), new RegExp(`options\\.${key}`), key);
    // The live words show the corrections they will be typed with.
    assert.match(dictation, /readonly property string shownText: SettingsHelpers\.applyDictationCorrections\(liveText,/);
    assert.match(pill, /readonly property string words: tail\(Dictation\.shownText\)/);
    // "streaming" is a recording: the menubar must not read it as idle.
    assert.match(dictation, /readonly property bool recording: state === "recording" \|\| state === "streaming"/);
    assert.match(dictation, /\["idle", "recording", "streaming", "transcribing"\]\.indexOf\(value\)/);
    // A change handler may run before dependent bindings re-evaluate.
    const handler = dictation.slice(dictation.indexOf("onStateChanged: {"), dictation.indexOf("FileView {"));
    assert.match(handler, /if \(state === "recording" \|\| state === "streaming"\) \{/);
    assert.doesNotMatch(handler, /\bif \((?:recording|busy|transcribing)\b/);
});

test("the daemon is reconfigured only between dictations", () => {
    assert.match(dictation,
        /if \(!Settings\.loaded \|\| root\.busy \|\| root\.sessionActive \|\| applyProc\.running\) \{\s*restart\(\);/);
    assert.match(dictation, /"--live", root\.options\.dictationLiveText \? "1" : "0"/);
});

test("the offer comes once, after typed words, and only while it can help", () => {
    const typed = dictation.slice(dictation.indexOf("id: deliverProc"), dictation.indexOf("id: historyProc"));
    assert.match(typed, /if \(!root\.options\.dictationPrompted && root\.statusKnown\s*&& root\.options\.dictationModel === "base" && !root\.recommendedInstalled\)\s*root\.showOffer\(\);/);
    assert.match(dictation, /Settings\.setModuleOption\("indicators", "dictationPrompted", true\)/);
    // The offer recommends Parakeet where it knows both languages, Whisper turbo elsewhere.
    assert.match(dictation, /readonly property string recommendedModel: parakeetFits \? "parakeet" : "large-v3-turbo"/);
    assert.match(offer, /Dictation\.downloadRecommended\(\)/);
    // A download that finished is chosen; removing it chooses the built-in model first.
    assert.match(dictation, /if \(result === "done"\) \{[\s\S]*?root\.downloadModel === "parakeet" \? "parakeet" : "large-v3-turbo"\)/);
    assert.match(dictation, /function removeModel\(name\) \{[\s\S]*?if \(options\.dictationModel === setting\)\s*Settings\.setModuleOption\("indicators", "dictationModel", "base"\);\s*removeProc\.command/);
    // A chosen model that the languages no longer fit is not given to Voxtype.
    assert.match(dictation, /if \(chosen === "parakeet" && parakeetInstalled && parakeetFits\)\s*return "parakeet";/);
    assert.match(dictation, /readonly property string applyKey: JSON\.stringify\(\[effectiveModel, languages,/);
});

test("tidy-up can be skipped for the words as said, and the original is a click away", () => {
    assert.match(dictation, /function typeOriginal\(\) \{[\s\S]*?Quickshell\.execDetached\(\["touch", transcriptPath \+ "\.original"\]\);/);
    assert.match(dictation, /function copyOriginal\(\) \{[\s\S]*?Quickshell\.execDetached\(\["wl-copy", "--", text\]\);/);
    assert.match(pill, /enabled: root\.listening \|\| \(root\.tidying && !Dictation\.originalRequested\)/);
    assert.match(pill, /if \(root\.phase === "done"\)\s*Dictation\.copyOriginal\(\);\s*else\s*Dictation\.openHistory\(\);/);
    // The pill shows a finished dictation only when there is something to say.
    assert.match(pill, /readonly property bool doneNote: phase === "done" && \(result\.tidied === true \|\| result\.polishFailed === true\)/);
});

test("the history opens from the menubar, a shortcut and Settings, and gives the keyboard back", () => {
    // Keyboard first, then the dismissal grab, as the launcher does on Hyprland 0.56.
    assert.match(history, /WlrLayershell\.keyboardFocus: !shown \? WlrKeyboardFocus\.None\s*: dismissalGrab\.active \? WlrKeyboardFocus\.OnDemand : WlrKeyboardFocus\.Exclusive/);
    assert.match(history, /HyprlandFocusGrab \{\s*id: dismissalGrab\s*active: root\.shown && root\.dismissalGrabReady\s*windows: \[root\]\s*onCleared: Dictation\.closeHistory\(\)/);
    // Typing an entry again closes the history first, so the words go below.
    assert.match(dictation, /function typeEntry\(id\) \{\s*closeHistory\(\);\s*historyCommand\(\["type", id\]\);/);
    const indicators = read("Bar/Modules/Indicators.qml");
    assert.match(indicators, /case "dictation":\s*if \(mouseButton === Qt\.MiddleButton\)\s*Dictation\.toggleHistory\(\);/);
    const shell = read("shell.qml");
    assert.match(shell, /name: "dictationHistory"[\s\S]{0,120}onPressed: Dictation\.toggleHistory\(\)/);
    assert.match(shell, /DictationPill \{\}\s*DictationOffer \{\}\s*DictationHistory \{\}/);
    const bindings = fs.readFileSync(path.join(repo, "desktop/hypr/bindings.lua"), "utf8");
    assert.match(bindings, /bind\(mainMod \.\. " \+ CTRL \+ SHIFT \+ X", hl\.dsp\.global\("quickshell:dictationHistory"\),/);
    // History commands run one at a time, with the retention Settings chose.
    assert.match(dictation, /\.concat\(\["--retention", options\.dictationHistory\]\)/);
    assert.match(page, /Settings\.closePanel\(\);\s*Dictation\.openHistory\(\);/);
});

test("neither surface takes the keyboard from the window being dictated into", () => {
    assert.match(pill, /WlrLayershell\.keyboardFocus: WlrKeyboardFocus\.None/);
    assert.match(pill, /WlrLayershell\.layer: WlrLayer\.Overlay/);
    assert.match(pill, /mask: Region \{\s*item: pill\s*\}/);
    assert.match(offer, /WlrLayershell\.keyboardFocus: shown \? WlrKeyboardFocus\.OnDemand : WlrKeyboardFocus\.None/);
    assert.doesNotMatch(offer, /WlrKeyboardFocus\.Exclusive/);
});

test("F9, Super+Ctrl+X and the microphone key toggle dictation in the shell", () => {
    const bindings = fs.readFileSync(path.join(repo, "desktop/hypr/bindings.lua"), "utf8");
    const toggles = bindings.match(/bind\("[^"]*"[^\n]*quickshell:dictationToggle[^\n]*\n[^\n]*/g)
        .concat(bindings.match(/bind\(mainMod[^\n]*quickshell:dictationToggle[^\n]*\n[^\n]*/g));
    assert.equal(toggles.length, 3, toggles.join("\n"));
    for (const binding of toggles) {
        assert.match(binding, /"dictation\.toggle"\)/);
        assert.doesNotMatch(binding, /locked = true/, "never typed into the lock screen");
    }
    assert.doesNotMatch(bindings, /voxtype/);
    const shell = read("shell.qml");
    assert.match(shell, /name: "dictationToggle"[\s\S]{0,120}onPressed: Dictation\.toggle\(\)/);
    assert.match(shell, /DictationPill \{\}\s*DictationOffer \{\}/);
});

test("Settings → Assistant has a Dictation tab, which the old links open", () => {
    const settings = read("Common/Settings.qml");
    assert.match(settings, /\{ id: "dictation", label: "Dictation"/);
    assert.match(settings, /dictation: "assistant"\n/);
    assert.match(read("Settings/SettingsView.qml"), /case "assistant": return tab === "dictation" \? dictationPage : assistantPage;/);
    assert.match(read("shell.qml"), /function settings\(\): void \{ Dictation\.openSettings\(\); \}/);
    assert.match(dictation, /Settings\.showPanel\("dictation", /);
});

test("the seeded Voxtype configuration streams, detects silence and keeps the model loaded", () => {
    const toml = fs.readFileSync(path.join(repo, "desktop/defaults/voxtype.toml"), "utf8");
    for (const line of ['model = "base"', 'language = "en"', "streaming = true",
        "on_demand_loading = false", "revision_mode = true", "enabled = true", 'backend = "energy"'])
        assert.ok(toml.includes(`\n${line}\n`), line);
    const desktop = fs.readFileSync(path.join(repo, "nix/modules/desktop.nix"), "utf8");
    assert.match(desktop, /ExecStart = "\$\{cfg\.dictationPackage\}\/bin\/voxtype daemon"/,
        "a command-line --on-demand-loading would override live text");
    const options = fs.readFileSync(path.join(repo, "nix/modules/default.nix"), "utf8");
    assert.match(options, /patches = \(old\.patches or \[ \]\) \+\+ \[ \.\.\/packages\/voxtype-dictation\.patch \]/);
    // ONNX Runtime from Nixpkgs runs Parakeet, which the patch streams.
    assert.match(options, /pkgs\.voxtype\.override \{ vulkanSupport = true; onnxSupport = true; \}/);
    // Nixpkgs' Rust builds link onig_sys and libsqlite3-sys to system
    // libraries; this build (unlike NixOS's cached one) compiles both.
    assert.match(options, /buildInputs = \(old\.buildInputs or \[ \]\) \+\+ \[ pkgs\.oniguruma pkgs\.sqlite \]/);
    const patch = fs.readFileSync(path.join(repo, "nix/packages/voxtype-dictation.patch"), "utf8");
    assert.match(patch, /\+fn parakeet_streams_by_window\(model: &str\) -> bool \{/);
    assert.match(patch, /\+fn write_recording\(transcript: &std::path::Path, samples: &\[f32\], sample_rate: u32\) \{/);
    // whisper.cpp's vector instructions, off in every Nix build unless asked
    // for, and a unit that does not start on a processor without them.
    for (const flag of ["GGML_SSE42", "GGML_AVX", "GGML_AVX2", "GGML_FMA", "GGML_F16C", "GGML_BMI2"])
        assert.match(options, new RegExp(`${flag} = "ON"`), flag);
    assert.match(desktop, /unitConfig\.ConditionCPUFeature = \[ "sse4_2" "avx" "avx2" "f16c" "bmi2" \]/);
    const helper = fs.readFileSync(path.join(shellDir, "scripts/dictation.py"), "utf8");
    assert.match(helper, /CPU_FEATURES = \("sse4_2", "avx", "avx2", "fma", "f16c", "bmi2"\)/);
    assert.match(dictation, /readonly property bool available: Settings\.developerToolsConfigured && cpuSupported/);
});
