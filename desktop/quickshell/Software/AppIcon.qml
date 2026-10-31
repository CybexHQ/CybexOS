import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// An app's icon: the one that ships with the catalogue, else its desktop
// entry's themed icon, else a Flathub app's icon from Flathub's media
// server, else a quiet placeholder tile.
Item {
    id: root

    property var app: null
    property string icon: ""
    // A Flathub search result's or page's icon; loads only where one is shown.
    property string url: ""
    property real size: Theme.scaled(44)

    readonly property string shipped: Software.iconSource(root.app)
    // A desktop entry's themed icon, only when the theme really has it.
    readonly property string themed: shipped === "" && root.icon !== ""
        ? (/^\//.test(root.icon) ? "file://" + root.icon : Quickshell.iconPath(root.icon, true)) : ""
    readonly property string remote: shipped === "" && themed === "" ? Helpers.flathubMedia(root.url) : ""
    readonly property bool ready: shipped !== "" ? image.status === Image.Ready
        : themed !== "" ? true : remote !== "" && image.status === Image.Ready

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Rectangle {
        anchors.fill: parent
        visible: !root.ready
        radius: Math.round(root.size * 0.24)
        color: Theme.chip
        Sym {
            anchors.centerIn: parent
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
