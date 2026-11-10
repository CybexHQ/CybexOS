// Pure rules for the Cybex OS Assistant (docs/assistant.md): where the
// character stands, which side of it the box opens on, which agent answers,
// and how a turn snapshot from the service reads on screen. Shared by QML and
// Node tests, so no Qt APIs.

// Space kept between the character, its box and the edges of the output.
var EDGE = 12;
var GAP = 10;
// The box opens below unless it would get less than this and above has more.
var MIN_BELOW = 300;
// A press that moves less than this is a click, not a drag.
var DRAG_THRESHOLD = 4;
// Super+I held this long is push-to-talk; a shorter press is a tap.
var HOLD_MS = 280;

var AGENT_IDS = ["claude", "codex"];
var AGENT_LABELS = { claude: "Claude Code", codex: "Codex" };
// Brand marks bundled with the shell (BrandIcons.qml).
var AGENT_ICONS = { claude: "claude", codex: "openai" };

// The approval card's glyph for each kind of request.
var APPROVAL_GLYPHS = { command: "terminal", edit: "edit", apply: "deployed_code_update", other: "security" };

var ACTIVE_STATUSES = ["running", "waiting"];
var FINISHED_STATUSES = ["completed", "stopped", "failed"];
// The service's step while the agent thinks or writes; any other step is a
// tool at work (cybexos_assistant/turn.py).
var THINKING_STEP = "Thinking";

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

// Where the character stands on an output of width × height. A saved place
// of -1 is the default: the top-right corner, below the bar's reserve. A saved
// place from a larger output is pulled back inside this one.
function placement(saved, output, size, topReserve) {
    var width = Math.max(size, output.width || 0);
    var height = Math.max(size, output.height || 0);
    var reserve = Math.max(0, topReserve || 0);
    var x = typeof saved.x === "number" && saved.x >= 0 ? saved.x : width - size - EDGE * 2;
    var y = typeof saved.y === "number" && saved.y >= 0 ? saved.y : reserve + EDGE * 2;
    return {
        x: Math.round(clamp(x, 0, width - size)),
        y: Math.round(clamp(y, 0, height - size))
    };
}

// The box under (or over) the character. It flips above only when below is
// cramped and above is roomier; `room` is the height it may grow to, which
// the reply card scrolls within.
function dockPlacement(bubble, size, output, dockWidth, topReserve) {
    var width = output.width || 0;
    var height = output.height || 0;
    var reserve = Math.max(0, topReserve || 0);
    var w = Math.min(dockWidth, Math.max(0, width - EDGE * 2));
    var below = height - (bubble.y + size + GAP) - EDGE;
    var aboveRoom = bubble.y - GAP - Math.max(EDGE, reserve);
    var above = below < MIN_BELOW && aboveRoom > below;
    var x = clamp(bubble.x + size / 2 - w / 2, EDGE, Math.max(EDGE, width - w - EDGE));
    return {
        x: Math.round(x),
        width: Math.round(w),
        above: above,
        room: Math.max(0, Math.round(above ? aboveRoom : below)),
        // The edge the box grows from: its top when below, its bottom when above.
        anchorY: Math.round(above ? bubble.y - GAP : bubble.y + size + GAP)
    };
}

// The output under a point in global (compositor) coordinates, for a drag
// that ended on another display. Returns -1 when the point is on none.
function outputAt(outputs, x, y) {
    for (var i = 0; i < outputs.length; i++) {
        var o = outputs[i];
        if (x >= o.x && x < o.x + o.width && y >= o.y && y < o.y + o.height)
            return i;
    }
    return -1;
}

function dragged(dx, dy) {
    return Math.abs(dx) > DRAG_THRESHOLD || Math.abs(dy) > DRAG_THRESHOLD;
}

// "auto" follows the `cybex agent` default when it is one of ours and
// installed, then Claude Code, then Codex. An explicit choice that is not
// installed is still returned: the service reports it as missing, which
// tells the person what to install.
function resolveAgent(setting, agents, preferred) {
    var installed = function(id) {
        return !!(agents && agents[id] && agents[id].available);
    };
    if (setting === "claude" || setting === "codex")
        return setting;
    var ready = function(id) {
        return installed(id) && agents[id].auth === "ready";
    };
    if (AGENT_IDS.indexOf(preferred) !== -1 && ready(preferred))
        return preferred;
    for (var j = 0; j < AGENT_IDS.length; j++) {
        if (ready(AGENT_IDS[j]))
            return AGENT_IDS[j];
    }
    if (AGENT_IDS.indexOf(preferred) !== -1 && installed(preferred))
        return preferred;
    for (var i = 0; i < AGENT_IDS.length; i++) {
        if (installed(AGENT_IDS[i]))
            return AGENT_IDS[i];
    }
    return "claude";
}

// The agent chip cycles through the installed agents only.
function nextAgent(current, agents) {
    var installed = AGENT_IDS.filter(function(id) {
        return !!(agents && agents[id] && agents[id].available);
    });
    if (installed.length === 0)
        return current;
    var index = installed.indexOf(current);
    return installed[(index + 1) % installed.length];
}

function anyAgent(agents) {
    return AGENT_IDS.some(function(id) {
        return !!(agents && agents[id] && agents[id].available);
    });
}

// The model sent with a turn; "default" leaves it to the agent's own config.
function modelFor(agent, claudeModel, codexModel) {
    var value = agent === "codex" ? codexModel : claudeModel;
    return value && value !== "default" ? value : "";
}

function active(turn) {
    return !!turn && ACTIVE_STATUSES.indexOf(turn.status) !== -1;
}

function finished(turn) {
    return !!turn && FINISHED_STATUSES.indexOf(turn.status) !== -1;
}

// Wiz's pose (Assistant/Wiz.qml), the most urgent state first: being
// dragged, no service, the microphone, a question waiting, a turn at work (a
// tool's step is work, the service's own step is thinking), a finished turn's
// celebration or another happy moment, a failed reply, and an open box, which
// he listens to.
function characterPose(state) {
    if (state.dragging)
        return "carried";
    if (!state.connected)
        return "asleep";
    if (state.listening)
        return "listening";
    if (state.waiting)
        return "needs-input";
    if (state.busy || state.transcribing)
        return state.busy && state.step && state.step !== THINKING_STEP ? "working" : "thinking";
    // A routine found something: the amber pip until it is opened.
    if (state.attention)
        return "needs-input";
    if (state.celebrating)
        return "finished";
    if (state.speaking)
        return "happy";
    if (state.failed)
        return "sorry";
    if (state.composing)
        return "listening";
    return "idle";
}

// "8 s", "1 min 05 s", "12 min": the worker pill's elapsed time.
function elapsedLabel(ms) {
    var seconds = Math.max(0, Math.floor((ms || 0) / 1000));
    if (seconds < 60)
        return seconds + " s";
    var minutes = Math.floor(seconds / 60);
    if (minutes >= 10)
        return minutes + " min";
    var rest = seconds % 60;
    return minutes + " min " + (rest < 10 ? "0" : "") + rest + " s";
}

// A ~/-relative path reads better in a narrow card than the full home path.
function displayPath(path, home) {
    var value = String(path || "");
    if (home && (value === home || value.indexOf(home + "/") === 0))
        return "~" + value.slice(home.length);
    return value;
}

// Closure changes from `nix store diff-closures` as rows for the review card:
// "obsidian: ∅ → 1.9.12, +148.2 MiB" becomes {name, change, kind}.
function closureChanges(text, limit) {
    var rows = [];
    String(text || "").replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").split("\n").forEach(function(line) {
        var match = /^\s*([^:]+):\s*(.+?)\s*$/.exec(line);
        if (!match)
            return;
        var change = match[2];
        var kind = /∅ →/.test(change) ? "added" : /→ ∅/.test(change) ? "removed" : "changed";
        rows.push({ name: match[1].trim(), change: change, kind: kind });
    });
    var max = limit || 8;
    return { rows: rows.slice(0, max), more: Math.max(0, rows.length - max) };
}

// Turns a service failure into the one action that would fix it.
function errorAction(kind, agent) {
    switch (kind) {
    case "auth": return { label: "Sign in", auth: true };
    case "missing": return { label: "Settings", page: "assistant" };
    case "service": return { label: "Start the assistant", unit: "cybexos-assistant.service" };
    default: return null;
    }
}

// A finished turn's reply as it is copied: the text, without the trailing
// whitespace Markdown leaves behind.
function copyText(turn) {
    return String(turn && turn.text || "").replace(/\s+$/, "");
}

// A whole conversation as it is copied: each question, then its answer.
function conversationText(conversation) {
    return ((conversation && conversation.turns) || []).map(function(turn) {
        var answer = turn.status === "failed" ? (turn.error || "") : (turn.text || "");
        return "> " + String(turn.prompt || "").split("\n").join("\n> ") + "\n\n" + answer.replace(/\s+$/, "");
    }).join("\n\n");
}

// ---- conversation history ---------------------------------------------------
// The new box lists this many recent conversations under its suggestions.
var RECENT_LIMIT = 3;
var DAY_MS = 24 * 3600 * 1000;

function startOfDay(ms, offsetDays) {
    var d = new Date(ms);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + (offsetDays || 0)).getTime();
}

// The heading a conversation is listed under: "today", "yesterday", "week"
// (the five days before) or "older".
function historyGroup(at, now) {
    if (at >= startOfDay(now, 0))
        return "today";
    if (at >= startOfDay(now, -1))
        return "yesterday";
    if (at >= startOfDay(now, -6))
        return "week";
    return "older";
}

// How a row reads its time: "now", "minutes" (value), "time" (today),
// "yesterday", "weekday" (the last week) or "date". The view formats the
// time, weekday and date in the shell's language.
function historyTime(at, now) {
    var minutes = Math.floor(Math.max(0, now - at) / 60000);
    if (minutes < 1)
        return { kind: "now", value: 0 };
    if (minutes < 60)
        return { kind: "minutes", value: minutes };
    var group = historyGroup(at, now);
    if (group === "today")
        return { kind: "time", value: at };
    if (group === "yesterday")
        return { kind: "yesterday", value: at };
    if (group === "week")
        return { kind: "weekday", value: at };
    return { kind: "date", value: at };
}

// Rows under their day headings, newest first, headings in order.
function groupConversations(rows, now) {
    var order = ["today", "yesterday", "week", "older"];
    var groups = {};
    (rows || []).forEach(function(row) {
        var key = historyGroup(row.updatedAt || 0, now);
        (groups[key] = groups[key] || []).push(row);
    });
    return order.filter(function(key) { return !!groups[key]; }).map(function(key) {
        return { group: key, rows: groups[key] };
    });
}

// A row's status, live while its question runs in the service.
function liveStatus(row, turn) {
    if (row && turn && turn.conversation === row.id && active(turn))
        return turn.status;
    return row ? row.status : "";
}

// Clicking the character, a tap of Super+I or the launcher opens a new
// conversation, unless the last one still needs the person: a question
// running or waiting for an answer, or an answer they have not seen.
function opensLastConversation(state) {
    return !!(state.busy || (state.unread && state.hasReply));
}

// ---- replies ------------------------------------------------------------------
// A reply split into its prose and its fenced code blocks, so each code block
// can carry its own Copy button: [{kind: "text", text}, {kind: "code", lang, text}].
// An unclosed fence (a reply still streaming) runs to the end.
function markdownBlocks(text) {
    var lines = String(text || "").split("\n");
    var blocks = [];
    var prose = [];
    var code = null;
    function flushProse() {
        var joined = prose.join("\n");
        if (joined.trim() !== "")
            blocks.push({ kind: "text", text: joined.replace(/^\n+|\n+$/g, "") });
        prose = [];
    }
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var fence = /^\s{0,3}(`{3,}|~{3,})\s*([^`\s]*)/.exec(line);
        if (code === null && fence) {
            flushProse();
            code = { marker: fence[1], lang: fence[2] || "", lines: [] };
        } else if (code !== null && new RegExp("^\\s{0,3}" + code.marker.charAt(0) + "{" + code.marker.length + ",}\\s*$").test(line)) {
            blocks.push({ kind: "code", lang: code.lang, text: code.lines.join("\n") });
            code = null;
        } else if (code !== null) {
            code.lines.push(line);
        } else {
            prose.push(line);
        }
    }
    if (code !== null)
        blocks.push({ kind: "code", lang: code.lang, text: code.lines.join("\n") });
    flushProse();
    return blocks;
}

// The step list starts folded after a short answer and open after a long one.
var FOLD_STEPS_BELOW = 400;

function stepsFolded(text, steps) {
    return (steps || []).length > 0 && String(text || "").length < FOLD_STEPS_BELOW;
}

// ---- what changed ------------------------------------------------------------------
// "barOpacity" reads "Bar opacity" when the settings index has no label for it.
function humanizeKey(key) {
    var words = String(key || "").replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ").trim();
    return words === "" ? "" : words.charAt(0).toUpperCase() + words.slice(1).toLowerCase();
}

// A setting's value as a change row shows it: On/Off, 80%, a short text.
// `kind` hints how a number reads ("percent" for 0–1 opacities).
function formatValue(value, present) {
    if (present === false)
        return "default";
    if (value === null || value === undefined)
        return "none";
    if (value === true)
        return "On";
    if (value === false)
        return "Off";
    if (typeof value === "number") {
        if (value > 0 && value < 1 && String(value).length <= 5)
            return Math.round(value * 100) + "%";
        return String(value);
    }
    if (typeof value === "string")
        return value === "" ? "empty" : value.length > 28 ? value.slice(0, 27) + "…" : value;
    var text = JSON.stringify(value);
    return text.length > 28 ? text.slice(0, 27) + "…" : text;
}

// The label of a settings key from the search index's rows, else humanized.
function settingLabel(key, rows) {
    var found = settingRow(key, rows);
    return found ? found.label : humanizeKey(key);
}

function settingRow(key, rows) {
    for (var i = 0; i < (rows || []).length; i++) {
        if (rows[i].key === key)
            return rows[i];
    }
    return null;
}

// A setting's value where the file had none: the default it stood at, when
// `defaults` (Settings.defaults) knows the key, so a row reads "Off → On"
// rather than "default → On".
function settingValue(key, value, present, defaults) {
    if (present === false && defaults && Object.prototype.hasOwnProperty.call(defaults, key))
        return formatValue(defaults[key], true);
    return formatValue(value, present);
}

// One change from the service's log as a row reads: what, old → new, and
// whether Undo is offered (docs/assistant.md). A setting is named as
// Settings names it, with where it lives ("Appearance · Theme") in `place`;
// `defaults` resolves a value the file did not hold yet.
function changeRow(change, rows, defaults) {
    var c = change || {};
    var row = { id: c.id, kind: c.kind, status: c.status, undoable: !!c.undoable, at: c.at || 0,
        question: c.question || "", conversation: c.conversation || "", label: "", before: "", after: "",
        detail: "", place: "", glyph: "edit", action: "undo" };
    switch (c.kind) {
    case "setting": {
        var found = settingRow(c.key, rows);
        row.label = found ? found.label : humanizeKey(c.key);
        row.place = found ? [found.pageLabel || "", found.group || ""].filter(function(part) { return part !== ""; })
            .join(" · ") : "";
        row.before = settingValue(c.key, c.before, c.hadBefore, defaults);
        row.after = settingValue(c.key, c.after, c.hasAfter, defaults);
        row.glyph = /^(wall|palette|theme|accent|font|bar|glass)/i.test(c.key || "") ? "palette" : "tune";
        break;
    }
    case "file":
        row.label = c.path || "";
        row.detail = (c.files && c.files[0] && c.files[0].op) || c.op || "modified";
        row.glyph = "description";
        row.action = row.detail === "created" ? "delete" : "undo";
        break;
    case "plugin":
        row.label = c.name || c.plugin || "";
        row.detail = c.op || "created";
        row.glyph = "widgets";
        row.action = c.op === "created" ? "remove" : "undo";
        break;
    case "app":
        row.label = (c.app && (c.app.name || c.app.id)) || "";
        row.detail = c.op || "installed";
        row.glyph = "apps";
        row.action = c.op === "installed" ? "remove" : "undo";
        break;
    case "routine":
        row.label = (c.routine && c.routine.title) || "";
        row.detail = c.op === "deleted" ? "removed" : "created";
        row.glyph = "repeat";
        row.action = c.op === "created" ? "remove" : "undo";
        break;
    case "system":
        row.label = "System change";
        row.detail = c.transaction || "";
        row.glyph = "deployed_code_update";
        row.action = "review";
        break;
    }
    return row;
}

// Rows under day headings, as History groups conversations.
function groupChanges(changes, now) {
    return groupConversations((changes || []).map(function(change) {
        return Object.assign({}, change, { updatedAt: change.at || 0 });
    }), now);
}

// ---- the suggestion that fits the moment ----------------------------------------------
var SITUATION_MS = 3600 * 1000;
var REPEATS = 3;

// The one situational suggestion, or null: a failure first, then a kept
// update, then a warning repeated in notifications. `state` holds the
// moments the shell noticed: {now, updateFailed: {at, version}, kept: {at,
// version}, warnings: [{key, summary, at}], dismissedAt}. Each lasts an hour
// and ends once used or when Wiz is asked something else (dismissedAt).
function situation(state) {
    var s = state || {};
    var now = s.now || 0;
    var fresh = function(at) {
        return typeof at === "number" && at > 0 && now - at < SITUATION_MS && at > (s.dismissedAt || 0);
    };
    if (s.updateFailed && fresh(s.updateFailed.at))
        return { kind: "update-failed", at: s.updateFailed.at, version: s.updateFailed.version || "" };
    if (s.kept && fresh(s.kept.at))
        return { kind: "kept", at: s.kept.at, version: s.kept.version || "" };
    var counts = {};
    var latest = {};
    (s.warnings || []).forEach(function(warning) {
        if (!fresh(warning.at))
            return;
        counts[warning.key] = (counts[warning.key] || 0) + 1;
        if (!latest[warning.key] || warning.at > latest[warning.key].at)
            latest[warning.key] = warning;
    });
    var best = null;
    Object.keys(counts).forEach(function(key) {
        if (counts[key] >= REPEATS && (!best || latest[key].at > best.at))
            best = { kind: "repeated", at: latest[key].at, summary: latest[key].summary, count: counts[key] };
    });
    return best;
}

// Whether a notification reads as something going wrong, which earns it an
// Ask Wiz action and counts toward a repeated warning.
function looksLikeFailure(summary, body, critical) {
    if (critical)
        return true;
    return /\b(fail(ed|s|ure)?|error|could ?n[o']t|can ?n[o']t|unable|disconnected|lost|crash(ed)?|denied|problem)\b/i
        .test(String(summary || "") + " " + String(body || "").slice(0, 400));
}

// ---- placing the character -------------------------------------------------------------
// While dragging, these spots catch the character: the four corners and the
// middle of each side edge, kept clear of the bar.
var SNAP_DISTANCE = 72;

function snapZones(output, size, topReserve) {
    var w = output.width || 0;
    var h = output.height || 0;
    var top = Math.max(0, topReserve || 0) + EDGE * 2;
    var left = EDGE * 2;
    var right = Math.max(left, w - size - EDGE * 2);
    var bottom = Math.max(top, h - size - EDGE * 2);
    var middle = Math.round((top + bottom) / 2);
    return [
        { id: "top-left", x: left, y: top }, { id: "top-right", x: right, y: top },
        { id: "bottom-left", x: left, y: bottom }, { id: "bottom-right", x: right, y: bottom },
        { id: "left", x: left, y: middle }, { id: "right", x: right, y: middle }
    ];
}

// The zone a drop lands in, or null to stay exactly where it was dropped.
function snapTarget(point, zones) {
    var best = null;
    var bestDistance = SNAP_DISTANCE;
    (zones || []).forEach(function(zone) {
        var distance = Math.sqrt(Math.pow(zone.x - point.x, 2) + Math.pow(zone.y - point.y, 2));
        if (distance <= bestDistance) {
            best = zone;
            bestDistance = distance;
        }
    });
    return best;
}

// A drop with more than this share of him past the side edge tucks him away.
var TUCK_SHARE = 0.4;
// How much of him still shows when tucked: the hat's brim and one eye.
var TUCK_VISIBLE = 0.36;

function tuckSide(pointerX, grabX, size, width) {
    var left = pointerX - grabX;
    if (left < -size * TUCK_SHARE)
        return "left";
    if (left + size > width + size * TUCK_SHARE)
        return "right";
    return "";
}

function tuckedX(side, size, width) {
    var shown = Math.round(size * TUCK_VISIBLE);
    return side === "left" ? shown - size : width - shown;
}

// ---- the wide view ------------------------------------------------------------------------
// The expanded box stands beside the character, on the side with more room,
// from the top of the free area down; `width` is the person's chosen width.
function expandedPlacement(bubble, size, output, width, topReserve) {
    var w = output.width || 0;
    var h = output.height || 0;
    var reserve = Math.max(0, topReserve || 0);
    var leftRoom = bubble.x - GAP - EDGE;
    var rightRoom = w - (bubble.x + size + GAP) - EDGE;
    var onLeft = leftRoom >= rightRoom;
    var room = Math.max(0, onLeft ? leftRoom : rightRoom);
    var boxWidth = Math.round(clamp(width || 560, Math.min(320, room), Math.max(Math.min(320, room), room)));
    var top = Math.max(reserve + EDGE, Math.min(bubble.y, h - EDGE - 320));
    return {
        x: Math.round(onLeft ? bubble.x - GAP - boxWidth : bubble.x + size + GAP),
        y: Math.round(top),
        width: boxWidth,
        height: Math.round(Math.max(240, Math.min(720, h - top - EDGE))),
        onLeft: onLeft
    };
}

// ---- agent and model ------------------------------------------------------------------
var CLAUDE_MODELS = [{ value: "default", label: "Default" }, { value: "fable", label: "Fable" },
    { value: "sonnet", label: "Sonnet" }, { value: "opus", label: "Opus" }];
var CODEX_MODELS = [{ value: "default", label: "Default" }, { value: "gpt-5.6-luna", label: "Luna" },
    { value: "gpt-5.6-terra", label: "Terra" }, { value: "gpt-5.6-sol", label: "Sol" }];

function modelChoices(agent) {
    return agent === "codex" ? CODEX_MODELS : CLAUDE_MODELS;
}

function modelLabel(agent, value) {
    var choices = modelChoices(agent);
    for (var i = 0; i < choices.length; i++) {
        if (choices[i].value === value)
            return choices[i].label;
    }
    return value || "Default";
}

// ---- telling the person ----------------------------------------------------------------
// A question that took this long earns a notification when it finishes out of sight.
var NOTIFY_AFTER_MS = 20000;

// Whether a turn's moment ("finished" or "waiting") becomes a notification.
function notifies(setting, moment, boxVisible, durationMs) {
    if (setting === "never")
        return false;
    if (setting === "closed" && boxVisible)
        return false;
    if (moment === "waiting")
        return true;
    return durationMs >= NOTIFY_AFTER_MS;
}

// ---- attachments ----------------------------------------------------------------------------
var IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "webp", "gif"];
var ATTACHMENT_GLYPHS = { window: "window", selection: "select", image: "photo", text: "warning", file: "attach_file" };

function attachmentGlyph(kind) {
    return ATTACHMENT_GLYPHS[kind] || "attach_file";
}
var MAX_ATTACHMENTS = 8;

function isImagePath(path) {
    var match = /\.([A-Za-z0-9]+)$/.exec(String(path || ""));
    return !!match && IMAGE_EXTENSIONS.indexOf(match[1].toLowerCase()) !== -1;
}

// file:///home/a%20b.txt → /home/a b.txt; anything not a local file → "".
function localPath(url) {
    var text = String(url || "");
    if (text.indexOf("file://") !== 0)
        return text.charAt(0) === "/" ? text : "";
    try {
        return decodeURIComponent(text.slice(7).replace(/^localhost/, ""));
    } catch (e) {
        return "";
    }
}

function lineCount(text) {
    var value = String(text || "").replace(/\n+$/, "");
    return value === "" ? 0 : value.split("\n").length;
}

function sizeLabel(bytes) {
    var value = Math.max(0, bytes || 0);
    if (value < 1024)
        return value + " B";
    if (value < 1024 * 1024)
        return Math.round(value / 1024) + " KB";
    return (value / 1024 / 1024).toFixed(1) + " MB";
}

var exported = {
    EDGE: EDGE,
    GAP: GAP,
    MIN_BELOW: MIN_BELOW,
    DRAG_THRESHOLD: DRAG_THRESHOLD,
    HOLD_MS: HOLD_MS,
    AGENT_IDS: AGENT_IDS,
    AGENT_LABELS: AGENT_LABELS,
    AGENT_ICONS: AGENT_ICONS,
    APPROVAL_GLYPHS: APPROVAL_GLYPHS,
    clamp: clamp,
    placement: placement,
    dockPlacement: dockPlacement,
    outputAt: outputAt,
    dragged: dragged,
    resolveAgent: resolveAgent,
    nextAgent: nextAgent,
    anyAgent: anyAgent,
    modelFor: modelFor,
    active: active,
    finished: finished,
    characterPose: characterPose,
    elapsedLabel: elapsedLabel,
    displayPath: displayPath,
    closureChanges: closureChanges,
    errorAction: errorAction,
    copyText: copyText,
    RECENT_LIMIT: RECENT_LIMIT,
    historyGroup: historyGroup,
    historyTime: historyTime,
    groupConversations: groupConversations,
    liveStatus: liveStatus,
    opensLastConversation: opensLastConversation,
    conversationText: conversationText,
    markdownBlocks: markdownBlocks,
    FOLD_STEPS_BELOW: FOLD_STEPS_BELOW,
    stepsFolded: stepsFolded,
    humanizeKey: humanizeKey,
    formatValue: formatValue,
    settingLabel: settingLabel,
    settingRow: settingRow,
    settingValue: settingValue,
    changeRow: changeRow,
    groupChanges: groupChanges,
    SITUATION_MS: SITUATION_MS,
    situation: situation,
    looksLikeFailure: looksLikeFailure,
    SNAP_DISTANCE: SNAP_DISTANCE,
    snapZones: snapZones,
    snapTarget: snapTarget,
    TUCK_VISIBLE: TUCK_VISIBLE,
    tuckSide: tuckSide,
    tuckedX: tuckedX,
    expandedPlacement: expandedPlacement,
    modelChoices: modelChoices,
    modelLabel: modelLabel,
    NOTIFY_AFTER_MS: NOTIFY_AFTER_MS,
    notifies: notifies,
    isImagePath: isImagePath,
    localPath: localPath,
    lineCount: lineCount,
    sizeLabel: sizeLabel,
    MAX_ATTACHMENTS: MAX_ATTACHMENTS,
    attachmentGlyph: attachmentGlyph
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
