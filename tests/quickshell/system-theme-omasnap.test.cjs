// The Omasnap system theme target (scripts/theme_omasnap.py): the screenshot
// overlay's controls take the shell's colours from a folder of their own,
// the one the Omasnap package reads (nix/packages/omasnap.nix).
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { darkTokens, lightTokens, renderTarget, runDriver, scratch } = require("./system-theme.cjs");

const repoRoot = path.resolve(__dirname, "../..");

// Omasnap's own reading of the file (src/chrome-theme.cpp readValues): plain
// assignments, with a [section] prefixing the keys under it.
function values(text) {
    const result = {};
    let section = "";
    for (const line of text.split("\n").map(raw => raw.trim())) {
        const header = line.match(/^\[([\w.-]+)\]$/);
        if (header) {
            section = header[1];
            continue;
        }
        const pair = line.match(/^([\w-]+)\s*=\s*"([^"\\]*)"$/);
        if (pair)
            result[section ? `${section}.${pair[1]}` : pair[1]] = pair[2];
    }
    return result;
}

test("Omasnap's controls take the shell's panel, text and accent colours", () => {
    for (const tokens of [darkTokens(), lightTokens()]) {
        const files = renderTarget("omasnap", tokens);
        assert.deepEqual(Object.keys(files), ["omasnap/colors.toml"]);
        assert.deepEqual(values(files["omasnap/colors.toml"]), {
            background: tokens.colors.background,
            foreground: tokens.colors.text,
            light_foreground: tokens.colors.textMuted,
            accent: tokens.colors.accent,
            orange: tokens.colors.amber,
            "popups.background": tokens.colors.surface,
            "popups.text": tokens.colors.text,
        });
    }
});

test("the theme is written where the Omasnap package looks for it", t => {
    const state = scratch(t);
    const result = runDriver(state, ["apply"], JSON.stringify(darkTokens()) + "\n");
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.report.targets.omasnap, { changed: true, error: null });
    const file = path.join(state, "omasnap", "colors.toml");
    assert.equal(values(fs.readFileSync(file, "utf8")).accent, darkTokens().colors.accent);
    assert.equal(fs.statSync(file).mode & 0o777, 0o644);
    assert.deepEqual(fs.readdirSync(path.dirname(file)), ["colors.toml"], "no temporary file is left beside it");
    assert.equal(runDriver(state, ["apply"], JSON.stringify(darkTokens()) + "\n").report.targets.omasnap.changed, false);

    const recipe = fs.readFileSync(path.join(repoRoot, "nix/packages/omasnap.nix"), "utf8");
    assert.match(recipe, /--replace-fail '"\.local\/state\/omarchy\/current\/theme"' '"\.local\/state\/cybexos\/theme\/omasnap"'/,
        "Omasnap reads ~/.local/state/cybexos/theme/omasnap, the folder theme-apply.py writes");
});
