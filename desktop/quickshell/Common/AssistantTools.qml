pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "SettingsHelpers.js" as SettingsHelpers
import "SettingsSearchData.js" as SearchData
import "WallhavenHelpers.js" as WallhavenHelpers
import "WindowCommands.js" as WindowCommands

// The desktop tools only the shell can carry out (docs/assistant.md). The
// assistant service decides whether a call may run, asks the person when it
// should and records what changed; it then sends the call here as
// `desktop.request` (cybexos_assistant/desktop.py lists the tools). Every
// answer goes back through `respond(result)` or `fail(message)`.
//
// Preferences go through Settings.set, so a value is checked exactly as the
// Settings window checks it, and is written at once so the service sees the
// change it records for Undo. The assistant's own settings are not offered.
Singleton {
    id: root

    // Keys the agent may not change: the assistant's own behaviour and its
    // tool permissions belong to the person.
    function blockedKey(key) {
        return /^assistant/.test(key);
    }

    function known(key) {
        return Object.prototype.hasOwnProperty.call(SettingsHelpers.defaults(), key);
    }

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function typeOf(value) {
        return (Array.isArray(value) || value instanceof Array) ? "list" : value === null ? "none" : typeof value;
    }

    function handle(tool, args, respond, fail) {
        try {
            switch (tool) {
            case "desktop_status": return respond(status());
            case "settings_search": return respond(search(String(args.query || "")));
            case "settings_get": return respond(read(args.keys));
            case "settings_set": return setValue(args.key, args.value, respond, fail);
            case "wallpaper_set": return setWallpaper(args, respond, fail);
            case "app_open": return openApp(String(args.app || ""), respond, fail);
            case "window_info": return respond(windowInfo(args.address));
            case "window_focus": return windowCommand(args.address, WindowCommands.focusWindow(args.address),
                "focused", respond, fail);
            case "window_close": return windowCommand(args.address, WindowCommands.closeWindow(args.address),
                "closed", respond, fail);
            case "window_move": return windowCommand(args.address,
                WindowCommands.moveWindow(args.address, Number(args.workspace)), "moved", respond, fail);
            case "workspace_switch": {
                const command = WindowCommands.focusWorkspace(Number(args.workspace));
                if (command === "")
                    return fail(I18n.tr("That is not a workspace number."));
                Hyprland.dispatch(command);
                return respond({ workspace: Number(args.workspace) });
            }
            default:
                return fail("The desktop does not know " + tool + ".");
            }
        } catch (error) {
            return fail(String(error && error.message ? error.message : error));
        }
    }

    // ---- looking ---------------------------------------------------------------
    function toplevelRow(toplevel) {
        const ipc = toplevel.lastIpcObject || {};
        return {
            address: "0x" + WindowCommands.bareAddress(toplevel.address),
            app: ipc.class || toplevel.wayland?.appId || "",
            title: toplevel.title || "",
            workspace: toplevel.workspace ? toplevel.workspace.id : (ipc.workspace ? ipc.workspace.id : null),
            floating: !!ipc.floating
        };
    }

    function status() {
        const active = Hyprland.activeToplevel;
        return {
            focused: active ? toplevelRow(active) : null,
            windows: Hyprland.toplevels.values.map(toplevelRow),
            workspaces: Hyprland.workspaces.values.filter(ws => ws.id > 0).map(ws => ({
                id: ws.id, name: ws.name, display: ws.monitor ? ws.monitor.name : "",
                focused: Hyprland.focusedWorkspace === ws })),
            displays: Hyprland.monitors.values.map(monitor => ({
                name: monitor.name, width: monitor.width, height: monitor.height, scale: monitor.scale,
                focused: Hyprland.focusedMonitor === monitor,
                workspace: monitor.activeWorkspace ? monitor.activeWorkspace.id : null })),
            theme: { mode: Settings.themeMode, accent: Settings.accent },
            wallpaper: { file: Settings.wall, folder: Wallpaper.dir }
        };
    }

    function search(query) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word !== "");
        const defaults = SettingsHelpers.defaults();
        const rows = SearchData.ROWS.filter(row => row.key !== "" && !blockedKey(row.key) && known(row.key))
            .map(row => {
                const haystack = (row.label + " " + row.group + " " + row.pageLabel + " " + row.terms + " "
                    + row.key).toLowerCase();
                return { row: row, score: words.filter(word => haystack.indexOf(word) !== -1).length };
            })
            .filter(entry => words.length === 0 || entry.score > 0)
            .sort((a, b) => b.score - a.score)
            .slice(0, 12);
        return { results: rows.map(entry => ({
            key: entry.row.key, label: entry.row.label, page: entry.row.pageLabel, group: entry.row.group,
            current: Settings[entry.row.key], default: defaults[entry.row.key],
            type: typeOf(defaults[entry.row.key]) })) };
    }

    function read(keys) {
        const defaults = SettingsHelpers.defaults();
        const wanted = (Array.isArray(keys) || keys instanceof Array) && keys.length > 0
            ? keys.map(String) : Object.keys(defaults);
        const values = {};
        const unknown = [];
        for (const key of wanted) {
            if (!known(key) || blockedKey(key))
                unknown.push(key);
            else
                values[key] = Settings[key];
        }
        return unknown.length > 0 ? { values: values, unknown: unknown } : { values: values };
    }

    function windowFor(address) {
        const key = WindowCommands.bareAddress(address);
        return key === "" ? null
            : Hyprland.toplevels.values.find(toplevel => WindowCommands.bareAddress(toplevel.address) === key) ?? null;
    }

    function windowInfo(address) {
        const toplevel = windowFor(address);
        return toplevel ? toplevelRow(toplevel) : {};
    }

    // ---- changing --------------------------------------------------------------
    function setValue(key, value, respond, fail) {
        key = String(key || "");
        if (!known(key))
            return fail(I18n.format("There is no setting called %1. Use settings_search to find one.", [key]));
        if (blockedKey(key))
            return fail(I18n.tr("The assistant's own settings are left to the person."));
        const accepted = SettingsHelpers.normalizeKey(key, value);
        if (!same(accepted, value))
            return fail(I18n.format("%1 does not accept that value. It is %2 now; the default is %3.",
                [key, JSON.stringify(Settings[key]), JSON.stringify(SettingsHelpers.defaults()[key])]));
        const before = Settings[key];
        Settings.set(key, value);
        Settings.saveNow();
        // Settings' own name and place for it, so the answer can call it
        // what the reply's change row and the Settings window call it.
        const row = SearchData.ROWS.find(entry => entry.key === key);
        return respond({ key: key, label: row ? row.label : "", page: row ? row.pageLabel : "",
            group: row ? row.group : "", before: before, after: Settings[key] });
    }

    // A pending wallpaper download answers once it lands or fails.
    property var wallpaperWaiting: null

    function setWallpaper(args, respond, fail) {
        if (args.file) {
            if (!Wallpaper.setByName(String(args.file)))
                return fail(I18n.tr("That image is not in the wallpaper folder."));
            Settings.saveNow();
            return respond({ wallpaper: String(args.file) });
        }
        const item = WallhavenHelpers.parseItem(args.record);
        if (!item)
            return fail(I18n.tr("Wallhaven did not describe that wallpaper in a way it can be saved."));
        if (wallpaperWaiting)
            wallpaperWaiting.fail(I18n.tr("Another wallpaper was chosen."));
        wallpaperWaiting = { id: item.id, respond: respond, fail: fail };
        OnlineWallpapers.apply(item);
    }

    Connections {
        target: OnlineWallpapers

        function onApplied(fileName) {
            const waiting = root.wallpaperWaiting;
            if (!waiting)
                return;
            root.wallpaperWaiting = null;
            Settings.saveNow();
            waiting.respond({ wallpaper: fileName });
        }

        function onDownloadErrorChanged() {
            const waiting = root.wallpaperWaiting;
            if (!waiting || OnlineWallpapers.downloadError === "" || OnlineWallpapers.failedId !== waiting.id)
                return;
            root.wallpaperWaiting = null;
            waiting.fail(OnlineWallpapers.downloadError);
        }
    }

    function openApp(name, respond, fail) {
        const wanted = name.trim().toLowerCase().replace(/\.desktop$/, "");
        if (wanted === "")
            return fail(I18n.tr("Name the app to open."));
        const apps = DesktopEntries.applications.values.filter(entry => !entry.noDisplay);
        const entry = apps.find(app => app.id.toLowerCase() === wanted)
            ?? apps.find(app => (app.name || "").toLowerCase() === wanted)
            ?? apps.find(app => (app.name || "").toLowerCase().indexOf(wanted) !== -1);
        if (!entry)
            return fail(I18n.format("No app called %1 is installed.", [name]));
        Pointer.launch(entry);
        return respond({ opened: entry.name, id: entry.id });
    }

    function windowCommand(address, command, done, respond, fail) {
        // Hyprland falls back to the focused window when a selector does not
        // resolve, so a window that has gone is refused here (WindowCommands.js).
        if (!windowFor(address))
            return fail(I18n.tr("That window is no longer open. Look again with desktop_status."));
        if (command === "")
            return fail(I18n.tr("That window or workspace cannot be named safely."));
        Hyprland.dispatch(command);
        const result = { address: address };
        result[done] = true;
        return respond(result);
    }
}
