pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../../Common"

// A short menu of labelled actions that opens above a button in the drawer's
// pinned session row (Power, More). It lives inside the drawer's own window
// and surface, so it needs no window of its own.
//
// Keyboard: the first entry takes focus as the menu opens, Up and Down move
// (wrapping), Home and End jump, Return, Enter or Space choose, and Escape
// closes it and hands focus back to the button that opened it. A press
// anywhere else closes it; pressing the button again toggles it.
Controls.Popup {
    id: root

    // [{ id, glyph, label }]
    property var entries: []
    // The button it hangs from; also where focus returns.
    property Item opener: null
    // Right edges aligned with the opener rather than left edges.
    property bool alignEnd: false
    property string accessibleName: ""
    signal chosen(string id)

    readonly property real rowPadding: Theme.scaled(10)
    // Reading the font ties the width to the text size as well.
    readonly property real labelWidth: entryMetrics.font.pixelSize > 0
        ? Math.ceil(entries.reduce((widest, entry) =>
            Math.max(widest, entryMetrics.advanceWidth(entry.label)), 0))
        : 0

    function toggle() {
        if (opened)
            close();
        else
            open();
    }

    function choose(id) {
        close();
        chosen(id);
    }

    function focusEntry(index) {
        const count = entries.length;
        if (count === 0)
            return;
        const item = entryRepeater.itemAt(((index % count) + count) % count);
        if (item)
            item.forceActiveFocus();
    }

    function dismiss() {
        close();
        if (opener && opener.visible)
            opener.forceActiveFocus();
    }

    parent: opener
    x: alignEnd && opener ? opener.width - width : 0
    y: -height - Theme.scaled(6)
    width: Math.max(opener ? opener.width : 0,
        leftPadding + rightPadding + rowPadding * 2 + Theme.iconMedium
            + Theme.iconTextSpacing + labelWidth)
    padding: Theme.scaled(4)
    modal: false
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent

    onOpened: Qt.callLater(() => {
        if (root.opened)
            root.focusEntry(0);
    })

    FontMetrics {
        id: entryMetrics
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.control
        font.weight: Theme.weightMedium
    }

    background: Rectangle {
        radius: 10
        color: Theme.menuBg
        border.width: 1
        border.color: Theme.hairline
    }

    contentItem: Column {
        spacing: Theme.scaled(2)
        Accessible.role: Accessible.PopupMenu
        Accessible.name: root.accessibleName

        Repeater {
            id: entryRepeater
            model: root.entries

            delegate: Rectangle {
                id: entry

                required property var modelData
                required property int index

                width: parent ? parent.width : 0
                height: Math.max(Theme.inlineActionHeight, entryLabel.implicitHeight + Theme.scaled(10))
                radius: Theme.rowRadius
                color: "transparent"
                border.width: Theme.focusWidth(activeFocus)
                border.color: Theme.focusRing
                activeFocusOnTab: true
                Accessible.role: Accessible.MenuItem
                Accessible.name: modelData.label
                Accessible.onPressAction: root.choose(entry.modelData.id)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Down) root.focusEntry(index + 1);
                    else if (event.key === Qt.Key_Up) root.focusEntry(index - 1);
                    else if (event.key === Qt.Key_Home) root.focusEntry(0);
                    else if (event.key === Qt.Key_End) root.focusEntry(root.entries.length - 1);
                    else if (event.key === Qt.Key_Escape) root.dismiss();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) root.choose(entry.modelData.id);
                    else return;
                    event.accepted = true;
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    hovered: entryMouse.containsMouse
                    pressed: entryMouse.pressed
                    tint: Theme.textHi
                    pressPoint: Qt.point(entryMouse.mouseX, entryMouse.mouseY)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: root.rowPadding
                    anchors.right: parent.right
                    anchors.rightMargin: root.rowPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.iconTextSpacing

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: entry.modelData.glyph
                        size: Theme.iconMedium
                        color: entryMouse.containsMouse ? Theme.textHi : Theme.textMid
                    }

                    Text {
                        id: entryLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.control
                        font.weight: Theme.weightMedium
                        color: Theme.textHi
                        Accessible.ignored: true
                    }
                }

                MouseArea {
                    id: entryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(entry.modelData.id)
                }
            }
        }
    }
}
