import QtQuick
import Quickshell
import Quickshell.Wayland
import "Common"

// The words of a dictation while you speak (docs/dictation.md): a pill where
// the volume OSD sits, on the overlay layer, never taking the keyboard, so
// the window you are dictating into keeps its focus. The words are typed
// into that window only when you stop; until then they are Whisper's best
// guess and may still change.
PanelWindow {
    id: root

    readonly property string phase: Dictation.phase
    readonly property bool shown: phase !== "" && phase !== "done"
    readonly property bool listening: phase === "starting" || phase === "listening"
    readonly property bool working: phase === "finishing" || phase === "typing"
    readonly property bool problem: phase === "failed" || phase === "empty"

    visible: shown || pill.opacity > 0.001
    screen: Screens.focused
    readonly property bool atTop: Settings.osd === "top"
    readonly property int barClearance: Theme.barTopMargin + Theme.barHeight + 12
    readonly property bool sharesBarScreen: Screens.hasBar(root.screen)
    // Clear of the welcome guide's resume pill, which sits at the bottom
    // while the guide is set aside (WelcomeWindow.qml).
    readonly property int welcomeClearance: !atTop && Welcome.open && Welcome.aside ? Theme.scaled(56) : 0
    anchors {
        top: atTop
        bottom: !atTop
    }
    // PanelWindow.margins is a Quickshell group qmllint cannot resolve.
    // qmllint disable unqualified
    margins {
        top: atTop && Settings.position === "top" && sharesBarScreen ? barClearance : 12
        bottom: (!atTop && Settings.position === "bottom" && sharesBarScreen ? barClearance : 12) + welcomeClearance
    }
    // qmllint enable unqualified
    readonly property int pad: 48
    implicitWidth: maxPillWidth + pad * 2
    implicitHeight: pill.implicitHeight + pad * 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-dictation"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: pill
    }

    readonly property real maxPillWidth: Math.min(Theme.scaled(620), (screen ? screen.width : 1280) - 64)
    readonly property real textRoom: maxPillWidth - Theme.panelPadding * 2 - Theme.iconMedium - Theme.controlSpacing

    // The end of what was said: two lines' worth, cut at a word.
    function tail(text) {
        const limit = 150;
        if (text.length <= limit)
            return text;
        const cut = text.slice(text.length - limit);
        const space = cut.indexOf(" ");
        return "…" + (space > 0 && space < 30 ? cut.slice(space + 1) : cut);
    }

    readonly property string words: tail(Dictation.liveText)
    readonly property string statusText: {
        switch (phase) {
        case "starting": return I18n.tr("Starting…");
        case "listening": return I18n.tr("Listening…");
        case "finishing": return I18n.tr("Finishing…");
        case "typing": return I18n.tr("Typing…");
        case "copied": return I18n.tr("Copied to the clipboard. Paste with Ctrl+V.");
        case "empty": return I18n.tr("No speech heard");
        case "failed":
            switch (Dictation.failure) {
            case "microphone": return I18n.tr("The microphone did not start");
            case "timeout": return I18n.tr("Dictation took too long to finish");
            case "typing": return I18n.tr("Your words could not be typed");
            default: return I18n.tr("Dictation failed");
            }
        default: return "";
        }
    }
    // While words arrive they are the message; the status says what
    // happens next.
    readonly property bool showWords: words !== "" && (listening || working)

    Rectangle {
        id: pill

        x: root.pad + (root.maxPillWidth - width) / 2
        y: root.pad + (root.shown ? 0 : root.atTop ? -16 : 16)
        opacity: root.shown ? 1 : 0
        width: Math.min(root.maxPillWidth, Math.max(Theme.scaled(220), content.implicitWidth + Theme.panelPadding * 2))
        implicitHeight: Math.max(Theme.controlHeight, content.implicitHeight + Theme.scaled(20))
        radius: Math.min(height / 2, Theme.popRadius * 2)
        color: Theme.panelSurface
        border.width: 1
        border.color: root.problem ? Theme.redBorder : Theme.popBorder
        Accessible.role: Accessible.StatusBar
        Accessible.name: root.showWords ? root.words : root.statusText

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.panelFadeDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: Theme.panelMotionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Row {
            id: content
            x: Theme.panelPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.controlSpacing

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconMedium
                height: Theme.iconMedium

                // A soft pulse behind the microphone while it listens.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + Theme.scaled(10)
                    height: width
                    radius: width / 2
                    color: Theme.redText
                    visible: root.listening && !Theme.reducedMotion
                    opacity: 0

                    SequentialAnimation on opacity {
                        running: root.listening && root.visible && !Theme.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.28; to: 0.04; duration: 900; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 200 }
                    }
                }

                Sym {
                    anchors.centerIn: parent
                    name: root.listening ? "mic"
                        : root.working ? "loader-2"
                        : root.phase === "copied" ? "content_paste"
                        : root.phase === "empty" ? "mic_off"
                        : "error"
                    size: Theme.iconMedium
                    color: root.listening || root.problem ? Theme.redText : Theme.textHi
                }
            }

            // Sized by its text, up to the pill's room; a width taken from
            // the column itself would loop back to nothing.
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.scaled(2)

                Text {
                    visible: root.showWords
                    width: Math.min(implicitWidth, root.textRoom)
                    text: root.words
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    // Still Whisper's guess until the dictation ends.
                    color: root.working ? Theme.textMid : Theme.textHi
                }

                Text {
                    width: Math.min(implicitWidth, root.textRoom)
                    text: root.statusText
                    elide: Text.ElideRight
                    font.family: Theme.fontMenu
                    font.pixelSize: root.showWords ? Theme.typography.metadata : Theme.typography.primary
                    color: root.problem ? Theme.redText : root.showWords ? Theme.textLow : Theme.textHi
                }
            }
        }

        // A click stops a dictation that is listening.
        MouseArea {
            anchors.fill: parent
            enabled: root.listening
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: Dictation.stop()
        }
    }
}
