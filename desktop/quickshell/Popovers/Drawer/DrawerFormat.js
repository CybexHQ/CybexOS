// Pure formatting for the drawer's Overview (DrawerSystemHero.qml,
// DrawerProcesses.qml). Keep this file free of Qt APIs so
// tests/quickshell/drawer-format.test.cjs runs the exact rules under Node.
// Units come from Common/SysInfoHelpers.js (docs/shell-states.md): storage
// decimal, memory binary; this file only arranges what they return.

// "11.8 GiB" and "30.7 GiB" read as "11.8 / 30.7 GiB"; mixed units keep
// both ("588 GB / 1 TB"). Anything that is not "<number> <unit>" (such as
// "Unavailable") is shown as it came.
function pair(used, total) {
    var a = String(used), b = String(total);
    var unitA = a.lastIndexOf(" "), unitB = b.lastIndexOf(" ");
    if (unitA > 0 && unitB > 0 && a.slice(unitA) === b.slice(unitB))
        return a.slice(0, unitA) + " / " + b;
    return a + " / " + b;
}

// The machine as a person names it: the vendor once, then the model.
// DMI often repeats the vendor in the product name ("LENOVO" + "LENOVO
// ThinkPad"), and Framework's product name has no vendor at all.
function fullModel(vendor, model) {
    var v = String(vendor || "").trim(), m = String(model || "").trim();
    if (m === "")
        return v;
    if (v === "" || m.toLowerCase().indexOf(v.toLowerCase()) === 0)
        return m;
    return v + " " + m;
}

// The summary line's short form: a trailing parenthetical ("(AMD Ryzen AI
// 300 Series)") moves to Details, where the full model is listed.
function compactModel(vendor, model) {
    var full = fullModel(vendor, model);
    var trimmed = full.replace(/\s*\([^()]*\)\s*$/, "").trim();
    return trimmed !== "" ? trimmed : full;
}

// Uptime to two units at most: "12d 23h", "4h 5m", "35m".
function shortUptime(seconds) {
    var value = Number(seconds);
    if (!isFinite(value) || value < 0)
        return "";
    var minutes = Math.floor(value / 60);
    var days = Math.floor(minutes / 1440);
    var hours = Math.floor(minutes / 60) % 24;
    var mins = minutes % 60;
    if (days > 0)
        return hours > 0 ? days + "d " + hours + "h" : days + "d";
    if (hours > 0)
        return mins > 0 ? hours + "h " + mins + "m" : hours + "h";
    return mins + "m";
}

// Top processes shows five rows, or three when the drawer body is too short
// for them below the everyday controls (a 1280×720 laptop). Decided from
// the body's height budget, never from the content above, so the list does
// not jump when a player or an update card comes and goes. A budget of 0
// means the host gave no envelope: the full list.
function processRows(budget, shortBelow) {
    var value = Number(budget);
    return value > 0 && value < Number(shortBelow) ? 3 : 5;
}

var exported = {
    pair: pair,
    fullModel: fullModel,
    compactModel: compactModel,
    shortUptime: shortUptime,
    processRows: processRows
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
