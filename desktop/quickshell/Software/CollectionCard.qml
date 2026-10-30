pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers
import "../Common/TablerGlyphs.js" as Tabler

// An installer profile as a collection: its apps, what installing the
// missing ones downloads, and one action that adds them all to the list.
Rectangle {
    id: root

    property var profile: ({})
    readonly property var summary: Helpers.collection(profile, Software.appsById)
    readonly property int waiting: summary.missing.filter(app => Software.queued(app.attribute) === "install").length
    readonly property bool allAdded: summary.missing.length > 0 && waiting === summary.missing.length

    implicitHeight: Theme.scaled(132)
    radius: Theme.chipRadius + 5
    color: Theme.cardFill
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Theme.accentText : Theme.hairlineSoft
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: Software.label(profile.name || "")
    Accessible.onPressAction: Software.openCollection(profile.id)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            Software.openCollection(root.profile.id);
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
        onClicked: Software.openCollection(root.profile.id)
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.scaled(14)

        Rectangle {
            id: badge
            width: Theme.scaled(36)
            height: width
            radius: Theme.chipRadius + 2
            color: Theme.accentAlpha(0.14)
            Sym {
                anchors.centerIn: parent
                name: Helpers.glyph(root.profile.icon, Tabler.has)
                size: Theme.iconLarge
                color: Theme.accentText
            }
        }
        Column {
            anchors.left: badge.right
            anchors.leftMargin: Theme.scaled(12)
            anchors.right: parent.right
            anchors.verticalCenter: badge.verticalCenter
            spacing: Theme.scaled(1)
            Text {
                width: parent.width
                text: Software.label(root.profile.name || "")
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
                    const count = root.summary.apps.length;
                    const apps = count === 1 ? I18n.tr("1 app") : I18n.format("%1 apps", [count]);
                    const size = Helpers.size(root.summary.downloadBytes);
                    return root.summary.missing.length === 0 ? I18n.format("%1 · all installed", [apps])
                        : size !== "" ? I18n.format("%1 · ≈ %2 to download", [apps, size]) : apps;
                }
                color: Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        Row {
            id: stack
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.scaled(2)
            spacing: -Theme.scaled(8)
            Repeater {
                model: root.summary.apps.slice(0, 6)
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    width: Theme.scaled(34)
                    height: width
                    radius: width / 2
                    color: Theme.panelSurface
                    border.width: 1
                    border.color: Theme.hairlineSoft
                    AppIcon {
                        anchors.centerIn: parent
                        app: chip.modelData
                        size: Theme.scaled(26)
                    }
                }
            }
        }
        SoftwareButton {
            objectName: "softwareCollectionInstall"
            anchors.right: parent.right
            anchors.verticalCenter: stack.verticalCenter
            visible: root.summary.missing.length > 0
            queued: root.allAdded
            glyph: root.allAdded ? "check" : "plus"
            text: root.allAdded ? I18n.tr("Added") : I18n.tr("Install all")
            enabled: !root.allAdded
            accessibleName: I18n.format("Install all of %1", [Software.label(root.profile.name || "")])
            onTriggered: Software.installAll(root.profile.id)
        }
    }
}
