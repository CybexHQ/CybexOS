// The Control Center button's icon (Settings -> Bar & Control Center ->
// Control Center -> Button icon), which the fish prompt shows too.
//
// A setting value is one of:
//   "cybex"              the Cybex OS mark: its SVG on the bar, and in the
//                        prompt the one glyph of Cybex OS Symbols
//                        (scripts/build-symbols-font.py)
//   "os"                 the operating system's logo: NixOS on the bar; the
//                        prompt keeps its per-distribution icon, so a
//                        Distrobox still shows its own
//   "nf:<name>:<code>"   a Nerd Font icon by name, with its codepoint so
//                        neither the bar nor the prompt needs the catalogue
//                        (assets/nerd-icons/glyphs.json, scripts/update-nerd-icons)
//
// Keep this file free of Qt APIs so Node tests can load it.

var DEFAULT = "cybex";
// Cybex OS Symbols' only glyph, in Supplementary Private Use Area-B.
var CYBEX_CODEPOINT = 0x1000CB;
// nf-linux-nixos.
var NIXOS_CODE = "f313";
// What the prompt file holds when the prompt keeps its own OS icon.
var PROMPT_OS = "os";

var CUSTOM = /^nf:([a-z0-9]+(?:-[a-z0-9_]+)+):([0-9a-f]{4,5})$/;

// Icon sets by name prefix, in the order search ranks them.
var SETS = [
    { id: "md", label: "Material Design" },
    { id: "fa", label: "Font Awesome" },
    { id: "linux", label: "Linux logos" },
    { id: "dev", label: "Devicons" },
    { id: "oct", label: "Octicons" },
    { id: "cod", label: "Codicons" },
    { id: "fae", label: "Font Awesome Extension" },
    { id: "weather", label: "Weather Icons" },
    { id: "seti", label: "Seti UI" },
    { id: "custom", label: "Nerd Fonts" }
];

// Shown before anything is typed: a varied first screen of the catalogue.
var FEATURED = [
    "md-rocket_launch", "md-console", "fa-terminal", "md-ghost", "md-cat", "md-dog",
    "md-paw", "md-fire", "md-lightning_bolt", "md-star", "md-heart", "md-code_braces",
    "md-chip", "md-leaf", "md-weather_night", "md-white_balance_sunny", "md-skull",
    "md-crown", "md-diamond_stone", "md-atom", "md-coffee", "md-orbit", "md-alien",
    "md-robot", "md-snowflake", "md-infinity", "md-bug", "md-hexagon", "md-cube_outline",
    "md-feather", "md-wizard_hat", "md-pirate", "md-sword", "md-shield", "md-flask",
    "md-music", "md-gamepad_variant", "md-cog", "md-penguin", "md-duck", "md-owl",
    "md-butterfly", "md-tree", "md-mushroom", "md-anchor", "md-compass", "md-earth",
    "md-lightbulb", "linux-tux", "linux-nixos", "linux-debian", "linux-fedora", "md-apple",
    "md-ubuntu"
];

function privateUse(code) {
    return (code >= 0xE000 && code <= 0xF8FF) || (code >= 0xF0000 && code <= 0xFFFFD);
}

// The value, or the default for anything a settings file could hold that
// is not one of the three forms above.
function normalize(value) {
    if (value === "cybex" || value === "os")
        return value;
    if (typeof value !== "string" || value.length > 80)
        return DEFAULT;
    var match = CUSTOM.exec(value);
    return match && privateUse(parseInt(match[2], 16)) ? value : DEFAULT;
}

function custom(name, code) {
    return normalize("nf:" + name + ":" + code);
}

function parse(value) {
    var safe = normalize(value);
    var match = CUSTOM.exec(safe);
    return match ? { mode: "custom", name: match[1], code: match[2] }
        : { mode: safe, name: "", code: safe === "os" ? NIXOS_CODE : "" };
}

function glyph(code) {
    var point = parseInt(code, 16);
    return isNaN(point) ? "" : String.fromCodePoint(point);
}

// The text glyph the bar draws, or "" for the Cybex OS mark, which the bar
// draws from its SVG.
function barGlyph(value) {
    var icon = parse(value);
    return icon.mode === "cybex" ? "" : glyph(icon.code);
}

// The prompt file's one line: the glyph to show, or PROMPT_OS when the prompt
// keeps the operating system's own icon (the "os" choice, or the prompt
// switch off).
function promptText(value, usePrompt) {
    var icon = parse(value);
    if (!usePrompt || icon.mode === "os")
        return PROMPT_OS;
    return icon.mode === "cybex" ? String.fromCodePoint(CYBEX_CODEPOINT) : glyph(icon.code);
}

function setOf(name) {
    var prefix = String(name).split("-")[0];
    for (var i = 0; i < SETS.length; i++) {
        if (SETS[i].id === prefix)
            return SETS[i];
    }
    return null;
}

// "md-rocket_launch" -> "Rocket launch".
function title(name) {
    var words = String(name).split("-").slice(1).join(" ").replace(/_/g, " ").trim();
    return words === "" ? String(name) : words.charAt(0).toUpperCase() + words.slice(1);
}

function setLabel(name) {
    var set = setOf(name);
    return set ? set.label : "";
}

// Up to `limit` catalogue entries for `query`: every word must appear in the
// name. Whole-word matches rank first, then names that start with a word,
// then by icon set and length, so "cat" finds md-cat before md-category.
// With no query, the featured icons that exist in this catalogue.
function search(glyphs, query, limit) {
    var max = limit > 0 ? limit : 60;
    var map = glyphs || {};
    var words = String(query || "").toLowerCase().split(/[\s_-]+/).filter(function(word) {
        return word !== "";
    });
    if (words.length === 0) {
        return FEATURED.filter(function(name) {
            return Object.prototype.hasOwnProperty.call(map, name);
        }).slice(0, max).map(function(name) {
            return { name: name, code: map[name] };
        });
    }
    var found = [];
    Object.keys(map).forEach(function(name) {
        var set = setOf(name);
        if (!set)
            return;
        var parts = name.split("-").slice(1).join("_").split("_");
        var score = 0;
        for (var i = 0; i < words.length; i++) {
            var word = words[i];
            if (name.indexOf(word) === -1)
                return;
            if (parts.indexOf(word) !== -1)
                score += 4;
            else if (parts.some(function(part) { return part.indexOf(word) === 0; }))
                score += 2;
            else if (set.id === word)
                score += 1;
        }
        found.push({ name: name, code: map[name], score: score, rank: SETS.indexOf(set) });
    });
    found.sort(function(a, b) {
        return b.score - a.score || a.rank - b.rank || a.name.length - b.name.length
            || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    });
    return found.slice(0, max).map(function(entry) {
        return { name: entry.name, code: entry.code };
    });
}

var exported = {
    DEFAULT: DEFAULT,
    CYBEX_CODEPOINT: CYBEX_CODEPOINT,
    NIXOS_CODE: NIXOS_CODE,
    PROMPT_OS: PROMPT_OS,
    SETS: SETS,
    FEATURED: FEATURED,
    normalize: normalize,
    custom: custom,
    parse: parse,
    glyph: glyph,
    barGlyph: barGlyph,
    promptText: promptText,
    title: title,
    setLabel: setLabel,
    search: search
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
