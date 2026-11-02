pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Dictation through Voxtype (docs/dictation.md). Voxtype writes its state for
// every control path, including the assistant's push-to-talk; watching it
// keeps the menubar honest even when this shell did not start the recording.
//
// The shell's own dictations record to a file instead of letting Voxtype type
// as it goes: the words appear in the dictation pill while you speak (from
// the `.live` file the Cybex OS patch writes) and are typed once, finished,
// when you stop. Settings owns the speech model, languages, live text and
// vocabulary; changes are written to Voxtype's config.toml here.
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
    // "finishing", "typing", then briefly "done", "copied", "empty" or
    // "failed" for the pill to say how it ended.
    property string phase: ""
    readonly property bool sessionActive: phase === "starting" || phase === "listening"
        || phase === "finishing" || phase === "typing"
    property string liveText: ""
    // Why a dictation failed: microphone, timeout, typing or transcription.
    property string failure: ""
    property bool sawRecording: false
    // A stop pressed before Voxtype began recording is sent once it has.
    property bool pendingStop: false

    // The enhanced model (scripts/dictation.py) and its download.
    property bool enhancedInstalled: false
    property bool statusKnown: false
    readonly property real enhancedSize: 874188075
    property string download: ""          // "", "running", "failed"
    property int downloadProgress: 0
    property string downloadError: ""
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
        failure = "";
        sawRecording = false;
        pendingStop = false;
        // Removing the last session's files first is what makes the next
        // reads this recording's words.
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p -m 0700 "$1" && rm -f -- "$2" "$2.done" "$2.live" && exec voxtype record start --file="$2"',
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
            typeProc.running = true;
        } else if (outcome.status === "empty") {
            finish("empty");
        } else {
            failure = "transcription";
            finish("failed");
        }
    }

    // ---- model ---------------------------------------------------------------------
    function refreshStatus() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function downloadEnhanced() {
        if (downloadProc.running)
            return;
        download = "running";
        downloadProgress = 0;
        downloadError = "";
        downloadProc.running = true;
    }

    function cancelDownload() {
        if (downloadProc.running) {
            download = "";
            downloadProc.running = false;
        }
    }

    // Back to the built-in model first, so the daemon never points at a
    // missing file; it keeps the deleted model only until it restarts.
    function removeEnhanced() {
        Settings.setModuleOption("indicators", "dictationModel", "base");
        removeProc.running = true;
    }

    function useModel(value) {
        if (value === "large-v3-turbo" && !enhancedInstalled) {
            downloadEnhanced();
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
    readonly property string applyKey: JSON.stringify([options.dictationModel, languages,
        options.dictationLiveText, options.dictationVocabulary])
    onApplyKeyChanged: applyTimer.restart()

    function statusJson() {
        return JSON.stringify({available: available, state: state, phase: phase,
            liveText: liveText, failure: failure, enhancedInstalled: enhancedInstalled,
            download: download, downloadProgress: downloadProgress,
            downloadError: downloadError, offerShown: offerShown, applyError: applyError,
            applied: applied, applying: applyProc.running || applyTimer.running,
            model: options.dictationModel, languages: languages, cpuSupported: cpuSupported,
            liveTextEnabled: options.dictationLiveText});
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

    Timer {
        id: endHold
        interval: 1800
        onTriggered: {
            if (!root.sessionActive) {
                root.phase = "";
                root.liveText = "";
            }
        }
    }

    Process {
        id: typeProc
        command: ["python3", root.script, "type", root.transcriptPath]
        onExited: code => {
            if (code === 0 || code === 2) {
                root.finish(code === 0 ? "done" : "copied");
                // The first dictation that typed words is the moment to
                // offer better recognition, once (docs/dictation.md).
                if (!root.options.dictationPrompted && root.statusKnown
                        && root.options.dictationModel === "base" && !root.enhancedInstalled)
                    root.showOffer();
            } else if (code === 3) {
                root.finish("empty");
            } else {
                root.failure = "typing";
                root.finish("failed");
            }
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
        command: ["python3", root.script, "download"]
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
                root.enhancedInstalled = true;
                Settings.setModuleOption("indicators", "dictationModel", "large-v3-turbo");
            } else if (root.download === "running") {
                root.download = "failed";
                root.downloadError = result.indexOf("failed ") === 0 ? result.slice(7) : "network";
            }
            root.refreshStatus();
        }
    }

    Process {
        id: removeProc
        command: ["python3", root.script, "remove"]
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
                "--model", root.options.dictationModel === "large-v3-turbo" ? "enhanced" : "base",
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
