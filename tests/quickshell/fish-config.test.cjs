const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoDir = path.resolve(__dirname, "../..");
const config = path.join(repoDir, "desktop/defaults/fish-config.fish");
const hasFish = spawnSync("fish", ["--version"]).status === 0;

// conf.d/50-cybexos.fish is sourced by every fish, including `fish -c` from
// scripts and tools. Only the environment belongs there; the prompt, hooks
// and aliases cost six processes per shell and serve only a terminal.
test("the fish config keeps prompt setup out of non-interactive shells", () => {
    const source = fs.readFileSync(config, "utf8");
    const gate = source.indexOf("if status is-interactive");
    assert.ok(gate > 0, "interactive setup must sit behind `status is-interactive`");
    for (const needle of ["fish_add_path", "set -gx EDITOR", "set -gx SCCACHE_DIR"])
        assert.ok(source.indexOf(needle) < gate, `${needle} must stay available to fish -c`);
    for (const needle of ["oh-my-posh init", "zoxide init", "fzf --fish", "direnv hook",
        "POSH_OS_ICON", "alias update="])
        assert.ok(source.indexOf(needle) > gate, `${needle} is interactive-only`);
    assert.doesNotMatch(source, /\bsh -c/, "os-release is read with builtins, once");
});

test("sourcing the fish config spawns nothing unless the shell is interactive",
    { skip: !hasFish && "fish is not installed" }, () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "fish-config-"));
    try {
        const bin = path.join(tmp, "bin");
        const calls = path.join(tmp, "calls.log");
        fs.mkdirSync(bin);
        fs.writeFileSync(calls, "");
        for (const name of ["sh", "oh-my-posh", "zoxide", "fzf", "direnv"])
            fs.writeFileSync(path.join(bin, name),
                `#!${require("./shell.cjs").executable("bash")}\nprintf '%s\\n' "${name}" >>"$FISH_CONFIG_CALLS"\n`,
                { mode: 0o755 });
        const run = interactive => spawnSync("fish",
            ["--no-config", ...(interactive ? ["-i"] : []), "-c", `source ${config}`], {
                encoding: "utf8",
                input: "",
                env: {
                    ...process.env,
                    // fish_add_path writes universal variables under these.
                    HOME: tmp,
                    XDG_CONFIG_HOME: path.join(tmp, "config"),
                    XDG_DATA_HOME: path.join(tmp, "data"),
                    XDG_CACHE_HOME: path.join(tmp, "cache"),
                    PATH: `${bin}:${process.env.PATH}`,
                    FISH_CONFIG_CALLS: calls,
                },
            });

        const quiet = run(false);
        assert.equal(quiet.status, 0, quiet.stderr);
        assert.equal(fs.readFileSync(calls, "utf8"), "", "fish -c ran prompt setup");

        const terminal = run(true);
        assert.equal(terminal.status, 0, terminal.stderr);
        assert.deepEqual(fs.readFileSync(calls, "utf8").trim().split("\n").sort(),
            ["direnv", "fzf", "oh-my-posh", "zoxide"]);
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
});

// Wiz in kitty (docs/branding.md): the default fastfetch config's logo is
// $CYBEXOS_FASTFETCH_LOGO or the braille logo, and only the interactive
// `fastfetch` function sets it, to the picture the desktop package renders.
test("fastfetch draws Wiz only through the variable its default config names", () => {
    const source = fs.readFileSync(config, "utf8");
    const defaults = fs.readFileSync(path.join(repoDir, "desktop/defaults/fastfetch.jsonc"), "utf8");
    const packaging = fs.readFileSync(path.join(repoDir, "nix/packages/desktop.nix"), "utf8");
    const logo = defaults.split("\n").find(line => line.startsWith('  "logo":'));
    assert.match(logo, /"source": "\$\{CYBEXOS_FASTFETCH_LOGO:-@CYBEXOS_FASTFETCH@\}"/);
    // An explicit "file" type would print the picture as text.
    assert.doesNotMatch(logo, /"type":/);
    const start = source.indexOf("function fastfetch ");
    assert.ok(start > source.indexOf("if status is-interactive"), "the function is interactive-only");
    const body = source.slice(start, source.indexOf("\n    end\n", start));
    assert.match(body, /set -l wiz \/run\/current-system\/sw\/share\/cybexos\/wiz\/terminal\/idle\.png\n/);
    assert.match(packaging, /assets\/wiz\/idle\.svg \\\n.* \$out\/share\/cybexos\/wiz\/terminal\/idle\.png\n/);
    // Where fastfetch cannot draw the picture it prints the file as text:
    // only a plain call, to a terminal, from a shell kitty itself started.
    for (const gate of ["test (count $argv) -eq 0", "isatty stdout", "not set -q NO_COLOR",
        "contains -- $terminal kitty .kitty-wrapped", "'*${CYBEXOS_FASTFETCH_LOGO:-*' <$config"])
        assert.ok(body.includes(gate), gate);
    assert.match(body, /CYBEXOS_FASTFETCH_LOGO=\$wiz command fastfetch --logo-height 9\n/);
    assert.match(body, /else\n +command fastfetch \$argv\n/);
});

test("outside kitty, fastfetch runs as typed", { skip: !hasFish && "fish is not installed" }, () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "fish-fastfetch-"));
    try {
        const bin = path.join(tmp, "bin");
        fs.mkdirSync(bin);
        fs.writeFileSync(path.join(bin, "fastfetch"),
            `#!${require("./shell.cjs").executable("bash")}\nprintf 'logo=%s args=%s\\n' "\${CYBEXOS_FASTFETCH_LOGO-unset}" "$*"\n`,
            { mode: 0o755 });
        const result = spawnSync("fish", ["--no-config", "-i", "-c",
            `source ${config}; fastfetch --logo arch; fastfetch`], {
            encoding: "utf8",
            input: "",
            env: {
                ...process.env,
                HOME: tmp,
                XDG_CONFIG_HOME: path.join(tmp, "config"),
                XDG_DATA_HOME: path.join(tmp, "data"),
                XDG_CACHE_HOME: path.join(tmp, "cache"),
                PATH: `${bin}:${process.env.PATH}`,
            },
        });
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(result.stdout.trim().split("\n").filter(line => line.startsWith("logo=")),
            ["logo=unset args=--logo arch", "logo=unset args="]);
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
});
