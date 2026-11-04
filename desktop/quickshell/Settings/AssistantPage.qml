pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers
import "../Common/SettingsSearchData.js" as SettingsSearchData

// Assistant: who answers, what it may see and hear, how it behaves on the
// desktop, everything it changed and the routines it runs
// (docs/assistant.md). The agents keep their own sign-in and settings; this
// page chooses the agent and the assistant's tool permissions. Screen context
// and spoken replies are off until switched on here.
SettingsPage {
    id: page
    pageReset: true

    readonly property bool claudeInstalled: !!(Assistant.agents.claude && Assistant.agents.claude.available)
    readonly property bool codexInstalled: !!(Assistant.agents.codex && Assistant.agents.codex.available)

    // ---- the change log ------------------------------------------------------
    property var changes: []
    property bool allChanges: false
    readonly property var changeGroups: AssistantHelpers.groupChanges(
        allChanges ? changes : changes.slice(0, 12), Assistant.now)

    function reloadChanges() {
        if (!Assistant.connected)
            return;
        Assistant.loadChanges(rows => {
            if (rows !== null)
                page.changes = rows;
        });
    }

    onVisibleChanged: {
        if (visible)
            reloadChanges();
    }
    Component.onCompleted: reloadChanges()

    Connections {
        target: Assistant

        function onChangesRevisionChanged() {
            page.reloadChanges();
        }

        function onConnectedChanged() {
            page.reloadChanges();
        }
    }

    function groupLabel(group) {
        switch (group) {
        case "today": return I18n.tr("Today");
        case "yesterday": return I18n.tr("Yesterday");
        case "week": return I18n.tr("Earlier this week");
        default: return I18n.tr("Older");
        }
    }

    function changeValue(row) {
        const time = Qt.formatTime(new Date(row.at), Settings.clock24 ? "HH:mm" : "h:mm AP");
        const what = row.kind === "setting" ? row.before + " → " + row.after
            : row.detail === "created" ? I18n.tr("created")
            : row.detail === "installed" ? I18n.tr("installed")
            : row.detail === "removed" || row.detail === "deleted" ? I18n.tr("removed")
            : row.kind === "system" ? I18n.tr("system change")
            : I18n.tr("changed");
        const state = row.status === "undone" ? I18n.tr("undone")
            : row.status === "blocked" ? I18n.tr("changed again later, undo that first")
            : row.status === "changed" ? I18n.tr("changed since")
            : "";
        return [what, time, state].filter(part => part !== "").join(" · ");
    }

    function undoLabel(row) {
        switch (row.action) {
        case "delete": return I18n.tr("Delete");
        case "remove": return I18n.tr("Remove");
        default: return I18n.tr("Undo");
        }
    }

    // ---- the routine being written ------------------------------------------------
    property bool editing: false
    property string editId: ""
    property string editQuestion: ""
    property string editKind: "weekly"
    property int editWeekday: 0
    property int editDay: 1
    property string editTime: "09:00"
    property bool editAttention: true
    property string editError: ""

    function newRoutine() {
        editId = "";
        editQuestion = "";
        editKind = "weekly";
        editWeekday = 0;
        editDay = 1;
        editTime = "09:00";
        editAttention = true;
        editError = "";
        editing = true;
    }

    function editRoutine(routine) {
        editId = routine.id;
        editQuestion = routine.question;
        editKind = routine.schedule.kind;
        editWeekday = routine.schedule.weekday || 0;
        editDay = routine.schedule.day || 1;
        editTime = routine.schedule.time || "09:00";
        editAttention = routine.notify !== "always";
        editError = "";
        editing = true;
    }

    function saveRoutine() {
        const schedule = { kind: editKind };
        if (editKind !== "update")
            schedule.time = editTime.trim();
        if (editKind === "weekly")
            schedule.weekday = editWeekday;
        if (editKind === "monthly")
            schedule.day = editDay;
        const fields = { question: editQuestion.trim(), schedule: schedule,
            notify: editAttention ? "attention" : "always" };
        const done = (routine, error) => {
            if (error) {
                page.editError = error.message;
                return;
            }
            page.editing = false;
        };
        if (editId === "")
            Assistant.createRoutine(fields, done);
        else
            Assistant.updateRoutine(editId, Object.assign({ title: fields.question }, fields), done);
    }

    function routineDetail(routine) {
        const last = routine.last;
        const lastText = !last ? I18n.tr("not run yet")
            : last.status === "failed" ? I18n.tr("last run failed")
            : last.attention ? I18n.tr("last run found something")
            : I18n.tr("last run: all well");
        return [Assistant.routineLabel(routine),
            routine.notify === "always" ? I18n.tr("always tells you") : I18n.tr("tells you when something needs attention"),
            routine.enabled ? lastText : I18n.tr("paused")].join(" · ");
    }

    function installedLabel(installed) {
        return !Assistant.connected ? "" : installed ? I18n.tr("installed") : I18n.tr("not installed");
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.settingsGroupSpacing

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Assistant")

            ValueRow {
                width: parent.width
                label: I18n.tr("Status")
                value: !Settings.assistantConfigured ? I18n.tr("Not part of this installation")
                    : Assistant.connected && Assistant.setupRequired ? I18n.tr("Sign in to set up the assistant")
                    : Assistant.connected ? (Settings.assistantShown ? I18n.tr("Ready, on screen") : I18n.tr("Ready, hidden"))
                    : I18n.tr("The assistant service is not running")
                dotColor: Assistant.connected ? Theme.ok : Theme.textFaint

                SettingsAction {
                    visible: Settings.assistantConfigured && Assistant.connected
                    text: Settings.assistantShown ? I18n.tr("Hide") : I18n.tr("Show")
                    onTriggered: Assistant.toggleShown(Settings.panelScreenName)
                }
                SettingsAction {
                    visible: Settings.assistantConfigured && !Assistant.connected
                    text: I18n.tr("Start")
                    onTriggered: Quickshell.execDetached(["systemctl", "--user", "start", "cybexos-assistant.service"])
                }
            }
            SettingsHint {
                width: parent.width
                text: I18n.tr("Click the character or tap Super+I to type. Hold Super+I to talk, and release to send. Super+Shift+I asks about the selected text.")
            }
            // The read-only `cybex doctor` report, and the assistant asked
            // about it (docs/system-check.md).
            ValueRow {
                width: parent.width
                visible: Settings.assistantConfigured
                label: I18n.tr("System check")
                value: Doctor.running ? I18n.tr("Checking this computer…")
                    : Doctor.report === null ? (Doctor.error || I18n.tr("Not checked yet"))
                    : Doctor.attention.length === 0 ? I18n.tr("This computer looks good")
                    : Doctor.attention.length === 1 ? Doctor.sentence(Doctor.attention[0])
                    : I18n.format("%1 things to look at", [Doctor.attention.length])
                dotColor: Doctor.report === null ? Theme.textFaint : Doctor.attention.length > 0 ? Theme.amber : Theme.ok
                Component.onCompleted: Doctor.refreshIfStale()

                SettingsAction {
                    text: I18n.tr("Ask the assistant")
                    enabled: Assistant.connected && !Assistant.busy
                    onTriggered: Assistant.checkSystem()
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Agent")

            PickerRow {
                width: parent.width
                label: I18n.tr("Answered by")
                settingKey: "assistantAgent"
                model: [
                    { value: "auto", label: I18n.tr("Automatic") },
                    { value: "claude", label: "Claude Code" },
                    { value: "codex", label: "Codex" }
                ]
                caption: Settings.assistantAgent === "auto" && Assistant.connected
                    ? I18n.format("Now %1", [AssistantHelpers.AGENT_LABELS[Assistant.agent]]) : ""
                captionMono: false
            }
            SettingsHint {
                width: parent.width
                text: I18n.tr("Automatic follows your cybex agent default, then whichever is installed. Sign-in stays with the agent itself.")
            }
            PickerRow {
                width: parent.width
                label: I18n.tr("Tool permissions")
                settingKey: "assistantApprovalPolicy"
                model: [
                    { value: "always", label: I18n.tr("Always allow") },
                    { value: "ask", label: I18n.tr("Ask first") }
                ]
            }
            ValueRow {
                width: parent.width
                label: I18n.tr("Sign-in")
                value: Assistant.authChecking ? I18n.tr("Checking sign-in…")
                    : Assistant.agentReady ? I18n.tr("Signed in") : I18n.tr("Sign-in required")
                SettingsAction {
                    text: Assistant.agentReady ? I18n.tr("Check sign-in") : I18n.tr("Sign in")
                    enabled: Assistant.connected && !Assistant.authChecking && !Assistant.busy
                    onTriggered: {
                        if (Assistant.agentReady)
                            Assistant.refreshAuth();
                        else {
                            Assistant.openComposer(true);
                            Assistant.refreshAuth();
                        }
                    }
                }
            }
            SelectRow {
                width: parent.width
                label: I18n.tr("Claude Code model")
                settingKey: "assistantClaudeModel"
                model: [{ value: "default", label: I18n.tr("Claude Code's default") },
                    { value: "fable", label: "Fable" }, { value: "sonnet", label: "Sonnet" },
                    { value: "opus", label: "Opus" }]
                hint: page.installedLabel(page.claudeInstalled)
            }
            SelectRow {
                width: parent.width
                label: I18n.tr("Codex model")
                settingKey: "assistantCodexModel"
                model: [{ value: "default", label: I18n.tr("Codex's default") },
                    { value: "gpt-5.6-luna", label: "Luna" }, { value: "gpt-5.6-terra", label: "Terra" },
                    { value: "gpt-5.6-sol", label: "Sol" }]
                hint: page.installedLabel(page.codexInstalled)
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Conversations")

            PickerRow {
                width: parent.width
                label: I18n.tr("Keep conversations")
                settingKey: "assistantHistory"
                model: [
                    { value: "month", label: I18n.tr("30 days") },
                    { value: "forever", label: I18n.tr("Forever") },
                    { value: "session", label: I18n.tr("Don’t save") }
                ]
            }
            SettingsHint {
                width: parent.width
                text: Settings.assistantHistory === "session"
                    ? I18n.tr("Conversations last until you log out. Nothing is saved on this computer.")
                    : I18n.tr("Conversations are saved in your home folder. Clearing them leaves Claude Code’s and Codex’s own sessions alone.")
            }
            ValueRow {
                width: parent.width
                label: I18n.tr("History")
                value: !Assistant.connected ? I18n.tr("The assistant service is not running")
                    : Assistant.conversations.length === 0 ? I18n.tr("No conversations yet")
                    : Assistant.conversations.length === 1 ? I18n.tr("1 conversation")
                    : I18n.format("%1 conversations", [Assistant.conversations.length])

                SettingsAction {
                    text: I18n.tr("Open")
                    enabled: Assistant.connected
                    onTriggered: Assistant.openHistory()
                }
                SettingsAction {
                    text: I18n.tr("Clear…")
                    enabled: Assistant.connected && Assistant.conversations.length > 0
                    onTriggered: {
                        Assistant.openHistory();
                        Assistant.confirmingClear = true;
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Behaviour")

            PickerRow {
                width: parent.width
                label: I18n.tr("When the pointer rests on Wiz")
                settingKey: "assistantHover"
                model: [
                    { value: "status", label: I18n.tr("Show status") },
                    { value: "open", label: I18n.tr("Open the box") },
                    { value: "nothing", label: I18n.tr("Nothing") }
                ]
            }
            PickerRow {
                width: parent.width
                label: I18n.tr("Notify when Wiz finishes")
                settingKey: "assistantNotify"
                model: [
                    { value: "closed", label: I18n.tr("When the box is closed") },
                    { value: "always", label: I18n.tr("Always") },
                    { value: "never", label: I18n.tr("Never") }
                ]
            }
            SettingsHint {
                width: parent.width
                text: I18n.tr("Questions that take longer than 20 seconds, and every question waiting for your answer.")
            }
            SwitchRow {
                width: parent.width
                label: I18n.tr("Fade while working under Wiz")
                settingKey: "assistantFade"
                description: I18n.tr("When the pointer sweeps over him, he fades and clicks go to the window underneath. Resting on him brings him back.")
            }
            SwitchRow {
                width: parent.width
                label: I18n.tr("Include the focused window")
                settingKey: "assistantWindowContext"
                description: I18n.tr("A new question carries the app and title of the window you were using, as a chip you can remove.")
            }
            SwitchRow {
                width: parent.width
                label: I18n.tr("Wide view for answers")
                settingKey: "assistantExpanded"
                description: I18n.tr("Opens answers beside Wiz with room for tables and code. Expand and its edge change this too.")
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Changes Wiz made")
            property string searchAnchor: "assistant-changes"

            SettingsHint {
                width: parent.width
                text: page.changes.length === 0 ? I18n.tr("Nothing yet. Every preference, file, widget, app and routine Wiz changes is listed here and can be undone.")
                    : I18n.tr("Undo restores what was there before. A change that something later changed again waits for that to be undone first.")
            }

            Repeater {
                model: page.changeGroups

                delegate: SettingsSubsection {
                    id: day
                    required property var modelData
                    width: parent.width
                    title: page.groupLabel(day.modelData.group)

                    Repeater {
                        model: day.modelData.rows

                        delegate: ValueRow {
                            id: changeRowItem
                            required property var modelData
                            readonly property var row: AssistantHelpers.changeRow(modelData, SettingsSearchData.ROWS)
                            width: parent.width
                            label: row.label
                            labelMono: row.kind === "file"
                            value: page.changeValue(row)
                            valueColor: row.status === "blocked" || row.status === "changed" ? Theme.amber
                                : row.status === "undone" ? Theme.textFaint : Theme.textMid

                            SettingsAction {
                                visible: changeRowItem.row.undoable
                                text: page.undoLabel(changeRowItem.row)
                                onTriggered: Assistant.undoChanges([changeRowItem.row.id])
                            }
                            SettingsAction {
                                visible: changeRowItem.row.kind === "system"
                                text: I18n.tr("Software Update…")
                                onTriggered: Updates.show()
                            }
                            SettingsAction {
                                visible: changeRowItem.row.conversation !== ""
                                    && Assistant.conversations.some(entry => entry.id === changeRowItem.row.conversation)
                                compact: true
                                glyph: "history"
                                text: I18n.tr("Open the conversation")
                                onTriggered: Assistant.openConversation(changeRowItem.row.conversation)
                            }
                        }
                    }
                }
            }

            ValueRow {
                width: parent.width
                visible: page.changes.length > 12
                label: I18n.format("%1 changes this month", [page.changes.length])
                SettingsAction {
                    text: page.allChanges ? I18n.tr("Show fewer") : I18n.tr("Show all")
                    onTriggered: page.allChanges = !page.allChanges
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Routines")
            property string searchAnchor: "assistant-routines"

            SettingsHint {
                width: parent.width
                text: I18n.tr("Questions Wiz asks on a schedule while you're logged in. A routine only looks and reports; fixes wait for you in its conversation. Ask Wiz for one (“every Monday morning, check this computer”) or add one here.")
            }

            Repeater {
                model: Assistant.routines

                delegate: ValueRow {
                    id: routineRow
                    required property var modelData
                    width: parent.width
                    label: modelData.title
                    value: page.routineDetail(modelData)
                    valueColor: modelData.last && modelData.last.attention ? Theme.amber : Theme.textMid

                    SettingsAction {
                        compact: true
                        glyph: "play_arrow"
                        text: I18n.tr("Run now")
                        enabled: Assistant.connected
                        onTriggered: Assistant.runRoutine(routineRow.modelData.id)
                    }
                    SettingsAction {
                        text: routineRow.modelData.enabled ? I18n.tr("Pause") : I18n.tr("Resume")
                        onTriggered: Assistant.updateRoutine(routineRow.modelData.id,
                            { enabled: !routineRow.modelData.enabled })
                    }
                    SettingsAction {
                        text: I18n.tr("Edit")
                        onTriggered: page.editRoutine(routineRow.modelData)
                    }
                    SettingsAction {
                        compact: true
                        glyph: "delete"
                        danger: true
                        text: I18n.tr("Remove")
                        onTriggered: Assistant.deleteRoutine(routineRow.modelData.id)
                    }
                }
            }

            ValueRow {
                width: parent.width
                visible: !page.editing
                label: Assistant.routines.length === 0 ? I18n.tr("No routines yet") : ""
                SettingsAction {
                    glyph: "add"
                    text: I18n.tr("New routine")
                    enabled: Assistant.connected
                    onTriggered: page.newRoutine()
                }
            }

            // The routine being written or changed.
            SettingsSubsection {
                width: parent.width
                visible: page.editing
                title: page.editId === "" ? I18n.tr("New routine") : I18n.tr("Edit routine")

                SettingsTextRow {
                    width: parent.width
                    // A draft: Save or Cancel below, nothing to reset.
                    dirty: false
                    resetKeys: []
                    label: I18n.tr("Question")
                    value: page.editQuestion
                    placeholder: I18n.tr("Check this computer and tell me if anything needs attention")
                    onCommitted: text => page.editQuestion = text
                }
                SelectRow {
                    width: parent.width
                    // A draft: Save or Cancel below, nothing to reset.
                    dirty: false
                    resetKeys: []
                    label: I18n.tr("When")
                    current: page.editKind
                    model: [
                        { value: "daily", label: I18n.tr("Every day") },
                        { value: "weekly", label: I18n.tr("Every week") },
                        { value: "monthly", label: I18n.tr("Every month") },
                        { value: "update", label: I18n.tr("After each kept update") }
                    ]
                    onPicked: value => page.editKind = value
                }
                SelectRow {
                    width: parent.width
                    // A draft: Save or Cancel below, nothing to reset.
                    dirty: false
                    resetKeys: []
                    visible: page.editKind === "weekly"
                    label: I18n.tr("Day")
                    current: page.editWeekday
                    model: [
                        { value: 0, label: I18n.tr("Monday") }, { value: 1, label: I18n.tr("Tuesday") },
                        { value: 2, label: I18n.tr("Wednesday") }, { value: 3, label: I18n.tr("Thursday") },
                        { value: 4, label: I18n.tr("Friday") }, { value: 5, label: I18n.tr("Saturday") },
                        { value: 6, label: I18n.tr("Sunday") }
                    ]
                    onPicked: value => page.editWeekday = value
                }
                SelectRow {
                    width: parent.width
                    // A draft: Save or Cancel below, nothing to reset.
                    dirty: false
                    resetKeys: []
                    visible: page.editKind === "monthly"
                    label: I18n.tr("Day of the month")
                    current: page.editDay
                    model: Array.from({ length: 28 }, (_, index) => ({ value: index + 1, label: String(index + 1) }))
                    onPicked: value => page.editDay = value
                }
                SettingsTextRow {
                    width: parent.width
                    // A draft: Save or Cancel below, nothing to reset.
                    dirty: false
                    resetKeys: []
                    visible: page.editKind !== "update"
                    label: I18n.tr("Time")
                    value: page.editTime
                    placeholder: "09:00"
                    fieldWidth: Theme.scaled(90, Theme.typeScale)
                    onCommitted: text => page.editTime = text
                }
                SwitchRow {
                    width: parent.width
                    // A draft: Save or Cancel below, nothing to reset.
                    dirty: false
                    resetKeys: []
                    label: I18n.tr("Tell me only when something needs attention")
                    checked: page.editAttention
                    onToggled: value => page.editAttention = value
                }
                SettingsHint {
                    width: parent.width
                    visible: page.editError !== ""
                    tone: "warning"
                    text: page.editError
                }
                ValueRow {
                    width: parent.width
                    SettingsAction {
                        text: I18n.tr("Cancel")
                        onTriggered: page.editing = false
                    }
                    SettingsAction {
                        primary: true
                        text: page.editId === "" ? I18n.tr("Add routine") : I18n.tr("Save")
                        enabled: page.editQuestion.trim() !== ""
                        onTriggered: page.saveRoutine()
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Voice and screen")

            SwitchRow {
                width: parent.width
                label: I18n.tr("Speak replies")
                settingKey: "assistantSpeak"
                description: Assistant.connected && !Assistant.speechAvailable
                    ? I18n.tr("Speech is unavailable: speech-dispatcher is not running.")
                    : I18n.tr("Reads each reply aloud and asks the agent to keep it short.")
            }
            SwitchRow {
                width: parent.width
                label: I18n.tr("Screen context")
                settingKey: "assistantScreenContext"
                description: I18n.tr("Adds a screen button to the box. It sends one screenshot of the display the assistant is on, without the assistant, with that question only, and deletes it afterwards.")
            }
            ValueRow {
                width: parent.width
                label: I18n.tr("Talking")
                value: Assistant.voiceAvailable ? I18n.tr("Voxtype, on this computer") : I18n.tr("Voxtype is not running")
                SettingsAction {
                    text: I18n.tr("Dictation settings")
                    onTriggered: Settings.setTab("assistant", "dictation")
                }
            }
        }
    }
}
