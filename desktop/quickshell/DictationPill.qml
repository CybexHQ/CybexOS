import QtQuick
import Quickshell
import Quickshell.Wayland
import "Common"

// The words of a dictation while you speak (docs/dictation.md): a pill where
// the volume OSD sits, on the overlay layer, never taking the keyboard, so
// the window you are dictating into keeps its focus. The words are typed
// into that window only when you stop; until then they are the model's best
// guess and may still change. With tidy-up on, the tidied words replace them
// before they are typed, and the pill says how it went, with the original
// words a click away.
PanelWindow {
    id: root

    readonly property string phase: Dictation.phase
    readonly property var result: Dictation.lastResult
    // A finished dictation shows only when there is something to say: it was
    // tidied (the original is a click away) or polishing did not answer.
    readonly property bool doneNote: phase === "done" && (result.tidied === true || result.polishFailed === true)
    readonly property bool shown: phase !== "" && (phase !== "done" || doneNote)
    readonly property bool listening: phase === "starting" || phase === "listening"
    readonly property bool tidying: phase === "tidying"
    readonly property bool working: phase === "finishing" || phase === "typing" || tidying
    readonly property bool problem: phase === "failed" || phase === "empty"
    // The one action a finished pill offers.
    readonly property string action: phase === "done" && result.tidied === true ? I18n.tr("Copy original")
        : phase === "failed" && result.id ? I18n.tr("Open history") : ""
    readonly property string agentName: Settings.modOpts.indicators.dictationPolishAgent === "codex"
        ? "Codex" : "Claude"

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

    readonly property string words: tail(Dictation.shownText)
    readonly property string statusText: {
        switch (phase) {
        case "starting": return I18n.tr("Starting…");
        case "listening": return I18n.tr("Listening…");
        case "finishing": return I18n.tr("Finishing…");
        case "tidying":
            return Dictation.tidyMode === "polish"
                ? I18n.format(I18n.tr("Polishing with %1… Click to type it as said"), [agentName])
                : I18n.tr("Tidying…");
        case "typing": return I18n.tr("Typing…");
        case "done":
            return result.polishFailed === true
                ? I18n.format(I18n.tr("Typed with basic tidy-up: %1 did not answer"), [agentName])
                : I18n.format(I18n.tr("Typed %1 words · tidied"), [result.words || 0]);
        case "copied": return I18n.tr("Copied to the clipboard. Paste with Ctrl+V.");
        case "empty": return I18n.tr("No speech heard");
        case "failed":
            switch (Dictation.failure) {
            case "microphone": return I18n.tr("The microphone did not start");
            case "timeout": return I18n.tr("Dictation took too long to finish");
            case "typing": return result.id ? I18n.tr("Your words could not be typed. They are in history.")
                : I18n.tr("Your words could not be typed");
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
        Accessible.name: root.showWords ? root.words + ". " + root.statusText : root.statusText

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
                        : root.tidying ? "sparkles"
                        : root.working ? "loader-2"
                        : root.phase === "done" ? "check"
                        : root.phase === "copied" ? "content_paste"
                        : root.phase === "empty" ? "mic_off"
                        : "error"
                    size: Theme.iconMedium
                    color: root.listening || root.problem ? Theme.redText
                        : root.tidying ? Theme.accentText : Theme.textHi
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

                // Copy original, or Open history for words that were not typed.
                Rectangle {
                    id: actionButton
                    visible: root.action !== ""
                    width: actionLabel.implicitWidth + Theme.scaled(16)
                    height: actionLabel.implicitHeight + Theme.scaled(6)
                    radius: Theme.scaled(8)
                    color: actionMouse.containsMouse ? Theme.hoverFillStrong : Theme.hoverFill
                    Accessible.role: Accessible.Button
                    Accessible.name: root.action

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: root.action
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        color: Theme.accentText
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.phase === "done")
                                Dictation.copyOriginal();
                            else
                                Dictation.openHistory();
                        }
                    }
                }
            }
        }

        // A click stops a dictation that is listening; while tidy-up runs it
        // types the words as they were said instead.
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: root.listening || (root.tidying && !Dictation.originalRequested)
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.listening)
                    Dictation.stop();
                else
                    Dictation.typeOriginal();
            }
        }
    }
}
