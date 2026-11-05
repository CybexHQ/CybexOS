const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { load, shellDir } = require("./shell.cjs");

// The 2026-11 notification work: the drawer collision rule (a toast never
// lands on the open Control Center; the drawer takes the arrival) and the
// card anatomy rules shared by toasts and the drawer list. The decisions
// live in NotifPolicy.js / NotifHelpers.js so they run here; the service
// half runs the real Notifs.qml functions against fake signals, as
// notification-policy.test.cjs does.

const P = load("NotifPolicy.js");
const H = load("NotifHelpers.js");
const S = load("NotifSmart.js");
const Holds = load("NotifHolds.js");

function read(rel) {
    return fs.readFileSync(path.join(shellDir, rel), "utf8");
}

const drawer = (changes = {}) => ({ open: true, tab: "overview", screen: "one", side: "right",
    tabEnabled: true, ...changes });

test("the drawer takes an arrival only on its own output, on its side, with the tab available", () => {
    assert.equal(P.drawerRoute(drawer(), "one", "top-right", false), "strip");
    // The drawer is an edge column; its side is what collides, not the end.
    assert.equal(P.drawerRoute(drawer(), "one", "bottom-right", false), "strip");
    assert.equal(P.drawerRoute(drawer(), "one", "top-left", false), "toast");
    assert.equal(P.drawerRoute(drawer(), "one", "bottom-left", false), "toast");
    assert.equal(P.drawerRoute(drawer(), "two", "top-right", false), "toast", "another output");
    assert.equal(P.drawerRoute(drawer({ open: false }), "one", "top-right", false), "toast");
    assert.equal(P.drawerRoute(drawer({ tab: "" }), "one", "top-right", false), "toast");
    assert.equal(P.drawerRoute(drawer({ screen: "" }), "one", "top-right", false), "toast");
    assert.equal(P.drawerRoute(null, "one", "top-right", false), "toast");
    // A drawer opened from the bar's left section pins to the left edge.
    assert.equal(P.drawerRoute(drawer({ side: "left" }), "one", "top-left", false), "strip");
    assert.equal(P.drawerRoute(drawer({ side: "left" }), "one", "top-right", false), "toast");
});

test("critical arrivals pin a banner, and the open list takes everything", () => {
    assert.equal(P.drawerRoute(drawer(), "one", "top-right", true), "banner");
    assert.equal(P.drawerRoute(drawer({ tab: "notifications" }), "one", "top-right", false), "list");
    assert.equal(P.drawerRoute(drawer({ tab: "notifications" }), "one", "top-right", true), "list");
});

test("with the Notifications tab switched off there is nowhere to point, except the tab itself", () => {
    const off = drawer({ tabEnabled: false });
    assert.equal(P.drawerRoute(off, "one", "top-right", false), "toast");
    assert.equal(P.drawerRoute(off, "one", "top-right", true), "toast");
    // Presented by name (the bell, Super+N) it joins the strip and is the list.
    assert.equal(P.drawerRoute({ ...off, tab: "notifications" }, "one", "top-right", false), "list");
    assert.equal(P.notificationsTabEnabled([{ id: "overview", on: true }, { id: "notifications", on: true }]), true);
    assert.equal(P.notificationsTabEnabled([{ id: "notifications", on: false }]), false);
    assert.equal(P.notificationsTabEnabled([{ id: "overview", on: true }]), false);
    for (const hostile of [undefined, null, "notifications", {}, [null], [{ id: "notifications", on: "yes" }]])
        assert.equal(P.notificationsTabEnabled(hostile), false, JSON.stringify(hostile));
    assert.equal(P.toastSide("top-left"), "left");
    assert.equal(P.toastSide("bottom-right"), "right");
    assert.equal(P.toastSide(undefined), "right");
});

test("unread and pinned marks name present entries, newest first and bounded", () => {
    const entries = [{ key: "c" }, { key: "b" }, { key: "a" }];
    assert.deepEqual(P.presentKeys(entries, ["a", "gone", "c"]), ["c", "a"]);
    assert.deepEqual(P.presentKeys([], ["a"]), []);
    let keys = [];
    for (let i = 0; i < 70; i++)
        keys = P.markKey(keys, "k" + i);
    assert.equal(keys.length, 64);
    assert.equal(keys[0], "k69");
    assert.deepEqual(P.markKey(["a", "b", "c"], "b"), ["b", "a", "c"], "no repeats; a repeat moves forward");
});

test("+n more counts what each output's stack kept off, once, while that stack lasts", () => {
    const entries = [{ key: "a" }, { key: "b" }, { key: "c" }, { key: "d" }];
    const toasts = [{ key: "a", screenName: "one" }, { key: "d", screenName: "two" }];
    const rows = [{ key: "b", screenName: "one" }, { key: "b", screenName: "one" },
        { key: "c", screenName: "one" }, { key: "gone", screenName: "one" },
        { key: "a", screenName: "one" }, { key: "c", screenName: "" }];
    assert.deepEqual({ ...P.overflowCounts(rows, entries, toasts) }, { one: 2 },
        "dismissed, showing, duplicate and screenless rows do not count");
    assert.deepEqual(P.liveOverflow(rows, [{ key: "d", screenName: "two" }]), [],
        "an output whose stack emptied starts over");
    assert.equal(P.liveOverflow(rows, toasts).length, 5);
});

// ---- the service, through the real Notifs.qml functions -------------------

function service() {
    const source = read("Common/Notifs.qml");
    const queue = [];
    const context = { Helpers: H, Policy: P, Smart: S, Format: load("Format.js"), console, Date,
        NotificationUrgency: { Normal: 1, Critical: 2 }, BrandIcons: { has: () => false },
        Settings: { notifHistoryCount: 50, notifDedupeSeconds: 10, notifBurstLimit: 5,
            notifPopupGroups: 3, notifPopupPerGroup: 3, notifFullscreen: "away", notifDuration: 8,
            notifPosition: "top-right", notifHistoryHours: 24 },
        Screens: { focused: { name: "one" } }, Quickshell: { screens: [{ name: "one" }, { name: "two" }] },
        Qt: { callLater: fn => { if (!queue.includes(fn)) queue.push(fn); } },
        entries: [], toasts: [], snoozes: [], burstEvents: [], heldGroups: {}, fullscreenOutputs: [],
        dnd: false, quietActive: false, localSerial: 0, historyGeneration: 0,
        historyProcess: { running: false }, historyWrite: { stop() {} }, fingerprintImage: () => "",
        I18n: { tr: s => s }, queue,
        drawerState: { open: false, tab: "", screen: "", side: "right", tabEnabled: true },
        unreadKeys: [], pinnedKeys: [], arrivalKey: "", overflow: [],
        arrivalLife: { restarts: 0, restart() { this.restarts++; }, stop() {} } };
    context.root = context;
    context.groupHoldQueue = Holds.create(context.Qt.callLater, groups => { context.heldGroups = groups; });
    context.historyRetention = { stop() {}, start() {} };
    context.snoozeTimer = { stop() {}, start() {} };
    context.dndTimer = { stop() {}, start() {} };
    vm.createContext(context);
    for (const name of ["describe", "remoteSource", "publish", "updateEntry", "removeEntry", "hideToast",
        "dismiss", "invoke", "defaultAction", "secondaryActions", "canActivate", "activate", "timeoutFor",
        "send", "queueHistory", "scheduleRetention", "routeToDrawer", "unpin", "noteOverflow",
        "updateNotice", "primaryAction", "holdGroup"]) {
        const match = source.match(new RegExp("^    function " + name + "\\([^]*?^    }", "m"));
        assert.ok(match, name);
        vm.runInContext(match[0], context);
    }
    context.replaceableSignals = ["appNameChanged", "appIconChanged", "desktopEntryChanged", "hintsChanged",
        "imageChanged", "summaryChanged", "bodyChanged", "urgencyChanged", "expireTimeoutChanged", "actionsChanged"];
    const start = source.indexOf("        onNotification: notif => {") + "        onNotification: ".length;
    const end = source.indexOf("\n        }\n    }", start) + "\n        }".length;
    context.receive = vm.runInContext("(" + source.slice(start, end) + ")", context);
    return context;
}

function sender(summary, extra = {}) {
    const value = { appName: "Chat", desktopEntry: "chat", summary, body: "Message", urgency: 1, actions: [],
        hints: {}, expireTimeout: -1, resident: false, ...extra };
    for (const name of ["closed", "appNameChanged", "appIconChanged", "desktopEntryChanged", "hintsChanged",
        "imageChanged", "summaryChanged", "bodyChanged", "urgencyChanged", "expireTimeoutChanged", "actionsChanged"]) {
        const handlers = [];
        value[name] = { connect: fn => handlers.push(fn),
            disconnect: fn => { const i = handlers.indexOf(fn); if (i >= 0) handlers.splice(i, 1); },
            emit: () => handlers.slice().forEach(fn => fn()) };
    }
    value.expired = 0;
    value.expire = () => { value.expired++; value.closed.emit(); };
    value.dismissed = 0;
    value.dismiss = () => { value.dismissed++; value.closed.emit(); };
    return value;
}

test("arrivals under the open drawer skip the toast, count as unread and flash the strip", () => {
    const c = service();
    c.drawerState = drawer();
    const notif = sender("Under the drawer");
    c.receive(notif);
    assert.equal(c.toasts.length, 0, "no toast over the drawer");
    assert.equal(c.entries.length, 1, "it is kept in the list");
    assert.deepEqual(c.unreadKeys, [c.entries[0].key]);
    assert.equal(c.arrivalKey, c.entries[0].key);
    assert.equal(c.arrivalLife.restarts, 1, "the strip's five seconds start");
    assert.equal(notif.expired, 0, "the sender is not told it expired: its actions keep working");

    const critical = sender("Battery critical", { appName: "Power", desktopEntry: "power", urgency: 2 });
    c.receive(critical);
    assert.equal(c.toasts.length, 0);
    assert.equal(c.pinnedKeys[0], c.entries[0].key, "critical pins a banner");
    assert.notEqual(c.arrivalKey, c.entries[0].key, "the banner replaces the strip for it");
    assert.equal(c.unreadKeys.length, 2);

    // Nothing replays once the drawer closes; the next arrival toasts again.
    c.drawerState = drawer({ open: false, tab: "" });
    assert.equal(c.toasts.length, 0);
    c.receive(sender("After closing", { appName: "Mail", desktopEntry: "mail" }));
    assert.equal(c.toasts.length, 1);
    assert.equal(c.unreadKeys.length, 2);
});

test("policy runs first: Focus, quiet hours and bursts never reach the drawer", () => {
    const c = service();
    c.drawerState = drawer();
    c.dnd = true;
    c.receive(sender("While focused"));
    c.dnd = false;
    c.quietActive = true;
    c.receive(sender("Quiet hours", { appName: "Two", desktopEntry: "two" }));
    c.quietActive = false;
    assert.equal(c.entries.length, 2);
    assert.deepEqual(c.unreadKeys, []);
    assert.equal(c.arrivalKey, "");
    c.Settings.notifBurstLimit = 1;
    c.receive(sender("First of a burst", { appName: "Burst", desktopEntry: "burst" }));
    c.receive(sender("Second of a burst", { appName: "Burst", desktopEntry: "burst" }));
    assert.equal(c.unreadKeys.length, 1, "the burst limit holds the second back silently");
});

test("other outputs and the far side keep their toasts; the open list counts nothing", () => {
    const c = service();
    c.drawerState = drawer({ screen: "two" });
    c.receive(sender("On the focused output"));
    assert.equal(c.toasts.length, 1);
    c.drawerState = drawer({ side: "left" });
    c.receive(sender("Far side", { appName: "Two", desktopEntry: "two" }));
    assert.equal(c.toasts.length, 2);
    c.drawerState = drawer({ tab: "notifications" });
    c.receive(sender("Into the open list", { appName: "Three", desktopEntry: "three" }));
    assert.equal(c.toasts.length, 2);
    assert.deepEqual(c.unreadKeys, [], "it is in front of the person already");
    assert.equal(c.arrivalKey, "");
});

test("acting on a pinned card handles it; activation runs the default and dismisses", () => {
    const c = service();
    c.drawerState = drawer();
    const reply = { identifier: "reply", text: "Reply", invoked: 0, invoke() { this.invoked++; } };
    const open = { identifier: "default", text: "Open", invoked: 0, invoke() { this.invoked++; } };
    const critical = sender("Disk full", { urgency: 2, actions: [open, reply] });
    c.receive(critical);
    const entry = c.entries[0];
    assert.deepEqual(c.pinnedKeys, [entry.key]);
    c.invoke(entry, reply);
    assert.equal(reply.invoked, 1);
    assert.deepEqual(c.pinnedKeys, []);

    c.drawerState = drawer({ open: false, tab: "" });
    const mail = sender("Mail", { appName: "Mail", desktopEntry: "mail", actions: [open] });
    c.receive(mail);
    const card = c.entries[0];
    c.activate(card);
    assert.equal(open.invoked, 1, "body click runs the default action");
    assert.equal(c.entries.some(item => item.key === card.key), false, "and the card is done with");
    assert.equal(mail.dismissed, 1);

    const keep = { identifier: "default", text: "Open", invoke() {} };
    const resident = sender("Resident", { appName: "Player", desktopEntry: "player", actions: [keep], resident: true });
    c.receive(resident);
    c.activate(c.entries[0]);
    assert.equal(c.entries[0].summary, "Resident", "a resident sender asked to stay listed");
});

test("the stack's group bound counts what it pushed out for +n more", () => {
    const c = service();
    for (const app of ["One", "Two", "Three", "Four"])
        c.receive(sender(app, { appName: app, desktopEntry: app.toLowerCase() }));
    assert.equal(c.toasts.length, 3);
    assert.deepEqual({ ...P.overflowCounts(c.overflow, c.entries, c.toasts) }, { one: 1 });
});

test("only a staged update's next step takes the accent", () => {
    const c = service();
    const restart = { identifier: "default", text: "Restart now", invoke() {} };
    const later = { identifier: "later", text: "Later", invoke() {} };
    const update = { appName: "Software Update", live: true, webOrigin: "", actions: [restart, later] };
    assert.equal(c.primaryAction(update), restart);
    assert.equal(c.primaryAction({ ...update, actions: [{ identifier: "default", text: "" }, later] }), later,
        "an unlabelled default cannot be a button; the update's first action leads");
    assert.equal(c.primaryAction({ ...update, appName: "Chat" }), null);
    assert.equal(c.primaryAction({ ...update, webOrigin: "updates.example" }), null);
    assert.equal(c.primaryAction({ ...update, live: false }), null);
    const plan = H.actionPlan(c.secondaryActions(update), c.primaryAction(update));
    assert.deepEqual(plan.buttons.map(action => action.text), ["Restart now", "Later"]);
    assert.equal(plan.primary, 0);
});

// ---- card anatomy rules -----------------------------------------------------

test("a card's body gives up a line to its buttons and the title holds two lines", () => {
    assert.equal(H.TITLE_LINES, 2);
    assert.equal(H.bodyLineLimit(3, false), 3);
    assert.equal(H.bodyLineLimit(3, true), 2);
    assert.equal(H.bodyLineLimit(2, true), 2);
    assert.equal(H.bodyLineLimit(1, true), 1);
    assert.equal(H.bodyLineLimit(0, false), 0, "Body preview Off hides the body");
    for (const hostile of [undefined, NaN, -4, "x"])
        assert.equal(H.bodyLineLimit(hostile, false), 0);
    assert.equal(H.bodyLineLimit(9, false), 3);
});

test("two buttons: the sender's own first, shell shortcuts fill, snoozes wait under More", () => {
    const a = { identifier: "a", text: "Reply" }, b = { identifier: "b", text: "Mark as read" };
    const c = { identifier: "c", text: "Mute" };
    const code = { kind: "copy-code", text: "Copy verification code", value: "123456" };
    const wiz = { kind: "ask-wiz", text: "Ask Wiz" };
    const link = { kind: "link", text: "Open link · example.com", value: "https://example.com/" };
    const snooze = { kind: "snooze", text: "Snooze 15 minutes", minutes: 15 };
    const unsnooze = { kind: "unsnooze", text: "Unsnooze" };

    let plan = H.actionPlan([wiz, a, b, c, code, link, snooze], null);
    assert.deepEqual(plan.buttons, [a, b]);
    assert.deepEqual(plan.more, [wiz, c, code, link, snooze], "More keeps the service's order");
    assert.equal(plan.primary, -1);

    plan = H.actionPlan([wiz, code, link, snooze], null);
    assert.deepEqual(plan.buttons, [code, wiz], "a code to copy is the likeliest next step");
    assert.deepEqual(plan.more, [link, snooze]);

    plan = H.actionPlan([snooze, unsnooze], null);
    assert.deepEqual(plan.buttons, [], "snoozing is never a resting button");
    assert.deepEqual(plan.more, [snooze, unsnooze]);

    plan = H.actionPlan([a, b, snooze], b);
    assert.deepEqual(plan.buttons, [b, a], "the primary leads");
    assert.equal(plan.primary, 0);
    assert.deepEqual(plan.more, [snooze]);
    assert.deepEqual(H.actionPlan(undefined, null), { buttons: [], more: [], primary: -1 });
    assert.equal(H.ACTION_BUTTONS, 2);
});

test("every labelled sender action is offered; default and close never are", () => {
    const list = [{ identifier: "default", text: "Open" }, { identifier: "one", text: "One" },
        { identifier: "two", text: "Two" }, { identifier: "three", text: "Three" },
        { identifier: "close", text: "Close" }, { identifier: "blank", text: " " }];
    assert.deepEqual(H.senderActions(list).map(action => action.identifier), ["one", "two", "three"]);
    assert.deepEqual(H.secondaryActions(list).map(action => action.identifier), ["one", "two"]);
});

test("a monogram replaces the generic bell", () => {
    assert.equal(H.monogram("Signal"), "S");
    assert.equal(H.monogram("brave"), "B");
    assert.equal(H.monogram("www.example.com"), "E");
    assert.equal(H.monogram("  (beta) app"), "B");
    assert.equal(H.monogram("1Password"), "1");
    assert.equal(H.monogram("élan"), "É");
    assert.equal(H.monogram("微信"), "微");
    assert.equal(H.monogram("🎵 Music"), "🎵", "an astral character stays whole");
    assert.equal(H.monogram("<b>Chat</b>"), "C", "markup is not a letter");
    assert.equal(H.monogram(""), "");
    assert.equal(H.monogram("…"), "");
    assert.equal(H.monogram(undefined), "");
});

// ---- the surfaces ------------------------------------------------------------

test("toasts never take keyboard focus and point at the drawer's tab", () => {
    const toasts = read("NotificationToasts.qml");
    assert.match(toasts, /WlrLayershell\.keyboardFocus:\s*WlrKeyboardFocus\.None/);
    assert.match(toasts, /keyboardEnabled:\s*false/);
    assert.match(toasts, /overflowCount:\s*Notifs\.toastOverflow\[root\.screenName\] \|\| 0/);
    assert.match(toasts, /I18n\.format\("\+%1 more", \[root\.overflowCount\]\)/);
    assert.match(toasts, /Popouts\.openPanel\("notifications", undefined, undefined, root\.screenName\)/);
    assert.doesNotMatch(toasts.slice(toasts.indexOf("id: moreChip")), /activeFocusOnTab|forceActiveFocus/);
    assert.match(toasts, /onActivated:\s*Notifs\.activate\(slot\.modelData\)/);
    // Expiry pauses while the pointer is on the deck (that hover is `expanded`).
    assert.match(toasts, /readonly property bool expanded:\s*expandedByUser \|\| deckHover\.hovered/);
});

test("the arrival strip never takes focus; the critical banner can be handled from the keyboard", () => {
    const arrival = read("Popovers/Drawer/DrawerArrival.qml");
    const strip = arrival.slice(arrival.indexOf("id: stripReveal"));
    const banner = arrival.slice(arrival.indexOf("id: bannerReveal"), arrival.indexOf("id: stripReveal"));
    assert.doesNotMatch(strip, /activeFocusOnTab|forceActiveFocus/);
    assert.match(strip, /onClicked:\s*root\.open\(\)/);
    assert.match(banner, /activeFocusOnTab:\s*bannerReveal\.reveal/);
    assert.match(banner, /Notifs\.dismiss\(bannerCard\.entry\)/);
    assert.match(arrival, /readonly property bool listShown:\s*currentTab === "notifications"/);
    assert.match(arrival, /Popouts\.openPanel\(name, Popouts\.island\)/,
        "opening the tab goes through the panel name, so Notifs sees it read");
    const notifs = read("Common/Notifs.qml");
    assert.match(notifs, /interval:\s*5000\s*onTriggered:\s*root\.arrivalKey = ""/);
    assert.match(notifs, /onDrawerTabChanged:[\s\S]*?unreadKeys = \[\];[\s\S]*?pinnedKeys = \[\];/);
});

test("the tab strip's selected state and unread count follow the shared vocabulary", () => {
    const tabs = read("Popovers/Drawer/DrawerTabs.qml");
    assert.match(tabs, /color:\s*on \? Theme\.selectedFill : "transparent"/);
    assert.match(tabs, /height:\s*Theme\.selectedEdgeWidth[\s\S]{0,60}?color:\s*Theme\.selectedMark/);
    assert.match(tabs, /color:\s*segment\.on \? Theme\.accentText : Theme\.textFaint/);
    assert.match(tabs, /hovered:\s*segmentMouse\.containsMouse && !segment\.on/, "hover stays the neutral chip");
    const badge = tabs.slice(tabs.indexOf("id: countBadge"));
    assert.match(badge, /z:\s*2/);
    assert.match(badge, /color:\s*Theme\.accent\n/);
    assert.match(badge, /color:\s*Theme\.accentFg/);
    assert.match(tabs, /readonly property int unreadCount:\s*Notifs\.unread\.length/);
    assert.match(tabs, /I18n\.format\("%1, %2 unread"/);
});

test("the drawer list keeps Focus as a labelled switch on the shared state", () => {
    const centre = read("Popovers/Drawer/DrawerNotifications.qml");
    assert.match(centre, /Toggle \{[\s\S]*?checked:\s*Notifs\.dnd[\s\S]*?onToggled:\s*value => Notifs\.setDnd\(value\)/);
    assert.match(centre, /I18n\.tr\("Focus"\)[\s\S]*?I18n\.tr\("Silences notifications"\)/);
    assert.doesNotMatch(centre, /I18n\.tr\("On"\)|modeChoice/);
    assert.match(centre, /target:\s*Theme\.scaled\(24\)/);
    assert.match(centre, /closeAlways:\s*true/);
    assert.match(centre, /onCloseRequested:\s*root\.dismiss\(recentCard\)/);
    assert.match(centre, /function dismiss\(card\)[\s\S]*?Qt\.callLater\(\(\) => root\.focusCardAt\(index\)\)/,
        "focus returns to the neighbouring card after a keyboard dismiss");
    assert.match(centre, /property bool fresh:\s*modelData\.arrived > root\.shownAt/);
});
