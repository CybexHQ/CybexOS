pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// What is on this computer, by who put it there: apps added in Software
// (removable here), apps included with Cybex OS, apps from the machine's own
// configuration (read-only here). Packages without an app follow, folded.
PageScroll {
    id: root

    readonly property var groups: Software.installedGroups
    property bool showOther: false

    objectName: "softwareInstalledPage"
    spacing: Theme.scaled(8)

    Notice {
        width: parent.width
        glyph: "shield-lock"
        text: I18n.tr("Every change is a checked system update. Your previous system stays available as a fallback if something goes wrong.")
    }
    Notice {
        width: parent.width
        visible: Software.catalogue.configurationChanged === true
        glyph: "info-circle"
        text: I18n.tr("Your app choices differ from what is installed. The next change you install includes them.")
    }

    GroupLabel {
        width: parent.width
        text: I18n.tr("Added by you")
        detail: root.groups.software.length === 1 ? I18n.tr("1 app") : I18n.format("%1 apps", [root.groups.software.length])
    }
    Text {
        visible: root.groups.software.length === 0
        width: parent.width
        text: I18n.tr("Apps you install in Software appear here. You can remove them here too.")
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    Repeater {
        model: root.groups.software
        delegate: InstalledRow {
            required property var modelData
            objectName: "softwareInstalledMine"
            width: root.innerWidth
            row: modelData
        }
    }

    GroupLabel {
        width: parent.width
        visible: root.groups.cybexos.length > 0
        text: I18n.tr("Included with Cybex OS")
        detail: I18n.tr("Updated with the system")
    }
    Repeater {
        model: root.groups.cybexos
        delegate: InstalledRow {
            required property var modelData
            objectName: "softwareInstalledVendor"
            width: root.innerWidth
            row: modelData
        }
    }

    GroupLabel {
        width: parent.width
        visible: root.groups.personal.length > 0
        text: I18n.tr("From your configuration")
        detail: I18n.tr("Change these in /etc/nixos")
    }
    Repeater {
        model: root.groups.personal
        delegate: InstalledRow {
            required property var modelData
            objectName: "softwareInstalledPersonal"
            width: root.innerWidth
            row: modelData
        }
    }

    Item {
        width: parent.width
        height: Theme.scaled(8)
    }
    Rectangle {
        objectName: "softwareOtherPackages"
        width: parent.width
        visible: root.groups.other.length > 0
        height: Theme.scaled(44)
        radius: Theme.chipRadius + 3
        color: otherMouse.containsMouse ? Theme.hoverFill : "transparent"
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? Theme.accentText : Theme.hairlineSoft
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("Other packages")
        Accessible.onPressAction: root.showOther = !root.showOther
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.showOther = !root.showOther;
                event.accepted = true;
            }
        }
        Sym {
            id: chevron
            x: Theme.scaled(14)
            anchors.verticalCenter: parent.verticalCenter
            name: root.showOther ? "chevron-down" : "chevron-right"
            size: Theme.iconMedium
            color: Theme.textMid
        }
        Text {
            anchors.left: chevron.right
            anchors.leftMargin: Theme.scaled(10)
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Other packages")
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.primary
            font.weight: Theme.weightSemibold
            textFormat: Text.PlainText
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(14)
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.format("%1 command-line tools, libraries and services", [root.groups.other.length])
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            textFormat: Text.PlainText
        }
        MouseArea {
            id: otherMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.showOther = !root.showOther
        }
    }
    Repeater {
        model: root.showOther ? root.groups.other : []
        delegate: InstalledRow {
            required property var modelData
            objectName: "softwareInstalledOther"
            width: root.innerWidth
            implicitHeight: Theme.scaled(46)
            row: modelData
        }
    }
}
