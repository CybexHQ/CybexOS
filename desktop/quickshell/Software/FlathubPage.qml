pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/ExternalUrl.js" as ExternalUrl
import "../Common/SoftwareHelpers.js" as Helpers

// One Flathub app: who makes it, that it installs for this account right away
// and runs in a sandbox, what installing it downloads and may access,
// screenshots, what it does and the facts. Details load from Flathub when
// the page opens; a search result fills in meanwhile.
PageScroll {
    id: root

    property string appId: ""
    readonly property var app: Software.flathubPage(appId)
    readonly property string pageState: Software.flathubPageState(appId)
    readonly property var installedRow: Software.flathubApp(appId)
    readonly property string mode: Software.flathubMode(app)
    readonly property string failure: Software.flathubFailure(appId)
    readonly property var shots: Helpers.screenshots(app)
    readonly property int loadedShots: shotTiles.loaded
    readonly property int failedShots: shotTiles.failed
    readonly property string licence: Helpers.license(app.license)
    readonly property bool removable: installedRow !== null && installedRow.installation === "user"
    readonly property bool wide: innerWidth >= Theme.scaled(700)
    readonly property var allowed: Helpers.permissions(app.permissions)
    property bool confirmRemove: false

    objectName: "softwareFlathubPage"
    Component.onCompleted: Software.loadFlathub(appId)

    Timer {
        id: confirmTimeout
        interval: 4000
        onTriggered: root.confirmRemove = false
    }

    function downloadLine() {
        if (mode === "installing")
            return I18n.tr("Installing from Flathub…");
        if (mode === "removing")
            return I18n.tr("Removing…");
        if (mode === "updating")
            return I18n.tr("Updating from Flathub…");
        if (installedRow)
            return installedRow.installation === "user" ? I18n.tr("Installed for you from Flathub")
                : I18n.tr("Installed for everyone on this computer");
        if (mode === "off")
            return I18n.tr("Flathub isn't available on this computer.");
        if (mode === "unfree")
            return I18n.tr("Proprietary apps are turned off on this computer.");
        if (mode === "unsupported")
            return I18n.tr("Flathub doesn't offer this app for this computer.");
        if (pageState !== "ready")
            return I18n.tr("Installs right away, for your account");
        const size = Helpers.size(app.downloadBytes);
        return size !== "" ? I18n.format("Download ≈ %1 · installs right away, for your account", [size])
            : I18n.tr("Installs right away, for your account");
    }
    function permissionText(key) {
        return key === "files-all" ? I18n.tr("Can read and change all your files")
            : key === "files-home" ? I18n.tr("Can read and change files in your home folder")
            : key === "files-some" ? I18n.tr("Can use some of your folders")
            : key === "devices" ? I18n.tr("Can use devices such as cameras and controllers")
            : key === "host-commands" ? I18n.tr("Can run commands outside its sandbox")
            : key === "x11" ? I18n.tr("Uses the older X11 display system, which isolates apps less")
            : key === "network" ? I18n.tr("Can use the network") : "";
    }
    // In Helpers.PERMISSIONS order.
    function permissionGlyph(key) {
        return ["folder", "home", "folder", "plug", "terminal-2", "app-window", "world"][Helpers.PERMISSIONS.indexOf(key)] || "world";
    }

    // ---- heading ------------------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: Math.max(icon.height, info.implicitHeight, actions.implicitHeight)

        AppIcon {
            id: icon
            url: root.app.icon || ""
            icon: root.installedRow ? root.installedRow.icon || "" : ""
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
                objectName: "softwareFlathubName"
                width: parent.width
                text: root.app.name || root.appId
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
                visible: text !== ""
                text: root.app.developer || ""
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
                    glyph: "shield-lock"
                    text: I18n.tr("From Flathub · sandboxed")
                }
                Tag {
                    visible: root.app.verified === true
                    tone: "ok"
                    glyph: "circle-check"
                    text: I18n.tr("Verified developer")
                }
                Tag {
                    visible: root.pageState === "ready" || root.app.free !== undefined
                    tone: root.app.free === false ? "vendor" : ""
                    text: root.app.free === false ? I18n.tr("Proprietary")
                        : root.licence !== "" ? I18n.format("Free software · %1", [root.licence]) : I18n.tr("Free software")
                }
                Tag {
                    visible: root.installedRow !== null
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
                    objectName: "softwareFlathubRemove"
                    visible: root.removable && root.mode === "open"
                    big: true
                    quiet: !root.confirmRemove
                    glyph: "trash"
                    enabled: !Software.flathubBusy
                    text: root.confirmRemove ? I18n.tr("Remove now") : I18n.tr("Remove")
                    accessibleName: root.confirmRemove ? I18n.format("Confirm removing %1", [root.app.name || root.appId])
                        : I18n.format("Remove %1", [root.app.name || root.appId])
                    onTriggered: {
                        if (!root.confirmRemove) {
                            root.confirmRemove = true;
                            confirmTimeout.restart();
                            return;
                        }
                        root.confirmRemove = false;
                        Software.removeFlathub(root.appId, root.app.name || "");
                    }
                }
                FlathubAction {
                    id: primaryAction
                    objectName: "softwareFlathubPrimary"
                    entry: root.app
                    big: true
                    prominent: true
                }
            }
            Text {
                id: note
                objectName: "softwareFlathubDownload"
                width: parent.width
                text: root.downloadLine()
                color: Theme.textDim
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
    }

    Notice {
        objectName: "softwareFlathubFailure"
        width: parent.width
        visible: root.failure !== ""
        glyph: "alert-triangle"
        text: root.failure
    }
    Notice {
        width: parent.width
        visible: root.app.eol === true
        glyph: "alert-triangle"
        text: I18n.tr("Flathub marks this app as no longer maintained. It may stop receiving fixes.")
    }
    Row {
        visible: root.pageState === "loading"
        spacing: Theme.scaled(8)
        Spinner {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.textDim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Loading details from Flathub…")
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            textFormat: Text.PlainText
        }
    }
    Notice {
        objectName: "softwareFlathubError"
        width: parent.width
        visible: root.pageState === "error"
        glyph: "alert-triangle"
        text: Software.flathubPageError(root.appId) || I18n.tr("Flathub's details for this app couldn't be loaded.")
        action: I18n.tr("Try Again")
        actionPrimary: false
        onTriggered: Software.loadFlathub(root.appId)
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
                x: index === 0 ? 0 : major + shotTiles.gap
                y: count >= 3 && index === 2 ? (shotTiles.height + shotTiles.gap) / 2 : 0
                width: index === 0 || count === 2 ? major : shotTiles.width - major - shotTiles.gap
                height: count >= 3 && index > 0 ? (shotTiles.height - shotTiles.gap) / 2 : shotTiles.height
                onLoadedChanged: shotTiles.recount()
                onFailedChanged: shotTiles.recount()
                onOpened: Software.viewScreenshots(root.shots, tile.index)
            }
        }
    }
    Text {
        visible: root.shots.length > 0 && root.failedShots > 0 && root.loadedShots === 0
        width: parent.width
        text: I18n.tr("Screenshots couldn't be loaded from Flathub right now.")
        color: Theme.textFaint
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
        textFormat: Text.PlainText
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
            SectionTitle {
                width: parent.width
                visible: root.pageState === "ready"
                text: I18n.tr("Sandbox")
            }
            Text {
                visible: root.pageState === "ready"
                width: parent.width
                text: root.allowed.length > 0
                    ? I18n.tr("Flathub apps run in a sandbox. This one asks for:")
                    : I18n.tr("Flathub apps run in a sandbox. This one asks for no special access.")
                color: Theme.textMid
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            Repeater {
                model: root.pageState === "ready" ? root.allowed : []
                delegate: Row {
                    id: permission
                    required property string modelData
                    objectName: "softwareFlathubPermission"
                    width: about.width
                    spacing: Theme.scaled(8)
                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.permissionGlyph(permission.modelData)
                        size: Theme.iconSmall
                        color: ["files-all", "host-commands"].includes(permission.modelData) ? Theme.amber : Theme.textDim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.iconSmall - parent.spacing
                        text: root.permissionText(permission.modelData)
                        color: Theme.textMid
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                }
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
                    label: root.installedRow ? I18n.tr("Installed version") : I18n.tr("Version on Flathub")
                    value: (root.installedRow ? root.installedRow.version || root.app.version : root.app.version) || "—"
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Comes from")
                    value: "Flathub" // i18n: untranslated (product name)
                    code: root.appId
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Download")
                    value: root.installedRow ? I18n.tr("Installed")
                        : Helpers.size(root.app.downloadBytes) !== "" ? "≈ " + Helpers.size(root.app.downloadBytes) : "—"
                }
                FactRow {
                    width: parent.width
                    visible: (root.app.runtime || "") !== ""
                    label: I18n.tr("Shared runtime")
                    value: root.app.runtime || ""
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Updates")
                    value: I18n.tr("In Software's Updates tab")
                }
                FactRow {
                    width: parent.width
                    label: I18n.tr("Licence")
                    value: root.app.free === false ? I18n.tr("Proprietary") : root.app.license || I18n.tr("Free software")
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

    Row {
        spacing: Theme.scaled(6)
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: "world"
            size: Theme.iconTiny
            color: Theme.textFaint
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.innerWidth - Theme.iconTiny - Theme.scaled(6)
            text: I18n.tr("Details, icons and screenshots come from flathub.org. Flathub apps are installed for your account only and are not part of system updates or rollback.")
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }
}
