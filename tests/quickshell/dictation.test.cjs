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

test("the shell's dictations record to a file and type the finished words once", () => {
    // Settings gives Voxtype the model and languages: a per-recording --model
    // would run a separate, non-streaming transcriber, and --language never
    // reached the daemon at all.
    for (const [label, source] of [["Dictation", dictation], ["Assistant", read("Common/Assistant.qml")]]) {
        assert.match(source, /exec voxtype record start --file="\$2"/, label);
        assert.doesNotMatch(source, /voxtype --(?:model|language)|record start[^\n]*--(?:model|language)/, label);
        assert.match(source, /rm -f -- "\$2" "\$2\.done" "\$2\.live"/,
            `${label} clears the last session's transcript, outcome and live words`);
    }
    assert.match(dictation, /path: root\.sessionActive \? root\.transcriptPath \+ "\.live" : ""/);
    assert.match(dictation, /path: root\.transcriptPath \+ "\.done"/);
    assert.match(dictation, /command: \["python3", root\.script, "type", root\.transcriptPath\]/);
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
    const typed = dictation.slice(dictation.indexOf("id: typeProc"), dictation.indexOf("id: statusProc"));
    assert.match(typed, /if \(!root\.options\.dictationPrompted && root\.statusKnown\s*&& root\.options\.dictationModel === "base" && !root\.enhancedInstalled\)\s*root\.showOffer\(\);/);
    assert.match(dictation, /Settings\.setModuleOption\("indicators", "dictationPrompted", true\)/);
    // A download that finished is chosen; removing it chooses the built-in model first.
    assert.match(dictation, /if \(result === "done"\) \{[\s\S]*?"dictationModel", "large-v3-turbo"\)/);
    assert.match(dictation, /function removeEnhanced\(\) \{\s*Settings\.setModuleOption\("indicators", "dictationModel", "base"\);\s*removeProc\.running = true;/);
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
    // whisper.cpp's vector instructions, off in every Nix build unless asked
    // for, and a unit that does not start on a processor without them.
    for (const flag of ["GGML_SSE42", "GGML_AVX", "GGML_AVX2", "GGML_FMA", "GGML_F16C", "GGML_BMI2"])
        assert.match(options, new RegExp(`${flag} = "ON"`), flag);
    assert.match(desktop, /unitConfig\.ConditionCPUFeature = \[ "sse4_2" "avx" "avx2" "f16c" "bmi2" \]/);
    const helper = fs.readFileSync(path.join(shellDir, "scripts/dictation.py"), "utf8");
    assert.match(helper, /CPU_FEATURES = \("sse4_2", "avx", "avx2", "fma", "f16c", "bmi2"\)/);
    assert.match(dictation, /readonly property bool available: Settings\.developerToolsConfigured && cpuSupported/);
});
