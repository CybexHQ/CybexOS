import QtQuick
import "../Common"

// One screenshot from Flathub's media server, loaded when its app's page
// opens. A slow or failed download leaves a calm placeholder, never an error.
Item {
    id: root

    property string url: ""
    property real radius: Theme.chipRadius + 3
    readonly property bool loaded: frame.status === Image.Ready
    readonly property bool failed: frame.status === Image.Error
    signal opened()

    activeFocusOnTab: loaded
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("Screenshot")
    Accessible.onPressAction: {
        if (root.loaded)
            root.opened();
    }
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && root.loaded) {
            root.opened();
            event.accepted = true;
        }
    }
    onLoadedChanged: {
        if (loaded)
            Software.remember(url);
    }

    MediaFrame {
        id: frame
        anchors.fill: parent
        radius: root.radius
        source: root.url
    }
    Sym {
        anchors.centerIn: parent
        visible: !root.loaded
        name: "photo"
        size: Theme.iconHero
        color: Theme.textFaint
        opacity: root.failed ? 0.5 : 1
    }
    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: mouse.containsMouse && root.loaded
        pressed: mouse.pressed
        rippleEnabled: false
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.loaded ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.loaded)
                root.opened();
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: root.activeFocus
        color: "transparent"
        radius: root.radius
        border.width: 2
        border.color: Theme.accentText
    }
}
