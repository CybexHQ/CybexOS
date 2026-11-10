const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./shell.cjs");
const H = load("UpdatesHelpers.js");
const available = { upstream: { state: "available", available: "new revision" }, cybexos: { state: "unavailable" } };

test("updater status polling slows only when its window and worker are idle", () => {
    for (const state of ["idle", "done", "ready", "awaiting-boot", "failed", "unavailable"])
        assert.equal(H.statusPollInterval(false, false, state), 30000, state);
    assert.equal(H.statusPollInterval(true, false, "idle"), 2000, "visible status remains responsive");
    assert.equal(H.statusPollInterval(false, true, "building"), 2000, "background progress remains responsive");
    assert.equal(H.statusPollInterval(false, true, "idle"), 2000, "queued requests keep the fast cadence");
    assert.equal(H.statusPollInterval(false, false, "awaiting-login"), 2000,
        "boot confirmation and its result retain the fast cadence");
});

test("progress distinguishes compilation from measured downloads and handles old workers", () => {
    const deployment = {state: "building", progress: {schema: 1, active: true, step: "downloading",
        downloads: {doneBytes: 25e6, expectedBytes: 100e6, active: 2, totalKnown: true},
        builds: {done: 3, expected: 9, active: 0}, components: []}};
    let result = H.preparation(deployment);
    assert.equal(result.label, "Downloading packages");
    assert.equal(result.fraction, 0.25);
    deployment.progress.builds.active = 1;
    deployment.progress.components = ["window-manager"];
    result = H.preparation(deployment);
    assert.equal(result.label, "Compiling window manager");
    assert.equal(result.fraction, -1, "download bytes are not compilation completion");
    deployment.state = "validating";
    assert.equal(H.preparation(deployment).label, "Checking compatibility");
    assert.equal(H.preparation(deployment).fraction, -1);
    assert.equal(H.preparation({state:"discovering"}).label, "Preparing update sources");
    assert.equal(H.preparation({state:"building"}).fraction, -1);
});

test("unknown totals and malformed telemetry never produce a fake percentage or private label", () => {
    for (const progress of [null, {}, {schema:1, active:true, step:"secret module", components:["private url"],
        downloads:{active:1, doneBytes:10, expectedBytes:100}}, {schema:1, active:true, downloads:{active:1,
        doneBytes:200, expectedBytes:100, totalKnown:true}}, {schema:1, active:true,
        downloads:{active:1, doneBytes:-1, expectedBytes:NaN, totalKnown:true}, builds:{active:Infinity}}]) {
        const result = H.preparation({state:"building", progress});
        assert.equal(result.fraction, -1);
        assert.doesNotMatch(result.label, /private|secret/);
    }
    assert.equal(H.elapsed(294), "4:54");
    assert.equal(H.elapsed(3661), "1:01:01");
    assert.equal(H.elapsed(-1), "0:00");
    assert.equal(H.downloadSize(25e6), "25.0 MB");
});

test("source scope includes only confirmed and explicitly selected updates", () => {
    assert.equal(H.scope(available, ["upstream", "cybexos"]), "upstream");
    assert.equal(H.scope(available, ["cybexos"]), "");
    const both = { ...available, cybexos: { state: "available", available: "1.1.0" } };
    assert.equal(H.scope(both, ["upstream", "cybexos"]), "both");
    assert.equal(H.scope(both, ["cybexos"]), "cybexos");
});

test("an unpublished vendor channel is neutral and leaves NixOS updates selectable", () => {
    const sources = { ...available, cybexos: {state: "unpublished", installed: "1.0.0-beta.7"} };
    assert.equal(H.validSources(sources), true);
    assert.equal(H.scope(sources, ["upstream", "cybexos"]), "upstream");
    assert.equal(H.capabilities({state: "idle"}, false, true, H.scope(sources, ["upstream"])).prepare, true);
});

test("a machine ahead of its release channel is neutral and offers no Cybex OS update", () => {
    const sources = { ...available, cybexos: {state: "ahead", installed: "1.0.19", available: "1.0.17", channel: "stable"} };
    assert.equal(H.validSources(sources), true);
    assert.equal(H.scope(sources, ["upstream", "cybexos"]), "upstream");
    assert.equal(H.scope({ ...sources, upstream: {state: "current"} }, ["upstream", "cybexos"]), "");
    assert.equal(H.newerRelease({state: "ready", changeKind: "update", availableVersion: "1.0.16"}, sources), "",
        "the channel's older newest release is never offered as newer");
});

test("the release channel comes from status and is never guessed", () => {
    assert.equal(H.channel({channel: {selected: "beta", declared: "stable", override: true}}), "beta");
    assert.equal(H.channel({channel: {selected: "stable"}}), "stable");
    for (const value of [{}, {channel: {selected: ""}}, {channel: {selected: "nightly"}}, {channel: "beta"}, null])
        assert.equal(H.channel(value), "", JSON.stringify(value));
});

test("failed discovery, zero updates and completed history create no update badge", () => {
    for (const state of ["idle", "done", "failed", "interrupted", "ready", "recovery-failed"]) {
        assert.equal(H.indicator(false, state), false, state);
    }
    assert.equal(H.indicator(true, "idle"), true);
    assert.equal(H.indicator(true, "done"), true, "a later confirmed update survives older completed history");
    assert.equal(H.indicator(true, "awaiting-boot"), false);
});

test("a package hold survives reload and suppresses only its exact update candidate", () => {
    const held = {state: "failed", changeKind: "update", notPrebuilt: ["opencode-2.2.5"], inputs: {
        nixpkgs: {rev: "nixpkgs-revision"}, cybexos: {rev: "cybexos-revision"}}};
    const sources = {upstream: {state: "available", available: "nixpkgs-revision"}, cybexos: {state: "current"}};
    const reloaded = JSON.parse(JSON.stringify(held));
    assert.deepEqual(H.waitingPackages(reloaded), ["opencode-2.2.5"]);
    assert.equal(H.holdTarget(reloaded, sources), "same");
    assert.equal(H.indicator(true, held.state, H.holdTarget(held, sources)), false);
    for (const [name, source] of [["upstream", {state: "available", available: "new-nixpkgs"}],
        ["cybexos", {state: "available", revision: "new-cybexos"}], ["firmware", {state: "available"}]]) {
        const changed = H.holdTarget(held, {...sources, [name]: source});
        assert.equal(changed, "changed", name);
        assert.equal(H.indicator(true, held.state, changed), true, name);
    }
    assert.equal(H.holdTarget({...held, inputs: {}}, sources), "unknown");
    assert.equal(H.holdTarget(held, {}), "unknown");
    assert.equal(H.indicator(true, held.state, "unknown"), true, "unknown revisions never hide an update");
    for (const notPrebuilt of [null, [], "opencode", [null], [""]])
        assert.deepEqual(H.waitingPackages({...held, notPrebuilt}), []);
    for (const state of ["ready", "activating", "interrupted", "recovery-failed"])
        assert.deepEqual(H.waitingPackages({...held, state}), []);
});

test("a Nixpkgs that no longer works with Cybex OS holds the update like a package wait", () => {
    const details = {origin: "cybexos", file: "nix/modules/applications.nix",
        message: "brave has been removed from nixpkgs"};
    const held = JSON.parse(JSON.stringify({state: "failed", changeKind: "update", incompatible: details,
        inputs: {nixpkgs: {rev: "nixpkgs-revision"}, cybexos: {rev: "cybexos-revision"}}}));
    const sources = {upstream: {state: "available", available: "nixpkgs-revision"}, cybexos: {state: "current"}};
    assert.deepEqual(H.incompatible(held), details);
    assert.equal(H.held(held), true);
    assert.deepEqual(H.waitingPackages(held), []);
    assert.equal(H.holdTarget(held, sources), "same");
    assert.equal(H.page({...held, statusLoaded: true, sourcesLoaded: true, hasUpdates: true,
        waitingForPackages: H.held(held), holdTarget: "same"}), "waiting");
    // A release that may support it is shown and prepared again.
    const release = {...sources, cybexos: {state: "available", revision: "new-cybexos"}};
    assert.equal(H.holdTarget(held, release), "changed");
    assert.equal(H.autoPrepare(true, {prepare: true}, "failed", false, H.held(held), false), true);
    // A personal module that needs changing is the person's to fix.
    const personal = {...held, incompatible: {origin: "personal", file: "local/browser.nix"}};
    assert.equal(H.incompatible(personal), null);
    assert.equal(H.held(personal), false);
    assert.equal(H.holdTarget(personal, sources), "");
    for (const value of [null, "cybexos", {}, {origin: "other"}])
        assert.equal(H.held({...held, incompatible: value}), false);
    for (const changeKind of ["configuration", "software", undefined])
        assert.equal(H.held({...held, changeKind}), false, changeKind);
});

test("local kernel refusals remain actionable problems after reload", () => {
    const error = "The candidate would compile a Linux kernel (linux-image-7.3). Cybex OS requires stock prebuilt kernels.";
    for (const changeKind of ["configuration", "region", "maintenance", "software", undefined]) {
        const deployment = JSON.parse(JSON.stringify({state: "failed", changeKind,
            notPrebuilt: ["linux-image-7.3"], error,
            request: {id: "request", action: "stage", state: "failed", error},
            inputs: {nixpkgs: {rev: "new revision"}}}));
        const waitingForPackages = H.waitingPackages(deployment).length > 0;
        assert.equal(waitingForPackages, false, changeKind);
        assert.equal(H.holdTarget(deployment, available), "", changeKind);
        assert.equal(H.page({...deployment, statusLoaded: true, sourcesLoaded: true,
            hasUpdates: true, waitingForPackages}), "problem", changeKind);
        assert.equal(H.problem({...deployment, statusLoaded: true}), "failed");
    }
    const update = {state: "failed", changeKind: "update", notPrebuilt: ["linux-7.3"]};
    assert.equal(H.page({...update, statusLoaded: true,
        waitingForPackages: H.waitingPackages(update).length > 0}), "waiting",
        "an update whose stock kernel is not cached yet still waits");
});

test("a failed recovery blocks preparation and offers explicit restoration", () => {
    const capabilities = H.capabilities({ state: "recovery-failed", transaction: "failed" }, false, true, "upstream");
    assert.equal(H.active("recovery-failed"), false);
    assert.equal(capabilities.prepare, false);
    assert.equal(capabilities.apply, false);
    assert.equal(capabilities.rollback, true);
});

test("ready review cannot be accidentally restaged; apply is bound to its identity", () => {
    const value = { state: "ready", transaction: "id", reviewToken: "token" };
    assert.equal(H.capabilities(value, false, true, "both").prepare, false);
    assert.equal(H.capabilities(value, false, true, "both").apply, true);
    assert.equal(H.capabilities({ state: "ready" }, false, true, "both").apply, false);
    assert.equal(H.capabilities(value, true, true, "both").apply, false);
    assert.equal(H.capabilities(value, false, false, "both").apply, false);
});

test("boot, login and stale preview have separate next steps", () => {
    assert.equal(H.capabilities({ state: "awaiting-boot" }, false, true, "upstream").prepare, false);
    assert.equal(H.capabilities({ state: "awaiting-login" }, false, true, "upstream").confirm, true);
    const stale = H.capabilities({ state: "stale", transaction: "id" }, false, true, "upstream");
    assert.equal(stale.prepare, true);
    assert.equal(stale.apply, false);
    assert.equal(stale.discard, true);
});

test("queued requests and unknown worker liveness block duplicate operations", () => {
    for (const state of ["queued", "running", "unknown"]) assert.equal(H.pending({ state }), true);
    for (const state of ["done", "failed"]) assert.equal(H.pending({ state }), false);
    for (const state of ["discovering", "building", "validating", "activating", "recovering"]) {
        assert.equal(H.capabilities({ state }, false, true, "upstream").prepare, false);
    }
});

test("unknown and malformed helper responses never become a reviewable plan", () => {
    for (const value of [null, {}, {upstream: {}, cybexos: {}}, {upstream: {state: "available"}, cybexos: {state:"current"}}]) {
        assert.equal(!!H.validSources(value), false);
    }
    assert.equal(H.validSources(available), true);
    assert.equal(H.validDeployment({ state: "idle" }), true);
    assert.equal(!!H.validDeployment({ state: "ready" }), false);
    assert.equal(H.validDeployment({ state: "ready", transaction: "a".repeat(32), reviewToken: "b".repeat(64),
        changes: "app: 1 → 2", packageChanges: [] }), true);
});

test("Control Center keeps pending system changes and errors reachable without a badge", () => {
    assert.equal(H.overviewVisible(false, { state: "idle" }, ""), false);
    assert.equal(H.overviewVisible(false, { state: "idle" }, "Failed to check"), true);
    assert.equal(H.overviewVisible(false, { state: "ready" }, ""), true);
    assert.equal(H.overviewVisible(false, { state: "awaiting-login" }, ""), true);
});

test("finished failures can be dismissed; a pending generation cannot", () => {
    for (const state of ["failed", "interrupted", "rolled-back"])
        assert.equal(H.capabilities({ state, transaction: "id" }, false, true, "").discard, true, state);
    for (const state of ["awaiting-boot", "awaiting-login", "recovery-failed", "done", "idle"])
        assert.equal(H.capabilities({ state, transaction: "id" }, false, true, "").discard, false, state);
});

const base = { statusLoaded: true, sourcesLoaded: true, hasUpdates: false, error: "", state: "idle",
    request: {}, automatic: { prepare: true, confirm: true } };
const page = values => H.page({ ...base, ...values });

test("Software Update shows one page per worker state, ahead of discovery", () => {
    assert.equal(page({ statusLoaded: false }), "checking");
    assert.equal(page({ statusLoaded: false, statusError: "no helper" }), "problem");
    assert.equal(page({ sourcesLoaded: false }), "checking");
    assert.equal(page({}), "current");
    assert.equal(page({ state: "done" }), "current");
    assert.equal(page({ hasUpdates: true }), "available");
    assert.equal(page({ hasUpdates: true, state: "done" }), "available", "a later update follows completed history");
    for (const state of ["discovering", "building", "validating"])
        assert.equal(page({ state, hasUpdates: true }), "preparing");
    assert.equal(page({ state: "ready", sourcesLoaded: false }), "ready", "a prepared update survives unknown discovery");
    assert.equal(page({ state: "activating" }), "installing");
    assert.equal(page({ state: "awaiting-boot", hasUpdates: true }), "restart");
    assert.equal(page({ state: "recovering" }), "recovering");
    assert.equal(page({ state: "unavailable" }), "unavailable");
    for (const state of ["failed", "interrupted", "stale", "rolled-back", "recovery-failed"])
        assert.equal(page({ state, hasUpdates: true }), "problem", state);
    assert.equal(page({ error: "offline" }), "problem");
    assert.equal(page({ error: "offline", hasUpdates: true }), "available", "a reachable update outranks another source's error");
});

test("queued requests show their action before the worker reports a phase", () => {
    assert.equal(page({ request: { state: "queued", action: "stage" } }), "preparing");
    assert.equal(page({ state: "ready", request: { state: "queued", action: "apply" } }), "installing");
    assert.equal(page({ state: "awaiting-login", request: { state: "running", action: "confirm" } }), "finishing");
    assert.equal(page({ state: "recovery-failed", request: { state: "queued", action: "rollback" } }), "recovering");
    assert.equal(page({ state: "ready", request: { state: "queued" }, requestAction: "apply" }), "installing");
    assert.equal(page({ state: "ready", request: { state: "queued", action: "discard" } }), "ready");
    assert.equal(page({ state: "ready", request: { state: "failed", action: "apply" } }), "ready");
});

test("NixOS packages NixOS hasn't built yet read as up to date until something is installable", () => {
    const held = {state: "failed", changeKind: "update", notPrebuilt: ["codex-0.167.0"], inputs: {
        nixpkgs: {rev: "nixpkgs-revision"}, cybexos: {rev: "cybexos-revision"}}};
    const sources = {upstream: {state: "available", available: "nixpkgs-revision"}, cybexos: {state: "current"}};
    assert.equal(H.quietHold(held, sources, H.holdTarget(held, sources)), true);
    assert.equal(H.quietHold(held, null, H.holdTarget(held, null)), true, "before the first check");
    // A release, firmware or newer packages are still updates to offer.
    for (const changed of [{...sources, cybexos: {state: "available", revision: "cybexos-revision"}},
        {...sources, upstream: {state: "available", available: "newer-nixpkgs"}},
        {...sources, firmware: {state: "available"}}])
        assert.equal(H.quietHold(held, changed, H.holdTarget(held, changed)), false);
    // Waiting for a Cybex OS release that supports the packages is explained.
    const incompatible = {...held, notPrebuilt: null, incompatible: {origin: "cybexos", message: "gone"}};
    assert.equal(H.quietHold(incompatible, sources, H.holdTarget(incompatible, sources)), false);
    assert.equal(H.quietHold({...held, state: "ready"}, sources, "same"), false);
    const quiet = {state: "failed", waitingForPackages: true, quietHold: true, holdTarget: "same", hasUpdates: false};
    assert.equal(page({...quiet, sourcesLoaded: true}), "current");
    assert.equal(page({...quiet, sourcesLoaded: false}), "checking");
    assert.equal(page({...quiet, sourcesLoaded: true, request: {state: "queued", action: "stage"}}), "preparing");
    assert.equal(H.overviewVisible(false, {request: null}, ""), false);
});

test("prebuilt refusals wait without masking an active worker or a changed candidate", () => {
    const held = {state: "failed", waitingForPackages: true, holdTarget: "same", hasUpdates: true};
    assert.equal(page(held), "waiting");
    assert.equal(page({...held, sourcesLoaded: false, holdTarget: "unknown"}), "waiting");
    assert.equal(page({...held, holdTarget: "changed"}), "available");
    assert.equal(page({...held, request: {state: "queued", action: "stage"}}), "preparing");
    assert.equal(page({...held, state: "activating"}), "installing");
    assert.equal(page({...held, state: "recovering"}), "recovering");
    assert.equal(H.capabilities({state: "failed"}, false, true, "upstream").prepare, true,
        "an explicit check remains available while waiting");
});

test("keeping a trial boot names the version running and the one Go back returns to", () => {
    const release = { scope: "both", installedVersion: "1.0.25", availableVersion: "1.0.26" };
    assert.deepEqual(H.trialVersions(release), { id: "cybexos", now: "1.0.26", before: "1.0.25" });
    const packages = { scope: "upstream", installedVersion: "1.0.25", availableVersion: "1.0.25", highlights: { schema: 1,
        components: [{ id: "kernel", before: "6.12.55", after: "6.12.58" },
            { id: "nixos", before: "26.05.20261024.abc", after: "26.05.20261027.def" }] } };
    assert.deepEqual(H.trialVersions(packages), { id: "nixos", now: "26.05.20261027.def", before: "26.05.20261024.abc" },
        "NixOS before the kernel; an unchanged Cybex OS is no identity");
    assert.deepEqual(H.trialVersions({ highlights: { schema: 1, components: [{ id: "kernel", before: "6.12.55", after: "6.12.58" }] } }),
        { id: "kernel", now: "6.12.58", before: "6.12.55" });
    assert.equal(H.trialVersions({ state: "awaiting-login", transaction: "a" }), null, "an older record names none");
    assert.equal(H.trialVersions(null), null);
    const view = require("node:fs").readFileSync(require("node:path").join(require("./shell.cjs").shellDir,
        "SoftwareUpdate/UpdateView.qml"), "utf8");
    assert.match(view, /readonly property var trial: page === "confirm" \? Helpers\.trialVersions\(deployment\) : null/);
    assert.match(view, /I18n\.tr\("This version"\)[\s\S]*?I18n\.tr\("Previous version"\)/);
    assert.match(view, /I18n\.tr\("Keep this version"\)/);
    assert.match(view, /I18n\.tr\("Go back to the previous version"\)/);
});

test("Software Update's buttons and labels are in sentence case", () => {
    const fs = require("node:fs"), path = require("node:path"), { shellDir } = require("./shell.cjs");
    for (const name of ["UpdateView.qml", "ReadyPage.qml", "TechnicalDetails.qml", "WhatsNewPage.qml", "StatusPage.qml"]) {
        const source = fs.readFileSync(path.join(shellDir, "SoftwareUpdate", name), "utf8");
        for (const [, text] of source.matchAll(/I18n\.tr\("([^"]+)"\)/g)) {
            const names = text.replace(/Cybex OS|NixOS|Linux|Wiz|NVIDIA|Flathub|Wi-Fi|Bluetooth|Mesa|Hyprland|OK/g, "");
            for (const sentence of names.split(/[.?!:]\s+/)) {
                const words = sentence.trim().split(/\s+/).slice(1);
                assert.ok(!words.some(word => /^[A-Z][a-z]/.test(word)), `${name}: "${text}"`);
            }
        }
    }
});

test("a trial boot is confirmed automatically unless that failed or is switched off", () => {
    assert.equal(page({ state: "awaiting-login" }), "finishing");
    assert.equal(page({ state: "awaiting-login", automatic: { prepare: true, confirm: false } }), "confirm");
    assert.equal(page({ state: "awaiting-login", automatic: undefined }), "confirm", "an older status asks");
    const failed = { state: "failed", action: "confirm", error: "Hyprland health failed" };
    assert.equal(page({ state: "awaiting-login", request: failed }), "confirm");
    assert.equal(H.confirmFailed("awaiting-login", failed), true);
    assert.equal(H.confirmFailed("awaiting-login", { ...failed, action: "stage" }), false);
    assert.equal(H.problem({ statusLoaded: true, state: "rolled-back" }), "rolled-back");
    assert.equal(H.problem({ statusLoaded: true, state: "idle" }), "check");
    assert.equal(H.problem({ statusLoaded: false }), "status");
});

test("background preparation is requested for each new target, never over a person's work", () => {
    const sources = { upstream: { state: "available", available: "a" }, cybexos: { state: "current", available: "1.0.0" } };
    assert.equal(H.targetKey(sources, "lock"), JSON.stringify(["lock", "a", "", []]));
    assert.notEqual(H.targetKey(sources, "lock"), H.targetKey(sources, "other lock"));
    assert.equal(H.autoPrepare(true, { prepare: true }, "idle", false), true);
    assert.equal(H.autoPrepare(true, { prepare: true }, "done", false), true);
    assert.equal(H.autoPrepare(true, { prepare: false }, "idle", false), false);
    assert.equal(H.autoPrepare(false, { prepare: true }, "idle", false), false);
    assert.equal(H.autoPrepare(true, { prepare: true }, "idle", true), false);
    assert.equal(H.autoPrepare(true, { prepare: true }, "failed", false, true), true,
        "a package hold can request the bounded background check without being dismissed");
    assert.equal(H.autoPrepare(true, { prepare: true }, "failed", true, true), false);
    for (const state of ["ready", "stale", "failed", "rolled-back", "awaiting-boot", "building"])
        assert.equal(H.autoPrepare(true, { prepare: true }, state, false), false, state);
    // A prepared update may be prepared again; the unit decides whether.
    assert.equal(H.autoPrepare(true, { prepare: true }, "ready", false, false, true), true);
    assert.equal(H.autoPrepare(true, { prepare: true }, "ready", true, false, true), false);
    assert.equal(H.autoPrepare(true, { prepare: false }, "ready", false, false, true), false);
    assert.equal(H.autoPrepare(true, { prepare: true }, "stale", false, false, true), false);
});

test("a prepared update stays installable while preparing it again does not finish", () => {
    const prepared = { state: "ready", changeKind: "update", scope: "both", availableVersion: "1.0.1" };
    assert.equal(H.preparedUpdate(prepared), true);
    for (const value of [{ ...prepared, changeKind: "software" }, { ...prepared, scope: "firmware" },
                         { ...prepared, scope: "local" }, { ...prepared, state: "stale" }, undefined])
        assert.equal(H.preparedUpdate(value), false, JSON.stringify(value));
    const failed = { ...prepared, replacement: { state: "failed", version: "1.0.2", scope: "both", error: "No network.",
        requestId: "r" }, request: { id: "r", state: "failed", error: "No network." } };
    assert.deepEqual(H.replacement(failed, "1.0.2"), { state: "failed", error: "No network.", version: "1.0.2", scope: "both" });
    assert.equal(H.replacement(failed, "1.0.3"), null, "an attempt for an older release is not shown");
    assert.equal(H.replacement(failed, ""), null);
    const packages = { ...prepared, replacement: { state: "waiting", version: "1.0.1", scope: "both" } };
    assert.equal(H.replacement(packages, "").state, "waiting", "a packages-only attempt");
    assert.equal(H.replacement({ ...packages, scope: "upstream", replacement: { state: "failed", version: null } }, "").scope,
        "upstream");
    assert.equal(H.replacement({ ...failed, replacement: { ...failed.replacement, state: "done" } }, "1.0.2"), null);
    assert.equal(H.replacement({ ...failed, changeKind: "software" }, "1.0.2"), null);
    assert.equal(H.replacementRequest(failed), true, "the review reports the attempt, not a generic failure");
    assert.equal(H.replacementRequest({ ...failed, request: { id: "other", state: "failed" } }), false);
    assert.equal(H.replacementRequest({ ...failed, state: "failed" }), false);
    assert.equal(H.replacementRequest(prepared), false);
});

test("versions read as people expect: NixOS builds and firmware as dates", () => {
    assert.deepEqual(H.versionParts("nixos", "26.05.20261024.abcdef1"), { text: "26.05", date: "2026-10-24" });
    assert.deepEqual(H.versionParts("nixos", "26.11pre.20261024.abcdef1"), { text: "26.11", date: "2026-10-24" });
    assert.deepEqual(H.versionParts("firmware", "20261014"), { text: "", date: "2026-10-14" });
    assert.deepEqual(H.versionParts("tool", "0-unstable-2026-10-01"), { text: "", date: "2026-10-01" });
    assert.deepEqual(H.versionParts("kernel", "6.12.58"), { text: "6.12.58", date: "" });
    assert.deepEqual(H.versionParts("tool", "20261399"), { text: "20261399", date: "" }, "not a date");
    assert.deepEqual(H.versionParts("kernel", null), { text: "", date: "" });
});

test("the review groups components, apps and tools, falling back to package changes", () => {
    const highlights = { schema: 1, components: [{ id: "kernel", before: "6.12.55", after: "6.12.58" }],
        apps: [{ name: "firefox", title: "Firefox", icon: "firefox", kind: "updated", before: "1", after: "2" }],
        tools: [], background: 213, sizeChange: 40e6 };
    const review = H.summary({ highlights });
    assert.equal(review.components[0].id, "kernel");
    assert.equal(review.apps[0].title, "Firefox");
    assert.equal(review.background, 213);
    const older = H.summary({ packageChanges: [{ name: "hello", kind: "updated", before: "1", after: "2", oldPath: "/nix/store/x" },
        { name: "same", kind: "rebuilt", before: "1", after: "1" }] });
    assert.deepEqual(older.tools, [{ name: "hello", kind: "updated", before: "1", after: "2" }]);
    assert.deepEqual(H.summary({}).components, []);
    for (const id of Object.keys(H.COMPONENTS))
        assert.ok(H.component(id).label && H.component(id).detail && H.component(id).glyph, id);
    assert.equal(H.component("unknown").label, "unknown");
});

test("a Cybex OS release published after an update was prepared is offered, once and only for updates", () => {
    const prepared = { state: "ready", changeKind: "update", scope: "upstream", availableVersion: "1.0.1" };
    const found = version => ({ upstream: { state: "available" }, cybexos: { state: "available", available: version } });
    assert.equal(H.newerRelease(prepared, found("1.0.2")), "1.0.2");
    assert.equal(H.newerRelease({ ...prepared, scope: "both", availableVersion: "1.0.2" }, found("1.0.2")), "",
        "the prepared update already has it");
    assert.equal(H.newerRelease(prepared, found("1.0.1")), "");
    assert.equal(H.newerRelease({ ...prepared, availableVersion: "1.0.3" }, found("1.0.2")), "", "never an older release");
    assert.equal(H.newerRelease(prepared, found("1.0.2-beta.1")), "1.0.2-beta.1");
    assert.equal(H.newerRelease({ ...prepared, availableVersion: "1.0.2-beta.3" }, found("1.0.2-rc.1")), "1.0.2-rc.1");
    assert.equal(H.newerRelease({ ...prepared, availableVersion: "1.0.2-rc.1" }, found("1.0.2")), "1.0.2");
    assert.equal(H.newerRelease({ ...prepared, availableVersion: "1.0.10" }, found("1.0.9")), "", "numeric, not text, order");
    // A Software or configuration change keeps its own selection; the
    // offer is only for prepared updates that are still awaiting review.
    for (const changeKind of ["software", "configuration", "region", "maintenance"])
        assert.equal(H.newerRelease({ ...prepared, changeKind }, found("1.0.2")), "", changeKind);
    for (const state of ["idle", "building", "awaiting-boot", "stale", "failed"])
        assert.equal(H.newerRelease({ ...prepared, state }, found("1.0.2")), "", state);
    assert.equal(H.newerRelease(prepared, { cybexos: { state: "current", available: "1.0.2" } }), "");
    assert.equal(H.newerRelease(prepared, { cybexos: { state: "available", available: "next" } }), "");
    assert.equal(H.newerRelease({ ...prepared, availableVersion: "" }, found("1.0.2")), "");
    assert.equal(H.newerRelease(undefined, undefined), "");
});

test("release notes, sizes and labels stay short and honest", () => {
    assert.deepEqual(H.noteItems("## Highlights\n- One\n* Two\n\n1. Three\n• Four", 3), { items: ["One", "Two", "Three"], more: true });
    assert.deepEqual(H.noteItems(""), { items: [], more: false });
    // GitHub release notes: wrapped Markdown items stay whole, inline markup is text.
    const notes = "# Cybex OS 1.0.1\n\nThe first published release.\n\n## Updates\n\n"
        + "- **Keyless releases.** A release is a published GitHub release of\n  `CybexHQ/CybexOS`. See\n"
        + "  [the guide](https://example.com/releasing).\n- *Health* judges what changes; xps_speaker_tuning\n"
        + "  and 2 * 3 stay as written.\n\n1) Settings \u2192 Sudo\n+ ![logo](https://example.com/logo.png)";
    assert.deepEqual(H.noteItems(notes, 10), { items: [
        "The first published release.",
        "Keyless releases. A release is a published GitHub release of CybexHQ/CybexOS. See the guide.",
        "Health judges what changes; xps_speaker_tuning and 2 * 3 stay as written.",
        "Settings \u2192 Sudo"], more: false });
    assert.equal(H.noteItems(notes, 2).more, true);
    assert.equal(H.sizeChange(40e6), "+40 MB");
    assert.equal(H.sizeChange(-2.04e9), "\u22122.0 GB");
    assert.equal(H.sizeChange(1000), "", "a rounding error is not a size change");
});

test("Wiz shows each status page in the pose language every surface shares", () => {
    const pose = (page, problem = "check", confirmFailed = false, kept = false) =>
        H.statusPose(page, problem, confirmFailed, kept).pose;
    assert.equal(pose("checking"), "thinking");
    assert.equal(pose("current"), "happy");
    assert.equal(pose("current", "check", false, true), "finished", "a kept release celebrates");
    assert.equal(pose("whats-new"), "finished");
    assert.deepEqual(H.statusPose("available", "check", false, false), { pose: "idle", unread: true },
        "something new is idle with the unread pip");
    for (const page of ["preparing", "installing", "recovering"])
        assert.equal(pose(page), "working", page);
    assert.equal(pose("restart"), "needs-input", "restart and shut down are the person's move");
    assert.equal(pose("waiting"), "needs-input", "an unavailable package waits rather than signalling failure");
    assert.equal(pose("finishing"), "thinking");
    assert.equal(pose("confirm"), "listening", "Does everything work? asks");
    assert.equal(pose("confirm", "check", true), "needs-input", "a failed confirmation waits for a decision");
    for (const problem of ["rolled-back", "failed", "recovery-failed", "check", "status"])
        assert.equal(pose("problem", problem), "sorry", problem);
    for (const problem of ["interrupted", "stale"])
        assert.equal(pose("problem", problem), "needs-input", problem);
    assert.equal(pose("unavailable"), "asleep");
    const states = load("WizRig.js").STATES;
    for (const page of ["checking", "current", "available", "preparing", "installing", "restart", "finishing",
        "confirm", "recovering", "problem", "unavailable", "whats-new", "ready", "waiting"]) {
        const value = H.statusPose(page, "check", false, false);
        assert.ok(states.includes(value.pose), page + ": " + value.pose);
        assert.equal(value.unread, page === "available", page);
    }
});

test("the review of a prepared update and its toasts stay free of Wiz", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const { shellDir } = require("./shell.cjs");
    const read = name => fs.readFileSync(path.join(shellDir, name), "utf8");
    assert.doesNotMatch(read("SoftwareUpdate/ReadyPage.qml"), /Wiz\b/);
    assert.doesNotMatch(read("Bar/Modules/Updates.qml"), /Wiz\b/);
    assert.match(read("SoftwareUpdate/StatusPage.qml"), /AssistantUi\.Wiz \{/);
    assert.match(read("SoftwareUpdate/WhatsNewPage.qml"), /AssistantUi\.Wiz \{/);
});

const keptRecord = { state: "done", changeKind: "update", scope: "cybexos", transaction: "a".repeat(32),
    installedVersion: "1.0.0-beta.20", availableVersion: "1.0.0-beta.21", notes: "## Highlights\n- Wiz",
    highlights: { schema: 1, components: [{ id: "cybexos", before: "1.0.0-beta.20", after: "1.0.0-beta.21" },
        { id: "kernel", before: "6.12.55", after: "6.12.58" }], apps: [], tools: [], background: 3, sizeChange: 0 } };

test("a kept Cybex OS release keeps its notes and important changes", () => {
    const kept = H.keptRelease(keptRecord);
    assert.equal(kept.version, "1.0.0-beta.21");
    assert.equal(kept.previous, "1.0.0-beta.20");
    assert.equal(kept.notes, "## Highlights\n- Wiz");
    assert.deepEqual(kept.components.map(row => row.id), ["cybexos", "kernel"]);
    assert.equal(H.keptRelease({ ...keptRecord, scope: "both" }).version, "1.0.0-beta.21");
    assert.deepEqual(H.keptRelease({ ...keptRecord, highlights: null, notes: undefined }).components, [],
        "a record without highlights still has its What's New");
});

test("only a kept new Cybex OS version is a release; NixOS packages alone are just up to date", () => {
    assert.equal(H.keptRelease({ ...keptRecord, scope: "upstream", availableVersion: "1.0.0-beta.20" }), null);
    assert.equal(H.keptRelease({ ...keptRecord, availableVersion: "1.0.0-beta.20" }), null, "same version");
    assert.equal(H.keptRelease({ ...keptRecord, scope: "firmware" }), null,
        "a later firmware-only update keeps the older version fields");
    for (const state of ["ready", "activating", "awaiting-boot", "awaiting-login", "rolled-back", "failed", "idle"])
        assert.equal(H.keptRelease({ ...keptRecord, state }), null, state);
    for (const changeKind of ["configuration", "software", "region", "maintenance", undefined])
        assert.equal(H.keptRelease({ ...keptRecord, changeKind }), null, String(changeKind));
    assert.equal(H.keptRelease({ ...keptRecord, availableVersion: "" }), null);
    assert.equal(H.keptRelease(null), null);
    assert.equal(H.keptRelease({}), null);
});

test("each kept release is announced once", () => {
    const kept = H.keptRelease(keptRecord);
    assert.equal(H.announce(kept, ""), true);
    assert.equal(H.announce(kept, "1.0.0-beta.20"), true, "an older release was announced");
    assert.equal(H.announce(kept, "1.0.0-beta.21"), false);
    assert.equal(H.announce(null, ""), false);
});

test("release notes render as Markdown that never fetches anything", () => {
    const notes = "## Highlights\n- **Wiz** joins Software Update ![wiz](https://example.com/wiz.png)\n"
        + "- See [the docs](https://example.com/docs) or <https://example.com/x>\n"
        + "<img src=\"https://example.com/track.gif\"><b>bold</b>\n![ref][logo]\n\n[logo]: https://example.com/logo.png";
    const value = H.releaseNotes(notes);
    assert.doesNotMatch(value, /wiz\.png|track\.gif|<img|<b>|!\[/);
    assert.match(value, /^#### Highlights\n- \*\*Wiz\*\* joins Software Update/,
        "headings stay under the page's own heading");
    assert.equal(H.releaseNotes("# One\n### Three\n####### seven\n#hashtag"), "#### One\n#### Three\n####### seven\n#hashtag");
    assert.match(value, /\[the docs\]\(https:\/\/example\.com\/docs\)/);
    assert.match(value, /\[https:\/\/example\.com\/x\]\(https:\/\/example\.com\/x\)/, "an autolink stays a link");
    assert.equal(H.releaseNotes(""), "");
    assert.equal(H.releaseNotes(undefined), "");
});
