import QtQuick
import "../Common"
import "../Popovers" as Popovers

// A section's heading, with an optional link ("See all") on the right and an
// optional quiet button after it ("Show all 9").
Item {
    id: root

    property string text: ""
    property string detail: ""
    property string link: ""
    property string action: ""
    property string actionGlyph: ""
    property string actionName: ""
    property string actionAccessibleName: action
    signal linkClicked()
    signal actionTriggered()

    implicitHeight: Math.max(title.implicitHeight, more.implicitHeight, button.visible ? button.implicitHeight : 0)
        + Theme.scaled(6)

    Text {
        id: title
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        // A button beside the title sits on the same centre line, inside.
        anchors.bottomMargin: button.visible ? Math.max(0, (button.height - height) / 2) : 0
        anchors.right: side.left
        anchors.rightMargin: Theme.scaled(12)
        text: root.text
        color: Theme.textHi
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.title
        font.weight: Theme.weightBold
        elide: Text.ElideRight
        textFormat: Text.PlainText
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Row {
        id: side
        anchors.right: parent.right
        anchors.verticalCenter: title.verticalCenter
        spacing: Theme.scaled(12)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.detail !== ""
            text: root.detail
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            textFormat: Text.PlainText
        }
        Popovers.LinkText {
            id: more
            anchors.verticalCenter: parent.verticalCenter
            visible: root.link !== ""
            text: root.link
            font.pixelSize: Theme.typography.secondary
            onClicked: root.linkClicked()
        }
        SoftwareButton {
            id: button
            objectName: root.actionName
            anchors.verticalCenter: parent.verticalCenter
            visible: root.action !== ""
            quiet: true
            text: root.action
            glyph: root.actionGlyph
            accessibleName: root.actionAccessibleName
            onTriggered: root.actionTriggered()
        }
    }
}
