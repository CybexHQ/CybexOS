pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Apps update together with the system, all prebuilt, in Software Update.
// This page only reads: which installed apps a prepared update changes, or
// that one is available or on its way, or that everything is current.
PageScroll {
    id: root

    readonly property var deployment: Updates.deployment
    readonly property bool update: (deployment.changeKind || "") === "update"
    readonly property bool prepared: update && deployment.state === "ready"
    readonly property bool preparing: update && (Updates.runActive || ["discovering", "building", "validating"].includes(deployment.state))
    readonly property bool restart: update && Updates.rebootRecommended
    readonly property var rows: Software.updates
    readonly property int components: ((deployment.highlights || {}).components || []).length
        + Number((deployment.highlights || {}).background || 0)

    objectName: "softwareUpdatesPage"
    spacing: Theme.scaled(8)

    Notice {
        objectName: "softwareUpdatesNotice"
        width: parent.width
        visible: root.prepared || root.preparing || root.restart || Updates.hasUpdates
        glyph: root.restart ? "refresh" : "download"
        title: root.prepared ? I18n.tr("A system update is ready to install.")
            : root.restart ? I18n.tr("Restart to finish the system update.")
            : root.preparing ? I18n.tr("A system update is being prepared.")
            : I18n.tr("System updates are available.")
        text: root.prepared ? I18n.tr("Apps update together with the system, all prebuilt, so nothing compiles.")
            : root.restart ? I18n.tr("The update is installed. Restart when convenient to finish it.")
            : root.preparing ? I18n.tr("Software Update shows its progress. Your apps keep working meanwhile.")
            : I18n.tr("Prepare them in Software Update to see which of your apps change.")
        action: root.prepared ? I18n.tr("Install in Software Update…") : I18n.tr("Open Software Update…")
        actionName: "softwareOpenUpdates"
        onTriggered: Software.openSoftwareUpdate()
    }

    GroupLabel {
        width: parent.width
        visible: root.rows.length > 0
        text: I18n.tr("Your apps in this update")
        detail: (root.rows.length === 1 ? I18n.tr("1 app") : I18n.format("%1 apps", [root.rows.length]))
            + (root.components > 0 ? " · " + I18n.format("%1 system components", [root.components]) : "")
    }
    Repeater {
        model: root.rows
        delegate: Rectangle {
            id: change
            required property var modelData
            readonly property var app: modelData.app
            objectName: "softwareUpdateRow"
            width: root.innerWidth
            height: Theme.scaled(56)
            radius: Theme.chipRadius + 3
            color: Theme.cardFill
            AppIcon {
                id: icon
                x: Theme.scaled(12)
                anchors.verticalCenter: parent.verticalCenter
                app: change.app
                icon: change.modelData.icon || ""
                size: Theme.scaled(36)
            }
            Column {
                anchors.left: icon.right
                anchors.leftMargin: Theme.scaled(12)
                anchors.right: versions.left
                anchors.rightMargin: Theme.scaled(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.scaled(1)
                Text {
                    width: parent.width
                    text: change.modelData.title
                    color: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    font.weight: Theme.weightBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: change.app ? Software.label(Software.subcategoryName(change.app)
                        || (Software.category(change.app) || {}).name || "") : ""
                    color: Theme.textDim
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            Row {
                id: versions
                anchors.right: parent.right
                anchors.rightMargin: Theme.scaled(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.scaled(7)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: change.modelData.kind === "updated"
                    text: change.modelData.before || ""
                    color: Theme.textDim
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.typography.secondary
                    textFormat: Text.PlainText
                }
                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: change.modelData.kind === "updated"
                    name: "arrow-right"
                    size: Theme.iconSmall
                    color: Theme.textFaint
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: change.modelData.kind === "added" ? I18n.tr("New")
                        : change.modelData.kind === "removed" ? I18n.tr("Removed") : change.modelData.after || ""
                    color: change.modelData.kind === "removed" ? Theme.redText : Theme.ok
                    font.family: change.modelData.kind === "updated" ? Theme.fontNumeric : Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    font.weight: Theme.weightSemibold
                    textFormat: Text.PlainText
                }
            }
        }
    }

    // Up to date, or nothing app-specific to show yet.
    Column {
        objectName: "softwareUpToDate"
        visible: !Updates.hasUpdates && !root.prepared && !root.preparing && !root.restart
        width: parent.width
        topPadding: Theme.scaled(56)
        spacing: Theme.scaled(10)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.scaled(64)
            height: width
            radius: width / 2
            color: Theme.okBgSoft
            Sym {
                anchors.centerIn: parent
                name: "circle-check"
                size: Theme.scaled(32)
                color: Theme.ok
            }
        }
        Text {
            width: parent.width
            text: I18n.tr("Your apps are up to date")
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.heading
            font.weight: Theme.weightBold
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            width: parent.width
            text: I18n.tr("Apps update together with the system in Software Update, all prebuilt, so nothing compiles.")
            color: Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            visible: Updates.checkedAt !== null
            text: Updates.checkedAt ? I18n.format("Last checked at %1", [Qt.formatTime(Updates.checkedAt, Qt.locale().timeFormat(Locale.ShortFormat))]) : ""
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.scaled(8)
            topPadding: Theme.scaled(6)
            SoftwareButton {
                objectName: "softwareCheckUpdates"
                big: true
                busy: Updates.busy
                enabled: !Updates.busy
                glyph: "refresh"
                text: Updates.busy ? I18n.tr("Checking…") : I18n.tr("Check for updates")
                onTriggered: {
                    Updates.refreshStatus();
                    Updates.check(true);
                }
            }
            SoftwareButton {
                big: true
                quiet: true
                text: I18n.tr("Open Software Update…")
                onTriggered: Software.openSoftwareUpdate()
            }
        }
    }
}
