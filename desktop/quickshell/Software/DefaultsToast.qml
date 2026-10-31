import QtQuick
import "../Common"

// What just changed about a job, with Undo: an app took over (at once, or
// once it finished installing), or the jobs went back to Cybex OS's picks.
Rectangle {
    id: root

    readonly property var notice: Software.defaultsNotice
    readonly property string roleId: notice && notice.roles.length > 0 ? notice.roles[0] : ""
    readonly property var card: Software.roleCard(roleId)

    objectName: "softwareDefaultsToast"
    visible: notice !== null
    implicitWidth: row.implicitWidth + Theme.scaled(22)
    implicitHeight: row.implicitHeight + Theme.scaled(18)
    radius: Theme.chipRadius + 6
    color: Theme.surfaceStrong
    border.width: 1
    border.color: Theme.hairline
    Accessible.role: Accessible.AlertMessage
    Accessible.name: title.text

    Timer {
        interval: 9000
        running: root.notice !== null
        onTriggered: Software.defaultsNotice = null
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.scaled(12)
        RoleIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.notice !== null && !root.notice.reset
            option: root.card.option
            desktop: root.card.desktop
            size: Theme.scaled(30)
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(1)
            Text {
                id: title
                objectName: "softwareDefaultsToastTitle"
                text: !root.notice ? "" : root.notice.reset ? I18n.tr("Back to Cybex OS's picks")
                    : I18n.format("%1 is now your %2", [root.notice.name, Software.roleWord(root.roleId, "noun")])
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                textFormat: Text.PlainText
            }
            Text {
                text: !root.notice ? "" : root.notice.reset ? I18n.tr("Apps you installed stay installed.")
                    : Software.roleWord(root.roleId, "after")
                color: Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                textFormat: Text.PlainText
            }
        }
        SoftwareButton {
            objectName: "softwareDefaultsUndo"
            anchors.verticalCenter: parent.verticalCenter
            glyph: "arrow-back-up"
            text: I18n.tr("Undo")
            onTriggered: Software.undoDefaults()
        }
    }
}
