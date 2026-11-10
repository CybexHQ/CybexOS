import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"
import "../Common/Monogram.js" as Monogram
import "../Common/SoftwareHelpers.js" as Helpers

// An app's icon: the one that ships with the catalogue, else its desktop
// entry's themed icon, else a Flathub app's icon from Flathub's media
// server, else a monogram tile: the name's first letter on a colour derived
// from the name (Common/Monogram.js), so icon-less apps still differ.
Item {
    id: root

    property var app: null
    property string icon: ""
    // A Flathub search result's or page's icon; loads only where one is shown.
    property string url: ""
    // The name the monogram is drawn from, when no catalogue app gives one.
    property string name: app && app.name ? app.name : ""
    property real size: Theme.scaled(44)

    readonly property string shipped: Software.iconSource(root.app)
    // A desktop entry's themed icon, only when the theme really has it.
    readonly property string themed: shipped === "" && root.icon !== ""
        ? (/^\//.test(root.icon) ? "file://" + root.icon : Quickshell.iconPath(root.icon, true)) : ""
    readonly property string remote: shipped === "" && themed === "" ? Helpers.flathubMedia(root.url) : ""
    readonly property bool ready: shipped !== "" ? image.status === Image.Ready
        : themed !== "" ? true : remote !== "" && image.status === Image.Ready
    // While an icon is still on its way the tile stays a quiet chip, so a
    // letter does not flash before the artwork.
    readonly property bool loading: (shipped !== "" || remote !== "") && image.status === Image.Loading
    readonly property bool lettered: !loading && monogram.letter !== ""
    readonly property var monogram: Monogram.tile(root.name, Theme.dark)
    // The letter's type role grows with the tile, as an icon's size would.
    readonly property int letterSize: size >= Theme.scaled(100) ? Theme.typography.clock
        : size >= Theme.scaled(72) ? Theme.typography.displayLarge
        : size >= Theme.scaled(40) ? Theme.typography.heading
        : size >= Theme.scaled(34) ? Theme.typography.title
        : Theme.typography.primary

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Rectangle {
        objectName: "softwareMonogram"
        anchors.fill: parent
        visible: !root.ready
        radius: Math.round(root.size * 0.24)
        color: root.lettered ? root.monogram.fill : Theme.chip
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.72
            height: parent.height * 0.72
            visible: root.lettered
            text: root.monogram.letter
            color: root.monogram.ink
            font.family: Theme.fontMenu
            font.pixelSize: root.letterSize
            font.weight: Theme.weightBold
            fontSizeMode: Text.Fit
            minimumPixelSize: Theme.typography.metadata
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
        Sym {
            anchors.centerIn: parent
            visible: !root.loading && root.monogram.letter === ""
            name: "apps"
            size: Math.round(root.size * 0.5)
            color: Theme.textDim
        }
    }
    Image {
        id: image
        anchors.fill: parent
        visible: (root.shipped !== "" || root.remote !== "") && status === Image.Ready
        source: root.shipped !== "" ? root.shipped : root.remote
        sourceSize.width: 128
        sourceSize.height: 128
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    IconImage {
        anchors.fill: parent
        visible: root.themed !== ""
        implicitSize: root.size
        asynchronous: true
        source: root.themed
    }
}
