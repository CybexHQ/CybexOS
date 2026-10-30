// Wiz, the assistant's character (docs/assistant.md): the rig in
// Common/WizRig.js, the layers scripts/export-wiz builds from it, and the
// rules that keep Assistant/Wiz.qml cheap on a full-output overlay.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const vm = require("node:vm");
const { shellDir, load } = require("./shell.cjs");

const W = load("WizRig.js");
const root = path.resolve(shellDir, "../..");
const layersDir = path.join(shellDir, "assets/wiz");
const read = relative => fs.readFileSync(path.join(shellDir, relative), "utf8");
const wiz = read("Assistant/Wiz.qml");
// The code alone: the comments explain what it avoids, by name.
const code = wiz.replace(/^\s*\/\/.*$/gm, "");

test("every state has a complete pose", () => {
    const keys = Object.keys(W.POSES.idle).sort();
    assert.deepEqual(Object.keys(W.POSES).sort(), [...W.STATES].sort());
    for (const state of W.STATES) {
        assert.deepEqual(Object.keys(W.POSES[state]).sort(), keys, state);
        for (const key of keys)
            assert.ok(Number.isFinite(W.POSES[state][key]), `${state}.${key}`);
    }
    // Wiz.qml reads every key; one it ignored would be a silent no-op.
    for (const key of keys)
        assert.match(wiz, new RegExp(`stance\\.${key}\\b`), key);
});

test("the committed layers are exactly what the rig exports", () => {
    const names = Object.keys(W.LAYERS);
    assert.deepEqual(fs.readdirSync(layersDir).filter(name => name.endsWith(".svg")).sort(),
        names.map(name => `${name}.svg`).sort());
    for (const name of names)
        assert.equal(fs.readFileSync(path.join(layersDir, `${name}.svg`), "utf8"), W.layerSVG(name),
            `assets/wiz/${name}.svg is stale; run scripts/export-wiz`);
    const check = spawnSync(path.join(root, "scripts/export-wiz"), ["--check"], { encoding: "utf8" });
    assert.equal(check.status, 0, check.stderr);
});

test("each layer holds its drawing, strokes and glow included", () => {
    for (const [name, layer] of Object.entries(W.LAYERS)) {
        const ops = W.layerOps(name);
        assert.ok(ops.length > 0, `${name} draws nothing`);
        const at = layer.at || [0, 0];
        const [x0, y0] = [at[0] + layer.box[0], at[1] + layer.box[1]];
        const [x1, y1] = [x0 + layer.box[2], y0 + layer.box[3]];
        for (const op of ops) {
            const points = [];
            if (op.k === "radial") {
                points.push([op.cx - op.r, op.cy - op.r * op.sy, 0], [op.cx + op.r, op.cy + op.r * op.sy, 0]);
            } else {
                // Control points bound a curve; a stroke and three blur deviations bound its paint.
                const margin = (op.stroke ? (op.lw || 1) / 2 : 0) + (op.glow ? 3 * op.glow.s : 0);
                for (const segment of op.d)
                    for (let i = 1; i + 1 < segment.length; i += 2)
                        points.push([segment[i], segment[i + 1], margin]);
            }
            for (const [x, y, margin] of points)
                assert.ok(x - margin >= x0 && x + margin <= x1 && y - margin >= y0 && y + margin <= y1,
                    `${name} spills out of its box at (${x}, ${y})`);
        }
    }
});

test("the rig loads before QML has its globals", () => {
    // Qt 6.11 can run an imported script's top level before Math exists (a
    // component's first instance in a Repeater); the rig must not need it then.
    const context = { Math: undefined };
    vm.runInNewContext(fs.readFileSync(path.join(shellDir, "Common/WizRig.js"), "utf8") + "\nthis.loaded = WizRig;", context);
    assert.deepEqual(Object.keys(context.loaded.LAYERS), Object.keys(W.LAYERS));
});

test("Wiz.qml draws every exported layer and no other", () => {
    const named = new Set([...code.matchAll(/(?:name|art): "([a-z-]+)"\s*$/gm)].map(match => match[1]));
    if (/art: "rune" \+ rune\.index/.test(code) && /art: "rune" \+ frontRune\.index/.test(code))
        for (let i = 0; i < 4; i++)
            named.add(`rune${i}`);
    assert.deepEqual([...named].sort(), Object.keys(W.LAYERS).sort());
    assert.match(wiz, /source: Qt\.resolvedUrl\("\.\.\/assets\/wiz\/" \+ name \+ "\.svg"\)/);
    // Each layer is drawn once at the device size it is shown at.
    assert.match(wiz, /sourceSize: Qt\.size\(Math\.ceil\(box\[2\] \* root\.pixels\), Math\.ceil\(box\[3\] \* root\.pixels\)\)/);
    assert.match(wiz, /readonly property real pixels: unit \* Math\.max\(1, Math\.ceil\(Screen\.devicePixelRatio\)\)/);
});

test("nothing is painted or scripted per frame", () => {
    for (const costly of [/\bCanvas\b/, /\bFrameAnimation\b/, /requestPaint/, /layer\.enabled/,
        /\bShaderEffect\b/, /\bMultiEffect\b/, /\bAnimatedSprite\b/, /\bParticleSystem\b/,
        /ScriptAction/, /PathAnimation/])
        assert.doesNotMatch(code, costly);
    assert.doesNotMatch(code, /WizRig\.create|\.ops\(|toSVG|layerSVG/, "the rig only supplies tables at runtime");
    // A repeating Timer may wake a still Wiz for a blink, a glance, a wobble,
    // a pulse or a bead of sweat; each must stop with the rest of him. The
    // others fire once: the end of a drag's motion and of a dizzy spell.
    const timers = [...code.matchAll(/Timer \{([\s\S]*?)\n    \}/g)].map(match => match[1]);
    assert.equal(timers.length, 7);
    for (const body of timers) {
        if (/repeat: true/.test(body))
            assert.match(body, /running: root\.live && /, body);
        else
            assert.match(body, /id: (?:calm|recover)\b/, body);
    }
});

test("loops run only while live and busy, and Wiz holds still otherwise", () => {
    assert.match(wiz, /readonly property bool live: animated && visible/);
    assert.match(wiz, /readonly property bool looping: live && \(pose === "thinking" \|\| pose === "working"\s*\|\| \(pose === "listening" && recording\)\)/);
    // Each infinite loop is gated on a live-derived condition, or is one of the
    // two loops resume() starts only while looping.
    const loops = [...wiz.matchAll(/(?:SequentialAnimation|RotationAnimator|ParallelAnimation)(?: on \w+)? \{\s*(?:id: (\w+)\s*)?(?:running: ([^\n]+)\s*)?loops: Animation\.Infinite/g)];
    assert.equal(loops.length, (code.match(/Animation\.Infinite/g) || []).length,
        "every infinite loop is in the shape this contract reads");
    for (const [source, id, running] of loops) {
        if (id === "breathing" || id === "swaying")
            continue;
        assert.ok(running, `an infinite loop without a running condition: ${source}`);
        assert.match(running, /root\.live|(?:orbiter|mote|spell)\.running/, source);
    }
    // An orbiter runs as its user says: runes while thinking, stars while dizzy.
    const orbiters = [...code.matchAll(/delegate: Orbiter \{([\s\S]*?)\n\s*\}/g)].map(match => match[1]);
    assert.equal(orbiters.length, 4);
    for (const body of orbiters)
        assert.match(body, /running: root\.live && root\.(?:runes > 0\.02|dizziness > 0\.01)/, body);
    assert.match(wiz, /readonly property bool running: root\.live && root\.spell > 0\.02/);
    assert.match(wiz, /readonly property bool running: root\.live && visible/);
    assert.match(wiz, /function resume\(\) \{\s*if \(!looping\)\s*return;/);
    assert.match(wiz, /onLoopingChanged: settle\(\)/);
    assert.match(wiz, /Component\.onCompleted: resume\(\)/, "a Wiz created mid-turn starts his loops");
    // A waiting question pulses three times, then only as a reminder.
    assert.match(wiz, /interval: root\.pulses < 3 \? 1111 : 8000/);
    // Pose changes snap when Wiz may not move.
    const behaviors = [...wiz.matchAll(/Behavior on \w+ \{\s*enabled: ([^;\n]+)/g)].map(match => match[1]);
    assert.ok(behaviors.length >= 21);
    for (const enabled of behaviors)
        assert.equal(enabled.trim(), "root.animated");
});

test("a drag's velocity follows the pointer, restarting after a pause", () => {
    const C = W.CARRY;
    let s = W.follow(null, 100, 100, 1000);
    assert.equal(s.vx, 0, "a grab starts from rest");
    for (let t = 1016; t <= 1600; t += 16)
        s = W.follow(s, 100 + (t - 1000) * 1.2, 100, t);
    assert.ok(Math.abs(s.vx - 1200) < 1 && s.vy === 0, `a steady 1200 px/s drag reads ${s.vx}`);
    const close = W.follow(s, s.x + 50, s.y, s.at + C.minStep - 1);
    assert.equal(close, s, "samples closer than minStep wait for the next one");
    const later = W.follow(s, s.x + 50, s.y, s.at + C.stale + 1);
    assert.equal(later.vx, 0, "after a pause the pointer starts from rest");
    assert.ok(W.normal(C.speed) > 0.7 && W.normal(10 * C.speed) < 1 && W.normal(-C.speed) < -0.7);
});

test("quick reversals make him dizzy, slow or old ones do not", () => {
    const C = W.CARRY;
    function wave(speed, halfPeriod, duration, start) {
        let s = null, x = 0;
        for (let t = start; t <= start + duration; t += 16) {
            x += (Math.floor((t - start) / halfPeriod) % 2 ? -1 : 1) * speed * 0.016;
            s = W.follow(s, x, 0, t);
        }
        return s;
    }
    assert.ok(W.shaken(wave(1500, 130, 900, 0)), "three fast back-and-forths");
    assert.ok(!W.shaken(wave(400, 130, 900, 0)), "too slow to count");
    assert.ok(!W.shaken(wave(1500, 600, 900, 0)), "one reversal is a change of mind, not a shake");
    let s = wave(1500, 130, 900, 0);
    s = W.follow(s, s.x, s.y, s.at + 100);
    s = W.follow(s, s.x, s.y, s.at + C.shakeWindow + 100);
    assert.ok(!W.shaken(s), "reversals older than the window are forgotten");
});

test("he leans into every direction, diagonals included", () => {
    const right = W.carry(0.8, 0), left = W.carry(-0.8, 0), up = W.carry(0, -0.8), down = W.carry(0, 0.8);
    // Pulled right: swings so his bottom trails, hat and tip blown back, eyes
    // ahead, feet trailing; left is the mirror image.
    assert.ok(right.swing > 0 && right.hatX < 0 && right.tip < 0 && right.eyeX > 0 && right.feet > 0);
    for (const key of ["swing", "hatX", "hatTilt", "tip", "eyeX", "feet"])
        assert.equal(left[key], -right[key], key);
    assert.equal(right.hatY, 0);
    // Lifted: the hat is shoved down over his eyes. Dropping: it floats off
    // above him and tumbles, and he looks up at it.
    assert.ok(up.hatY > 0 && up.eyeY < 0 && up.swing === 0);
    assert.ok(down.hatY < 0 && down.hatTilt < 0 && down.eyeY < 0);
    // A diagonal is one motion: stretched along it, the hat thrown back and up.
    const diagonal = W.carry(0.6, 0.6);
    assert.equal(Math.round(diagonal.angle), 45);
    assert.equal(Math.round(W.carry(0.6, -0.6).angle), -45);
    assert.ok(diagonal.hatX < 0 && diagonal.hatY < 0 && diagonal.eyeX > 0 && diagonal.smear > right.smear * 0.99);
    assert.ok(W.carry(0.3, 0).smear < right.smear, "the stretch grows with speed");
    for (const value of Object.values(W.carry(0, 0)))
        assert.equal(Math.abs(value), 0);
});

test("carried, he reacts only while live and always comes back to rest", () => {
    assert.match(code, /readonly property bool carried: pose === "carried"/);
    assert.match(code, /onDragPointChanged: \{\s*if \(carried && live\)\s*follow\(\);/);
    assert.match(code, /if \(carried\) \{\s*tracker = null;\s*recover\.stop\(\);\s*if \(live\)\s*startle\(\);/);
    assert.match(code, /\} else \{\s*impact = Math\.min\(1, 0\.35 \+ 0\.65 \* Math\.sqrt\(ux \* ux \+ uy \* uy\)\);[\s\S]{0,80}ux = 0;\s*uy = 0;\s*if \(live\)\s*land\(\);\s*if \(dizzy\)\s*recover\.restart\(\);/);
    // Every one-shot ends where it began.
    for (const id of ["startling", "landing"]) {
        const start = code.indexOf(`id: ${id}`);
        const block = code.slice(start, code.indexOf("\n    }\n", start));
        const last = block.slice(block.lastIndexOf("ParallelAnimation {"));
        for (const property of ["thudX", "thudY"])
            assert.match(last, new RegExp(`property: "${property}"; to: 1;`), `${id} ${property}`);
    }
    assert.match(code, /property: "squint"; to: 1;/);
    assert.match(code, /property: "crook"; to: 0; duration: 160/);
    assert.match(code, /YAnimator \{ target: hatNod; from: -root\.hop; to: 0;/);
    assert.match(code, /onStopped: breath\.x = 0/);
    // Reduced motion or an idle session ends a drag's motion at once.
    const off = code.slice(code.indexOf("onLiveChanged: {"));
    for (const step of ["startling.complete()", "landing.complete()", "hopping.complete()", "crooking.complete()", "dizzy = false"])
        assert.ok(off.includes(step), step);
});

test("Wiz is the only character and holds still with reduced motion or nobody there", () => {
    assert.match(read("Assistant/Wiz.qml"), /property bool animated: !Theme\.reducedMotion && !Activity\.idle/);
    assert.match(read("Assistant/qmldir"), /^Wiz Wiz\.qml$/m);
    assert.doesNotMatch(read("Assistant/qmldir"), /AssistantCharacter/);

    const window = read("AssistantWindow.qml");
    assert.match(window, /readonly property real size: Assistant\.characterSize/);
    assert.match(window, /Wiz \{\n\s*id: character/);
    assert.match(window, /pose: Assistant\.pose/);
    assert.match(window, /recording: Assistant\.listening/);
    // Once per pointer move, both coordinates at once; Wiz swings himself.
    assert.match(window, /root\.dragY = [^\n]+\n\s*root\.dragPoint = Qt\.point\(root\.dragX, root\.dragY\);/);
    assert.match(window, /grab: Qt\.point\(root\.pressWindow\.x - root\.pressBubble\.x, root\.pressWindow\.y - root\.pressBubble\.y\)/);
    assert.doesNotMatch(window, /rotation: root\.dragging/);
    assert.match(read("shell.qml"), /size: Assistant\.characterSize/);
    assert.match(read("Common/Assistant.qml"), /readonly property real characterSize: Theme\.scaled\(88\)/);
});
