// Screenshots are taken by Omasnap (nix/packages/omasnap.nix): the
// `screenshot` command chooses its mode, and Omasnap's Omarchy-style
// notifications reach the desktop through nix/packages/omasnap-notify.sh.
// Each run gets a private PATH of stubs, so nothing touches the real screen
// or notification server.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { executable } = require("./shell.cjs");

const root = path.resolve(__dirname, "../..");
const bash = executable("bash");

function fixture(t) {
    const base = fs.mkdtempSync(path.join(os.tmpdir(), "qs-omasnap-test-"));
    const bin = path.join(base, "bin");
    const log = path.join(base, "log");
    fs.mkdirSync(bin);
    fs.mkdirSync(log);
    t.after(() => fs.rmSync(base, { recursive: true, force: true }));
    const stub = (name, body) =>
        fs.writeFileSync(path.join(bin, name), `#!${bash}\n${body}\n`, { mode: 0o755 });
    // Every stub records its name and arguments, one argument per line.
    const recorder = name => stub(name, `{ echo "== ${name}"; printf '%s\\n' "$@"; } >> "$TEST_LOG/calls"`);
    // notify-send prints the action the person chose: $CHOICE.
    stub("notify-send", `{ echo "== notify-send"; printf '%s\\n' "$@"; } >> "$TEST_LOG/calls"
printf '%s' "\${CHOICE:-}"`);
    const notifier = path.join(bin, "omarchy-notification-send");
    fs.writeFileSync(notifier, fs.readFileSync(path.join(root, "nix/packages/omasnap-notify.sh"), "utf8")
        .replace("@bash@", bash).replaceAll("@notify-send@", path.join(bin, "notify-send")), { mode: 0o755 });
    return {
        recorder,
        run(program, args, extra = {}) {
            return spawnSync(program, args, {
                env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, TEST_LOG: log, ...extra },
                encoding: "utf8", timeout: 10_000
            });
        },
        notify(args, choice = "") {
            return this.run(notifier, args, { CHOICE: choice });
        },
        // [[name, ...arguments], ...] in the order they ran.
        calls() {
            const file = path.join(log, "calls");
            if (!fs.existsSync(file))
                return [];
            return fs.readFileSync(file, "utf8").split("== ").filter(Boolean)
                .map(entry => entry.replace(/\n$/, "").split("\n"));
        }
    };
}

test("the screenshot command opens Omasnap in the mode its shortcut names", t => {
    const cases = [
        [[], ["smart"]],
        [["region"], ["smart"]],
        [["window"], ["windows"]],
        [["fullscreen"], ["fullscreen", "--copy", "--save"]],
        [["scroll"], ["scroll"]],
        [["region", "--editor", "overlay"], ["smart", "--editor", "overlay"]],
    ];
    for (const [args, expected] of cases) {
        const f = fixture(t);
        f.recorder("omasnap");
        const result = f.run(path.join(root, "assets/scripts/screenshot"), args);
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(f.calls(), [["omasnap", ...expected]], `screenshot ${args.join(" ")}`);
    }
});

test("an unknown screenshot mode is refused without opening Omasnap", t => {
    const f = fixture(t);
    f.recorder("omasnap");
    const result = f.run(path.join(root, "assets/scripts/screenshot"), ["scroll-stop"]);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /Usage: screenshot/);
    assert.deepEqual(f.calls(), []);
});

test("a plain notice is sent without waiting for an action", t => {
    const f = fixture(t);
    const result = f.notify(["-g", "", "--app-name", "omasnap", "-t", "4500",
        "Screenshot copied to clipboard"]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls(), [["notify-send", "--app-name=Screenshot", "--urgency=low", "--expire-time=4500",
        "--", "Screenshot copied to clipboard", ""]]);
});

test("a saved capture shows its picture, and a click edits it", t => {
    const f = fixture(t);
    f.recorder("omasnap");
    const result = f.notify(["-g", "", "--app-name", "omasnap", "-t", "4500", "Screenshot saved and copied",
        "Click to edit", "--image", "/home/me/Pictures/Screenshots/shot one.png",
        "--exec", "omasnap", "file:///home/me/Pictures/Screenshots/shot%20one.png"], "default");
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls(), [
        ["notify-send", "--app-name=Screenshot", "--urgency=low", "--expire-time=4500",
            "--icon=/home/me/Pictures/Screenshots/shot one.png", "--action=default=Edit",
            "--", "Screenshot saved and copied", "Click to edit"],
        ["omasnap", "file:///home/me/Pictures/Screenshots/shot%20one.png"],
    ]);
});

test("a dismissed notice runs nothing", t => {
    const f = fixture(t);
    f.recorder("omasnap");
    const result = f.notify(["--app-name", "omasnap", "Screenshot saved", "Click to edit",
        "--image", "/tmp/shot.png", "--exec", "omasnap", "file:///tmp/shot.png"], "");
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls().map(call => call[0]), ["notify-send"]);
});

test("action buttons run their own command with the shared arguments", t => {
    const toast = ["--app-name", "omasnap", "-t", "7000", "Screenshot saved", "1,280 × 800 · 96 kB",
        "--image", "/tmp/shot.png", "--action", "Open", "xdg-open", "--action", "Edit", "omasnap",
        "--recent", "c0ffee", "--with", "/tmp/shot.png"];
    for (const [choice, expected] of [["0", ["xdg-open", "/tmp/shot.png"]],
                                      ["1", ["omasnap", "--recent", "c0ffee", "/tmp/shot.png"]],
                                      // A click on the card is the first action.
                                      ["default", ["xdg-open", "/tmp/shot.png"]]]) {
        const f = fixture(t);
        f.recorder("omasnap");
        f.recorder("xdg-open");
        const result = f.notify(toast, choice);
        assert.equal(result.status, 0, result.stderr);
        const calls = f.calls();
        assert.deepEqual(calls[0], ["notify-send", "--app-name=Screenshot", "--urgency=low", "--expire-time=7000",
            "--icon=/tmp/shot.png", "--action=default=Open", "--action=0=Open", "--action=1=Edit",
            "--", "Screenshot saved", "1,280 × 800 · 96 kB"]);
        assert.deepEqual(calls.slice(1), [expected], `choice ${choice}`);
    }
});

test("text that looks like an option stays text", t => {
    const f = fixture(t);
    const result = f.notify(["--app-name", "omasnap", "--hint=string:x-evil:1", "-50% smaller"]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls(), [["notify-send", "--app-name=Screenshot", "--urgency=low", "--expire-time=-1",
        "--", "--hint=string:x-evil:1", "-50% smaller"]]);
});

test("a notice without a headline is refused", t => {
    const f = fixture(t);
    const result = f.notify(["--app-name", "omasnap"]);
    assert.equal(result.status, 1);
    assert.deepEqual(f.calls(), []);
});
