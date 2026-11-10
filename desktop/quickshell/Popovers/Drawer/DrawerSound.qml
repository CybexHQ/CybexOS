pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../Common"
import "../../Common/AudioHelpers.js" as AudioHelpers
import "../../Common/Format.js" as Format
import ".."

// The drawer's Sound tab: the default output and its level, every output
// device as a row, the microphone with its live level, and per-application
// streams. Without an output it says why in the drawer's one empty-state
// pattern (DrawerEmptyState): the sound service is not running, or it has
// no speakers or headphones to play on.
Column {
    id: root
    property bool showSettingsAction: true

    // "" while there is an output to show; otherwise why there is none.
    readonly property string emptyKind: !Pipewire.ready ? "service"
        : !Audio.ready ? "device" : ""
    readonly property bool serviceDown: !Pipewire.ready

    readonly property var nodeValues: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sinkCandidates: AudioHelpers.outputDevices(
        nodeValues, Audio.outputSink, Audio.tuningPresent, Audio.speakerSink)
    readonly property var sourceCandidates: AudioHelpers.sourceDevices(
        nodeValues, Audio.source)
    readonly property var playbackCandidates: AudioHelpers.playbackStreams(nodeValues)
    readonly property var readyStreams: AudioHelpers.sortPlaybackStreams(
        playbackCandidates.filter(node => node && node.audio), Media.players)

    // Local outputs are the short list the drawer always shows; the AirPlay
    // and network targets can be a dozen rows, so they sit behind one
    // disclosure. A connected network sink stays visible while current.
    readonly property var localSinks: AudioHelpers.localSinks(
        sinkCandidates, Audio.outputSink)
    readonly property var networkSinks: AudioHelpers.networkSinks(
        sinkCandidates, Audio.outputSink)
    readonly property var visibleSinks: {
        const current = networkSinks.filter(node =>
            AudioHelpers.sameNode(node, Audio.outputSink));
        return networkOpen ? localSinks.concat(networkSinks)
            : localSinks.concat(current);
    }
    property bool networkOpen: false

    width: parent ? parent.width : 0
    spacing: Theme.scaled(14)

    PwObjectTracker { objects: root.sinkCandidates }
    PwObjectTracker { objects: root.sourceCandidates }
    PwObjectTracker { objects: root.playbackCandidates }

    PwNodePeakMonitor {
        id: inputPeak
        node: Audio.source
        // The monitor holds a capture stream open on the source while it is
        // enabled; a muted microphone has nothing to meter.
        enabled: root.visible && !!Audio.source && !Audio.sourceMuted
    }

    // The monitor's peak moves at the PipeWire buffer rate, and a meter bound
    // straight to it redrew the popout at display rate for as long as the tab
    // was open. Sample it at ~15 Hz instead; the meter rounds to whole pixels,
    // so a quiet microphone draws nothing at all.
    property real micPeak: 0

    Timer {
        interval: 66
        repeat: true
        running: inputPeak.enabled
        onTriggered: root.micPeak = Format.clamp01(inputPeak.peak)
        onRunningChanged: {
            if (!running)
                root.micPeak = 0;
        }
    }

    DrawerEmptyState {
        visible: root.emptyKind !== ""
        glyph: root.serviceDown ? "volume_off" : "headphones"
        title: root.emptyKind === "service" ? I18n.tr("Sound service isn't running")
            : I18n.tr("No speakers or headphones")
        detail: root.emptyKind === "service"
            ? I18n.tr("Apps can't play sound until it starts.")
            : I18n.tr("Connect speakers or headphones to hear sound.")
        actionText: root.showSettingsAction ? I18n.tr("Sound settings") : ""
        onAction: Settings.showPanel("sound", Popouts.hostScreenName)
    }

    // ---- output header ---------------------------------------------------
    Item {
        visible: root.emptyKind === ""
        width: parent.width
        height: 40

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: muteButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: Audio.outputName
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.title
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                // Shown only with an output (emptyKind), so there is always
                // a real level to report.
                text: (Audio.muted ? I18n.tr("Muted")
                        : I18n.format("Volume %1%", [Audio.volume]))
                    + (Audio.sourceReady
                        ? " · " + (Audio.sourceMuted ? I18n.tr("Microphone muted")
                            : I18n.format("Microphone %1%", [Audio.sourceVolume]))
                        : "")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
                elide: Text.ElideRight
            }
        }

        DrawerIconButton {
            id: muteButton
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            glyph: Audio.muted ? "volume_off" : "volume_up"
            glyphSize: 16
            tint: Audio.muted ? Theme.redText : Theme.textMid
            enabled: Audio.ready
            accessibleName: Audio.muted ? "Unmute output" : "Mute output"
            onClicked: Audio.toggleMuted()
        }
    }

    DrawerSliderRow {
        visible: root.emptyKind === ""
        glyph: Audio.muted || Audio.volume === 0 ? "volume_off"
            : Audio.volume < 50 ? "volume_down" : "volume_up"
        value: Audio.level
        ready: Audio.ready
        showValue: true
        accessibleName: "Output volume"
        onMoved: v => Audio.setVolume(v)
    }

    // ---- output devices --------------------------------------------------
    Column {
        visible: root.emptyKind === ""
        width: parent.width
        spacing: 2

        // Both lists derive from every PipeWire node, so any stream coming or
        // going — a notification sound, a browser tab, this tab's own mic
        // monitor — produced a fresh array. The ScriptModels diff it by node
        // identity: rows that survive keep their delegates, a slider mid-drag
        // included.
        Repeater {
            model: ScriptModel {
                values: root.visibleSinks
            }

            delegate: Rectangle {
                id: sinkRow

                required property var modelData
                readonly property bool current: AudioHelpers.sameNode(
                    modelData, Audio.outputSink)
                    || (Audio.tuningPresent && AudioHelpers.sameNode(
                        modelData, Audio.speakerSink)
                        && AudioHelpers.sameNode(Audio.outputSink, Audio.tuningSink))

                width: parent ? parent.width : 0
                height: 36
                radius: Theme.rowRadius
                color: current ? Theme.chip
                    : sinkMouse.containsMouse ? Theme.chip : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Sym {
                    id: sinkMark
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    name: AudioHelpers.sinkGlyph(sinkRow.modelData)
                    size: 16
                    color: sinkRow.current ? Theme.accentText : Theme.textMid
                }

                Text {
                    anchors.left: sinkMark.right
                    anchors.leftMargin: 12
                    anchors.right: sinkCheck.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: AudioHelpers.sinkLabel(sinkRow.modelData)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    font.weight: sinkRow.current
                        ? Theme.weightSemibold : Theme.weightMedium
                    color: sinkRow.current ? Theme.textHi : Theme.textMid
                    elide: Text.ElideRight
                }

                Sym {
                    id: sinkCheck
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"
                    size: 16
                    color: Theme.accentText
                    visible: sinkRow.current
                }

                MouseArea {
                    id: sinkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.setDefaultSink(sinkRow.modelData)
                }

                Accessible.role: Accessible.Button
                Accessible.name: I18n.format("Switch output to %1",
                    [AudioHelpers.sinkLabel(sinkRow.modelData)])
            }
        }

        // The AirPlay / network targets, folded behind one row.
        Rectangle {
            visible: root.networkSinks.length > 0
            width: parent.width
            height: 32
            radius: Theme.rowRadius
            color: networkDisclosureMouse.containsMouse
                ? Theme.chip : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }

            Sym {
                id: networkDisclosureMark
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                name: "cast"
                size: 15
                color: Theme.textFaint
            }

            Text {
                anchors.left: networkDisclosureMark.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.networkOpen ? "Hide network outputs"
                    : root.networkSinks.length + " network outputs"
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.control
                font.weight: Theme.weightMedium
                color: Theme.textFaint
            }

            Sym {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                name: root.networkOpen ? "expand_less" : "expand_more"
                size: 16
                color: Theme.textFaint
            }

            MouseArea {
                id: networkDisclosureMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.networkOpen = !root.networkOpen
            }

            Accessible.role: Accessible.Button
            Accessible.name: root.networkOpen
                ? "Hide network outputs" : "Show network outputs"
        }
    }

    // ---- microphone ------------------------------------------------------
    Column {
        visible: Audio.sourceReady
        width: parent.width
        spacing: 6

        SectionLabel {
            width: parent.width
            text: I18n.tr("MICROPHONE")
            detail: Audio.sourceMuted ? "muted" : Audio.sourceVolume + ""
        }

        Rectangle {
            width: parent.width
            height: 36
            radius: Theme.rowRadius
            color: Theme.chip

            Sym {
                id: micMark
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                name: Audio.sourceMuted ? "mic_off" : "mic"
                size: 16
                color: Audio.sourceMuted ? Theme.redText : Theme.accentText
            }

            Text {
                anchors.left: micMark.right
                anchors.leftMargin: 12
                anchors.right: micLevel.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: AudioHelpers.sourceLabel(Audio.source)
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Rectangle {
                id: micLevel
                anchors.right: micMute.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 60
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.10)

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.round(parent.width * root.micPeak)
                    radius: 2
                    color: Theme.ok
                }
            }

            DrawerIconButton {
                id: micMute
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                glyph: Audio.sourceMuted ? "mic_off" : "mic"
                glyphSize: 15
                tint: Audio.sourceMuted ? Theme.redText : Theme.textFaint
                accessibleName: Audio.sourceMuted
                    ? "Unmute microphone" : "Mute microphone"
                onClicked: Audio.toggleSourceMuted()
            }
        }
    }

    // ---- application streams ---------------------------------------------
    Column {
        visible: root.readyStreams.length > 0
        width: parent.width
        spacing: 2

        SectionLabel {
            width: parent.width
            text: I18n.tr("APPS")
            detail: String(root.readyStreams.length)
        }

        Repeater {
            model: ScriptModel {
                values: root.readyStreams
            }

            delegate: Item {
                id: streamRow

                required property var modelData
                readonly property var streamAudio: modelData && modelData.audio
                    ? modelData.audio : null
                readonly property real streamLevel: streamAudio
                    ? Format.clamp01(streamAudio.volume) : 0

                width: parent ? parent.width : 0
                height: 32

                Text {
                    id: streamName
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 72
                    text: AudioHelpers.streamLabel(streamRow.modelData,
                        Media.players, root.readyStreams)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                    elide: Text.ElideRight
                }

                HSlider {
                    anchors.left: streamName.right
                    anchors.leftMargin: 10
                    anchors.right: streamPct.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    value: streamRow.streamLevel
                    accessibleName: streamName.text + " volume"
                    onMoved: v => {
                        if (streamRow.streamAudio)
                            streamRow.streamAudio.volume = v;
                    }
                }

                Text {
                    id: streamPct
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(streamRow.streamLevel * 100) + "%"
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.typography.metadata
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textFaint
                }
            }
        }
    }

    // The empty state carries its own way to Settings.
    DrawerFooter {
        visible: root.showSettingsAction && root.emptyKind === ""
        actionText: I18n.tr("Sound settings")
        onActionClicked: {
            Settings.showPanel("sound");
        }
    }
}
