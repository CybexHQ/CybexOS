import QtQuick
import "../Common"

// An uppercase group label in a list, with a quiet count or note.
Item {
    id: root

    property string text: ""
    property string detail: ""

    implicitHeight: label.implicitHeight + Theme.scaled(14)

    Text {
        id: label
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.scaled(4)
        text: root.text
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
        font.weight: Theme.weightSemibold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        textFormat: Text.PlainText
        Accessible.role: Accessible.Heading
        Accessible.name: root.text
    }
    Text {
        anchors.right: parent.right
        anchors.baseline: label.baseline
        text: root.detail
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
        textFormat: Text.PlainText
    }
}
