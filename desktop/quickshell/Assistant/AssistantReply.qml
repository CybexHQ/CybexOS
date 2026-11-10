pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers

// The answer, under the question it answers. It stays until closed. What the
// turn left behind gets its own row: a staged system change to review and
// apply, a new widget to add to the bar, a routine it created, and what it
// changed, each with its own Undo (AssistantChanges). "What Wiz did" lists
// its steps. `room` is the height the box may use on this side of the
// character; a long reply scrolls inside it, and Expand opens the wide view.
AssistantSurface {
    id: root

    property real room: 400
    readonly property var turn: Assistant.turn
    readonly property bool failed: turn !== null && turn.status === "failed"
    readonly property var plugins: turn && turn.plugins ? turn.plugins : []
    readonly property var changes: turn && turn.changes ? turn.changes.filter(change => change.kind !== "system") : []
    readonly property var steps: turn && turn.steps ? turn.steps : []
    readonly property var routinesMade: turn && turn.routines ? turn.routines : []
    // The answer is longer than the box shows: Expand says so in words.
    readonly property bool overflowing: bodyFlick.contentHeight > bodyFlick.height + 1
    // The build this turn staged, while the updater still holds it.
    readonly property bool staged: turn !== null && !!turn.staged
        && Updates.deployment.transaction === turn.staged
    readonly property string deploymentState: staged ? (Updates.deployment.state || "") : ""
    readonly property var closure: AssistantHelpers.closureChanges(
        staged ? Updates.deployment.changes || "" : "", 5)
    readonly property real chromeHeight: header.height + actions.height
        + extras.height + spacing * 3 + padding * 2

    // ---- the question ------------------------------------------------------------
    Item {
        id: header
        width: parent.width
        height: Theme.scaled(28)

        BrandIcon {
            id: agentMark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSmall
            height: Theme.iconSmall
            name: root.turn ? AssistantHelpers.AGENT_ICONS[root.turn.agent] || "" : ""
            colorized: true
            tint: Theme.textLow
            normalizeTintSource: true
        }

        Text {
            anchors.left: agentMark.right
            anchors.leftMargin: Theme.scaled(7)
            anchors.right: duration.left
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.turn ? I18n.format("You · %1", [root.turn.prompt]) : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textLow
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
        }

        Text {
            id: duration
            anchors.right: expand.left
            anchors.rightMargin: Theme.scaled(4)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.turn !== null && root.turn.finishedAt > 0
            text: root.turn ? AssistantHelpers.elapsedLabel(root.turn.finishedAt - root.turn.startedAt) : ""
            color: Theme.textFaint
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.secondary
            font.features: Theme.tabularNumberFeatures
        }

        AssistantButton {
            id: expand
            anchors.right: close.left
            anchors.rightMargin: Theme.scaled(2)
            anchors.verticalCenter: parent.verticalCenter
            glyph: Settings.assistantExpanded ? "close_fullscreen" : "open_in_full"
            label: !Settings.assistantExpanded && root.overflowing ? I18n.tr("Expand") : ""
            accessibleName: Settings.assistantExpanded ? I18n.tr("Back to the small box") : I18n.tr("Expand")
            controlHeight: Theme.scaled(28)
            color: !Settings.assistantExpanded && root.overflowing ? Theme.chip : "transparent"
            onTriggered: Assistant.toggleExpanded()
        }

        AssistantButton {
            id: close
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "close"
            accessibleName: I18n.tr("Close the reply")
            controlHeight: Theme.scaled(28)
            color: "transparent"
            onTriggered: Assistant.closeReply()
        }
    }

    // ---- the answer ----------------------------------------------------------------
    Flickable {
        id: bodyFlick
        width: parent.width
        height: Math.max(Theme.scaled(24), Math.min(body.implicitHeight,
            root.room - root.chromeHeight))
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        AssistantMarkdown {
            id: body
            width: bodyFlick.width
            plain: root.failed
            text: root.failed ? (root.turn.error || I18n.tr("Something went wrong."))
                : root.turn ? root.turn.text || "" : ""
            color: root.failed ? Theme.redText : Theme.textHi
        }
    }

    // ---- what the turn left behind ---------------------------------------------------
    Column {
        id: extras
        width: parent.width
        spacing: Theme.scaled(8)

        // A failure names its one fix.
        AssistantButton {
            readonly property var action: root.failed
                ? AssistantHelpers.errorAction(root.turn.errorKind, root.turn.agent) : null
            visible: action !== null
            label: !action ? ""
                : root.turn.errorKind === "auth" ? I18n.tr("Sign in")
                : root.turn.errorKind === "missing" ? I18n.tr("Assistant settings")
                : I18n.tr("Start the assistant")
            primary: true
            onTriggered: Assistant.fix(root.turn.errorKind)
        }

        // A system change built and checked by the updater, waiting for review.
        Rectangle {
            width: parent.width
            visible: root.staged
            height: visible ? stagedColumn.implicitHeight + Theme.scaled(18) : 0
            radius: Theme.scaled(12)
            color: Theme.cardFill
            border.width: 1
            border.color: Theme.hairline

            Column {
                id: stagedColumn
                x: Theme.scaled(9)
                y: Theme.scaled(9)
                width: parent.width - Theme.scaled(18)
                spacing: Theme.scaled(4)

                Text {
                    width: parent.width
                    text: root.deploymentState === "ready" ? I18n.tr("Staged change · built and checked")
                        : root.deploymentState === "done" || root.deploymentState === "awaiting-boot"
                            || root.deploymentState === "awaiting-login" ? I18n.tr("Applied")
                        : Updates.deployment.phase || ""
                    elide: Text.ElideRight
                    color: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    font.weight: Theme.weightSemibold
                }

                Repeater {
                    model: root.deploymentState === "ready" ? root.closure.rows : []

                    delegate: Text {
                        required property var modelData
                        width: stagedColumn.width
                        text: (modelData.kind === "added" ? "+ " : modelData.kind === "removed" ? "− " : "~ ")
                            + modelData.name + "  " + modelData.change
                        elide: Text.ElideRight
                        color: modelData.kind === "added" ? Theme.ok
                            : modelData.kind === "removed" ? Theme.redText : Theme.textMid
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.typography.metadata
                    }
                }

                Text {
                    width: parent.width
                    visible: root.deploymentState === "awaiting-boot"
                    text: Updates.rebootRecommendation
                    wrapMode: Text.WordWrap
                    color: Theme.textLow
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }

                Row {
                    spacing: Theme.scaled(6)
                    visible: root.deploymentState === "ready"
                    topPadding: Theme.scaled(4)

                    AssistantButton {
                        objectName: "assistantReviewChange"
                        label: I18n.tr("Review change…")
                        primary: true
                        onTriggered: Assistant.reviewStagedChange()
                    }

                }
            }
        }

        // Routines this answer created: when they run, and their settings.
        Repeater {
            model: root.routinesMade

            delegate: Rectangle {
                id: routineCard
                required property var modelData
                width: extras.width
                height: routineColumn.implicitHeight + Theme.scaled(16)
                radius: Theme.scaled(10)
                color: Theme.cardFill

                Column {
                    id: routineColumn
                    x: Theme.scaled(10)
                    y: Theme.scaled(8)
                    width: parent.width - Theme.scaled(20)
                    spacing: Theme.scaled(3)

                    Row {
                        spacing: Theme.scaled(6)

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "event"
                            size: Theme.iconSmall
                            color: Theme.accentText
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Routine created")
                            color: Theme.textHi
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            font.weight: Theme.weightSemibold
                        }
                    }
                    Text {
                        width: parent.width
                        text: routineCard.modelData.title
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Theme.textMid
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                    }
                    Text {
                        width: parent.width
                        text: Assistant.routineLabel(routineCard.modelData) + " · "
                            + (routineCard.modelData.notify === "always" ? I18n.tr("always tells you")
                                : I18n.tr("tells you only when something needs attention"))
                        wrapMode: Text.WordWrap
                        color: Theme.textLow
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                    }
                    Row {
                        topPadding: Theme.scaled(4)
                        spacing: Theme.scaled(4)

                        AssistantButton {
                            label: I18n.tr("Edit")
                            controlHeight: Theme.scaled(26)
                            onTriggered: Assistant.showRoutines()
                        }
                        AssistantButton {
                            label: I18n.tr("Run now")
                            glyph: "play_arrow"
                            controlHeight: Theme.scaled(26)
                            onTriggered: Assistant.runRoutine(routineCard.modelData.id)
                        }
                    }
                }
            }
        }

        // Everything the answer changed, each with its own Undo.
        AssistantChanges {
            width: parent.width
            changes: root.changes
        }

        AssistantSteps {
            width: parent.width
            steps: root.steps
            folded: AssistantHelpers.stepsFolded(root.turn ? root.turn.text : "", root.steps)
        }

        // Widgets the turn created. They stay off until added.
        Repeater {
            model: root.plugins

            delegate: Rectangle {
                id: pluginRow
                required property var modelData
                width: extras.width
                height: Theme.scaled(40)
                radius: Theme.scaled(10)
                color: Theme.cardFill

                Sym {
                    id: pluginGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.scaled(10)
                    anchors.verticalCenter: parent.verticalCenter
                    name: "widgets"
                    size: Theme.iconMedium
                    color: Theme.accentText
                }

                Column {
                    anchors.left: pluginGlyph.right
                    anchors.leftMargin: Theme.scaled(9)
                    anchors.right: addButton.left
                    anchors.rightMargin: Theme.scaled(8)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: pluginRow.modelData.name || pluginRow.modelData.id
                        elide: Text.ElideRight
                        color: Theme.textHi
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                    }
                    Text {
                        width: parent.width
                        text: I18n.format("%1 · off until added", [pluginRow.modelData.id])
                        elide: Text.ElideRight
                        color: Theme.textLow
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.typography.metadata
                    }
                }

                AssistantButton {
                    id: addButton
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.scaled(6)
                    anchors.verticalCenter: parent.verticalCenter
                    label: I18n.tr("Add to bar")
                    primary: true
                    controlHeight: Theme.scaled(28)
                    onTriggered: Assistant.addWidget(pluginRow.modelData.id)
                }
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
    }

    // ---- actions -------------------------------------------------------------------
    Flow {
        id: actions
        width: parent.width
        spacing: Theme.scaled(4)

        AssistantButton {
            visible: Assistant.speechAvailable && !root.failed && root.turn !== null && (root.turn.text || "") !== ""
            label: Assistant.speaking ? I18n.tr("Stop") : I18n.tr("Speak")
            glyph: Assistant.speaking ? "stop" : "volume_up"
            onTriggered: {
                if (Assistant.speaking)
                    Assistant.stopSpeaking();
                else
                    Assistant.speak();
            }
        }

        AssistantButton {
            label: I18n.tr("Reply")
            glyph: "reply"
            onTriggered: Assistant.reply()
        }

        AssistantButton {
            objectName: "assistantCopyReply"
            visible: !root.failed && root.turn !== null && (root.turn.text || "") !== ""
            glyph: "content_copy"
            label: I18n.tr("Copy")
            accessibleName: I18n.tr("Copy the reply")
            tip: I18n.tr("Copy the reply")
            onTriggered: Assistant.copyReply()
        }

        AssistantButton {
            objectName: "assistantHandoff"
            visible: root.turn !== null && root.turn.resumable === true
            glyph: "terminal"
            label: I18n.tr("Terminal")
            accessibleName: I18n.tr("Continue in a terminal")
            tip: I18n.tr("Continue in a terminal")
            onTriggered: Assistant.handoff()
        }
    }

    // Sentence by sentence while it is read aloud.
    Rectangle {
        width: parent.width
        height: 2
        radius: 1
        visible: Assistant.speaking && Assistant.speechCount > 0
        color: Theme.hairline

        Rectangle {
            width: parent.width * Math.min(1, (Assistant.speechIndex + 1) / Math.max(1, Assistant.speechCount))
            height: parent.height
            radius: 1
            color: Theme.accent

            Behavior on width {
                NumberAnimation { duration: Theme.chipFadeDuration }
            }
        }
    }
}
