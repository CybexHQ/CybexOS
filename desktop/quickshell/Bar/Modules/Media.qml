pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import ".."
import "../../Common"
import "../../Common/StatusHelpers.js" as StatusHelpers

// Now-playing chip: the cover, the track, and a play/pause button ringed by
// the track's progress.
//
// The chip keeps one width while it is used. Nothing unfolds under the
// pointer, so the modules beside it never move; skipping lives on a middle
// click, the media keys and the panel. Paused reads at rest: the title dims
// and the cover loses its colour. The wheel sets this player's own volume.
BarModule {
    id: root

    moduleId: "media"
    detailSaving: titleClip.naturalWidth > 0 ? titleClip.naturalWidth + mediaChip.spacing : 0

    readonly property var player: Media.player
    readonly property bool playing: Media.playing
    readonly property var others: Media.others
    readonly property var label: StatusHelpers.chipText(Settings.modOpts.media.titleFormat,
        player ? player.trackTitle : "", player ? player.trackArtist : "")
    readonly property string trackKey: player
        ? StatusHelpers.playerKey(player) + "\n" + player.trackTitle + "\n" + player.trackArtist : ""

    function escaped(value) {
        return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // The wheel steps this player's volume, not the output's; the OSD says
    // whose it is. A handler rather than another MouseArea, as in Volume.qml.
    WheelHandler {
        target: null
        // Virtual pointers (remote desktop, wlr-virtual-pointer) report no
        // device type, and the default filter would drop their wheel.
        acceptedDevices: PointerDevice.AllDevices
        onWheel: event => {
            const delta = event.angleDelta.y !== 0
                ? event.angleDelta.y : event.pixelDelta.y * 8;
            if (delta === 0 || !Media.volumeAvailable)
                return;
            Media.stepVolume(delta > 0 ? 0.05 : -0.05);
            Osd.showPlayer();
        }
    }

    BarChip {
        id: mediaChip

        host: root.host
        panelName: "media"
        isle: root.isle
        anchorItem: root.groupAnchor ?? mediaChip
        leftPadding: 4
        rightPadding: 3
        spacing: 8
        contentTakesInput: true
        middleClickable: true
        tooltip: root.player
            ? root.player.trackTitle + (root.player.trackArtist !== ""
                ? " · " + root.player.trackArtist : "")
                + (root.player.identity ? " — " + root.player.identity : "")
            : "Media"
        tooltipAlign: -1
        onMiddleClicked: {
            if (root.player && root.player.canGoNext)
                root.player.next();
        }

        // ---- cover --------------------------------------------------------
        // A second player shows as a cover tucked behind the first.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.others.length > 0 ? 25 : 20
            height: 20

            MediaArt {
                visible: root.others.length > 0
                x: 5
                width: 20
                height: 20
                scale: 0.8
                transformOrigin: Item.Right
                opacity: 0.7
                radius: 5
                // A card even without a cover, so the stack always reads.
                tile: true
                player: root.others.find(other => other.trackArtUrl !== "") ?? root.others[0] ?? null
                markColor: Theme.barTextLow
            }

            MediaArt {
                width: 20
                height: 20
                radius: 5
                tile: false
                player: root.player
                dimmed: !root.playing
                markColor: mediaChip.fg
                markHighlighted: mediaChip.held || mediaChip.hovered
            }
        }

        // ---- title --------------------------------------------------------
        // One line in the configured order, the title brighter than the
        // artist. A title too long for the chip ends in an ellipsis at rest
        // and drifts through its full length while the pointer is on it.
        Item {
            id: titleClip

            readonly property real naturalWidth: Math.min(fullTitle.implicitWidth,
                Settings.modOpts.media.maxWidth)
            readonly property real overflow: Math.max(0, fullTitle.implicitWidth - width)
            readonly property bool drifting: (mediaChip.hovered || mediaChip.held)
                && overflow > 0 && !Theme.reducedMotion

            visible: !root.compact && naturalWidth > 0
            anchors.verticalCenter: parent.verticalCenter
            width: naturalWidth
            height: fullTitle.implicitHeight
            clip: true

            Text {
                id: fullTitle

                readonly property color mainColor: !root.playing ? Theme.barTextLow
                    : mediaChip.held || mediaChip.hovered ? Theme.barTextHi : Theme.barTextMid
                readonly property color sideColor: root.playing ? Theme.barTextDim : Theme.barTextFaint
                readonly property string first: root.escaped(root.label.first)
                readonly property string second: root.escaped(root.label.second)

                width: titleClip.drifting ? implicitWidth : titleClip.width
                textFormat: Text.StyledText
                text: root.label.second === "" ? first
                    : root.label.titleFirst
                        ? first + "<font color=\"" + sideColor + "\"> · " + second + "</font>"
                        : "<font color=\"" + sideColor + "\">" + first + " · </font>" + second
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.bar
                font.weight: Theme.weightSemibold
                color: mainColor
                elide: titleClip.drifting ? Text.ElideNone : Text.ElideRight
                maximumLineCount: 1

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                transform: Translate {
                    id: slide
                }
            }

            SequentialAnimation {
                running: titleClip.drifting
                loops: Animation.Infinite
                onRunningChanged: {
                    if (!running)
                        fullTitle.x = 0;
                }

                PauseAnimation { duration: 700 }
                NumberAnimation {
                    target: fullTitle
                    property: "x"
                    to: -titleClip.overflow
                    duration: Math.max(800, titleClip.overflow * 28)
                    easing.type: Easing.InOutSine
                }
                PauseAnimation { duration: 1100 }
                NumberAnimation {
                    target: fullTitle
                    property: "x"
                    to: 0
                    duration: Math.max(800, titleClip.overflow * 28)
                    easing.type: Easing.InOutSine
                }
            }

            // A new track rises into place instead of replacing the old one.
            ParallelAnimation {
                id: slideIn

                NumberAnimation {
                    target: slide
                    property: "y"
                    from: 10
                    to: 0
                    duration: 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
                NumberAnimation {
                    target: fullTitle
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 220
                }
            }
        }

        // ---- play / pause ---------------------------------------------------
        // Always there, so the chip never changes width. The ring around it is
        // the track's progress; it is grey while paused, and absent when the
        // player reports no length.
        Item {
            id: playButton

            readonly property bool hovered: playPointer.over

            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            scale: playMouse.pressed ? 0.86 : 1
            Accessible.role: Accessible.Button
            Accessible.name: root.playing ? I18n.tr("Pause") : I18n.tr("Play")
            Accessible.onPressAction: playMouse.toggle()

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.pressDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: playButton.hovered ? Theme.barChipHover : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                Accessible.ignored: true

                ShapePath {
                    strokeColor: Qt.rgba(Theme.barTextHi.r, Theme.barTextHi.g, Theme.barTextHi.b, 0.16)
                    strokeWidth: 2
                    fillColor: "transparent"

                    PathAngleArc {
                        centerX: 12
                        centerY: 12
                        radiusX: 10
                        radiusY: 10
                        startAngle: 0
                        sweepAngle: 360
                    }
                }

                ShapePath {
                    strokeColor: Media.length <= 0 ? "transparent"
                        : root.playing ? Theme.barAccent : Theme.barTextFaint
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: 12
                        centerY: 12
                        radiusX: 10
                        radiusY: 10
                        startAngle: -90
                        sweepAngle: 360 * Media.progress
                    }
                }
            }

            PlayGlyph {
                anchors.centerIn: parent
                playing: root.playing
                size: 11
                color: playButton.hovered ? Theme.barAccent : Theme.barTextHi
            }

            PointerCheck {
                id: playPointer
                host: root.host
                target: playButton
                hovered: playMouse.containsMouse
            }

            MouseArea {
                id: playMouse

                function toggle() {
                    if (root.player && root.player.canTogglePlaying)
                        root.player.togglePlaying();
                }

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toggle()
            }
        }
    }

    onTrackKeyChanged: {
        if (!Theme.reducedMotion && trackKey !== "")
            slideIn.restart();
    }
}
