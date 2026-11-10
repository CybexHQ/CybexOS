pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// The apps doing each everyday job, chosen by Cybex OS until you choose
// another. It sits under Explore's featured apps as one compact row, so
// discovery leads; "Show all" opens every job. A card opens the job's picker.
Column {
    id: root

    // Every job, or only the row that fits.
    property bool expanded: false
    readonly property int columns: Math.min(5, Helpers.columns(width, Theme.scaled(172), Theme.scaled(10)))
    readonly property int total: Software.roles.length
    readonly property bool folds: total > columns

    objectName: "softwareDefaults"
    spacing: Theme.scaled(10)
    Component.onCompleted: DefaultApplications.refresh()

    SectionTitle {
        width: parent.width
        text: I18n.tr("Your default apps")
        detail: Software.changedRoles.length > 0 ? "" : I18n.tr("Applies to your account only")
        link: Software.changedRoles.length > 0 ? I18n.tr("Reset to Cybex picks") : ""
        action: !root.folds ? "" : root.expanded ? I18n.tr("Show fewer") : I18n.format("Show all %1", [root.total])
        actionGlyph: root.expanded ? "chevron-up" : "chevron-down"
        actionName: "softwareDefaultsMore"
        actionAccessibleName: root.expanded ? I18n.tr("Show fewer default apps") : I18n.tr("Show all default apps")
        onLinkClicked: Software.resetDefaults()
        onActionTriggered: root.expanded = !root.expanded
    }
    Text {
        visible: root.expanded || !root.folds
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
        columns: root.columns
        spacing: Theme.scaled(10)
        Repeater {
            model: root.expanded ? Software.roles : Software.roles.slice(0, root.columns)
            delegate: DefaultCard {
                required property var modelData
                width: (grid.width - grid.spacing * (grid.columns - 1)) / grid.columns
                role: modelData
            }
        }
    }
}
