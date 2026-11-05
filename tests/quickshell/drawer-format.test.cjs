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
