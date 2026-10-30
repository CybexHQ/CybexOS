pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/ExternalUrl.js" as ExternalUrl
import "../Common/SoftwareHelpers.js" as Helpers

// One app: who makes it, how it arrives (prebuilt by NixOS or a vendor
// download), what installing it downloads, screenshots from Flathub, what
// it does, the facts, and similar apps. Install adds it to the list.
PageScroll {
    id: root

    property var app: ({})
    readonly property var verdict: Software.checks[app.attribute] || null
    readonly property bool vendor: app.free === false
    readonly property string queuedAction: Software.queued(app.attribute || "")
    readonly property var shots: Helpers.screenshots(app)
    readonly property int loadedShots: shotTiles.loaded
    readonly property int failedShots: shotTiles.failed
    readonly property string licence: Helpers.license(app.license)
    readonly property bool removable: app.installed === true && app.owner === "software"
    readonly property bool wide: innerWidth >= Theme.scaled(700)

    objectName: "softwareAppPage"
    Component.onCompleted: Software.requestCheck(app.attribute || "")

    function downloadLine() {
        if (app.installed) {
            return app.owner === "software" ? I18n.tr("Added by you")
                : app.owner === "personal" ? I18n.tr("From your configuration")
                : I18n.tr("Included with Cybex OS");
        }
        if (queuedAction === "install")
            return I18n.tr("On your install list");
        if (app.unavailable === "unfree")
            return I18n.tr("Proprietary apps are turned off on this computer.");
        if (app.unavailable === "missing")
            return I18n.tr("This app isn't in this computer's NixOS packages.");
        if (app.unavailable)
            return I18n.tr("NixOS marks this app as unavailable for this computer.");
        const state = verdict ? verdict.state : "checking";
        if (state === "compiles")
            return I18n.tr("NixOS hasn't finished building this yet. Try again after the next update.");
        if (state === "unavailable")
            return verdict.reason === "unfree" ? I18n.tr("Proprietary apps are turned off on this computer.")
                : I18n.tr("NixOS marks this app as unavailable for this computer.");
        if (vendor)
            return state === "prebuilt" ? I18n.tr("Vendor download · nothing to compile")
                : I18n.tr("Vendor download · checking…");
        const exact = state === "prebuilt" ? Helpers.size(verdict.downloadBytes) : "";
        const estimate = Helpers.size(app.downloadBytes);
        if (state === "prebuilt")
            return exact !== "" ? I18n.format("Download ≈ %1 · nothing to compile", [exact])
                : I18n.tr("Already downloaded · nothing to compile");
        if (state === "error")
            return estimate !== "" ? I18n.format("Download ≈ %1 · couldn't check NixOS's cache", [estimate])
                : I18n.tr("Couldn't check NixOS's cache. Software checks again before installing.");
        return estimate !== "" ? I18n.format("Download ≈ %1 · checking…", [estimate]) : I18n.tr("Checking the download…");
    }
    function downloadFact() {
        if (vendor)
            return I18n.tr("From the vendor");
        if (app.installed)
            return I18n.tr("Installed");
        const exact = verdict && verdict.state === "prebuilt" ? verdict.downloadBytes : -1;
        if (exact === 0)
            return I18n.tr("Already downloaded");
        const size = Helpers.size(exact > 0 ? exact : app.downloadBytes);
        return size !== "" ? "≈ " + size : "—";
    }

    // ---- heading ------------------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: Math.max(icon.height, info.implicitHeight, actions.implicitHeight)

        AppIcon {
            id: icon
            app: root.app
            size: Theme.scaled(84)
        }
        Column {
            id: info
            anchors.left: icon.right
            anchors.leftMargin: Theme.scaled(18)
            anchors.right: actions.left
            anchors.rightMargin: Theme.scaled(16)
            anchors.verticalCenter: icon.verticalCenter
            spacing: Theme.scaled(3)
            Text {
                objectName: "softwareAppName"
                width: parent.width
                text: root.app.name || ""
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.display
                font.weight: Theme.weightBold
                font.letterSpacing: -0.6
                elide: Text.ElideRight
                textFormat: Text.PlainText
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Text {
                width: parent.width
                text: [root.app.developer || "", Software.label(Software.subcategoryName(root.app)
                    || (Software.category(root.app) || {}).name || "")].filter(part => part !== "").join(" · ")
                color: Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Flow {
                width: parent.width
                topPadding: Theme.scaled(5)
                spacing: Theme.scaled(6)
                Tag {
                    tone: root.vendor ? "vendor" : "ok"
                    glyph: root.vendor ? "download" : "bolt"
                    text: root.vendor ? I18n.tr("Vendor download") : I18n.tr("Prebuilt by NixOS")
                }
                Tag {
                    text: root.vendor ? I18n.tr("Proprietary")
                        : root.licence !== "" ? I18n.format("Free software · %1", [root.licence]) : I18n.tr("Free software")
                }
                Tag {
                    visible: root.app.installed === true
                    tone: "ok"
                    glyph: "check"
                    text: I18n.tr("Installed")
                }
            }
        }
        Column {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: icon.verticalCenter
            width: Math.max(buttons.implicitWidth, Math.min(note.implicitWidth, Theme.scaled(300)))
            spacing: Theme.scaled(7)
            Row {
                id: buttons
                anchors.right: parent.right
                spacing: Theme.scaled(8)
                SoftwareButton {
                    objectName: "softwareAppRemove"
                    visible: root.removable
                    big: true
                    quiet: root.queuedAction !== "remove"
                    queued: root.queuedAction === "remove"
                    glyph: queued ? "check" : "trash"
                    text: root.queuedAction === "remove" ? I18n.tr("Will be removed") : I18n.tr("Remove")
                    accessibleName: root.queuedAction === "remove"
                        ? I18n.format("Keep %1", [root.app.name || ""]) : I18n.format("Remove %1", [root.app.name || ""])
                    onTriggered: Software.toggleRemove(root.app.attribute)
                }
                AppAction {
                    id: primaryAction
                    objectName: "softwareAppPrimary"
                    app: root.app
                    big: true
                    prominent: true
                    primary: primaryAction.mode === "install" || primaryAction.mode === "open"
                }
            }
            Text {
                id: note
                objectName: "softwareAppDownload"
                width: parent.width
                text: root.downloadLine()
                color: root.verdict && root.verdict.state === "compiles" && !root.app.installed ? Theme.amber : Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
    }

    // ---- screenshots --------------------------------------------------------
    Item {
        id: shotTiles
        property int loaded: 0
        property int failed: 0
        visible: root.shots.length > 0
        width: parent.width
        height: visible ? Math.min(Theme.scaled(300), width * (root.shots.length >= 3 ? 0.34 : 0.4)) : 0
        readonly property var shown: root.shots.slice(0, 3)
        readonly property real gap: Theme.scaled(8)

        function recount() {
            let ready = 0, broken = 0;
            for (let i = 0; i < tiles.count; i++) {
                const tile = tiles.itemAt(i) as ScreenshotTile;
                if (tile && tile.loaded) ready++;
                if (tile && tile.failed) broken++;
            }
            loaded = ready;
            failed = broken;
        }

        Repeater {
            id: tiles
            model: shotTiles.shown
            delegate: ScreenshotTile {
                id: tile
                required property string modelData
                required property int index
                readonly property int count: shotTiles.shown.length
                readonly property real major: count >= 3 ? (shotTiles.width - shotTiles.gap) * 2 / 3
                    : count === 2 ? (shotTiles.width - shotTiles.gap) / 2 : shotTiles.width
                objectName: "softwareScreenshot"
                url: modelData
                x: index === 0 ? 0 : count === 2 ? major + shotTiles.gap : major + shotTiles.gap
                y: count >= 3 && index === 2 ? (shotTiles.height + shotTiles.gap) / 2 : 0
                width: index === 0 || count === 2 ? major : shotTiles.width - major - shotTiles.gap
                height: count >= 3 && index > 0 ? (shotTiles.height - shotTiles.gap) / 2 : shotTiles.height
                onLoadedChanged: shotTiles.recount()
                onFailedChanged: shotTiles.recount()
                onOpened: Software.viewScreenshots(root.shots, tile.index)
            }
        }
    }
    Row {
        visible: root.shots.length > 0
        spacing: Theme.scaled(6)
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: "world"
            size: Theme.iconTiny
            color: Theme.textFaint
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.failedShots > 0 && root.loadedShots === 0
                ? I18n.tr("Screenshots couldn't be loaded from Flathub right now.")
                : I18n.tr("Screenshots load from Flathub when you open an app's page. Icons ship with Cybex OS.")
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            textFormat: Text.PlainText
        }
    }

    // ---- about and facts ----------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: root.wide ? Math.max(about.implicitHeight, facts.implicitHeight)
            : about.implicitHeight + facts.implicitHeight + Theme.scaled(16)

        Column {
            id: about
            width: root.wide ? (parent.width - Theme.scaled(20)) * 0.6 : parent.width
            spacing: Theme.scaled(8)
            SectionTitle {
                width: parent.width
                text: I18n.tr("About")
            }
            Repeater {
                model: Helpers.paragraphs(root.app.description)
                delegate: Item {
                    id: paragraph
                    required property var modelData
                    width: about.width
                    implicitHeight: body.implicitHeight
                    Text {
                        visible: paragraph.modelData.bullet
                        text: "•" // i18n: untranslated (list marker)
                        color: Theme.textDim
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.primary
                    }
                    Text {
                        id: body
                        x: paragraph.modelData.bullet ? Theme.scaled(16) : 0
                        width: parent.width - x
                        text: paragraph.modelData.text
                        color: Theme.textMid
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.primary
                        lineHeight: Theme.proseLineHeight
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                }
            }
            Text {
                visible: Helpers.paragraphs(root.app.description).length === 0
                width: parent.width
                text: root.app.summary || ""
                color: Theme.textMid
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
        Rectangle {
            id: facts
            x: root.wide ? parent.width - width : 0
            y: root.wide ? Theme.scaled(30) : about.implicitHeight + Theme.scaled(16)
            width: root.wide ? (parent.width - Theme.scaled(20)) * 0.4 : parent.width
            implicitHeight: factColumn.implicitHeight + Theme.scaled(8)
            radius: Theme.chipRadius + 5
            color: Theme.cardFill
            border.width: 1
            border.color: Theme.hairlineSoft
            Column {
                id: factColumn
                x: Theme.scaled(14)
                y: Theme.scaled(4)
                width: parent.width - Theme.scaled(28)
                FactRow {
                    width: parent.width
                    divider: false
                    label: root.app.installed ? I18n.tr("Installed version") : I18n.tr("Version in this system")
                    value: (root.app.installed ? root.app.installedVersion || root.app.version : root.app.version) || "—"
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Comes from")
                    value: root.vendor ? I18n.tr("Vendor, via NixOS") : I18n.tr("NixOS")
                    code: root.app.attribute || ""
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Download")
                    value: root.downloadFact()
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Updates")
                    value: I18n.tr("With Software Update")
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Licence")
                    value: root.vendor ? I18n.tr("Proprietary") : root.app.license || I18n.tr("Free software")
                }
                FactRow {
                    width: parent.width
                    visible: ExternalUrl.safeHttpUrl(root.app.homepage || "") !== ""
                    label: I18n.tr("Website")
                    value: Helpers.host(root.app.homepage)
                    link: root.app.homepage || ""
                    onLinkClicked: Qt.openUrlExternally(ExternalUrl.safeHttpUrl(root.app.homepage || ""))
                }
            }
        }
    }

    // ---- similar apps -------------------------------------------------------
    SectionTitle {
        width: parent.width
        visible: similar.count > 0
        text: I18n.tr("Similar apps")
    }
    Grid {
        id: similarGrid
        width: parent.width
        visible: similar.count > 0
        columns: Helpers.columns(width, Theme.scaled(220), Theme.scaled(10))
        spacing: Theme.scaled(10)
        Repeater {
            id: similar
            model: Helpers.similar(Software.apps, root.app, similarGrid.columns > 2 ? similarGrid.columns : 4)
            delegate: AppCard {
                required property var modelData
                width: (similarGrid.width - similarGrid.spacing * (similarGrid.columns - 1)) / similarGrid.columns
                app: modelData
            }
        }
    }
}
