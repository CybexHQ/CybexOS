// Software's pure logic (Common/SoftwareHelpers.js): catalogue queries, the
// install queue and the change it stages, following a deployment, updates.
const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");

const H = load("SoftwareHelpers.js");

const apps = [
    { id: "gimp", attribute: "gimp", name: "GIMP", summary: "Image editor", developer: "The GIMP team",
      category: "create", subcategory: "photo", installs: 60000, free: true, downloadBytes: 180e6,
      desktopIds: ["gimp.desktop"], brand: { light: "#f4e4cb", dark: "#293a56" },
      screenshots: ["https://dl.flathub.org/media/org/gimp/GIMP/x/screenshots/image-1_1248x702@1.png",
                    "http://dl.flathub.org/media/plain.png", "https://example.com/tracker.png"] },
    { id: "krita", attribute: "krita", name: "Krita", summary: "Digital painting", developer: "KDE",
      category: "create", subcategory: "drawing", installs: 40000, free: true, downloadBytes: 400e6,
      desktopIds: ["org.kde.krita.desktop"] },
    { id: "darktable", attribute: "darktable", name: "darktable", summary: "RAW photos", developer: "darktable",
      category: "create", subcategory: "photo", installs: 20000, free: true, downloadBytes: 60e6,
      desktopIds: ["org.darktable.darktable.desktop"] },
    { id: "spotify", attribute: "spotify", name: "Spotify", summary: "Music", developer: "Spotify AB",
      category: "media", subcategory: "audio", installs: 90000, free: false, downloadBytes: null,
      desktopIds: ["spotify.desktop"], installed: true, owner: "cybexos" },
    { id: "okular", attribute: "kdePackages.okular", name: "Okular", summary: "Documents", developer: "KDE",
      category: "work", subcategory: "office", installs: 5000, free: true, downloadBytes: 3e6,
      desktopIds: ["org.kde.okular.desktop"], unavailable: "missing" }
];
const categories = [{ id: "create", name: "Create" }, { id: "media", name: "Watch & Listen" }, { id: "work", name: "Work" }];

test("popularity orders the catalogue, categories and Editor's choice", () => {
    assert.deepEqual(H.popular(apps, 2).map(app => app.id), ["spotify", "gimp"]);
    assert.deepEqual(H.inCategory(apps, "create").map(app => app.id), ["gimp", "krita", "darktable"]);
    assert.deepEqual(H.inCategory(apps, "create", "photo").map(app => app.id), ["gimp", "darktable"]);
    assert.deepEqual(H.inCategory(apps, "").length, apps.length, "an empty category is the whole catalogue");
    // Featured apps first, in featured order, then the most popular of the rest.
    assert.deepEqual(H.editorsChoice(apps, ["darktable", "spotify"], "create", "", 3).map(app => app.id),
        ["darktable", "gimp", "krita"]);
    assert.deepEqual(H.featured(apps, ["krita", "missing", "gimp"]).map(app => app.id), ["krita", "gimp"]);
    assert.deepEqual(H.similar(apps, apps[0], 4).map(app => app.id), ["darktable", "krita"],
        "same subcategory first, never the app itself or another category");
    assert.deepEqual(H.similar(apps, null), []);
});

test("collections offer only apps that are missing and available", () => {
    const byId = H.index(apps, "id");
    const value = H.collection({ apps: ["gimp", "spotify", "okular", "nope"] }, byId);
    assert.deepEqual(value.apps.map(app => app.id), ["gimp", "spotify", "okular"]);
    assert.deepEqual(value.missing.map(app => app.id), ["gimp"]);
    assert.equal(value.downloadBytes, 180e6);
    assert.deepEqual(H.collection(null, byId).apps, []);
});

test("search ranks names before summaries, developers and categories", () => {
    assert.deepEqual(H.searchApps(apps, categories, "gimp").map(app => app.id), ["gimp"]);
    assert.deepEqual(H.searchApps(apps, categories, "  KDE ").map(app => app.id), ["krita", "okular"]);
    assert.deepEqual(H.searchApps(apps, categories, "watch").map(app => app.id), ["spotify"], "category names match");
    assert.deepEqual(H.searchApps(apps, categories, "dark").map(app => app.id), ["darktable"]);
    assert.deepEqual(H.searchApps(apps, categories, "raw photo").map(app => app.id), ["darktable"], "terms in any order");
    assert.deepEqual(H.searchApps(apps, categories, "photo zzz").map(app => app.id), [], "every term must match");
    assert.deepEqual(H.searchApps(apps, categories, "").length, 0);
    assert.deepEqual(H.morePackages([{ attribute: "gimp" }, { attribute: "hello" }], apps).map(row => row.attribute), ["hello"]);
});

test("the queue toggles requests and stages one declaration from today's choices", () => {
    let queue = [];
    queue = H.toggle(queue, { attribute: "gimp", action: "install" });
    queue = H.toggle(queue, { attribute: "hello", action: "remove" });
    assert.equal(H.queued(queue, "gimp"), "install");
    assert.equal(H.queued(queue, "nope"), "");
    assert.deepEqual(H.change(["hello", "git"], queue), { packages: ["gimp", "git"], previous: ["git", "hello"] });
    assert.deepEqual(H.toggle(queue, { attribute: "gimp", action: "install" }).map(row => row.attribute), ["hello"],
        "the same request again takes it off the list");
    assert.deepEqual(H.toggle(queue, { attribute: "gimp", action: "remove" }).find(row => row.attribute === "gimp").action,
        "remove", "a different request replaces it");
    assert.deepEqual(H.withAll(queue, [{ attribute: "gimp", action: "install" }, { attribute: "krita", action: "install" }])
        .map(row => row.attribute), ["gimp", "hello", "krita"]);
    assert.deepEqual(H.change([], [{ attribute: "gimp", action: "install" }, { attribute: "gimp", action: "install" }]).packages,
        ["gimp"]);
    // A refresh drops requests the machine already satisfies.
    const catalogue = { desired: ["gimp", "hello"], apps: [{ attribute: "krita", installed: true }] };
    assert.deepEqual(H.prune([{ attribute: "gimp", action: "install" }, { attribute: "krita", action: "install" },
        { attribute: "darktable", action: "install" }, { attribute: "hello", action: "remove" },
        { attribute: "git", action: "remove" }], catalogue).map(row => row.attribute), ["darktable", "hello"]);
});

test("the queue's download prefers checked plans and reports blocked apps", () => {
    const byAttribute = H.index(apps, "attribute");
    const queue = [{ attribute: "gimp", action: "install" }, { attribute: "krita", action: "install" },
        { attribute: "spotify", action: "install" }, { attribute: "hello", action: "remove" }];
    let state = H.queueState(queue, byAttribute, {});
    assert.equal(state.state, "checking");
    assert.equal(state.downloadBytes, 580e6, "catalogue estimates until checked; vendor apps have no NixOS size");
    assert.equal(state.vendor, 1);
    assert.deepEqual([state.count, state.installs, state.removals], [4, 3, 1]);
    state = H.queueState(queue, byAttribute, {
        gimp: { state: "prebuilt", downloadBytes: 1e6 }, krita: { state: "prebuilt", downloadBytes: 0 },
        spotify: { state: "prebuilt", vendor: true, downloadBytes: 5e6 } });
    assert.deepEqual([state.state, state.downloadBytes], ["prebuilt", 6e6]);
    state = H.queueState(queue, byAttribute, { gimp: { state: "compiles" }, krita: { state: "prebuilt" },
        spotify: { state: "unavailable" } });
    assert.deepEqual([state.state, state.blocked], ["blocked", ["gimp", "spotify"]]);
    const verdict = H.verdict({ packages: { gimp: { state: "compiles", compiles: ["gimp-3.0"], vendor: false, version: "3.0" } } }, "gimp");
    assert.deepEqual(verdict, { state: "compiles", reason: "", compiles: ["gimp-3.0"], vendor: false, version: "3.0" });
    assert.equal(H.verdict({ packages: {} }, "gimp"), null);
});

test("a software deployment is followed as one install, including after a shell restart", () => {
    const deployment = state => ({ state, changeKind: "software", requestId: "a".repeat(32) });
    assert.equal(H.owns(deployment("building"), "a".repeat(32)), true);
    assert.equal(H.owns(deployment("building"), "b".repeat(32)), false, "another request's change");
    assert.equal(H.owns({ state: "building", changeKind: "update" }, ""), false);
    assert.equal(H.owns(deployment("ready"), ""), true, "an unfinished change is adopted without a request ID");
    assert.equal(H.owns(deployment("awaiting-boot"), ""), false, "a finished one is not");
    for (const [state, phase] of [["discovering", "preparing"], ["validating", "preparing"], ["ready", "ready"],
        ["activating", "installing"], ["awaiting-boot", "done"], ["done", "done"], ["failed", "failed"], ["stale", "failed"]])
        assert.equal(H.phase("submitted", deployment(state), true), phase, state);
    assert.equal(H.phase("submitted", { state: "idle" }, false), "preparing", "accepted, the worker has not reported yet");
    assert.equal(H.phase("authorizing", { state: "idle" }, false), "authorizing");
    assert.equal(H.phase("submitted", { state: "idle" }, false, { state: "failed" }), "failed", "a worker that never reported");
    assert.equal(H.phase("", {}, false), "idle");
    assert.deepEqual(H.changed({ software: { packages: ["gimp", "git"], previous: ["git", "hello"] } }),
        { installs: ["gimp"], removals: ["hello"] });
    assert.deepEqual(H.changed({}), { installs: [], removals: [] });
});

test("another change, a pending restart or the live system blocks a new install", () => {
    assert.equal(H.blocked({ deployment: { state: "idle" } }), "");
    assert.equal(H.blocked({ deployment: { state: "failed" } }), "", "a failed change does not block retrying");
    assert.equal(H.blocked({ deployment: { state: "awaiting-boot" } }), "restart");
    assert.equal(H.blocked({ deployment: { state: "idle" }, rebootRecommended: true }), "restart");
    assert.equal(H.blocked({ deployment: { state: "building", changeKind: "update" } }), "busy");
    assert.equal(H.blocked({ deployment: { state: "idle" }, runActive: true }), "busy");
    assert.equal(H.blocked({ deployment: { state: "ready", changeKind: "update" } }), "pending");
    assert.equal(H.blocked({ deployment: { state: "ready" }, owned: true }), "", "Software's own change");
    assert.equal(H.blocked({ deployment: { state: "unavailable", available: false } }), "unavailable");
});

test("download progress is measured only when the worker knows the total", () => {
    const progress = (downloads, builds = {}, state = "building") =>
        H.progress({ state, progress: { schema: 1, active: true, downloads, builds } });
    assert.deepEqual(progress({ doneBytes: 25, expectedBytes: 100, totalKnown: true }),
        { fraction: 0.25, done: 25, expected: 100, building: false });
    assert.equal(progress({ doneBytes: 25, expectedBytes: 100 }).fraction, -1);
    assert.equal(progress({ doneBytes: 25, expectedBytes: 100, totalKnown: true }, { active: 1 }).fraction, -1);
    assert.equal(progress({ doneBytes: 25, expectedBytes: 100, totalKnown: true }, {}, "validating").fraction, -1);
    assert.equal(H.progress({ state: "building" }).fraction, -1);
    assert.equal(H.progress({ state: "building", progress: { schema: 2, active: true } }).fraction, -1);
});

test("installed apps group by who put them there, apps before other packages", () => {
    const catalogue = {
        apps: [
            { id: "gimp", attribute: "gimp", name: "GIMP", installed: true, owner: "software", desktopIds: ["gimp.desktop"], installedVersion: "3.0" },
            { id: "firefox", attribute: "firefox", name: "Firefox", installed: true, owner: "cybexos", desktopIds: ["firefox.desktop"] },
            { id: "krita", attribute: "krita", name: "Krita", installed: false, desktopIds: ["org.kde.krita.desktop"] }],
        packages: [
            { path: "/nix/store/a-gimp", name: "gimp", owner: "software", attributes: ["gimp"], apps: [{ id: "gimp.desktop", name: "GIMP" }] },
            { path: "/nix/store/b-firefox", name: "firefox", owner: "cybexos", apps: [{ id: "firefox.desktop", name: "Firefox" }] },
            { path: "/nix/store/c-kitty", name: "kitty", owner: "cybexos", version: "0.40", apps: [{ id: "kitty.desktop", name: "kitty", icon: "kitty" }] },
            { path: "/nix/store/d-obs", name: "obs-studio", owner: "personal", apps: [{ id: "com.obsproject.Studio.desktop", name: "OBS Studio" }] },
            { path: "/nix/store/e-hello", name: "hello", owner: "software", attributes: ["hello"], apps: [] },
            { path: "/nix/store/f-coreutils", name: "coreutils", owner: "cybexos", apps: [] }]
    };
    const groups = H.installedGroups(catalogue);
    assert.deepEqual(groups.software.map(row => row.name), ["GIMP"]);
    assert.deepEqual(groups.cybexos.map(row => row.name), ["Firefox", "kitty"]);
    assert.deepEqual(groups.personal.map(row => row.name), ["OBS Studio"]);
    assert.deepEqual(groups.other.map(row => [row.name, row.owner, row.attribute]),
        [["coreutils", "cybexos", ""], ["hello", "software", "hello"]]);
    assert.equal(groups.software[0].version, "3.0");
    assert.deepEqual(groups.cybexos[1].desktopIds, ["kitty.desktop"]);
    assert.equal(groups.cybexos[1].icon, "kitty");
    assert.equal(H.selectedPackage(catalogue, "hello").name, "hello");
    assert.equal(H.selectedPackage(catalogue, "nope"), null);
    assert.deepEqual(H.installedGroups(null), { software: [], cybexos: [], personal: [], other: [] });
});

test("the Updates tab lists installed apps a prepared system update changes", () => {
    const catalogue = { apps: [{ id: "firefox", name: "Firefox", desktopIds: ["firefox.desktop"] }],
        packages: [{ name: "firefox", apps: [{ id: "firefox.desktop" }] }, { name: "hello", apps: [] }] };
    const highlights = { schema: 1, apps: [{ name: "firefox", title: "Firefox Web Browser", icon: "firefox", kind: "updated", before: "143", after: "144" },
        { name: "kitty", title: "kitty", icon: "kitty", kind: "rebuilt", before: "1", after: "1" }] };
    const rows = H.appUpdates({ changeKind: "update", state: "ready", highlights }, catalogue);
    assert.deepEqual(rows.map(row => [row.title, row.before, row.after, !!row.app]), [["Firefox", "143", "144", true]]);
    assert.deepEqual(H.appUpdates({ changeKind: "software", state: "ready", highlights }, catalogue), []);
    assert.deepEqual(H.appUpdates({ changeKind: "update", state: "building", highlights }, catalogue), []);
    // An older worker without highlights: installed packages with apps only.
    const older = H.appUpdates({ changeKind: "update", state: "ready", packageChanges: [
        { name: "firefox", kind: "updated", before: "1", after: "2" }, { name: "hello", kind: "updated", before: "1", after: "2" }] }, catalogue);
    assert.deepEqual(older.map(row => row.name), ["firefox"]);
});

test("presentation helpers: sizes, colours, descriptions, licences and screenshots", () => {
    assert.equal(H.size(412e6), "412 MB");
    assert.equal(H.size(1.6e9), "1.6 GB");
    assert.equal(H.size(850e3), "850 kB");
    assert.equal(H.size(0), "");
    assert.equal(H.size(null), "");
    assert.equal(H.darkInk("#f4e4cb"), true);
    assert.equal(H.darkInk("#293a56"), false);
    assert.equal(H.mix("#000000", "#ffffff", 0.5), "#808080");
    assert.equal(H.brand(apps[0], null, true), "#293a56");
    assert.equal(H.brand(apps[0], null, false), "#f4e4cb");
    assert.equal(H.brand({ brand: { dark: "#123456" } }, null, false), "#123456", "one brand colour serves both themes");
    assert.equal(H.brand({}, { color: "#ff9f5a" }, true), H.mix("#ff9f5a", "#1a1917", 0.72));
    assert.match(H.brand({}, null, false), /^#[0-9a-f]{6}$/);
    assert.deepEqual(H.paragraphs(["First.", "• Item", "", 3]), [{ text: "First.", bullet: false }, { text: "Item", bullet: true }]);
    assert.deepEqual(H.paragraphs(null), []);
    assert.equal(H.license("GPL-3.0+ AND LGPL-3.0+"), "GPL-3.0+");
    assert.equal(H.license("LicenseRef-proprietary=https://example.com"), "");
    assert.equal(H.license("(MPL-1.1 or GPL-2.0)"), "MPL-1.1");
    assert.equal(H.host("https://www.gimp.org/"), "gimp.org");
    assert.equal(H.host("javascript:alert(1)"), "");
    assert.deepEqual(H.screenshots(apps[0]), [apps[0].screenshots[0]], "only https from Flathub's media server");
    assert.deepEqual(H.screenshots({}), []);
    assert.equal(H.glyph("palette", name => name === "palette"), "palette");
    assert.equal(H.glyph("briefcase", name => name === "files"), "files", "missing Tabler glyphs fall back");
    assert.equal(H.glyph("unknown-icon", () => false), "apps");
    assert.equal(H.columns(1000, 220, 10), 4);
    assert.equal(H.columns(100, 220, 10), 1);
    assert.deepEqual(H.entryIds(["gimp.desktop", "../evil.desktop", "x", 5]), ["gimp"]);
    assert.deepEqual(H.list({ length: 2, 0: "a", 1: "b" }), ["a", "b"], "array-likes from status snapshots");
    assert.deepEqual(H.list(null), []);
    assert.deepEqual(H.changed({ software: { packages: { length: 1, 0: "gimp" }, previous: { length: 0 } } }),
        { installs: ["gimp"], removals: [] });
});

test("Flathub apps: IDs, media, deduplicated results and installed rows", () => {
    assert.equal(H.flathubId("org.mozilla.thunderbird"), true);
    assert.equal(H.flathubId("net._86box._86Box"), true, "later elements may start with a digit or underscore");
    assert.equal(H.flathubId("1net.example.App"), false, "the first element starts with a letter");
    for (const bad of ["org.gimp", "-x.y.z", "org.gimp.GIMP --user", "org/gimp/GIMP", "", null, "a.b." + "c".repeat(260)])
        assert.equal(H.flathubId(bad), false, String(bad));
    assert.equal(H.flathubMedia("https://dl.flathub.org/media//org/mozilla/thunderbird/x/icons/128x128/org.mozilla.thunderbird.png"),
        "https://dl.flathub.org/media//org/mozilla/thunderbird/x/icons/128x128/org.mozilla.thunderbird.png");
    for (const bad of ["http://dl.flathub.org/media/a.png", "https://dl.flathub.org.example.com/media/a.png",
                       "https://dl.flathub.org/repo/a.png", "file:///etc/passwd", "https://dl.flathub.org/media/a.png?x=1"])
        assert.equal(H.flathubMedia(bad), "", bad);

    const catalogue = [{ id: "gimp", appstream: "org.gimp.GIMP", name: "GIMP" }];
    const results = [{ id: "org.gimp.GIMP", name: "GIMP" }, { id: "org.mozilla.thunderbird", name: "Thunderbird" },
                     { id: "bad id", name: "x" }, null];
    assert.deepEqual(H.flathubHits(results, catalogue).map(row => row.id), ["org.mozilla.thunderbird"],
        "catalogue apps are already shown above Flathub's results");
    assert.deepEqual(H.flathubHits({ length: 1, 0: results[1] }, []).map(row => row.id), ["org.mozilla.thunderbird"]);

    const installed = [{ id: "org.gimp.GIMP", name: "GIMP", installation: "system", desktop: true, version: "3.0" },
                       { id: "org.gimp.GIMP", name: "GIMP", installation: "user", desktop: true, version: "3.1" },
                       { id: "org.vim.Vim", name: "Vim", installation: "user", desktop: false, icon: "/x/vim.png" }];
    assert.equal(H.flatpak(installed, "org.gimp.GIMP").installation, "user", "this account's copy first");
    assert.equal(H.flatpak(installed, "org.example.Missing"), null);
    const rows = H.flathubInstalledRows(installed, catalogue);
    assert.deepEqual(rows.map(row => [row.name, row.flatpak.installation, row.desktopIds]),
        [["GIMP", "system", ["org.gimp.GIMP.desktop"]], ["GIMP", "user", ["org.gimp.GIMP.desktop"]], ["Vim", "user", []]]);
    assert.equal(rows[0].catalogue, catalogue[0], "a catalogue app lends its shipped icon");
    assert.equal(rows[2].owner, "flathub");
    assert.deepEqual(H.permissions(["network", "files-all", "unknown", "x11"]), ["files-all", "x11", "network"]);
});

test("Flathub actions follow the change in flight, what is installed and policy", () => {
    const entry = { id: "org.mozilla.thunderbird", name: "Thunderbird" };
    const on = { enabled: true, available: true };
    assert.equal(H.flathubMode(entry, null, null, on), "install");
    assert.equal(H.flathubMode(entry, { id: entry.id }, null, on), "open");
    assert.equal(H.flathubMode(null, null, null, on), "none");
    assert.equal(H.flathubMode({ id: "bad" }, null, null, on), "none");
    assert.equal(H.flathubMode(entry, null, null, { enabled: false, available: true }), "off");
    assert.equal(H.flathubMode(entry, null, null, { enabled: true, available: false }), "off");
    assert.equal(H.flathubMode(Object.assign({ unavailable: "unfree" }, entry), null, null, on), "unfree");
    assert.equal(H.flathubMode(Object.assign({ supported: false }, entry), null, null, on), "unsupported");
    const running = (action, ids, state) => ({ id: "a".repeat(32), action: action, ids: ids, state: state || "running" });
    assert.equal(H.flathubMode(entry, null, running("install", [entry.id]), on), "installing");
    assert.equal(H.flathubMode(entry, null, running("install", [entry.id], "queued"), on), "installing");
    assert.equal(H.flathubMode(entry, { id: entry.id }, running("remove", [entry.id]), on), "removing");
    assert.equal(H.flathubMode(entry, { id: entry.id }, running("update", []), on), "updating", "an update of everything");
    assert.equal(H.flathubMode(entry, null, running("install", ["org.vim.Vim"]), on), "install", "another app's change");
    assert.equal(H.flathubMode(entry, null, running("install", [entry.id], "failed"), on), "install");
    assert.equal(H.flathubTask(running("install", ["org.vim.Vim"]), entry.id), null);
    assert.equal(H.flathubRunning(running("update", [], "done")), false);
    assert.equal(H.flathubRunning(null), false);
});
