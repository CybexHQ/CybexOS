import QtQuick
import QtQuick.Controls as Controls
import "../../Common"

// One quick-toggle tile in the Overview grid: glyph over label. A tile that
// is on wears the shared selected-tile state (docs/shell-states.md): the
// accent tint, a 2 px accent border and an accent glyph, so "on" never reads
// as the hover chip. Off keeps the quiet chip. typography.test.cjs lists this
// file among the switch tracks allowed an accent field.
Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    // What the short label means, for the tooltip and assistive technology
    // ("Focus" silences notifications).
    property string description: ""
    property bool on: false
    signal toggled()

    height: Math.max(Theme.scaled(60), tileContent.implicitHeight + Theme.controlSpacing * 2)
    radius: 10
    color: on ? Theme.selectedFill : Theme.chip
    activeFocusOnTab: true
    border.width: on ? Theme.selectedBorderWidth : 0
    border.color: Theme.selectedMark
    Accessible.role: Accessible.CheckBox
    Accessible.checked: on
    Accessible.name: label
    Accessible.description: description
    Accessible.onToggleAction: root.toggled()
    Controls.ToolTip.visible: description !== "" && tileMouse.containsMouse
    Controls.ToolTip.delay: 600
    Controls.ToolTip.text: description

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.toggled();
            event.accepted = true;
        }
    }

    Column {
        id: tileContent
        anchors.centerIn: parent
        width: Math.max(0, parent.width - Theme.controlSpacing * 2)
        spacing: Theme.iconTextSpacing

        Sym {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.glyph
            size: Theme.iconLarge
            color: root.on ? Theme.accentText : Theme.textMid
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.label
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            font.weight: root.on ? Theme.weightSemibold : Theme.weightMedium
            color: root.on ? Theme.textHi : Theme.textMid
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: tileMouse.containsMouse
        pressed: tileMouse.pressed
        tint: Theme.textHi
        pressPoint: Qt.point(tileMouse.mouseX, tileMouse.mouseY)
    }

    // The keyboard ring sits inside the selected border rather than on it:
    // both are accent marks, and a ring drawn over the border would vanish.
    Rectangle {
        readonly property real inset: root.on ? Theme.selectedBorderWidth + 2 : 0
        anchors.fill: parent
        anchors.margins: inset
        radius: Math.max(0, root.radius - inset)
        color: "transparent"
        border.width: Theme.focusWidth(root.activeFocus)
        border.color: Theme.focusRing
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.toggled();
        }
    }
}
