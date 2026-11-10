pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../Common"

// The assistant box's one button: a glyph, a label, or both. `primary` is
// the action the card exists for (Send, Allow, Apply…); `danger` stops or
// refuses. A glyph-only button still names itself for screen readers, and
// `tip` shows a longer name on hover or keyboard focus. However small it is
// drawn, it takes the pointer over at least 32 px.
Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string accessibleName: label
    property bool primary: false
    property bool danger: false
    property bool round: label === ""
    property real controlHeight: Theme.scaled(30)
    // A glyph-only button shows its name on hover by itself.
    property string tip: label === "" ? accessibleName : ""
    readonly property real hitPad: Math.max(0, (Theme.scaled(32) - height) / 2)
    readonly property color ink: primary ? Theme.accentFg
        : danger ? Theme.redText : Theme.textMid

    signal triggered()

    implicitHeight: controlHeight
    implicitWidth: round ? controlHeight
        : content.implicitWidth + Theme.scaled(label !== "" && glyph !== "" ? 20 : 22)
    radius: round ? height / 2 : Theme.chipRadius
    color: primary ? Theme.accent : danger ? Theme.redBgSoft : Theme.chip
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: enabled && visible
    border.width: Theme.focusWidth(activeFocus)
    border.color: Theme.focusRing

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.onPressAction: {
        if (root.enabled)
            root.triggered();
    }

    Keys.onPressed: event => {
        if (root.enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space)) {
            pressState.pulseCenter();
            root.triggered();
            event.accepted = true;
        }
    }

    StateLayer {
        id: pressState
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse && root.enabled
        pressed: mouse.pressed
        focused: root.activeFocus
        tint: root.ink
        pressPoint: Qt.point(mouse.mouseX - root.hitPad, mouse.mouseY - root.hitPad)
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.scaled(6)

        Sym {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph !== ""
            name: root.glyph
            size: Theme.iconMedium
            color: root.ink
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            color: root.ink
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            font.weight: root.primary ? Theme.weightSemibold : Theme.weightMedium
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -root.hitPad
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggered()
    }

    // The panel's own surface and ink, as Settings' tips (SettingsTooltip).
    // Made only while wanted: History lists a delete button on every row.
    Loader {
        active: root.tip !== "" && (mouse.containsMouse || Theme.focusWidth(root.activeFocus) > 0)
        sourceComponent: Controls.ToolTip {
            id: tipBox
            parent: root
            visible: true
            text: root.tip
            delay: 450
            timeout: -1
            margins: Theme.scaled(6)
            padding: 0
            y: -height - Theme.scaled(6)

            contentItem: Text {
                text: tipBox.text
                leftPadding: Theme.scaled(8)
                rightPadding: Theme.scaled(8)
                topPadding: Theme.scaled(4)
                bottomPadding: Theme.scaled(4)
                textFormat: Text.PlainText
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.tooltip
                color: Theme.textHi
            }

            background: Rectangle {
                radius: Theme.chipRadius
                color: Theme.popBg
                border.width: 1
                border.color: Theme.stroke
            }
        }
    }
}
