pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers

// Wiz's conversation history, in the box under him (docs/assistant.md):
// grouped by day, newest first, searchable across questions and answers. A
// row opens its conversation to read and continue; Delete removes one, with
// Undo until the box closes; Clear history removes every one after asking.
// `room` is the height the box may use; the list scrolls within it.
AssistantSurface {
    id: root

    property real room: 400
    readonly property var groups: AssistantHelpers.groupConversations(Assistant.historyRows, Assistant.now)
    readonly property bool searching: Assistant.historyQuery.trim() !== ""
    readonly property real chromeHeight: header.height + searchField.height + footer.height
        + (toast.visible ? toast.height + spacing : 0) + spacing * 3 + padding * 2

    function groupLabel(group) {
        switch (group) {
        case "today": return I18n.tr("Today");
        case "yesterday": return I18n.tr("Yesterday");
        case "week": return I18n.tr("Earlier this week");
        default: return I18n.tr("Older");
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (Assistant.confirmingClear)
                Assistant.confirmingClear = false;
            else if (searchInput.text !== "")
                searchInput.text = "";
            else
                Assistant.backFromHistory();
            event.accepted = true;
        }
    }

    Connections {
        target: Assistant

        function onFocusComposer() {
            if (root.visible)
                Qt.callLater(() => searchInput.forceActiveFocus());
        }
    }

    onVisibleChanged: {
        if (visible)
            Qt.callLater(() => searchInput.forceActiveFocus());
    }

    // ---- header ------------------------------------------------------------------
    Item {
        id: header
        width: parent.width
        height: Theme.scaled(26)

        AssistantButton {
            id: back
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "arrow_back"
            accessibleName: I18n.tr("Back")
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.backFromHistory()
        }

        Text {
            anchors.left: back.right
            anchors.leftMargin: Theme.scaled(6)
            anchors.right: newButton.left
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("History")
            elide: Text.ElideRight
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            font.weight: Theme.weightSemibold
        }

        AssistantButton {
            id: newButton
            anchors.right: close.left
            anchors.rightMargin: Theme.scaled(4)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "add"
            label: I18n.tr("New")
            accessibleName: I18n.tr("New conversation")
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.newConversation()
        }

        AssistantButton {
            id: close
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "close"
            accessibleName: I18n.tr("Close")
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.closeBox()
        }
    }

    // ---- search ------------------------------------------------------------------
    Rectangle {
        id: searchField
        width: parent.width
        height: Theme.scaled(34)
        radius: Theme.scaled(9)
        color: Theme.well
        border.width: 1
        border.color: searchInput.activeFocus ? Theme.accent : Theme.hairline

        Sym {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(9)
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: Theme.iconSmall
            color: Theme.textFaint
        }

        TextInput {
            id: searchInput
            anchors.left: searchGlyph.right
            anchors.leftMargin: Theme.scaled(7)
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(9)
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: Theme.textHi
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.textHi
            selectByMouse: true
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            Accessible.name: I18n.tr("Search conversations")
            text: Assistant.historyQuery
            onTextChanged: Assistant.historyQuery = text
            onActiveFocusChanged: {
                if (activeFocus)
                    Assistant.focusRequested = true;
            }
            Keys.onDownPressed: event => {
                root.focusFirstRow();
                event.accepted = true;
            }

            Text {
                visible: searchInput.text === ""
                width: parent.width
                text: I18n.tr("Search conversations")
                elide: Text.ElideRight
                color: Theme.textFaint
                font: searchInput.font
            }
        }
    }

    function focusFirstRow() {
        for (let i = 0; i < list.children.length; i++) {
            const rows = list.children[i].rowItems;
            if (rows && rows.count > 0) {
                rows.itemAt(0).forceActiveFocus();
                return;
            }
        }
    }

    // ---- the conversations -------------------------------------------------------------
    Flickable {
        id: listFlick
        width: parent.width
        height: Math.max(Theme.scaled(60), Math.min(list.implicitHeight, root.room - root.chromeHeight))
        contentWidth: width
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: list
            width: listFlick.width

            Repeater {
                model: root.groups

                delegate: Column {
                    id: group
                    required property var modelData
                    readonly property alias rowItems: rows
                    width: list.width

                    Text {
                        width: parent.width
                        topPadding: Theme.scaled(8)
                        bottomPadding: Theme.scaled(2)
                        text: root.groupLabel(group.modelData.group).toUpperCase()
                        color: Theme.textFaint
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        font.weight: Theme.weightSemibold
                        font.letterSpacing: 0.6
                    }

                    Repeater {
                        id: rows
                        model: group.modelData.rows

                        delegate: AssistantConversationRow {
                            required property var modelData
                            width: group.width
                            row: modelData
                            deletable: true
                            onOpened: Assistant.openConversation(modelData.id)
                            onDeleteRequested: Assistant.deleteConversation(modelData.id)
                        }
                    }
                }
            }

            Column {
                width: parent.width
                visible: Assistant.historyRows.length === 0
                topPadding: Theme.scaled(18)
                bottomPadding: Theme.scaled(14)
                spacing: Theme.scaled(3)

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.searching ? I18n.format("Nothing matches “%1”.", [Assistant.historyQuery.trim()])
                        : I18n.tr("No conversations yet.")
                    wrapMode: Text.Wrap
                    color: Theme.textLow
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                }

                Text {
                    width: parent.width
                    visible: !root.searching
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("Questions you ask Wiz appear here.")
                    wrapMode: Text.Wrap
                    color: Theme.textFaint
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }
            }
        }
    }

    // ---- Undo for the one just deleted ---------------------------------------------------
    Rectangle {
        id: toast
        width: parent.width
        visible: Assistant.deletedConversation !== null
        height: visible ? Theme.scaled(34) : 0
        radius: Theme.scaled(9)
        color: Theme.cardFill
        border.width: 1
        border.color: Theme.hairline

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(10)
            anchors.right: undoButton.left
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            text: Assistant.deletedConversation
                ? I18n.format("Deleted “%1”", [Assistant.deletedConversation.title || ""]) : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textMid
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
        }

        AssistantButton {
            id: undoButton
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(4)
            anchors.verticalCenter: parent.verticalCenter
            label: I18n.tr("Undo")
            controlHeight: Theme.scaled(26)
            color: "transparent"
            onTriggered: Assistant.undoDelete()
        }
    }

    // ---- clearing ------------------------------------------------------------------------
    Item {
        id: footer
        width: parent.width
        visible: Assistant.confirmingClear || Assistant.conversations.length > 0
        height: !visible ? 0 : Assistant.confirmingClear ? confirm.implicitHeight : Theme.scaled(28)

        Rectangle {
            width: parent.width
            height: 1
            visible: !Assistant.confirmingClear
            color: Theme.hairline
            opacity: 0.6
        }

        AssistantButton {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            visible: !Assistant.confirmingClear && Assistant.conversations.length > 0
            glyph: "delete"
            label: I18n.tr("Clear history…")
            danger: true
            color: "transparent"
            controlHeight: Theme.scaled(26)
            onTriggered: Assistant.confirmingClear = true
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.scaled(1)
            visible: !Assistant.confirmingClear
            text: Assistant.conversations.length === 1 ? I18n.tr("1 conversation")
                : I18n.format("%1 conversations", [Assistant.conversations.length])
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
        }

        // Asked once, here in the box.
        Rectangle {
            id: confirm
            width: parent.width
            visible: Assistant.confirmingClear
            implicitHeight: confirmColumn.implicitHeight + Theme.scaled(24)
            radius: Theme.scaled(12)
            color: Theme.cardFill
            border.width: 1
            border.color: Theme.hairline

            Column {
                id: confirmColumn
                x: Theme.scaled(12)
                y: Theme.scaled(12)
                width: parent.width - Theme.scaled(24)
                spacing: Theme.scaled(6)

                Text {
                    width: parent.width
                    text: Assistant.conversations.length === 1 ? I18n.tr("Clear the conversation?")
                        : I18n.format("Clear all %1 conversations?", [Assistant.conversations.length])
                    wrapMode: Text.Wrap
                    color: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    font.weight: Theme.weightSemibold
                }

                Text {
                    width: parent.width
                    text: I18n.tr("They are removed from Wiz’s history on this computer. This can’t be undone.")
                    wrapMode: Text.Wrap
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }

                Text {
                    readonly property var running: Assistant.busy && Assistant.busyConversation !== ""
                        ? Assistant.conversations.find(row => row.id === Assistant.busyConversation) ?? null : null
                    width: parent.width
                    visible: running !== null
                    text: running ? I18n.format("“%1” is still working and will be stopped. A change it already staged stays in Software Update.",
                        [running.title || ""]) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.scaled(6)
                    topPadding: Theme.scaled(4)

                    AssistantButton {
                        label: I18n.tr("Cancel")
                        color: "transparent"
                        controlHeight: Theme.scaled(28)
                        onTriggered: Assistant.confirmingClear = false
                    }

                    AssistantButton {
                        objectName: "assistantClearHistory"
                        glyph: "delete"
                        label: I18n.tr("Clear all")
                        danger: true
                        controlHeight: Theme.scaled(28)
                        onTriggered: Assistant.clearHistory()
                    }
                }
            }
        }
    }
}
