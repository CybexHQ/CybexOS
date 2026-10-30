import QtQuick
import Quickshell
import Quickshell.Widgets
import "../Common"

// An app's icon: the one that ships with the catalogue, else its desktop
// entry's themed icon, else a quiet placeholder tile.
Item {
    id: root

    property var app: null
    property string icon: ""
    property real size: Theme.scaled(44)

    readonly property string shipped: Software.iconSource(root.app)
    // A desktop entry's themed icon, only when the theme really has it.
    readonly property string themed: shipped === "" && root.icon !== ""
        ? (/^\//.test(root.icon) ? "file://" + root.icon : Quickshell.iconPath(root.icon, true)) : ""
    readonly property bool ready: shipped !== "" ? image.status === Image.Ready : themed !== ""

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
        visible: root.shipped !== "" && status === Image.Ready
        source: root.shipped
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
