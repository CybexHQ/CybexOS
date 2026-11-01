pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers
import "../Common/T3CodeHelpers.js" as T3CodeHelpers

// Where a question is typed or spoken. Enter sends, Shift+Enter breaks the
// line and Esc closes (a recording is cancelled first). While listening, the
// field becomes a level meter; Voxtype transcribes once the key or button is
// released, and the words land here — sent straight away for push-to-talk.
//
// A new conversation offers History, suggestions and the three most recent
// conversations. A continued one (Reply, or a row in History) shows its
// questions and answers above the field; `room` is the height the box may
// use, which that transcript scrolls within.
AssistantSurface {
    id: root

    property real room: 400
    readonly property bool continuing: Assistant.continuing !== ""
    readonly property var thread: Assistant.thread
    // As many of the three as fit in the room on this side of the character.
    readonly property real recentRowHeight: Theme.scaled(38)
    readonly property real baseHeight: header.height + field.height + suggestionFlow.height
        + agentLine.height + root.spacing * 5 + root.padding * 2 + Theme.scaled(64)
    readonly property var recent: Assistant.conversations.slice(0, Math.max(0, Math.min(
        AssistantHelpers.RECENT_LIMIT, Math.floor((root.room - root.baseHeight) / root.recentRowHeight))))
    property bool menuOpen: false
    onVisibleChanged: menuOpen = false

    readonly property bool listening: Assistant.listening
    // The microphone's level, which the character's ring follows too.
    readonly property real level: listening ? peaks.peak : 0
    readonly property bool transcribing: Assistant.transcribing
    readonly property var suggestions: {
        const list = [
            { text: I18n.tr("Check this computer"), check: true },
            { text: I18n.tr("What can you do?"), screen: false },
            { text: I18n.tr("Make the menubar transparent"), screen: false },
            { text: I18n.tr("Create a CPU temperature widget"), screen: false }
        ];
        if (Settings.assistantScreenContext)
            list.push({ text: I18n.tr("Explain what is on my screen"), screen: true });
        return list;
    }

    function focusInput() {
        if (!root.listening && !Assistant.setupRequired)
            input.forceActiveFocus();
    }

    AssistantSetup {
        width: parent.width
        visible: Assistant.connected && Assistant.setupRequired
    }

    // Esc backs out one step at a time: the recording, the menu, then the box.
    function backOut() {
        if (Assistant.listening || Assistant.transcribing)
            Assistant.cancelListening();
        else if (root.menuOpen)
            root.menuOpen = false;
        else
            Assistant.closeComposer();
    }

    Connections {
        target: Assistant

        function onFocusComposer() {
            Qt.callLater(root.focusInput);
        }

        function onDraftChanged() {
            if (input.text !== Assistant.draft) {
                input.syncing = true;
                input.text = Assistant.draft;
                input.cursorPosition = input.text.length;
                input.syncing = false;
            }
        }
    }

    // ---- which conversation ----------------------------------------------------------
    Item {
        id: header
        width: parent.width
        height: Theme.scaled(26)
        visible: !root.listening

        AssistantButton {
            id: backButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.continuing
            glyph: "arrow_back"
            accessibleName: I18n.tr("Back to History")
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.openHistory()
        }

        Text {
            anchors.left: root.continuing ? backButton.right : parent.left
            anchors.leftMargin: root.continuing ? Theme.scaled(6) : 0
            anchors.right: headerActions.left
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            text: !root.continuing ? I18n.tr("New conversation")
                : Assistant.continuingRow ? Assistant.continuingRow.title
                : root.thread ? root.thread.title || "" : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            font.weight: Theme.weightSemibold
        }

        Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(2)

            AssistantButton {
                visible: !root.continuing && Assistant.connected
                objectName: "assistantHistoryButton"
                glyph: "history"
                label: I18n.tr("History")
                controlHeight: Theme.scaled(26)
                color: "transparent"
                onTriggered: Assistant.openHistory()
            }

            AssistantButton {
                visible: root.continuing
                glyph: "more_horiz"
                accessibleName: I18n.tr("More for this conversation")
                controlHeight: Theme.scaled(26)
                color: root.menuOpen ? Theme.chipHover : "transparent"
                onTriggered: root.menuOpen = !root.menuOpen
            }

            AssistantButton {
                visible: root.continuing
                glyph: "close"
                accessibleName: I18n.tr("Close")
                controlHeight: Theme.scaled(26)
                color: "transparent"
                onTriggered: Assistant.closeComposer()
            }
        }
    }

    // What can be done with the whole conversation.
    Flow {
        width: parent.width
        spacing: Theme.scaled(4)
        visible: root.continuing && root.menuOpen && !root.listening

        AssistantButton {
            visible: root.thread !== null && root.thread.resumable === true
            glyph: "terminal"
            label: I18n.tr("Continue in a terminal")
            controlHeight: Theme.scaled(28)
            onTriggered: {
                root.menuOpen = false;
                Assistant.handoff(Assistant.continuing);
            }
        }

        AssistantButton {
            visible: root.thread !== null
            glyph: "content_copy"
            label: I18n.tr("Copy conversation")
            controlHeight: Theme.scaled(28)
            onTriggered: {
                root.menuOpen = false;
                Assistant.copyConversation();
            }
        }

        AssistantButton {
            glyph: "add"
            label: I18n.tr("New conversation")
            controlHeight: Theme.scaled(28)
            onTriggered: {
                root.menuOpen = false;
                Assistant.newConversation();
            }
        }

        AssistantButton {
            glyph: "delete"
            label: I18n.tr("Delete conversation")
            danger: true
            controlHeight: Theme.scaled(28)
            onTriggered: {
                root.menuOpen = false;
                const id = Assistant.continuing;
                Assistant.openHistory();
                Assistant.deleteConversation(id);
            }
        }
    }

    // ---- the conversation so far -----------------------------------------------------
    Flickable {
        id: transcriptFlick
        readonly property real chrome: header.height + field.height + agentLine.height
            + root.spacing * 4 + root.padding * 2 + Theme.scaled(24)
        width: parent.width
        visible: root.continuing && root.thread !== null && !root.listening && !Assistant.setupRequired
        height: visible ? Math.max(Theme.scaled(60), Math.min(transcript.implicitHeight,
            root.room - chrome, Theme.scaled(420))) : 0
        contentWidth: width
        contentHeight: transcript.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        // The latest answer is where reading resumes.
        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
        onHeightChanged: contentY = Math.max(0, contentHeight - height)

        Column {
            id: transcript
            width: transcriptFlick.width
            spacing: Theme.scaled(10)

            Repeater {
                model: root.thread ? root.thread.turns || [] : []

                delegate: Column {
                    id: exchange
                    required property var modelData
                    readonly property bool failed: modelData.status === "failed"
                    readonly property bool active: modelData.status === "running" || modelData.status === "waiting"
                    width: transcript.width
                    spacing: Theme.scaled(6)

                    // The question, on the right.
                    Rectangle {
                        anchors.right: parent.right
                        width: Math.min(parent.width * 0.85, question.implicitWidth + Theme.scaled(20))
                        height: question.implicitHeight + Theme.scaled(12)
                        radius: Theme.scaled(10)
                        color: Theme.chip

                        Text {
                            id: question
                            x: Theme.scaled(10)
                            y: Theme.scaled(6)
                            width: Math.min(implicitWidth, exchange.width * 0.85 - Theme.scaled(20))
                            text: exchange.modelData.prompt || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.textHi
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                        }
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        visible: text !== ""
                        textFormat: exchange.failed ? TextEdit.PlainText : TextEdit.MarkdownText
                        text: exchange.failed ? (exchange.modelData.error || I18n.tr("Something went wrong."))
                            : exchange.active ? I18n.tr("Wiz is still working on this.")
                            : exchange.modelData.status === "stopped" && (exchange.modelData.text || "") === ""
                                ? I18n.tr("Stopped.")
                            : T3CodeHelpers.styleMarkdownLinks(exchange.modelData.text || "",
                                Theme.accentText.toString())
                        wrapMode: TextEdit.Wrap
                        color: exchange.failed ? Theme.redText : exchange.active ? Theme.textLow : Theme.textHi
                        selectionColor: Theme.accentSoft
                        selectedTextColor: Theme.textHi
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.control
                        onLinkActivated: link => {
                            if (/^(https?|mailto):/i.test(link))
                                Quickshell.execDetached(["xdg-open", link]);
                        }
                    }

                    Text {
                        visible: exchange.modelData.finishedAt > 0
                        text: (AssistantHelpers.AGENT_LABELS[root.thread ? root.thread.agent : ""] || "")
                            + " · " + AssistantHelpers.elapsedLabel(exchange.modelData.finishedAt
                                - exchange.modelData.startedAt)
                        color: Theme.textFaint
                        font.family: Theme.fontNumeric
                        font.pixelSize: Theme.typography.metadata
                        font.features: Theme.tabularNumberFeatures
                    }
                }
            }
        }
    }

    // ---- the attached screenshot ------------------------------------------------
    Rectangle {
        width: parent.width
        height: visible ? Theme.scaled(46) : 0
        visible: Assistant.screenAttached && !Assistant.setupRequired
        radius: Theme.chipRadius
        color: Theme.chip

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(10)

            Rectangle {
                width: Theme.scaled(56)
                height: Theme.scaled(34)
                radius: 4
                color: Theme.well
                clip: true

                Image {
                    anchors.fill: parent
                    source: Assistant.screenAttached ? "file://" + Assistant.screenPath : ""
                    sourceSize.width: Theme.scaled(112)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: I18n.format("Screen · %1", [Assistant.screenOutput])
                    color: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                }
                Text {
                    text: I18n.tr("Sent with this question only")
                    color: Theme.textLow
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }
            }
        }

        AssistantButton {
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(6)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "close"
            accessibleName: I18n.tr("Remove the screenshot")
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.detachScreen()
        }
    }

    // ---- the field ---------------------------------------------------------------
    Rectangle {
        id: field
        visible: !Assistant.setupRequired
        width: parent.width
        height: Math.max(Theme.scaled(44), inputArea.height + Theme.scaled(14))
        radius: Theme.scaled(12)
        color: Theme.well
        border.width: 1
        border.color: input.activeFocus || root.listening ? Theme.accent : Theme.hairline

        Behavior on border.color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }

        Item {
            id: inputArea
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(12)
            anchors.right: buttons.left
            anchors.rightMargin: Theme.scaled(6)
            anchors.verticalCenter: parent.verticalCenter
            height: root.listening || root.transcribing ? Theme.scaled(28)
                : Math.min(Theme.scaled(110), Math.max(Theme.scaled(22), input.contentHeight))

            Flickable {
                id: inputFlick
                anchors.fill: parent
                visible: !root.listening && !root.transcribing
                contentWidth: width
                contentHeight: Math.max(height, input.contentHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: input
                    property bool syncing: false

                    width: inputFlick.width
                    height: Math.max(inputFlick.height, contentHeight)
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: Theme.textHi
                    selectionColor: Theme.accentSoft
                    selectedTextColor: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    Accessible.name: I18n.tr("Ask the Cybex OS Assistant")
                    Accessible.description: I18n.tr("Enter sends. Shift Enter inserts a newline.")
                    Component.onCompleted: text = Assistant.draft

                    onTextChanged: {
                        if (!syncing)
                            Assistant.draft = text;
                    }
                    onActiveFocusChanged: {
                        if (activeFocus)
                            Assistant.focusRequested = true;
                    }
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y + cursorRectangle.height
                                > inputFlick.contentY + inputFlick.height)
                            inputFlick.contentY = cursorRectangle.y
                                + cursorRectangle.height - inputFlick.height;
                        else if (cursorRectangle.y < inputFlick.contentY)
                            inputFlick.contentY = cursorRectangle.y;
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.backOut();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (event.modifiers & Qt.ShiftModifier)
                                input.insert(input.cursorPosition, "\n");
                            else
                                Assistant.send();
                            event.accepted = true;
                        }
                    }

                    Text {
                        visible: input.text === ""
                        width: parent.width
                        text: !Assistant.connected ? I18n.tr("The assistant service is not running.")
                            : root.continuing ? I18n.tr("Reply…")
                            : I18n.tr("Ask Cybex OS anything…")
                        elide: Text.ElideRight
                        color: Theme.textFaint
                        font: input.font
                    }
                }
            }

            // Listening: the red dot, the level and the time so far.
            Row {
                anchors.fill: parent
                visible: root.listening
                spacing: Theme.scaled(8)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.scaled(8)
                    height: width
                    radius: width / 2
                    color: Theme.red

                    SequentialAnimation on opacity {
                        running: root.listening && !Theme.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }

                AssistantVisualizer {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - timer.width - Theme.scaled(24)
                    height: parent.height
                    level: root.level
                    running: root.listening
                }

                Text {
                    id: timer
                    anchors.verticalCenter: parent.verticalCenter
                    text: AssistantHelpers.elapsedLabel(Assistant.now - Assistant.listenStartedAt)
                    color: Theme.textLow
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.typography.metadata
                    font.features: Theme.tabularNumberFeatures
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.transcribing
                spacing: Theme.scaled(8)

                Sym {
                    id: transcribingSpinner
                    anchors.verticalCenter: parent.verticalCenter
                    name: "progress_activity"
                    size: Theme.iconMedium
                    color: Theme.accentText

                    RotationAnimator on rotation {
                        running: root.transcribing && !Theme.reducedMotion
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Transcribing…")
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                }
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(6)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.scaled(7)
            spacing: Theme.scaled(2)

            AssistantButton {
                visible: Settings.assistantScreenContext && !root.listening && !root.transcribing
                glyph: "monitor"
                accessibleName: Assistant.screenAttached ? I18n.tr("Remove the screenshot")
                    : I18n.tr("Attach the screen")
                color: Assistant.screenAttached ? Theme.chipHover : "transparent"
                enabled: !Assistant.capturing
                onTriggered: Assistant.toggleScreen()
            }

            AssistantButton {
                visible: Assistant.voiceAvailable && !root.transcribing
                glyph: root.listening ? "stop" : "mic"
                accessibleName: root.listening ? I18n.tr("Stop recording")
                    : I18n.tr("Talk instead of typing")
                color: root.listening ? Theme.redBgSoft : "transparent"
                danger: root.listening
                onTriggered: Assistant.toggleMicrophone()
            }

            AssistantButton {
                visible: root.listening || root.transcribing
                glyph: "close"
                accessibleName: I18n.tr("Cancel the recording")
                color: "transparent"
                onTriggered: Assistant.cancelListening()
            }

            AssistantButton {
                visible: Assistant.draft.trim() !== "" && !root.listening && !root.transcribing
                glyph: "send"
                primary: true
                accessibleName: I18n.tr("Send")
                enabled: Assistant.connected && !Assistant.busy
                onTriggered: Assistant.send()
            }
        }
    }

    // ---- first questions -----------------------------------------------------------
    Flow {
        id: suggestionFlow
        width: parent.width
        spacing: Theme.scaled(6)
        visible: Assistant.draft === "" && !root.continuing
            && !root.listening && !root.transcribing && Assistant.connected && !Assistant.setupRequired

        Repeater {
            model: root.suggestions

            delegate: Rectangle {
                id: chip
                required property var modelData
                width: chipText.implicitWidth + Theme.scaled(18)
                height: Theme.scaled(26)
                radius: height / 2
                color: chipMouse.containsMouse ? Theme.chipHover : Theme.chip
                Accessible.role: Accessible.Button
                Accessible.name: chip.modelData.text

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.text
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (chip.modelData.check)
                            Assistant.checkSystem();
                        else if (chip.modelData.screen)
                            Assistant.askAboutScreen(chip.modelData.text);
                        else
                            Assistant.send(chip.modelData.text);
                    }
                }
            }
        }
    }

    // ---- the last three conversations ---------------------------------------------------
    Column {
        width: parent.width
        visible: !root.continuing && root.recent.length > 0 && !root.listening && !root.transcribing
            && Assistant.connected && !Assistant.setupRequired
        spacing: 0

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairline
            opacity: 0.6
        }

        Text {
            width: parent.width
            topPadding: Theme.scaled(8)
            bottomPadding: Theme.scaled(2)
            text: I18n.tr("Recent").toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightSemibold
            font.letterSpacing: 0.6
        }

        Repeater {
            model: root.recent

            delegate: AssistantConversationRow {
                required property var modelData
                required property int index
                width: root.width - root.padding * 2
                row: modelData
                showPreview: index === 0
                onOpened: Assistant.openConversation(modelData.id)
            }
        }

        AssistantButton {
            anchors.right: parent.right
            visible: Assistant.conversations.length > root.recent.length
            label: I18n.format("All conversations (%1)", [Assistant.conversations.length])
            glyph: "arrow_forward"
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.openHistory()
        }
    }

    // The service starts with the session; this is for one that stopped.
    AssistantButton {
        visible: !Assistant.connected
        label: I18n.tr("Start the assistant")
        glyph: "play_arrow"
        onTriggered: Assistant.fix("service")
    }

    // ---- who answers, and how to talk --------------------------------------------------
    Item {
        id: agentLine
        width: parent.width
        height: Theme.scaled(22)
        visible: !Assistant.setupRequired

        Rectangle {
            id: agentChip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: agentRow.implicitWidth + Theme.scaled(14)
            height: Theme.scaled(22)
            radius: height / 2
            color: agentMouse.containsMouse && !root.continuing ? Theme.chipHover : Theme.chip
            Accessible.role: root.continuing ? Accessible.StaticText : Accessible.Button
            Accessible.name: root.continuing
                ? I18n.format("Continues with %1", [Assistant.askAgentLabel])
                : I18n.format("Answered by %1. Change the agent.", [Assistant.agentLabel])

            Row {
                id: agentRow
                anchors.centerIn: parent
                spacing: Theme.scaled(5)

                BrandIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSmall
                    height: Theme.iconSmall
                    name: AssistantHelpers.AGENT_ICONS[Assistant.askAgent] || ""
                    colorized: true
                    tint: Theme.textMid
                    normalizeTintSource: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool installed: !!(Assistant.agents[Assistant.askAgent]
                        && Assistant.agents[Assistant.askAgent].available)
                    text: !installed && Assistant.connected
                        ? I18n.format("%1 is not installed", [Assistant.askAgentLabel])
                        : root.continuing ? I18n.format("Continues with %1", [Assistant.askAgentLabel])
                        : Assistant.agentLabel
                    color: installed || !Assistant.connected ? Theme.textMid : Theme.redText
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }
            }

            MouseArea {
                id: agentMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.continuing
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!AssistantHelpers.anyAgent(Assistant.agents))
                        Settings.showPanel("assistant", Assistant.screenName);
                    else
                        Settings.set("assistantAgent",
                            AssistantHelpers.nextAgent(Assistant.agent, Assistant.agents));
                }
            }
        }

        Text {
            anchors.left: agentChip.right
            anchors.leftMargin: Theme.scaled(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: Assistant.notice !== "" ? Assistant.notice
                : Assistant.busy ? I18n.tr("Wiz is still working on another question.")
                // The agent chip says who continues; the keys are as in a new box.
                : root.continuing && !root.listening && !root.transcribing ? ""
                : root.listening ? (Assistant.voiceLatched ? I18n.tr("Tap the microphone to send")
                    : I18n.tr("Release to send · Esc cancels"))
                : root.transcribing ? ""
                : Assistant.voiceAvailable ? I18n.tr("Hold Super+I to talk")
                : I18n.tr("Enter sends · Esc closes")
            color: Assistant.notice !== "" ? Theme.textMid : Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
        }
    }

    // The microphone's level, only while recording.
    PwObjectTracker {
        objects: root.listening && Pipewire.defaultAudioSource ? [Pipewire.defaultAudioSource] : []
    }

    PwNodePeakMonitor {
        id: peaks
        node: Pipewire.defaultAudioSource
        enabled: root.listening
    }
}
