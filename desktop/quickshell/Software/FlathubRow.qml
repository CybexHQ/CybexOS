import QtQuick
import "../Common"

// A Flathub search result: its icon from Flathub, name, developer and
// summary, whether Flathub verified the developer, and its action.
Item {
    id: root

    property var entry: ({})

    implicitHeight: Theme.scaled(64)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.entry.name || ""
    Accessible.description: root.entry.summary || ""
    Accessible.onPressAction: Software.openFlathub(root.entry.id, root.entry)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            Software.openFlathub(root.entry.id, root.entry);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.chipRadius + 3
        color: mouse.containsMouse || root.activeFocus ? Theme.cardFill : "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.accentText
        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.openFlathub(root.entry.id, root.entry)
    }

    AppIcon {
        id: icon
        x: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        url: root.entry.icon || ""
        size: Theme.scaled(44)
    }
    Column {
        anchors.left: icon.right
        anchors.leftMargin: Theme.scaled(12)
        anchors.right: action.left
        anchors.rightMargin: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(2)
        Row {
            width: parent.width
            spacing: Theme.scaled(5)
            Text {
                id: title
                width: Math.min(implicitWidth, parent.width - (verified.visible ? verified.width + parent.spacing : 0))
                text: root.entry.name || ""
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Sym {
                id: verified
                anchors.verticalCenter: title.verticalCenter
                visible: root.entry.verified === true
                name: "circle-check"
                size: Theme.iconTiny
                color: Theme.accentText
                Accessible.role: Accessible.StaticText
                Accessible.name: I18n.tr("Verified by Flathub")
            }
        }
        Text {
            width: parent.width
            text: root.entry.summary || ""
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
    FlathubAction {
        id: action
        objectName: "softwareFlathubAction"
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        entry: root.entry
    }
}
