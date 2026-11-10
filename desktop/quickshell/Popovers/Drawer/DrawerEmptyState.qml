import QtQuick
import "../../Common"
import ".."

// The one way a drawer tab says why it has nothing to show (2026-11 UI
// council): a quiet glyph, the cause in one plain line, a sentence on what
// it means, and at most one action ("Turn on", "Sound settings"). Sound,
// Network, Bluetooth and Power use it alike for missing hardware, a radio
// that is turned off and a service that is not running, so the three never
// read differently from one tab to the next. Everything wraps; nothing is
// cut short at a larger text size.
Column {
    id: root

    property string glyph: "info"
    property string title: ""
    property string detail: ""
    property string actionText: ""
    signal action()

    width: parent ? parent.width : 0
    spacing: Theme.iconTextSpacing
    topPadding: Theme.scaled(8)
    bottomPadding: Theme.scaled(4)

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.iconLarge + Theme.scaled(20)
        height: width
        radius: width / 2
        color: Theme.chip
        Accessible.ignored: true

        Sym {
            anchors.centerIn: parent
            name: root.glyph
            size: Theme.iconLarge
            color: Theme.textMid
        }
    }

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.title
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.primary
        font.weight: Theme.weightSemibold
        color: Theme.textHi
        Accessible.role: Accessible.StaticText
        Accessible.name: root.title
        Accessible.description: root.detail
    }

    Text {
        visible: text !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.detail
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        color: Theme.textMid
        Accessible.ignored: true
    }

    // Secondary tier (docs/shell-states.md): chip and hairline, 32 px high.
    Item {
        visible: root.actionText !== ""
        width: parent.width
        height: actionButton.height + Theme.scaled(4)

        ActionButton {
            id: actionButton
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            label: root.actionText
            tint: Theme.textHi
            fill: Theme.chip
            hPadding: Theme.scaled(24)
            border.width: Theme.focusWidth(activeFocus) || 1
            border.color: Theme.focusWidth(activeFocus) > 0 ? Theme.focusRing : Theme.hairline
            onTriggered: root.action()
        }
    }
}
