import QtQuick
import "../Common"
import "../Popovers" as Popovers

// One line of an app's facts: what, and its value; a value can carry a
// package attribute in the instrument face, or be a link.
Item {
    id: root

    property string label: ""
    property string value: ""
    property string code: ""
    property string link: ""
    property bool divider: true
    signal linkClicked()

    readonly property real room: Math.max(0, width - name.implicitWidth - Theme.scaled(16))
    implicitHeight: Math.max(name.implicitHeight, values.implicitHeight) + Theme.scaled(16)

    Rectangle {
        visible: root.divider
        width: parent.width
        height: 1
        color: Theme.hairlineSoft
    }
    Text {
        id: name
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        textFormat: Text.PlainText
    }
    Row {
        id: values
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(6)
        Text {
            visible: root.value !== "" && root.link === ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.room - (codeChip.visible ? codeChip.width + values.spacing : 0))
            text: root.value
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
        }
        Popovers.LinkText {
            visible: root.link !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            font.pixelSize: Theme.typography.secondary
            onClicked: root.linkClicked()
        }
        Rectangle {
            id: codeChip
            visible: root.code !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(codeText.implicitWidth + Theme.scaled(10), root.room)
            height: codeText.implicitHeight + Theme.scaled(4)
            radius: Theme.chipRadius - 3
            color: Theme.chip
            Text {
                id: codeText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - Theme.scaled(10))
                text: root.code
                color: Theme.textMid
                font.family: Theme.fontMono
                font.pixelSize: Theme.typography.metadata
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
        }
    }
}
