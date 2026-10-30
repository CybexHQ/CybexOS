import QtQuick
import "../Common"

// A screenshot at the size of the window, over a scrim. Left and Right go
// through the app's screenshots; Escape or a click outside closes it.
Rectangle {
    id: root

    readonly property var viewer: Software.viewer
    readonly property var urls: viewer ? viewer.urls : []
    readonly property int index: viewer ? viewer.index : 0

    visible: viewer !== null
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.82) : Qt.rgba(0.08, 0.08, 0.12, 0.78)
    focus: visible
    Accessible.role: Accessible.Dialog
    Accessible.name: I18n.tr("Screenshot")
    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }
    Keys.onLeftPressed: Software.stepViewer(-1)
    Keys.onRightPressed: Software.stepViewer(1)
    Keys.onEscapePressed: Software.closeViewer()

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Software.closeViewer()
    }
    Image {
        anchors.fill: parent
        anchors.margins: Theme.scaled(64)
        source: root.urls[root.index] || ""
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 1600
        MouseArea {
            anchors.fill: parent
        }
    }
    SoftwareButton {
        anchors.left: parent.left
        anchors.leftMargin: Theme.scaled(14)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.urls.length > 1
        big: true
        foreground: "#f7f5f0"
        glyph: "chevron-left"
        accessibleName: I18n.tr("Previous screenshot")
        onTriggered: Software.stepViewer(-1)
    }
    SoftwareButton {
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(14)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.urls.length > 1
        big: true
        foreground: "#f7f5f0"
        glyph: "chevron-right"
        accessibleName: I18n.tr("Next screenshot")
        onTriggered: Software.stepViewer(1)
    }
    SoftwareButton {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.scaled(14)
        big: true
        foreground: "#f7f5f0"
        glyph: "x"
        accessibleName: I18n.tr("Close")
        onTriggered: Software.closeViewer()
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.scaled(22)
        visible: root.urls.length > 1
        text: I18n.format("%1 of %2", [root.index + 1, root.urls.length])
        color: "#f7f5f0"
        font.family: Theme.fontNumeric
        font.pixelSize: Theme.typography.secondary
        textFormat: Text.PlainText
    }
}
