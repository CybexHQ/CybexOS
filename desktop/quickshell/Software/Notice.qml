import QtQuick
import "../Common"

// A calm, accent-tinted explanation with an optional action.
Rectangle {
    id: root

    property string glyph: "info-circle"
    property string title: ""
    property string text: ""
    property string action: ""
    property bool actionPrimary: true
    property bool busy: false
    property string actionName: "softwareNoticeAction"
    signal triggered()

    implicitHeight: Math.max(copy.implicitHeight, button.visible ? button.implicitHeight : 0) + Theme.scaled(24)
    radius: Theme.chipRadius + 5
    color: Theme.accentAlpha(Theme.dark ? 0.08 : 0.07)
    border.width: 1
    border.color: Theme.accentAlpha(0.28)

    Sym {
        id: icon
        x: Theme.scaled(14)
        anchors.verticalCenter: parent.verticalCenter
        name: root.glyph
        size: Theme.iconLarge
        color: Theme.accentText
    }
    Column {
        id: copy
        anchors.left: icon.right
        anchors.leftMargin: Theme.scaled(12)
        anchors.right: button.visible ? button.left : parent.right
        anchors.rightMargin: Theme.scaled(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(2)
        Text {
            width: parent.width
            visible: root.title !== ""
            text: root.title
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.primary
            font.weight: Theme.weightSemibold
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            visible: root.text !== ""
            text: root.text
            color: Theme.textMid
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            lineHeight: 1.1
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }
    SoftwareButton {
        id: button
        objectName: root.actionName
        visible: root.action !== ""
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(12)
        anchors.verticalCenter: parent.verticalCenter
        big: true
        busy: root.busy
        primary: root.actionPrimary
        text: root.action
        onTriggered: root.triggered()
    }
}
