pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import "AssistantHelpers.js" as AssistantHelpers

// The shell's side of the Cybex OS Assistant (docs/assistant.md). The
// cybexos-assistant user service owns the agent processes and every turn, so
// a reload of this shell never ends one; this singleton is its client. It
// owns what only the desktop can know: where the character stands, whether
// its box is open, push-to-talk through Voxtype, and the one screenshot a
// question may carry.
Singleton {
    id: root

    // ---- availability ------------------------------------------------------
    readonly property bool available: Settings.assistantConfigured
    readonly property string runtimeDir:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cybexos"
    readonly property string socketPath: runtimeDir + "/assistant.sock"
    readonly property string scratchDir: runtimeDir + "/assistant"
    readonly property string home: Quickshell.env("HOME") || ""

    // ---- service state -------------------------------------------------------
    readonly property bool connected: socket.connected && helloed
    property bool helloed: false
    property var agents: ({})
    property bool speechAvailable: false
    property var turn: null
    // A question asked while the main one runs, answered alongside; it may
    // only look (docs/assistant.md).
    property var side: null
    // The question waiting until Wiz is free ("Up next"), or null.
    property var queue: null
    property var routines: []
    // The conversation a routine found something in: Wiz shows the amber pip
    // until it is opened.
    property string attentionConversation: ""
    // Bumped whenever the change log changes, so Settings reloads it.
    property int changesRevision: 0
    // The `cybex agent` default, which "auto" follows.
    property string preferredAgent: ""

    readonly property string agent: AssistantHelpers.resolveAgent(
        Settings.assistantAgent, agents, preferredAgent)
    readonly property string agentLabel: AssistantHelpers.AGENT_LABELS[agent] || agent
    readonly property bool agentInstalled: !!(agents[agent] && agents[agent].available)
    readonly property bool agentReady: agentInstalled && agents[agent].auth === "ready"
    // Chosen with the box's agent chip, for this conversation only; Settings
    // keeps the default.
    property string agentOverride: ""
    property string modelOverride: ""
    // Who answers the next question: a continued conversation keeps the
    // agent it started with, a new one takes the chip's choice or the default.
    readonly property string askAgent: continuingRow ? continuingRow.agent
        : thread && continuing !== "" ? thread.agent : agentOverride !== "" ? agentOverride : agent
    readonly property string askModel: modelOverride !== ""
        ? (modelOverride === "default" ? "" : modelOverride)
        : AssistantHelpers.modelFor(askAgent, Settings.assistantClaudeModel, Settings.assistantCodexModel)
    readonly property string askModelLabel: AssistantHelpers.modelLabel(askAgent, askModel === "" ? "default" : askModel)
    readonly property string askAgentLabel: AssistantHelpers.AGENT_LABELS[askAgent] || askAgent
    readonly property bool askReady: !!(agents[askAgent] && agents[askAgent].available
        && agents[askAgent].auth === "ready")
    readonly property bool setupRequired: !askReady
    property bool authChecking: false
    property string signingIn: ""

    readonly property bool busy: AssistantHelpers.active(turn)
    readonly property bool sideBusy: AssistantHelpers.active(side)
    readonly property bool waiting: turn !== null && turn.status === "waiting"
    readonly property var approvals: turn && turn.approvals ? turn.approvals : []
    readonly property bool hasReply: AssistantHelpers.finished(turn)
    // The conversation a running question belongs to.
    readonly property string busyConversation: busy && turn ? turn.conversation || "" : ""

    // ---- conversation history (docs/assistant.md) -------------------------------
    // Every conversation, newest first, as the service lists them.
    property var conversations: []
    // The conversation the next question continues; "" starts a new one.
    property string continuing: ""
    // That conversation's questions and answers, once loaded.
    property var thread: null
    readonly property var continuingRow: continuing === "" ? null
        : conversations.find(row => row.id === continuing) ?? null
    property bool historyOpen: false
    property string historyQuery: ""
    // Search results while a query is typed; the full list otherwise.
    property var searchResults: []
    readonly property var historyRows: historyQuery.trim() === "" ? conversations : searchResults
    // The conversation deleted last, offered back with Undo while the box stays open.
    property var deletedConversation: null
    property bool confirmingClear: false

    // ---- presence and placement --------------------------------------------
    // The character is out unless game mode wants the screen to itself.
    readonly property bool shown: available && Settings.assistantShown && !GameMode.active
    readonly property ShellScreen screen: Screens.byName(Settings.assistantScreen) ?? Screens.focused
    readonly property string screenName: screen ? screen.name : ""

    // ---- box state -----------------------------------------------------------
    // The composer: a new conversation, or `continuing` with its transcript.
    property bool composing: false
    // The box was opened by the keyboard or a click, so it takes the keyboard.
    property bool focusRequested: false
    property string draft: ""
    // Clicking the character while it works tucks the box away.
    property bool tucked: false
    property bool replyOpen: false
    property bool unread: false
    property bool celebrating: false
    property string notice: ""
    property bool dragging: false
    // The status line under him while the pointer rests on him.
    property bool statusShown: false
    readonly property bool failed: turn !== null && turn.status === "failed" && replyOpen

    readonly property var characterState: ({
        connected: root.connected, listening: root.listening, waiting: root.waiting,
        busy: root.busy, transcribing: root.transcribing, dragging: root.dragging,
        speaking: root.speaking, celebrating: root.celebrating, failed: root.failed,
        composing: root.composing || root.historyOpen, step: root.turn ? root.turn.step || "" : "",
        attention: root.attentionConversation !== ""
    })
    readonly property string pose: AssistantHelpers.characterPose(characterState)
    // Wiz stands on his own and needs the room.
    readonly property real characterSize: Theme.scaled(88)

    // ---- voice ---------------------------------------------------------------
    // Voxtype runs on every installation; Dictation watches its state for us.
    readonly property bool voiceAvailable: available && !Dictation.stateMissing
    property bool listening: false
    property bool transcribing: false
    // A tap on the microphone latches it; a held key or press does not.
    property bool voiceLatched: false
    property bool sendAfterTranscript: false
    // The recording ended without a stop from here (see onStateChanged).
    property bool endedByDaemon: false
    property double listenStartedAt: 0
    readonly property string transcriptPath: scratchDir + "/voice.txt"

    // ---- screen context ------------------------------------------------------
    property bool capturing: false
    // A suggestion about the screen waits for its screenshot.
    property string pendingScreenQuestion: ""
    property bool screenAttached: false
    property string screenPath: ""
    property string screenOutput: ""

    // ---- attachments (docs/assistant.md) --------------------------------------------
    // What goes with the next question besides the screenshot: the focused
    // window, selected text, files and pasted or dropped images. Each is a
    // chip the person can remove; images are copied to the scratch folder,
    // which the service empties once the question is answered.
    property var attachments: []
    property int attachmentSerial: 0

    // ---- the suggestion that fits the moment ------------------------------------------
    property var updateFailedAt: null
    property var keptRelease: null
    property var warnings: []
    property double situationDismissedAt: 0
    readonly property var situation: AssistantHelpers.situation({ now: now, updateFailed: updateFailedAt,
        kept: keptRelease, warnings: warnings, dismissedAt: situationDismissedAt })

    // ---- speech ----------------------------------------------------------------
    property bool speaking: false
    property string speechId: ""
    property int speechIndex: 0
    property int speechCount: 0

    // ---- Super+I --------------------------------------------------------------
    property bool shortcutHolding: false

    // ---- the system check ------------------------------------------------------
    // The question behind "Check this computer". Sending it, however it was
    // typed or chosen, tells the service this is a system check, so the agent
    // starts from `cybex doctor` (docs/system-check.md).
    readonly property string systemCheckQuestion:
        I18n.tr("Check this computer for missing drivers and other problems.")

    signal focusComposer()

    // ---- presence ------------------------------------------------------------
    function show(outputName) {
        if (!available)
            return;
        if (outputName && outputName !== Settings.assistantScreen && Screens.byName(outputName))
            moveTo(outputName, Settings.assistantX, Settings.assistantY);
        else if (Settings.assistantScreen === "" && screen)
            Settings.set("assistantScreen", screen.name);
        Settings.set("assistantShown", true);
        // Brought back for a reply that finished while it was away.
        if (unread && hasReply && !busy) {
            unread = false;
            replyOpen = true;
        }
    }

    function hide() {
        if (listening)
            cancelListening();
        closeBox();
        Settings.set("assistantShown", false);
    }

    function toggleShown(outputName) {
        if (Settings.assistantShown)
            hide();
        else
            show(outputName);
    }

    // Where the character rests on an output this size: AssistantWindow puts
    // him there, and the welcome guide's hand-off flies him there.
    function restingPlace(width, height) {
        const reserve = Settings.position === "top" ? Theme.barHeight + Theme.barTopMargin : 0;
        return AssistantHelpers.placement({ x: Settings.assistantX, y: Settings.assistantY },
            { width: width, height: height }, characterSize, reserve);
    }

    function moveTo(outputName, x, y) {
        if (outputName !== Settings.assistantScreen)
            Settings.set("assistantScreen", outputName);
        if (x !== Settings.assistantX)
            Settings.set("assistantX", Math.round(x));
        if (y !== Settings.assistantY)
            Settings.set("assistantY", Math.round(y));
    }

    // ---- the box -------------------------------------------------------------
    function openComposer(withFocus) {
        if (!available)
            return;
        if (!Settings.assistantShown)
            show(Screens.focused ? Screens.focused.name : "");
        tucked = false;
        // While a question runs, the box is its pill; another conversation
        // can still be read (and answered once Wiz is free).
        if (busy && (continuing === "" || continuing === busyConversation))
            return;
        composing = true;
        if (withFocus) {
            focusRequested = true;
            focusComposer();
        }
    }

    // Opened by a click, a tap of Super+I or the launcher: a new conversation,
    // unless the last one still needs the person (opensLastConversation).
    // Hovering opens the box as it was left instead (AssistantWindow.qml).
    function openFresh(withFocus) {
        if (!available)
            return;
        if (!Settings.assistantShown)
            show(Screens.focused ? Screens.focused.name : "");
        untuck();
        // A routine's finding comes first: its conversation opens.
        if (attentionConversation !== "" && !busy) {
            const id = attentionConversation;
            attentionConversation = "";
            if (conversations.some(row => row.id === id)) {
                openConversation(id);
                return;
            }
        }
        if (AssistantHelpers.opensLastConversation({ busy: busy, unread: unread, hasReply: hasReply })) {
            if (busy) {
                tucked = false;
                if (withFocus) {
                    focusRequested = true;
                    focusComposer();
                }
            } else {
                unread = false;
                closeComposer();
                replyOpen = true;
            }
            return;
        }
        startNew();
        openComposer(withFocus);
    }

    // The next question starts a new conversation.
    function startNew() {
        continuing = "";
        thread = null;
        historyOpen = false;
        confirmingClear = false;
        replyOpen = false;
        agentOverride = "";
        modelOverride = "";
        clearAttachments();
        stopSpeaking();
        if (Settings.assistantWindowContext)
            attachWindow();
    }

    function toggleComposer() {
        if ((composing || historyOpen) && focusRequested && !listening)
            closeBox();
        else if (busy && Settings.assistantShown && !composing && !historyOpen) {
            // While he works, Super+I opens the working box to ask something
            // else meanwhile, and tucks it away again.
            if (!tucked && focusRequested) {
                tucked = true;
                focusRequested = false;
            } else {
                untuck();
                tucked = false;
                focusRequested = true;
                focusComposer();
            }
        }
        else if (composing || historyOpen)
            openComposer(true);
        else
            openFresh(true);
    }

    function closeComposer() {
        composing = false;
        focusRequested = false;
        notice = "";
    }

    // The empty box a hover opened closes again once the pointer leaves.
    function hoverEnded() {
        if (composing && !focusRequested && draft.trim() === "" && !listening
                && !transcribing && !screenAttached && !capturing)
            closeComposer();
    }

    // A click elsewhere: History closes with the rest of the box.
    function focusLost() {
        if (historyOpen)
            closeHistory();
        hoverEnded();
    }

    function closeReply() {
        replyOpen = false;
        unread = false;
        stopSpeaking();
    }

    function closeBox() {
        closeComposer();
        closeReply();
        closeHistory();
    }

    function reviewStagedChange() {
        if (!turn || !turn.staged || Updates.deployment.transaction !== turn.staged)
            return;
        closeBox();
        Updates.closeWhatsNew();
        // Release the overlay's focus and input region before showing the
        // review window. The turn stays available on the character.
        Qt.callLater(Updates.show);
    }

    function characterClicked() {
        if (Settings.assistantTuck !== "") {
            untuck();
            return;
        }
        if (attentionConversation !== "" && !busy) {
            openFresh(true);
            return;
        }
        if (unread && hasReply) {
            unread = false;
            closeComposer();
            closeHistory();
            replyOpen = true;
            return;
        }
        unread = false;
        if (historyOpen) {
            closeBox();
            return;
        }
        if (busy && !composing) {
            tucked = !tucked;
            return;
        }
        if (composing && focusRequested && draft.trim() === "")
            closeComposer();
        else if (composing)
            // The box a hover opened takes the keyboard, as it was.
            openComposer(true);
        else
            openFresh(true);
    }

    // Continues the conversation of the answer on screen.
    function reply() {
        const id = turn ? turn.conversation || "" : "";
        closeReply();
        if (id !== "")
            continueConversation(id);
        openComposer(true);
    }

    // ---- the history -------------------------------------------------------------
    function continueConversation(id) {
        if (continuing !== id || thread === null || thread.id !== id) {
            continuing = id;
            thread = null;
        }
        loadThread();
    }

    function loadThread() {
        const id = continuing;
        if (id === "" || !connected)
            return;
        request("conversation.open", { id: id }, (result, error) => {
            if (root.continuing !== id)
                return;
            if (error || !result || !result.conversation) {
                root.continuing = "";
                root.thread = null;
                root.notice = error ? error.message : "";
                return;
            }
            root.thread = result.conversation;
        });
    }

    function openHistory() {
        if (!available)
            return;
        if (!Settings.assistantShown)
            show(Screens.focused ? Screens.focused.name : "");
        historyOpen = true;
        confirmingClear = false;
        tucked = false;
        focusRequested = true;
        refreshConversations();
        focusComposer();
    }

    function closeHistory() {
        historyOpen = false;
        historyQuery = "";
        searchResults = [];
        confirmingClear = false;
        deletedConversation = null;
    }

    // Back from History to the box it was opened from.
    function backFromHistory() {
        closeHistory();
        if (busy && continuing === busyConversation)
            composing = false;
        else
            openComposer(true);
    }

    // History's "New": the box for a new conversation.
    function newConversation() {
        closeHistory();
        startNew();
        openComposer(true);
    }

    // A row in History or under the suggestions.
    function openConversation(id) {
        closeHistory();
        replyOpen = false;
        if (busy && id === busyConversation) {
            // Its question is still running: the pill shows it.
            continuing = id;
            composing = false;
            tucked = false;
            return;
        }
        if (turn && turn.conversation === id)
            unread = false;
        continueConversation(id);
        openComposer(true);
    }

    function refreshConversations() {
        request("conversation.list", {}, (result, error) => {
            if (result)
                root.conversations = result.conversations || [];
        });
        search();
    }

    function search() {
        const query = historyQuery.trim();
        if (query === "") {
            searchResults = [];
            return;
        }
        request("conversation.list", { query: query }, (result, error) => {
            if (result && root.historyQuery.trim() === query)
                root.searchResults = result.conversations || [];
        });
    }

    onHistoryQueryChanged: searchDelay.restart()

    Timer {
        id: searchDelay
        interval: 180
        onTriggered: root.search()
    }

    function deleteConversation(id) {
        const row = conversations.find(entry => entry.id === id) ?? null;
        request("conversation.delete", { id: id }, (result, error) => {
            if (error) {
                root.notice = error.message;
                return;
            }
            root.deletedConversation = row;
            if (root.continuing === id) {
                root.continuing = "";
                root.thread = null;
            }
            if (root.turn && root.turn.conversation === id)
                root.closeReply();
        });
    }

    function undoDelete() {
        const row = deletedConversation;
        if (!row)
            return;
        deletedConversation = null;
        request("conversation.restore", { id: row.id }, (result, error) => {
            if (error)
                root.notice = error.message;
        });
    }

    // Every conversation goes, from this computer's history; the agents
    // keep their own session files.
    function clearHistory() {
        confirmingClear = false;
        request("conversation.clear", {}, (result, error) => {
            if (error) {
                root.notice = error.message;
                return;
            }
            root.deletedConversation = null;
            root.continuing = "";
            root.thread = null;
            root.closeReply();
        });
    }

    function copyConversation() {
        if (!thread)
            return;
        Quickshell.clipboardText = AssistantHelpers.conversationText(thread);
        notice = I18n.tr("Copied.");
    }

    // ---- Super+I: tap to type, hold to talk ------------------------------------
    function shortcutPressed() {
        if (!available)
            return;
        if (listening) {
            stopListening(true);
            return;
        }
        shortcutHolding = true;
        holdTimer.restart();
    }

    function shortcutReleased() {
        if (holdTimer.running) {
            holdTimer.stop();
            shortcutHolding = false;
            toggleComposer();
            return;
        }
        if (shortcutHolding && listening && !voiceLatched)
            stopListening(true);
        shortcutHolding = false;
    }

    Timer {
        id: holdTimer
        interval: AssistantHelpers.HOLD_MS
        onTriggered: {
            if (root.voiceAvailable && !root.busy) {
                root.openComposer(false);
                root.startListening(false);
            } else {
                root.shortcutHolding = false;
                root.toggleComposer();
            }
        }
    }

    // ---- asking ----------------------------------------------------------------
    function send(text) {
        const prompt = String(text === undefined ? draft : text).trim();
        if (prompt === "" || (busy && queue !== null && sideBusy))
            return;
        if (!connected) {
            notice = I18n.tr("The assistant service is not running.");
            return;
        }
        if (!askReady) {
            draft = prompt;
            openComposer(true);
            refreshAuth();
            return;
        }
        stopSpeaking();
        const context = { output: screenName, speak: Settings.assistantSpeak, language: I18n.language,
            wide: Settings.assistantExpanded };
        if (prompt === systemCheckQuestion)
            context.purpose = "system-check";
        const continued = continuing;
        const sent = attachments;
        const params = {
            text: prompt,
            agent: root.askAgent,
            model: root.askModel,
            conversation: continued,
            screenshot: screenAttached ? screenPath : "",
            attachments: sent.map(item => ({ kind: item.kind, label: item.label, path: item.path || "",
                text: item.text || "" })),
            context: context
        };
        // The service owns the screenshot and images from here and deletes them.
        const shot = screenAttached ? screenPath : "";
        screenAttached = false;
        screenPath = "";
        attachments = [];
        // Asking anything ends the moment's suggestion.
        situationDismissedAt = Date.now();
        draft = "";
        notice = "";
        composing = false;
        focusRequested = false;
        replyOpen = false;
        tucked = false;
        unread = false;
        closeHistory();
        const wasBusy = busy;
        request("turn.start", params, (result, error) => {
            if (error) {
                // Refused before the service took the screenshot: remove it
                // here, so it does not outlive the question it was for.
                if (shot !== "")
                    Quickshell.execDetached(["rm", "-f", "--", shot]);
                // The chips come back with the words, images and all.
                root.attachments = sent;
                root.draft = prompt;
                root.notice = error.code === -32001
                    ? I18n.tr("Wiz is still working on another question.")
                    : error.message || I18n.tr("The assistant could not start.");
                // A conversation deleted meanwhile: the question starts a new one.
                if (error.code === -32002 && root.continuing === continued) {
                    root.continuing = "";
                    root.thread = null;
                }
                root.composing = true;
                if (error.code === -32004)
                    root.refreshAuth();
                return;
            }
            if (result.queued) {
                root.queue = result.queued;
                root.notice = I18n.tr("Up next: Wiz asks this once he is free.");
                return;
            }
            if (result.turn && result.turn.lane === "side") {
                root.adoptSide(result.turn);
                return;
            }
            // The box reopened by a hover continues this conversation.
            root.continuing = result.turn ? result.turn.conversation || "" : "";
            root.thread = null;
            root.adopt(result.turn);
            if (wasBusy)
                root.composing = false;
        });
    }

    function stop() {
        if (busy)
            request("turn.stop", {});
    }

    function stopSide() {
        if (sideBusy)
            request("turn.stop", { lane: "side" });
    }

    // ---- the queue -------------------------------------------------------------------
    function removeQueued() {
        request("queue.remove", {}, (result, error) => {
            if (!error)
                root.queue = null;
        });
    }

    // Stops the current question, so the waiting one starts now.
    function runQueuedNow() {
        request("queue.run", {}, (result, error) => {
            if (error)
                root.notice = error.message;
        });
    }

    // Asks the assistant to check this computer, from the welcome guide or
    // the box's first suggestion. Without a signed-in agent the question
    // waits in the box while setup is shown, like any other.
    function checkSystem() {
        if (!available || busy)
            return;
        if (!Settings.assistantShown)
            show(Screens.focused ? Screens.focused.name : "");
        startNew();
        send(systemCheckQuestion);
    }

    // `cybexos-runtime ipc assistant ask` and the launcher's Ask Wiz: a
    // question of its own, in a new conversation.
    function ask(text) {
        if (!available)
            return;
        if (!busy)
            startNew();
        openComposer(false);
        send(text);
    }

    function respond(approvalId, decision) {
        request("approval.respond", { id: approvalId, decision: decision });
    }

    function undo() {
        if (!turn)
            return;
        const ids = (turn.changes || []).filter(change => change.undoable).map(change => change.id);
        if (ids.length > 0)
            undoChanges(ids);
    }

    // Undoes changes from the log (the reply's rows, Settings → Assistant).
    function undoChanges(ids, done) {
        request("change.undo", { ids: ids }, (result, error) => {
            if (error) {
                root.notice = error.message;
                if (done)
                    done(false);
                return;
            }
            const skipped = result.skipped || [];
            root.notice = skipped.length === 0 ? I18n.tr("Undone.")
                : skipped.length === 1 && (result.restored || []).length === 0 ? skipped[0].reason
                : I18n.format("Undid %1; %2 were left as they are.", [(result.restored || []).length,
                    skipped.length]);
            if (done)
                done(true);
        });
    }

    // The log for Settings → Assistant → Changes.
    function loadChanges(callback) {
        request("change.list", {}, (result, error) => callback(error ? null : result.changes || []));
    }

    // ---- routines ---------------------------------------------------------------------
    function createRoutine(fields, callback) {
        request("routine.create", fields, (result, error) => {
            if (error)
                root.notice = error.message;
            if (callback)
                callback(error ? null : result.routine, error);
        });
    }

    function updateRoutine(id, fields, callback) {
        request("routine.update", Object.assign({ id: id }, fields), (result, error) => {
            if (error)
                root.notice = error.message;
            if (callback)
                callback(error ? null : result.routine, error);
        });
    }

    function deleteRoutine(id) {
        request("routine.delete", { id: id });
    }

    function runRoutine(id) {
        request("routine.run", { id: id }, (result, error) => {
            if (error)
                root.notice = error.message;
            else if (result.waiting)
                root.notice = I18n.tr("Wiz runs it as soon as he is free.");
        });
    }

    // Settings → Assistant, scrolled to its routines.
    function showRoutines() {
        Settings.showPanel("assistant", screenName);
        Settings.highlightKey = "";
        Settings.highlightKey = "assistant-routines";
    }

    // "Mondays at 09:00", "Every day at 08:00", "After each kept update".
    function routineLabel(routine) {
        const schedule = routine && routine.schedule ? routine.schedule : {};
        const days = [I18n.tr("Mondays"), I18n.tr("Tuesdays"), I18n.tr("Wednesdays"), I18n.tr("Thursdays"),
            I18n.tr("Fridays"), I18n.tr("Saturdays"), I18n.tr("Sundays")];
        switch (schedule.kind) {
        case "daily": return I18n.format("Every day at %1", [schedule.time]);
        case "weekly": return I18n.format("%1 at %2", [days[schedule.weekday || 0], schedule.time]);
        case "monthly": return I18n.format("Day %1 of each month at %2", [schedule.day, schedule.time]);
        default: return I18n.tr("After each kept update");
        }
    }

    // Continues the same Claude Code or Codex session in Kitty, for work that
    // outgrows a box under a character: the conversation given, else the
    // answer's.
    function handoff(id) {
        const conversation = id || (turn ? turn.conversation || "" : "");
        request("conversation.handoff", { id: conversation }, (result, error) => {
            if (error || !result || !(Array.isArray(result.argv) || result.argv instanceof Array)) {
                root.notice = error ? error.message : I18n.tr("Nothing to continue yet.");
                return;
            }
            Quickshell.execDetached(["cybexos-apps", "terminal", "--app-id=cybexos-agent",
                "--dir=" + (result.cwd || root.home), "--"].concat(result.argv));
        });
    }

    function copyReply() {
        Quickshell.clipboardText = AssistantHelpers.copyText(turn);
        notice = I18n.tr("Copied.");
    }

    function addWidget(pluginId) {
        Quickshell.execDetached(["cybex", "plugin", "enable", pluginId]);
        notice = I18n.tr("Added to the bar.");
    }

    function fix(kind) {
        const action = AssistantHelpers.errorAction(kind, turn ? turn.agent : agent);
        if (!action)
            return;
        if (action.auth) {
            // The failed question's conversation continues once signed in.
            if (turn && turn.conversation)
                continueConversation(turn.conversation);
            openComposer(true);
            signIn(turn ? turn.agent : agent);
        } else if (action.command)
            Quickshell.execDetached(["cybexos-apps", "terminal", "--hold", "--"].concat(action.command));
        else if (action.unit)
            Quickshell.execDetached(["systemctl", "--user", "start", action.unit]);
        else if (action.page)
            Settings.showPanel(action.page, screenName);
    }

    // Sign-in stays with the agent. The service only supplies its fixed login
    // command and checks its status; no credential is sent through this socket.
    // Both agents' commands open the browser and wait for it on localhost, so
    // the command runs in the background, without a terminal.
    // Returns whether the sign-in was asked for.
    function signIn(agentId) {
        if (!connected || authChecking || busy || signInProcess.running)
            return false;
        Settings.set("assistantAgent", agentId);
        request("auth.login", { agent: agentId }, (result, error) => {
            if (error || !result || !(Array.isArray(result.argv) || result.argv instanceof Array)) {
                root.notice = error ? error.message : I18n.tr("Sign-in could not start.");
                return;
            }
            if (signInProcess.running)
                return;
            root.signingIn = agentId;
            root.focusRequested = false;
            signInProcess.agent = agentId;
            signInProcess.workingDirectory = result.cwd;
            signInProcess.command = ["sh", "-c", "exec \"$@\" </dev/null >/dev/null 2>&1", "sh"].concat(result.argv);
            signInProcess.running = true;
            authPoll.restart();
            authDeadline.restart();
        });
        return true;
    }

    // Stops a sign-in still waiting for the browser.
    function cancelSignIn() {
        authPoll.stop();
        authDeadline.stop();
        signingIn = "";
        signInProcess.running = false;
    }

    function refreshAuth() {
        if (!connected || authChecking)
            return;
        authChecking = true;
        request("auth.status", {}, (result, error) => {
            root.authChecking = false;
            if (result)
                root.adoptAgents(result.agents || {});
            else if (error)
                root.notice = error.message;
        });
    }

    function adoptAgents(next) {
        agents = next;
        if (signingIn !== "" && next[signingIn] && next[signingIn].auth === "ready") {
            signingIn = "";
            authPoll.stop();
            authDeadline.stop();
            signInProcess.running = false;
            notice = I18n.tr("Signed in. Your question is ready to send.");
        }
    }

    Timer {
        id: authPoll
        interval: 3000
        repeat: true
        onTriggered: root.refreshAuth()
    }

    Timer {
        id: authDeadline
        interval: 300000
        onTriggered: root.cancelSignIn()
    }

    // The agent's login command. Its output can name the account, so it is
    // discarded rather than read or logged. It exits once the browser has
    // signed in; the status check confirms it.
    Process {
        id: signInProcess
        property string agent: ""
        onExited: (code) => {
            if (root.signingIn !== agent)
                return;
            if (code === 0) {
                root.refreshAuth();
                return;
            }
            authPoll.stop();
            authDeadline.stop();
            root.signingIn = "";
            root.notice = I18n.tr("Sign-in did not finish. Try again.");
        }
    }

    // ---- voice -----------------------------------------------------------------
    function startListening(latched) {
        if (!askReady) {
            openComposer(true);
            refreshAuth();
            return;
        }
        if (!voiceAvailable || listening || transcribing || busy)
            return;
        listening = true;
        endedByDaemon = false;
        voiceLatched = latched === true;
        listenStartedAt = Date.now();
        notice = "";
        // Removing the previous transcript first is what makes the next read
        // this recording's words. The model and languages are dictation's,
        // in Voxtype's configuration (Dictation applies Settings there).
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p -m 0700 "$1" && rm -f -- "$2" "$2.done" "$2.live" "$2.wav" && exec voxtype record start --file="$2"',
            "sh", scratchDir, transcriptPath]);
        Dictation.refresh();
        transcriptTimeout.stop();
    }

    function stopListening(sendWhenDone) {
        if (!listening)
            return;
        listening = false;
        voiceLatched = false;
        transcribing = true;
        sendAfterTranscript = sendWhenDone === true;
        Quickshell.execDetached(["voxtype", "record", "stop"]);
        Dictation.refresh();
        transcriptTimeout.restart();
        transcriptCheck.restart();
    }

    function cancelListening() {
        if (!listening && !transcribing)
            return;
        listening = false;
        transcribing = false;
        voiceLatched = false;
        transcriptTimeout.stop();
        Quickshell.execDetached(["voxtype", "record", "cancel"]);
    }

    function toggleMicrophone() {
        if (listening)
            stopListening(false);
        else
            startListening(true);
    }

    // Voxtype's state returns to idle once the transcript is on disk.
    Connections {
        target: Dictation

        function onStateChanged() {
            if (root.listening && Dictation.state === "transcribing") {
                // Voxtype ended the recording itself, at its length limit:
                // the words still arrive, for the person to send.
                root.listening = false;
                root.voiceLatched = false;
                root.transcribing = true;
                root.sendAfterTranscript = false;
                transcriptTimeout.restart();
            } else if (root.transcribing && Dictation.state === "idle") {
                transcript.reload();
            } else if (root.listening && Dictation.state === "idle"
                    && Date.now() - root.listenStartedAt > 1500) {
                // A live recording that Voxtype ended at its length limit goes
                // straight back to idle with its words on disk; a dropped one
                // (a device error, or Voxtype restarting) leaves none.
                root.listening = false;
                root.voiceLatched = false;
                root.transcribing = true;
                root.sendAfterTranscript = false;
                root.endedByDaemon = true;
                transcript.reload();
            }
        }
    }

    // A release that came before Voxtype had started recording leaves its
    // state idle throughout, so no change announces the end.
    Timer {
        id: transcriptCheck
        interval: 1500
        onTriggered: {
            if (root.transcribing && Dictation.state === "idle")
                transcript.reload();
        }
    }

    FileView {
        id: transcript
        path: root.transcriptPath
        printErrors: false
        onLoaded: root.transcribed(text().trim())
        onLoadFailed: root.transcribed("")
    }

    function transcribed(words) {
        if (!transcribing)
            return;
        transcribing = false;
        transcriptTimeout.stop();
        Quickshell.execDetached(["rm", "-f", "--", transcriptPath, transcriptPath + ".wav"]);
        const dropped = endedByDaemon;
        endedByDaemon = false;
        if (words === "") {
            notice = dropped ? I18n.tr("The microphone stopped. Try again.") : I18n.tr("Nothing was heard.");
            return;
        }
        draft = draft.trim() === "" ? words : draft.trim() + " " + words;
        if (sendAfterTranscript)
            send();
        else
            openComposer(true);
    }

    Timer {
        id: transcriptTimeout
        interval: 45000
        onTriggered: {
            if (root.transcribing) {
                root.transcribing = false;
                root.notice = I18n.tr("Transcription took too long.");
            }
        }
    }

    // ---- screen context ----------------------------------------------------------
    // One screenshot of the display the character is on, taken with the
    // character hidden; it travels with the next question only.
    function attachScreen() {
        if (!Settings.assistantScreenContext || capturing || screenName === "" || !askReady)
            return;
        capturing = true;
        captureDelay.restart();
    }

    function askAboutScreen(question) {
        if (screenAttached) {
            send(question);
            return;
        }
        pendingScreenQuestion = question;
        attachScreen();
    }

    function detachScreen() {
        if (screenPath !== "")
            Quickshell.execDetached(["rm", "-f", "--", screenPath]);
        screenAttached = false;
        screenPath = "";
    }

    function toggleScreen() {
        if (screenAttached)
            detachScreen();
        else
            attachScreen();
    }

    // Long enough for the compositor to present a frame without the
    // character before grim reads the output.
    Timer {
        id: captureDelay
        interval: 160
        onTriggered: {
            const path = root.scratchDir + "/screen-" + Date.now() + ".png";
            capture.path = path;
            capture.output = root.screenName;
            capture.command = ["sh", "-c", 'mkdir -p -m 0700 "$1" && exec grim -o "$2" -l 6 "$3"',
                "sh", root.scratchDir, root.screenName, path];
            capture.running = true;
            captureTimeout.restart();
        }
    }

    // The character stays hidden while capturing, so a capture that hangs
    // must not hide it for good.
    Timer {
        id: captureTimeout
        interval: 8000
        onTriggered: {
            if (!root.capturing)
                return;
            capture.running = false;
            root.capturing = false;
            root.pendingScreenQuestion = "";
            root.notice = I18n.tr("The screen could not be captured.");
        }
    }

    Process {
        id: capture
        property string path: ""
        property string output: ""
        onExited: (code) => {
            captureTimeout.stop();
            if (!root.capturing)
                return;
            root.capturing = false;
            if (code === 0) {
                if (root.screenPath !== "" && root.screenPath !== capture.path)
                    Quickshell.execDetached(["rm", "-f", "--", root.screenPath]);
                root.screenPath = capture.path;
                root.screenOutput = capture.output;
                root.screenAttached = true;
                if (root.pendingScreenQuestion !== "")
                    root.send(root.pendingScreenQuestion);
            } else {
                root.notice = I18n.tr("The screen could not be captured.");
            }
            root.pendingScreenQuestion = "";
        }
    }

    // ---- speech --------------------------------------------------------------
    function speak() {
        if (!turn || !turn.text || !connected)
            return;
        request("speech.say", { text: turn.text, language: I18n.language }, (result, error) => {
            if (error || !result) {
                root.notice = error ? error.message : "";
                return;
            }
            root.speechId = result.id;
            root.speechIndex = 0;
            root.speechCount = (result.sentences || []).length;
            root.speaking = root.speechCount > 0;
        });
    }

    function stopSpeaking() {
        if (!speaking)
            return;
        speaking = false;
        request("speech.stop", {});
    }

    // ---- attachments ------------------------------------------------------------------
    function attach(item) {
        const others = item.kind === "window" || item.kind === "selection"
            ? attachments.filter(entry => entry.kind !== item.kind) : attachments.slice();
        if (others.length >= AssistantHelpers.MAX_ATTACHMENTS) {
            notice = I18n.tr("That is as much as one question can carry.");
            if (item.kind === "image" && item.path)
                Quickshell.execDetached(["rm", "-f", "--", item.path]);
            return;
        }
        attachmentSerial++;
        attachments = others.concat([Object.assign({ id: "a" + attachmentSerial, detail: "" }, item)]);
    }

    function removeAttachment(id) {
        const item = attachments.find(entry => entry.id === id);
        if (item && item.kind === "image" && item.path)
            Quickshell.execDetached(["rm", "-f", "--", item.path]);
        attachments = attachments.filter(entry => entry.id !== id);
    }

    function clearAttachments() {
        for (const item of attachments) {
            if (item.kind === "image" && item.path)
                Quickshell.execDetached(["rm", "-f", "--", item.path]);
        }
        attachments = [];
    }

    // The focused window's app and title, as Wiz's box opens over it. The box
    // is a layer, not a window, so the focus is still the person's window.
    function attachWindow() {
        const window = Hyprland.activeToplevel;
        if (!window || (window.title || "") === "")
            return;
        const ipc = window.lastIpcObject || {};
        const app = String(ipc.class || "").replace(/^.*\./, "");
        const label = (app !== "" ? app.charAt(0).toUpperCase() + app.slice(1) + " · " : "") + window.title;
        attach({ kind: "window", label: label.length > 160 ? label.slice(0, 159) + "…" : label });
    }

    // Super+Shift+I: the box, with the selected text attached.
    function askAboutSelection() {
        if (!available)
            return;
        selectionReader.running = false;
        selectionReader.running = true;
    }

    Process {
        id: selectionReader
        command: ["sh", "-c", "wl-paste --primary --no-newline 2>/dev/null | head -c 262144"]
        stdout: StdioCollector {
            id: selectionText
            onStreamFinished: {
                const text = selectionText.text;
                root.openFresh(true);
                if (text.trim() === "") {
                    root.notice = I18n.tr("Nothing is selected.");
                    return;
                }
                const lines = AssistantHelpers.lineCount(text);
                root.attach({ kind: "selection", label: I18n.tr("Selected text"), text: text,
                    detail: lines === 1 ? I18n.tr("1 line") : I18n.format("%1 lines", [lines]) });
            }
        }
    }

    // Files dropped on Wiz or the box. Images travel as pictures, copied to
    // the scratch folder the service empties; anything else as text, which
    // the service reads and refuses when it is not.
    function attachUrls(urls) {
        const paths = (urls || []).map(url => AssistantHelpers.localPath(url.toString ? url.toString() : url))
            .filter(path => path !== "");
        if (paths.length === 0)
            return;
        if (!composing && !busy)
            openFresh(true);
        for (const path of paths) {
            const name = path.split("/").pop();
            if (AssistantHelpers.isImagePath(path)) {
                attachmentSerial++;
                const copy = scratchDir + "/drop-" + Date.now() + "-" + attachmentSerial + "."
                    + name.split(".").pop().toLowerCase();
                Quickshell.execDetached(["sh", "-c", 'mkdir -p -m 0700 "$1" && cp -- "$2" "$3"', "sh",
                    scratchDir, path, copy]);
                attach({ kind: "image", label: name, path: copy });
            } else {
                attach({ kind: "file", label: name, path: path });
            }
        }
        fileSizes.paths = paths;
        fileSizes.running = false;
        fileSizes.running = true;
    }

    Process {
        id: fileSizes
        property var paths: []
        command: ["stat", "--printf=%s\t%n\n", "--"].concat(paths)
        stdout: SplitParser {
            onRead: line => {
                const tab = line.indexOf("\t");
                if (tab < 0)
                    return;
                const size = parseInt(line.slice(0, tab), 10);
                const path = line.slice(tab + 1);
                root.attachments = root.attachments.map(item => item.path === path || item.label === path.split("/").pop()
                    && item.kind === "image" ? Object.assign({}, item, { detail: AssistantHelpers.sizeLabel(size) }) : item);
            }
        }
    }

    // A pasted image (Ctrl+V with a picture on the clipboard).
    function pasteImage() {
        attachmentSerial++;
        imagePaste.target = scratchDir + "/paste-" + Date.now() + "-" + attachmentSerial + ".png";
        imagePaste.running = false;
        imagePaste.running = true;
    }

    Process {
        id: imagePaste
        property string target: ""
        command: ["sh", "-c", 'wl-paste --list-types 2>/dev/null | grep -qx "image/png" || exit 3; '
            + 'mkdir -p -m 0700 "$1" && wl-paste --no-newline --type image/png > "$2" && echo pasted', "sh",
            root.scratchDir, target]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "pasted")
                    root.attach({ kind: "image", label: I18n.tr("Pasted image"), path: imagePaste.target });
            }
        }
    }

    // "Ask Wiz" from a notification, Software Update or the system check:
    // the box opens with what that place knows attached and the question
    // typed, ready to send or change. Nothing is sent yet.
    function askWith(question, item) {
        if (!available)
            return;
        openFresh(true);
        if (busy && !composing)
            tucked = false;
        if (item)
            attach(item);
        draft = question;
        focusComposer();
    }

    // Whether Ask Wiz may be offered: the service can take a question now.
    readonly property bool canAsk: available && connected && !GameMode.active

    // ---- the suggestion that fits the moment --------------------------------------------
    function noticeWarning(entry, critical) {
        if (!entry || !AssistantHelpers.looksLikeFailure(entry.summary, entry.body, critical))
            return;
        const summary = String(entry.displaySummary || entry.summary || "").replace(/\s+/g, " ").trim();
        if (summary === "" || entry.appName === "Wiz")
            return;
        const now = Date.now();
        warnings = warnings.filter(item => now - item.at < AssistantHelpers.SITUATION_MS).slice(-40)
            .concat([{ key: (entry.sourceKey || entry.appName || "") + "|" + summary, summary: summary, at: now }]);
    }

    function useSituation() {
        situationDismissedAt = Date.now();
    }

    Connections {
        target: Updates

        function onDeploymentChanged() {
            const state = Updates.deployment.state;
            if (state === "failed" && (!root.updateFailedAt || root.updateFailedAt.transaction
                    !== (Updates.deployment.transaction || "")))
                root.updateFailedAt = { at: Date.now(), version: Updates.projectVersion || "",
                    transaction: Updates.deployment.transaction || "" };
        }

        function onKeptChanged() {
            const kept = Updates.kept;
            if (kept && kept.version && (!root.keptRelease || root.keptRelease.version !== kept.version))
                root.keptRelease = { at: Date.now(), version: kept.version };
        }
    }

    // Arrivals since the last look, including a repeat folded into an
    // earlier entry (its lastArrived moves on).
    property double notificationsSeenAt: Date.now()

    Connections {
        target: Notifs

        function onEntriesChanged() {
            let latest = root.notificationsSeenAt;
            for (const entry of Notifs.entries) {
                const arrived = entry.lastArrived || entry.arrived || 0;
                if (arrived <= root.notificationsSeenAt)
                    continue;
                latest = Math.max(latest, arrived);
                root.noticeWarning(entry, entry.urgency === NotificationUrgency.Critical);
            }
            root.notificationsSeenAt = latest;
        }
    }

    // The update that failed, for Ask Wiz: what Software Update knows of it.
    function updateFailureText() {
        const deployment = Updates.deployment || {};
        return [I18n.format("State: %1", [deployment.state || ""]),
            deployment.phase ? I18n.format("Phase: %1", [deployment.phase]) : "",
            deployment.transaction ? "Transaction: " + deployment.transaction + " (cybex update log "
                + deployment.transaction + ")" : "",
            Updates.error].filter(line => line !== "").join("\n");
    }

    function askAboutUpdate() {
        askWith(I18n.tr("Why did this update fail?"), { kind: "text",
            label: Updates.projectVersion !== "" ? I18n.format("Update · %1", [Updates.projectVersion])
                : I18n.tr("Software Update"),
            detail: I18n.tr("failed"), text: updateFailureText() });
    }

    // ---- the wide view ---------------------------------------------------------------
    function toggleExpanded() {
        Settings.set("assistantExpanded", !Settings.assistantExpanded);
    }

    // ---- tucked behind an edge -------------------------------------------------------
    function tuckTo(side) {
        if (Settings.assistantTuck !== side)
            Settings.set("assistantTuck", side);
        closeBox();
    }

    // Back out from behind the edge, standing just inside it.
    function untuck() {
        const side = Settings.assistantTuck;
        if (side === "")
            return;
        Settings.set("assistantTuck", "");
        if (screen)
            moveTo(screen.name, side === "left" ? AssistantHelpers.EDGE * 2
                : screen.width - characterSize - AssistantHelpers.EDGE * 2, Settings.assistantY);
    }

    // ---- what resting the pointer on him shows ---------------------------------------
    readonly property var status: {
        if (!connected)
            return { title: I18n.tr("Asleep"), detail: I18n.tr("The assistant service is not running") };
        if (waiting)
            return { title: I18n.tr("Waiting for you"), detail: approvals.length > 0 ? approvals[0].title || "" : "" };
        if (busy)
            return { title: I18n.tr("Working"), detail: turn ? turn.prompt || "" : "" };
        if (attentionConversation !== "") {
            const row = conversations.find(entry => entry.id === attentionConversation);
            return { title: I18n.tr("A routine found something"), detail: row ? row.title : "" };
        }
        if (unread && hasReply)
            return { title: I18n.tr("Reply ready"), detail: turn ? turn.prompt || "" : "" };
        return { title: I18n.tr("Ask me anything"), detail: "" };
    }

    // ---- desktop tools ---------------------------------------------------------------
    function runDesktopTool(params) {
        const id = params.id;
        let answered = false;
        const reply = (ok, result, error) => {
            if (answered)
                return;
            answered = true;
            request("desktop.respond", { id: id, ok: ok, result: result ?? null, error: error || "" });
        };
        AssistantTools.handle(String(params.tool || ""), params.arguments || {},
            result => reply(true, result, ""), message => reply(false, null, String(message)));
    }

    // ---- service ---------------------------------------------------------------
    property int nextId: 1
    property var pending: ({})

    function request(method, params, callback) {
        if (!socket.connected) {
            if (callback)
                callback(null, { code: -32000, message: I18n.tr("The assistant service is not running.") });
            return;
        }
        const id = nextId++;
        if (callback)
            pending[id] = { callback: callback, at: Date.now() };
        socket.write(JSON.stringify({ jsonrpc: "2.0", id: id, method: method, params: params || {} }) + "\n");
        socket.flush();
    }

    function receive(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (e) {
            console.warn("assistant: unreadable message from the service");
            return;
        }
        if (message.id !== undefined && message.method === undefined) {
            const entry = pending[message.id];
            delete pending[message.id];
            if (entry)
                entry.callback(message.result ?? null, message.error ?? null);
            return;
        }
        const params = message.params || {};
        switch (message.method) {
        case "agents.updated":
            adoptAgents(params.agents || {});
            break;
        case "turn.updated":
            if (params.lane === "side")
                adoptSide(params.turn);
            else
                adopt(params.turn);
            break;
        case "queue.updated":
            queue = params.queue || null;
            break;
        case "changes.updated":
            changesRevision++;
            break;
        case "routines.updated":
            routines = params.routines || [];
            break;
        case "routine.finished":
            routineFinished(params);
            break;
        case "notice":
            notice = params.text || "";
            break;
        case "desktop.request":
            runDesktopTool(params);
            break;
        case "conversations.updated":
            adoptConversations(params.conversations || []);
            break;
        case "turn.delta":
            if (turn && params.id === turn.id)
                turn = Object.assign({}, turn, { text: (turn.text || "") + (params.text || "") });
            else if (side && params.id === side.id)
                side = Object.assign({}, side, { text: (side.text || "") + (params.text || "") });
            break;
        case "speech.progress":
            if (params.id === speechId)
                speechIndex = params.index;
            break;
        case "speech.done":
            if (params.id === speechId)
                speaking = false;
            break;
        }
    }

    // Whether the box would be in view on the screen the person is using.
    function boxInView() {
        return Settings.assistantShown && !tucked && Settings.assistantTuck === "" && !GameMode.active
            && (!Screens.focused || !screen || Screens.focused.name === screen.name);
    }

    // Takes the service's snapshot of the current turn, and reacts to the
    // moment it finishes.
    function adopt(next) {
        const previous = turn;
        turn = next || null;
        if (!next)
            return;
        const wasActive = previous !== null && previous.id === next.id && AssistantHelpers.active(previous);
        if (next.status === "waiting" && !(previous && previous.id === next.id && previous.status === "waiting")) {
            if (AssistantHelpers.notifies(Settings.assistantNotify, "waiting", boxInView(), 0))
                notifyTurn(next, "waiting");
            // A question nobody can see waits forever; bring the character out.
            tucked = false;
            untuck();
            if (!Settings.assistantShown)
                show(Screens.focused ? Screens.focused.name : "");
        }
        if (!wasActive || !AssistantHelpers.finished(next))
            return;
        // Its transcript now has the answer.
        if (next.conversation === continuing)
            thread = null;
        if (next.status === "stopped") {
            draft = next.prompt || "";
            notice = next.undo && next.undo.length > 0
                ? I18n.tr("Stopped. Undo reverts what it had changed.")
                : I18n.tr("Stopped. Nothing was changed.");
            replyOpen = (next.undo && next.undo.length > 0) || (next.text || "") !== "";
            composing = !replyOpen;
            return;
        }
        if (!next.routine && AssistantHelpers.notifies(Settings.assistantNotify, "finished", boxInView(),
                (next.finishedAt || 0) - (next.startedAt || 0)))
            notifyTurn(next, "finished");
        // A routine's run reports through routine.finished instead.
        if (next.routine) {
            replyOpen = false;
            return;
        }
        // A box tucked away, or a character hidden, gets the dot instead: the
        // reply opens when the character is next clicked.
        unread = tucked || !Settings.assistantShown || Settings.assistantTuck !== "";
        replyOpen = !unread;
        tucked = false;
        if (next.status === "completed") {
            celebrating = true;
            celebrateTimer.restart();
            if (Settings.assistantSpeak && !unread)
                speak();
        }
    }

    Timer {
        id: celebrateTimer
        interval: 2400
        onTriggered: root.celebrating = false
    }

    // The side lane's question: shown in the working box under the main one.
    function adoptSide(next) {
        side = next || null;
    }

    function dismissSide() {
        if (side && !sideBusy)
            side = null;
    }

    // ---- notifications (docs/assistant.md) ----------------------------------------------
    readonly property string posesDir: "/run/current-system/sw/share/cybexos/wiz/notify/"

    function notifyTurn(snapshot, moment) {
        const actions = [];
        if (moment === "finished") {
            for (const plugin of snapshot.plugins || [])
                actions.push("--action=add:" + plugin.id + "=" + I18n.tr("Add to bar"));
            if (snapshot.staged)
                actions.push("--action=review=" + I18n.tr("Review change…"));
        }
        actions.push("--action=open=" + I18n.tr("Open"));
        const failed = snapshot.status === "failed";
        const title = moment === "waiting" ? I18n.tr("Wiz needs your answer")
            : failed ? I18n.format("Wiz could not finish: %1", [snapshot.prompt || ""])
            : I18n.format("Done: %1", [snapshot.prompt || ""]);
        const card = (snapshot.approvals || [])[0];
        const body = moment === "waiting" ? (card ? card.title || "" : I18n.tr("A question is waiting for you."))
            : failed ? snapshot.error || "" : String(snapshot.text || "").replace(/\s+/g, " ").slice(0, 160);
        const pose = moment === "waiting" ? "needs-input" : failed ? "sorry" : "finished";
        turnNotice.conversation = snapshot.conversation || "";
        turnNotice.running = false;
        turnNotice.command = ["notify-send", "--app-name=Wiz", "--icon=" + posesDir + pose + ".png",
            "--urgency=" + (moment === "waiting" ? "critical" : "normal")].concat(actions, [title, body]);
        turnNotice.running = true;
    }

    Process {
        id: turnNotice
        property string conversation: ""
        stdout: SplitParser {
            onRead: line => root.noticeAction(line.trim(), turnNotice.conversation)
        }
    }

    Process {
        id: routineNotice
        property string conversation: ""
        stdout: SplitParser {
            onRead: line => root.noticeAction(line.trim(), routineNotice.conversation)
        }
    }

    function noticeAction(action, conversation) {
        if (action === "open") {
            if (turn && turn.conversation === conversation && (busy || (hasReply && unread))) {
                show(Screens.focused ? Screens.focused.name : "");
                untuck();
                if (busy)
                    tucked = false;
                else {
                    unread = false;
                    replyOpen = true;
                }
            } else if (conversation !== "") {
                if (attentionConversation === conversation)
                    attentionConversation = "";
                show(Screens.focused ? Screens.focused.name : "");
                openConversation(conversation);
            }
        } else if (action.indexOf("add:") === 0) {
            addWidget(action.slice(4));
        } else if (action === "review") {
            reviewStagedChange();
        }
    }

    function routineFinished(params) {
        const conversation = params.conversation || "";
        if (params.attention && conversation !== "")
            attentionConversation = conversation;
        if (!params.notify || Settings.assistantNotify === "never")
            return;
        const routine = params.routine || {};
        routineNotice.conversation = conversation;
        routineNotice.running = false;
        routineNotice.command = ["notify-send", "--app-name=Wiz",
            "--icon=" + posesDir + (params.attention ? "needs-input" : "finished") + ".png",
            "--action=open=" + I18n.tr("Open"),
            params.attention ? I18n.format("%1: something needs you", [routine.title || I18n.tr("Routine")])
                : I18n.format("%1: all is well", [routine.title || I18n.tr("Routine")]),
            params.summary || ""];
        routineNotice.running = true;
    }

    function adoptConversations(rows) {
        conversations = rows;
        if (historyQuery.trim() !== "")
            searchDelay.restart();
        // Gone from the history (deleted or cleared elsewhere, or pruned).
        if (continuing !== "" && !rows.some(row => row.id === continuing) && !(busy && continuing === busyConversation)) {
            continuing = "";
            thread = null;
        } else if (continuing !== "" && composing)
            loadThread();
    }

    function hello() {
        request("hello", { client: "quickshell", protocol: 1 }, (result, error) => {
            if (error || !result) {
                console.warn("assistant: hello failed:", error ? error.message : "no result");
                return;
            }
            root.helloed = true;
            root.adoptAgents(result.agents || {});
            root.speechAvailable = !!(result.speech && result.speech.available);
            root.adoptConversations(result.conversations || []);
            // A reconnect adopts the service's view of the turn; nothing is
            // replayed.
            root.side = result.side || null;
            root.queue = result.queue || null;
            root.routines = result.routines || [];
            const previous = root.turn;
            root.turn = result.turn || null;
            if (root.turn && AssistantHelpers.finished(root.turn)
                    && (!previous || previous.id !== root.turn.id))
                root.replyOpen = false;
        });
    }

    // Recheck on opening: the person may have signed in or out in a terminal.
    onComposingChanged: {
        if (composing && connected)
            refreshAuth();
        if (composing && continuing !== "" && thread === null)
            loadThread();
    }

    Socket {
        id: socket
        path: root.socketPath
        parser: SplitParser {
            onRead: line => root.receive(line)
        }
        onConnectionStateChanged: {
            root.helloed = false;
            if (connected) {
                retry.interval = 1000;
                root.hello();
            } else {
                // Requests in flight will never be answered.
                const waiting = root.pending;
                root.pending = {};
                for (const id of Object.keys(waiting))
                    waiting[id].callback(null, { code: -32000,
                        message: I18n.tr("The assistant service is not running.") });
            }
        }
    }

    // Reconnects with a gentle backoff; the service may start after the shell
    // or restart under it.
    Timer {
        id: retry
        interval: 1000
        repeat: true
        running: root.available && !socket.connected
        triggeredOnStart: true
        onTriggered: {
            socket.connected = true;
            interval = Math.min(15000, interval * 2);
        }
    }

    // ---- the `cybex agent` default ----------------------------------------------
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config"))
            + "/cybexos/defaults/agent"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.preferredAgent = text().trim()
        onLoadFailed: root.preferredAgent = ""
    }

    Binding {
        target: Dictation
        property: "assistantWatching"
        value: root.available
    }

    // The service applies "Keep conversations" whenever it lists them.
    Connections {
        target: Settings

        function onAssistantHistoryChanged() {
            if (root.connected)
                root.refreshConversations();
        }
    }

    // The elapsed time in the worker pill, and how long ago a listed
    // conversation was.
    property double now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.busy || root.listening || root.historyOpen || root.composing
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    // A transient notice fades on its own.
    Timer {
        interval: 6000
        running: root.notice !== ""
        onTriggered: root.notice = ""
    }
}
