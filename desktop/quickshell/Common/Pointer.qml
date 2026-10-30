pragma Singleton
import QtQuick
import Quickshell
import "PointerHelpers.js" as PointerHelpers

// The pointer (Settings -> Appearance -> Pointer, docs/settings.md): the
// themes on this computer and in the catalogue, their downloads, and giving
// the desktop the one the settings ask for. scripts/pointer.py lists,
// downloads from the binary cache, removes and applies; this keeps the list
// and decides what to apply and when.
//
// Settings holds the choice (pointerTheme, pointerSize, pointerLeftHanded).
// A chosen theme that is no longer installed falls back to the
// installation's own rather than leave Hyprland looking for it. The session
// starts with the pointer the last apply recorded (cybexos-session), so at
// start-up only a difference is applied, such as a shell.json edited while
// signed out. Hiding the pointer is Hyprland configuration and stays with
// Settings.applyPointerHiding().
Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/scripts/pointer.py"
    property var themes: []
    property var installationDefault: PointerHelpers.FALLBACK_DEFAULT
    // Whether this computer can download catalogue themes: a source-tree run
    // has no machine record of their store paths.
    property bool downloadsAvailable: false
    property bool loaded: false
    property string listError: ""

    // One download or removal at a time: the theme it is for, then its
    // failure, kept for the theme until the next attempt.
    property string downloading: ""
    property string removing: ""
    property string failedTheme: ""
    property string failure: ""
    property string failureDetail: ""
    // A download picks its theme once it arrives, unless another was picked
    // in the meantime.
    property string pickAfterDownload: ""

    property string applyError: ""
    // What the desktop has: the session's own environment until the first
    // apply. The marker records whether the next login was told.
    property string applied: (Quickshell.env("XCURSOR_THEME") || "") + " "
        + (Quickshell.env("XCURSOR_SIZE") || "")
    property bool startChecked: false

    readonly property var resolved: {
        return PointerHelpers.resolve({
            pointerTheme: Settings.pointerTheme,
            pointerSize: Settings.pointerSize,
            pointerLeftHanded: Settings.pointerLeftHanded
        }, themes, installationDefault);
    }
    readonly property string wanted: resolved.theme + " " + resolved.size
    readonly property string wantedRecord: wanted + (resolved.explicit ? " explicit" : "")
    readonly property bool busy: downloading !== "" || removing !== ""

    function entry(id) {
        return PointerHelpers.find(themes, id);
    }

    function refresh() {
        if (listRequest.running) {
            listRequest.again = true;
            return;
        }
        listRequest.running = true;
    }

    // A gallery tile's click: an installed theme is chosen at once, one that
    // is not is downloaded first.
    function pick(id) {
        const theme = entry(id);
        if (!theme)
            return;
        if (theme.installed) {
            pickAfterDownload = "";
            failedTheme = "";
            failure = "";
            failureDetail = "";
            Settings.set("pointerTheme", id);
        } else if (theme.downloadable) {
            download(id, true);
        }
    }

    function download(id, pickIt) {
        if (busy || !entry(id))
            return false;
        downloading = id;
        failedTheme = "";
        failure = "";
        failureDetail = "";
        pickAfterDownload = pickIt ? id : "";
        actionRequest.command = ["python3", "-B", root.script, "download", id];
        actionRequest.running = true;
        return true;
    }

    // The theme in use is not removed: the desktop would lose its pointer.
    function remove(id) {
        const theme = entry(id);
        if (busy || !theme || !theme.removable || inUse(id))
            return false;
        removing = id;
        failedTheme = "";
        failure = "";
        failureDetail = "";
        actionRequest.command = ["python3", "-B", root.script, "remove", id];
        actionRequest.running = true;
        return true;
    }

    // Whether a download serves the pointer in use, including its sibling
    // themes from the same package.
    function inUse(id) {
        return PointerHelpers.inUse(themes, resolved.chosen, id);
    }

    // `pointer use`: what a tile's click does. "ok" once the theme is picked
    // or its download has started, otherwise "error: <reason>".
    function use(id) {
        const theme = entry(id);
        if (!loaded)
            return "error: the pointer list is not ready";
        if (!theme)
            return "error: no pointer theme " + id;
        if (!theme.installed && !theme.downloadable)
            return "error: " + id + " is not installed and cannot be downloaded here";
        if (busy)
            return "error: another download or removal is running";
        pick(id);
        return "ok";
    }

    function status() {
        return JSON.stringify({loaded: loaded, downloadsAvailable: downloadsAvailable,
            applied: applied, wanted: wantedRecord, resolved: {chosen: resolved.chosen,
                theme: resolved.theme, size: resolved.size, explicit: resolved.explicit,
                missing: resolved.missing},
            downloading: downloading, removing: removing, failure: failure,
            failureDetail: failureDetail, applyError: applyError, listError: listError,
            themes: themes.map(theme => ({id: theme.id, source: theme.source,
                installed: theme.installed, downloadable: theme.downloadable,
                removable: theme.removable}))});
    }

    function parse(body) {
        try {
            return JSON.parse(body);
        } catch (e) {
            return null;
        }
    }

    function errorOf(code, body, stderr, fallback) {
        const reply = parse(body);
        if (reply && typeof reply.error === "string" && reply.error !== "")
            return reply.error;
        const lines = String(stderr || "").trim().split("\n");
        return lines[lines.length - 1] || fallback + " (exit " + code + ")";
    }

    function apply() {
        if (!loaded || !Settings.loaded)
            return;
        if (!startChecked) {
            // The session started with the pointer the last apply recorded;
            // only a difference needs applying now.
            startChecked = true;
            if (applied === wanted) {
                applied = wantedRecord;
                return;
            }
        }
        if (wantedRecord !== applied)
            applyTimer.restart();
    }

    onWantedRecordChanged: apply()
    onLoadedChanged: apply()
    Connections {
        target: Settings
        function onLoadedChanged() {
            root.apply();
        }
    }

    // A size picked in passing or several tiles clicked in a row apply once.
    Timer {
        id: applyTimer
        interval: 250
        onTriggered: {
            if (applyRequest.running) {
                applyRequest.again = true;
                return;
            }
            const resolved = root.resolved;
            applyRequest.record = root.wantedRecord;
            applyRequest.command = ["python3", "-B", root.script, "apply", resolved.theme,
                String(resolved.size)].concat(resolved.explicit ? ["--explicit"] : []);
            applyRequest.running = true;
        }
    }

    Component.onCompleted: refresh()

    CommandRequest {
        id: listRequest
        property bool again: false
        property string pickWhenListed: ""
        command: ["python3", "-B", root.script, "list"]
        timeoutMs: 60000
        onCompleted: (code, body, stderr) => {
            const list = code === 0 ? PointerHelpers.listIn(root.parse(body)) : null;
            if (list) {
                root.themes = list.themes;
                root.downloadsAvailable = list.downloads;
                root.installationDefault = list.installationDefault;
                root.listError = "";
                root.loaded = true;
            } else {
                root.listError = root.errorOf(code, body, stderr, "Could not list pointers");
                console.warn("pointer:", root.listError);
            }
            if (again) {
                again = false;
                running = true;
            }
        }
    }

    CommandRequest {
        id: actionRequest
        // Substituting a large theme over a slow connection takes a while;
        // the helper gives up first and says so.
        timeoutMs: 960000
        onCompleted: (code, body, stderr) => {
            const id = root.downloading || root.removing;
            const downloaded = root.downloading !== "";
            const reply = root.parse(body);
            if (code !== 0 || !reply || reply.success !== true) {
                root.failedTheme = id;
                root.failure = root.errorOf(code, body, stderr,
                    downloaded ? "Could not download the pointer" : "Could not remove the pointer");
                root.failureDetail = reply && typeof reply.detail === "string" ? reply.detail.slice(0, 300) : "";
                root.pickAfterDownload = "";
            }
            root.downloading = "";
            root.removing = "";
            listRequest.pickWhenListed = root.pickAfterDownload;
            root.pickAfterDownload = "";
            root.refresh();
        }
    }

    // The list after a download says whether the theme arrived; only then is
    // it picked. A list that was already running when the download ended
    // is followed by another, which decides.
    Connections {
        target: listRequest
        function onCompleted() {
            if (listRequest.running)
                return;
            const id = listRequest.pickWhenListed;
            listRequest.pickWhenListed = "";
            const theme = id === "" ? null : root.entry(id);
            if (theme && theme.installed)
                Settings.set("pointerTheme", id);
        }
    }

    CommandRequest {
        id: applyRequest
        property bool again: false
        property string record: ""
        timeoutMs: 60000
        onCompleted: (code, body, stderr) => {
            const reply = root.parse(body);
            if (code === 0 && reply && reply.success === true) {
                root.applyError = "";
            } else {
                root.applyError = root.errorOf(code, body, stderr, "Could not apply the pointer");
                console.warn("pointer:", root.applyError);
            }
            // A failure is not retried with the same choice; the next change
            // runs every step again.
            root.applied = record;
            if (again || root.wantedRecord !== root.applied) {
                again = false;
                applyTimer.restart();
            }
        }
    }
}
