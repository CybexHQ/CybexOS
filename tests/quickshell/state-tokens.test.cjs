// The 2026-11 state system (docs/shell-states.md): the accent marks laid on
// a state — a rail's selected edge, a selected tile's border, the keyboard
// focus ring — and the boundary of an off switch must stay findable (3:1,
// WCAG 1.4.11) in the default palette in both modes and in every bundled
// theme pack, against the least favourable backdrop copy sits on. Secondary
// copy holds 4.5:1 on every window and card surface there, and disabled
// content stays readable at about 3:1.
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

const real = name => Number(theme.match(new RegExp(`readonly property real ${name}:\\s*([\\d.]+)`))[1]);
const chipHoverAlpha = real("chipHoverAlpha");
const chipAlpha = real("chipAlpha");
const tileAlpha = real("tileAlpha");
const defaultAccent = H.defaults().accent;
const LADDER = ["textMid", "textLow", "textDim", "textFaint", "icon"];

// The cards a panel carries at rest: Theme.chip / cardFill and Theme.tile.
// Dark mode lays them as white, light mode as the palette's ink.
function cardsOn(surfaces, dark, ink) {
    const alphas = dark ? [0.08, H.DARK_CARD_ALPHA] : [chipAlpha, tileAlpha];
    return surfaces.flatMap(surface =>
        alphas.map(alpha => H.mixHex(surface, dark ? "#ffffff" : ink, alpha)));
}

function fixedLadder(mode) {
    const out = {};
    for (const step of ["TextMid", "TextLow", "TextDim", "TextFaint", "Icon", "TextDisabled"])
        out[step[0].toLowerCase() + step.slice(1)] = hex(mode + step);
    return out;
}

// The default palette's references, as Theme.copyReferenceBg builds them.
test("Theme's dark reference is a resting card on the raised panel", () => {
    assert.match(theme, /readonly property real darkCardAlpha: SettingsHelpers\.DARK_CARD_ALPHA/);
    assert.match(theme, /SettingsHelpers\.mixHex\(popBg\.toString\(\), "#ffffff", darkCardAlpha\)/);
    assert.match(theme, /readonly property color tile: dark[\s\S]*?Qt\.rgba\(1, 1, 1, darkCardAlpha\)/);
    assert.match(theme, /themeReference\(Settings\.themePalette, chipHoverAlpha, darkCardAlpha\)/);
});

const darkPanels = [hex("darkBackground"), hex("darkPopBg")];
const lightPanels = [hex("lightBackground"), hex("lightPopBg")];
const cases = [
    { name: "default dark", dark: true, accent: defaultAccent,
      reference: H.mixHex(hex("darkPopBg"), "#ffffff", H.DARK_CARD_ALPHA),
      surfaces: [...darkPanels, hex("darkMenuBg"), ...cardsOn(darkPanels, true)],
      ladder: fixedLadder("dark"), textMid: hex("darkTextMid") },
    { name: "default light", dark: false, accent: defaultAccent,
      reference: H.mixHex(hex("lightBackground"), "#18162c", chipHoverAlpha),
      surfaces: [...lightPanels, hex("lightMenuBg"), ...cardsOn(lightPanels, false, "#18162c")],
      ladder: fixedLadder("light"), textMid: hex("lightTextMid") },
];

const themesDir = path.join(shellDir, "themes");
for (const id of fs.readdirSync(themesDir)) {
    const pack = JSON.parse(fs.readFileSync(path.join(themesDir, id, "theme.json"), "utf8"));
    const palette = Object.assign({}, pack.palette, { mode: pack.mode });
    const reference = H.themeReference(palette, chipHoverAlpha, H.DARK_CARD_ALPHA);
    const s = H.themeSurfaces(palette);
    const dark = pack.mode !== "light";
    const ladder = H.themeTextPalette(reference, palette);
    cases.push({
        name: id, dark, accent: pack.accent, reference,
        surfaces: [s.background, s.surface, s.surfaceRaised,
            ...cardsOn([s.background, s.surface], dark, s.ink)],
        ladder, textMid: ladder.textMid,
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

    test(`${c.name}: secondary copy clears 4.5:1 on every window and card surface`, () => {
        for (const backdrop of [c.reference, ...c.surfaces])
            for (const step of LADDER)
                assert.ok(H.contrastRatio(c.ladder[step], backdrop) >= 4.5,
                    `${c.name}: ${step} ${c.ladder[step]} on ${backdrop} is `
                    + H.contrastRatio(c.ladder[step], backdrop).toFixed(2) + ":1");
    });

    test(`${c.name}: disabled content is dimmed but still about 3:1`, () => {
        const disabled = c.ladder.textDisabled;
        const onReference = H.contrastRatio(disabled, c.reference);
        assert.ok(onReference >= 3 && onReference < 3.6,
            `${c.name}: textDisabled ${disabled} is ${onReference.toFixed(2)}:1 on the reference`);
        for (const backdrop of c.surfaces)
            assert.ok(H.contrastRatio(disabled, backdrop) >= 3,
                `${c.name}: textDisabled ${disabled} on ${backdrop}`);
        assert.ok(onReference < H.contrastRatio(c.ladder.textFaint, c.reference),
            `${c.name}: disabled must read quieter than the faintest copy`);
    });

    test(`${c.name}: the selected fill is an accent tint, not the hover chip`, () => {
        const tokens = H.stateTokens(c.accent, c.reference, c.dark);
        assert.ok(tokens.selectedAlpha > 0.1 && tokens.selectedAlpha < 0.3);
    });
}

test("Theme draws disabled content through one token, on the bar too", () => {
    assert.match(theme, /readonly property color textDisabled: textPalette \? textPalette\.textDisabled/);
    assert.match(theme, /readonly property color barTextDisabled: barPalette\.textDisabled/);
    for (const bar of ["#1a1917", "#eae9ef", "#ffffff", "#000000", "#5d6b8a"]) {
        const palette = H.barPalette(bar);
        const ratio = H.contrastRatio(palette.textDisabled, bar);
        assert.ok(ratio >= 3 && ratio < 3.6, `${bar}: bar disabled ink at ${ratio.toFixed(2)}:1`);
    }
});

test("Theme keeps hover and selection apart and draws focus through one helper", () => {
    assert.match(theme, /readonly property color selectedFill:/);
    assert.doesNotMatch(theme, /readonly property color selectedFill:\s*chip\b/);
    assert.match(theme, /function focusWidth\(focused\)/);
    assert.match(theme, /Common\.FocusModality\.keyboard/);
});
