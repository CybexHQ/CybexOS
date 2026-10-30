import QtQuick
import "../Common"

// A theme's busy pointer at the gallery's scale: its first frame at rest and
// its own animation while `playing`, unless motion is reduced. The preview
// is a strip of up to twelve frames side by side (scripts/pointer_xcursor.py).
Item {
    id: root

    property var theme: null
    // Screen pixels per preview pixel.
    property real shapeScale: 1
    property bool playing: false
    readonly property string source: theme && theme.previews && theme.previews.busy
        ? "file://" + theme.previews.busy : ""
    readonly property int frames: theme ? Math.max(1, theme.busyFrames) : 1
    readonly property int frameWidth: Math.max(1, Math.floor(strip.implicitWidth / frames))

    implicitWidth: strip.status === Image.Ready ? frameWidth * shapeScale : 0
    implicitHeight: strip.status === Image.Ready ? strip.implicitHeight * shapeScale : 0
    width: implicitWidth
    height: implicitHeight

    // Only read for the strip's size; the sprite draws it.
    Image {
        id: strip
        visible: false
        source: root.source
        asynchronous: true
    }

    AnimatedSprite {
        anchors.fill: parent
        visible: strip.status === Image.Ready
        source: root.source
        frameCount: root.frames
        frameWidth: root.frameWidth
        frameHeight: Math.max(1, strip.implicitHeight)
        frameDuration: Math.max(20, Math.round((root.theme ? root.theme.busyDuration : 0) / root.frames) || 80)
        interpolate: false
        smooth: true
        running: root.playing && root.frames > 1 && !Theme.reducedMotion
        onRunningChanged: if (!running) currentFrame = 0
    }
}
