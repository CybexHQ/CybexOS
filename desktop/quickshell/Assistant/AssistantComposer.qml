pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers

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
    // The agent and model menu under the chip.
    property bool modelMenuOpen: false
    onVisibleChanged: {
        menuOpen = false;
        modelMenuOpen = false;
    }

    readonly property bool listening: Assistant.listening
    // The microphone's level, which the character's ring follows too.
    readonly property real level: listening ? peaks.peak : 0
    readonly property bool transcribing: Assistant.transcribing
    // The one suggestion that fits the moment, first, with why it is there.
    readonly property var situational: {
        const moment = Assistant.situation;
        if (!moment)
            return null;
        switch (moment.kind) {
        case "update-failed":
            return { text: I18n.tr("Why did the update fail?"), update: true, glyph: "warning",
                warn: true, reason: I18n.format("Software Update failed %1", [root.ago(moment.at)]) };
        case "kept":
            return { text: I18n.format("What's new in %1?", [moment.version]), glyph: "auto_awesome",
                reason: I18n.format("Cybex OS %1 was kept %2", [moment.version, root.ago(moment.at)]) };
        case "repeated":
            return { text: I18n.format("Why does “%1” keep happening?", [moment.summary]), glyph: "notifications",
                reason: I18n.format("%1 times in the last hour", [moment.count]) };
        }
        return null;
    }

    function ago(at) {
        const minutes = Math.max(0, Math.floor((Assistant.now - at) / 60000));
        return minutes < 1 ? I18n.tr("just now") : minutes === 1 ? I18n.tr("a minute ago")
            : I18n.format("%1 minutes ago", [minutes]);
    }

    readonly property var suggestions: {
        const list = [
            { text: I18n.tr("Check this computer"), check: true },
            { text: I18n.tr("What can you do?"), screen: false },
            { text: I18n.tr("Make the menubar transparent"), screen: false },
            { text: I18n.tr("Create a CPU temperature widget"), screen: false }
        ];
        if (Settings.assistantScreenContext)
            list.push({ text: I18n.tr("Explain what is on my screen"), screen: true });
        // Only three fixed ones after the moment's own.
        return root.situational ? [root.situational].concat(list.slice(0, 3)) : list;
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
        else if (root.modelMenuOpen)
            root.modelMenuOpen = false;
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
                glyph: Settings.assistantExpanded ? "close_fullscreen" : "open_in_full"
                accessibleName: Settings.assistantExpanded ? I18n.tr("Back to the small box") : I18n.tr("Expand")
                controlHeight: Theme.scaled(26)
                color: "transparent"
                onTriggered: Assistant.toggleExpanded()
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

                    AssistantMarkdown {
                        width: parent.width
                        visible: text !== ""
                        plain: exchange.failed || exchange.active
                        text: exchange.failed ? (exchange.modelData.error || I18n.tr("Something went wrong."))
                            : exchange.active ? I18n.tr("Wiz is still working on this.")
                            : exchange.modelData.status === "stopped" && (exchange.modelData.text || "") === ""
                                ? I18n.tr("Stopped.")
                            : exchange.modelData.text || ""
                        color: exchange.failed ? Theme.redText : exchange.active ? Theme.textLow : Theme.textHi
                    }

                    AssistantSteps {
                        width: parent.width
                        steps: exchange.modelData.steps || []
                        folded: true
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

    // ---- what goes with the question ----------------------------------------------
    Flow {
        id: attachmentFlow
        width: parent.width
        spacing: Theme.scaled(5)
        visible: Assistant.attachments.length > 0 && !Assistant.setupRequired && !root.listening

        Repeater {
            model: Assistant.attachments

            delegate: Rectangle {
                id: attachmentChip
                required property var modelData
                height: Theme.scaled(26)
                width: Math.min(attachmentFlow.width, chipRow.implicitWidth + Theme.scaled(8))
                radius: Theme.scaled(7)
                color: Theme.chip
                border.width: 1
                border.color: Theme.hairline
                Accessible.role: Accessible.StaticText
                Accessible.name: attachmentChip.modelData.label

                Row {
                    id: chipRow
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.scaled(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.scaled(5)

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: AssistantHelpers.attachmentGlyph(attachmentChip.modelData.kind)
                        size: Theme.iconSmall
                        color: Theme.textMid
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, attachmentFlow.width - Theme.scaled(110))
                        text: attachmentChip.modelData.label
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                        color: Theme.textHi
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (attachmentChip.modelData.detail || "") !== ""
                        text: attachmentChip.modelData.detail || ""
                        color: Theme.textFaint
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                    }
                    AssistantButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "close"
                        accessibleName: I18n.format("Remove %1", [attachmentChip.modelData.label])
                        controlHeight: Theme.scaled(18)
                        color: "transparent"
                        onTriggered: Assistant.removeAttachment(attachmentChip.modelData.id)
                    }
                }
            }
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
                        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            // A picture on the clipboard is attached; text pastes as usual.
                            Assistant.pasteImage();
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
                glyph: "photo"
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
                readonly property bool moment: !!chip.modelData.reason
                width: Math.min(suggestionFlow.width, chipContent.implicitWidth + Theme.scaled(18))
                height: Theme.scaled(26)
                radius: height / 2
                color: chipMouse.containsMouse ? Theme.chipHover : Theme.chip
                border.width: moment ? 1 : 0
                border.color: chip.modelData.warn ? Theme.amber : Theme.accentText
                Accessible.role: Accessible.Button
                Accessible.name: chip.modelData.text
                Accessible.description: chip.modelData.reason || ""

                Row {
                    id: chipContent
                    anchors.centerIn: parent
                    spacing: Theme.scaled(4)

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: chip.moment
                        name: chip.modelData.glyph || ""
                        size: Theme.iconSmall
                        color: chip.modelData.warn ? Theme.amber : Theme.accentText
                    }
                    Text {
                        id: chipText
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, suggestionFlow.width - Theme.scaled(40))
                        text: chip.modelData.text
                        elide: Text.ElideRight
                        color: chip.moment ? Theme.textHi : Theme.textMid
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (chip.moment)
                            Assistant.useSituation();
                        if (chip.modelData.check)
                            Assistant.checkSystem();
                        else if (chip.modelData.update)
                            Assistant.askAboutUpdate();
                        else if (chip.modelData.screen)
                            Assistant.askAboutScreen(chip.modelData.text);
                        else
                            Assistant.send(chip.modelData.text);
                    }
                }
            }
        }
    }

    // Why the first suggestion is there.
    Row {
        visible: suggestionFlow.visible && root.situational !== null
        spacing: Theme.scaled(5)

        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: "schedule"
            size: Theme.iconSmall
            color: Theme.textFaint
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.situational ? root.situational.reason : ""
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
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
            color: agentMouse.containsMouse || root.modelMenuOpen ? Theme.chipHover : Theme.chip
            Accessible.role: Accessible.Button
            Accessible.name: I18n.format("Answered by %1 · %2. Change the agent or model.",
                [Assistant.askAgentLabel, Assistant.askModelLabel])

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
                        : Assistant.askAgentLabel + " · " + Assistant.askModelLabel
                    color: installed || !Assistant.connected ? Theme.textMid : Theme.redText
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.modelMenuOpen ? "expand_less" : "expand_more"
                    size: Theme.iconSmall
                    color: Theme.textLow
                }
            }

            MouseArea {
                id: agentMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!AssistantHelpers.anyAgent(Assistant.agents))
                        Settings.showPanel("assistant", Assistant.screenName);
                    else
                        root.modelMenuOpen = !root.modelMenuOpen;
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

    // ---- agent and model, for this conversation ---------------------------------------
    Rectangle {
        id: modelMenu
        width: parent.width
        visible: root.modelMenuOpen && !Assistant.setupRequired
        height: visible ? menuColumn.implicitHeight + Theme.scaled(10) : 0
        radius: Theme.scaled(10)
        color: Theme.cardFill
        border.width: 1
        border.color: Theme.hairline

        Column {
            id: menuColumn
            x: Theme.scaled(5)
            y: Theme.scaled(5)
            width: parent.width - Theme.scaled(10)
            spacing: Theme.scaled(1)

            Text {
                leftPadding: Theme.scaled(6)
                topPadding: Theme.scaled(2)
                text: I18n.tr("Agent").toUpperCase()
                color: Theme.textFaint
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightSemibold
                font.letterSpacing: 0.6
            }

            Repeater {
                model: AssistantHelpers.AGENT_IDS

                delegate: AssistantMenuRow {
                    required property string modelData
                    readonly property var status: Assistant.agents[modelData] || {}
                    width: menuColumn.width
                    glyphBrand: AssistantHelpers.AGENT_ICONS[modelData]
                    label: AssistantHelpers.AGENT_LABELS[modelData]
                    // A conversation continues with the agent it started with.
                    enabled: !root.continuing && status.available === true
                    checked: Assistant.askAgent === modelData
                    detail: root.continuing && Assistant.askAgent !== modelData
                        ? I18n.format("Started with %1", [Assistant.askAgentLabel])
                        : status.available !== true ? I18n.tr("Not installed")
                        : status.auth !== "ready" ? I18n.tr("Sign in…") : ""
                    onChosen: {
                        if (status.auth !== "ready") {
                            root.modelMenuOpen = false;
                            Assistant.signIn(modelData);
                            return;
                        }
                        Assistant.agentOverride = modelData === Assistant.agent ? "" : modelData;
                        Assistant.modelOverride = "";
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairline
            }

            Text {
                leftPadding: Theme.scaled(6)
                topPadding: Theme.scaled(2)
                text: I18n.tr("Model").toUpperCase()
                color: Theme.textFaint
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightSemibold
                font.letterSpacing: 0.6
            }

            Repeater {
                model: AssistantHelpers.modelChoices(Assistant.askAgent)

                delegate: AssistantMenuRow {
                    required property var modelData
                    width: menuColumn.width
                    label: modelData.value === "default" ? I18n.tr("Default") : modelData.label
                    detail: modelData.value === "default"
                        ? I18n.format("%1's own", [Assistant.askAgentLabel]) : ""
                    checked: (Assistant.askModel === "" ? "default" : Assistant.askModel) === modelData.value
                    onChosen: {
                        Assistant.modelOverride = modelData.value;
                        root.modelMenuOpen = false;
                    }
                }
            }

            Text {
                width: parent.width
                leftPadding: Theme.scaled(6)
                rightPadding: Theme.scaled(6)
                bottomPadding: Theme.scaled(3)
                text: I18n.tr("Only for this conversation. Your default stays in Settings.")
                wrapMode: Text.WordWrap
                color: Theme.textFaint
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
            }
        }
    }

    // Dropped files and images go with the question.
    DropArea {
        parent: root
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            if (drop.hasUrls) {
                Assistant.attachUrls(drop.urls);
                drop.accept();
            }
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
