// Settings -> Appearance -> Pointer: what scripts/pointer.py lists, checked,
// and which pointer the settings ask for. Free of Qt APIs so
// pointer.test.cjs can run it under Node; that test also holds THEME and
// SIZES to SettingsHelpers' copies, which validate the stored settings.

var THEME = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/;
var SIZES = { large: 32, larger: 48, largest: 64 };
var PACKAGE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/;
var SOURCES = ["bundled", "download", "yours", "system"];
var SHAPES = ["arrow", "hand", "text", "busy", "resize", "forbidden"];
var FALLBACK_DEFAULT = { theme: "Bibata-Modern-Classic", size: 24 };

function name(value) {
    return typeof value === "string" && THEME.test(value) ? value : "";
}

function sizeIn(value, fallback) {
    return typeof value === "number" && isFinite(value) && value >= 16 && value <= 128
        ? Math.round(value) : fallback;
}

function previewsIn(value) {
    var out = {};
    if (!value || typeof value !== "object")
        return out;
    SHAPES.forEach(function(shape) {
        var path = value[shape];
        if (typeof path === "string" && path.charAt(0) === "/" && path.length < 4096)
            out[shape] = path;
    });
    return out;
}

// The `list` reply as the gallery uses it, or null when it is not one.
function listIn(reply) {
    if (!reply || typeof reply !== "object" || reply.success !== true
            || !(Array.isArray(reply.themes) || reply.themes instanceof Array))
        return null;
    var fallback = reply.default && typeof reply.default === "object" ? reply.default : {};
    var themes = [];
    var seen = {};
    reply.themes.forEach(function(theme) {
        if (!theme || typeof theme !== "object" || name(theme.id) === "" || seen[theme.id])
            return;
        seen[theme.id] = true;
        themes.push({
            id: theme.id,
            name: typeof theme.name === "string" && theme.name !== "" ? theme.name.slice(0, 64) : theme.id,
            package: typeof theme.package === "string" && PACKAGE.test(theme.package) ? theme.package : null,
            source: SOURCES.indexOf(theme.source) !== -1 ? theme.source : "system",
            installed: theme.installed === true,
            downloadable: theme.downloadable === true,
            removable: theme.removable === true,
            left: name(theme.left),
            leftInstalled: theme.leftInstalled === true,
            previews: previewsIn(theme.previews),
            busyFrames: Math.max(1, Math.min(60, Math.round(Number(theme.busyFrames) || 1))),
            busyDuration: Math.max(0, Math.min(10000, Math.round(Number(theme.busyDuration) || 0))),
            sizes: (Array.isArray(theme.sizes) || theme.sizes instanceof Array)
                ? theme.sizes.filter(function(size) { return typeof size === "number" && size > 0; }) : []
        });
    });
    return {
        themes: themes,
        downloads: reply.downloads === true,
        installationDefault: {
            theme: name(fallback.theme) || FALLBACK_DEFAULT.theme,
            size: sizeIn(fallback.size, FALLBACK_DEFAULT.size)
        }
    };
}

function find(themes, id) {
    for (var i = 0; i < themes.length; i++) {
        if (themes[i].id === id)
            return themes[i];
    }
    return null;
}

// The pointer the settings ask for on this computer:
//   chosen     the theme picked, or the installation's when none is (or the
//              picked one is no longer installed: `missing`)
//   theme      what Hyprland is given: `chosen`, or its left-handed version
//   size       pixels before the display's scale
//   explicit   whether anything differs from the installation's own, which
//              decides whether the next login is told about it
function resolve(settings, themes, installationDefault) {
    var fallback = installationDefault || FALLBACK_DEFAULT;
    var picked = name(settings.pointerTheme);
    var pickedEntry = picked === "" ? null : find(themes, picked);
    var missing = picked !== "" && !(pickedEntry && pickedEntry.installed);
    var chosen = picked !== "" && !missing ? picked : fallback.theme;
    var entry = find(themes, chosen);
    var leftAvailable = !!(entry && entry.left && entry.leftInstalled);
    var size = SIZES[settings.pointerSize] || fallback.size;
    return {
        chosen: chosen,
        entry: entry,
        missing: missing,
        leftAvailable: leftAvailable,
        theme: settings.pointerLeftHanded === true && leftAvailable ? entry.left : chosen,
        size: size,
        explicit: picked !== "" || settings.pointerSize !== "default" || settings.pointerLeftHanded === true
    };
}

// Whether removing `id`'s download would take away the pointer in use: it
// is the chosen theme, or comes in the same package (Capitaine and
// Capitaine White are one download).
function inUse(themes, chosen, id) {
    var theme = find(themes, id);
    var current = find(themes, chosen);
    return !!theme && !!current && (theme.id === current.id
        || theme.package !== null && theme.package === current.package);
}

// The largest size a theme draws, when the chosen size is beyond it.
function sizeLimit(entry, size) {
    if (!entry || !entry.sizes || entry.sizes.length === 0)
        return 0;
    var largest = Math.max.apply(null, entry.sizes);
    return size > largest ? largest : 0;
}

var exported = {
    THEME: THEME,
    SIZES: SIZES,
    SHAPES: SHAPES,
    FALLBACK_DEFAULT: FALLBACK_DEFAULT,
    name: name,
    listIn: listIn,
    find: find,
    resolve: resolve,
    inUse: inUse,
    sizeLimit: sizeLimit
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
