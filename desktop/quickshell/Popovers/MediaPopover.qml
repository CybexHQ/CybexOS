pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../Common"
import "../Common/Format.js" as Format

// The media panel: which app is playing and a way to it, the cover and the
// track, a seek bar, the usual centred transport, this player's own volume,
// and every other player underneath.
//
// It shows Media.player, the same player as the bar chip. Picking one of the
// other players pins it for both until another player starts playing.
//
// The cover's colours wash the top of the panel. The wash is scrimmed so the
// copy over it keeps the contrast the colour ladder was calibrated for, and
// it ends above the seek bar, so nothing below has to know about artwork.
Surface {
    id: root

    padding: 0
    spacing: 0
    focus: visible

    readonly property var player: Media.player
    readonly property var others: Media.others
    readonly property bool playing: Media.playing
    readonly property real len: Media.length
    readonly property bool seekable: player !== null && player.canSeek && len > 0
    // No length and no seeking is what a live stream looks like over MPRIS.
    readonly property bool live: player !== null && len <= 0 && !player.canSeek
    readonly property bool hasArt: player !== null && player.trackArtUrl !== ""
    property string announcement: ""

    readonly property int heroSize: 104
    readonly property int headerHeight: 44
    readonly property int washHeight: headerHeight + heroSize + 46
    // How much of the artwork survives the scrim at the top of the panel. A
    // paused panel keeps its colour, a step quieter: losing the field
    // entirely would restyle the whole panel on every pause.
    property real washStrength: playing ? 0.62 : 0.42
    Behavior on washStrength {
        NumberAnimation { duration: Theme.surfaceDuration }
    }
    readonly property real washFadeStart: root.height > 0
        ? Math.max(0, (root.washHeight - 90) / root.height) : 0
    readonly property real washFadeEnd: root.height > 0
        ? Math.min(1, root.washHeight / root.height) : 1

    // ---- keyboard ---------------------------------------------------------
    // Arrows act on playback wherever focus is; Tab walks the controls and
    // Space or Enter presses the focused one.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Popouts.close();
        } else if (!root.player) {
            return;
        } else if (event.key === Qt.Key_Space) {
            root.player.togglePlaying();
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            const forward = event.key === Qt.Key_Right;
            if (event.modifiers & Qt.ShiftModifier) {
                if (forward && root.player.canGoNext)
                    root.player.next();
                else if (!forward && root.player.canGoPrevious)
                    root.player.previous();
            } else {
                Media.seekBy(forward ? 10 : -10);
            }
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            Media.stepVolume(event.key === Qt.Key_Up ? 0.05 : -0.05);
        } else {
            return;
        }
        event.accepted = true;
    }

    function announceMedia() {
        if (!player) {
            announcement = I18n.tr("Nothing playing");
            return;
        }
        const title = player.trackTitle || I18n.tr("Unknown track");
        announcement = (player.identity || I18n.tr("Media")) + ": " + title
            + (playing ? I18n.tr(", playing") : I18n.tr(", paused"));
    }

    function focusInitial() {
        if (!visible)
            return;
        Qt.callLater(() => {
            if (playButton.visible && playButton.available)
                playButton.forceActiveFocus();
            else
                root.forceActiveFocus();
        });
    }

    onVisibleChanged: focusInitial()
    onPlayerChanged: {
        announceMedia();
        focusInitial();
    }
    onPlayingChanged: announceMedia()

    readonly property string trackKey: player
        ? player.trackTitle + "\n" + player.trackArtist + "\n" + player.identity : ""
    onTrackKeyChanged: {
        announceMedia();
        if (visible && !Theme.reducedMotion && trackKey !== "")
            heroSlide.restart();
    }

    // ---- pieces -------------------------------------------------------------
    // Three bars that rise and fall while the player plays; reduced motion
    // keeps them still. Paused, they are not there: three flat bars read as
    // an ellipsis.
    component LevelBars: Row {
        id: bars

        property bool active: false
        property color tone: Theme.accentText

        visible: active
        spacing: 2
        height: 10
        Accessible.ignored: true

        Repeater {
            model: 3

            Rectangle {
                id: bar

                required property int index

                y: bars.height - height
                width: 2
                height: 3
                radius: 1
                color: bars.active ? bars.tone : Theme.textFaint

                SequentialAnimation on height {
                    running: bars.active && bars.visible && !Theme.reducedMotion
                    loops: Animation.Infinite
                    onRunningChanged: {
                        if (!running)
                            bar.height = 3;
                    }

                    PauseAnimation { duration: bar.index * 160 }
                    NumberAnimation { to: 10; duration: 420; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 3; duration: 420; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // A round control. `filled` is play, the panel's one filled button; the
    // modifiers light in the accent with a dot under them while on; `shown`
    // false keeps a slot for a modifier the player does not have, so the
    // transport stays centred.
    component TransportButton: Rectangle {
        id: button

        property string glyph
        // Play and pause are drawn solid (PlayGlyph); the rest are outlines.
        property bool playGlyph: false
        property bool playGlyphPlaying: false
        property int diameter: 42
        property int glyphSize: Theme.iconLarge
        property bool filled: false
        property bool active: false
        property bool toggle: false
        property bool available: true
        property bool shown: true
        property string accessibleName: ""
        property string accessibleDescription: ""
        signal triggered

        readonly property bool hovered: buttonMouse.containsMouse

        width: diameter
        height: diameter
        radius: diameter / 2
        visible: shown
        opacity: available ? 1 : 0.35
        scale: buttonMouse.pressed ? 0.9 : 1
        activeFocusOnTab: shown && available
        Accessible.role: toggle ? Accessible.CheckBox : Accessible.Button
        Accessible.name: button.accessibleName
        Accessible.description: button.accessibleDescription
        Accessible.checked: toggle && active
        Accessible.onPressAction: {
            if (button.available)
                button.triggered();
        }
        color: {
            if (button.filled)
                return button.hovered ? Qt.lighter(Theme.textHi, 1.08) : Theme.textHi;
            return button.hovered || button.activeFocus ? Theme.chipHover : "transparent";
        }
        border.width: Theme.focusWidth(activeFocus)
        border.color: Theme.focusRing

        Keys.onPressed: event => {
            if (button.available && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space)) {
                button.triggered();
                event.accepted = true;
            }
        }

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        Behavior on scale {
            NumberAnimation {
                duration: Theme.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        readonly property color inkColor: button.filled ? Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 1)
            : button.active ? Theme.accentText
            : button.hovered ? Theme.textHi : Theme.icon

        Sym {
            anchors.centerIn: parent
            visible: !button.playGlyph
            name: button.glyph
            size: button.glyphSize
            color: button.inkColor
        }

        PlayGlyph {
            anchors.centerIn: parent
            visible: button.playGlyph
            playing: button.playGlyphPlaying
            size: Math.round(button.glyphSize * 0.75)
            color: button.inkColor
        }

        Rectangle {
            visible: button.toggle && button.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            width: 4
            height: 4
            radius: 2
            color: Theme.accentText
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: button.available && button.shown
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                button.forceActiveFocus();
                button.triggered();
            }
        }
    }

    // A square icon button for the header and the volume row.
    component IconButton: Rectangle {
        id: iconButton

        property string glyph
        property color tone: Theme.icon
        property string accessibleName: ""
        signal triggered

        readonly property bool hovered: iconMouse.containsMouse

        width: 30
        height: 30
        radius: Theme.chipRadius
        color: hovered || activeFocus ? Theme.chipHover : "transparent"
        border.width: Theme.focusWidth(activeFocus)
        border.color: Theme.focusRing
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.onPressAction: iconButton.triggered()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                iconButton.triggered();
                event.accepted = true;
            }
        }

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        Sym {
            anchors.centerIn: parent
            name: iconButton.glyph
            size: Theme.iconMedium
            color: iconButton.hovered ? Theme.textHi : iconButton.tone
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.triggered()
        }
    }

    // ---- the wash ------------------------------------------------------------
    // One layer, clipped and faded by the panel's own backdrop mask: the
    // cover, tiny and stretched (the stretch is the blur), knocked back by a
    // scrim that strengthens towards the copy.
    backdropMaskGradient: Gradient {
        GradientStop { position: 0; color: "#ffffff" }
        GradientStop { position: root.washFadeStart; color: "#ffffff" }
        GradientStop { position: root.washFadeEnd; color: "#00ffffff" }
        GradientStop { position: 1; color: "#00ffffff" }
    }

    backdrop: Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.washHeight
        visible: root.hasArt

        Image {
            anchors.fill: parent
            source: root.player ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(24, 24)
            asynchronous: true
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                brightness: Theme.dark ? -0.45 : 0.25
                saturation: 0.6
            }
        }

        // The scrim is the panel's own surface, so where it closes up it
        // matches what is around it.
        Rectangle {
            id: scrim

            readonly property color base: root.surfaceColor

            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(scrim.base.r, scrim.base.g, scrim.base.b, 1 - root.washStrength)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.rgba(scrim.base.r, scrim.base.g, scrim.base.b, 1 - root.washStrength * 0.62)
                }
                GradientStop {
                    position: 0.78
                    color: Qt.rgba(scrim.base.r, scrim.base.g, scrim.base.b, 0.94)
                }
                // Closes up into the surface itself, so the field has no edge.
                GradientStop {
                    position: 1
                    color: Qt.rgba(scrim.base.r, scrim.base.g, scrim.base.b, 1)
                }
            }
        }
    }

    // ---- header: the app, its state, and a way to it ------------------------
    Item {
        width: parent.width
        height: root.headerHeight
        visible: root.player !== null

        Row {
            x: Theme.panelPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            MediaArt {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                radius: 4
                tile: false
                markOnly: true
                player: root.player
                markColor: Theme.textMid
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.width - Theme.panelPadding * 2 - 170)
                text: root.player ? root.player.identity : ""
                elide: Text.ElideRight
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            LevelBars {
                anchors.verticalCenter: parent.verticalCenter
                active: root.playing
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.playing ? I18n.tr("Playing") : I18n.tr("Paused")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightMedium
                color: Theme.textDim
            }
        }

        IconButton {
            id: showButton
            anchors.right: parent.right
            anchors.rightMargin: Theme.panelPadding - 6
            anchors.verticalCenter: parent.verticalCenter
            visible: root.player !== null && Media.canShow(root.player)
            glyph: "open_in_new"
            accessibleName: I18n.format("Show %1", [root.player ? root.player.identity : ""])
            onTriggered: {
                if (Media.show(root.player))
                    Popouts.close();
            }
        }
    }

    // ---- cover and track ------------------------------------------------------
    Item {
        width: parent.width
        height: root.heroSize
        visible: root.player !== null

        MediaArt {
            id: hero
            x: Theme.panelPadding
            width: root.heroSize
            height: root.heroSize
            radius: Theme.cardRadius + 3
            player: root.player
            markColor: Theme.textDim
        }

        Item {
            anchors.left: hero.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: Theme.panelPadding
            anchors.verticalCenter: hero.verticalCenter
            height: trackColumn.implicitHeight

            Column {
                id: trackColumn
                width: parent.width
                spacing: 3

                transform: Translate {
                    id: heroOffset
                }

                Text {
                    width: parent.width
                    text: root.player && root.player.trackTitle !== ""
                        ? root.player.trackTitle : I18n.tr("Unknown track")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.title
                    font.weight: Theme.weightBold
                    font.letterSpacing: -0.3
                    color: Theme.textHi
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 1.15
                }

                Text {
                    width: parent.width
                    topPadding: 2
                    visible: text !== ""
                    text: root.player ? root.player.trackArtist : ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    font.weight: Theme.weightSemibold
                    color: Theme.textMid
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.player ? root.player.trackAlbum : ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    font.weight: Theme.weightMedium
                    color: Theme.textDim
                    elide: Text.ElideRight
                }
            }

            ParallelAnimation {
                id: heroSlide

                NumberAnimation {
                    target: heroOffset
                    property: "y"
                    from: 12
                    to: 0
                    duration: 340
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
                NumberAnimation {
                    target: trackColumn
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 240
                }
            }
        }
    }

    // ---- seek -------------------------------------------------------------------
    // Thicker under the pointer, with the time the pointer is over. A drag
    // previews and seeks once, on release. The end time switches to the time
    // remaining and stays that way for the session.
    Item {
        id: seek

        readonly property bool hovered: seekMouse.containsMouse || seekMouse.pressed
        property real preview: -1
        readonly property real shownPosition: preview >= 0 ? preview : Media.position
        readonly property real ratio: root.len > 0 ? Format.clamp01(shownPosition / root.len) : 0

        function timeAt(x) {
            return Format.clamp01(x / seekTrack.width) * root.len;
        }

        width: parent.width - Theme.panelPadding * 2
        x: Theme.panelPadding
        height: 52
        visible: root.player !== null
        Accessible.role: Accessible.Slider
        Accessible.name: I18n.tr("Seek")
        Accessible.description: Format.mmss(Media.position)
        Accessible.onIncreaseAction: Media.seekBy(10)
        Accessible.onDecreaseAction: Media.seekBy(-10)

        Rectangle {
            id: seekTrack
            y: 24 - height / 2
            width: parent.width
            height: seek.hovered && root.seekable ? 6 : 4
            radius: height / 2
            color: Qt.rgba(Theme.textHi.r, Theme.textHi.g, Theme.textHi.b, 0.14)

            Behavior on height {
                NumberAnimation { duration: 120 }
            }

            Rectangle {
                width: root.live ? parent.width : parent.width * seek.ratio
                height: parent.height
                radius: parent.radius
                color: root.seekable ? Theme.textHi : Theme.textFaint
            }

            Rectangle {
                visible: root.seekable
                x: parent.width * seek.ratio - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: Theme.textHi
                scale: seek.hovered ? 1 : 0

                Behavior on scale {
                    NumberAnimation { duration: 120 }
                }
            }
        }

        // The time under the pointer.
        Rectangle {
            visible: seekMouse.containsMouse && root.seekable
            x: Math.max(0, Math.min(seek.width - width, seekMouse.mouseX - width / 2))
            y: seekTrack.y - height - 4
            width: hoverTime.implicitWidth + 12
            height: hoverTime.implicitHeight + 6
            radius: 5
            color: Theme.menuBg
            border.width: 1
            border.color: Theme.hairline

            Text {
                id: hoverTime
                anchors.centerIn: parent
                text: Format.mmss(seek.timeAt(seekMouse.mouseX))
                font.family: Theme.fontNumeric
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightSemibold
                font.features: Theme.tabularNumberFeatures
                color: Theme.textHi
            }
        }

        MouseArea {
            id: seekMouse
            x: 0
            y: seekTrack.y - 8
            width: parent.width
            height: seekTrack.height + 16
            hoverEnabled: true
            enabled: root.seekable
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => seek.preview = seek.timeAt(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    seek.preview = seek.timeAt(mouse.x);
            }
            onReleased: mouse => {
                Media.seek(seek.timeAt(mouse.x));
                seek.preview = -1;
            }
            onCanceled: seek.preview = -1
        }

        Text {
            anchors.left: parent.left
            y: 34
            text: root.live ? I18n.tr("Live") : Format.mmss(seek.shownPosition)
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.metadata
            font.weight: root.live ? Theme.weightBold : Theme.weightMedium
            font.features: Theme.tabularNumberFeatures
            font.capitalization: root.live ? Font.AllUppercase : Font.MixedCase
            color: root.live ? Theme.redText : Theme.textMid
        }

        Text {
            id: endTime
            anchors.right: parent.right
            y: 34
            visible: root.len > 0
            text: Media.showRemaining ? "-" + Format.mmss(root.len - seek.shownPosition)
                : Format.mmss(root.len)
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightMedium
            font.features: Theme.tabularNumberFeatures
            color: endMouse.containsMouse ? Theme.textHi : Theme.textDim
            Accessible.role: Accessible.Button
            Accessible.name: Media.showRemaining ? I18n.tr("Show track length") : I18n.tr("Show time remaining")
            Accessible.onPressAction: Media.showRemaining = !Media.showRemaining

            MouseArea {
                id: endMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Media.showRemaining = !Media.showRemaining
            }
        }
    }

    // ---- transport --------------------------------------------------------------
    Item {
        width: parent.width
        height: 68
        visible: root.player !== null

        Row {
            anchors.centerIn: parent
            spacing: 12

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "shuffle"
                diameter: 34
                glyphSize: Theme.iconMedium
                toggle: true
                shown: root.player !== null && root.player.shuffleSupported
                active: root.player !== null && root.player.shuffle
                available: root.player !== null && root.player.canControl
                accessibleName: I18n.tr("Shuffle")
                accessibleDescription: active ? I18n.tr("On") : I18n.tr("Off")
                onTriggered: root.player.shuffle = !root.player.shuffle
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "skip_previous"
                available: root.player !== null && root.player.canGoPrevious
                accessibleName: I18n.tr("Previous track")
                onTriggered: root.player.previous()
            }

            TransportButton {
                id: playButton
                anchors.verticalCenter: parent.verticalCenter
                playGlyph: true
                playGlyphPlaying: root.playing
                diameter: 54
                glyphSize: Theme.iconHero
                filled: true
                available: root.player !== null && root.player.canTogglePlaying
                accessibleName: root.playing ? I18n.tr("Pause") : I18n.tr("Play")
                onTriggered: root.player.togglePlaying()
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "skip_next"
                available: root.player !== null && root.player.canGoNext
                accessibleName: I18n.tr("Next track")
                onTriggered: root.player.next()
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                // Repeat has two on-states, so one track takes its own mark.
                glyph: root.player && root.player.loopState === MprisLoopState.Track
                    ? "repeat_one" : "repeat"
                diameter: 34
                glyphSize: Theme.iconMedium
                toggle: true
                shown: root.player !== null && root.player.loopSupported
                active: root.player !== null && root.player.loopState !== MprisLoopState.None
                available: root.player !== null && root.player.canControl
                accessibleName: I18n.tr("Repeat")
                accessibleDescription: !root.player
                    || root.player.loopState === MprisLoopState.None ? I18n.tr("Off")
                    : root.player.loopState === MprisLoopState.Track ? I18n.tr("One track") : I18n.tr("Playlist")
                onTriggered: {
                    const s = root.player.loopState;
                    root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                        : s === MprisLoopState.Playlist ? MprisLoopState.Track
                        : MprisLoopState.None;
                }
            }
        }
    }

    // ---- this player's volume ---------------------------------------------------
    Item {
        width: parent.width
        height: 40
        visible: root.player !== null && Media.volumeAvailable

        IconButton {
            id: muteButton
            x: Theme.panelPadding - 6
            anchors.verticalCenter: parent.verticalCenter
            glyph: Media.muted || Media.volume <= 0 ? "volume_off"
                : Media.volume < 0.5 ? "volume_down" : "volume_up"
            tone: Media.muted ? Theme.redText : Theme.icon
            accessibleName: Media.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
            onTriggered: Media.toggleMuted()
        }

        HSlider {
            anchors.left: muteButton.right
            anchors.leftMargin: 6
            anchors.right: volumeText.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            value: Media.muted ? 0 : Media.volume
            dimmed: Media.muted
            accessibleName: I18n.format("%1 volume", [root.player ? root.player.identity : ""])
            onMoved: v => Media.setVolume(v)
        }

        Text {
            id: volumeText
            anchors.right: parent.right
            anchors.rightMargin: Theme.panelPadding
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            text: Media.muted ? I18n.tr("Muted") : Math.round(Media.volume * 100) + "%"
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightMedium
            font.features: Theme.tabularNumberFeatures
            color: Media.muted ? Theme.redText : Theme.textDim
        }
    }

    Item {
        width: parent.width
        height: 10
        visible: root.player !== null
    }

    // ---- other players -----------------------------------------------------------
    // A row brings its player to the top; its button plays or pauses it where
    // it is.
    Column {
        width: parent.width
        visible: root.player !== null && root.others.length > 0
        bottomPadding: 8

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairline
        }

        Text {
            x: Theme.panelPadding
            topPadding: 12
            bottomPadding: 6
            text: I18n.tr("Other players")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightSemibold
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
            color: Theme.textFaint
        }

        Repeater {
            model: root.others

            Rectangle {
                id: otherRow

                required property var modelData
                readonly property bool otherPlaying: modelData !== null && modelData.isPlaying

                x: 8
                width: parent.width - 16
                height: 48
                radius: Theme.rowRadius
                color: rowMouse.containsMouse || activeFocus ? Theme.chip : "transparent"
                border.width: Theme.focusWidth(activeFocus)
                border.color: Theme.focusRing
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: I18n.format("Show %1", [modelData ? modelData.identity : ""])
                Accessible.description: modelData ? modelData.trackTitle : ""
                Accessible.onPressAction: Media.pin(otherRow.modelData)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        Media.pin(otherRow.modelData);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Space) {
                        if (otherRow.modelData.canTogglePlaying)
                            otherRow.modelData.togglePlaying();
                        event.accepted = true;
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Media.pin(otherRow.modelData)
                }

                MediaArt {
                    id: otherArt
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 6
                    player: otherRow.modelData
                    dimmed: !otherRow.otherPlaying
                }

                Column {
                    anchors.left: otherArt.right
                    anchors.leftMargin: 10
                    anchors.right: otherToggle.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: otherRow.modelData ? otherRow.modelData.trackTitle : ""
                        elide: Text.ElideRight
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        LevelBars {
                            anchors.verticalCenter: parent.verticalCenter
                            active: otherRow.otherPlaying
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (otherRow.otherPlaying ? 16 : 0)
                            text: (otherRow.modelData ? otherRow.modelData.identity : "") + " · "
                                + (otherRow.otherPlaying ? I18n.tr("Playing") : I18n.tr("Paused"))
                            elide: Text.ElideRight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.metadata
                            font.weight: Theme.weightMedium
                            color: Theme.textDim
                        }
                    }
                }

                TransportButton {
                    id: otherToggle
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    playGlyph: true
                    playGlyphPlaying: otherRow.otherPlaying
                    diameter: 32
                    glyphSize: Theme.iconMedium
                    available: otherRow.modelData !== null && otherRow.modelData.canTogglePlaying
                    accessibleName: otherRow.otherPlaying
                        ? I18n.format("Pause %1", [otherRow.modelData ? otherRow.modelData.identity : ""])
                        : I18n.format("Play %1", [otherRow.modelData ? otherRow.modelData.identity : ""])
                    onTriggered: otherRow.modelData.togglePlaying()
                }
            }
        }
    }

    // ---- nothing playing ------------------------------------------------------
    // Only reachable when a player quits while the panel is open: the bar
    // chip hides itself when there is nothing to show.
    Item {
        width: parent.width
        height: 176
        visible: root.player === null

        Column {
            anchors.centerIn: parent
            width: parent.width - Theme.panelPadding * 4
            spacing: 0

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 56
                radius: 28
                color: Theme.chip

                Sym {
                    anchors.centerIn: parent
                    name: "music_note"
                    size: Theme.iconHero
                    color: Theme.textDim
                }
            }

            Text {
                width: parent.width
                topPadding: 14
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Nothing playing")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                color: Theme.textMid
            }

            Text {
                width: parent.width
                topPadding: 5
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Start music or a video, and it shows up here.")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                font.weight: Theme.weightRegular
                color: Theme.textDim
                wrapMode: Text.Wrap
            }
        }
    }

    Item {
        width: 1
        height: 1
        opacity: 0
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.announcement
    }

    Component.onCompleted: {
        announceMedia();
        focusInitial();
    }
}
