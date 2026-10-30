import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// A package from the full Nixpkgs search. It is checked before Install is
// offered: only a prebuilt package (or an unfree vendor download) can join
// the install list.
Rectangle {
    id: root

    property var result: ({})
    readonly property string attribute: result.attribute || ""
    readonly property var verdict: Software.checks[attribute] || null
    readonly property string queuedAction: Software.queued(attribute)
    readonly property bool installed: (Software.catalogue.desired || []).includes(attribute)
        || (Software.catalogue.selected || []).includes(attribute)
    readonly property string phase: installed ? "installed"
        : queuedAction === "install" ? "added"
        : !verdict ? "unchecked"
        : verdict.state

    implicitHeight: Math.max(Theme.scaled(58), copy.implicitHeight + Theme.scaled(18))
    radius: Theme.chipRadius + 3
    color: Theme.cardFill

    Column {
        id: copy
        anchors.left: parent.left
        anchors.leftMargin: Theme.scaled(14)
        anchors.right: side.left
        anchors.rightMargin: Theme.scaled(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(2)
        Row {
            width: parent.width
            spacing: Theme.scaled(8)
            Text {
                id: name
                width: Math.min(implicitWidth, parent.width - version.width - parent.spacing)
                text: root.result.name || root.attribute
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                id: version
                anchors.baseline: name.baseline
                text: root.result.version || ""
                color: Theme.textDim
                font.family: Theme.fontNumeric
                font.pixelSize: Theme.typography.secondary
                textFormat: Text.PlainText
            }
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.result.description || ""
            color: Theme.textMid
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            readonly property string verdictState: root.verdict ? root.verdict.state : ""
            width: parent.width
            text: verdictState === "compiles"
                ? I18n.tr("NixOS hasn't finished building this yet. Try again after the next update.")
                : verdictState === "unavailable" ? (root.verdict.reason === "unfree"
                    ? I18n.tr("Proprietary apps are turned off on this computer.")
                    : I18n.tr("NixOS marks this package as unavailable for this computer."))
                : verdictState === "error" ? I18n.tr("Couldn't check NixOS's cache. Try again.")
                : verdictState === "prebuilt" && !root.installed ? (root.verdict.vendor ? I18n.tr("Vendor download · nothing to compile")
                    : root.verdict.downloadBytes > 0 ? I18n.format("Prebuilt · %1 to download", [Helpers.size(root.verdict.downloadBytes)])
                    : I18n.tr("Prebuilt · already downloaded"))
                : root.attribute
            color: verdictState === "compiles" ? Theme.amber : verdictState === "prebuilt" && !root.installed ? Theme.ok : Theme.textFaint
            font.family: text === root.attribute ? Theme.fontMono : Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
    Item {
        id: side
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(12)
        anchors.verticalCenter: parent.verticalCenter
        width: button.width
        height: button.height
        SoftwareButton {
            id: button
            objectName: "softwarePackageAction"
            anchors.right: parent.right
            visible: root.phase !== "installed"
            busy: root.phase === "checking"
            queued: root.phase === "added"
            glyph: queued ? "check" : ""
            enabled: ["unchecked", "error", "prebuilt", "added"].includes(root.phase)
            primary: root.phase === "prebuilt"
            text: root.phase === "added" ? I18n.tr("Added")
                : root.phase === "prebuilt" ? I18n.tr("Install")
                : root.phase === "checking" ? I18n.tr("Checking…")
                : root.phase === "compiles" ? I18n.tr("Not ready yet")
                : root.phase === "unavailable" ? I18n.tr("Unavailable")
                : I18n.tr("Check")
            accessibleName: root.phase === "prebuilt" ? I18n.format("Install %1", [root.result.name || root.attribute])
                : root.phase === "added" ? I18n.format("Take %1 off the install list", [root.result.name || root.attribute])
                : I18n.format("Check whether %1 is prebuilt", [root.result.name || root.attribute])
            onTriggered: {
                if (root.phase === "prebuilt" || root.phase === "added")
                    Software.toggleInstall(root.attribute);
                else
                    Software.requestCheck(root.attribute);
            }
        }
        Tag {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.phase === "installed"
            tone: "ok"
            glyph: "check"
            text: I18n.tr("Installed")
        }
    }
}
