const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { shellDir, load } = require('./shell.cjs');
const W = load('WallpaperNames.js');

test('the user\'s own files keep their casing, with separators as spaces', () => {
    assert.equal(W.label('IMG_2034.JPG', false), 'IMG 2034');
    assert.equal(W.label('wallhaven-qroy2d.jpg', false), 'wallhaven qroy2d');
    assert.equal(W.label('.png', false), '.png', 'nothing left keeps the file name');
    const picker = fs.readFileSync(path.join(shellDir, 'Settings/WallpaperPicker.qml'), 'utf8');
    assert.match(picker, /label: WallpaperNames\.label\(Wallpaper\.basename\(path\)\)/);
    const welcome = fs.readFileSync(path.join(shellDir, 'Common/Welcome.qml'), 'utf8');
    assert.match(welcome, /WallpaperNames\.label\(Settings\.wall\)/);
    const finish = fs.readFileSync(path.join(shellDir, 'Welcome/FinishStep.qml'), 'utf8');
    assert.match(finish, /title: Welcome\.wallpaperName/);
    assert.doesNotMatch(finish, /Settings\.accent\]/, 'the summary shows a swatch, not a hex code');
});
