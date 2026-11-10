// Wiz's newer shell rules (docs/assistant.md): replies with code blocks, what
// changed and how it reads, the suggestion that fits the moment, snapping and
// tucking, the wide view, notifications, attachments, and the wiring that
// connects them to the service, the settings and the compositor.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const A = load("AssistantHelpers.js");
const root = path.resolve(shellDir, "../..");
const read = relative => fs.readFileSync(path.join(shellDir, relative), "utf8");
const repo = relative => fs.readFileSync(path.join(root, relative), "utf8");

test("a reply splits into prose and code blocks, each code block copyable on its own", () => {
    assert.deepEqual(A.markdownBlocks("Run this:\n```fish\ncybex update stage local\n```\nThen review."), [
        { kind: "text", text: "Run this:" },
        { kind: "code", lang: "fish", text: "cybex update stage local" },
        { kind: "text", text: "Then review." }
    ]);
    assert.deepEqual(A.markdownBlocks("````\na```b\n````"), [{ kind: "code", lang: "", text: "a```b" }],
        "a longer fence holds a shorter one");
    assert.deepEqual(A.markdownBlocks("Streaming\n```\npartial"), [
        { kind: "text", text: "Streaming" }, { kind: "code", lang: "", text: "partial" }]);
    assert.deepEqual(A.markdownBlocks(""), []);
    const markdown = read("Assistant/AssistantMarkdown.qml");
    assert.match(markdown, /Quickshell\.clipboardText = block\.modelData\.text;/);
    assert.match(markdown, /if \(\/\^\(https\?\|mailto\):\/i\.test\(link\)\)/, "only web and mail links open");
});

test("the steps fold after a short answer and stay open after a long one", () => {
    assert.equal(A.stepsFolded("Done.", [{ label: "Read a file" }]), true);
    assert.equal(A.stepsFolded("x".repeat(A.FOLD_STEPS_BELOW), [{ label: "Read a file" }]), false);
    assert.equal(A.stepsFolded("Done.", []), false);
});

test("a change reads as what it is, with its old and new value", () => {
    const rows = [{ key: "barOpacity", label: "Menubar opacity" }];
    const setting = A.changeRow({ id: "ch-1", kind: "setting", key: "barOpacity", before: 1, after: 0.8,
        hadBefore: true, hasAfter: true, status: "applied", undoable: true }, rows);
    assert.deepEqual([setting.label, setting.before, setting.after, setting.undoable, setting.action],
        ["Menubar opacity", "1", "80%", true, "undo"]);
    const unknown = A.changeRow({ kind: "setting", key: "clock24", hadBefore: false, hasAfter: true, after: true }, []);
    assert.deepEqual([unknown.label, unknown.before, unknown.after], ["Clock24", "default", "On"]);
    assert.equal(A.changeRow({ kind: "plugin", name: "CPU", op: "created" }, []).action, "remove");
    assert.equal(A.changeRow({ kind: "app", app: { id: "com.spotify.Client", name: "Spotify" }, op: "installed" }, []).label,
        "Spotify");
    assert.equal(A.changeRow({ kind: "system", transaction: "abc" }, []).action, "review");
    assert.equal(A.humanizeKey("assistantWindowContext"), "Assistant window context");
    assert.equal(A.formatValue("a".repeat(40)).length, 28);
});

test("a setting change is named as Settings names it, with its resolved values", () => {
    const rows = [{ key: "glassEnabled", label: "Glass effect", pageLabel: "Appearance", group: "Theme" }];
    const glass = A.changeRow({ kind: "setting", key: "glassEnabled", hadBefore: false, hasAfter: true, after: true,
        undoable: true }, rows, { glassEnabled: false });
    assert.deepEqual([glass.label, glass.place, glass.before, glass.after], ["Glass effect", "Appearance · Theme", "Off", "On"],
        "a default the file did not hold reads as the value it stood at");
    const undone = A.changeRow({ kind: "setting", key: "glassEnabled", hadBefore: true, before: true, hasAfter: false },
        rows, { glassEnabled: false });
    assert.deepEqual([undone.before, undone.after], ["On", "Off"], "a value taken back to its default");
    const unknown = A.changeRow({ kind: "setting", key: "mystery", hadBefore: false, after: 2 }, rows, { glassEnabled: false });
    assert.deepEqual([unknown.place, unknown.before], ["", "default"], "an unknown default still says so");
    const changes = read("Assistant/AssistantChanges.qml");
    assert.match(changes, /AssistantHelpers\.changeRow\(change, SettingsSearchData\.ROWS,\s*Settings\.defaults\)/);
    assert.match(changes, /case "On": return I18n\.tr\("On"\);/, "values read in the person's language");
});

test("the reply's copy and terminal actions say what they do", () => {
    const reply = read("Assistant/AssistantReply.qml");
    assert.match(reply, /objectName: "assistantCopyReply"[\s\S]{0,160}?label: I18n\.tr\("Copy"\)/);
    assert.match(reply, /objectName: "assistantHandoff"[\s\S]{0,160}?label: I18n\.tr\("Terminal"\)[\s\S]{0,120}?tip: I18n\.tr\("Continue in a terminal"\)/);
    const button = read("Assistant/AssistantButton.qml");
    assert.match(button, /property string tip: label === "" \? accessibleName : ""/, "a glyph-only button names itself on hover");
    assert.match(button, /hitPad: Math\.max\(0, \(Theme\.scaled\(32\) - height\) \/ 2\)/, "a 32 px pointer target");
});

test("one suggestion fits the moment: a failure, then a kept update, then a repeated warning", () => {
    const now = 10 * 3600 * 1000;
    const warnings = [1, 2, 3].map(minute => ({ key: "nm|Wi-Fi disconnected", summary: "Wi-Fi disconnected",
        at: now - minute * 60000 }));
    assert.equal(A.situation({ now: now, warnings: warnings.slice(0, 2) }), null, "twice is not yet a pattern");
    assert.deepEqual(A.situation({ now: now, warnings: warnings }),
        { kind: "repeated", at: now - 60000, summary: "Wi-Fi disconnected", count: 3 });
    assert.equal(A.situation({ now: now, warnings: warnings, kept: { at: now - 1000, version: "1.0.10" } }).kind, "kept");
    assert.equal(A.situation({ now: now, kept: { at: now - 1000 }, updateFailed: { at: now - 5000 } }).kind,
        "update-failed");
    assert.equal(A.situation({ now: now, updateFailed: { at: now - A.SITUATION_MS - 1 } }), null, "it lasts an hour");
    assert.equal(A.situation({ now: now, updateFailed: { at: now - 5000 }, dismissedAt: now - 1000 }), null,
        "asking anything ends it");
    assert.equal(A.looksLikeFailure("Backup failed", ""), true);
    assert.equal(A.looksLikeFailure("Song changed", "Now playing"), false);
    assert.equal(A.looksLikeFailure("Meeting", "in 5 minutes", true), true, "critical counts");
});

test("a drop near a corner or a side lands there; past a side edge he tucks away", () => {
    const zones = A.snapZones({ width: 1920, height: 1080 }, 88, 40);
    assert.deepEqual(zones.map(zone => zone.id),
        ["top-left", "top-right", "bottom-left", "bottom-right", "left", "right"]);
    const topRight = zones[1];
    assert.equal(A.snapTarget({ x: topRight.x - 30, y: topRight.y + 30 }, zones).id, "top-right");
    assert.equal(A.snapTarget({ x: 900, y: 500 }, zones), null, "the middle of the screen stays where dropped");
    assert.equal(A.tuckSide(1900, 20, 88, 1920), "right");
    assert.equal(A.tuckSide(10, 60, 88, 1920), "left");
    assert.equal(A.tuckSide(960, 40, 88, 1920), "");
    assert.equal(A.tuckedX("right", 88, 1920), 1920 - Math.round(88 * A.TUCK_VISIBLE));
    assert.ok(A.tuckedX("left", 88, 1920) < 0);
    const window = read("AssistantWindow.qml");
    assert.match(window, /Assistant\.tuckTo\(root\.tuckWanted\)/);
    assert.match(window, /zone \? zone\.x : AssistantHelpers\.clamp\(root\.dragX/);
});

test("the wide view stands beside Wiz on the side with more room", () => {
    const right = A.expandedPlacement({ x: 1800, y: 60 }, 88, { width: 1920, height: 1080 }, 560, 40);
    assert.equal(right.onLeft, true);
    assert.equal(right.x + right.width, 1800 - A.GAP);
    const left = A.expandedPlacement({ x: 40, y: 60 }, 88, { width: 1920, height: 1080 }, 560, 40);
    assert.equal(left.onLeft, false);
    assert.equal(left.x, 40 + 88 + A.GAP);
    assert.ok(left.height <= 720 && left.y >= 40);
    const narrow = A.expandedPlacement({ x: 600, y: 60 }, 88, { width: 1280, height: 720 }, 900, 0);
    assert.ok(narrow.width <= 600 - A.GAP - A.EDGE, "never wider than the room beside him");
});

test("a finished question notifies only when it took a while and the box was not in view", () => {
    assert.equal(A.notifies("closed", "finished", false, 25000), true);
    assert.equal(A.notifies("closed", "finished", true, 25000), false);
    assert.equal(A.notifies("closed", "finished", false, 5000), false);
    assert.equal(A.notifies("always", "finished", true, 25000), true);
    assert.equal(A.notifies("closed", "waiting", false, 0), true, "a waiting question always counts");
    assert.equal(A.notifies("never", "waiting", false, 0), false);
    const H = load("SettingsHelpers.js");
    assert.equal(H.defaults().assistantNotify, "closed");
    assert.equal(H.merge({ assistantNotify: "loud" }).assistantNotify, "closed");
});

test("attachments: local paths, images, sizes", () => {
    assert.equal(A.localPath("file:///home/me/a%20b.txt"), "/home/me/a b.txt");
    assert.equal(A.localPath("https://example.com/x"), "");
    assert.equal(A.isImagePath("/tmp/shot.PNG"), true);
    assert.equal(A.isImagePath("/tmp/build.log"), false);
    assert.equal(A.sizeLabel(48 * 1024), "48 KB");
    assert.equal(A.lineCount("a\nb\n"), 2);
    const assistant = read("Common/Assistant.qml");
    assert.match(assistant, /wl-paste --primary --no-newline/, "Super+Shift+I reads the primary selection");
    assert.match(assistant, /attachments: sent\.map\(item =>/);
    assert.match(read("shell.qml"), /name: "assistantSelection"[\s\S]*?onPressed: Assistant\.askAboutSelection\(\)/);
    assert.match(repo("desktop/hypr/bindings.lua"),
        /bind\(mainMod \.\. " \+ SHIFT \+ I", hl\.dsp\.global\("quickshell:assistantSelection"\)/);
});

test("a routine's finding shows the amber pip, and the agent model choice holds for one conversation", () => {
    assert.equal(A.characterPose({ connected: true, attention: true }), "needs-input");
    assert.equal(A.characterPose({ connected: true, attention: true, busy: true, step: "Thinking" }), "thinking");
    assert.deepEqual(A.modelChoices("codex").map(choice => choice.value),
        ["default", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]);
    assert.equal(A.modelLabel("claude", "opus"), "Opus");
    const assistant = read("Common/Assistant.qml");
    assert.match(assistant, /function startNew\(\) \{[\s\S]*?agentOverride = "";\s*modelOverride = "";/);
    assert.deepEqual(A.modelChoices("claude").map(choice => choice.value), ["default", "fable", "sonnet", "opus"]);
    // The same models Settings offers.
    const page = read("Settings/AssistantPage.qml");
    for (const choice of A.modelChoices("claude").concat(A.modelChoices("codex")).filter(c => c.value !== "default"))
        assert.match(page, new RegExp(`value: "${choice.value}"`));
});

test("the desktop tools the shell carries out never touch the assistant's own settings", () => {
    const tools = read("Common/AssistantTools.qml");
    assert.match(tools, /function blockedKey\(key\) \{\s*return \/\^assistant\/\.test\(key\);/);
    assert.match(tools, /SettingsHelpers\.normalizeKey\(key, value\)/, "values are checked as Settings checks them");
    assert.match(tools, /Settings\.saveNow\(\);/, "written at once, so the change log sees it");
    assert.match(tools, /if \(!windowFor\(address\)\)/, "a window that has gone is refused");
    const service = repo("desktop/assistant/cybexos_assistant/desktop.py");
    for (const name of ["settings_search", "settings_get", "settings_set", "wallpaper_set", "app_open",
        "window_focus", "window_move", "window_close", "workspace_switch", "desktop_status"])
        assert.match(service, new RegExp(`"${name}": \\{[^}]*"where": "shell"`));
    for (const name of ["settings_search", "settings_get", "settings_set", "wallpaper_set", "app_open",
        "window_focus", "window_move", "window_close", "workspace_switch", "desktop_status"])
        assert.match(tools, new RegExp(`case "${name}"`));
});

test("Ask Wiz appears where things go wrong and only prepares the question", () => {
    const notifs = read("Common/Notifs.qml");
    assert.match(notifs, /result\.unshift\(\{ kind: "ask-wiz", text: I18n\.tr\("Ask Wiz"\) \}\)/);
    assert.match(notifs, /if \(action\.kind === "ask-wiz"\) \{[\s\S]*?Assistant\.askWith\(/);
    assert.match(read("SoftwareUpdate/UpdateView.qml"), /objectName: "updateAskWiz"[\s\S]*?Assistant\.askAboutUpdate\(\)/);
    const assistant = read("Common/Assistant.qml");
    assert.match(assistant, /function askWith\(question, item\) \{[\s\S]*?draft = question;/);
    assert.doesNotMatch(assistant.match(/function askWith[\s\S]*?\n    \}/)[0], /send\(/, "nothing is sent until Enter");
});

test("Settings offers the new behaviour, the change log and routines", () => {
    const page = read("Settings/AssistantPage.qml");
    for (const key of ["assistantHover", "assistantNotify", "assistantFade", "assistantWindowContext", "assistantExpanded"])
        assert.match(page, new RegExp(`settingKey: "${key}"`));
    assert.match(page, /searchAnchor: "assistant-changes"/);
    assert.match(page, /searchAnchor: "assistant-routines"/);
    const H = load("SettingsHelpers.js");
    const d = H.defaults();
    assert.deepEqual([d.assistantHover, d.assistantFade, d.assistantWindowContext, d.assistantExpanded,
        d.assistantExpandedWidth, d.assistantTuck], ["status", true, true, false, 560, ""]);
    assert.equal(H.merge({ assistantExpandedWidth: 5000 }).assistantExpandedWidth, 1200, "kept within its range");
    assert.equal(H.merge({ assistantTuck: "top" }).assistantTuck, "");
});
