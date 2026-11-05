// The 2026-11 state system (docs/shell-states.md): the accent marks laid on
// a state — a rail's selected edge, a selected tile's border, the keyboard
// focus ring — and the boundary of an off switch must stay findable (3:1,
// WCAG 1.4.11) in the default palette in both modes and in every bundled
// theme pack, against the least favourable backdrop copy sits on.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir, load } = require("./shell.cjs");

const H = load("SettingsHelpers.js");
const theme = fs.readFileSync(path.join(shellDir, "Common", "Theme.qml"), "utf8");

function hex(name) {
    const match = theme.match(new RegExp(`readonly property color ${name}:\\s*"(#[0-9a-fA-F]{6})"`));
    assert.ok(match, `Theme.${name} must be a hex literal`);
    return match[1];
}

const chipHoverAlpha = Number(theme.match(/readonly property real chipHoverAlpha:\s*([\d.]+)/)[1]);
const defaultAccent = load("SettingsHelpers.js").defaults
    ? load("SettingsHelpers.js").defaults().accent : "#60a5fa";

// The default palette's references, as Theme.copyReferenceBg builds them.
const cases = [
    { name: "default dark", dark: true, accent: defaultAccent, reference: hex("darkPopBg"),
      surfaces: [hex("darkBackground"), hex("darkPopBg")], textMid: hex("darkTextMid") },
    { name: "default light", dark: false, accent: defaultAccent,
      reference: H.mixHex(hex("lightBackground"), "#18162c", chipHoverAlpha),
      surfaces: [hex("lightBackground"), hex("lightPopBg")], textMid: hex("lightTextMid") },
];

const themesDir = path.join(shellDir, "themes");
for (const id of fs.readdirSync(themesDir)) {
    const pack = JSON.parse(fs.readFileSync(path.join(themesDir, id, "theme.json"), "utf8"));
    const palette = Object.assign({}, pack.palette, { mode: pack.mode });
    const reference = H.themeReference(palette, chipHoverAlpha);
    const surfaces = H.themeSurfaces ? H.themeSurfaces(palette) : null;
    cases.push({
        name: id, dark: pack.mode !== "light", accent: pack.accent, reference,
        surfaces: surfaces ? [surfaces.background, surfaces.surface] : [],
        textMid: H.themeTextPalette(reference, palette).textMid,
    });
}

test("every bundled theme pack is covered", () => {
    assert.ok(cases.length >= 2 + 8, `expected the default palette and at least 8 packs, got ${cases.length}`);
});

for (const c of cases) {
    test(`${c.name}: selected marks and the focus ring clear 3:1`, () => {
        const tokens = H.stateTokens(c.accent, c.reference, c.dark);
        for (const backdrop of [c.reference, ...c.surfaces]) {
            assert.ok(H.contrastRatio(tokens.selectedMark, backdrop) >= 3,
                `${c.name}: selected mark ${tokens.selectedMark} on ${backdrop}`);
            assert.ok(H.contrastRatio(tokens.focusRing, backdrop) >= 3,
                `${c.name}: focus ring ${tokens.focusRing} on ${backdrop}`);
        }
    });

    test(`${c.name}: an off switch's boundary clears 3:1`, () => {
        assert.ok(H.contrastRatio(c.textMid, c.reference) >= 3,
            `${c.name}: switch border ${c.textMid} on ${c.reference}`);
    });

    test(`${c.name}: the selected fill is an accent tint, not the hover chip`, () => {
        const tokens = H.stateTokens(c.accent, c.reference, c.dark);
        assert.ok(tokens.selectedAlpha > 0.1 && tokens.selectedAlpha < 0.3);
    });
}

test("Theme keeps hover and selection apart and draws focus through one helper", () => {
    assert.match(theme, /readonly property color selectedFill:/);
    assert.doesNotMatch(theme, /readonly property color selectedFill:\s*chip\b/);
    assert.match(theme, /function focusWidth\(focused\)/);
    assert.match(theme, /Common\.FocusModality\.keyboard/);
});
