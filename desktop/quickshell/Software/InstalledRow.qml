import QtQuick
import "../Common"

// An installed app or package: who it came from and what can be done here.
// Software's own choices can be removed; everything can be opened.
Rectangle {
    id: root

    // From SoftwareHelpers.installedGroups().
    property var row: ({})
    readonly property var app: row.app || null
    readonly property string queuedAction: Software.queued(row.attribute || "")
    readonly property bool removable: row.owner === "software" && (row.attribute || "") !== ""
    readonly property bool openable: app ? Software.canOpenApp(app)
        : (row.desktopIds || []).length > 0 && Software.canOpen(row.desktopIds, row.name)

    implicitHeight: Theme.scaled(56)
    radius: Theme.chipRadius + 3
    color: Theme.cardFill
    border.width: activeFocus ? 2 : 0
    border.color: Theme.accentText
    activeFocusOnTab: app !== null
    Accessible.role: app !== null ? Accessible.Button : Accessible.ListItem
    Accessible.name: row.name || ""
    Accessible.onPressAction: {
        if (root.app)
            Software.openApp(root.app.id);
    }
    Keys.onPressed: event => {
        if (root.app && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            Software.openApp(root.app.id);
            event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        visible: root.app !== null
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        rippleEnabled: false
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.app !== null
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.openApp(root.app.id)
    }

    AppIcon {
        id: icon
        x: Theme.scaled(12)
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        icon: root.row.icon || ""
        size: Theme.scaled(36)
    }
    Column {
        anchors.left: icon.right
        anchors.leftMargin: Theme.scaled(12)
        anchors.right: buttons.left
        anchors.rightMargin: Theme.scaled(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(1)
        Text {
            width: parent.width
            text: root.row.name || ""
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.primary
            font.weight: Theme.weightBold
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            text: {
                const how = root.app ? (root.app.free === false ? I18n.tr("Vendor download") : I18n.tr("Prebuilt by NixOS"))
                    : (root.row.description || "");
                const where = root.app ? Software.label(Software.subcategoryName(root.app) || (Software.category(root.app) || {}).name || "") : "";
                return [how, where, root.row.version || ""].filter(part => part !== "").join(" · ");
            }
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(8)
        SoftwareButton {
            objectName: "softwareInstalledRemove"
            visible: root.removable
            quiet: root.queuedAction !== "remove"
            queued: root.queuedAction === "remove"
            glyph: queued ? "check" : ""
            text: root.queuedAction === "remove" ? I18n.tr("Will be removed") : I18n.tr("Remove")
            accessibleName: root.queuedAction === "remove" ? I18n.format("Keep %1", [root.row.name || ""])
                : I18n.format("Remove %1", [root.row.name || ""])
            onTriggered: Software.toggleRemove(root.row.attribute)
        }
        SoftwareButton {
            visible: (root.row.desktopIds || []).length > 0
            enabled: root.openable
            text: I18n.tr("Open")
            accessibleName: I18n.format("Open %1", [root.row.name || ""])
            onTriggered: {
                if (root.app)
                    Software.openApplication(root.app);
                else
                    Software.launch(root.row.desktopIds, root.row.name);
            }
        }
    }
}
