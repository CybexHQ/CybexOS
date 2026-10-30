// Settings -> Appearance -> Pointer: which pointer the settings ask for
// (Common/PointerHelpers.js), the schema-31 keys, the catalogue and its
// shipped previews, and the Hyprland side of hiding the pointer.
// tests/nixos/test_pointer.py covers scripts/pointer.py and cybexos-session.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { shellDir, load, untranslated } = require("./shell.cjs");

const H = load("SettingsHelpers.js");
const P = load("PointerHelpers.js");
const repo = path.resolve(shellDir, "../..");
const read = relative => untranslated(fs.readFileSync(path.join(shellDir, relative), "utf8"));

const installed = (id, extra = {}) => ({ id, name: id, installed: true, left: "", leftInstalled: false, ...extra });
const FALLBACK = { theme: "Bibata-Modern-Classic", size: 24 };
const settings = (values = {}) => ({ pointerTheme: "", pointerSize: "default", pointerLeftHanded: false, ...values });

test("the helpers validate exactly what the settings schema stores", () => {
    assert.equal(P.THEME.source, /^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/.source);
    assert.match(fs.readFileSync(path.join(shellDir, "Common/SettingsHelpers.js"), "utf8"),
        new RegExp("var POINTER_THEME = /" + P.THEME.source.replace(/[\\^$.*+?()[\]{}|/]/g, "\\$&") + "/;"));
    assert.deepEqual(P.SIZES, H.POINTER_SIZES);
    assert.deepEqual(H.POINTER_SIZE_IDS, ["default"].concat(Object.keys(P.SIZES)));
});

test("schema 31 stores the pointer with safe fallbacks", () => {
    const d = H.defaults();
    assert.deepEqual([d.pointerTheme, d.pointerSize, d.pointerLeftHanded, d.pointerHideTyping, d.pointerHideIdle],
        ["", "default", false, false, 0]);
    const good = H.merge({ v: 31, pointerTheme: "WhiteSur-cursors", pointerSize: "largest", pointerLeftHanded: true,
        pointerHideTyping: true, pointerHideIdle: 10 });
    assert.deepEqual([good.pointerTheme, good.pointerSize, good.pointerLeftHanded, good.pointerHideTyping,
        good.pointerHideIdle], ["WhiteSur-cursors", "largest", true, true, 10]);
    const bad = H.merge({ v: 31, pointerTheme: "../../etc", pointerSize: "huge", pointerLeftHanded: "yes",
        pointerHideTyping: 1, pointerHideIdle: 30 });
    assert.deepEqual([bad.pointerTheme, bad.pointerSize, bad.pointerLeftHanded, bad.pointerHideTyping,
        bad.pointerHideIdle], ["", "default", false, false, 0],
        "Hyprland hides an idle pointer after at most 20 seconds");
    assert.equal(H.normalizeKey("pointerTheme", "a b"), "");
});

test("the settings ask for the installation's pointer until something else is picked", () => {
    const themes = [installed("Bibata-Modern-Classic", { left: "Bibata-Modern-Classic-Right", leftInstalled: true }),
        installed("WhiteSur-cursors"), { id: "Hackneyed", installed: false, left: "", leftInstalled: false }];
    assert.deepEqual(P.resolve(settings(), themes, FALLBACK), {
        chosen: "Bibata-Modern-Classic", entry: themes[0], missing: false, leftAvailable: true,
        theme: "Bibata-Modern-Classic", size: 24, explicit: false });
    const left = P.resolve(settings({ pointerLeftHanded: true, pointerSize: "larger" }), themes, FALLBACK);
    assert.deepEqual([left.theme, left.size, left.explicit], ["Bibata-Modern-Classic-Right", 48, true]);
    const whitesur = P.resolve(settings({ pointerTheme: "WhiteSur-cursors", pointerLeftHanded: true }), themes, FALLBACK);
    assert.deepEqual([whitesur.theme, whitesur.leftAvailable], ["WhiteSur-cursors", false],
        "a theme without a left-handed version keeps its own");
    // Not on this computer (yet, or any more): the installation's pointer, said so.
    const missing = P.resolve(settings({ pointerTheme: "Hackneyed" }), themes, FALLBACK);
    assert.deepEqual([missing.chosen, missing.missing, missing.explicit], ["Bibata-Modern-Classic", true, true]);
    assert.equal(P.resolve(settings({ pointerSize: "large" }), [], { theme: "Adwaita", size: 30 }).size, 32);
    assert.equal(P.resolve(settings(), [], { theme: "Adwaita", size: 30 }).size, 30, "a personal default size");
});

test("the list reply is checked before the gallery uses it", () => {
    assert.equal(P.listIn(null), null);
    assert.equal(P.listIn({ success: false, themes: [] }), null);
    const list = P.listIn({ success: true, downloads: true, default: { theme: "x y", size: 9000 }, themes: [
        { id: "Bibata-Modern-Classic", name: "Bibata Modern Classic", source: "bundled", installed: true,
            previews: { arrow: "/p/arrow.png", hand: "relative.png", evil: "/x" }, busyFrames: 500, sizes: [24, "48"] },
        { id: "Bibata-Modern-Classic" }, { id: "../x" }, { id: "Mine", source: "elsewhere" }] });
    assert.deepEqual(list.installationDefault, FALLBACK);
    assert.equal(list.downloads, true);
    assert.deepEqual(list.themes.map(t => t.id), ["Bibata-Modern-Classic", "Mine"]);
    assert.deepEqual(list.themes[0].previews, { arrow: "/p/arrow.png" });
    assert.equal(list.themes[0].busyFrames, 60);
    assert.deepEqual(list.themes[0].sizes, [24]);
    assert.equal(list.themes[1].source, "system");
    assert.equal(list.themes[0].package, null);
    assert.equal(P.listIn({ success: true, themes: [{ id: "WhiteSur-cursors", package: "whitesur-cursors" },
        { id: "Odd", package: "../x" }] }).themes.map(t => t.package).join(","), "whitesur-cursors,");
    assert.equal(P.sizeLimit({ sizes: [24, 30, 36, 48] }, 64), 48);
    assert.equal(P.sizeLimit({ sizes: [24, 48, 96] }, 64), 0);
    assert.equal(P.sizeLimit(null, 64), 0);
});

test("a download serving the pointer in use, under either name, is not removed", () => {
    const themes = P.listIn({ success: true, themes: [
        { id: "capitaine-cursors", package: "capitaine-cursors", installed: true },
        { id: "capitaine-cursors-white", package: "capitaine-cursors", installed: true },
        { id: "WhiteSur-cursors", package: "whitesur-cursors", installed: true },
        { id: "MyPointer", installed: true }, { id: "Other", installed: true }] }).themes;
    assert.ok(P.inUse(themes, "capitaine-cursors", "capitaine-cursors-white"), "one download, two themes");
    assert.ok(P.inUse(themes, "capitaine-cursors", "capitaine-cursors"));
    assert.ok(!P.inUse(themes, "capitaine-cursors", "WhiteSur-cursors"));
    assert.ok(!P.inUse(themes, "MyPointer", "Other"), "themes without a package share none");
    assert.ok(!P.inUse(themes, "Absent", "WhiteSur-cursors"));
});

test("every catalogue theme ships its previews, and the machine records its downloads", () => {
    const pointers = path.join(shellDir, "assets/pointers");
    const catalogue = JSON.parse(fs.readFileSync(path.join(pointers, "catalogue.json"), "utf8"));
    const index = JSON.parse(fs.readFileSync(path.join(pointers, "previews/index.json"), "utf8")).themes;
    const ids = catalogue.themes.map(t => t.id);
    assert.equal(new Set(ids).size, ids.length);
    assert.deepEqual(Object.keys(index).sort(), [...ids].sort());
    for (const theme of catalogue.themes) {
        assert.ok(P.name(theme.id) && (!theme.left || P.name(theme.left)), theme.id);
        assert.match(theme.package, /^[A-Za-z0-9][A-Za-z0-9._-]*$/, theme.id);
        assert.deepEqual(index[theme.id].shapes, P.SHAPES, theme.id);
        for (const shape of P.SHAPES)
            assert.ok(fs.statSync(path.join(pointers, "previews", theme.id, shape + ".png")).size > 0, theme.id + " " + shape);
    }
    assert.ok(catalogue.themes.some(t => t.id === "Bibata-Modern-Classic" && t.bundled), "the default is bundled");
    const desktop = fs.readFileSync(path.join(repo, "nix/modules/desktop.nix"), "utf8");
    assert.match(desktop, /builtins\.readFile \.\.\/\.\.\/desktop\/quickshell\/assets\/pointers\/catalogue\.json/);
    assert.match(desktop, /builtins\.unsafeDiscardStringContext path\.value/,
        "a download is recorded, never part of the system");
    assert.match(desktop, /environment\.systemPackages = \[ pkgs\.bibata-cursors pkgs\.adwaita-icon-theme \]/);
    assert.match(fs.readFileSync(path.join(repo, "scripts/check-prebuilt"), "utf8"), /cybexosPointerDownloads/);
});

test("Settings owns hiding; Pointer applies the choice and never the reverse", () => {
    const settingsQml = read("Common/Settings.qml");
    assert.match(settingsQml, /"pointerTheme", "pointerSize", "pointerLeftHanded", "pointerHideTyping", "pointerHideIdle"\]/);
    assert.match(settingsQml, /"hl\.config\(\{ cursor = \{ hide_on_key_press = "/);
    assert.match(settingsQml, /pointerHidingProc\.command = \["hyprctl", "eval", dispatchedPointerHiding\]/);
    assert.doesNotMatch(settingsQml, /\bPointer\.(?!qml\b)\w/, "Settings never binds to Pointer");
    const pointerQml = read("Common/Pointer.qml");
    assert.match(pointerQml, /root\.script, "apply", resolved\.theme,\s*String\(resolved\.size\)\]\.concat\(resolved\.explicit \? \["--explicit"\] : \[\]\)/);
    assert.match(pointerQml, /Settings\.set\("pointerTheme", id\)/);
    assert.match(read("shell.qml"), /void Pointer\.loaded;/, "the shell checks the pointer as it starts");
    const page = read("Settings/AppearancePage.qml");
    for (const key of ["pointerTheme", "pointerSize", "pointerLeftHanded", "pointerHideTyping", "pointerHideIdle"])
        assert.match(page, new RegExp(`settingKey: "${key}"`), key);
    const search = load("SettingsSearchData.js");
    for (const key of ["pointerTheme", "pointerSize", "pointerLeftHanded", "pointerHideTyping", "pointerHideIdle"])
        assert.ok(search.ROWS.some(row => row.key === key && row.page === "appearance"), key);
});

const lua = [process.env.CYBEXOS_TEST_LUA, "lua", "luajit", "lua5.4"]
    .find(name => name && spawnSync(name, ["-v"], { encoding: "utf8" }).status === 0);

function persistedCursor(t, settingsText) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cybexos-tests.pointer."));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    fs.copyFileSync(path.join(shellDir, "../hypr/looknfeel.lua"), path.join(root, "looknfeel.lua"));
    if (settingsText !== undefined) {
        fs.mkdirSync(path.join(root, ".config/cybexos"), { recursive: true });
        fs.writeFileSync(path.join(root, ".config/cybexos/shell.json"), settingsText);
    }
    const driver = `
local cursor
local noop = function() end
hl = { config = function(spec) if spec.cursor then cursor = spec.cursor end end, curve = noop, animation = noop,
  window_rule = noop, get_config = function() return nil end, get_monitors = function() return {} end,
  on = function() return { remove = noop } end,
  workspace_rule = function() return { set_enabled = noop } end,
  layer_rule = function() return { set_enabled = noop } end }
dofile(${JSON.stringify(path.join(root, "looknfeel.lua"))})
io.write(tostring(cursor.hide_on_key_press), " ", tostring(cursor.inactive_timeout), " ", tostring(cursor.no_hardware_cursors))
`;
    const result = spawnSync(lua, ["-e", driver], { encoding: "utf8", env: { ...process.env, HOME: root } });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout;
}

test("Hyprland starts with the stored pointer hiding", { skip: !lua && "no Lua interpreter" }, t => {
    assert.equal(persistedCursor(t), "false 0 false");
    assert.equal(persistedCursor(t, JSON.stringify(H.merge({ v: 31, pointerHideTyping: true, pointerHideIdle: 20 }), null, 2)),
        "true 20 false");
    assert.equal(persistedCursor(t, '{"pointerHideTyping": "true", "pointerHideIdle": 7}'), "false 0 false",
        "only the offered values count");
});
