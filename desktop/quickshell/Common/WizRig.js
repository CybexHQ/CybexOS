// Wiz, the Cybex OS Assistant's character: his artwork, poses and timing.
// Shared by Assistant/Wiz.qml, scripts/export-wiz and the Node tests, so plain
// JavaScript with no Qt or DOM APIs. Geometry lives in a 120 × 120 unit box.
//
// Quickshell never runs the drawing code below per frame. scripts/export-wiz
// renders each layer once, at rest, into assets/wiz/<layer>.svg; Wiz.qml
// stacks those layers and moves them declaratively, reading POSES, LAYOUT and
// LAYERS from here. ops() still describes the complete motion (breathing,
// blinks, runes, the spell, the nod) at any moment, which documents what the
// QML reproduces and lets toSVG() draw any pose as a still picture. While he
// is dragged, follow() and carry() turn the pointer's motion into how he
// swings, where his hat goes and whether he has been shaken dizzy.
//
//   var rig = WizRig.create(seed)
//   rig.update(dtSeconds, state, { reducedMotion, loop })
//   var ops = rig.ops({ frame: "free" | "disc", unread, effects })   // draw list
//   WizRig.toSVG(ops, size, viewBox)                        // still SVG
//   WizRig.layerSVG(name)                                   // one layer at rest
//   WizRig.stillSVG(state, { without, unread })             // a whole pose at rest
//
// States: idle | listening | thinking | working | finished | needs-input |
//         happy | greeting | sorry | asleep | carried

var WizRig = (function () {
  var C = {
    disc: "#1B1E23", discEdge: "#2E333B",
    cloak: "#23262C", edge: "#484E59", seam: "#16181C", face: "#0B0D10", collarHi: "#3E434D",
    eye: "#EEF6FF", eyeGlow: "#78BEFF",
    brimUnder: "#1C1F24", brim: "#30343C", brimHi: "#4E5561",
    hat: "#353A43", hatEdge: "#4A505B", crease: "#1A1D22",
    band: "#DC1E37", bandHi: "#FF6B7D", bandLo: "#8E1223",
    magic: "#4FA3F7", magicHi: "#9BD3FF", spellCore: "#E4F4FF", particle: "#BFE3FF", spark: "#D6EEFF",
    amber: "#F5B83D"
  };
  var STATES = ["idle", "listening", "thinking", "working", "finished", "needs-input", "happy", "greeting", "sorry", "asleep", "carried"];
  var BASE = { lean: 0, sc: 1, sy: 1, bodyY: 0, hatY: 0, hatRot: 0, hatLift: 0, eyeOpen: 1, eyeX: 0, eyeY: 0,
    happy: 0, spell: 0, runes: 0, amber: 0, bob: 1, sway: 1, tip: 0, voice: 0, glow: 1, feet: 0 };
  function pose(o) { var p = {}, k; for (k in BASE) p[k] = BASE[k]; for (k in o) p[k] = o[k]; return p; }
  var POSES = {
    "idle": pose({}),
    "listening": pose({ lean: 3, sc: 1.07, bodyY: 1, hatY: -6, hatRot: -4, eyeOpen: 1.3, eyeX: 0.6, eyeY: -0.8, bob: 0.4, sway: 0.5, tip: -1, voice: 1 }),
    "thinking": pose({ lean: -2, hatY: -1, hatRot: 3, eyeOpen: 0.78, eyeX: -2, eyeY: -2.4, runes: 1, bob: 0.6, sway: 1.7, tip: 1 }),
    "working": pose({ sc: 1.02, hatY: -1.5, eyeOpen: 0.92, eyeY: 1.8, spell: 1, bob: 0.5, sway: 0.5 }),
    "finished": pose({ happy: 1, eyeY: 0.4, bob: 0.8 }),
    "needs-input": pose({ sy: 0.95, bodyY: 2, hatY: 9, hatLift: -10, eyeOpen: 1.15, eyeX: 3.2, eyeY: -1.2, amber: 1, bob: 0.4, sway: 0.6, tip: -2 }),
    // A happy moment that is not a finished turn: no sparkle, no nod.
    "happy": pose({ happy: 1, eyeY: 0.4, bob: 0.8 }),
    // Hello: he lifts his hat off his head and tips it, eyes smiling.
    "greeting": pose({ lean: 1.5, hatY: -9, hatRot: -16, hatLift: -4, happy: 1, eyeY: 0.2, bob: 0.9, tip: -2 }),
    // The reply failed: hat tipped down, eyes lowered.
    "sorry": pose({ lean: -1.5, sc: 0.98, sy: 0.98, bodyY: 1, hatY: 2.5, hatRot: -7, eyeOpen: 0.72, eyeX: -1.2, eyeY: 2.2, bob: 0.3, sway: 0.4, tip: 2 }),
    // The assistant service is not there: hat down, eyes closed and dim.
    "asleep": pose({ sy: 0.97, bodyY: 1.5, hatY: 4, hatRot: -4, eyeOpen: 0.1, eyeY: 2, bob: 0.5, sway: 0.3, tip: 2.5, glow: 0.55 }),
    // Picked up: stretched, eyes huge, feet out of the cloak. carry() adds the
    // motion on top.
    "carried": pose({ sc: 1.02, sy: 1.04, bodyY: -1, hatY: -3, eyeOpen: 1.5, eyeY: -0.6, bob: 0, sway: 0.3, feet: 1 })
  };
  var BLEND_RATE = 7;        // pose easing, 1/s
  var FINISH_CYCLE = 3.4;    // s, sparkle + nod length when looping
  var KAPPA = 0.5523;
  var RUNES = [
    [["M", -2, -3], ["L", -2, 3], ["M", -2, -3], ["L", 1.8, -1.2], ["L", -2, 0.6], ["L", 2, 3]],
    [["M", 0, -3.2], ["L", 0, 3.2], ["M", -2.4, -0.8], ["L", 0, -3.2], ["L", 2.4, -0.8]],
    [["M", 0, -3.2], ["L", 2.6, 0], ["L", 0, 3.2], ["L", -2.6, 0], ["Z"]],
    [["M", -2, -3], ["L", -2, 3], ["M", 2, -3], ["L", 2, 3], ["M", -2, 1], ["L", 2, -1]]
  ];
  var STAR = [["M", 0, -5], ["Q", 0.9, -0.9, 5, 0], ["Q", 0.9, 0.9, 0, 5], ["Q", -0.9, 0.9, -5, 0], ["Q", -0.9, -0.9, 0, -5], ["Z"]];
  // [x, y, delay s, size] of the five sparkles a finished turn shows.
  var SPARKS = [[90, 4, 0, 1.2], [25, 28, 0.1, 0.85], [101, 46, 0.2, 0.75], [17, 64, 0.3, 0.65], [62, -5, 0.06, 0.6]];
  // Being dragged: a leg and boot (the left one; the right is its mirror), a
  // bead of sweat, "?!" drawn as strokes (no font), a puff of dust on
  // landing, and a spiral for each dizzy eye. All in local units around 0.
  var LEG = [["M", -1.4, 0], ["L", 1.4, 0], ["L", 1.4, 10], ["L", -1.4, 10], ["Z"]];
  var BOOT = [-1.8, 11.6, 5.8, 3.2];
  var SWEAT = [["M", 0, -4], ["C", 2.6, -0.6, 3, 1.6, 0, 3.6], ["C", -3, 1.6, -2.6, -0.6, 0, -4], ["Z"]];
  var QUESTION = [["M", -3.4, -4.6], ["C", -3.4, -8.4, 3.2, -8.4, 3.2, -4.6], ["C", 3.2, -2.2, 0, -1.8, 0, 1.2]];
  var BANG = [["M", 7.6, -7.8], ["L", 7.6, 1.2]];
  var PUFFS = [[-2.2, 0, 2.6, 2.2], [1.8, -0.6, 2.1, 1.8], [0.4, 1, 2.4, 1.6]];
  // Built when drawn: a QML import can run this file's top level before
  // globals such as Math exist (Qt 6.11, a component's first instance in a
  // Repeater), so nothing here computes at load time.
  function spiral() {
    var d = [], n = 36;
    for (var i = 0; i <= n; i++) {
      var a = i / n * 4.5 * Math.PI, r = 0.4 + 3.3 * i / n;
      d.push([i ? "L" : "M", r * Math.cos(a), r * Math.sin(a)]);
    }
    return d;
  }

  // Pivots and paths the drawing and Wiz.qml share, in rig units.
  var LAYOUT = {
    ground: [60, 110],       // the body leans and scales about this point
    eyes: [60, 68],          // eye centre line; blinks close towards it
    eyeGap: 5.5,             // each eye's distance from the middle
    brim: [60, 56],          // the hat tilts about the brim's centre...
    peek: [25, 56],          // ...and lifts about its left edge
    cone: [60, 55],          // Wiz.qml sways the cone about its base; ops() bends it
    spell: [60, 89],         // the working spell, which rises 1.5 as it appears
    pip: [93, 36],           // the waiting (amber) and unread pip
    orbit: { cx: 61, cy: 30, rx: 31, ry: 6.5, rate: 1.25 },   // the thinking runes
    sparks: SPARKS,
    // Dragged: where the legs hang from, under the cloak; the middle the
    // body stretches about along the drag; the "?!", the sweat, the dust
    // and the dizzy stars' orbit round the cone.
    feet: [[52, 101], [68, 101]],
    core: [60, 80],
    shout: [88, -2],
    sweat: [[42, 60], [78, 60]],
    phew: [79, 66],
    dust: [[38, 110], [82, 110]],
    dizzy: { cx: 61, cy: 27, rx: 23, ry: 5, rate: 3.9 }
  };

  // ---- carried --------------------------------------------------------------
  // While dragged, the pointer's velocity drives him: loose parts lag behind
  // the motion, his eyes look where he is going, his body stretches along it
  // (so a diagonal drag reads as diagonal), and a few quick reversals make him
  // dizzy. Velocities are in output pixels per second, y pointing down.
  var CARRY = {
    speed: 1400,        // what reads as a fling: reactions approach full strength
    smoothing: 0.35,    // share of a new sample in the running velocity
    minStep: 12,        // ms; closer samples wait for the next one
    stale: 150,         // ms; a pause longer than this starts from rest
    shakeSpeed: 650,    // a reversal counts as shaking above this speed...
    shakeTurns: 3,      // ...this many of them...
    shakeWindow: 1200   // ...within this many ms
  };
  // Full-strength reaction per unit of normalised velocity (carry()).
  var REACTION = {
    swing: 18,       // degrees about the grab: the bottom trails the motion
    hatX: -5,        // the hat slides back...
    hatUp: 8,        // ...is shoved down over the eyes when lifted...
    hatDown: -16,    // ...and floats off above him when he drops
    hatTilt: -14, hatTumble: -10,
    tip: -6,         // degrees: the tip of the hat blows back
    eyeX: 3.2, eyeUp: -2.2, eyeDown: -2.4,   // ahead, or up at the floating hat
    smear: 0.12,     // stretch along the motion
    feet: 30         // degrees: the feet trail behind
  };

  // The drag's running velocity and shake count, from successive positions.
  function follow(state, x, y, now) {
    var s = state || {};
    if (s.at != null && now - s.at >= 0 && now - s.at < CARRY.minStep) return s;
    var fresh = s.at == null || now - s.at > CARRY.stale;
    var next = { x: x, y: y, at: now, vx: 0, vy: 0, dirX: s.dirX || 0, dirY: s.dirY || 0, turns: [] };
    if (!fresh) {
      var dt = (now - s.at) / 1000;
      next.vx = s.vx + ((x - s.x) / dt - s.vx) * CARRY.smoothing;
      next.vy = s.vy + ((y - s.y) / dt - s.vy) * CARRY.smoothing;
    }
    var turns = s.turns || [];
    for (var i = 0; i < turns.length; i++)
      if (now - turns[i] <= CARRY.shakeWindow) next.turns.push(turns[i]);
    var dirX = Math.abs(next.vx) > CARRY.shakeSpeed ? (next.vx > 0 ? 1 : -1) : 0;
    var dirY = Math.abs(next.vy) > CARRY.shakeSpeed ? (next.vy > 0 ? 1 : -1) : 0;
    if ((dirX && next.dirX && dirX !== next.dirX) || (dirY && next.dirY && dirY !== next.dirY))
      next.turns.push(now);
    if (dirX) next.dirX = dirX;
    if (dirY) next.dirY = dirY;
    return next;
  }
  function shaken(state) { return !!state && !!state.turns && state.turns.length >= CARRY.shakeTurns; }
  // Velocity to -1..1 per axis, saturating gently past a fling.
  function normal(v) { return Math.tanh(v / CARRY.speed); }
  // How he reacts to a normalised velocity (ux, uy).
  function carry(ux, uy) {
    var up = Math.max(0, -uy), down = Math.max(0, uy), m = Math.min(1, Math.sqrt(ux * ux + uy * uy));
    var R = REACTION;
    return {
      swing: R.swing * ux,
      hatX: R.hatX * ux,
      hatY: R.hatUp * up + R.hatDown * down,
      hatTilt: R.hatTilt * ux + R.hatTumble * down,
      tip: R.tip * ux,
      eyeX: R.eyeX * ux,
      eyeY: R.eyeUp * up + R.eyeDown * down,
      smear: R.smear * m,
      angle: m > 0.001 ? Math.atan2(uy, ux) * 180 / Math.PI : 0,
      feet: R.feet * ux
    };
  }


  // ---- geometry helpers -------------------------------------------------
  function ell(cx, cy, rx, ry) {
    var kx = rx * KAPPA, ky = ry * KAPPA;
    return [["M", cx - rx, cy],
      ["C", cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry],
      ["C", cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy],
      ["C", cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry],
      ["C", cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy], ["Z"]];
  }
  function arc(cx, cy, r, a0, a1) {
    var segs = [], n = Math.max(1, Math.ceil(Math.abs(a1 - a0) / (Math.PI / 2))), step = (a1 - a0) / n;
    var k = 4 / 3 * Math.tan(step / 4);
    segs.push(["M", cx + r * Math.cos(a0), cy + r * Math.sin(a0)]);
    for (var i = 0; i < n; i++) {
      var s = a0 + i * step, e = s + step;
      segs.push(["C", cx + r * (Math.cos(s) - k * Math.sin(s)), cy + r * (Math.sin(s) + k * Math.cos(s)),
        cx + r * (Math.cos(e) + k * Math.sin(e)), cy + r * (Math.sin(e) - k * Math.cos(e)),
        cx + r * Math.cos(e), cy + r * Math.sin(e)]);
    }
    return segs;
  }
  function P(d, s) { var o = { k: "path", d: d }; for (var key in s) o[key] = s[key]; return o; }
  function G(t, a) { return { k: "g", t: t, a: a == null ? 1 : a }; }
  var END = { k: "end" };

  // ---- rig --------------------------------------------------------------
  function Rig(seed) {
    this.seed = seed == null ? Math.random() * 10 : seed;
    this.clock = this.seed * 3;
    this.state = "idle";
    this.enter = this.clock;
    this.cur = null;
    this.reduced = false;
    this.loop = true;
  }
  Rig.prototype.rnd = function (n) {
    var x = Math.sin(n * 12.9898 + this.seed * 78.233) * 43758.5453;
    return (x - Math.floor(x)) * 2 - 1;
  };
  Rig.prototype.target = function () {
    var tg = pose(POSES[this.state]);
    if (this.reduced) return tg;
    var g = Math.floor(this.clock / 2.3 + this.seed);
    if (this.state === "idle") { tg.eyeX += this.rnd(g) * 1.7; tg.eyeY += this.rnd(g + 31) * 0.7; }
    else if (this.state === "needs-input") tg.eyeX += this.rnd(g * 3) * 1.3;
    else if (this.state === "thinking") tg.eyeX += this.rnd(g);
    return tg;
  };
  // dt: seconds since last frame (already multiplied by any speed factor).
  Rig.prototype.update = function (dt, state, opts) {
    opts = opts || {};
    this.reduced = !!opts.reducedMotion;
    this.loop = opts.loop !== false;
    if (!POSES[state]) state = "idle";
    this.clock += dt;
    if (state !== this.state) { this.state = state; this.enter = this.clock; }
    var tg = this.target();
    if (!this.cur) { this.cur = tg; return; }
    var r = this.reduced ? 1 : 1 - Math.exp(-dt * BLEND_RATE);
    for (var k in tg) this.cur[k] += (tg[k] - this.cur[k]) * r;
  };

  // Every leaf carries `layer`: the assets/wiz file it is exported into.
  Rig.prototype.ops = function (opts) {
    opts = opts || {};
    var c = this.cur || this.target(), st = this.state, red = this.reduced;
    var t = red ? 0 : this.clock, O = [];
    var disc = opts.frame === "disc";
    var Lg = LAYOUT.ground, Le = LAYOUT.eyes, Lb = LAYOUT.brim, Lk = LAYOUT.peek, Lo = LAYOUT.orbit;

    var bobV = Math.sin(t * 2.1) * 0.9 * c.bob;
    var voiceV = Math.abs(Math.sin(t * 7.3) * Math.sin(t * 3.1)) * 1.6 * c.voice;
    var nod = 0, spark = -1;
    if (st === "finished") {
      var tE = this.clock - this.enter;
      if (this.loop) tE = tE % FINISH_CYCLE;
      if (red) spark = 0.5;
      else {
        spark = tE;
        if (tE > 0.15 && tE < 0.95) nod = Math.abs(Math.sin(Math.PI * (tE - 0.15) / 0.4));
      }
    }
    var bodyY = c.bodyY + bobV + nod * 0.8;
    var hatY = c.hatY + Math.sin(t * 2.1 - 0.7) * 0.6 * c.bob - voiceV + nod * 3.4;
    var w = c.tip + Math.sin(t * 1.4 + this.seed) * 1.3 * c.sway + nod * 1.2;

    var per = 3.4 + (this.seed % 1.6), ph = (this.clock + this.seed * 2) % per, blink = 1;
    if (!red && ph < 0.16) blink = 1 - 0.92 * Math.sin(Math.PI * ph / 0.16);
    blink = blink + (1 - blink) * Math.min(1, c.happy * 1.5);
    var open = Math.max(0.06, c.eyeOpen * blink);
    var ey = Le[1] + c.eyeY + nod * 2.2 + c.happy * 1.2;
    function eye(cx) {
      var a = 2.7, h = 3.3 * open, top = ey - h * 1.33, bot = ey + h * 1.33 * (1 - 1.6 * c.happy);
      return [["M", cx - a, ey], ["C", cx - a, top, cx + a, top, cx + a, ey], ["C", cx + a, bot, cx - a, bot, cx - a, ey], ["Z"]];
    }

    // frame
    if (disc) {
      O.push(P(ell(60, 60, 58, 58), { fill: C.disc, stroke: C.discEdge, lw: 1.5, layer: "disc" }));
      var arcOp = Math.max(c.spell, c.runes);
      if (arcOp > 0.01) {
        var a0 = ((t * 220) % 360) * Math.PI / 180;
        O.push(P(arc(60, 60, 55, a0, a0 + 70 / 55), { stroke: C.magic, lw: 2.6, cap: "round", a: arcOp, layer: "disc" }));
      }
      var amr = c.amber * (red ? 1 : 0.55 + 0.45 * Math.sin(t * 4));
      if (amr > 0.01) O.push(P(ell(60, 60, 55, 55), { stroke: C.amber, lw: 2.6, a: amr, layer: "disc" }));
      O.push(G([["t", 60, 63], ["s", 0.78, 0.78], ["t", -60, -63]]));
    }

    var fx = opts.effects || {};
    O.push(P(ell(Lg[0], Lg[1] + 0.5, 22 - bobV * 0.8 + (c.sc - 1) * 20, 3.2), { fill: "#000000", a: 0.3 * (1 - 0.65 * c.feet), layer: "shadow" }));
    if (fx.dust) for (var u = 0; u < LAYOUT.dust.length; u++) {
      O.push(G([["t", LAYOUT.dust[u][0], LAYOUT.dust[u][1]]]));
      for (var v = 0; v < PUFFS.length; v++)
        O.push(P(ell(PUFFS[v][0], PUFFS[v][1], PUFFS[v][2], PUFFS[v][3]), { fill: "#8A919C", a: 0.55, layer: "dust" }));
      O.push(END);
    }
    O.push(G([["t", Lg[0], Lg[1]], ["r", c.lean, 0, 0], ["s", c.sc, c.sc * c.sy], ["t", -Lg[0], -Lg[1]], ["t", 0, bodyY]]));

    // legs, behind the cloak, out only while carried
    if (c.feet > 0.02) for (var f = 0; f < LAYOUT.feet.length; f++) {
      O.push(G([["t", LAYOUT.feet[f][0], LAYOUT.feet[f][1] - 6 * (1 - c.feet)], ["s", f ? -1 : 1, 1]], c.feet));
      O.push(P(LEG, { fill: C.seam, layer: "foot" }));
      O.push(P(ell(BOOT[0], BOOT[1], BOOT[2], BOOT[3]), { fill: C.brim, stroke: C.edge, lw: 1.2, layer: "foot" }));
      O.push(P([["M", BOOT[0] - BOOT[2] + 1.6, BOOT[1] - 1.2], ["Q", BOOT[0] - 1, BOOT[1] - 2.6, BOOT[0] + 1.8, BOOT[1] - 2.1]], { stroke: C.brimHi, lw: 0.9, cap: "round", layer: "foot" }));
      O.push(END);
    }

    // body
    O.push(P([["M", 60, 60], ["C", 47, 60, 42, 70, 41, 80], ["C", 40, 90, 37, 100, 34, 106], ["Q", 60, 114, 86, 106],
      ["C", 83, 100, 80, 90, 79, 80], ["C", 78, 70, 73, 60, 60, 60], ["Z"]], { fill: C.cloak, stroke: C.edge, lw: 1.2, join: "round", layer: "body" }));
    O.push(P([["M", 60, 85], ["L", 60, 108.6]], { stroke: C.seam, lw: 1.1, cap: "round", layer: "body" }));
    O.push(P(ell(60, Le[1], 15.5, 8.5), { fill: C.face, layer: "body" }));
    if (c.spell > 0.01) O.push({ k: "radial", cx: 60, cy: 74, r: 16, sy: 0.5, color: C.magic, stops: [[0, 1], [0.55, 0.55], [1, 0]], a: 0.75 * c.spell, layer: "underlight" });
    if (fx.dizzy) for (var e = -1; e <= 1; e += 2) {
      O.push(G([["t", Le[0] + e * LAYOUT.eyeGap + c.eyeX, Le[1] + c.eyeY]]));
      O.push(P(spiral(), { stroke: C.eye, lw: 1.15, cap: "round", join: "round", glow: { c: C.eyeGlow, o: 0.95, s: 1.2 }, layer: "dizzy-eye" }));
      O.push(END);
    } else {
      O.push(P(eye(Le[0] - LAYOUT.eyeGap + c.eyeX), { fill: C.eye, a: c.glow, glow: { c: C.eyeGlow, o: 0.95, s: 1.6 }, layer: "eyes" }));
      O.push(P(eye(Le[0] + LAYOUT.eyeGap + c.eyeX), { fill: C.eye, a: c.glow, glow: { c: C.eyeGlow, o: 0.95, s: 1.6 }, layer: "eyes" }));
    }
    O.push(P([["M", 43.5, 72], ["C", 50, 78.5, 70, 78.5, 76.5, 72], ["C", 78.2, 75.5, 79, 79, 79.2, 82], ["Q", 60, 88, 40.8, 82],
      ["C", 41, 79, 41.8, 75.5, 43.5, 72], ["Z"]], { fill: C.cloak, layer: "collar" }));
    O.push(P([["M", 44, 72.5], ["C", 50.2, 78.9, 69.8, 78.9, 76, 72.5]], { stroke: C.collarHi, lw: 1.3, cap: "round", layer: "collar" }));

    // spell (working)
    var s = c.spell;
    if (s > 0.02) {
      var fl = red ? 1 : 1 + 0.07 * Math.sin(t * 17) + 0.05 * Math.sin(t * 29 + 1);
      var sx0 = LAYOUT.spell[0], sy0 = LAYOUT.spell[1] - s * 1.5, ringR = 5.8 * s, rot = ((t * 140) % 360) * Math.PI / 180;
      O.push(G([], Math.min(1, s * 1.4)));
      O.push({ k: "radial", cx: sx0, cy: sy0, r: 8.5 * s * fl + 6, sy: 1, color: C.magic, stops: [[0, 0.6], [0.5, 0.3], [1, 0]], a: 1, layer: "spell-glow" });
      var dashes = [], n = Math.max(6, Math.floor(2 * Math.PI * ringR / 4.8));
      for (var i = 0; i < n; i++) { var da = rot + i * 2 * Math.PI / n; dashes = dashes.concat(arc(sx0, sy0, ringR, da, da + 2.2 / ringR)); }
      O.push(P(dashes, { stroke: C.magicHi, lw: 0.9, layer: "spell-ring" }));
      O.push(P(ell(sx0, sy0, 2.9 * s * fl, 2.9 * s * fl), { fill: C.spellCore, glow: { c: C.magic, o: 1, s: 2.5 }, layer: "spell-core" }));
      for (var j = 0; j < 4; j++) {
        var pp = red ? j / 4 : (t * 0.8 + j / 4) % 1, pr = 0.9 * (1 - pp * 0.4);
        O.push(P(ell(sx0 + Math.sin(j * 2.3 + t * 2.5) * 3.5 * (1 - pp * 0.3), sy0 - 3 - pp * 15, pr, pr), { fill: C.particle, a: s * (1 - pp), layer: "mote" }));
      }
      O.push(END);
    }

    // hat
    O.push(G([["t", 0, hatY], ["r", c.hatRot, Lb[0], Lb[1]], ["r", c.hatLift, Lk[0], Lk[1]]]));
    var front = [];
    if (c.runes > 0.02) for (var q = 0; q < 4; q++) {
      var ra = t * Lo.rate + q * Math.PI / 2 + 0.4, sn = Math.sin(ra), rk = (0.82 + 0.22 * sn) * c.runes;
      var rune = [G([["t", Lo.cx + Lo.rx * Math.cos(ra), Lo.cy + Lo.ry * sn + Math.sin(t * 2.2 + q) * 1.3], ["s", rk, rk]], c.runes * (sn > 0 ? 1 : 0.5)),
        P(RUNES[q], { stroke: C.magicHi, lw: 1.15, cap: "round", join: "round", glow: { c: C.magic, o: 1, s: 1.5 }, layer: "rune" + q }), END];
      if (sn > 0) front = front.concat(rune); else O = O.concat(rune);
    }
    O.push(P(ell(60, 56.9, 35, 7), { fill: C.brimUnder, stroke: C.edge, lw: 1.1, layer: "brim" }));
    O.push(P(ell(60, 56, 35, 7), { fill: C.brim, layer: "brim" }));
    O.push(P([["M", 25.6, 55.2], ["C", 25.6, 47.8, 94.4, 47.8, 94.4, 55.2]], { stroke: C.brimHi, lw: 1, layer: "brim" }));
    O.push(P([["M", 41, 56], ["C", 45, 42, 50, 30, 56 + w * .2, 22], ["C", 61 + w * .4, 15, 68 + w * .7, 9 + w * .1, 75 + w, 6.5 + w * .2],
      ["C", 78 + w * 1.2, 5.6 + w * .4, 80.5 + w * 1.3, 6.6 + w * .6, 81 + w * 1.4, 9 + w * .8],
      ["C", 77 + w * 1.1, 9 + w * .5, 71 + w * .6, 13 + w * .2, 69 + w * .4, 19],
      ["C", 67.5 + w * .2, 27, 72, 42, 79, 56], ["Q", 60, 62, 41, 56], ["Z"]], { fill: C.hat, stroke: C.hatEdge, lw: 1.1, join: "round", layer: "cone" }));
    O.push(P([["M", 69 + w * .4, 19], ["C", 67.5 + w * .2, 27, 72, 42, 79, 56], ["Q", 70, 59.8, 63, 59.2], ["C", 62.5, 46, 64, 30, 69 + w * .4, 19], ["Z"]], { fill: "#000000", a: 0.22, layer: "cone" }));
    O.push(P([["M", 57.5 + w * .25, 21.5], ["Q", 63 + w * .5, 18.5, 68.6 + w * .4, 19.6]], { stroke: C.crease, lw: 1, cap: "round", layer: "cone" }));
    O.push(P([["M", 43.1, 49], ["Q", 60, 55.5, 75.8, 49], ["L", 78.2, 54.6], ["Q", 60, 61.4, 41.4, 54.6], ["Z"]], { fill: C.band, layer: "band" }));
    O.push(P([["M", 43.3, 49.3], ["Q", 60, 55.8, 75.6, 49.3]], { stroke: C.bandHi, lw: 0.8, a: 0.45, layer: "band" }));
    O.push(P([["M", 41.6, 54.3], ["Q", 60, 61.1, 78, 54.3]], { stroke: C.bandLo, lw: 1, layer: "band" }));
    O = O.concat(front);
    if (fx.dizzy) for (var ds = 0; ds < 4; ds++) {
      var da2 = ds * Math.PI / 2 + 0.4, Ld = LAYOUT.dizzy;
      O.push(G([["t", Ld.cx + Ld.rx * Math.cos(da2), Ld.cy + Ld.ry * Math.sin(da2)], ["s", 0.55, 0.55]]));
      O.push(P(STAR, { fill: C.spark, stroke: C.magic, lw: 1, join: "round", glow: { c: C.magic, o: 0.95, s: 1.6 }, layer: "star" }));
      O.push(END);
    }
    O.push(END);

    // carried: "?!" and a bead of sweat
    if (fx.shout) {
      O.push(G([["t", LAYOUT.shout[0], LAYOUT.shout[1]]]));
      // A dark outline under the light strokes keeps it legible on light wallpapers.
      O.push(P(QUESTION.concat(BANG), { stroke: C.face, lw: 4.1, cap: "round", join: "round", a: 0.85, layer: "shout" }));
      O.push(P(ell(0, 4.6, 2.25, 2.25).concat(ell(7.6, 4.6, 2.25, 2.25)), { fill: C.face, a: 0.85, layer: "shout" }));
      O.push(P(QUESTION.concat(BANG), { stroke: C.eye, lw: 2.3, cap: "round", join: "round", glow: { c: C.eyeGlow, o: 0.9, s: 1.3 }, layer: "shout" }));
      O.push(P(ell(0, 4.6, 1.35, 1.35).concat(ell(7.6, 4.6, 1.35, 1.35)), { fill: C.eye, glow: { c: C.eyeGlow, o: 0.9, s: 1.3 }, layer: "shout" }));
      O.push(END);
    }
    if (fx.sweat) {
      O.push(G([["t", LAYOUT.sweat[1][0], LAYOUT.sweat[1][1]]]));
      O.push(P(SWEAT, { fill: C.magicHi, stroke: C.magic, lw: 0.8, layer: "sweat" }));
      O.push(END);
    }

    // finished sparkle
    if (spark >= 0) for (var z = 0; z < SPARKS.length; z++) {
      var S = SPARKS[z], sp = (spark - S[2]) / 0.6, e = sp > 0 && sp < 1 ? Math.sin(Math.PI * sp) : 0;
      if (e < 0.01) continue;
      O.push(G([["t", S[0], S[1]], ["r", sp * 70, 0, 0], ["s", S[3] * e, S[3] * e]]));
      O.push(P(STAR, { fill: C.spark, glow: { c: C.magic, o: 0.95, s: 2 }, layer: "sparkle" }));
      O.push(END);
    }

    // needs-input pip, or the unread one
    var am = c.amber, Lp = LAYOUT.pip;
    if (am > 0.02) {
      var pq = red ? 0.4 : (t * 0.9) % 1, ringP = 3 + 6 * pq;
      O.push(P(ell(Lp[0], Lp[1], ringP, ringP), { stroke: C.amber, lw: 1.2, a: (1 - pq) * am * 0.8, layer: "pip-ring" }));
      O.push(P(ell(Lp[0], Lp[1], 3 * am, 3 * am), { fill: C.amber, layer: "pip" }));
    } else if (opts.unread) {
      O.push(P(ell(Lp[0], Lp[1], 3, 3), { fill: C.magic, layer: "unread" }));
    }

    O.push(END);          // root
    if (disc) O.push(END); // disc frame
    return O;
  };

  // ---- layers -------------------------------------------------------------
  // What Wiz.qml stacks, each exported at rest into assets/wiz/<name>.svg.
  // `box` is [x, y, width, height] in rig units. Layers without `at` keep
  // their place in the 120-unit box; the others are exported around their
  // own centre `at`, so Wiz.qml can move, spin and scale them about it.
  // `tag` picks the ops a layer shares with another; `state`, `patch` and
  // `effects` set what it is drawn in; `first` keeps that many ops of a part
  // drawn several times; `opaque` leaves its fading to Wiz.qml.
  var LAYERS = {
    "shadow": { box: [36, 106, 48, 9] },
    "body": { box: [32, 58, 56, 58] },
    "underlight": { state: "working", box: [43, 65, 34, 18] },
    "eyes": { box: [46, 58, 28, 20] },
    "eyes-happy": { tag: "eyes", patch: { happy: 1 }, box: [46, 58, 28, 20] },
    "collar": { box: [39, 70, 42, 20] },
    "spell-glow": { state: "working", at: [60, 87.5], box: [-15, -15, 30, 30] },
    "spell-ring": { state: "working", at: [60, 87.5], box: [-7, -7, 14, 14] },
    "spell-core": { state: "working", at: [60, 87.5], box: [-11, -11, 22, 22] },
    "mote": { state: "working", at: [60, 84.5], box: [-2, -2, 4, 4], first: 1 },
    "rune0": { state: "thinking", box: [-9, -9, 18, 18] },
    "rune1": { state: "thinking", box: [-9, -9, 18, 18] },
    "rune2": { state: "thinking", box: [-9, -9, 18, 18] },
    "rune3": { state: "thinking", box: [-9, -9, 18, 18] },
    "brim": { box: [23, 46, 74, 20] },
    "cone": { box: [38, 3, 46, 61] },
    "band": { box: [40, 47, 40, 16] },
    "sparkle": { state: "finished", box: [-12, -12, 24, 24], first: 1 },
    "pip": { state: "needs-input", at: [93, 36], box: [-4, -4, 8, 8] },
    "pip-ring": { state: "needs-input", at: [93, 36], box: [-7, -7, 14, 14], opaque: true },
    "unread": { at: [93, 36], box: [-4, -4, 8, 8] },
    "foot": { state: "carried", box: [-9, -1, 18, 17], first: 3 },
    "sweat": { effects: { sweat: true }, box: [-4, -5, 8, 10] },
    "shout": { effects: { shout: true }, box: [-9, -14, 22, 24], first: 5 },
    "dust": { effects: { dust: true }, box: [-6, -4, 12, 8], first: 3 },
    "dizzy-eye": { effects: { dizzy: true }, box: [-9, -9, 18, 18], first: 1 },
    "star": { effects: { dizzy: true }, box: [-11, -11, 22, 22], first: 1 }
  };

  function layerOps(name) {
    var L = LAYERS[name], rig = new Rig(0), tag = L.tag || name, out = [];
    rig.update(0, L.state || "idle", { reducedMotion: true });
    for (var k in L.patch || {}) rig.cur[k] = L.patch[k];
    var ops = rig.ops({ unread: name === "unread", effects: L.effects });
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i];
      if ((o.k === "path" || o.k === "radial") && o.layer === tag) {
        if (L.opaque) o = Object.assign({}, o, { a: 1 });
        out.push(o);
        if (out.length === L.first) break;
      }
    }
    return out;
  }

  function layerSVG(name) {
    var L = LAYERS[name], at = L.at || [0, 0], b = L.box;
    var ops = [G([])].concat(layerOps(name), [END]);
    return toSVG(ops, null, [at[0] + b[0], at[1] + b[1], b[2], b[3]]) + "\n";
  }

  // A whole pose at rest as one picture: what the boot splash, the lock
  // screen, the terminal and the installer show (scripts/export-wiz). Every
  // still shares one box, so poses swapped in place line up. `without` leaves
  // out layers, which the installer moves on its own.
  var STILL_BOX = [-8, -12, 136, 132];
  function stillSVG(state, opts) {
    opts = opts || {};
    var rig = new Rig(0), skip = opts.without || [];
    rig.update(0, state, { reducedMotion: true });
    var ops = rig.ops({ unread: !!opts.unread }).filter(function (o) {
      return (o.k !== "path" && o.k !== "radial") || skip.indexOf(o.layer) === -1;
    });
    return toSVG(ops, null, opts.box || STILL_BOX) + "\n";
  }

  // ---- still SVG ----------------------------------------------------------
  function num(n) { return Math.round(n * 100) / 100; }
  function dStr(d) {
    var out = [];
    for (var i = 0; i < d.length; i++) out.push(d[i][0] + d[i].slice(1).map(num).join(" "));
    return out.join("");
  }
  function tStr(t) {
    return t.map(function (o) {
      if (o[0] === "t") return "translate(" + num(o[1]) + " " + num(o[2]) + ")";
      if (o[0] === "s") return "scale(" + num(o[1]) + " " + num(o[2]) + ")";
      return "rotate(" + num(o[1]) + " " + num(o[2]) + " " + num(o[3]) + ")";
    }).join(" ");
  }
  // size: the width attribute (the height follows the viewBox); viewBox:
  // [x, y, w, h] in rig units, the whole 120-unit box by default.
  function toSVG(ops, size, viewBox) {
    var vb = viewBox || [0, 0, 120, 120], scale = (size || vb[2]) / vb[2];
    var defs = [], body = [], filters = {}, gid = 0;
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i];
      if (o.k === "g") body.push('<g' + (o.t.length ? ' transform="' + tStr(o.t) + '"' : '') + (o.a < 1 ? ' opacity="' + num(o.a) + '"' : '') + '>');
      else if (o.k === "end") body.push('</g>');
      else if (o.k === "radial") {
        var id = "wr" + (gid++);
        defs.push('<radialGradient id="' + id + '">' + o.stops.map(function (s) {
          return '<stop offset="' + s[0] + '" stop-color="' + o.color + '" stop-opacity="' + s[1] + '"/>';
        }).join("") + '</radialGradient>');
        body.push('<ellipse cx="' + num(o.cx) + '" cy="' + num(o.cy) + '" rx="' + num(o.r) + '" ry="' + num(o.r * o.sy) + '" fill="url(#' + id + ')"' + (o.a < 1 ? ' opacity="' + num(o.a) + '"' : '') + '/>');
      } else if (o.k === "path") {
        var f = "";
        if (o.glow) {
          var key = o.glow.c + o.glow.o + "_" + o.glow.s;
          if (!filters[key]) {
            filters[key] = "wg" + (gid++);
            defs.push('<filter id="' + filters[key] + '" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur in="SourceAlpha" stdDeviation="' + o.glow.s + '" result="b"/><feFlood flood-color="' + o.glow.c + '" flood-opacity="' + o.glow.o + '"/><feComposite in2="b" operator="in"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>');
          }
          f = ' filter="url(#' + filters[key] + ')"';
        }
        body.push('<path d="' + dStr(o.d) + '" fill="' + (o.fill || "none") + '"' +
          (o.stroke ? ' stroke="' + o.stroke + '" stroke-width="' + (o.lw || 1) + '"' + (o.cap ? ' stroke-linecap="' + o.cap + '"' : '') + (o.join ? ' stroke-linejoin="' + o.join + '"' : '') : '') +
          (o.a != null && o.a < 1 ? ' opacity="' + num(o.a) + '"' : '') + f + '/>');
      }
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + num(vb[2] * scale) + '" height="' + num(vb[3] * scale) +
      '" viewBox="' + vb.map(num).join(" ") + '">' +
      (defs.length ? '<defs>' + defs.join("") + '</defs>' : '') + body.join("") + '</svg>';
  }

  return {
    create: function (seed) { return new Rig(seed); },
    follow: follow,
    shaken: shaken,
    normal: normal,
    carry: carry,
    CARRY: CARRY,
    REACTION: REACTION,
    toSVG: toSVG,
    layerOps: layerOps,
    layerSVG: layerSVG,
    stillSVG: stillSVG,
    STILL_BOX: STILL_BOX,
    STATES: STATES,
    POSES: POSES,
    LAYOUT: LAYOUT,
    LAYERS: LAYERS,
    COLORS: C
  };
})();

if (typeof module !== "undefined" && module.exports) module.exports = WizRig;
