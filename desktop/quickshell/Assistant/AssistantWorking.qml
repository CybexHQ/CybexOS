pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers

// The pill while the agent works: what it is doing right now, how long it
// has taken and Stop. Anything it needs a decision on stacks underneath;
// the turn does not continue until it is answered.
//
// Under it, another question can be asked meanwhile (docs/assistant.md): it
// is answered alongside, looking only, and one that needs a change waits as
// "Up next" until the current one is done.
AssistantSurface {
    id: root

    readonly property var turn: Assistant.turn
    readonly property var side: Assistant.side
    readonly property var queued: Assistant.queue
    // Room for the side answer, which scrolls within it.
    property real room: 400
    padding: Theme.scaled(8)

    function focusInput() {
        if (visible && !Assistant.waiting)
            asideInput.forceActiveFocus();
    }

    Connections {
        target: Assistant

        function onFocusComposer() {
            Qt.callLater(root.focusInput);
        }

        // A question the service refused comes back to the field.
        function onDraftChanged() {
            if (Assistant.busy && asideInput.text === "" && Assistant.draft !== "") {
                asideInput.text = Assistant.draft;
                Assistant.draft = "";
            }
        }
    }

    Item {
        width: parent.width
        height: Theme.scaled(32)

        Item {
            id: spinner
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconMedium
            height: Theme.iconMedium

            Sym {
                anchors.fill: parent
                visible: !Assistant.waiting
                name: "progress_activity"
                size: Theme.iconMedium
                color: Theme.accentText

                RotationAnimator on rotation {
                    running: !Assistant.waiting && root.visible && !Theme.reducedMotion
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            // Its own glyph: a stopped spinner would leave it tilted.
            Sym {
                anchors.fill: parent
                visible: Assistant.waiting
                name: "priority_high"
                size: Theme.iconMedium
                color: Theme.amber
            }
        }

        AnimatedText {
            anchors.left: spinner.right
            anchors.leftMargin: Theme.scaled(10)
            anchors.right: elapsed.left
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            text: Assistant.waiting ? I18n.tr("Needs your answer")
                : root.turn && root.turn.step ? root.turn.step : I18n.tr("Thinking")
            elide: Text.ElideRight
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
        }

        Text {
            id: elapsed
            anchors.right: historyButton.left
            anchors.rightMargin: Theme.scaled(6)
            anchors.verticalCenter: parent.verticalCenter
            text: root.turn ? AssistantHelpers.elapsedLabel(Assistant.now - root.turn.startedAt) : ""
            color: Theme.textLow
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.metadata
            font.features: Theme.tabularNumberFeatures
        }

        // Other conversations can be read while this one works.
        AssistantButton {
            id: historyButton
            anchors.right: stopButton.left
            anchors.rightMargin: Theme.scaled(4)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "history"
            accessibleName: I18n.tr("History")
            color: "transparent"
            controlHeight: Theme.scaled(28)
            onTriggered: Assistant.openHistory()
        }

        AssistantButton {
            id: stopButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: I18n.tr("Stop")
            glyph: "stop"
            danger: true
            controlHeight: Theme.scaled(28)
            onTriggered: Assistant.stop()
        }
    }

    Repeater {
        model: Assistant.approvals

        delegate: AssistantApproval {
            required property var modelData
            width: root.width - root.padding * 2
            approval: modelData
        }
    }

    // ---- asked meanwhile -----------------------------------------------------------
    Column {
        width: parent.width
        visible: root.side !== null
        spacing: Theme.scaled(6)

        Rectangle {
            anchors.right: parent.right
            width: Math.min(parent.width * 0.85, sideQuestion.implicitWidth + Theme.scaled(20))
            height: sideQuestion.implicitHeight + Theme.scaled(12)
            radius: Theme.scaled(10)
            color: Theme.chip

            Text {
                id: sideQuestion
                x: Theme.scaled(10)
                y: Theme.scaled(6)
                width: Math.min(implicitWidth, root.width * 0.85 - Theme.scaled(36))
                text: root.side ? root.side.prompt || "" : ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
            }
        }

        Item {
            width: parent.width
            height: Theme.scaled(22)

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: badge.implicitWidth + Theme.scaled(12)
                height: Theme.scaled(20)
                radius: Theme.scaled(5)
                color: Theme.chip

                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: Assistant.sideBusy ? I18n.tr("Looking, alongside…")
                        : root.side && root.side.needsChange ? I18n.tr("Answered alongside · needs a change")
                        : I18n.tr("Answered alongside · only looked")
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightSemibold
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.scaled(2)

                AssistantButton {
                    visible: Assistant.sideBusy
                    label: I18n.tr("Stop")
                    controlHeight: Theme.scaled(22)
                    color: "transparent"
                    onTriggered: Assistant.stopSide()
                }
                AssistantButton {
                    visible: !Assistant.sideBusy
                    glyph: "close"
                    accessibleName: I18n.tr("Dismiss this answer")
                    controlHeight: Theme.scaled(22)
                    color: "transparent"
                    onTriggered: Assistant.dismissSide()
                }
            }
        }

        Flickable {
            id: sideFlick
            width: parent.width
            height: Math.min(sideAnswer.implicitHeight, Math.max(Theme.scaled(80), root.room * 0.45))
            contentWidth: width
            contentHeight: sideAnswer.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            visible: sideAnswer.text !== ""

            AssistantMarkdown {
                id: sideAnswer
                width: sideFlick.width
                plain: root.side !== null && root.side.status === "failed"
                text: !root.side ? "" : root.side.status === "failed" ? root.side.error || ""
                    : root.side.text || ""
                color: root.side && root.side.status === "failed" ? Theme.redText : Theme.textHi
            }
        }
    }

    // ---- up next ------------------------------------------------------------------------
    Rectangle {
        width: parent.width
        visible: root.queued !== null
        height: visible ? queueColumn.implicitHeight + Theme.scaled(14) : 0
        radius: Theme.scaled(10)
        color: "transparent"
        border.width: 1
        border.color: Theme.hairline

        Column {
            id: queueColumn
            x: Theme.scaled(10)
            y: Theme.scaled(7)
            width: parent.width - Theme.scaled(20) - queueActions.width
            spacing: Theme.scaled(2)

            Text {
                width: parent.width
                text: root.queued ? I18n.format("Up next · %1", [root.queued.text]) : ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
            }
            Text {
                width: parent.width
                text: root.queued && root.queued.reason === "change"
                    ? I18n.tr("It changes something, so it waits for the current question.")
                    : I18n.tr("Wiz asks it as soon as he is free.")
                wrapMode: Text.WordWrap
                color: Theme.textFaint
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
            }
        }

        Row {
            id: queueActions
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(2)

            AssistantButton {
                label: confirmRun ? I18n.tr("Stop the current one?") : I18n.tr("Run now")
                property bool confirmRun: false
                controlHeight: Theme.scaled(24)
                color: confirmRun ? Theme.redBgSoft : "transparent"
                danger: confirmRun
                onTriggered: {
                    if (confirmRun) {
                        confirmRun = false;
                        Assistant.runQueuedNow();
                    } else {
                        confirmRun = true;
                    }
                }
            }
            AssistantButton {
                glyph: "close"
                accessibleName: I18n.tr("Remove the waiting question")
                controlHeight: Theme.scaled(24)
                color: "transparent"
                onTriggered: Assistant.removeQueued()
            }
        }
    }

    // ---- ask something else ---------------------------------------------------------------
    Rectangle {
        width: parent.width
        visible: !Assistant.waiting && !(Assistant.queue !== null && Assistant.sideBusy)
        height: visible ? Math.max(Theme.scaled(38), asideInput.contentHeight + Theme.scaled(14)) : 0
        radius: Theme.scaled(10)
        color: Theme.well
        border.width: 1
        border.color: asideInput.activeFocus ? Theme.accent : Theme.hairline

        TextEdit {
            id: asideInput
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(10)
            anchors.right: asideSend.left
            anchors.rightMargin: Theme.scaled(6)
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: TextEdit.Wrap
            color: Theme.textHi
            selectionColor: Theme.accentSoft
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            Accessible.name: I18n.tr("Ask something else while Wiz works")
            onActiveFocusChanged: {
                if (activeFocus)
                    Assistant.focusRequested = true;
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.sendAside();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    Assistant.focusRequested = false;
                    Assistant.tucked = true;
                    event.accepted = true;
                }
            }

            Text {
                visible: asideInput.text === ""
                width: parent.width
                text: I18n.tr("Ask something else…")
                elide: Text.ElideRight
                color: Theme.textFaint
                font: asideInput.font
            }
        }

        AssistantButton {
            id: asideSend
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(5)
            anchors.verticalCenter: parent.verticalCenter
            visible: asideInput.text.trim() !== ""
            glyph: "send"
            primary: true
            controlHeight: Theme.scaled(26)
            accessibleName: I18n.tr("Send")
            onTriggered: root.sendAside()
        }
    }

    Text {
        width: parent.width
        visible: Assistant.notice !== ""
        text: Assistant.notice
        wrapMode: Text.WordWrap
        color: Theme.textMid
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
    }

    function sendAside() {
        const text = asideInput.text.trim();
        if (text === "")
            return;
        asideInput.text = "";
        // A new question of its own: alongside, or up next.
        Assistant.continuing = "";
        Assistant.thread = null;
        Assistant.send(text);
    }
}
