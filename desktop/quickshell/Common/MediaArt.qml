pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "StatusHelpers.js" as StatusHelpers

// A player's cover, rounded, and the player's own mark where there is none —
// the bar chip, the media panel and its list of other players all draw the
// same thing at different sizes.
//
// The cover is the thing people recognise, so it wins. The mark is the app's
// brand, its desktop-entry icon, or the media-type glyph, in that order.
Item {
    id: root

    property var player: null
    property real radius: 5
    // Paused: the cover loses most of its colour. Animated, so a pause reads
    // as a change of state rather than a different picture.
    property bool dimmed: false
    // The mark sits on a tile in a panel; in the bar it rests on the slab.
    property bool tile: true
    property real markSize: Math.round(Math.min(width, height) * (tile ? 0.5 : 0.9))
    property color markColor: Theme.textDim
    // Hover tint for the mark, the way every other menubar icon brightens.
    property bool markHighlighted: false
    // The app's mark even when there is a cover: the panel header names the
    // app, the hero shows the cover.
    property bool markOnly: false
    property color markHighlightColor: Theme.barTextHi

    readonly property string artUrl: player ? player.trackArtUrl : ""
    readonly property bool hasArt: !markOnly && artUrl !== "" && cover.status === Image.Ready
    readonly property string brand: Media.brandFor(player)
    readonly property string iconSource: Media.resolvePlayerIcon(player)

    property real drain: dimmed ? 1 : 0
    Behavior on drain {
        NumberAnimation { duration: Theme.surfaceDuration }
    }

    Accessible.ignored: true

    // ---- cover ----------------------------------------------------------
    // Image has no radius and Rectangle's clip is square, so the corner is
    // the shell's masking idiom (Common/StateLayer.qml rounds its ripple the
    // same way).
    Item {
        id: coverLayer
        anchors.fill: parent
        visible: root.hasArt
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: coverMask
            saturation: -0.8 * root.drain
            brightness: -0.12 * root.drain
        }

        Image {
            id: cover
            anchors.fill: parent
            source: root.markOnly ? "" : root.artUrl
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(Math.max(16, Math.round(root.width * 2)),
                Math.max(16, Math.round(root.height * 2)))
            asynchronous: true
            smooth: true
            mipmap: true
        }
    }

    Rectangle {
        id: coverMask
        anchors.fill: parent
        radius: root.radius
        color: "white"
        visible: false
        layer.enabled: true
    }

    // ---- the player's mark ------------------------------------------------
    Rectangle {
        anchors.fill: parent
        visible: !root.hasArt && root.tile
        radius: root.radius
        color: Theme.tile
        border.width: 1
        border.color: Theme.hairline
    }

    BrandIcon {
        id: brandMark
        anchors.centerIn: parent
        width: root.markSize
        height: root.markSize
        visible: !root.hasArt && available && status === Image.Ready
        name: root.brand
        highlighted: root.markHighlighted
    }

    Image {
        id: appMark
        anchors.centerIn: parent
        width: root.markSize
        height: root.markSize
        visible: !root.hasArt && !brandMark.visible && status === Image.Ready
        source: root.iconSource
        sourceSize: Qt.size(Math.round(root.markSize * 2), Math.round(root.markSize * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // The tint animates here rather than inside the effect so the
        // offscreen layer exists only while it is non-zero, as in BrandIcon;
        // at rest the icon takes the plain image path.
        property real tintAmount: root.markHighlighted ? 1 : 0
        Behavior on tintAmount {
            NumberAnimation { duration: Theme.chipFadeDuration }
        }
        layer.enabled: visible && tintAmount > 0.001
        layer.effect: MultiEffect {
            colorization: appMark.tintAmount
            colorizationColor: root.markHighlightColor
        }
    }

    Sym {
        anchors.centerIn: parent
        visible: !root.hasArt && !brandMark.visible && !appMark.visible
        name: StatusHelpers.playerGlyph(root.player)
        size: Math.round(root.markSize * 0.9)
        color: root.markHighlighted ? root.markHighlightColor : root.markColor
    }
}
