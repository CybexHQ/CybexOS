import QtQuick

// A small labelled notification button (Expand group, Dismiss group, the
// snooze choices). The chip keeps its compact height; its hit area reaches
// past it to at least a 32 px target, as SettingsAction's does.
Rectangle {
    id: root
    property string text: ""
    signal triggered()
    readonly property real hitInsetX: Math.min(0, (width - Theme.inlineActionHeight) / 2)
    readonly property real hitInsetY: Math.min(0, (height - Theme.inlineActionHeight) / 2)
    implicitWidth: label.implicitWidth + Theme.controlSpacing * 2
    implicitHeight: Math.max(Theme.chipHeight, label.implicitHeight + 10)
    radius: Theme.chipRadius
    color: hover.hovered || activeFocus ? Theme.hoverFillStrong : Theme.hoverFill
    border.width: Theme.focusWidth(activeFocus)
    border.color: Theme.focusRing
    activeFocusOnTab: visible && enabled
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (root.enabled) root.triggered()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.triggered();
            event.accepted = true;
        }
    }
    HoverHandler { id: hover }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        textFormat: Text.PlainText
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
        color: Theme.textMid
    }
    MouseArea {
        anchors.fill: parent
        anchors.leftMargin: root.hitInsetX
        anchors.rightMargin: root.hitInsetX
        anchors.topMargin: root.hitInsetY
        anchors.bottomMargin: root.hitInsetY
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.triggered();
        }
    }
}
