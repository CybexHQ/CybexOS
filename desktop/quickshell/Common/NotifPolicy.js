// Bounded, deterministic notification admission shared by QML and Node tests.
function sourceKey(row) {
    // webSourceIdentity is canonicalized by the admission/restore boundary.
    // Legacy hostname-only history never acquires an invented HTTP(S) origin.
    if (row.webOrigin) {
        var identity = typeof row.webSourceIdentity === "string" && row.webSourceIdentity.length <= 320
            ? row.webSourceIdentity : "";
        return "web:" + (identity || "unqualified:" + String(row.webOrigin).slice(0, 253).toLowerCase());
    }
    // Keep punctuation and case: lossy slugs alias unrelated native senders.
    return "app:" + JSON.stringify([row.desktopEntry || "", row.appName || "Notification"]);
}

function isQsImage(source) {
    return typeof source === "string" && source.length <= 64
        && /^image:\/\/qsimage\/[0-9]{1,20}\/[0-9]{1,20}$/.test(source)
        && !/[\r\n]/.test(source);
}

function imageIdentity(source, fingerprint) {
    // Quickshell allocates a different provider handle for each notification,
    // even when the attached pixels match. Never equate unresolved handles.
    if (String(source || "").indexOf("image://qsimage") === 0) {
        return isQsImage(source) && typeof fingerprint === "string" && fingerprint.length === 71
            && /^sha256:[0-9a-f]{64}$/.test(fingerprint) ? "pixels:" + fingerprint : null;
    }
    return "uri:" + (source || "");
}

function signature(row) {
    // null marks action data that cannot be compared in full within bounds.
    // Keep its source identity intact for grouping, snoozes and burst limits.
    if (row.actionSignature === null) return null;
    var image = imageIdentity(row.image, row.imageFingerprint);
    var icon = imageIdentity(row.appIcon, row.appIconFingerprint);
    if (image === null || icon === null) return null;
    // Compare full bounded content, not a hash or title alone. Action changes
    // are semantically different; progress is never an occurrence.
    return JSON.stringify([sourceKey(row), row.summary, row.body, row.urgency,
        icon, image, row.actionSignature || ""]);
}

function duplicate(entries, row, now, seconds) {
    if (!(seconds > 0) || row.progress || row.oversized)
        return null;
    var sig = signature(row);
    if (sig === null) return null;
    for (var i = 0; i < entries.length; i++) {
        var old = entries[i];
        // Window anchored to the first occurrence: a flood cannot extend it.
        if (!old.restored && !old.progress && !old.oversized && now >= old.arrived
                && now - old.arrived <= seconds * 1000 && signature(old) === sig)
            return old;
    }
    return null;
}

function activeSnoozes(snoozes, now) {
    return snoozes.filter(function(item) { return item.until > now; }).slice(0, 64);
}

function quietReason(dnd, quiet, snoozes, key, now) {
    if (dnd) return "dnd";
    if (quiet) return "quiet";
    return activeSnoozes(snoozes, now).some(function(item) { return item.key === key; })
        ? "snoozed" : "";
}

function burst(events, key, now, limit) {
    var recent = events.filter(function(item) { return now >= item.at && now - item.at < 10000; });
    var allowed = recent.filter(function(item) { return item.key === key; }).length < limit;
    if (allowed) recent.push({ key: key, at: now });
    // Limits total bookkeeping even with many hostile source identities.
    return { allowed: allowed && recent.length <= 256, events: recent.slice(-256) };
}

function groups(entries) {
    var map = Object.create(null), result = [];
    for (var i = 0; i < entries.length; i++) {
        var row = entries[i], key = row.sourceKey || sourceKey(row);
        if (!map[key]) {
            map[key] = { key: key, app: row.displayAppName, items: [] };
            result.push(map[key]);
        }
        map[key].items.push(row);
    }
    return result;
}

function popupPlan(toasts, row, groupLimit, perGroup) {
    var current = toasts.filter(function(item) { return item.key !== row.key; });
    var list = [row].concat(current), bySource = Object.create(null), accepted = [];
    var order = [];
    for (var i = 0; i < list.length; i++) {
        var item = list[i], key = item.sourceKey;
        if (!bySource[key]) {
            if (order.length >= groupLimit) continue;
            order.push(key);
            bySource[key] = 0;
        }
        if (bySource[key] >= perGroup) continue;
        bySource[key]++;
        accepted.push(item);
    }
    return accepted;
}

function targetScreen(focused, screens, fullscreen, policy) {
    var names = screens.map(function(screen) { return screen.name; });
    var name = names.indexOf(focused) >= 0 ? focused : (names[0] || "");
    if (policy === "show" || fullscreen.indexOf(name) < 0) return name;
    return names.find(function(candidate) { return fullscreen.indexOf(candidate) < 0; }) || "";
}

// ---- the drawer collision rule (2026-11) ------------------------------------
// A toast drawn over the open Control Center hides the drawer it lands on. So
// while the drawer is open on the output a toast would use, on the side of
// the screen its corner is on, and it can show the Notifications tab, a new
// arrival goes to the drawer instead: a persistent unread count on the tab
// and a short strip under the tabs, or a pinned banner when it is critical.
// The drawer is an edge column that can run the output's full height, so
// only the side matters, not whether the toasts sit at its top or bottom.
// Admission policy (Focus, quiet hours, snoozes, bursts, fullscreen) runs
// before this; nothing it held back is replayed when the drawer closes.
//
// `drawer` is { open, tab, screen, side, tabEnabled }: whether a drawer tab is
// presented, which one, its output name, the screen edge it is pinned to
// ("left"/"right") and whether the person keeps the Notifications tab in the
// strip (Settings.drawerTabs).

function toastSide(position) {
    return String(position || "").indexOf("left") !== -1 ? "left" : "right";
}

function notificationsTabEnabled(tabs) {
    var list = (Array.isArray(tabs) || tabs instanceof Array) ? tabs : [];
    return list.some(function(tab) { return !!tab && tab.id === "notifications" && tab.on === true; });
}

function drawerCovers(drawer, screen, position) {
    if (!drawer || !drawer.open || !drawer.tab || !drawer.screen || drawer.screen !== screen)
        return false;
    if (toastSide(position) !== (drawer.side === "left" ? "left" : "right"))
        return false;
    // A tab switched off in settings still presents when opened by name, and
    // then it is the list itself.
    return drawer.tab === "notifications" || drawer.tabEnabled === true;
}

// Where an admitted arrival is shown: "toast", or in the covering drawer as
// "list" (the Notifications tab is showing: it lands at the top of the list),
// "banner" (critical: pinned under the tabs until handled) or "strip".
function drawerRoute(drawer, screen, position, critical) {
    if (!drawerCovers(drawer, screen, position))
        return "toast";
    if (drawer.tab === "notifications")
        return "list";
    return critical ? "banner" : "strip";
}

// Keys still present in `entries`, in entry order. Unread and pinned marks
// name entries by key; a dismissed or evicted entry drops out on its own.
function presentKeys(entries, keys) {
    var wanted = Object.create(null), result = [];
    for (var i = 0; i < keys.length; i++)
        wanted[keys[i]] = true;
    for (var j = 0; j < entries.length; j++) {
        if (wanted[entries[j].key])
            result.push(entries[j].key);
    }
    return result;
}

// Remember up to 64 keys, newest first, without repeats.
function markKey(keys, key) {
    return [key].concat(keys.filter(function(item) { return item !== key; })).slice(0, 64);
}

// The stack's "+n more" count per output: notifications the group bounds,
// a burst or a held deck kept off that output's stack, still in history and
// not showing. Rows are { key, screenName }.
function overflowCounts(rows, entries, toasts) {
    var kept = Object.create(null), shown = Object.create(null), seen = Object.create(null);
    var counts = Object.create(null);
    for (var i = 0; i < entries.length; i++)
        kept[entries[i].key] = true;
    for (var j = 0; j < toasts.length; j++)
        shown[toasts[j].key] = true;
    for (var k = 0; k < rows.length; k++) {
        var row = rows[k], id = row.screenName + "\u0000" + row.key;
        if (!row.screenName || !kept[row.key] || shown[row.key] || seen[id])
            continue;
        seen[id] = true;
        counts[row.screenName] = (counts[row.screenName] || 0) + 1;
    }
    return counts;
}

// An output's count starts over once its stack has emptied.
function liveOverflow(rows, toasts) {
    var live = Object.create(null);
    for (var i = 0; i < toasts.length; i++)
        live[toasts[i].screenName] = true;
    return rows.filter(function(row) { return !!live[row.screenName]; }).slice(-256);
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { sourceKey: sourceKey, isQsImage: isQsImage, imageIdentity: imageIdentity,
        signature: signature, duplicate: duplicate,
        activeSnoozes: activeSnoozes, quietReason: quietReason, burst: burst,
        groups: groups, popupPlan: popupPlan, targetScreen: targetScreen,
        toastSide: toastSide, notificationsTabEnabled: notificationsTabEnabled,
        drawerCovers: drawerCovers, drawerRoute: drawerRoute,
        presentKeys: presentKeys, markKey: markKey,
        overflowCounts: overflowCounts, liveOverflow: liveOverflow };
