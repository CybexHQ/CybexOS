pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import "../Common"

// A remote image in a rounded frame. Rounded clipping needs the GPU scene
// graph; under the software renderer (isolated checks) the frame clips square.
Item {
    id: root

    property string source: ""
    property real radius: Theme.chipRadius + 3
    property color fill: Theme.chip
    property int sourceWidth: 1248
    // A fade into the panel colour along the bottom, under a caption.
    property bool fade: false
    property int status: Image.Null
    readonly property bool rounded: GraphicsInfo.api !== GraphicsInfo.Software

    Loader {
        anchors.fill: parent
        sourceComponent: root.rounded ? roundedFrame : squareFrame
    }
    Component {
        id: roundedFrame
        ClippingRectangle {
            radius: root.radius
            color: root.fill
            Image {
                id: roundImage
                anchors.fill: parent
                source: root.source
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: Image.AlignTop
                sourceSize.width: root.sourceWidth
                opacity: roundImage.status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Theme.chipFadeDuration }
                }
                onStatusChanged: root.status = roundImage.status
                Component.onCompleted: root.status = roundImage.status
            }
            Rectangle {
                anchors.fill: parent
                visible: root.fade
                gradient: Gradient {
                    GradientStop { position: 0.2; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) }
                    GradientStop { position: 0.8; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.95) }
                }
            }
        }
    }
    Component {
        id: squareFrame
        Rectangle {
            radius: root.radius
            color: root.fill
            clip: true
            Image {
                id: squareImage
                anchors.fill: parent
                source: root.source
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: Image.AlignTop
                sourceSize.width: root.sourceWidth
                opacity: squareImage.status === Image.Ready ? 1 : 0
                onStatusChanged: root.status = squareImage.status
                Component.onCompleted: root.status = squareImage.status
            }
            Rectangle {
                anchors.fill: parent
                visible: root.fade
                gradient: Gradient {
                    GradientStop { position: 0.2; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) }
                    GradientStop { position: 0.8; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.95) }
                }
            }
        }
    }
}
