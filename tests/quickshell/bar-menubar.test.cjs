// The menubar refinements of the 2026-11 UI review (docs/shell-states.md):
// full-height pointer targets, the media chip's share of the bar and the
// overflow priority, the dots-style workspace pill, and the two-tone Cybex X.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load, shellDir } = require("./shell.cjs");

const L = load("LayoutHelpers.js");
const G = load("BarGeometry.js");
const read = rel => fs.readFileSync(path.join(shellDir, rel), "utf8");

// A bar with launcher, workspaces and the media chip on the left, the clock
// in the centre, and volume, notifications and Control Center on the right.
function bar(width, title, options = {}) {
    const chip = 4 + 20 + 8 + title + 8 + 24 + 3;
    const left = 32 + 124 + chip;
    return {
        width, sideMargin: 6, gutter: 8, overflowWidth: 32,
        widths: { left, center: 150, right: options.right ?? 200 },
        centerExtents: { left: 75, right: 75 },
        entries: [
            { id: "ws", col: "left", width: 120, saving: 0, policy: "auto" },
            { id: "media", col: options.mediaCol ?? "left", width: chip, currentWidth: chip,
                saving: title + 8, shrinkable: Math.max(0, title - 64),
                policy: options.mediaPolicy ?? "auto" },
            { id: "clock", col: "center", width: 110, saving: 40, policy: "auto", centerSide: "right" },
            { id: "vol", col: "right", width: 50, saving: 20, policy: "auto" },
            { id: "notifications", col: "right", width: 30, saving: 0, policy: "auto" },
            { id: "control", col: "right", width: 28, saving: 0, policy: "auto" }
        ]
    };
}

test("a roomy bar draws the media title at the user's maximum", () => {
    const result = G.fitMenubar(L.fitBar, bar(1920, 180), 12);
    assert.deepEqual(result.compact, []);
    assert.deepEqual(result.overflow, []);
    assert.equal(result.mediaCut, 0);
});

test("the media title shrinks to end the chip 12 px short of the centre group", () => {
    for (const width of [900, 800]) {
        const options = bar(width, 180);
        const result = G.fitMenubar(L.fitBar, options, 12);
        assert.deepEqual(result.compact, [], `${width}: shrinking comes before dropping the title`);
        assert.ok(result.mediaCut > 0 && result.mediaCut <= 180 - 64, `${width}: ${result.mediaCut}`);
        // The drawn left section, with the title cut, ends the gap short of
        // the centre group.
        const drawnLeft = options.widths.left - result.mediaCut;
        assert.ok(result.centerX - drawnLeft >= 12, `${width}: ${result.centerX - drawnLeft}`);
        assert.ok(result.centerX - drawnLeft < 13, `${width}: the title takes the room it has`);
    }
});

test("the title is given up only once even its minimum does not fit", () => {
    const result = G.fitMenubar(L.fitBar, bar(700, 180), 12);
    assert.deepEqual(result.compact, ["media"]);
    assert.equal(result.mediaCut, 0);
});

test("the media chip goes to More before the clock or the right cluster lose detail", () => {
    const options = bar(600, 180);
    const plain = L.fitBar(options);
    assert.ok(plain.compact.includes("clock") && !plain.overflow.includes("media"),
        "fitBar alone compacts the clock while the media chip stays");
    const result = G.fitMenubar(L.fitBar, options, 12);
    assert.ok(result.overflow.includes("media"));
    assert.ok(!result.compact.includes("vol"), "the right cluster keeps its value");
    for (const kept of ["ws", "clock", "vol", "notifications", "control"])
        assert.equal(result.overflow.includes(kept), false, kept);
});

test("the priority pass is kept only when it costs the protected modules less", () => {
    const fit = opts => ({ compact: ["clock"], overflow: [], widths: opts.widths,
        centerExtents: { left: 0, right: 0 }, centerX: 0, centerOffset: 0, fits: true });
    const result = G.priorityFit(fit, bar(600, 180));
    assert.deepEqual(result.overflow, [], "no gain, no hidden chip");
    const always = bar(600, 180);
    always.entries.find(entry => entry.id === "clock").policy = "compact";
    assert.deepEqual(G.priorityFit(fit, always).overflow, [],
        "a module the user always compacts is not a loss to win back");
});

test("a centre or always-compact media chip keeps its configured width", () => {
    assert.equal(G.fitMenubar(L.fitBar, bar(800, 180, { mediaCol: "center" }), 12).mediaCut, 0);
    const compact = G.fitMenubar(L.fitBar, bar(800, 180, { mediaPolicy: "compact" }), 12);
    assert.equal(compact.mediaCut, 0);
    assert.ok(compact.compact.includes("media"));
});

test("a media chip in the right column shrinks towards the centre group too", () => {
    const options = bar(900, 180, { mediaCol: "right" });
    const chip = options.entries.find(entry => entry.id === "media").width;
    options.widths.left -= chip;
    options.widths.right += chip;
    const result = G.fitMenubar(L.fitBar, options, 12);
    assert.ok(result.mediaCut > 0, String(result.mediaCut));
    const available = 900 - 12;
    const rightStart = available - (options.widths.right - result.mediaCut);
    assert.ok(rightStart - (result.centerX + 150) >= 12);
});

test("the bar measures a cut title at full width and applies the fit's cut", () => {
    const bar = read("Bar/Bar.qml");
    const media = read("Bar/Modules/Media.qml");
    assert.match(bar, /BarGeometry\.fitMenubar\(LayoutHelpers\.fitBar,/);
    assert.match(bar, /mediaTitleCut = result\.mediaCut/);
    assert.match(bar, /shrinkable: slot\.detailShrinkable/);
    assert.match(bar, /width: slot\.width \+ \(moduleCompact\(id\) \? slot\.detailSaving : 0\) \+ cut/);
    assert.match(media, /detailShrinkable: Math\.max\(0, titleClip\.naturalWidth - titleMinimum\)/);
    assert.match(media, /width: naturalWidth - cut/);
    // The user's preferences stay in charge of the title.
    assert.match(media, /Settings\.modOpts\.media\.maxWidth/);
    assert.match(media, /Settings\.modOpts\.media\.titleFormat/);
    assert.match(read("Bar/ModuleSlot.qml"), /onDetailShrinkableChanged: host\.scheduleFit\(\)/);
});

test("bar targets span the bar's height and at least 32 px", () => {
    for (const rel of ["Bar/BarIcon.qml", "Bar/BarChip.qml"]) {
        const source = read(rel);
        assert.match(source, /readonly property real hitSlack: Theme\.barSpacing \/ 2/, rel);
        assert.match(source, /readonly property real hitMinWidth: Theme\.scaled\(32\)/, rel);
        assert.match(source, /hitMinWidth - hitSlack \* 2/, rel);
        assert.match(source,
            /MouseArea \{\s*id: mouse\s*anchors\.centerIn: parent\s*width: parent\.width \+ root\.hitSlack \* 2\s*height: Math\.max\(parent\.height, Theme\.barHeight\)/,
            rel);
        assert.match(source, /BarHover \{[\s\S]{0,200}?hitArea: mouse/, `${rel}: hover follows the click`);
    }
    assert.match(read("Bar/PointerCheck.qml"), /const area = root\.region \?\? root\.target;/);
    assert.match(read("Bar/BarHover.qml"), /region: root\.hitArea/);
    for (const rel of ["Bar/Workspaces.qml", "Bar/Modules/Tray.qml", "Bar/Modules/Indicators.qml"])
        assert.match(read(rel), /height: Math\.max\(parent\.height, Theme\.barHeight\)/, rel);
});

test("the dots style marks the current workspace with a 20 × 8 accent pill", () => {
    // Claude Fable, 2026-11 review: "pills of at least 8px, a filled or
    // wider pill for the active workspace, and a dimmer state for empty ones."
    const source = read("Bar/Workspaces.qml");
    const Motion = load("WorkspaceMotion.js");
    const inset = (Motion.CELL_WIDTH - 4 - 20) / 2;
    const cell = Motion.indicatorBounds([1, 2, 3], 2);
    assert.equal((cell.right - inset) - (cell.left + inset), 20);
    assert.equal((cell.left + inset + cell.right - inset) / 2, Motion.CELL_WIDTH * 1.5,
        "the pill is centred on its cell");
    assert.match(source, /readonly property int dotSize: 8/);
    assert.match(source, /readonly property int dotPillWidth: 20/);
    assert.match(source, /readonly property real dotPillInset: \(WorkspaceMotion\.CELL_WIDTH - 4 - dotPillWidth\) \/ 2/);
    assert.match(source, /const inset = numbered \? 0 : dotPillInset;/);
    assert.match(source, /height: root\.numbered \? Theme\.chipInnerHeight : root\.dotSize/);
    assert.match(source, /color: Theme\.barWsCurrent/);
    assert.match(source, /focused && !root\.numbered \? "transparent"/,
        "the pill replaces the current workspace's dot");
    // Every place is an 8 px pip in both styles; an empty one is a ring.
    assert.match(source, /width: slot\.showNumber \? Theme\.chipInnerHeight : root\.dotSize/);
    assert.match(source, /readonly property bool hollow: !exists && !urgent && !showNumber/);
    assert.match(source, /color: slot\.hollow \? "transparent" : slot\.restingTone/);
    assert.match(source, /border\.width: slot\.hollow \? 1\.5 : 0/);
});

test("the Cybex X is two-tone from its own SVG geometry", () => {
    const brand = read("Bar/BarBrandIcon.qml");
    const svg = read("assets/cybexos.svg");
    const paths = [...svg.matchAll(/ d="([^"]+)"/g)].map(match => match[1]);
    assert.equal(paths.length, 2);
    for (const d of paths)
        assert.ok(brand.includes(`path: "${d}"`), "BarBrandIcon draws assets/cybexos.svg's paths");
    assert.match(svg, /viewBox="147 3 44 44"/);
    assert.match(brand, /readonly property real unit: Math\.min\(root\.width, root\.height\) \/ 44/);
    assert.match(brand, /x: -147 \* mark\.unit/);
    assert.match(brand, /y: -3 \* mark\.unit/);
    assert.match(brand, /readonly property bool twoTone: name === "cybexos"/);
    // At rest: the shared ink, the short stroke at 55 %.
    assert.match(brand, /property color longInk: root\.highlighted \? Theme\.barTextHi : Theme\.barIcon/);
    assert.match(brand,
        /property color shortInk: root\.highlighted \? brandRed\s*: Qt\.rgba\(Theme\.barIcon\.r, Theme\.barIcon\.g, Theme\.barIcon\.b, 0\.55\)/);
    assert.match(brand, /readonly property color brandRed: "#DC1E37"/);
    assert.match(svg, /fill="#DC1E37"/);
    // Every other identity keeps the shared monochrome treatment.
    assert.match(brand, /BrandIcon \{[\s\S]{0,120}?visible: !root\.twoTone/);
});
