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

var exported = {
    STYLES: STYLES,
    styleIn: styleIn,
    floating: floating,
    hug: hug,
    edgeMargin: edgeMargin,
    outerRadius: outerRadius,
    exclusiveZone: exclusiveZone,
    barY: barY,
    hideShift: hideShift,
    popoutAnchorDepth: popoutAnchorDepth,
    tooltipNudge: tooltipNudge
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
