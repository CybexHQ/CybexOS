import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// An Editor's choice: the app's artwork with its name and action. A
// screenshot appears once the app's page has loaded it this session.
Item {
    id: root

    property var app: ({})
    readonly property color base: Helpers.brand(app, Software.category(app), Theme.dark)
    readonly property string shot: Software.shownScreenshot(app)
    readonly property bool darkText: shot !== "" ? !Theme.dark : Helpers.darkInk(base.toString())
    readonly property color ink: shot !== "" ? Theme.textHi : darkText ? "#1d1b26" : "#f7f5f0"
    readonly property real corner: Theme.chipRadius + 5

    implicitHeight: Theme.scaled(172)
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
        radius: root.corner
        border.width: 1
        border.color: Theme.hairlineSoft
        gradient: Gradient {
            GradientStop { position: 0; color: Helpers.mix(root.base.toString(), root.darkText ? "#ffffff" : "#000000", 0.16) }
            GradientStop { position: 1; color: root.base }
        }
    }
    AppIcon {
        visible: root.shot === ""
        app: root.app
        size: Theme.scaled(92)
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(18)
        y: Theme.scaled(16)
    }
    MediaFrame {
        anchors.fill: parent
        visible: root.shot !== ""
        radius: root.corner
        source: root.shot
        sourceWidth: 720
        fade: true
    }

    StateLayer {
        anchors.fill: parent
        radius: root.corner
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        rippleEnabled: false
        tint: root.ink
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.openApp(root.app.id)
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.scaled(14)
        height: Theme.scaled(40)
        AppIcon {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            size: Theme.scaled(38)
        }
        Column {
            anchors.left: icon.right
            anchors.leftMargin: Theme.scaled(10)
            anchors.right: action.left
            anchors.rightMargin: Theme.scaled(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(1)
            Text {
                width: parent.width
                text: root.app.name || ""
                color: root.ink
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                text: root.app.summary || ""
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.78)
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        AppAction {
            id: action
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            foreground: root.shot !== "" ? "transparent" : root.ink
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.activeFocus
        color: "transparent"
        radius: root.corner
        border.width: 2
        border.color: Theme.accentText
    }
}
