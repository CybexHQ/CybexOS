// The monogram tile an app without an icon shows (Common/Monogram.js):
// its first letter on a colour derived from its name, readable in both themes.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load, shellDir } = require("./shell.cjs");

const M = load("Monogram.js");

test("the letter is the name's first letter or digit", () => {
    assert.equal(M.letter("GIMP"), "G");
    assert.equal(M.letter("darktable"), "D");
    assert.equal(M.letter("  (beta) tool"), "B", "leading punctuation and spaces are skipped");
    assert.equal(M.letter("7-Zip"), "7");
    assert.equal(M.letter("😀 Smile"), "😀", "an astral character stays whole");
    assert.equal(M.letter(""), "");
    assert.equal(M.letter(null), "");
    assert.equal(M.letter("—"), "");
});

test("the same name always gets the same colour, case and spacing aside", () => {
    assert.equal(M.hue("Betterbird"), M.hue("betterbird"));
    assert.equal(M.hue(" Betterbird "), M.hue("Betterbird"));
    assert.deepEqual(M.tile("Betterbird", true), M.tile("Betterbird", true));
    assert.ok(M.HUES.includes(M.hue("anything")));
    const hues = new Set(["Files", "kitty", "Betterbird", "hello", "Text Editor", "Document Viewer", "imv", "mpv"]
        .map(name => M.hue(name)));
    assert.ok(hues.size >= 4, "different names spread over the palette");
});

test("every tile keeps 4.5:1 between letter and fill in both themes", () => {
    for (const hue of M.HUES) {
        // A name for each hue: search a few until one lands on it.
        let name = "";
        for (let i = 0; i < 2000 && name === ""; i++)
            if (M.hue("app " + i) === hue) name = "app " + i;
        assert.notEqual(name, "", `a name for hue ${hue}`);
        for (const dark of [true, false]) {
            const tile = M.tile(name, dark);
            assert.match(tile.fill, /^#[0-9a-f]{6}$/);
            assert.match(tile.ink, /^#[0-9a-f]{6}$/);
            assert.ok(M.contrast(tile.fill, tile.ink) >= 4.5,
                `${dark ? "dark" : "light"} hue ${hue}: ${tile.ink} on ${tile.fill} is ${M.contrast(tile.fill, tile.ink).toFixed(2)}:1`);
        }
    }
});

test("Software draws the monogram where an app has no icon", () => {
    const icon = fs.readFileSync(path.join(shellDir, "Software/AppIcon.qml"), "utf8");
    assert.match(icon, /import "\.\.\/Common\/Monogram\.js" as Monogram/);
    assert.match(icon, /Monogram\.tile\(root\.name, Theme\.dark\)/);
    assert.match(icon, /property string name: app && app\.name \? app\.name : ""/);
});
