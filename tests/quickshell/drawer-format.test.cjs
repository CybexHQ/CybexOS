// Popovers/Drawer/DrawerFormat.js: how Overview's summary arranges the
// readings Common/SysInfoHelpers.js formats (docs/shell-states.md).
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const F = require(path.join(shellDir, "Popovers", "Drawer", "DrawerFormat.js"));
const S = load("SysInfoHelpers.js");

test("a used / total pair shares its unit and keeps both when they differ", () => {
    assert.equal(F.pair("11.8 GiB", "30.7 GiB"), "11.8 / 30.7 GiB");
    assert.equal(F.pair("588 GB", "1 TB"), "588 GB / 1 TB");
    assert.equal(F.pair("0 B", "8 GiB"), "0 B / 8 GiB");
    assert.equal(F.pair("Unavailable", "Unavailable"), "Unavailable / Unavailable");
    // The units the drawer feeds it: memory binary, storage decimal.
    assert.equal(F.pair(S.formatIecBytes(11.8 * 2 ** 30), S.formatIecBytes(31 * 2 ** 30)),
        "11.8 / 31 GiB");
    assert.equal(F.pair(S.formatStorageBytes(588e9), S.formatStorageBytes(1e12)),
        "588 GB / 1 TB");
});

test("the machine is named once, and the summary drops a trailing parenthetical", () => {
    assert.equal(F.fullModel("Framework", "Laptop 13 (AMD Ryzen AI 300 Series)"),
        "Framework Laptop 13 (AMD Ryzen AI 300 Series)");
    assert.equal(F.compactModel("Framework", "Laptop 13 (AMD Ryzen AI 300 Series)"),
        "Framework Laptop 13");
    assert.equal(F.fullModel("LENOVO", "LENOVO ThinkPad X1"), "LENOVO ThinkPad X1");
    assert.equal(F.fullModel("Dell Inc.", ""), "Dell Inc.");
    assert.equal(F.fullModel("", "XPS 13 9350"), "XPS 13 9350");
    assert.equal(F.compactModel("", ""), "");
    assert.equal(F.compactModel("", "(Generic)"), "(Generic)",
        "a name that is only a parenthetical stays as it is");
});

test("uptime keeps its two largest units", () => {
    assert.equal(F.shortUptime(0), "0m");
    assert.equal(F.shortUptime(35 * 60 + 20), "35m");
    assert.equal(F.shortUptime(4 * 3600 + 5 * 60), "4h 5m");
    assert.equal(F.shortUptime(4 * 3600), "4h");
    assert.equal(F.shortUptime(12 * 86400 + 23 * 3600 + 50 * 60), "12d 23h");
    assert.equal(F.shortUptime(2 * 86400 + 30 * 60), "2d");
    assert.equal(F.shortUptime(-1), "");
    assert.equal(F.shortUptime(NaN), "");
});

test("Top processes drops to three rows only for a short body", () => {
    assert.equal(F.processRows(0, 640), 5, "no envelope: the full list");
    assert.equal(F.processRows(480, 640), 3);
    assert.equal(F.processRows(639, 640), 3);
    assert.equal(F.processRows(640, 640), 5);
    assert.equal(F.processRows(860, 640), 5);
});

test("a process reads as people know it, not as its Nix wrapper", () => {
    assert.equal(F.processLabel(".quickshell-wra"), "quickshell", "cut to 15 characters by the kernel");
    assert.equal(F.processLabel(".firefox-wrapped"), "firefox");
    assert.equal(F.processLabel(".firefox-wrappe"), "firefox");
    assert.equal(F.processLabel("MainThread"), "MainThread");
    assert.equal(F.processLabel(".xdg-desktop-po"), ".xdg-desktop-po", "only a wrapper suffix is dropped");
    assert.equal(F.processLabel(".hidden"), ".hidden");
    assert.equal(F.processLabel(""), "");
});

test("the tab strip keeps every label whole: one row, then more rows", () => {
    // Six labels at the default 14 px in a monospace face (8.4 px a
    // character), icons 19 px, 5 px either side, in the 400 px drawer.
    const labels = ["Overview", "Sound", "Network", "Bluetooth", "Power", "Alerts"]
        .map(label => Math.ceil(label.length * 8.4));
    const stacked = labels.map(w => Math.max(19, w) + 10);
    const inline = labels.map(w => 19 + 7 + w + 10);
    const one = F.tabLayout(stacked, inline, 429, 2);
    assert.equal(one.rows, 1);
    assert.equal(one.stacked, true);
    assert.ok(one.widths.every((w, i) => w >= stacked[i]), "no tab narrower than its label");
    assert.ok(Math.abs(one.widths.reduce((a, b) => a + b, 0) + 2 * 5 - 429) < 0.01, "the row is filled");
    // Room for all at the widest: equal widths.
    const wide = F.tabLayout(stacked, inline, 800, 2);
    assert.ok(wide.widths.every(w => w === wide.widths[0]));
    // A narrow drawer wraps onto rows of equal cells, beside the icon if it fits.
    const narrow = F.tabLayout(stacked, inline, 335, 2);
    assert.ok(narrow.rows >= 2);
    assert.ok(narrow.widths.every(w => w === narrow.widths[0]));
    const cellNeeds = narrow.stacked ? Math.max(...stacked) : Math.max(...inline);
    assert.ok(narrow.widths[0] >= cellNeeds, "every label fits its cell");
    assert.equal(narrow.rows, Math.ceil(6 / narrow.columns));
    assert.deepEqual(F.tabLayout([], [], 400, 2).widths, []);
    // Nothing fits even one column: one column regardless, labels wrap there.
    assert.equal(F.tabLayout([500], [520], 300, 2).columns, 1);
});
