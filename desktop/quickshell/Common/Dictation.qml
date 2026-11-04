pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsHelpers.js" as SettingsHelpers

// Dictation through Voxtype (docs/dictation.md). Voxtype writes its state for
// every control path, including the assistant's push-to-talk; watching it
// keeps the menubar honest even when this shell did not start the recording.
//
// The shell's own dictations record to a file instead of letting Voxtype type
// as it goes: the words appear in the dictation pill while you speak (from
// the `.live` file the Cybex OS patch writes) and are typed once, finished,
// when you stop, after corrections and tidy-up (scripts/dictation.py
// deliver), which also keeps them in the dictation history. Settings owns the
// speech model, languages, live text and vocabulary; changes are written to
// Voxtype's config.toml here.
Singleton {
    id: root

    // Voxtype's keys and menubar button come with the developer tooling
    // feature. Without it there is no dictation surface, though the daemon
    // still runs for the assistant's push-to-talk, which asks for its state
    // to be watched for that alone.
    // Dictation's CPU path needs AVX2 (nix/modules/default.nix); on an older
    // processor the daemon does not start, so nothing offers it.
    readonly property bool available: Settings.developerToolsConfigured && cpuSupported
    property bool cpuSupported: true
    property bool assistantWatching: false
    readonly property bool watching: available || assistantWatching
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string statePath: runtimeDir + "/voxtype/state"
    readonly property string sessionDir: runtimeDir + "/cybexos-dictation"
    readonly property string transcriptPath: sessionDir + "/transcript.txt"
    readonly property string script: Quickshell.shellDir + "/scripts/dictation.py"
    readonly property var options: Settings.modOpts.indicators

    property string state: "idle"
    // "streaming" is a recording whose words arrive while it runs.
    readonly property bool recording: state === "recording" || state === "streaming"
    readonly property bool transcribing: state === "transcribing"
    readonly property bool busy: recording || transcribing

    // This shell's own dictation: "" (none), "starting", "listening",
    // "finishing", "tidying", "typing", then briefly "done", "copied",
    // "empty" or "failed" for the pill to say how it ended.
    property string phase: ""
    readonly property bool sessionActive: phase === "starting" || phase === "listening"
        || phase === "finishing" || phase === "tidying" || phase === "typing"
    property string liveText: ""
    // The live words with the person's corrections, as they will be typed.
    readonly property string shownText: SettingsHelpers.applyDictationCorrections(liveText,
        options.dictationCorrections || [])
    // How tidy-up runs for this dictation ("basic" or "polish"), and whether
    // the original words were asked for instead.
    property string tidyMode: ""
    property bool originalRequested: false
    // How the last dictation ended: {status, text, original, tidied, tidy,
    // polishFailed, words, app, id} from scripts/dictation.py deliver.
    property var lastResult: ({})
    // Why a dictation failed: microphone, timeout, typing or transcription.
    property string failure: ""
    property bool sawRecording: false
    // A stop pressed before Voxtype began recording is sent once it has.
    property bool pendingStop: false

    // The downloadable models (scripts/dictation.py) and their download:
    // "enhanced" is Whisper turbo (Settings: Accurate), "parakeet" Parakeet
    // v3 (Fast & accurate).
    property bool enhancedInstalled: false
    property bool parakeetInstalled: false
    property bool statusKnown: false
    readonly property real enhancedSize: 874188075
    readonly property real parakeetSize: 670480039
    property string download: ""          // "", "running", "failed"
    property string downloadModel: ""     // "enhanced" or "parakeet"
    property int downloadProgress: 0
    property string downloadError: ""
    // Parakeet knows 25 European languages; for others, Whisper.
    readonly property bool parakeetFits: SettingsHelpers.parakeetSupports(
        options.dictationPrimaryLanguage, options.dictationSecondaryLanguage)
    // What the first-use offer and Settings recommend for these languages.
    readonly property string recommendedModel: parakeetFits ? "parakeet" : "large-v3-turbo"
    readonly property bool recommendedInstalled: recommendedModel === "parakeet" ? parakeetInstalled : enhancedInstalled
    readonly property real recommendedSize: recommendedModel === "parakeet" ? parakeetSize : enhancedSize
    // The model Voxtype is given: a choice the languages no longer fit, or
    // whose download is gone, falls back to one that works.
    readonly property string effectiveModel: {
        const chosen = options.dictationModel;
        if (chosen === "parakeet" && parakeetInstalled && parakeetFits)
            return "parakeet";
        if (chosen === "large-v3-turbo" && enhancedInstalled)
            return "large-v3-turbo";
        if (chosen === "parakeet" && enhancedInstalled)
            return "large-v3-turbo";
        return "base";
    }

    // ---- history -------------------------------------------------------------------------
    property bool historyOpen: false
    property var historyEntries: []
    property var suggestions: []
    property int weekWords: 0
    property bool historyLoaded: false
    // Suggestions the person has not answered and has no correction for yet.
    readonly property var openSuggestions: suggestions.filter(item =>
        !(options.dictationCorrections || []).some(rule =>
            String(rule.heard).toLowerCase() === String(item.heard).toLowerCase()))
    // Shown once, after the first dictation that typed words.
    property bool offerShown: false
    property string applyError: ""
    // The last configuration the daemon was given: {changed, restarted, model}.
    property var applied: ({})

    // ---- control ---------------------------------------------------------------
    function toggle() {
        if (phase === "starting" || phase === "listening" || (recording && !sessionActive))
            stop();
        else if (phase === "finishing" || (transcribing && !sessionActive))
            cancel();
        else if (phase === "tidying")
            typeOriginal();
        else if (!busy)
            start();
    }

    function start() {
        if (busy || sessionActive)
            return;
        endHold.stop();
        // The pill takes the offer's place; a download carries on, and
        // Settings shows its progress.
        offerShown = false;
        phase = "starting";
        liveText = "";
        tidyMode = "";
        originalRequested = false;
        lastResult = ({});
        failure = "";
        sawRecording = false;
        pendingStop = false;
        // Removing the last session's files first is what makes the next
        // reads this recording's words.
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p -m 0700 "$1" && rm -f -- "$2" "$2.done" "$2.live" "$2.wav" "$2.original" && exec voxtype record start --file="$2"',
            "sh", sessionDir, transcriptPath]);
        settle.restart();
        startGuard.restart();
        livePoll.start();
    }

    function stop() {
        if (phase === "starting") {
            phase = "finishing";
            pendingStop = true;
            return;
        }
        if (phase === "listening")
            phase = "finishing";
        Quickshell.execDetached(["voxtype", "record", "stop"]);
        settle.restart();
        if (phase === "finishing")
            awaitResult();
    }

    function cancel() {
        Quickshell.execDetached(["voxtype", "record", "cancel"]);
        settle.restart();
        if (sessionActive)
            finish("");
    }

    function refresh() {
        stateView.reload();
    }

    // While tidy-up runs: type the words as heard instead. The helper reads
    // this before typing; once typing has begun it no longer applies.
    function typeOriginal() {
        if (phase !== "tidying" || originalRequested)
            return;
        originalRequested = true;
        Quickshell.execDetached(["touch", transcriptPath + ".original"]);
    }

    // After a tidied dictation: the words as heard, for the clipboard.
    function copyOriginal() {
        const text = String(lastResult.original || "");
        if (text !== "")
            Quickshell.execDetached(["wl-copy", "--", text]);
        endHold.stop();
        phase = "";
        liveText = "";
    }

    function run(command) {
        Quickshell.execDetached(command);
        settle.restart();
    }

    function awaitResult() {
        startGuard.stop();
        resultDeadline.restart();
        resultPoll.start();
    }

    // The pill keeps the ending on screen for a moment, then goes.
    function finish(outcome) {
        startGuard.stop();
        resultPoll.stop();
        resultDeadline.stop();
        livePoll.stop();
        phase = outcome;
        if (outcome === "")
            liveText = "";
        else
            endHold.restart();
    }

    function onResult(text) {
        let outcome = {};
        try {
            outcome = JSON.parse(text);
        } catch (error) {
            return;
        }
        resultPoll.stop();
        resultDeadline.stop();
        if (outcome.status === "ok") {
            phase = "typing";
            livePoll.stop();
            deliverProc.command = ["python3", root.script, "deliver", root.transcriptPath,
                "--options", JSON.stringify(deliveryOptions())];
            deliverProc.running = true;
        } else if (outcome.status === "empty") {
            finish("empty");
        } else {
            failure = "transcription";
            finish("failed");
        }
    }

    // What the helper needs to finish a dictation, from Settings.
    function deliveryOptions() {
        return {
            corrections: options.dictationCorrections || [],
            tidy: options.dictationTidy,
            agent: options.dictationPolishAgent,
            skipCode: !options.dictationTidyCode,
            history: options.dictationHistory,
            keepAudio: options.dictationKeepAudio,
            languages: languages
        };
    }

    // ---- model ---------------------------------------------------------------------
    function refreshStatus() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function downloadModelNamed(name) {
        if (downloadProc.running)
            return;
        downloadModel = name;
        download = "running";
        downloadProgress = 0;
        downloadError = "";
        downloadProc.command = ["python3", root.script, "download", name];
        downloadProc.running = true;
    }

    function downloadEnhanced() {
        downloadModelNamed("enhanced");
    }

    // The model the first-use offer recommends for the languages chosen.
    function downloadRecommended() {
        if (recommendedInstalled)
            Settings.setModuleOption("indicators", "dictationModel", recommendedModel);
        else
            downloadModelNamed(recommendedModel === "parakeet" ? "parakeet" : "enhanced");
    }

    function cancelDownload() {
        if (downloadProc.running) {
            download = "";
            downloadProc.running = false;
        }
    }

    // Back to the built-in model first, so the daemon never points at a
    // missing file; it keeps the deleted model only until it restarts.
    function removeModel(name) {
        const setting = name === "parakeet" ? "parakeet" : "large-v3-turbo";
        if (options.dictationModel === setting)
            Settings.setModuleOption("indicators", "dictationModel", "base");
        removeProc.command = ["python3", root.script, "remove", name];
        removeProc.running = true;
    }

    function removeEnhanced() {
        removeModel("enhanced");
    }

    function useModel(value) {
        if (value === "large-v3-turbo" && !enhancedInstalled) {
            downloadModelNamed("enhanced");
            return;
        }
        if (value === "parakeet" && !parakeetInstalled) {
            downloadModelNamed("parakeet");
            return;
        }
        Settings.setModuleOption("indicators", "dictationModel", value);
    }

    function dismissOffer() {
        offerShown = false;
    }

    function showOffer() {
        offerShown = true;
        if (!options.dictationPrompted)
            Settings.setModuleOption("indicators", "dictationPrompted", true);
    }

    function setSecondaryLanguage(code) {
        Settings.setModuleOption("indicators", "dictationSecondaryLanguage", code);
    }

    readonly property string languages: {
        const primary = options.dictationPrimaryLanguage;
        const secondary = options.dictationSecondaryLanguage;
        return secondary === "off" || secondary === primary ? primary : primary + "," + secondary;
    }
    readonly property string applyKey: JSON.stringify([effectiveModel, languages,
        options.dictationLiveText, options.dictationVocabulary])
    onApplyKeyChanged: applyTimer.restart()

    // ---- vocabulary and corrections ---------------------------------------------------
    function addTerm(term) {
        const terms = SettingsHelpers.dictationTerms(options.dictationVocabulary);
        terms.push(String(term || ""));
        Settings.setModuleOption("indicators", "dictationVocabulary", SettingsHelpers.dictationTermsLine(terms));
    }

    function removeTerm(term) {
        const terms = SettingsHelpers.dictationTerms(options.dictationVocabulary).filter(item => item !== term);
        Settings.setModuleOption("indicators", "dictationVocabulary", SettingsHelpers.dictationTermsLine(terms));
    }

    function addCorrection(heard, write) {
        const rules = (options.dictationCorrections || []).filter(rule =>
            String(rule.heard).toLowerCase() !== String(heard).trim().toLowerCase());
        rules.push({heard: String(heard).trim(), write: String(write).trim()});
        Settings.setModuleOption("indicators", "dictationCorrections", SettingsHelpers.dictationCorrectionsIn(rules, []));
    }

    function removeCorrection(heard) {
        Settings.setModuleOption("indicators", "dictationCorrections",
            (options.dictationCorrections || []).filter(rule => rule.heard !== heard));
    }

    // A suggestion from history edits: taken as a correction, or declined;
    // either way it is not suggested again.
    function acceptSuggestion(item) {
        addCorrection(item.heard, item.write);
        historyCommand(["forget", item.heard, item.write]);
    }

    function declineSuggestion(item) {
        historyCommand(["forget", item.heard, item.write]);
    }

    // ---- history ------------------------------------------------------------------------
    function openHistory() {
        if (!available)
            return;
        offerShown = false;
        historyOpen = true;
        refreshHistory();
    }

    function closeHistory() {
        historyOpen = false;
    }

    function toggleHistory() {
        if (historyOpen)
            closeHistory();
        else
            openHistory();
    }

    function refreshHistory() {
        historyCommand(["list"]);
    }

    // Commands run one at a time, in order; each refreshes the list after.
    property var historyQueue: []
    function historyCommand(args) {
        historyQueue = historyQueue.concat([args]);
        runHistoryQueue();
    }

    function runHistoryQueue() {
        if (historyProc.running || historyQueue.length === 0)
            return;
        const next = historyQueue[0];
        historyQueue = historyQueue.slice(1);
        historyProc.action = next[0];
        historyProc.command = ["python3", root.script, "history"].concat(next)
            .concat(["--retention", options.dictationHistory]);
        historyProc.running = true;
    }

    // Typing again goes to the window under the history, once it has closed.
    function typeEntry(id) {
        closeHistory();
        historyCommand(["type", id]);
    }

    function copyEntry(id) {
        historyCommand(["copy", id]);
    }

    function deleteEntry(id) {
        historyCommand(["delete", id]);
    }

    function editEntry(id, text) {
        historyCommand(["edit", id, text]);
    }

    function playEntry(id) {
        historyCommand(["play", id]);
    }

    function retranscribeEntry(id) {
        historyCommand(["retranscribe", id]);
    }

    function clearHistory() {
        historyCommand(["clear"]);
    }

    // Settings → Assistant → Dictation.
    function openSettings() {
        Settings.showPanel("dictation", Screens.focused ? Screens.focused.name : "");
    }

    function statusJson() {
        return JSON.stringify({available: available, state: state, phase: phase,
            liveText: liveText, shownText: shownText, failure: failure,
            enhancedInstalled: enhancedInstalled, parakeetInstalled: parakeetInstalled,
            download: download, downloadModel: downloadModel, downloadProgress: downloadProgress,
            downloadError: downloadError, offerShown: offerShown, applyError: applyError,
            applied: applied, applying: applyProc.running || applyTimer.running,
            model: options.dictationModel, effectiveModel: effectiveModel,
            recommendedModel: recommendedModel, languages: languages, cpuSupported: cpuSupported,
            liveTextEnabled: options.dictationLiveText, tidy: options.dictationTidy,
            tidyMode: tidyMode, lastResult: lastResult, historyOpen: historyOpen,
            historyCount: historyEntries.length, suggestions: openSuggestions});
    }

    Component.onCompleted: refreshStatus()

    // ---- Voxtype's state --------------------------------------------------------------
    // Whether the last read found no state file. The view also watches the
    // file's directory, so while the file exists a creation or an atomic
    // replace is seen without polling; only a missing file may have taken
    // its directory with it (the daemon not started yet), and a missing
    // directory cannot be watched.
    property bool stateMissing: false

    onStateChanged: {
        if (!sessionActive)
            return;
        // From `state` itself: this handler can run before the `recording`
        // binding has seen the change.
        if (state === "recording" || state === "streaming") {
            sawRecording = true;
            startGuard.stop();
            if (phase === "starting")
                phase = "listening";
            if (pendingStop) {
                pendingStop = false;
                Quickshell.execDetached(["voxtype", "record", "stop"]);
                awaitResult();
            }
        } else if (sawRecording && (phase === "starting" || phase === "listening")) {
            // Voxtype ended it itself (its length limit, or no speech).
            phase = "finishing";
            awaitResult();
        }
    }

    FileView {
        id: stateView
        path: root.watching ? root.statePath : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.stateMissing = false;
            const value = text().trim();
            root.state = ["idle", "recording", "streaming", "transcribing"].indexOf(value) !== -1
                ? value : "idle";
        }
        onLoadFailed: {
            root.stateMissing = true;
            root.state = "idle";
        }
    }

    // inotify covers normal transitions; this bounded replay covers a daemon
    // replacing the state file between watches after a bar-originated action.
    Timer {
        id: settle
        interval: 250
        repeat: true
        property int ticks: 0
        onTriggered: {
            root.refresh();
            if (++ticks >= 20)
                stop();
        }
        onRunningChanged: {
            if (running)
                ticks = 0;
        }
    }

    // Each reload rebuilds the view's inotify watches, so the poll runs only
    // while there is no file to watch, and not while the session is idle.
    Timer {
        interval: 3000
        running: root.watching && root.stateMissing && !Activity.idle
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: Activity

        function onResumed() {
            if (root.watching && root.stateMissing)
                root.refresh();
        }
    }

    // ---- this shell's session -----------------------------------------------------------
    // A start that never became a recording (no daemon, no microphone).
    Timer {
        id: startGuard
        interval: 6000
        onTriggered: {
            if (root.pendingStop) {
                root.pendingStop = false;
                root.finish("");
            } else if (root.phase === "starting") {
                root.failure = "microphone";
                root.finish("failed");
            }
        }
    }

    // The live words: watched, with a light poll in case the file appeared
    // before its directory was watched. Only while a session runs.
    FileView {
        id: liveView
        path: root.sessionActive ? root.transcriptPath + ".live" : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root.phase === "listening" || root.phase === "finishing" || root.phase === "starting")
                root.liveText = text().trim();
        }
    }

    Timer {
        id: livePoll
        interval: 300
        repeat: true
        onTriggered: liveView.reload()
    }

    // Voxtype publishes the outcome (`.done`) after the transcript itself.
    FileView {
        id: resultView
        path: root.transcriptPath + ".done"
        printErrors: false
        onLoaded: root.onResult(text())
    }

    Timer {
        id: resultPoll
        interval: 150
        repeat: true
        onTriggered: resultView.reload()
    }

    Timer {
        id: resultDeadline
        interval: 120000
        onTriggered: {
            root.failure = "timeout";
            root.finish("failed");
        }
    }

    // A tidied dictation stays a little longer, for Copy original; a failed
    // one for Open history.
    Timer {
        id: endHold
        interval: root.phase === "failed" && root.lastResult.id
            || root.phase === "done" && root.lastResult.tidied ? 3500 : 1800
        onTriggered: {
            if (!root.sessionActive) {
                root.phase = "";
                root.liveText = "";
            }
        }
    }

    // Corrections, tidy-up, typing and history (scripts/dictation.py deliver).
    Process {
        id: deliverProc
        stdout: SplitParser {
            onRead: line => {
                let event = {};
                try {
                    event = JSON.parse(line);
                } catch (error) {
                    return;
                }
                if (event.event === "tidying") {
                    root.tidyMode = event.mode || "basic";
                    root.phase = "tidying";
                } else if (event.event === "typing") {
                    root.phase = "typing";
                    if (typeof event.text === "string" && event.text !== "")
                        root.liveText = event.text;
                } else if (event.event === "result") {
                    root.lastResult = event;
                }
            }
        }
        onExited: code => {
            if (root.historyOpen || root.historyLoaded)
                root.refreshHistory();
            if (code === 0 || code === 2) {
                root.finish(code === 0 ? "done" : "copied");
                // The first dictation that typed words is the moment to
                // offer better recognition, once (docs/dictation.md).
                if (!root.options.dictationPrompted && root.statusKnown
                        && root.options.dictationModel === "base" && !root.recommendedInstalled)
                    root.showOffer();
            } else if (code === 3) {
                root.finish("empty");
            } else {
                root.failure = "typing";
                root.finish("failed");
            }
        }
    }

    Process {
        id: historyProc
        property string action: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let result = {};
                try {
                    result = JSON.parse(text);
                } catch (error) {
                    return;
                }
                if (historyProc.action === "list") {
                    root.historyEntries = result.entries || [];
                    root.suggestions = result.suggestions || [];
                    root.weekWords = result.weekWords || 0;
                    root.historyLoaded = true;
                } else if (result.suggestions) {
                    root.suggestions = result.suggestions;
                }
            }
        }
        onExited: {
            if (action !== "list" && !root.historyQueue.some(args => args[0] === "list"))
                root.historyQueue = root.historyQueue.concat([["list"]]);
            root.runHistoryQueue();
        }
    }

    // ---- model and configuration --------------------------------------------------------
    Process {
        id: statusProc
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text);
                    root.enhancedInstalled = status.installed === true;
                    root.parakeetInstalled = !!(status.models && status.models.parakeet
                        && status.models.parakeet.installed === true);
                    root.cpuSupported = status.cpu !== false;
                    root.statusKnown = true;
                } catch (error) {
                    root.statusKnown = false;
                }
            }
        }
    }

    Process {
        id: downloadProc
        property string result: ""
        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (text.indexOf("progress ") === 0) {
                    const value = parseInt(text.slice(9), 10);
                    if (value >= 0 && value <= 100)
                        root.downloadProgress = value;
                } else if (text === "done" || text.indexOf("failed ") === 0) {
                    downloadProc.result = text;
                }
            }
        }
        onRunningChanged: {
            if (running) {
                result = "";
                return;
            }
            if (result === "done") {
                root.download = "";
                if (root.downloadModel === "parakeet")
                    root.parakeetInstalled = true;
                else
                    root.enhancedInstalled = true;
                Settings.setModuleOption("indicators", "dictationModel",
                    root.downloadModel === "parakeet" ? "parakeet" : "large-v3-turbo");
            } else if (root.download === "running") {
                root.download = "failed";
                root.downloadError = result.indexOf("failed ") === 0 ? result.slice(7) : "network";
            }
            root.refreshStatus();
        }
    }

    Process {
        id: removeProc
        onExited: root.refreshStatus()
    }

    // Settings → Voxtype. Waits for a running dictation: the daemon restarts
    // when a key changes, which would end it.
    Timer {
        id: applyTimer
        interval: 700
        onTriggered: {
            if (!Settings.loaded || root.busy || root.sessionActive || applyProc.running) {
                restart();
                return;
            }
            applyProc.command = ["python3", root.script, "apply",
                "--model", root.effectiveModel === "parakeet" ? "parakeet"
                    : root.effectiveModel === "large-v3-turbo" ? "enhanced" : "base",
                "--languages", root.languages,
                "--live", root.options.dictationLiveText ? "1" : "0",
                "--vocabulary", root.options.dictationVocabulary];
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.applyError = result.error || "";
                    if (!result.error)
                        root.applied = result;
                } catch (error) {
                    root.applyError = "";
                }
            }
        }
    }

    Connections {
        target: Settings

        function onLoadedChanged() {
            if (Settings.loaded)
                applyTimer.restart();
        }
    }
}
