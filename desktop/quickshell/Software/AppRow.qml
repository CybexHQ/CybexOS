import QtQuick
import "../Common"

// A catalogue app in a list: icon, name, one line of summary, its action.
Item {
    id: root

    property var app: ({})
    property bool showAction: true

    implicitHeight: Theme.scaled(64)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.app.name || ""
    Accessible.description: root.app.summary || ""
    Accessible.onPressAction: Software.openApp(root.app.id)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            Software.openApp(root.app.id);
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
        onClicked: Software.openApp(root.app.id)
    }

    AppIcon {
        id: icon
        x: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        size: Theme.scaled(44)
    }
    Column {
        anchors.left: icon.right
        anchors.leftMargin: Theme.scaled(12)
        anchors.right: action.visible ? action.left : parent.right
        anchors.rightMargin: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(2)
        Text {
            width: parent.width
            text: root.app.name || ""
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.primary
            font.weight: Theme.weightBold
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            text: root.app.summary || ""
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
    AppAction {
        id: action
        visible: root.showAction && action.mode !== "none"
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
    }
}
