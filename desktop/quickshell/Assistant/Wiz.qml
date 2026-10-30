pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../Common"
import "../Common/WizRig.js" as Rig

// Wiz, the assistant's character (docs/assistant.md).
//
// Still layers, each drawn once at the size it is shown (assets/wiz/,
// exported from Common/WizRig.js by scripts/export-wiz), moved by declarative
// animation: no Canvas, no offscreen layer, and no script per frame except
// while he is being dragged. A change of
// pose glides once. Idle holds still between blinks, glances and a rare wobble
// of the hat, so a resting Wiz draws a few frames a second at most. Loops run
// only while the assistant works (the runes, the spell, the sway) and pulse
// only briefly while a question waits; they are Animators, which the threaded
// render loop runs on the scene graph's thread. Without `animated` every pose
// holds still and nothing ticks.
//
// Picked up, he panics: a startled jump with "?!", sweat and his feet out,
// then he swings from where he was grabbed while his hat and feet trail the
// pointer's motion (WizRig.carry), stretched along it so a diagonal drag
// reads as one. A few quick shakes make him dizzy. Dropped, he lands with a
// thud, his hat a beat later and crooked. Only a drag and its landing animate;
// the springs that follow the pointer run on the frames the drag draws anyway.
Item {
    id: root

    // One of WizRig.STATES; Assistant.pose picks it.
    property string pose: "idle"
    // 0..1, the microphone's level, which lifts the hat while recording.
    property real level: 0
    property bool recording: false
    property bool hovered: false
    property bool unread: false
    // The box opens above the character, so an attentive look goes up.
    property bool boxAbove: false
    // The pointer over the character, -1..1, for the eyes to follow.
    property real lookX: 0
    property real lookY: 0
    // While carried: the character's place on its output, set once per
    // pointer move, and the point it was grabbed by, in item pixels.
    property point dragPoint: Qt.point(0, 0)
    property point grab: Qt.point(width / 2, height / 2)
    // Off for reduced motion (which power saver turns on) and an unattended
    // session: poses snap into place and nothing loops. Every surface that
    // shows him inherits this.
    property bool animated: !Theme.reducedMotion && !Activity.idle

    readonly property var wiz: Rig.WizRig
    readonly property var layout: wiz.LAYOUT
    readonly property var stance: wiz.POSES[pose] || wiz.POSES.idle
    readonly property bool live: animated && visible
    // Running a turn or recording: the loops' states. Everything else only
    // blinks, glances or plays once.
    readonly property bool looping: live && (pose === "thinking" || pose === "working"
        || (pose === "listening" && recording))
    readonly property bool attentive: pose === "listening" && !recording
    readonly property bool carried: pose === "carried"
    // Rig units to item pixels, and to device pixels for drawing the layers.
    readonly property real unit: Math.min(width, height) / 120
    readonly property real pixels: unit * Math.max(1, Math.ceil(Screen.devicePixelRatio))

    implicitWidth: 88
    implicitHeight: 88

    // ---- the pose ------------------------------------------------------------
    // Eased the way the rig blends (7/s, most of the way in under half a second).
    property real lean: stance.lean
    property real bodyScale: stance.sc
    property real squash: stance.sy
    property real bodyY: stance.bodyY
    property real hatY: stance.hatY
    property real hatRot: stance.hatRot
    property real hatLift: stance.hatLift
    property real eyeOpen: stance.eyeOpen * (hovered && stance.happy === 0 ? 1.1 : 1)
    property real eyeX: stance.eyeX
    property real eyeY: stance.eyeY
    property real happy: stance.happy
    property real spell: stance.spell
    property real runes: stance.runes
    property real amber: stance.amber
    property real tip: stance.tip
    property real glow: stance.glow
    property real voiceLift: recording ? level * 2.4 * stance.voice : 0
    // Out from under the cloak while carried; his shadow fades as he leaves the ground.
    property real feet: stance.feet

    component Blend: NumberAnimation {
        duration: 450
        easing.type: Easing.OutCubic
    }
    Behavior on lean { enabled: root.animated; Blend {} }
    Behavior on bodyScale { enabled: root.animated; Blend {} }
    Behavior on squash { enabled: root.animated; Blend {} }
    Behavior on bodyY { enabled: root.animated; Blend {} }
    Behavior on hatY { enabled: root.animated; Blend {} }
    Behavior on hatRot { enabled: root.animated; Blend {} }
    Behavior on hatLift { enabled: root.animated; Blend {} }
    Behavior on eyeOpen { enabled: root.animated; Blend {} }
    Behavior on eyeX { enabled: root.animated; Blend {} }
    Behavior on eyeY { enabled: root.animated; Blend {} }
    Behavior on happy { enabled: root.animated; Blend {} }
    Behavior on spell { enabled: root.animated; Blend {} }
    Behavior on runes { enabled: root.animated; Blend {} }
    Behavior on amber { enabled: root.animated; Blend {} }
    Behavior on tip { enabled: root.animated; Blend {} }
    Behavior on glow { enabled: root.animated; Blend {} }
    Behavior on feet {
        enabled: root.animated
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on voiceLift {
        enabled: root.animated
        NumberAnimation { duration: 90 }
    }

    // ---- glances and blinks ----------------------------------------------------
    property real glanceX: 0
    property real glanceY: 0
    property real blink: 1
    readonly property point gaze: carried ? Qt.point(reaction.eyeX, reaction.eyeY)
        : hovered ? Qt.point(lookX * 2, lookY * 1.2)
        : attentive ? Qt.point(0, boxAbove ? -1 : 1.4)
        : Qt.point(glanceX, glanceY)

    // Idle looks around the most, thinking and a waiting question sideways.
    readonly property var glances: ({ "idle": [1.7, 0.7], "thinking": [1, 0], "needs-input": [1.3, 0] })

    Timer {
        running: root.live && root.glances[root.pose] !== undefined && !root.hovered
        repeat: true
        interval: 2300
        onTriggered: {
            const reach = root.glances[root.pose];
            // Now and then the eyes come back to the middle.
            const back = Math.random() < 0.3;
            root.glanceX = back ? 0 : (Math.random() * 2 - 1) * reach[0];
            root.glanceY = back ? 0 : (Math.random() * 2 - 1) * reach[1];
            interval = 2300 + Math.random() * 3200;
        }
    }
    onPoseChanged: {
        glanceX = 0;
        glanceY = 0;
        pulses = 0;
        if (pose === "finished" && live)
            celebrate();
    }

    Timer {
        running: root.live && ["happy", "greeting", "finished", "asleep"].indexOf(root.pose) === -1 && !root.dizzy
        repeat: true
        interval: 3400
        onTriggered: {
            blinking.restart();
            interval = 3400 + Math.random() * 1600;
        }
    }

    SequentialAnimation {
        id: blinking
        NumberAnimation { target: root; property: "blink"; to: 0.08; duration: 80; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "blink"; to: 1; duration: 80; easing.type: Easing.OutQuad }
    }

    // ---- the orbits ------------------------------------------------------------
    // The rig's runes, motes and sway follow sines. A quarter period is one
    // eased step, so a looping wave is four Animators, and a wave starting a
    // quarter later is the same four in a rotated order.
    readonly property var cosine: [1, 0, -1, 0]
    function wave(step, phase, middle, amplitude) {
        return middle + amplitude * cosine[(phase + step) % 4];
    }
    function ease(step, phase) {
        return (phase + step) % 2 === 0 ? Easing.InSine : Easing.OutSine;
    }

    // One exported layer, drawn once at the size it is shown and then only
    // moved. Its box places it in the rig's frame, or around the centre of
    // the item holding it; `origin` shifts a full-frame layer under a pivot.
    component Part: Image {
        required property string name
        property point origin: Qt.point(0, 0)
        readonly property var box: root.wiz.LAYERS[name].box
        x: box[0] - origin.x
        y: box[1] - origin.y
        width: box[2]
        height: box[3]
        source: Qt.resolvedUrl("../assets/wiz/" + name + ".svg")
        sourceSize: Qt.size(Math.ceil(box[2] * root.pixels), Math.ceil(box[3] * root.pixels))
        smooth: true
    }

    // Something circling the hat: a rune while he thinks, a star while he is
    // dizzy. Each is drawn twice, moving together: behind the cone at half
    // strength, and over it on the near half of the orbit only. The two swap
    // at the far left and right, which the cone does not cover.
    component Orbiter: Item {
        id: orbiter

        required property int index
        property bool front: false
        property string art
        property var orbit: root.layout.orbit
        property real size: 1
        property bool running: false
        readonly property int quarter: Math.round(Math.PI / 2 / orbit.rate * 1000)
        // y and size follow the sine, a quarter behind x's cosine.
        readonly property int lag: (index + 3) % 4

        function near(step) {
            return (index + step) % 4 < 2 ? 1 : 0;
        }

        x: root.wave(0, index, orbit.cx, orbit.rx)
        y: root.wave(0, lag, orbit.cy, orbit.ry)
        scale: root.wave(0, lag, 0.82 * size, 0.22 * size)
        opacity: front ? near(0) : 1

        Part {
            name: orbiter.art
        }

        SequentialAnimation on x {
            running: orbiter.running
            loops: Animation.Infinite
            XAnimator { from: root.wave(0, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); to: root.wave(1, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); duration: orbiter.quarter; easing.type: root.ease(0, orbiter.index) }
            XAnimator { from: root.wave(1, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); to: root.wave(2, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); duration: orbiter.quarter; easing.type: root.ease(1, orbiter.index) }
            XAnimator { from: root.wave(2, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); to: root.wave(3, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); duration: orbiter.quarter; easing.type: root.ease(2, orbiter.index) }
            XAnimator { from: root.wave(3, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); to: root.wave(4, orbiter.index, orbiter.orbit.cx, orbiter.orbit.rx); duration: orbiter.quarter; easing.type: root.ease(3, orbiter.index) }
        }
        SequentialAnimation on y {
            running: orbiter.running
            loops: Animation.Infinite
            YAnimator { from: root.wave(0, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); to: root.wave(1, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); duration: orbiter.quarter; easing.type: root.ease(0, orbiter.lag) }
            YAnimator { from: root.wave(1, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); to: root.wave(2, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); duration: orbiter.quarter; easing.type: root.ease(1, orbiter.lag) }
            YAnimator { from: root.wave(2, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); to: root.wave(3, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); duration: orbiter.quarter; easing.type: root.ease(2, orbiter.lag) }
            YAnimator { from: root.wave(3, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); to: root.wave(4, orbiter.lag, orbiter.orbit.cy, orbiter.orbit.ry); duration: orbiter.quarter; easing.type: root.ease(3, orbiter.lag) }
        }
        SequentialAnimation on scale {
            running: orbiter.running
            loops: Animation.Infinite
            ScaleAnimator { from: root.wave(0, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); to: root.wave(1, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); duration: orbiter.quarter; easing.type: root.ease(0, orbiter.lag) }
            ScaleAnimator { from: root.wave(1, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); to: root.wave(2, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); duration: orbiter.quarter; easing.type: root.ease(1, orbiter.lag) }
            ScaleAnimator { from: root.wave(2, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); to: root.wave(3, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); duration: orbiter.quarter; easing.type: root.ease(2, orbiter.lag) }
            ScaleAnimator { from: root.wave(3, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); to: root.wave(4, orbiter.lag, 0.82 * orbiter.size, 0.22 * orbiter.size); duration: orbiter.quarter; easing.type: root.ease(3, orbiter.lag) }
        }
        SequentialAnimation on opacity {
            running: orbiter.running && orbiter.front
            loops: Animation.Infinite
            OpacityAnimator { from: orbiter.near(0); to: orbiter.near(0); duration: orbiter.quarter }
            OpacityAnimator { from: orbiter.near(1); to: orbiter.near(1); duration: orbiter.quarter }
            OpacityAnimator { from: orbiter.near(2); to: orbiter.near(2); duration: orbiter.quarter }
            OpacityAnimator { from: orbiter.near(3); to: orbiter.near(3); duration: orbiter.quarter }
        }
    }

    // A bead of sweat: flung off his head when he is grabbed and while he
    // dangles, or sliding down his face once he is down.
    component Drop: Item {
        id: drop

        property real direction: 1

        function fly() {
            sliding.stop();
            flying.restart();
        }
        function slide() {
            flying.stop();
            sliding.restart();
        }

        Item {
            id: bead
            opacity: 0

            Part {
                name: "sweat"
            }
        }

        ParallelAnimation {
            id: flying
            XAnimator { target: bead; from: 0; to: 10 * drop.direction; duration: 620; easing.type: Easing.OutQuad }
            SequentialAnimation {
                YAnimator { target: bead; from: 0; to: -5; duration: 220; easing.type: Easing.OutQuad }
                YAnimator { target: bead; from: -5; to: 9; duration: 400; easing.type: Easing.InQuad }
            }
            OpacityAnimator { target: bead; from: 1; to: 0; duration: 620; easing.type: Easing.InQuad }
            RotationAnimator { target: bead; from: 0; to: 50 * drop.direction; duration: 620 }
        }

        SequentialAnimation {
            id: sliding
            PauseAnimation { duration: 350 }
            ParallelAnimation {
                XAnimator { target: bead; from: 0; to: 0; duration: 0 }
                RotationAnimator { target: bead; from: 0; to: 0; duration: 0 }
            }
            ParallelAnimation {
                YAnimator { target: bead; from: 0; to: 7; duration: 800; easing.type: Easing.InQuad }
                OpacityAnimator { target: bead; from: 1; to: 0; duration: 800; easing.type: Easing.InQuad }
            }
        }
    }

    // A puff of dust kicked up by a landing, stronger for a harder one.
    component Puff: Item {
        id: puff

        property real direction: 1

        function burst() {
            puffing.restart();
        }

        Item {
            id: cloud
            opacity: 0
            scale: 0.4

            Part {
                name: "dust"
            }
        }

        ParallelAnimation {
            id: puffing
            XAnimator { target: cloud; from: 0; to: 7 * puff.direction; duration: 520; easing.type: Easing.OutQuad }
            ScaleAnimator { target: cloud; from: 0.4; to: 0.7 + 0.6 * root.impact; duration: 520; easing.type: Easing.OutQuad }
            OpacityAnimator { target: cloud; from: 0.25 + 0.7 * root.impact; to: 0; duration: 520; easing.type: Easing.InQuad }
        }
    }

    // A mote rising off the spell, a quarter of a rise behind the one before.
    // The rise is linear, so its loop is split where this mote starts.
    component Mote: Item {
        id: mote

        required property int index
        readonly property real start: index / 4
        readonly property int rise: 1250
        readonly property int drift: 628
        readonly property bool running: root.live && root.spell > 0.02

        x: root.wave(0, index, 0, 3)

        Item {
            id: climb
            y: -3 - 15 * mote.start
            opacity: 1 - mote.start
            scale: 1 - 0.4 * mote.start

            Part {
                name: "mote"
            }
        }

        SequentialAnimation {
            running: mote.running
            loops: Animation.Infinite
            ParallelAnimation {
                YAnimator { target: climb; from: -3 - 15 * mote.start; to: -18; duration: mote.rise * (1 - mote.start) }
                OpacityAnimator { target: climb; from: 1 - mote.start; to: 0; duration: mote.rise * (1 - mote.start) }
                ScaleAnimator { target: climb; from: 1 - 0.4 * mote.start; to: 0.6; duration: mote.rise * (1 - mote.start) }
            }
            ParallelAnimation {
                YAnimator { target: climb; from: -3; to: -3 - 15 * mote.start; duration: Math.max(1, mote.rise * mote.start) }
                OpacityAnimator { target: climb; from: 1; to: 1 - mote.start; duration: Math.max(1, mote.rise * mote.start) }
                ScaleAnimator { target: climb; from: 1; to: 1 - 0.4 * mote.start; duration: Math.max(1, mote.rise * mote.start) }
            }
        }
        SequentialAnimation on x {
            running: mote.running
            loops: Animation.Infinite
            XAnimator { from: root.wave(0, mote.index, 0, 3); to: root.wave(1, mote.index, 0, 3); duration: mote.drift; easing.type: root.ease(0, mote.index) }
            XAnimator { from: root.wave(1, mote.index, 0, 3); to: root.wave(2, mote.index, 0, 3); duration: mote.drift; easing.type: root.ease(1, mote.index) }
            XAnimator { from: root.wave(2, mote.index, 0, 3); to: root.wave(3, mote.index, 0, 3); duration: mote.drift; easing.type: root.ease(2, mote.index) }
            XAnimator { from: root.wave(3, mote.index, 0, 3); to: root.wave(4, mote.index, 0, 3); duration: mote.drift; easing.type: root.ease(3, mote.index) }
        }
    }

    // A finished turn's sparkle. A bursting one waits its turn, grows, spins
    // a little and shrinks away; a still one holds the rig's reduced-motion
    // picture, half a second into the burst.
    component Sparkle: Item {
        id: sparkle

        required property var modelData
        property bool burst: false
        readonly property real phase: (0.5 - modelData[2]) / 0.6

        function flare() {
            flaring.restart();
        }

        x: modelData[0]
        y: modelData[1]
        scale: burst ? 0 : phase > 0 && phase < 1 ? modelData[3] * Math.sin(Math.PI * phase) : 0
        rotation: burst ? 0 : phase * 70

        Part {
            name: "sparkle"
        }

        SequentialAnimation {
            id: flaring
            ScaleAnimator { target: sparkle; from: 0; to: 0; duration: sparkle.modelData[2] * 1000 }
            ParallelAnimation {
                SequentialAnimation {
                    ScaleAnimator { target: sparkle; from: 0; to: sparkle.modelData[3]; duration: 300; easing.type: Easing.OutSine }
                    ScaleAnimator { target: sparkle; from: sparkle.modelData[3]; to: 0; duration: 300; easing.type: Easing.InSine }
                }
                RotationAnimator { target: sparkle; from: 0; to: 70; duration: 600 }
            }
        }
    }

    // ---- the drawing ---------------------------------------------------------
    Item {
        id: rig
        width: 120
        height: 120
        x: (root.width - 120 * root.unit) / 2
        y: (root.height - 120 * root.unit) / 2
        scale: root.unit
        transformOrigin: Item.TopLeft

        Part {
            name: "shadow"
            opacity: 1 - 0.65 * root.feet
            transform: Scale {
                origin.x: root.layout.ground[0]
                origin.y: root.layout.ground[1]
                xScale: (1 + (root.bodyScale - 1) * 0.9) * (1 - 0.25 * root.feet)
            }
        }

        Repeater {
            id: puffs
            model: root.layout.dust
            delegate: Puff {
                required property var modelData
                required property int index
                x: modelData[0]
                y: modelData[1]
                direction: index === 0 ? -1 : 1
            }
        }

        // Leans and scales about the ground point, then rises with the pose.
        Item {
            id: body
            width: 120
            height: 120
            transform: [
                Translate { y: root.bodyY },
                Scale {
                    origin.x: root.layout.ground[0]
                    origin.y: root.layout.ground[1]
                    xScale: root.bodyScale
                    yScale: root.bodyScale * root.squash
                },
                Rotation {
                    origin.x: root.layout.ground[0]
                    origin.y: root.layout.ground[1]
                    angle: root.lean
                },
                // The startled stretch and the landing's squash.
                Scale {
                    origin.x: root.layout.ground[0]
                    origin.y: root.layout.ground[1]
                    xScale: root.thudX
                    yScale: root.thudY
                },
                // Stretched along the drag, whatever its direction.
                Rotation {
                    origin.x: root.layout.core[0]
                    origin.y: root.layout.core[1]
                    angle: -root.reaction.angle
                },
                Scale {
                    origin.x: root.layout.core[0]
                    origin.y: root.layout.core[1]
                    xScale: 1 + root.reaction.smear
                    yScale: 1 - root.reaction.smear / 2
                },
                Rotation {
                    origin.x: root.layout.core[0]
                    origin.y: root.layout.core[1]
                    angle: root.reaction.angle
                },
                // Hanging from where he was grabbed, the bottom trailing.
                Rotation {
                    origin.x: root.pivot.x
                    origin.y: root.pivot.y
                    angle: root.reaction.swing
                }
            ]

            // Breathing while the loops run; the nod when a turn finishes;
            // a nervous tremble while he dangles.
            Item {
                id: breath
                width: 120
                height: 120

                Item {
                    id: bodyNod
                    width: 120
                    height: 120

                    // Out from under the cloak while carried: they kick while
                    // he dangles and trail behind when he is pulled along.
                    Repeater {
                        model: root.layout.feet
                        delegate: Item {
                            id: leg

                            required property var modelData
                            required property int index
                            // The two kick in turn.
                            readonly property int phase: index === 0 ? 3 : 1

                            x: modelData[0]
                            y: modelData[1] - 6 * (1 - root.feet)
                            opacity: root.feet
                            visible: opacity > 0.02
                            rotation: root.reaction.feet

                            Item {
                                Part {
                                    name: "foot"
                                    mirror: leg.index === 1
                                }

                                SequentialAnimation on rotation {
                                    running: root.live && root.carried
                                    loops: Animation.Infinite
                                    RotationAnimator { from: root.wave(0, leg.phase, 0, 16); to: root.wave(1, leg.phase, 0, 16); duration: 120; easing.type: root.ease(0, leg.phase) }
                                    RotationAnimator { from: root.wave(1, leg.phase, 0, 16); to: root.wave(2, leg.phase, 0, 16); duration: 120; easing.type: root.ease(1, leg.phase) }
                                    RotationAnimator { from: root.wave(2, leg.phase, 0, 16); to: root.wave(3, leg.phase, 0, 16); duration: 120; easing.type: root.ease(2, leg.phase) }
                                    RotationAnimator { from: root.wave(3, leg.phase, 0, 16); to: root.wave(4, leg.phase, 0, 16); duration: 120; easing.type: root.ease(3, leg.phase) }
                                }
                            }
                        }
                    }

                    Part {
                        name: "body"
                    }

                    Part {
                        name: "underlight"
                        opacity: root.spell
                        visible: opacity > 0.01
                    }

                    // The pose's look, then glances and the pointer, then the lids.
                    Item {
                        width: 120
                        height: 120
                        x: root.eyeX
                        y: root.eyeY
                        opacity: root.glow

                        Item {
                            width: 120
                            height: 120
                            x: root.gaze.x
                            y: root.gaze.y

                            Behavior on x {
                                enabled: root.animated
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                enabled: root.animated
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }

                            Item {
                                id: dart
                                width: 120
                                height: 120

                                Item {
                                    id: eyesNod
                                    width: 120
                                    height: 120
                                    opacity: 1 - root.dizziness
                                    visible: opacity > 0.01
                                    transform: Scale {
                                        origin.x: root.layout.eyes[0]
                                        origin.y: root.layout.eyes[1]
                                        xScale: 1 + 0.15 * root.feet
                                        yScale: Math.max(0.06, root.eyeOpen * root.blink * root.squint)
                                    }

                                    Part {
                                        name: "eyes"
                                        opacity: 1 - root.happy
                                        visible: opacity > 0.01
                                    }

                                    Part {
                                        name: "eyes-happy"
                                        opacity: root.happy
                                        visible: opacity > 0.01
                                    }
                                }

                                // Dizzy: spirals for eyes, turning opposite ways.
                                Repeater {
                                    model: [-1, 1]
                                    delegate: Item {
                                        id: spiral

                                        required property real modelData

                                        x: root.layout.eyes[0] + modelData * root.layout.eyeGap
                                        y: root.layout.eyes[1]
                                        opacity: root.dizziness
                                        visible: opacity > 0.01

                                        Item {
                                            Part {
                                                name: "dizzy-eye"
                                            }

                                            RotationAnimator on rotation {
                                                running: root.live && root.dizziness > 0.01
                                                loops: Animation.Infinite
                                                from: 0
                                                to: 360 * spiral.modelData
                                                duration: 900
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Part {
                        name: "collar"
                    }

                    // Working: the spell in front of the cloak, rising as it appears.
                    Item {
                        id: spell
                        x: root.layout.spell[0]
                        y: root.layout.spell[1] - 1.5 * root.spell
                        scale: root.spell
                        opacity: Math.min(1, root.spell * 1.4)
                        visible: root.spell > 0.02

                        readonly property bool running: root.live && visible

                        Item {
                            Part {
                                name: "spell-glow"
                            }

                            SequentialAnimation on scale {
                                running: spell.running
                                loops: Animation.Infinite
                                ScaleAnimator { from: 1; to: 1.07; duration: 90 }
                                ScaleAnimator { from: 1.07; to: 0.97; duration: 120 }
                                ScaleAnimator { from: 0.97; to: 1.1; duration: 80 }
                                ScaleAnimator { from: 1.1; to: 0.95; duration: 130 }
                                ScaleAnimator { from: 0.95; to: 1.04; duration: 100 }
                                ScaleAnimator { from: 1.04; to: 1; duration: 110 }
                            }
                        }

                        Item {
                            Part {
                                name: "spell-ring"
                            }

                            RotationAnimator on rotation {
                                running: spell.running
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 2571
                            }
                        }

                        Item {
                            Part {
                                name: "spell-core"
                            }

                            SequentialAnimation on scale {
                                running: spell.running
                                loops: Animation.Infinite
                                ScaleAnimator { from: 1; to: 0.95; duration: 110 }
                                ScaleAnimator { from: 0.95; to: 1.08; duration: 90 }
                                ScaleAnimator { from: 1.08; to: 0.98; duration: 120 }
                                ScaleAnimator { from: 0.98; to: 1.06; duration: 100 }
                                ScaleAnimator { from: 1.06; to: 1; duration: 130 }
                            }
                        }

                        Repeater {
                            model: 4
                            delegate: Mote {}
                        }
                    }

                    // Tilts about the brim's centre, lifts about its left edge
                    // to peek, and rises with the voice.
                    Item {
                        id: hat
                        width: 120
                        height: 120
                        transform: [
                            Rotation {
                                origin.x: root.layout.peek[0]
                                origin.y: root.layout.peek[1]
                                angle: root.hatLift
                            },
                            Rotation {
                                origin.x: root.layout.brim[0]
                                origin.y: root.layout.brim[1]
                                angle: root.hatRot
                            },
                            Translate { y: root.hatY - root.voiceLift },
                            // Carried: blown back, shoved down or floating off;
                            // crooked after a landing, askew while dizzy.
                            Rotation {
                                origin.x: root.layout.brim[0]
                                origin.y: root.layout.brim[1]
                                angle: root.reaction.hatTilt + root.crook + 8 * root.dizziness
                            },
                            Translate {
                                x: root.reaction.hatX
                                y: root.reaction.hatY
                            }
                        ]

                        Item {
                            id: hatNod
                            width: 120
                            height: 120

                            Item {
                                width: 120
                                height: 120
                                opacity: root.runes * 0.5
                                visible: root.runes > 0.02

                                Repeater {
                                    model: 4
                                    delegate: Orbiter {
                                        id: rune
                                        art: "rune" + rune.index
                                        running: root.live && root.runes > 0.02
                                    }
                                }
                            }

                            Item {
                                width: 120
                                height: 120
                                opacity: root.dizziness * 0.5
                                visible: root.dizziness > 0.01

                                Repeater {
                                    model: 4
                                    delegate: Orbiter {
                                        art: "star"
                                        orbit: root.layout.dizzy
                                        size: 0.55
                                        running: root.live && root.dizziness > 0.01
                                    }
                                }
                            }

                            Part {
                                name: "brim"
                            }

                            // The cone sways about its base; the rig bends it
                            // instead, which a still layer cannot.
                            Item {
                                x: root.layout.cone[0]
                                y: root.layout.cone[1]
                                rotation: root.tip * 1.6 + root.reaction.tip

                                Item {
                                    id: sway

                                    Part {
                                        name: "cone"
                                        origin: Qt.point(root.layout.cone[0], root.layout.cone[1])
                                    }
                                }
                            }

                            Part {
                                name: "band"
                            }

                            Item {
                                width: 120
                                height: 120
                                opacity: root.runes
                                visible: root.runes > 0.02

                                Repeater {
                                    model: 4
                                    delegate: Orbiter {
                                        id: frontRune
                                        front: true
                                        art: "rune" + frontRune.index
                                        running: root.live && root.runes > 0.02
                                    }
                                }
                            }

                            Item {
                                width: 120
                                height: 120
                                opacity: root.dizziness
                                visible: root.dizziness > 0.01

                                Repeater {
                                    model: 4
                                    delegate: Orbiter {
                                        front: true
                                        art: "star"
                                        orbit: root.layout.dizzy
                                        size: 0.55
                                        running: root.live && root.dizziness > 0.01
                                    }
                                }
                            }
                        }
                    }

                    // A finished turn: a burst once, or held still.
                    Item {
                        visible: root.pose === "finished"

                        Repeater {
                            id: bursts
                            model: root.live ? root.layout.sparks : []
                            delegate: Sparkle {
                                burst: true
                            }
                        }

                        Repeater {
                            model: root.live ? [] : root.layout.sparks
                            delegate: Sparkle {}
                        }
                    }

                    // A question waiting (amber, pulsing) or an unread reply (blue).
                    Item {
                        x: root.layout.pip[0]
                        y: root.layout.pip[1]

                        Part {
                            name: "pip-ring"
                            visible: !root.live && root.amber > 0.02
                            // The rig's reduced-motion ring: 40% out, fading.
                            opacity: 0.48 * root.amber
                        }

                        Part {
                            id: pulseRing
                            name: "pip-ring"
                            visible: root.live && root.amber > 0.02
                            opacity: 0
                        }

                        Part {
                            name: "pip"
                            scale: root.amber
                            visible: root.amber > 0.02
                        }

                        Part {
                            name: "unread"
                            visible: root.unread && root.amber <= 0.02
                        }
                    }

                    // Grabbed: "?!" pops over his hat.
                    Item {
                        id: shout
                        x: root.layout.shout[0]
                        y: root.layout.shout[1]
                        opacity: 0
                        scale: 0

                        Part {
                            name: "shout"
                        }
                    }

                    Repeater {
                        id: flyers
                        model: root.layout.sweat
                        delegate: Drop {
                            required property var modelData
                            required property int index
                            x: modelData[0]
                            y: modelData[1]
                            direction: index === 0 ? -1 : 1
                        }
                    }

                    Drop {
                        id: phew
                        x: root.layout.phew[0]
                        y: root.layout.phew[1]
                    }
                }
            }
        }
    }

    // ---- breathing and the sway --------------------------------------------------
    // The loops start from rest and ease back to it, so changing pose never
    // makes the hat jump.
    property real breathDepth: 0
    property real swayReach: 0

    SequentialAnimation {
        id: breathing
        loops: Animation.Infinite
        YAnimator { target: breath; from: 0; to: root.breathDepth; duration: 748; easing.type: Easing.OutSine }
        YAnimator { target: breath; from: root.breathDepth; to: -root.breathDepth; duration: 1496; easing.type: Easing.InOutSine }
        YAnimator { target: breath; from: -root.breathDepth; to: 0; duration: 748; easing.type: Easing.InSine }
    }

    SequentialAnimation {
        id: swaying
        loops: Animation.Infinite
        RotationAnimator { target: sway; from: root.wave(0, 3, 0, root.swayReach); to: root.wave(1, 3, 0, root.swayReach); duration: 1122; easing.type: root.ease(0, 3) }
        RotationAnimator { target: sway; from: root.wave(1, 3, 0, root.swayReach); to: root.wave(2, 3, 0, root.swayReach); duration: 1122; easing.type: root.ease(1, 3) }
        RotationAnimator { target: sway; from: root.wave(2, 3, 0, root.swayReach); to: root.wave(3, 3, 0, root.swayReach); duration: 1122; easing.type: root.ease(2, 3) }
        RotationAnimator { target: sway; from: root.wave(3, 3, 0, root.swayReach); to: root.wave(4, 3, 0, root.swayReach); duration: 1122; easing.type: root.ease(3, 3) }
    }

    ParallelAnimation {
        id: settling
        RotationAnimator { target: sway; to: 0; duration: 300; easing.type: Easing.OutCubic }
        YAnimator { target: breath; to: 0; duration: 300; easing.type: Easing.OutCubic }
        onFinished: root.resume()
    }

    // A rare shake of the hat while idle.
    SequentialAnimation {
        id: wobble
        RotationAnimator { target: sway; from: 0; to: 2.4; duration: 380; easing.type: Easing.OutSine }
        RotationAnimator { target: sway; from: 2.4; to: -1.6; duration: 520; easing.type: Easing.InOutSine }
        RotationAnimator { target: sway; from: -1.6; to: 0.8; duration: 460; easing.type: Easing.InOutSine }
        RotationAnimator { target: sway; from: 0.8; to: 0; duration: 420; easing.type: Easing.InOutSine }
    }

    Timer {
        running: root.live && root.pose === "idle" && !root.hovered
        repeat: true
        interval: 20000
        onTriggered: {
            if (!settling.running && !swaying.running)
                wobble.restart();
            interval = 20000 + Math.random() * 15000;
        }
    }

    // Back to rest, then the loops this pose wants, at its own reach.
    function settle() {
        breathing.stop();
        swaying.stop();
        wobble.stop();
        if (animated) {
            settling.restart();
        } else {
            settling.stop();
            sway.rotation = 0;
            breath.y = 0;
        }
    }
    function resume() {
        if (!looping)
            return;
        breathDepth = 0.9 * stance.bob;
        swayReach = 2.1 * stance.sway;
        breathing.start();
        swaying.start();
    }
    onLoopingChanged: settle()
    onStanceChanged: {
        if (looping)
            settle();
    }
    Component.onCompleted: resume()

    // ---- once: the finished turn, and the waiting pulse --------------------------
    // Two nods: the body dips a little, the eyes more, the hat most.
    ParallelAnimation {
        id: nodding
        Nod { item: bodyNod; depth: 0.8 }
        Nod { item: eyesNod; depth: 1.4 }
        Nod { item: hatNod; depth: 2.6 }
    }

    component Nod: SequentialAnimation {
        id: nod
        required property Item item
        required property real depth
        YAnimator { target: nod.item; from: 0; to: 0; duration: 150 }
        YAnimator { target: nod.item; from: 0; to: nod.depth; duration: 200; easing.type: Easing.OutSine }
        YAnimator { target: nod.item; from: nod.depth; to: 0; duration: 200; easing.type: Easing.InSine }
        YAnimator { target: nod.item; from: 0; to: nod.depth; duration: 200; easing.type: Easing.OutSine }
        YAnimator { target: nod.item; from: nod.depth; to: 0; duration: 200; easing.type: Easing.InSine }
    }

    function celebrate() {
        nodding.restart();
        for (let i = 0; i < bursts.count; i++)
            (bursts.itemAt(i) as Sparkle)?.flare();
    }

    property int pulses: 0

    ParallelAnimation {
        id: pulse
        ScaleAnimator { target: pulseRing; from: 3 / 5.4; to: 9 / 5.4; duration: 1111 }
        OpacityAnimator { target: pulseRing; from: 0.8; to: 0; duration: 1111 }
    }

    // Three pulses as the question arrives, then a reminder now and then: a
    // question can wait for minutes, and the box already shows it.
    Timer {
        running: root.live && root.pose === "needs-input"
        repeat: true
        triggeredOnStart: true
        interval: root.pulses < 3 ? 1111 : 8000
        onTriggered: {
            pulse.restart();
            root.pulses++;
        }
    }

    // ---- carried ----------------------------------------------------------------
    // The drag's velocity (WizRig.follow), normalised and sprung, so he swings
    // past and settles when the pointer stops. Everything he does while
    // carried reads `reaction`.
    property var tracker: null
    property real ux: 0
    property real uy: 0
    readonly property var reaction: wiz.carry(ux, uy)
    readonly property point pivot: Qt.point(grab.x / unit, grab.y / unit)
    // Nearly still: he trembles instead.
    readonly property bool dangling: carried && Math.abs(ux) + Math.abs(uy) < 0.08

    component Spring: SpringAnimation {
        spring: 3.5
        damping: 0.22
        epsilon: 0.002
    }
    Behavior on ux { enabled: root.animated; Spring {} }
    Behavior on uy { enabled: root.animated; Spring {} }

    function follow() {
        tracker = wiz.follow(tracker, dragPoint.x, dragPoint.y, Date.now());
        ux = wiz.normal(tracker.vx);
        uy = wiz.normal(tracker.vy);
        if (wiz.shaken(tracker))
            dizzy = true;
        calm.restart();
    }
    onDragPointChanged: {
        if (carried && live)
            follow();
    }

    // The pointer stopped: he swings back to hanging straight.
    Timer {
        id: calm
        interval: root.wiz.CARRY.stale
        onTriggered: {
            root.ux = 0;
            root.uy = 0;
        }
    }

    // ---- dizzy ------------------------------------------------------------------
    property bool dizzy: false
    property real dizziness: dizzy ? 1 : 0
    Behavior on dizziness {
        enabled: root.animated
        NumberAnimation { duration: 300 }
    }

    // Seeing stars for a while after he is put down.
    Timer {
        id: recover
        interval: 2200
        onTriggered: root.dizzy = false
    }

    // ---- picked up and put down -------------------------------------------------
    property real thudX: 1
    property real thudY: 1
    property real squint: 1
    property real crook: 0
    // How hard the landing was, 0.35..1, from how fast he was moving.
    property real impact: 0.35
    property real hop: 12
    property int drips: 0

    onCarriedChanged: {
        if (carried) {
            tracker = null;
            recover.stop();
            if (live)
                startle();
        } else {
            impact = Math.min(1, 0.35 + 0.65 * Math.sqrt(ux * ux + uy * uy));
            calm.stop();
            ux = 0;
            uy = 0;
            if (live)
                land();
            if (dizzy)
                recover.restart();
        }
    }

    // "Yikes": he jumps up stretched, his hat pops off, his eyes dart, "?!"
    // flashes and sweat flies.
    function startle() {
        nodding.stop();
        landing.stop();
        crooking.stop();
        crook = 0;
        squint = 1;
        startling.restart();
        hop = 12;
        hopping.restart();
        doubleTake.restart();
        shouting.restart();
        for (let i = 0; i < flyers.count; i++)
            (flyers.itemAt(i) as Drop)?.fly();
    }

    // A thud: squashed with his eyes shut, the hat landing a beat later and
    // crooked, dust, then a bead of sweat and a shake of the hat.
    function land(sweat) {
        startling.stop();
        doubleTake.stop();
        landing.restart();
        hop = 10 * impact;
        hopping.restart();
        crooking.restart();
        for (let i = 0; i < puffs.count; i++)
            (puffs.itemAt(i) as Puff)?.burst();
        if (sweat !== false)
            phew.slide();
    }

    // Set down somewhere new without a drag, as the welcome guide hands him
    // to his corner: a light landing, no sweat.
    function arrive() {
        if (!live)
            return;
        impact = 0.5;
        land(false);
    }

    SequentialAnimation {
        id: startling
        ParallelAnimation {
            NumberAnimation { target: root; property: "thudY"; to: 1.14; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "thudX"; to: 0.94; duration: 90; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "thudY"; to: 1; duration: 320; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "thudX"; to: 1; duration: 320; easing.type: Easing.OutBack }
        }
    }

    SequentialAnimation {
        id: landing
        ParallelAnimation {
            NumberAnimation { target: root; property: "thudY"; to: 1 - 0.2 * root.impact; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "thudX"; to: 1 + 0.1 * root.impact; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "squint"; to: 0.12; duration: 80 }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "thudY"; to: 1 + 0.07 * root.impact; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "thudX"; to: 1 - 0.03 * root.impact; duration: 140; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "thudY"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "thudX"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "squint"; to: 1; duration: 320; easing.type: Easing.OutCubic }
        }
    }

    // The hat leaves his head and comes down with a bounce.
    SequentialAnimation {
        id: hopping
        YAnimator { target: hatNod; from: 0; to: -root.hop; duration: 140; easing.type: Easing.OutQuad }
        YAnimator { target: hatNod; from: -root.hop; to: 0; duration: 460; easing.type: Easing.OutBounce }
    }

    // It lands crooked; a moment later he shakes it straight.
    SequentialAnimation {
        id: crooking
        PauseAnimation { duration: 380 }
        NumberAnimation { target: root; property: "crook"; to: 7 * root.impact; duration: 150; easing.type: Easing.OutBack }
        PauseAnimation { duration: 650 }
        NumberAnimation { target: root; property: "crook"; to: -2.5; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "crook"; to: 1.5; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "crook"; to: 0; duration: 160; easing.type: Easing.OutSine }
    }

    SequentialAnimation {
        id: doubleTake
        XAnimator { target: dart; from: 0; to: -1.8; duration: 70 }
        XAnimator { target: dart; from: -1.8; to: 1.8; duration: 110 }
        XAnimator { target: dart; from: 1.8; to: 0; duration: 120 }
    }

    ParallelAnimation {
        id: shouting
        SequentialAnimation {
            ScaleAnimator { target: shout; from: 0; to: 1.25; duration: 160; easing.type: Easing.OutBack }
            ScaleAnimator { target: shout; from: 1.25; to: 1; duration: 100 }
        }
        SequentialAnimation {
            OpacityAnimator { target: shout; from: 1; to: 1; duration: 700 }
            OpacityAnimator { target: shout; from: 1; to: 0; duration: 220 }
        }
    }

    // Dangling: a nervous tremble, and a bead of sweat now and then.
    SequentialAnimation {
        running: root.live && root.dangling
        loops: Animation.Infinite
        onStopped: breath.x = 0
        XAnimator { target: breath; from: 0; to: 0.5; duration: 60 }
        XAnimator { target: breath; from: 0.5; to: -0.5; duration: 120 }
        XAnimator { target: breath; from: -0.5; to: 0; duration: 60 }
    }

    Timer {
        running: root.live && root.carried
        repeat: true
        interval: 1500
        onTriggered: {
            (flyers.itemAt(root.drips % flyers.count) as Drop)?.fly();
            root.drips++;
        }
    }

    onLiveChanged: {
        if (!live) {
            nodding.complete();
            pulse.complete();
            startling.complete();
            landing.complete();
            hopping.complete();
            crooking.complete();
            dizzy = false;
            ux = 0;
            uy = 0;
        }
    }
}
