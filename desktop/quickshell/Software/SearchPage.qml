pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// Search: catalogue apps by name, summary, developer and category first,
// then sandboxed apps from Flathub, then "More packages" from the machine's
// full Nixpkgs package set.
PageScroll {
    id: root

    property bool allFlathub: false
    readonly property var flathubShown: allFlathub ? Software.flathubHits : Software.flathubHits.slice(0, 8)

    objectName: "softwareSearchPage"

    Connections {
        target: Software
        function onQueryChanged() { root.allFlathub = false; }
    }

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
        visible: Software.flathubOn
        text: I18n.tr("From Flathub")
        detail: Software.flathubHits.length === 1 ? I18n.tr("1 app") : Software.flathubHits.length > 1
            ? I18n.format("%1 apps", [Software.flathubHits.length]) : ""
    }
    Text {
        visible: Software.flathubOn
        width: parent.width
        text: I18n.tr("Sandboxed apps for your account, installed right away without a restart. They update separately from the system. Results come from flathub.org.")
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    Row {
        visible: Software.flathubOn && Software.flathubSearching && Software.flathubHits.length === 0
        spacing: Theme.scaled(8)
        Spinner {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.textDim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Searching Flathub…")
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            textFormat: Text.PlainText
        }
    }
    Text {
        objectName: "softwareFlathubSearchError"
        visible: Software.flathubOn && Software.flathubError !== "" && !Software.flathubSearching
        width: parent.width
        text: Software.flathubError
        color: Theme.redText
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    Text {
        visible: Software.flathubOn && !Software.flathubSearching && Software.flathubError === ""
            && Software.flathubQuery === Software.query.trim() && Software.flathubHits.length === 0
        width: parent.width
        text: I18n.tr("No other Flathub apps match.")
        color: Theme.textDim
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        textFormat: Text.PlainText
    }
    Grid {
        id: flathubGrid
        width: parent.width
        visible: Software.flathubOn && root.flathubShown.length > 0
        columns: Helpers.columns(width, Theme.scaled(300), Theme.scaled(12))
        columnSpacing: Theme.scaled(12)
        rowSpacing: Theme.scaled(2)
        Repeater {
            model: Software.flathubOn ? root.flathubShown : []
            delegate: FlathubRow {
                required property var modelData
                objectName: "softwareFlathubResult"
                width: (flathubGrid.width - flathubGrid.columnSpacing * (flathubGrid.columns - 1)) / flathubGrid.columns
                entry: modelData
            }
        }
    }
    SoftwareButton {
        objectName: "softwareFlathubMore"
        visible: Software.flathubOn && !root.allFlathub && Software.flathubHits.length > root.flathubShown.length
        quiet: true
        text: I18n.format("Show all %1 Flathub apps", [Software.flathubHits.length])
        onTriggered: root.allFlathub = true
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
