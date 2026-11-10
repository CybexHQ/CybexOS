import QtQuick
import "Monogram.js" as Monogram
import "NotifHelpers.js" as Helpers

// A notification's source icon: the desktop entry's icon where one resolves,
// otherwise a browser-cached site favicon and finally the source's monogram —
// its first letter, so two icon-less senders still look different — or a
// warning for critical. Callers opt into a compact well so icons with very
// different silhouettes keep the same visual weight: the shell's resting chip
// rather than an accent tint, which made every card look like an alert. The
// monogram always sits in a well of its own, the same tile the launcher and
// Software draw for an app without an icon (Common/Monogram.js): a colour
// derived from the sender's name, so two icon-less senders differ at a glance.
Item {
    id: root

    required property var entry
    property int iconSize: 28
    // A typography role, chosen by the caller for the size of its well.
    property int monogramSize: Theme.typography.primary
    // The well's fill. A card that is itself a chip lifts it a step.
    property color wellColor: Theme.chip
    property bool urgent: false
    property bool framed: false
    property bool primaryFailed: false
    readonly property string primarySource: brand.available
        ? "" : Notifs.iconSource(entry)
    // Never turn untrusted sender metadata into a network fetch or subprocess.
    readonly property string siteSource: ""
    readonly property string monogram: Helpers.monogram(entry.displayAppName || entry.appName || "")
    readonly property bool showsMark: !brand.visible && !image.visible
    readonly property bool showsMonogram: showsMark && !urgent && monogram !== ""
    readonly property var monogramTile: Monogram.tile(entry.displayAppName || entry.appName || "", Theme.dark)

    function requestSiteIcon() {
        // Site brand icons and safe sender images are resolved in process.
    }

    onEntryChanged: {
        primaryFailed = false;
        requestSiteIcon();
    }
    onPrimarySourceChanged: primaryFailed = false
    Component.onCompleted: requestSiteIcon()

    Rectangle {
        anchors.fill: parent
        radius: Theme.chipRadius
        color: root.urgent && (root.framed || root.showsMark) ? Theme.redBgSoft
            : root.showsMonogram ? root.monogramTile.fill
            : root.framed ? root.wellColor
            : "transparent"
        border.width: root.urgent && (root.framed || root.showsMark) ? 1 : 0
        border.color: Theme.redBorder

        BrandIcon {
            id: brand
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            name: root.entry.brandIcon || ""
            visible: available && status === Image.Ready
        }

        Image {
            id: image
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            source: brand.available ? ""
                : root.primarySource !== "" && !root.primaryFailed
                    ? root.primarySource : root.siteSource
            sourceSize: Qt.size(root.iconSize, root.iconSize)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: !brand.visible && status === Image.Ready
            onStatusChanged: {
                if (status === Image.Error && root.primarySource !== ""
                        && source.toString() === root.primarySource)
                    root.primaryFailed = true;
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.showsMonogram
            text: root.monogram
            textFormat: Text.PlainText
            font.family: Theme.fontMenu
            font.pixelSize: root.monogramSize
            font.weight: Theme.weightBold
            color: root.monogramTile.ink
        }

        Sym {
            anchors.centerIn: parent
            visible: root.showsMark && !root.showsMonogram
            name: root.urgent ? "warning" : "notifications"
            size: Math.max(Theme.fontCaption, root.iconSize - (root.framed ? 3 : 8))
            color: root.urgent ? Theme.redText : Theme.accentText
        }
    }
}
