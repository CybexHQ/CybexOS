pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// Filled play and pause marks. The Tabler outlines read as "00" and an empty
// triangle at the sizes the bar chip and the media panel use them, so these
// two are drawn solid; every other icon stays a Sym outline.
Item {
    id: root

    property bool playing: false
    property real size: 14
    property color color: Theme.icon

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }

    // Pause: two rounded bars.
    Row {
        anchors.centerIn: parent
        visible: root.playing
        spacing: Math.max(2, Math.round(root.size * 0.2))

        Repeater {
            model: 2

            Rectangle {
                width: Math.max(2, Math.round(root.size * 0.24))
                height: Math.round(root.size * 0.78)
                radius: Math.max(1, width / 3)
                color: root.color
            }
        }
    }

    // Play: a triangle with softened corners, nudged right so its visual
    // weight sits at the centre.
    Shape {
        anchors.fill: parent
        visible: !root.playing
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: Math.max(1, root.size * 0.1)
            joinStyle: ShapePath.RoundJoin
            fillColor: root.color
            startX: root.size * 0.28
            startY: root.size * 0.14

            PathLine { x: root.size * 0.88; y: root.size * 0.5 }
            PathLine { x: root.size * 0.28; y: root.size * 0.86 }
            PathLine { x: root.size * 0.28; y: root.size * 0.14 }
        }
    }
}
