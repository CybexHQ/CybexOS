// The Ghostty, Alacritty and foot system theme targets (scripts/theme_ghostty.py,
// theme_alacritty.py, theme_foot.py) and their vendor fragments in
// desktop/defaults, which fall back to the default dark render.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
    darkTokens, lightTokens, renderTarget, runDriver, scratch, stubBin,
} = require("./system-theme.cjs");

const repoRoot = path.resolve(__dirname, "../..");
const vendor = name => fs.readFileSync(path.join(repoRoot, "desktop/defaults", name), "utf8");
const settingLines = text => text.split("\n").filter(line => line && !line.startsWith("#"));
const HEX = /^#[0-9a-f]{6}$/;

function render(name, tokens) {
    const files = renderTarget(name, tokens);
    assert.equal(Object.keys(files).length, 1);
    return Object.values(files)[0];
}

test("every terminal renders the same palette as kitty", () => {
    for (const tokens of [darkTokens(), lightTokens()]) {
        const kitty = new Map(settingLines(render("kitty", tokens)).map(line => line.split(" ")));
        const ghostty = settingLines(render("ghostty", tokens)).map(line => line.split(" = "));
        const palette = ghostty.filter(([key]) => key === "palette").map(([, value]) => value);
        assert.deepEqual(palette, Array.from({ length: 16 }, (_, i) => `${i}=${kitty.get("color" + i)}`));
        const ghosttyKeys = new Map(ghostty.filter(([key]) => key !== "palette"));
        assert.equal(ghosttyKeys.get("background"), tokens.colors.background);
        assert.equal(ghosttyKeys.get("cursor-color"), kitty.get("cursor"));
        assert.equal(ghosttyKeys.get("selection-background"), tokens.colors.accentContainer);
        assert.equal(ghosttyKeys.get("font-size"), kitty.get("font_size"));

        const foot = render("foot", tokens);
        const [dark, light] = foot.split("[colors-light]\n");
        assert.match(foot, /^\[main\]\nfont=JetBrainsMono Nerd Font:size=\d+\.\d\n/m);
        assert.equal(settingLines(dark.split("[colors-dark]\n")[1]).join("\n"), settingLines(light).join("\n"),
            "both of foot's palettes are the current one");
        assert.ok(settingLines(light).includes("background=" + tokens.colors.background.slice(1)));
        assert.ok(settingLines(light).includes("regular1=" + kitty.get("color1").slice(1)));
        assert.ok(settingLines(light).includes("bright7=" + kitty.get("color15").slice(1)));

        const alacritty = render("alacritty", tokens);
        assert.match(alacritty, new RegExp(`\\[colors\\.primary\\]\\nforeground = "${tokens.colors.text}"\\nbackground = "${tokens.colors.background}"`));
        assert.match(alacritty, new RegExp(`\\[colors\\.bright\\][^[]*white = "${kitty.get("color15")}"`));
        for (const match of alacritty.matchAll(/= "([^"]+)"/g))
            assert.match(match[1], HEX);
    }
});

test("each vendor fragment's fallback is the default dark render", () => {
    const dark = darkTokens();
    const ghosttyTheme = settingLines(render("ghostty", dark));
    const ghosttyVendor = settingLines(vendor("ghostty.conf"));
    assert.deepEqual(ghosttyVendor.filter(line => ghosttyTheme.includes(line)), ghosttyTheme);
    assert.doesNotMatch(vendor("ghostty.conf"), /^config-file/m,
        "the seeded config, not the fragment, names the theme so personal.conf loads last");

    assert.equal(settingLines(vendor("alacritty-colors.toml")).join("\n"), settingLines(render("alacritty", dark)).join("\n"));
    const alacritty = vendor("alacritty.toml");
    assert.match(alacritty, /^import = \["alacritty-colors\.toml", "~\/\.local\/state\/cybexos\/theme\/alacritty\.toml"\]$/m);
    assert.doesNotMatch(alacritty, /^\[colors|^size = /m, "the importing file is applied last, so it sets no theme");

    const foot = vendor("foot.ini");
    const fallback = foot.split("[colors-dark]\n")[1].split("\n[colors-light]")[0];
    const rendered = render("foot", dark).split("[colors-dark]\n")[1].split("\n[colors-light]")[0];
    assert.deepEqual(settingLines(fallback).filter(line => !line.startsWith("alpha=")), settingLines(rendered));
    assert.ok(foot.trimEnd().endsWith("[main]\ninclude=~/.local/state/cybexos/theme/foot.ini"), "included last, so it wins");
});

test("Ghostty reloads with SIGUSR2 when its file changes; the others need no signal", t => {
    const state = scratch(t);
    const stubs = stubBin(t, { pkill: "exit 1" });
    const ghostty = () => stubs.calls().filter(call => call.includes("ghostty"));
    const apply = tokens => {
        const result = runDriver(state, ["apply"], JSON.stringify(tokens) + "\n", { bin: stubs.bin });
        assert.equal(result.status, 0, result.stderr);
        for (const name of ["ghostty", "alacritty", "foot"])
            assert.equal(result.report.targets[name].error, null, name);
        return result.report.targets;
    };
    assert.equal(apply(darkTokens()).ghostty.changed, true);
    assert.deepEqual(ghostty(), ["pkill --signal USR2 --uid " + process.getuid()
        + " --full --exact ([^ ]*/)?\\.?ghostty(-wrapped)?( [^+].*)?"]);
    for (const name of ["ghostty.conf", "alacritty.toml", "foot.ini"])
        assert.ok(fs.existsSync(path.join(state, name)), name);
    assert.equal(apply(darkTokens()).ghostty.changed, false);
    assert.equal(ghostty().length, 1, "unchanged file: no reload");
    assert.equal(stubs.calls().filter(call => /alacritty|foot/.test(call)).length, 0);
});
