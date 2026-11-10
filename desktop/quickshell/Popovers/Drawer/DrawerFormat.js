// Pure formatting for the drawer's Overview (DrawerSystemHero.qml,
// DrawerProcesses.qml) and its tab strip (DrawerTabs.qml). Keep this file
// free of Qt APIs so
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

// A process as people know it. Nix wraps programs as ".name-wrapped", and
// the kernel keeps only 15 characters of a command name, so the list showed
// ".quickshell-wra". Anything else is shown as it came.
function processLabel(name) {
    var text = String(name || "");
    if (text.charAt(0) !== "." || text.length < 3)
        return text;
    var dash = text.lastIndexOf("-");
    if (dash <= 1)
        return text;
    var tail = text.slice(dash + 1);
    if (tail === "wrapped" || (text.length === 15 && tail !== ""
            && "wrapped".indexOf(tail) === 0))
        return text.slice(1, dash);
    return text;
}

// The tab strip's arrangement (DrawerTabs.qml). `stacked` and `inline` hold
// each tab's natural width with its label under or beside its icon,
// `available` the strip's inner width and `gap` the space between tabs.
//
// One row of stacked tabs whenever every label fits whole: the same width
// for all when even the widest fits that way, otherwise each its natural
// width plus an equal share of what is left. When they do not fit (a narrow
// drawer, a long translation), the fewest rows of equal columns in which
// every label fits, beside its icon if it can (a lower row) and under it
// otherwise. A label is never cut short.
function tabLayout(stacked, inline, available, gap) {
    var count = stacked.length;
    var room = Math.max(0, Number(available) || 0);
    var spacing = Math.max(0, Number(gap) || 0);
    var fill = function(width, n) {
        var widths = [];
        for (var i = 0; i < n; i++)
            widths.push(width);
        return widths;
    };
    if (count === 0)
        return { rows: 1, columns: 1, stacked: true, widths: [] };

    var share = Math.max(0, room - spacing * (count - 1));
    var sum = 0, widest = 0;
    for (var i = 0; i < count; i++) {
        sum += stacked[i];
        widest = Math.max(widest, stacked[i]);
    }
    if (sum <= share) {
        if (widest * count <= share)
            return { rows: 1, columns: count, stacked: true, widths: fill(share / count, count) };
        var extra = (share - sum) / count;
        return { rows: 1, columns: count, stacked: true,
            widths: stacked.map(function(width) { return width + extra; }) };
    }

    var widestInline = 0;
    for (var j = 0; j < count; j++)
        widestInline = Math.max(widestInline, inline[j]);
    for (var rows = 2; rows <= count; rows++) {
        var columns = Math.ceil(count / rows);
        var cell = Math.max(0, room - spacing * (columns - 1)) / columns;
        if (widestInline <= cell || columns === 1)
            return { rows: Math.ceil(count / columns), columns: columns, stacked: false,
                widths: fill(cell, count) };
        if (widest <= cell)
            return { rows: Math.ceil(count / columns), columns: columns, stacked: true,
                widths: fill(cell, count) };
    }
    return { rows: count, columns: 1, stacked: false, widths: fill(room, count) };
}

var exported = {
    pair: pair,
    fullModel: fullModel,
    compactModel: compactModel,
    shortUptime: shortUptime,
    processRows: processRows,
    processLabel: processLabel,
    tabLayout: tabLayout
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
