// The tile an app or source shows when it has no icon: its first letter or
// digit on a colour derived from its name, so two icon-less apps look
// different and the same app always looks the same. Pure, so Software, the
// launcher and the tests share it.
//
//   tile(name, dark) → { letter, fill, ink }   colours as "#rrggbb"
//   letter(name)     → "G" for "GIMP", "" when the name has nothing to show
//   hue(name)        → one of HUES, stable for a name
//
// The fill is a deep tone under light ink in the dark theme and a pale tint
// under a deep ink of the same hue in the light one; every pair keeps at
// least 4.5:1 (tests/quickshell/monogram.test.cjs).

// Twelve hues spread round the wheel, skipping the muddy yellow-greens.
var HUES = [4, 24, 38, 140, 168, 188, 204, 222, 248, 272, 296, 326];

var DARK_FILL = { s: 0.42, l: 0.30 };
var DARK_INK = "#f7f5f0";
var LIGHT_FILL = { s: 0.55, l: 0.78 };
var LIGHT_INK = { s: 0.6, l: 0.2 };

function clean(name) {
    return String(name === undefined || name === null ? "" : name).replace(/\s+/g, " ").trim();
}

// The first letter or digit, upper-cased; astral characters (emoji,
// historic scripts) stay whole. Leading punctuation and symbols are skipped.
function letter(name) {
    var text = clean(name);
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i);
        var ch = text.charAt(i);
        if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length)
            return text.slice(i, i + 2);
        if (/[\s!-\/:-@\[-`{-~]/.test(ch) || (code >= 0x2000 && code <= 0x206f))
            continue;
        var upper = ch.toUpperCase();
        return upper.length === 1 ? upper : ch;
    }
    return "";
}

// FNV-1a over the case-folded name: the same name, the same colour.
function hash(name) {
    var text = clean(name).toLowerCase();
    var h = 0x811c9dc5;
    for (var i = 0; i < text.length; i++) {
        h ^= text.charCodeAt(i);
        h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h >>> 0;
}

function hue(name) {
    return HUES[hash(name) % HUES.length];
}

function hex(rgb) {
    return "#" + rgb.map(function(part) {
        var value = Math.max(0, Math.min(255, Math.round(part * 255)));
        return (value < 16 ? "0" : "") + value.toString(16);
    }).join("");
}

function hsl(h, s, l) {
    var c = (1 - Math.abs(2 * l - 1)) * s;
    var x = c * (1 - Math.abs((h / 60) % 2 - 1));
    var m = l - c / 2;
    var rgb = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
        : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return hex(rgb.map(function(part) { return part + m; }));
}

function luminance(value) {
    var match = /^#([0-9a-f]{6})$/i.exec(String(value || ""));
    if (!match)
        return 0;
    var n = parseInt(match[1], 16);
    var channels = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(function(part) {
        var c = part / 255;
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(a, b) {
    var x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

function tile(name, dark) {
    var h = hue(name);
    return dark
        ? { letter: letter(name), fill: hsl(h, DARK_FILL.s, DARK_FILL.l), ink: DARK_INK }
        : { letter: letter(name), fill: hsl(h, LIGHT_FILL.s, LIGHT_FILL.l), ink: hsl(h, LIGHT_INK.s, LIGHT_INK.l) };
}

if (typeof module !== "undefined") module.exports = {
    HUES: HUES, letter: letter, hash: hash, hue: hue, hsl: hsl, luminance: luminance, contrast: contrast, tile: tile
};
