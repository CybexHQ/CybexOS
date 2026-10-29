pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../Common"

// The assistant's character: Wiz, or the Cybex X on a charcoal disc whose
// status ring shows activity (`assistantCharacter: mark`). Only the drawing
// differs; the window owns placement, dragging and input. The drawing not in
// use is not loaded, so its animations cost nothing.
//
// Moods (AssistantHelpers.mood) drive the mark: idle, attentive, listening,
// thinking, alert, happy, sorry, asleep. Poses (characterPose) drive Wiz.
Item {
    id: root

    property bool wiz: true
    property string mood: "idle"
    property string pose: "idle"
    // 0..1, the microphone's level while listening.
    property real level: 0
    property bool recording: false
    property bool hovered: false
    property bool unread: false
    // Which side the box is on, so an attentive look goes to it.
    property bool boxAbove: false
    // Where the pointer is over the character, in -1..1, for Wiz's eyes.
    property real lookX: 0
    property real lookY: 0
    // While dragged: its place on the output and where it was grabbed.
    property point dragPoint: Qt.point(0, 0)
    property point grab: Qt.point(width / 2, height / 2)

    implicitWidth: Assistant.characterSize
    implicitHeight: implicitWidth

    Loader {
        anchors.fill: parent
        sourceComponent: root.wiz ? wizDrawing : markDrawing
    }

    Component {
        id: wizDrawing

        Wiz {
            pose: root.pose
            level: root.level
            recording: root.recording
            hovered: root.hovered
            unread: root.unread
            boxAbove: root.boxAbove
            lookX: root.lookX
            lookY: root.lookY
            dragPoint: root.dragPoint
            grab: root.grab
            // Nobody at the machine sees him move.
            animated: !Theme.reducedMotion && !Activity.idle
        }
    }

    Component {
        id: markDrawing

        Item {
            id: mark

            readonly property color charcoal: "#1A1B1E"
            readonly property color accent: "#60A5FA"
            readonly property bool working: root.mood === "thinking"
            readonly property bool ringShown: root.hovered || root.mood === "attentive"
                || root.mood === "listening" || root.mood === "alert" || root.mood === "happy"

            // ---- the ring ------------------------------------------------------------
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 8
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: root.mood === "alert" ? Theme.amber
                    : root.mood === "listening" ? mark.accent : Qt.rgba(0.376, 0.647, 0.980, 0.55)
                opacity: mark.ringShown ? 1 : 0
                scale: root.mood === "listening" ? 1 + 0.22 * root.level : 1

                Behavior on opacity {
                    NumberAnimation { duration: Theme.chipFadeDuration }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 80 }
                }
            }

            // The working arc runs around the disc while a turn is in progress.
            Shape {
                id: arc
                anchors.centerIn: parent
                width: parent.width + 10
                height: width
                opacity: mark.working ? 1 : 0
                visible: opacity > 0
                preferredRendererType: Shape.CurveRenderer

                Behavior on opacity {
                    NumberAnimation { duration: Theme.chipFadeDuration }
                }

                ShapePath {
                    strokeColor: mark.accent
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: arc.width / 2
                        centerY: arc.height / 2
                        radiusX: arc.width / 2 - 2
                        radiusY: radiusX
                        startAngle: -90
                        sweepAngle: 100
                    }
                }

                RotationAnimator on rotation {
                    running: mark.working && !Theme.reducedMotion
                    from: 0
                    to: 360
                    duration: 1100
                    loops: Animation.Infinite
                }
            }

            // ---- the disc --------------------------------------------------------------
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: mark.charcoal
                border.width: 1
                border.color: Qt.rgba(0.953, 0.949, 0.925, root.hovered ? 0.28 : 0.14)

                Behavior on border.color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }
            }

            Image {
                anchors.centerIn: parent
                width: parent.width * 0.78
                height: width
                source: BrandIcons.source("cybexos")
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.ceil(width * 2)
                sourceSize.height: Math.ceil(height * 2)
                opacity: root.mood === "asleep" ? 0.55 : 1

                Behavior on opacity {
                    NumberAnimation { duration: Theme.chipFadeDuration }
                }
            }

            // A reply finished while the box was tucked away or the character hidden.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: -1
                width: Theme.scaled(13)
                height: width
                radius: width / 2
                color: root.mood === "alert" ? Theme.amber : mark.accent
                border.width: 2
                border.color: mark.charcoal
                visible: root.unread || root.mood === "alert"
            }
        }
    }
}
