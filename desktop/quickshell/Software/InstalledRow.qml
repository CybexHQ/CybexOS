import QtQuick
import "../Common"

// An installed app or package: who it came from and what can be done here.
// Software's own choices and this account's Flathub apps can be removed;
// everything can be opened.
Rectangle {
    id: root

    // From SoftwareHelpers.installedGroups() or flathubInstalledRows().
    property var row: ({})
    readonly property var app: row.app || null
    readonly property var flatpak: row.flatpak || null
    readonly property bool clickable: app !== null || flatpak !== null
    readonly property string queuedAction: Software.queued(row.attribute || "")
    readonly property string flathubMode: flatpak ? Software.flathubMode({ id: flatpak.id }) : ""
    readonly property bool removable: flatpak ? flatpak.installation === "user"
        : row.owner === "software" && (row.attribute || "") !== ""
    readonly property bool openable: flatpak ? true : app ? Software.canOpenApp(app)
        : (row.desktopIds || []).length > 0 && Software.canOpen(row.desktopIds, row.name)
    property bool confirmRemove: false

    function openPage() {
        if (root.flatpak)
            Software.openFlathub(root.flatpak.id, { name: root.row.name });
        else if (root.app)
            Software.openApp(root.app.id);
    }

    implicitHeight: Theme.scaled(56)
    radius: Theme.chipRadius + 3
    color: Theme.cardFill
    border.width: activeFocus ? 2 : 0
    border.color: Theme.accentText
    activeFocusOnTab: clickable
    Accessible.role: clickable ? Accessible.Button : Accessible.ListItem
    Accessible.name: row.name || ""
    Accessible.onPressAction: root.openPage()
    Keys.onPressed: event => {
        if (root.clickable && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.openPage();
            event.accepted = true;
        }
    }

    Timer {
        id: confirmTimeout
        interval: 4000
        onTriggered: root.confirmRemove = false
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        visible: root.clickable
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        rippleEnabled: false
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openPage()
    }

    AppIcon {
        id: icon
        x: Theme.scaled(12)
        anchors.verticalCenter: parent.verticalCenter
        app: root.app || root.row.catalogue || null
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
                if (root.flatpak)
                    return [root.flatpak.installation === "user" ? I18n.tr("Flathub · for you") : I18n.tr("Flathub · for everyone"),
                        root.row.version || ""].filter(part => part !== "").join(" · ");
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
            visible: root.removable && !root.flatpak
            quiet: root.queuedAction !== "remove"
            queued: root.queuedAction === "remove"
            glyph: queued ? "check" : ""
            text: root.queuedAction === "remove" ? I18n.tr("Will be removed") : I18n.tr("Remove")
            accessibleName: root.queuedAction === "remove" ? I18n.format("Keep %1", [root.row.name || ""])
                : I18n.format("Remove %1", [root.row.name || ""])
            onTriggered: Software.toggleRemove(root.row.attribute)
        }
        // A Flathub app goes right away, so the first press asks again.
        SoftwareButton {
            objectName: "softwareInstalledFlathubRemove"
            visible: root.removable && root.flatpak !== null
            quiet: !root.confirmRemove
            busy: root.flathubMode === "removing"
            enabled: !Software.flathubBusy
            text: root.flathubMode === "removing" ? I18n.tr("Removing…")
                : root.confirmRemove ? I18n.tr("Remove now") : I18n.tr("Remove")
            accessibleName: root.confirmRemove ? I18n.format("Confirm removing %1", [root.row.name || ""])
                : I18n.format("Remove %1", [root.row.name || ""])
            onTriggered: {
                if (!root.confirmRemove) {
                    root.confirmRemove = true;
                    confirmTimeout.restart();
                    return;
                }
                root.confirmRemove = false;
                Software.removeFlathub(root.flatpak.id, root.row.name);
            }
        }
        SoftwareButton {
            visible: (root.row.desktopIds || []).length > 0 || root.flatpak !== null
            enabled: root.openable && root.flathubMode !== "removing"
            text: I18n.tr("Open")
            accessibleName: I18n.format("Open %1", [root.row.name || ""])
            onTriggered: {
                if (root.flatpak)
                    Software.launchFlathub(root.flatpak.id, root.row.name);
                else if (root.app)
                    Software.openApplication(root.app);
                else
                    Software.launch(root.row.desktopIds, root.row.name);
            }
        }
    }
}
