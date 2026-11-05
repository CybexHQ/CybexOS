// Pure geometry for the three bar styles. Bar.qml and previews use the same
// style vocabulary; tests exercise the layer-shell reservation separately
// from a compositor.

var STYLES = ["hug", "floating", "attached"];

function styleIn(value) {
    return STYLES.indexOf(value) !== -1 ? value : "hug";
}

function floating(value) {
    return styleIn(value) === "floating";
}

function hug(value) {
    return styleIn(value) === "hug";
}

function edgeMargin(value, gap) {
    return floating(value) ? Math.max(0, Number(gap) || 0) : 0;
}

function outerRadius(value, radius) {
    return floating(value) ? Math.max(0, Number(radius) || 0) : 0;
}

function exclusiveZone(options) {
    options = options || {};
    if (options.autoHide || !options.exclusive)
        return 0;
    var height = Math.max(0, Number(options.height) || 0);
    return floating(options.style)
        ? edgeMargin(options.style, options.gap) + height - 2 : height;
}

function barY(options) {
    options = options || {};
    var margin = edgeMargin(options.style, options.gap);
    var height = Math.max(0, Number(options.height) || 0);
    return options.position === "bottom"
        ? Math.max(0, (Number(options.windowHeight) || 0) - margin - height)
        : margin;
}

function hideShift(options) {
    options = options || {};
    var distance = edgeMargin(options.style, options.gap)
        + Math.max(0, Number(options.height) || 0) + 12;
    return options.position === "bottom" ? distance : -distance;
}

function popoutAnchorDepth(style, gap, height) {
    return edgeMargin(style, gap) + Math.max(0, Number(height) || 0);
}

// How far a tooltip must move sideways to keep `margin` from both edges of
// the bar's window. `left` is where its caller placed it, in window
// coordinates. A tip wider than the window keeps its left margin.
function tooltipNudge(left, width, windowWidth, margin) {
    var gap = Math.max(0, Number(margin) || 0);
    var start = Number(left) || 0;
    var span = Math.max(0, Number(width) || 0);
    var room = Number(windowWidth) || 0;
    if (room <= 0)
        return 0;
    var high = room - gap - span;
    if (start > high)
        return Math.max(gap, high) - start;
    if (start < gap)
        return gap - start;
    return 0;
}

// ---- the media chip's share of the bar ---------------------------------
// The menubar's priority when room runs out (docs/shell-states.md): the right
// cluster outranks the clock, the clock the workspaces, and the workspaces
// the media chip, whose title goes before the chip itself.
// LayoutHelpers.fitBar already gives the media title up first and hides the
// chip first. fitMenubar wraps it with the two steps it does not know: the
// title shrinks to the room left before the centre group, at most
// `entry.shrinkable` of it, before it is given up; and the chip goes to More
// before the clock or anything in the right cluster loses its detail.
var MEDIA_GAP = 12;

function entryList(value) {
    return (Array.isArray(value) || value instanceof Array) ? value : [];
}

function sideLane(col) {
    return col === "left" || col === "right";
}

// What a fit took from the modules that outrank the media chip. A module the
// user set to always compact gave nothing up to the fit.
function protectedLoss(result, entries) {
    var lost = 0;
    entries.forEach(function(entry) {
        if (entry.id === "media" || entry.policy === "compact"
                || !(entry.id === "clock" || entry.col === "right"))
            return;
        if (result.compact.indexOf(entry.id) !== -1 || result.overflow.indexOf(entry.id) !== -1)
            lost++;
    });
    return lost;
}

function copyExtents(options) {
    return options.centerExtents ? {
        left: Math.max(0, Number(options.centerExtents.left) || 0),
        right: Math.max(0, Number(options.centerExtents.right) || 0)
    } : undefined;
}

// fitBar first; then, if that cost the clock or the right cluster something
// while the media chip stayed, the same fit with the chip in More from the
// start, kept only when it costs them less.
function priorityFit(fitBar, options) {
    var first = fitBar(options);
    var entries = entryList(options.entries);
    var media = entries.find(function(entry) { return entry.id === "media"; });
    if (!media || first.overflow.indexOf("media") !== -1)
        return first;
    var before = protectedLoss(first, entries);
    if (before === 0)
        return first;

    var source = options.widths || {};
    var widths = {
        left: Math.max(0, Number(source.left) || 0),
        center: Math.max(0, Number(source.center) || 0),
        right: Math.max(0, Number(source.right) || 0)
    };
    var extents = copyExtents(options);
    var chip = Math.max(0, Number(media.width) || 0);
    if (media.col in widths)
        widths[media.col] = Math.max(0, widths[media.col] - chip);
    if (media.col === "center" && extents) {
        var side = media.centerSide === "left" ? "left" : "right";
        extents[side] = Math.max(0, extents[side] - chip);
    }
    // The More button holding the chip is on screen from the start.
    widths.right += Math.max(0, Number(options.overflowWidth) || 0);
    var second = fitBar({
        width: options.width,
        sideMargin: options.sideMargin,
        gutter: options.gutter,
        widths: widths,
        centerExtents: extents,
        entries: entries.filter(function(entry) { return entry.id !== "media"; }),
        overflowWidth: 0
    });
    if (protectedLoss(second, entries) >= before)
        return first;
    second.overflow = ["media"].concat(second.overflow);
    return second;
}

// options: LayoutHelpers.fitBar's. The media entry may carry `shrinkable`,
// how much of its title can go before the title is given up. Returns
// fitBar's result plus `mediaCut`: how much of the title to withhold now.
function fitMenubar(fitBar, options, gap) {
    options = options || {};
    var space = gap === undefined ? MEDIA_GAP : Math.max(0, Number(gap) || 0);
    var entries = entryList(options.entries);
    var media = entries.find(function(entry) { return entry.id === "media"; }) || null;
    // Only a side lane has a measurable run up to the centre group; a media
    // chip in the centre keeps its configured width.
    var shrinkable = media && media.policy !== "compact" && sideLane(media.col)
        ? Math.max(0, Number(media.shrinkable) || 0) : 0;

    var fitted = options;
    if (shrinkable > 0) {
        var source = options.widths || {};
        var widths = {
            left: Math.max(0, Number(source.left) || 0),
            center: Math.max(0, Number(source.center) || 0),
            right: Math.max(0, Number(source.right) || 0)
        };
        widths[media.col] = Math.max(0, widths[media.col] - shrinkable);
        fitted = {
            width: options.width,
            sideMargin: options.sideMargin,
            gutter: options.gutter,
            widths: widths,
            centerExtents: copyExtents(options),
            entries: entries.map(function(entry) {
                if (entry !== media)
                    return entry;
                var shrunk = {};
                for (var key in entry)
                    shrunk[key] = entry[key];
                shrunk.width = Math.max(0, (Number(entry.width) || 0) - shrinkable);
                shrunk.saving = Math.max(0, (Number(entry.saving) || 0) - shrinkable);
                return shrunk;
            }),
            overflowWidth: options.overflowWidth
        };
    }

    var result = priorityFit(fitBar, fitted);
    result.mediaCut = 0;
    if (shrinkable > 0 && result.compact.indexOf("media") === -1
            && result.overflow.indexOf("media") === -1) {
        var available = Math.max(0, (Number(options.width) || 0)
            - 2 * (Number(options.sideMargin) || 0));
        var extents = result.centerExtents || { left: 0, right: 0 };
        var room = media.col === "left"
            ? result.centerX - result.widths.left - space
            : available - result.widths.right
                - (result.centerX + extents.left + extents.right) - space;
        result.mediaCut = Math.max(0, Math.ceil(shrinkable - Math.max(0, room)));
    }
    return result;
}

var exported = {
    STYLES: STYLES,
    MEDIA_GAP: MEDIA_GAP,
    styleIn: styleIn,
    floating: floating,
    hug: hug,
    edgeMargin: edgeMargin,
    outerRadius: outerRadius,
    exclusiveZone: exclusiveZone,
    barY: barY,
    hideShift: hideShift,
    popoutAnchorDepth: popoutAnchorDepth,
    tooltipNudge: tooltipNudge,
    priorityFit: priorityFit,
    fitMenubar: fitMenubar
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
