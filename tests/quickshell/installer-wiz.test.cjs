// The installer draws Wiz from pictures scripts/export-wiz cuts out of the
// desktop's rig (installer/kiosk/ui/wiz.slint, src/wiz.rs). Its frame and
// motion constants must stay the rig's. installer/kiosk/README.md.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {shellDir} = require('./shell.cjs');
const root = path.resolve(shellDir, '../..');
const WizRig = require(path.join(shellDir, 'Common/WizRig.js'));
const slint = fs.readFileSync(path.join(root, 'installer/kiosk/ui/wiz.slint'), 'utf8');
const artDir = path.join(root, 'installer/kiosk/assets/wiz');

test('his frame is the rig\'s still box, his feet on its ground', () => {
    const [x, y, width, height] = WizRig.STILL_BOX;
    assert.match(slint, new RegExp(`STILL_BOX, \\[${x}, ${y}, ${width}, ${height}\\]`));
    assert.match(slint, new RegExp(`width: ${width}px;`));
    assert.match(slint, new RegExp(`height: root\\.width \\* ${height} / ${width};`));
    assert.match(slint, new RegExp(`unit: root\\.width / ${width};`));
    assert.match(slint, new RegExp(`x: ${-x} \\* root\\.unit;`));
    assert.match(slint, new RegExp(`y: ${-y} \\* root\\.unit;`));
    assert.match(slint, new RegExp(`feet: ${WizRig.LAYOUT.ground[1] - y} \\* root\\.unit;`));
});

test('runes circle and sparkles burst as the rig draws them', () => {
    const orbit = WizRig.LAYOUT.orbit;
    assert.match(slint, new RegExp(`root\\.t \\* ${orbit.rate}rad`));
    assert.equal(slint.match(new RegExp(`root\\.px\\(${orbit.rx} \\* cos\\(self\\.at\\)\\)`, 'g')).length, 2);
    assert.equal(slint.match(new RegExp(`root\\.px\\(${orbit.ry} \\* sin\\(self\\.at\\)`, 'g')).length, 2);
    const delays = WizRig.LAYOUT.sparks.map(spark => spark[2]).join(', ');
    assert.ok(slint.includes(`for delay[z] in [${delays}]`), delays);
});

test('every picture the installer asks for is exported', () => {
    const files = fs.readdirSync(artDir).filter(name => name.endsWith('.svg')).map(name => name.slice(0, -4));
    const asked = [...slint.matchAll(/name: (?:root\.look \+ )?"([a-z0-9-]+)"/g)].map(match => match[1]);
    assert.ok(asked.length >= 10, asked.join(' '));
    const looks = ['thinking', 'working', 'needs-input', 'happy', 'sorry'];
    for (const name of asked) {
        // "-body", "-eyes" and "-hat" follow the pose; the others name a pose's part.
        const wanted = name.startsWith('-') ? looks.map(look => look + name) : [name];
        for (const want of wanted)
            assert.ok(files.some(file => file.startsWith(want)), `${want} is not in installer/kiosk/assets/wiz`);
    }
    const rust = fs.readFileSync(path.join(root, 'installer/kiosk/src/wiz.rs'), 'utf8');
    for (const file of files)
        assert.ok(rust.includes(`"${file}"`), `src/wiz.rs does not embed ${file}`);
});
