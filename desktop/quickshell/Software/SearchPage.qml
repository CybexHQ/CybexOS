pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// Search: catalogue apps by name, summary, developer and category first,
// then "More packages" from the machine's full Nixpkgs package set.
PageScroll {
    id: root

    objectName: "softwareSearchPage"

    SectionTitle {
        width: parent.width
        visible: Software.appResults.length > 0
        text: I18n.tr("Apps")
        detail: Software.appResults.length === 1 ? I18n.tr("1 app") : I18n.format("%1 apps", [Software.appResults.length])
    }
    Grid {
        id: grid
        width: parent.width
        visible: Software.appResults.length > 0
        columns: Helpers.columns(width, Theme.scaled(300), Theme.scaled(12))
        columnSpacing: Theme.scaled(12)
        rowSpacing: Theme.scaled(2)
        Repeater {
            model: Software.appResults
            delegate: AppRow {
                required property var modelData
                objectName: "softwareSearchApp"
                width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
                app: modelData
            }
        }
    }
    Text {
        visible: Software.appResults.length === 0
        width: parent.width
        text: I18n.format("No apps in the catalogue match “%1”.", [Software.query.trim()])
        color: Theme.textMid
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.primary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    SectionTitle {
        width: parent.width
        text: I18n.tr("More packages")
        detail: Software.morePackages.length > 0 && Software.moreTotal > Software.moreResults.length
            ? I18n.format("Showing %1 of %2", [Software.morePackages.length, Software.moreTotal]) : ""
    }
    Text {
        width: parent.width
        text: I18n.tr("Everything else in NixOS: command-line tools, libraries and other apps. Each is checked before you can install it, so nothing compiles.")
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    Row {
        visible: Software.moreBusy && Software.morePackages.length === 0
        spacing: Theme.scaled(8)
        Spinner {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.textDim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Searching NixOS packages… The first search takes a minute while the list is built.")
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            textFormat: Text.PlainText
        }
    }
    Text {
        visible: Software.moreError !== "" && !Software.moreBusy
        width: parent.width
        text: Software.moreError
        color: Theme.redText
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    Text {
        visible: !Software.moreBusy && Software.moreError === "" && Software.moreQuery === Software.query.trim()
            && Software.morePackages.length === 0
        width: parent.width
        text: I18n.tr("No other packages match.")
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        textFormat: Text.PlainText
    }
    Repeater {
        model: Software.morePackages
        delegate: PackageRow {
            required property var modelData
            objectName: "softwarePackageResult"
            width: root.innerWidth
            result: modelData
        }
    }
}
