pragma Singleton
import QtQuick
import Quickshell
import "SoftwareHelpers.js" as Helpers

// The Software app's state: the catalogue that ships with Cybex OS merged
// with this machine (`cybex software catalogue`), search, prebuilt checks,
// and the install queue that becomes one staged system change. The worker
// owns that change; Software follows it through Updates and applies it with
// Updates.apply(), which asks for authorization. Nothing compiles here: every
// install is checked first (`cybex software check`) and blocked if it would.
// Flathub is the second source: sandboxed apps installed for this account
// right away (`cybex software flathub`), outside system changes.
Singleton {
    id: root

    property bool open: false
    signal present()

    // ---- navigation --------------------------------------------------------
    // Tabs are roots; category, list and app pages stack above them. Search
    // results replace the stack while a query is typed.
    property string tab: "explore"
    property var pages: []
    property string query: ""
    readonly property var page: pages.length > 0 ? pages[pages.length - 1] : null
    readonly property bool searching: query.trim() !== ""
    readonly property bool canGoBack: pages.length > 0 || searching
    readonly property string view: page ? page.kind : searching ? "search" : tab

    function show() {
        if (open)
            present();
        else
            open = true;
        refresh();
    }
    function close() {
        open = false;
        viewer = null;
    }
    function selectTab(name) {
        if (!["explore", "installed", "updates"].includes(name))
            return;
        tab = name;
        pages = [];
        query = "";
        if (name === "updates")
            checkFlathubUpdates(false);
    }
    function search(text) {
        query = String(text || "").slice(0, 200);
        pages = [];
        moreDelay.restart();
        flathubDelay.restart();
    }
    function push(entry) { pages = pages.concat([entry]); }
    function openCategory(id) {
        if (categoriesById[id])
            push({ kind: "category", id: id, sub: "" });
    }
    function openList(kind) {
        if (["popular", "collection"].includes(kind) || kind === "")
            push({ kind: "popular", id: "", sub: "" });
    }
    function openCollection(id) {
        if (profiles.some(profile => profile.id === id))
            push({ kind: "collection", id: id, sub: "" });
    }
    function openApp(id) {
        const app = appsById[id];
        if (!app)
            return;
        push({ kind: "app", id: id, sub: "" });
        requestCheck(app.attribute);
    }
    function setSubcategory(sub) {
        if (!page || page.kind !== "category")
            return;
        pages = pages.slice(0, -1).concat([Object.assign({}, page, { sub: sub })]);
    }
    // Back from a page, then out of search. False when already at a tab root.
    function back() {
        if (pages.length > 0) {
            pages = pages.slice(0, -1);
            return true;
        }
        if (searching) {
            search("");
            return true;
        }
        return false;
    }

    // ---- the catalogue -----------------------------------------------------
    readonly property var empty: ({ apps: [], categories: [], profiles: [], featured: [], packages: [],
        desired: [], selected: [], icons: "" })
    property var catalogue: empty
    property bool loaded: false
    property string loadError: ""
    property bool reloadWanted: false
    readonly property bool loading: loader.busy
    readonly property var apps: catalogue.apps || []
    readonly property var categories: catalogue.categories || []
    readonly property var profiles: catalogue.profiles || []
    readonly property var appsById: Helpers.index(apps, "id")
    readonly property var appsByAttribute: Helpers.index(apps, "attribute")
    readonly property var categoriesById: Helpers.index(categories, "id")
    readonly property var installedGroups: Helpers.installedGroups(catalogue)
    readonly property var packagesByDesktop: {
        const result = {};
        for (const pkg of catalogue.packages || [])
            for (const entry of pkg.apps || [])
                if (!(entry.id in result))
                    result[entry.id] = pkg;
        return result;
    }

    function refresh() {
        if (!loader.run(["cybex", "software", "catalogue"]))
            reloadWanted = true;
        if (searching)
            moreDelay.restart();
        refreshFlathub();
    }
    function iconSource(app) {
        return app && /^[a-z0-9]{2,32}$/.test(app.id || "") && catalogue.icons
            ? "file://" + catalogue.icons + "/" + app.id + ".png" : "";
    }
    function category(app) { return app ? categoriesById[app.category] || null : null; }
    function subcategoryName(app) {
        const value = category(app);
        const sub = value ? (value.subcategories || []).find(entry => entry.id === app.subcategory) : null;
        return sub ? sub.name : "";
    }

    // Handlers read each command's `result`: values passed through a `var`
    // signal arrive with sequence-wrapped arrays, which concat cannot spread.
    JsonCommand {
        id: loader
        onCompleted: () => {
            const value = loader.result;
            if (!value || value.schema !== 1 || !(Array.isArray(value.apps) || value.apps instanceof Array)) {
                root.loadError = I18n.tr("Software returned an invalid catalogue. Refresh to try again.");
                return;
            }
            // Desired packages and versions changed: earlier checks are stale.
            if (root.catalogue.identity !== value.identity)
                root.checks = ({});
            root.catalogue = value;
            root.loaded = true;
            root.loadError = "";
            root.queue = Helpers.prune(root.queue, value);
        }
        onFailed: message => { root.loadError = message; }
    }
    Connections {
        target: loader
        function onBusyChanged() {
            if (!loader.busy && root.reloadWanted) {
                root.reloadWanted = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    // The catalogue's category and collection names, in the session's
    // language; anything newer than this list stays as the catalogue wrote it.
    readonly property var labels: ({
        "Create": I18n.tr("Create"), "Graphics, photography, 3D and publishing": I18n.tr("Graphics, photography, 3D and publishing"),
        "Photo": I18n.tr("Photo"), "Drawing": I18n.tr("Drawing"), "Vector": I18n.tr("Vector"), "3D": I18n.tr("3D"),
        "Publishing": I18n.tr("Publishing"),
        "Work": I18n.tr("Work"), "Documents, mail, notes and tasks": I18n.tr("Documents, mail, notes and tasks"),
        "Office": I18n.tr("Office"), "Mail & calendar": I18n.tr("Mail & calendar"), "Notes": I18n.tr("Notes"),
        "Tasks": I18n.tr("Tasks"), "Finance": I18n.tr("Finance"),
        "Develop": I18n.tr("Develop"), "Editors, databases, APIs and tools": I18n.tr("Editors, databases, APIs and tools"),
        "Editors": I18n.tr("Editors"), "Tools": I18n.tr("Tools"), "Databases & APIs": I18n.tr("Databases & APIs"),
        "Game engines": I18n.tr("Game engines"),
        "Play": I18n.tr("Play"), "Games, launchers and emulators": I18n.tr("Games, launchers and emulators"),
        "Launchers": I18n.tr("Launchers"), "Games": I18n.tr("Games"), "Emulators": I18n.tr("Emulators"),
        "Watch & Listen": I18n.tr("Watch & Listen"),
        "Video, music, podcasts and recording": I18n.tr("Video, music, podcasts and recording"),
        "Players": I18n.tr("Players"), "Video editing": I18n.tr("Video editing"), "Audio": I18n.tr("Audio"),
        "Recording": I18n.tr("Recording"),
        "Chat": I18n.tr("Chat"), "Messages, calls and meetings": I18n.tr("Messages, calls and meetings"),
        "Messaging": I18n.tr("Messaging"), "Meetings": I18n.tr("Meetings"),
        "Learn": I18n.tr("Learn"), "Study, science and reading": I18n.tr("Study, science and reading"),
        "Study": I18n.tr("Study"), "Science": I18n.tr("Science"), "Reading": I18n.tr("Reading"),
        "Utilities": I18n.tr("Utilities"), "Web, security, backups and system": I18n.tr("Web, security, backups and system"),
        "Web browsers": I18n.tr("Web browsers"), "Security": I18n.tr("Security"), "Files & backups": I18n.tr("Files & backups"),
        "System": I18n.tr("System"),
        "Software Development": I18n.tr("Software Development"), "Office & Productivity": I18n.tr("Office & Productivity"),
        "Graphics & Design": I18n.tr("Graphics & Design"), "Audio & Video": I18n.tr("Audio & Video"),
        "Gaming": I18n.tr("Gaming"), "Chat & Meetings": I18n.tr("Chat & Meetings")
    })
    function label(text) { return labels[text] || String(text || ""); }

    // ---- screenshots -------------------------------------------------------
    // Screenshots load from Flathub only on an app's page. Once one has, the
    // hero and Editor's choice may show it too for the rest of this session.
    property var shownScreenshots: ({})
    property var viewer: null
    function remember(url) {
        if (!url || shownScreenshots[url])
            return;
        const next = Object.assign({}, shownScreenshots);
        next[url] = true;
        shownScreenshots = next;
    }
    function shownScreenshot(app) {
        return Helpers.screenshots(app).find(url => !!shownScreenshots[url]) || "";
    }
    function viewScreenshots(urls, index) {
        if ((urls || []).length > 0)
            viewer = { urls: urls, index: Math.max(0, Math.min(index, urls.length - 1)) };
    }
    function stepViewer(delta) {
        if (viewer)
            viewer = { urls: viewer.urls, index: (viewer.index + delta + viewer.urls.length) % viewer.urls.length };
    }
    function closeViewer() { viewer = null; }

    // ---- search ------------------------------------------------------------
    // Catalogue apps match instantly; "More packages" come from the machine's
    // full Nixpkgs index, which takes a while to build the first time.
    readonly property var appResults: searching ? Helpers.searchApps(apps, categories, query, 48) : []
    property var moreResults: []
    property int moreTotal: 0
    property string moreQuery: ""
    property string moreError: ""
    readonly property bool moreBusy: searcher.busy || moreDelay.running
    readonly property var morePackages: moreQuery === query.trim() ? Helpers.morePackages(moreResults, apps) : []

    Timer {
        id: moreDelay
        interval: 350
        onTriggered: {
            const text = root.query.trim();
            if (text === "") {
                root.moreResults = [];
                root.moreQuery = "";
                return;
            }
            if (!searcher.run(["cybex", "software", "search", text]))
                restart();
            else
                searcher.text = text;
        }
    }
    JsonCommand {
        id: searcher
        property string text: ""
        onCompleted: () => {
            const value = searcher.result;
            root.moreResults = value.results || [];
            root.moreTotal = value.total || 0;
            root.moreQuery = text;
            root.moreError = "";
            if (text !== root.query.trim())
                moreDelay.restart();
        }
        onFailed: message => { root.moreError = message; root.moreQuery = text; }
    }

    // ---- prebuilt checks ---------------------------------------------------
    // One attribute at a time, on demand: opening an app page, adding to the
    // queue, or a search result's Check. Results last for this catalogue.
    property var checks: ({})
    property var checkQueue: []
    property string checkingAttribute: ""

    function check(attribute) { return checks[attribute] || null; }
    function setCheck(attribute, value) {
        const next = Object.assign({}, checks);
        next[attribute] = value;
        checks = next;
    }
    function requestCheck(attribute) {
        if (!attribute || checkQueue.includes(attribute) || checkingAttribute === attribute)
            return;
        const known = checks[attribute];
        if (known && known.state !== "error")
            return;
        checkQueue = checkQueue.concat([attribute]);
        setCheck(attribute, { state: "checking" });
        pumpChecks();
    }
    function pumpChecks() {
        if (checker.busy || flowChecker.busy || checkQueue.length === 0)
            return;
        const attribute = checkQueue[0];
        checkQueue = checkQueue.slice(1);
        checkingAttribute = attribute;
        if (!checker.run(["cybex", "software", "check", attribute]))
            checkingAttribute = "";
    }
    JsonCommand {
        id: checker
        onCompleted: () => {
            const value = checker.result;
            const attribute = root.checkingAttribute;
            const verdict = Helpers.verdict(value, attribute);
            root.setCheck(attribute, verdict ? Object.assign(verdict, { downloadBytes: Number(value.downloadBytes) || 0 })
                : { state: "error", error: "" });
            root.checkingAttribute = "";
            Qt.callLater(root.pumpChecks);
        }
        onFailed: message => {
            root.setCheck(root.checkingAttribute, { state: "error", error: message });
            root.checkingAttribute = "";
            Qt.callLater(root.pumpChecks);
        }
    }

    // ---- the install queue -------------------------------------------------
    // Items: {attribute, action: "install" | "remove", id, name}. Installing
    // checks the whole queue, stages one change, follows it, then asks to
    // apply it. Removals need no check.
    property var queue: []
    property var flowItems: []
    property string localPhase: "idle"
    property string flowError: ""
    property string requestId: ""
    property var requestStatus: ({})

    readonly property var deployment: Updates.deployment
    readonly property bool owned: Helpers.owns(deployment, requestId)
    readonly property string phase: Helpers.phase(localPhase, deployment, owned, requestStatus)
    readonly property bool flowActive: !["idle", "blocked"].includes(phase)
    readonly property string blockReason: Helpers.blocked({
        available: Updates.statusLoaded ? Updates.deployment.available !== false : true,
        deployment: deployment, owned: owned, rebootRecommended: Updates.rebootRecommended,
        runActive: Updates.runActive })
    readonly property var queueState: Helpers.queueState(queue, appsByAttribute, checks)
    // What the change in flight installs and removes, by attribute. A change
    // adopted after a shell restart is read back from the deployment.
    readonly property var flowChange: {
        if (flowItems.length > 0)
            return { installs: Helpers.installs(flowItems).map(row => row.attribute),
                removals: Helpers.removals(flowItems).map(row => row.attribute) };
        return Helpers.changed(deployment);
    }
    readonly property var preparation: Helpers.progress(deployment)
    readonly property string failure: flowError || (phase === "failed"
        ? (owned ? deployment.error || "" : requestStatus.error || "") : "")

    function queued(attribute) { return Helpers.queued(queue, attribute); }
    function item(attribute, action) {
        const app = appsByAttribute[attribute];
        return { attribute: attribute, action: action, id: app ? app.id : "", name: app ? app.name : attribute };
    }
    function toggleInstall(attribute) {
        if (!attribute)
            return;
        queue = Helpers.toggle(queue, item(attribute, "install"));
        flowError = "";
        if (queued(attribute) === "install")
            requestCheck(attribute);
        if (localPhase === "blocked" && queueState.blocked.length === 0)
            localPhase = "idle";
    }
    function toggleRemove(attribute) {
        if (!attribute)
            return;
        queue = Helpers.toggle(queue, item(attribute, "remove"));
        flowError = "";
    }
    function installAll(profileId) {
        const profile = profiles.find(entry => entry.id === profileId);
        const missing = Helpers.collection(profile, appsById).missing.filter(app => !queued(app.attribute));
        queue = Helpers.withAll(queue, missing.map(app => item(app.attribute, "install")));
        for (const app of missing)
            requestCheck(app.attribute);
    }
    function clearQueue() {
        queue = [];
        if (localPhase === "blocked")
            localPhase = "idle";
        flowError = "";
    }
    // Drop the queued apps that cannot be installed yet, keep the rest.
    function dropBlocked() {
        const blocked = queueState.blocked;
        queue = queue.filter(row => !blocked.includes(row.attribute));
        localPhase = "idle";
    }

    function install() {
        if (queue.length === 0 || blockReason !== "" || flowActive || !loaded)
            return;
        flowError = "";
        const attributes = Helpers.installs(queue).map(row => row.attribute);
        if (attributes.length === 0) {
            submit();
            return;
        }
        localPhase = "checking";
        if (!flowChecker.run(["cybex", "software", "check"].concat(attributes)))
            localPhase = "idle";
    }
    function submit() {
        const request = Helpers.change(catalogue.desired, queue);
        if (request.packages.length > 512) {
            flowError = I18n.tr("Software can keep up to 512 apps and packages. Remove some first.");
            localPhase = "idle";
            return;
        }
        flowItems = queue.slice();
        queue = [];
        requestId = "";
        requestStatus = ({});
        localPhase = "authorizing";
        if (!stager.run(["cybex", "software", "stage", JSON.stringify(request)]))
            restoreQueue("");
    }
    function restoreQueue(message) {
        queue = Helpers.withAll(flowItems, queue);
        flowItems = [];
        localPhase = "idle";
        flowError = message;
    }
    // Apply the prepared change; Updates asks for authorization.
    function confirm() {
        if (phase === "ready" && owned)
            Updates.apply();
    }
    // Discard a prepared change; the queued apps come back to the list.
    function cancelChange() {
        if (phase !== "ready" || !owned)
            return;
        Updates.discard();
        restoreQueue("");
        requestId = "";
    }
    function retry() {
        if (phase !== "failed")
            return;
        restoreQueue("");
        requestId = "";
        requestStatus = ({});
        install();
    }
    function dismiss() {
        const finished = phase === "done";
        if (phase === "failed")
            queue = Helpers.withAll(flowItems, queue);
        flowItems = [];
        requestId = "";
        requestStatus = ({});
        localPhase = "idle";
        flowError = "";
        if (finished)
            refresh();
    }
    onPhaseChanged: {
        // The change is live: the installed state and desired list moved.
        if (phase === "done")
            refresh();
    }

    JsonCommand {
        id: flowChecker
        onCompleted: () => {
            const value = flowChecker.result;
            const packages = value.packages || {};
            const attributes = Object.keys(packages);
            for (const attribute of attributes) {
                const verdict = Helpers.verdict(value, attribute);
                // A combined plan has one total; keep each app's own size.
                const own = attributes.length === 1 ? { downloadBytes: Number(value.downloadBytes) || 0 } : {};
                if (verdict)
                    root.setCheck(attribute, Object.assign({}, root.checks[attribute] || {}, own, verdict));
            }
            if (value.prebuilt === true && root.localPhase === "checking")
                root.submit();
            else if (root.localPhase === "checking")
                root.localPhase = "blocked";
            Qt.callLater(root.pumpChecks);
        }
        onFailed: message => {
            root.localPhase = "idle";
            root.flowError = message;
            Qt.callLater(root.pumpChecks);
        }
    }
    JsonCommand {
        id: stager
        onCompleted: () => {
            const value = stager.result;
            if (!/^[a-f0-9]{32}$/.test(value.requestId || "")) {
                root.restoreQueue(I18n.tr("The request was not accepted. Nothing was changed. Try again."));
                return;
            }
            root.requestId = value.requestId;
            root.localPhase = "submitted";
            Updates.refreshStatus();
        }
        onFailed: message => root.restoreQueue(message)
    }
    JsonCommand {
        id: requestPoll
        onCompleted: () => {
            const value = requestPoll.result;
            root.requestStatus = value || ({});
            if (!root.owned)
                Updates.refreshStatus();
        }
        onFailed: message => { root.requestStatus = { state: "failed", error: message }; }
    }
    // The supervised request settles once its worker finishes; its record
    // keeps a worker failure that never reached the deployment status.
    Timer {
        interval: 1500
        repeat: true
        running: root.open && root.requestId !== "" && !["done", "failed"].includes(root.requestStatus.state || "")
        onTriggered: requestPoll.run(["cybex", "software", "request", root.requestId])
    }

    // ---- opening apps ------------------------------------------------------
    // Exactly the catalogue's desktop entries, the visible one named like the
    // app first (LibreOffice's start centre, not Base); a freshly installed
    // entry not yet indexed opens from its package. Nothing guesses by name.
    function appEntryIds(app) {
        if (!app)
            return [];
        const ids = (app.appstream ? [app.appstream + ".desktop"] : []).concat(app.desktopIds || []);
        return ids.filter((id, index) => ids.indexOf(id) === index);
    }
    function entryFor(desktopIds, name) {
        void DesktopEntries.applications.values;
        let first = null;
        for (const id of Helpers.entryIds(desktopIds)) {
            const entry = DesktopEntries.byId(id);
            if (!entry || entry.noDisplay)
                continue;
            if (name && entry.name === name)
                return entry;
            if (first === null)
                first = entry;
        }
        return first;
    }
    function packageEntry(desktopIds, name) {
        let first = "";
        for (const id of desktopIds || []) {
            const pkg = packagesByDesktop[id];
            if (!pkg || !/^\/nix\/store\/[a-z0-9]{32}-[^/]+$/.test(pkg.path) || !/^[A-Za-z0-9_@.+-]+\.desktop$/.test(id))
                continue;
            const path = pkg.path + "/share/applications/" + id;
            if (name && (pkg.apps || []).some(entry => entry.id === id && entry.name === name))
                return path;
            if (first === "")
                first = path;
        }
        return first;
    }
    function canOpen(desktopIds, name) {
        return entryFor(desktopIds, name) !== null || packageEntry(desktopIds, name) !== "";
    }
    function canOpenApp(app) { return !!app && canOpen(appEntryIds(app), app.name); }
    function launch(desktopIds, name) {
        const entry = entryFor(desktopIds, name);
        if (entry) {
            entry.execute();
            return true;
        }
        const path = packageEntry(desktopIds, name);
        if (path !== "")
            Quickshell.execDetached(["gio", "launch", path]);
        return path !== "";
    }
    function openApplication(app) {
        if (!app)
            return false;
        if (launch(appEntryIds(app), app.name))
            return true;
        // Installed from Flathub instead: its own launcher.
        return !!flathubApp(app.appstream || "") && launchFlathub(app.appstream, app.name);
    }
    // A catalogue app installed from Flathub rather than NixOS.
    function viaFlathub(app) { return !!app && !app.installed && !!flathubApp(app.appstream || ""); }

    // ---- Flathub -----------------------------------------------------------
    // Status reads only this computer. Search, app pages and update checks
    // contact Flathub; installs, updates and removals run in a user service
    // the worker records, so Software follows a change after a shell restart.
    property var flathub: ({ schema: 1, enabled: false, available: false, remote: false, proprietary: false,
        task: null, installed: [] })
    property bool flathubLoaded: false
    property bool flathubStatusWanted: false
    readonly property bool flathubOn: flathubLoaded && flathub.enabled === true && flathub.available === true
    readonly property var flathubInstalled: Helpers.list(flathub.installed)
    readonly property var flathubTask: flathub.task || null
    readonly property bool flathubBusy: Helpers.flathubRunning(flathubTask) || flathubStarter.busy
    readonly property var flathubRows: Helpers.flathubInstalledRows(flathubInstalled, apps)
    property string flathubStartError: ""
    property string flathubStartId: ""
    property string flathubStartAction: ""
    property string lastFlathubTask: ""

    function flathubApp(id) { return Helpers.flatpak(flathubInstalled, id); }
    function flathubMode(entry) {
        if (entry && flathubStarter.busy && flathubStartId === entry.id)
            return flathubStartAction === "remove" ? "removing" : flathubStartAction === "update" ? "updating" : "installing";
        return Helpers.flathubMode(entry, flathubApp(entry ? entry.id : ""), flathubTask, flathubLoaded ? flathub : {});
    }
    // The latest change's error, when it concerns this app.
    function flathubFailure(id) {
        if (flathubStartError !== "" && flathubStartId === id)
            return flathubStartError;
        const task = Helpers.flathubTask(flathubTask, id);
        return task && task.state === "failed" ? task.error || "" : "";
    }
    // The latest update's error, for the Updates tab.
    readonly property string flathubUpdateError: flathubStartAction === "update" && flathubStartError !== "" ? flathubStartError
        : flathubTask && flathubTask.action === "update" && flathubTask.state === "failed" ? flathubTask.error || "" : ""
    function refreshFlathub() {
        if (!flathubStatus.run(["cybex", "software", "flathub", "status"]))
            flathubStatusWanted = true;
    }
    function startFlathub(action, ids, names) {
        if (flathubBusy)
            return false;
        flathubStartError = "";
        flathubStartId = ids.length === 1 ? ids[0] : "";
        flathubStartAction = action;
        return flathubStarter.run(["cybex", "software", "flathub", action, "--names", JSON.stringify(names || {})].concat(ids));
    }
    function installFlathub(id, name) {
        if (Helpers.flathubId(id))
            startFlathub("install", [id], { [id]: name || id });
    }
    function removeFlathub(id, name) {
        const row = flathubApp(id);
        if (row && row.installation === "user")
            startFlathub("remove", [id], { [id]: name || row.name || id });
    }
    function updateFlathub(ids) {
        const names = {};
        for (const row of flathubUpdates)
            names[row.id] = row.name;
        startFlathub("update", ids || [], names);
    }
    function launchFlathub(id, name) {
        if (!Helpers.flathubId(id))
            return false;
        if (launch([id + ".desktop"], name))
            return true;
        Quickshell.execDetached(["flatpak", "run", id]);
        return true;
    }

    JsonCommand {
        id: flathubStatus
        onCompleted: () => {
            const value = flathubStatus.result;
            if (!value || value.schema !== 1)
                return;
            root.flathub = value;
            root.flathubLoaded = true;
            const task = value.task || null;
            // This session's update finished: those apps are current now.
            if (task && task.id === root.lastFlathubTask && !Helpers.flathubRunning(task)) {
                root.lastFlathubTask = "";
                const ids = Helpers.list(task.ids);
                if (task.action === "update" && task.state === "done")
                    root.flathubUpdates = ids.length === 0 ? [] : root.flathubUpdates.filter(row => !ids.includes(row.id));
            }
        }
    }
    Connections {
        target: flathubStatus
        function onBusyChanged() {
            if (!flathubStatus.busy && root.flathubStatusWanted) {
                root.flathubStatusWanted = false;
                Qt.callLater(root.refreshFlathub);
            }
        }
    }
    JsonCommand {
        id: flathubStarter
        onCompleted: () => {
            root.lastFlathubTask = flathubStarter.result.task || "";
            root.refreshFlathub();
        }
        onFailed: message => {
            root.flathubStartError = message;
            root.refreshFlathub();
        }
    }
    // Follow a change while it runs, whether or not the window is open.
    Timer {
        interval: 1500
        repeat: true
        running: Helpers.flathubRunning(root.flathubTask)
        onTriggered: root.refreshFlathub()
    }

    // Search results, debounced with the NixOS search.
    property var flathubResults: []
    property int flathubTotal: 0
    property string flathubQuery: ""
    property string flathubError: ""
    readonly property bool flathubSearching: flathubSearcher.busy || flathubDelay.running
    readonly property var flathubHits: flathubQuery === query.trim() ? Helpers.flathubHits(flathubResults, apps) : []
    Timer {
        id: flathubDelay
        interval: 450
        onTriggered: {
            const text = root.query.trim();
            if (text === "" || !root.flathubOn) {
                root.flathubResults = [];
                root.flathubQuery = "";
                return;
            }
            if (!flathubSearcher.run(["cybex", "software", "flathub", "search", text]))
                restart();
            else
                flathubSearcher.text = text;
        }
    }
    JsonCommand {
        id: flathubSearcher
        property string text: ""
        onCompleted: () => {
            const value = flathubSearcher.result;
            root.flathubResults = Helpers.list(value.results);
            root.flathubTotal = Number(value.total) || 0;
            root.flathubQuery = text;
            root.flathubError = "";
            if (text !== root.query.trim())
                flathubDelay.restart();
        }
        onFailed: message => {
            root.flathubResults = [];
            root.flathubError = message;
            root.flathubQuery = text;
        }
    }

    // App pages: details from Flathub, one request at a time. A search
    // result or catalogue app lends its name, summary and icon meanwhile.
    property var flathubPages: ({})
    property var flathubPreviews: ({})
    property var flathubWanted: []
    function openFlathub(id, preview) {
        if (!Helpers.flathubId(id))
            return;
        if (preview) {
            const next = Object.assign({}, flathubPreviews);
            next[id] = preview;
            flathubPreviews = next;
        }
        push({ kind: "flathub", id: id, sub: "" });
        loadFlathub(id);
    }
    function flathubPage(id) {
        const loaded = flathubPages[id];
        return loaded && loaded.state === "ready" ? loaded.app : Object.assign({ id: id }, flathubPreviews[id] || {});
    }
    function flathubPageState(id) { return (flathubPages[id] || {}).state || "loading"; }
    function flathubPageError(id) { return (flathubPages[id] || {}).error || ""; }
    function setFlathubPage(id, value) {
        const next = Object.assign({}, flathubPages);
        next[id] = value;
        flathubPages = next;
    }
    function loadFlathub(id) {
        const known = flathubPages[id];
        if (known && known.state !== "error")
            return;
        setFlathubPage(id, { state: "loading" });
        if (!flathubWanted.includes(id))
            flathubWanted = flathubWanted.concat([id]);
        pumpFlathub();
    }
    function pumpFlathub() {
        if (flathubLoader.busy || flathubWanted.length === 0)
            return;
        const id = flathubWanted[0];
        flathubWanted = flathubWanted.slice(1);
        flathubLoader.appId = id;
        if (!flathubLoader.run(["cybex", "software", "flathub", "app", id]))
            flathubWanted = [id].concat(flathubWanted);
    }
    JsonCommand {
        id: flathubLoader
        property string appId: ""
        onCompleted: () => {
            const value = flathubLoader.result;
            root.setFlathubPage(appId, value && value.id === appId ? { state: "ready", app: value }
                : { state: "error", error: "" });
            Qt.callLater(root.pumpFlathub);
        }
        onFailed: message => {
            root.setFlathubPage(appId, { state: "error", error: message });
            Qt.callLater(root.pumpFlathub);
        }
    }

    // Updates for this account's Flathub apps, checked when the Updates tab
    // opens (at most every ten minutes) or on request.
    property var flathubUpdates: []
    property string flathubUpdatesError: ""
    property var flathubCheckedAt: null
    readonly property bool flathubChecking: flathubUpdater.busy
    readonly property bool flathubMine: flathubInstalled.some(row => row.installation === "user")
    function checkFlathubUpdates(force) {
        if (!flathubOn || !flathubMine || flathubUpdater.busy)
            return;
        if (!force && flathubCheckedAt && Date.now() - flathubCheckedAt.getTime() < 600000)
            return;
        flathubUpdater.run(["cybex", "software", "flathub", "updates"]);
    }
    JsonCommand {
        id: flathubUpdater
        onCompleted: () => {
            root.flathubUpdates = Helpers.list(flathubUpdater.result.updates);
            root.flathubUpdatesError = "";
            root.flathubCheckedAt = new Date();
        }
        onFailed: message => { root.flathubUpdatesError = message; }
    }

    // ---- updates -----------------------------------------------------------
    readonly property var updates: Helpers.appUpdates(Updates.deployment, catalogue)
    function openSoftwareUpdate() { Updates.show(); }
}
