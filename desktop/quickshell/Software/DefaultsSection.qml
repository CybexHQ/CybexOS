pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// The top of Software's home: the apps doing each everyday job, chosen by
// Cybex OS until you choose another. A card opens the job's picker.
Column {
    id: root

    objectName: "softwareDefaults"
    spacing: Theme.scaled(10)
    Component.onCompleted: DefaultApplications.refresh()

    SectionTitle {
        width: parent.width
        text: I18n.tr("Your default apps")
        detail: Software.changedRoles.length > 0 ? "" : I18n.tr("Applies to your account only")
        link: Software.changedRoles.length > 0 ? I18n.tr("Reset to Cybex picks") : ""
        onLinkClicked: Software.resetDefaults()
    }
    Text {
        width: Math.min(parent.width, Theme.scaled(760))
        text: I18n.tr("Cybex OS picked these for you. Change any of them: Software installs what's needed and switches over, and your shortcuts follow.")
        color: Theme.textMid
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    Grid {
        id: grid
        width: parent.width
        columns: Math.min(5, Helpers.columns(width, Theme.scaled(172), Theme.scaled(10)))
        spacing: Theme.scaled(10)
        Repeater {
            model: Software.roles
            delegate: DefaultCard {
                required property var modelData
                width: (grid.width - grid.spacing * (grid.columns - 1)) / grid.columns
                role: modelData
            }
        }
    }
}
