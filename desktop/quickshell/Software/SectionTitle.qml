import QtQuick
import "../Common"
import "../Popovers" as Popovers

// A section's heading, with an optional link ("See all") on the right.
Item {
    id: root

    property string text: ""
    property string detail: ""
    property string link: ""
    signal linkClicked()

    implicitHeight: Math.max(title.implicitHeight, more.implicitHeight) + Theme.scaled(6)

    Text {
        id: title
        anchors.left: parent.left
        anchors.bottom: parent.bottom
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
            visible: root.detail !== ""
            text: root.detail
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            textFormat: Text.PlainText
        }
        Popovers.LinkText {
            id: more
            visible: root.link !== ""
            text: root.link
            font.pixelSize: Theme.typography.secondary
            onClicked: root.linkClicked()
        }
    }
}
