import QtQuick
import "../Common"

// A catalogue app as a card: icon, name, category, summary, how it arrives
// (prebuilt or a vendor download) and its action. Opens the app's page.
Rectangle {
    id: root

    property var app: ({})

    implicitHeight: Theme.scaled(160)
    radius: Theme.chipRadius + 5
    color: Theme.cardFill
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Theme.accentText : Theme.hairlineSoft
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

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        rippleEnabled: false
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.openApp(root.app.id)
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.scaled(14)

        AppIcon {
            id: icon
            app: root.app
            size: Theme.scaled(44)
        }
        Column {
            anchors.left: icon.right
            anchors.leftMargin: Theme.scaled(10)
            anchors.right: parent.right
            anchors.verticalCenter: icon.verticalCenter
            spacing: Theme.scaled(1)
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
                text: Software.label(Software.subcategoryName(root.app) || (Software.category(root.app) || {}).name || "")
                color: Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        Text {
            anchors.top: icon.bottom
            anchors.topMargin: Theme.scaled(10)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: action.top
            anchors.bottomMargin: Theme.scaled(6)
            text: root.app.summary || ""
            color: Theme.textMid
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Tag {
            anchors.left: parent.left
            anchors.verticalCenter: action.verticalCenter
            tone: root.app.free === false ? "vendor" : "ok"
            glyph: root.app.free === false ? "download" : "bolt"
            text: root.app.free === false ? I18n.tr("Vendor download") : I18n.tr("Prebuilt")
        }
        AppAction {
            id: action
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            app: root.app
        }
    }
}
