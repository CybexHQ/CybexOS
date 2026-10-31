// Software's logic without Qt: catalogue queries, the install queue and the
// one system change it becomes, and how a deployment reads as an install.
// Views translate; nothing here returns English text.

// Arrays from status snapshots can arrive as array-likes; never trust
// Array.isArray or concat with them.
function list(value) {
    if ((Array.isArray(value) || value instanceof Array))
        return value;
    return value && typeof value === "object" && typeof value.length === "number"
        ? Array.prototype.slice.call(value) : [];
}

// ---- catalogue -------------------------------------------------------------

function index(rows, key) {
    const result = {};
    for (const row of rows || [])
        if (row && row[key] !== undefined && !(row[key] in result))
            result[row[key]] = row;
    return result;
}

function byPopularity(a, b) {
    return (Number(b.installs) || 0) - (Number(a.installs) || 0)
        || String(a.name || "").localeCompare(String(b.name || ""));
}

function popular(apps, limit) {
    const rows = (apps || []).slice().sort(byPopularity);
    return limit ? rows.slice(0, limit) : rows;
}

// A category's apps, most popular first; "" lists the whole catalogue.
function inCategory(apps, category, subcategory) {
    return popular((apps || []).filter(app => (!category || app.category === category)
        && (!subcategory || app.subcategory === subcategory)));
}

function featured(apps, ids) {
    const byId = index(apps, "id");
    return (ids || []).map(id => byId[id]).filter(app => !!app);
}

// Editor's choice for a category: its featured apps, then its most popular.
function editorsChoice(apps, ids, category, subcategory, count) {
    const wanted = count || 3;
    const pool = inCategory(apps, category, subcategory);
    const picked = featured(pool, ids);
    for (const app of pool) {
        if (picked.length >= wanted)
            break;
        if (!picked.includes(app))
            picked.push(app);
    }
    return picked.slice(0, wanted);
}

// Same subcategory first, then the same category; never the app itself.
function similar(apps, app, count) {
    if (!app)
        return [];
    const others = (apps || []).filter(other => other.id !== app.id && other.category === app.category);
    const close = popular(others.filter(other => other.subcategory === app.subcategory));
    const rest = popular(others.filter(other => other.subcategory !== app.subcategory));
    return close.concat(rest).slice(0, count || 4);
}

function profileApps(profile, byId) {
    return ((profile || {}).apps || []).map(id => (byId || {})[id]).filter(app => !!app);
}

// Apps a collection's "Install all" would add, and their known download.
function collection(profile, byId) {
    const apps = profileApps(profile, byId);
    const missing = apps.filter(app => !app.installed && !app.unavailable);
    return {
        apps: apps,
        missing: missing,
        downloadBytes: missing.reduce((sum, app) => sum + (Number(app.downloadBytes) || 0), 0),
        vendor: missing.some(app => !app.free)
    };
}

function terms(query) {
    return String(query || "").toLocaleLowerCase().split(/\s+/).filter(term => term !== "");
}

// Catalogue apps for a query, ranked by name, then the rest of the text.
function searchApps(apps, categories, query, limit) {
    const wanted = terms(query);
    if (wanted.length === 0)
        return [];
    const names = {};
    for (const category of categories || [])
        names[category.id] = String(category.name || "");
    const phrase = wanted.join(" ");
    const scored = [];
    for (const app of apps || []) {
        const name = String(app.name || "").toLocaleLowerCase();
        const text = [app.name, app.summary, app.developer, names[app.category] || "", app.attribute]
            .join(" ").toLocaleLowerCase();
        if (!wanted.every(term => text.includes(term)))
            continue;
        const score = name === phrase ? 0 : name.startsWith(phrase) ? 1
            : wanted.every(term => name.includes(term)) ? 2 : 3;
        scored.push({ app: app, score: score });
    }
    scored.sort((a, b) => a.score - b.score || byPopularity(a.app, b.app));
    return scored.slice(0, limit || 60).map(row => row.app);
}

// Full-Nixpkgs results that are not already shown as catalogue apps.
function morePackages(results, apps) {
    const shown = index(apps, "attribute");
    return (results || []).filter(row => row && !(row.attribute in shown));
}

// ---- installed -------------------------------------------------------------

// Apps first: catalogue entries and packages with desktop entries, grouped
// by who installed them. Packages without entries go under "other".
function installedGroups(catalogue) {
    const value = catalogue || {};
    const apps = (value.apps || []).filter(app => app.installed);
    const claimed = {};
    for (const app of apps)
        for (const id of app.desktopIds || [])
            claimed[id] = true;
    const groups = { software: [], cybexos: [], personal: [], other: [] };
    const add = (owner, row) => (groups[owner] || groups.cybexos).push(row);
    for (const app of apps)
        add(app.owner || "cybexos", { key: "app:" + app.id, app: app, name: app.name, attribute: app.attribute,
            desktopIds: app.desktopIds || [], icon: "", version: app.installedVersion || app.version || "",
            owner: app.owner || "cybexos" });
    for (const pkg of value.packages || []) {
        const entries = (pkg.apps || []).filter(entry => !claimed[entry.id]);
        const attribute = (pkg.attributes || [])[0] || "";
        if ((pkg.apps || []).length > 0 && entries.length === 0)
            continue;
        if (entries.length === 0) {
            groups.other.push({ key: "pkg:" + pkg.path, app: null, name: pkg.name, attribute: attribute,
                desktopIds: [], icon: "", version: pkg.version || "", owner: pkg.owner || "cybexos",
                description: pkg.description || "" });
            continue;
        }
        for (const entry of entries)
            claimed[entry.id] = true;
        add(pkg.owner || "cybexos", { key: "pkg:" + pkg.path + ":" + entries[0].id, app: null,
            name: entries[0].name, attribute: attribute, desktopIds: entries.map(entry => entry.id),
            icon: entries[0].icon || "", version: pkg.version || "", owner: pkg.owner || "cybexos",
            description: pkg.description || "" });
    }
    const byName = (a, b) => String(a.name).localeCompare(String(b.name));
    for (const name of Object.keys(groups))
        groups[name].sort(byName);
    return groups;
}

// An installed inventory package for this attribute, if Software chose it.
function selectedPackage(catalogue, attribute) {
    return ((catalogue || {}).packages || []).find(pkg => (pkg.attributes || []).includes(attribute)) || null;
}

// ---- the install queue -----------------------------------------------------

function queued(queue, attribute) {
    const item = (queue || []).find(row => row.attribute === attribute);
    return item ? item.action : "";
}

// Adds an install or removal, or takes the same request back off the list.
function toggle(queue, item) {
    const rows = (queue || []).filter(row => row.attribute !== item.attribute);
    return queued(queue, item.attribute) === item.action ? rows : rows.concat([item]);
}

function withAll(queue, items) {
    let rows = (queue || []).slice();
    for (const item of items || [])
        if (!queued(rows, item.attribute))
            rows = rows.concat([item]);
    return rows;
}

function installs(queue) {
    return (queue || []).filter(row => row.action === "install");
}

function removals(queue) {
    return (queue || []).filter(row => row.action === "remove");
}

// After a refresh: drop requests the machine already satisfies, such as an
// install another session made or a removal of something no longer chosen.
function prune(queue, catalogue) {
    const desired = new Set((catalogue || {}).desired || []);
    const byAttribute = index((catalogue || {}).apps, "attribute");
    return (queue || []).filter(row => row.action === "install"
        ? !desired.has(row.attribute) && !((byAttribute[row.attribute] || {}).installed)
        : desired.has(row.attribute));
}

// The declaration Software stages: today's choices plus installs, minus removals.
function change(desired, queue) {
    const previous = (desired || []).slice().sort();
    const wanted = new Set(previous);
    for (const row of queue || []) {
        if (row.action === "install")
            wanted.add(row.attribute);
        else if (row.action === "remove")
            wanted.delete(row.attribute);
    }
    return { packages: Array.from(wanted).sort(), previous: previous };
}

// What the queue would download and whether checks cleared it. A check's
// exact plan wins over the catalogue's estimate; vendor downloads come
// from their vendor and have no NixOS size.
function queueState(queue, byAttribute, checks) {
    const rows = installs(queue);
    let bytes = 0;
    let pending = 0;
    const blocked = [];
    let vendor = 0;
    for (const row of rows) {
        const result = (checks || {})[row.attribute];
        const app = (byAttribute || {})[row.attribute];
        if (result && result.vendor || app && app.free === false)
            vendor++;
        if (!result || result.state === "checking")
            pending++;
        else if (result.state !== "prebuilt")
            blocked.push(row.attribute);
        bytes += result && typeof result.downloadBytes === "number" ? result.downloadBytes
            : app && typeof app.downloadBytes === "number" ? app.downloadBytes : 0;
    }
    return {
        count: (queue || []).length, installs: rows.length, removals: removals(queue).length,
        downloadBytes: bytes, vendor: vendor, blocked: blocked,
        state: blocked.length > 0 ? "blocked" : pending > 0 ? "checking" : "prebuilt"
    };
}

// One app's verdict from a check result's packages.
function verdict(result, attribute) {
    const row = ((result || {}).packages || {})[attribute];
    if (!row)
        return null;
    return { state: row.state, reason: row.reason || "", compiles: row.compiles || [],
        vendor: row.vendor === true, version: row.version || "" };
}

// ---- following the system change ------------------------------------------

var PREPARING = ["discovering", "building", "validating"];
var FINISHED = ["awaiting-boot", "awaiting-login", "done"];
var FAILED = ["failed", "interrupted", "stale", "rolled-back", "recovery-failed"];

// Whether a deployment is this Software session's change. After a shell
// restart there is no request ID; an unfinished software change is adopted.
function owns(deployment, requestId) {
    const value = deployment || {};
    if (value.changeKind !== "software")
        return false;
    if (requestId)
        return value.requestId === requestId;
    return PREPARING.concat(["ready", "activating"]).includes(value.state);
}

// The phase the queue bar shows. `local` is Software's own step before the
// worker reports: checking, blocked, authorizing or submitted.
function phase(local, deployment, owned, request) {
    const state = (deployment || {}).state || "idle";
    if (owned) {
        if (PREPARING.includes(state)) return "preparing";
        if (state === "ready") return "ready";
        if (state === "activating") return "installing";
        if (FINISHED.includes(state)) return "done";
        if (FAILED.includes(state)) return "failed";
    }
    if ((request || {}).state === "failed")
        return "failed";
    if (local === "submitted")
        return "preparing";
    return local || "idle";
}

// What blocks a new change, if anything: an unfinished restart, another
// change in progress or awaiting review, or no updater (the live system).
function blocked(m) {
    const value = m || {};
    const deployment = value.deployment || {};
    const state = deployment.state || "idle";
    if (value.available === false || deployment.available === false)
        return "unavailable";
    if (value.owned)
        return "";
    if (value.rebootRecommended || ["awaiting-boot", "awaiting-login", "recovery-failed"].includes(state))
        return "restart";
    if (value.runActive || PREPARING.concat(["activating", "recovering", "firmware"]).includes(state))
        return "busy";
    if (["ready", "stale"].includes(state))
        return "pending";
    return "";
}

// Installs and removals a staged software change makes.
function changed(deployment) {
    const software = (deployment || {}).software || {};
    const before = new Set(list(software.previous));
    const after = new Set(list(software.packages));
    return {
        installs: Array.from(after).filter(name => !before.has(name)).sort(),
        removals: Array.from(before).filter(name => !after.has(name)).sort()
    };
}

// Download progress from the worker's telemetry; -1 when unmeasurable.
function progress(deployment) {
    const value = (deployment || {}).progress;
    const count = n => Number.isSafeInteger(n) && n >= 0 ? n : 0;
    if (!value || value.schema !== 1 || value.active !== true || (deployment || {}).state === "validating")
        return { fraction: -1, done: 0, expected: 0, building: false };
    const downloads = value.downloads || {};
    const builds = value.builds || {};
    const done = count(downloads.doneBytes);
    const expected = count(downloads.expectedBytes);
    const measurable = downloads.totalKnown === true && expected > 0 && done <= expected && !count(builds.active);
    return { fraction: measurable ? done / expected : -1, done: done, expected: expected,
        building: count(builds.active) > 0 };
}

// ---- updates ---------------------------------------------------------------

// Installed apps whose version changes in a prepared system update.
function appUpdates(deployment, catalogue) {
    const value = deployment || {};
    if (value.changeKind !== "update" || !["ready", "awaiting-boot", "awaiting-login"].includes(value.state))
        return [];
    const highlights = value.highlights || {};
    const apps = (catalogue || {}).apps || [];
    const installed = new Set(((catalogue || {}).packages || []).filter(pkg => (pkg.apps || []).length > 0)
        .map(pkg => pkg.name));
    const byName = {};
    for (const pkg of (catalogue || {}).packages || [])
        if ((pkg.apps || []).length > 0 && !(pkg.name in byName))
            byName[pkg.name] = pkg;
    const desktopApp = {};
    for (const app of apps)
        for (const id of app.desktopIds || [])
            desktopApp[id] = app;
    const appFor = name => {
        const pkg = byName[name];
        return pkg ? (pkg.apps || []).map(entry => desktopApp[entry.id]).find(app => !!app) || null : null;
    };
    const rows = highlights.schema === 1 && highlights.apps ? list(highlights.apps)
        : list(value.packageChanges).filter(change => change.kind !== "rebuilt" && installed.has(change.name));
    return rows.filter(row => row && row.kind !== "rebuilt").map(row => {
        const app = appFor(row.name);
        return { name: row.name, title: app ? app.name : row.title || row.name, icon: row.icon || "",
            app: app, kind: row.kind || "updated", before: row.before, after: row.after };
    }).sort((a, b) => String(a.title).localeCompare(String(b.title)));
}

// ---- Flathub ---------------------------------------------------------------

// Flatpak application IDs: reverse-DNS, at least three elements.
var FLATHUB_ID = /^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+){2,}$/;

function flathubId(value) {
    return typeof value === "string" && value.length <= 255 && FLATHUB_ID.test(value);
}

// Icons and screenshots of Flathub apps load from Flathub's media server only.
function flathubMedia(url) {
    const value = String(url || "");
    return /^https:\/\/dl\.flathub\.org\/media\/[A-Za-z0-9._~\/@%+-]+\.(?:png|jpe?g|webp|svg)$/.test(value) ? value : "";
}

// Flathub results that are not already shown as catalogue apps.
function flathubHits(results, apps) {
    const shown = {};
    for (const app of apps || [])
        if (app && app.appstream)
            shown[app.appstream] = true;
    return list(results).filter(row => row && flathubId(row.id) && !shown[row.id]);
}

// An installed Flatpak app by ID, this account's installation first.
function flatpak(installed, id) {
    const rows = list(installed).filter(row => row && row.id === id);
    return rows.find(row => row.installation === "user") || rows[0] || null;
}

// The latest Flathub change, when it concerns this app. An update of
// everything (no IDs) concerns every app.
function flathubTask(task, id) {
    if (!task || !id)
        return null;
    const ids = list(task.ids);
    return (task.action === "update" && ids.length === 0) || ids.includes(id) ? task : null;
}

function flathubRunning(task) {
    return !!task && ["queued", "running"].includes(task.state);
}

// The one action for a Flathub app: Install, Open, a change on its way, or
// why it cannot be installed here.
function flathubMode(entry, installedRow, task, status) {
    if (!entry || !flathubId(entry.id))
        return "none";
    const mine = flathubTask(task, entry.id);
    if (flathubRunning(mine))
        return mine.action === "remove" ? "removing" : mine.action === "update" ? "updating" : "installing";
    if (installedRow)
        return "open";
    const value = status || {};
    if (value.enabled === false || value.available === false)
        return "off";
    if (entry.unavailable === "unfree")
        return "unfree";
    if (entry.supported === false)
        return "unsupported";
    return "install";
}

// Installed Flathub apps for the Installed tab, by name. A catalogue app
// with the same AppStream ID lends its shipped icon.
function flathubInstalledRows(installed, apps) {
    const byAppstream = {};
    for (const app of apps || [])
        if (app && app.appstream && !(app.appstream in byAppstream))
            byAppstream[app.appstream] = app;
    return list(installed).filter(row => row && flathubId(row.id)).map(row => ({
        key: "flatpak:" + row.installation + ":" + row.id, app: null, catalogue: byAppstream[row.id] || null,
        name: row.name || row.id, attribute: "", desktopIds: row.desktop ? [row.id + ".desktop"] : [],
        icon: row.icon || "", version: row.version || "", owner: "flathub", flatpak: row
    })).sort((a, b) => String(a.name).localeCompare(String(b.name)));
}

// Sandbox permissions worth showing before an install, most significant first.
var PERMISSIONS = ["files-all", "files-home", "files-some", "devices", "host-commands", "x11", "network"];

function permissions(keys) {
    const wanted = list(keys);
    return PERMISSIONS.filter(key => wanted.includes(key));
}

// ---- default apps ------------------------------------------------------------
// The jobs Software offers apps for (catalogue.roles, as cybexos-apps names
// them), in the order the home page shows them, with each one's glyph.
var ROLE_GLYPHS = { browser: "world", terminal: "terminal-2", editor: "pencil", files: "folder", mail: "inbox",
    music: "music", video: "movie", pdf: "file-text", image: "photo" };

function roleDesktops(option) {
    return option ? [option.desktop].concat(option.flathubDesktop ? [option.flathubDesktop] : []) : [];
}

// One option on this computer: installed (its entry is there, or its Flathub
// app), and otherwise how it would arrive. `present(id)` says whether a
// desktop entry exists; `context` is {flathubOn, flathubInstalled}.
//   installed · web (a Cybex OS mail handler) · nixos · vendor (an unfree
//   download) · flathub · missing (Cybex OS's own, not on this computer) ·
//   unavailable (no way to install it here)
function roleOption(option, present, context) {
    const value = context || {};
    const entry = roleDesktops(option).find(id => present(id)) || "";
    const fromFlathub = !!option.flathub && !!flatpak(value.flathubInstalled, option.flathub);
    let source;
    if (option.web)
        source = "web";
    else if (entry !== "" || fromFlathub)
        source = "installed";
    else if (option.included)
        source = "missing";
    else if (option.attribute && !option.unavailable)
        source = option.free === false ? "vendor" : "nixos";
    else if (option.flathub && value.flathubOn)
        source = "flathub";
    else
        source = "unavailable";
    const desktop = entry || (fromFlathub || source === "flathub" ? option.flathubDesktop : option.desktop);
    return { option: option, source: source, desktop: desktop, ready: source === "installed" || source === "web" };
}

// The options a picker lists: those this computer can use or install.
function roleChoices(role, present, context) {
    return list((role || {}).options).map(option => roleOption(option, present, context))
        .filter(row => row.source !== "missing" && row.source !== "unavailable");
}

// The option a desktop entry ID belongs to, or null.
function roleOptionFor(role, desktop) {
    return desktop ? list((role || {}).options).find(option => roleDesktops(option).includes(desktop)) || null : null;
}

// Installed apps that can do the job but are not among the role's options.
function otherApps(role, state) {
    const known = {};
    for (const option of list((role || {}).options))
        for (const id of roleDesktops(option))
            known[id] = true;
    return list((state || {}).choices).filter(row => row && row.value && !known[row.value] && !/ · unavailable$/.test(row.label || ""));
}

// What a role's card says: the app doing the job and who chose it, or the
// one being switched to. `state` is cybexos-apps status for the role.
//   who: "system" (Cybex OS's pick) · "you" · "none" (nothing set) · "switching"
function roleCard(role, state) {
    const value = state || {};
    const pending = value.pending ? roleOptionFor(role, value.pending) : null;
    const effective = value.effective || "";
    const option = roleOptionFor(role, effective);
    const label = option ? option.name : (list(value.choices).find(row => row.value === effective) || {}).label || "";
    const who = pending ? "switching" : effective === "" ? "none"
        : value.personal && effective !== value.system ? "you" : "system";
    return { option: pending || option, name: pending ? pending.name : label, desktop: pending ? value.pending : effective,
        who: who, pending: pending };
}

// A role differs from Cybex OS's pick when this account chose for itself.
function roleChanged(states) {
    return Object.keys(states || {}).filter(id => !!ROLE_GLYPHS[id] && states[id] && states[id].personal
        && states[id].effective !== states[id].system);
}

// An option's notes as {key, yes}; 1Password notes only while proprietary
// apps (and so 1Password) are on.
function perks(option, proprietary) {
    return list((option || {}).perks).map(perk => ({ key: perk.replace(/^-/, ""), yes: perk[0] !== "-" }))
        .filter(perk => proprietary || perk.key !== "1password");
}

// ---- presentation ----------------------------------------------------------

// Decimal sizes, as Nix and the update review report them.
function size(bytes) {
    const value = Number(bytes);
    if (!isFinite(value) || value <= 0)
        return "";
    return value >= 1e9 ? (value / 1e9).toFixed(1) + " GB"
        : value >= 1e6 ? Math.max(1, Math.round(value / 1e6)) + " MB" : Math.max(1, Math.round(value / 1e3)) + " kB";
}

function parseHex(value) {
    const match = /^#?([0-9a-f]{6})$/i.exec(String(value || ""));
    if (!match)
        return null;
    const number = parseInt(match[1], 16);
    return [(number >> 16) & 255, (number >> 8) & 255, number & 255];
}

function hex(rgb) {
    return "#" + rgb.map(part => Math.max(0, Math.min(255, Math.round(part))).toString(16).padStart(2, "0")).join("");
}

function luminance(value) {
    const rgb = parseHex(value);
    if (!rgb)
        return 0;
    const linear = rgb.map(part => {
        const c = part / 255;
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

// Whether text over this colour should be dark (light backgrounds).
function darkInk(value) {
    return luminance(value) > 0.32;
}

function mix(a, b, amount) {
    const from = parseHex(a) || [0, 0, 0];
    const to = parseHex(b) || [0, 0, 0];
    // hex() keeps every channel in range for any amount.
    const t = Number(amount) || 0;
    return hex(from.map((part, i) => part + (to[i] - part) * t));
}

// An app's brand colour for the theme, else its category's, else neutral.
function brand(app, category, dark) {
    const value = (app || {}).brand || {};
    const own = dark ? value.dark || value.light : value.light || value.dark;
    if (parseHex(own))
        return own;
    const tint = (category || {}).color;
    if (parseHex(tint))
        return dark ? mix(tint, "#1a1917", 0.72) : mix(tint, "#ffffff", 0.78);
    return dark ? "#26241f" : "#f1f0f5";
}

// Description paragraphs; a leading "• " marks a list item.
function paragraphs(description) {
    return ((Array.isArray(description) || description instanceof Array) ? description : [])
        .filter(text => typeof text === "string" && text.trim() !== "")
        .map(text => /^•\s*/.test(text) ? { text: text.replace(/^•\s*/, ""), bullet: true }
            : { text: text, bullet: false });
}

// A licence short enough for a tag; proprietary licences have no SPDX name.
function license(value) {
    const text = String(value || "").trim();
    if (text === "" || /^LicenseRef-proprietary/i.test(text))
        return "";
    const first = text.split(/\s+(?:and|AND|or|OR)\s+/)[0].replace(/^\(/, "");
    return first.length > 24 ? first.slice(0, 23) + "…" : first;
}

function host(url) {
    const match = /^https?:\/\/([^/?#]+)/i.exec(String(url || ""));
    return match ? match[1].replace(/^www\./i, "") : "";
}

// Screenshots load from Flathub's media server only.
function screenshots(app) {
    return ((app || {}).screenshots || []).filter(url => typeof url === "string"
        && /^https:\/\/dl\.flathub\.org\/media\/[A-Za-z0-9._~\/@%+-]+\.(?:png|jpe?g|webp)$/.test(url));
}

// Catalogue icon names the bundled Tabler subset may lack; `has` asks it.
var GLYPH_FALLBACKS = { briefcase: "files", school: "brain", tool: "settings", "device-gamepad-2": "device-gamepad-2" };

function glyph(name, has) {
    if (name && (!has || has(name)))
        return name;
    const fallback = GLYPH_FALLBACKS[name];
    return fallback && (!has || has(fallback)) ? fallback : "apps";
}

function columns(width, minimum, spacing) {
    const gap = Number(spacing) || 0;
    return Math.max(1, Math.floor((Number(width) + gap) / (Math.max(1, Number(minimum)) + gap)));
}

// Desktop entry IDs as Quickshell names them: without ".desktop".
function entryIds(ids) {
    return (ids || []).filter(id => typeof id === "string" && /^[A-Za-z0-9_@.+-]+\.desktop$/.test(id))
        .map(id => id.slice(0, -8));
}

if (typeof module !== "undefined") module.exports = {
    list, index, byPopularity, popular, inCategory, featured, editorsChoice, similar, profileApps, collection,
    terms, searchApps, morePackages, installedGroups, selectedPackage, queued, toggle, withAll, installs, removals, prune,
    change, queueState, verdict, PREPARING, FINISHED, FAILED, owns, phase, blocked, changed, progress, appUpdates,
    size, parseHex, luminance, darkInk, mix, brand, paragraphs, license, host, screenshots, GLYPH_FALLBACKS, glyph,
    columns, entryIds, FLATHUB_ID, flathubId, flathubMedia, flathubHits, flatpak, flathubTask, flathubRunning,
    flathubMode, flathubInstalledRows, PERMISSIONS, permissions, ROLE_GLYPHS, roleDesktops, roleOption, roleChoices,
    roleOptionFor, otherApps, roleCard, roleChanged, perks
};
