const test = require("node:test");
const { untranslated } = require("./shell.cjs");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { shellDir } = require("./shell.cjs");

const read = rel => untranslated(fs.readFileSync(
    path.join(shellDir, "Popovers", "Drawer", rel), "utf8"));
const overview = read("DrawerOverview.qml");
const hero = read("DrawerSystemHero.qml");
const drawer = read("DrawerPopover.qml");
const footer = read("DrawerSessionFooter.qml");
const power = read("DrawerPower.qml");
const processes = read("DrawerProcesses.qml");
const sound = read("DrawerSound.qml");
const sliderRow = read("DrawerSliderRow.qml");
const drawerTile = read("DrawerTile.qml");
const tabs = read("DrawerTabs.qml");
const menu = read("DrawerMenu.qml");
const emptyState = read("DrawerEmptyState.qml");
const network = read("DrawerNetwork.qml");
const bluetooth = read("DrawerBluetooth.qml");
const viewState = read("DrawerViewState.qml");
const qmldir = fs.readFileSync(path.join(shellDir, "Popovers", "Drawer", "qmldir"), "utf8");
const drawerSettings = untranslated(fs.readFileSync(
    path.join(shellDir, "Settings", "DrawerPage.qml"), "utf8"));

test("Overview puts everyday controls first and keeps every section setting", () => {
    // 2026-11 review: toggles > sliders > now playing > pending update >
    // system summary > processes, which is also the above-the-fold priority.
    const order = ["// ---- quick toggles", "// ---- sliders", "// ---- now playing",
        "// ---- pending update", "DrawerSystemHero {", "DrawerProcesses {"]
        .map(marker => overview.indexOf(marker));
    assert.ok(order.every(index => index >= 0), `missing section: ${order}`);
    assert.deepEqual([...order].sort((a, b) => a - b), order,
        "Overview sections are out of their agreed order");
    for (const key of ["tiles", "sliders", "media", "updates", "processes"])
        assert.match(overview, new RegExp(`Settings\\.drawerOverview\\.${key} === true`),
            `${key} must stay switchable`);
    assert.doesNotMatch(hero, /Settings\.drawerOverview/,
        "machine identity must not acquire another visibility setting");
    assert.match(overview,
        /Claim\s*\{[\s\S]{0,180}?active:\s*root\.visible[\s\S]{0,180}?SysInfo\.acquire\(\)[\s\S]{0,180}?SysInfo\.release\(\)/,
        "Overview must own the system sampler while it is visible");
});

test("session actions left the body for the pinned row", () => {
    assert.doesNotMatch(overview, /Session\.(?:lock|suspend|logout|reboot|shutdown)\(/,
        "the old session row at the end of Overview must be gone");
    assert.doesNotMatch(overview, /\/\/ ---- session/);
});

test("the summary is one identity line, the machine, and three two-line meters", () => {
    assert.match(hero, /BrandIcon\s*\{[\s\S]{0,120}?name:\s*"cybexos"/);
    assert.match(hero, /name:\s*"computer"/,
        "unreadable OS metadata needs a generic-computer fallback");
    // The identity line is the one Settings Home writes.
    assert.match(hero, /path:\s*"\/etc\/cybexos\/release\.json"/);
    assert.match(hero, /"Cybex OS " \+ root\.releaseVersion/);
    assert.match(hero, /\[SysInfo\.osName, SysInfo\.osVersion\]\.filter\(Boolean\)\.join\(" "\)/);
    assert.match(hero, /DrawerFormat\.shortUptime\(SysInfo\.uptimeSecs\)/);

    for (const property of [
        "osName", "osVersion", "deviceVendor", "deviceModel", "kernelRelease",
        "uptimeSecs", "cpuModel", "cpuUsage", "cpuTemp", "memUsedBytes",
        "memTotalBytes", "swapUsedBytes", "swapTotalBytes", "rootFsUsedBytes",
        "rootFsTotalBytes", "rootFsAvailableBytes", "rootFsType",
    ])
        assert.match(hero, new RegExp(`SysInfo\\.${property}\\b`),
            `${property} is absent from the summary`);
    assert.doesNotMatch(hero, /SysInfo\.user\b/,
        "the summary must not expose the logged-in user");
    assert.doesNotMatch(hero, /SysInfo\.host\b/,
        "the summary must not expose the hostname");

    for (const label of ["CPU", "MEMORY", "DISK"])
        assert.ok(hero.includes(`label: "${label}"`), `${label} meter is missing`);
    assert.match(hero, /BlockMeter\s*\{/);
    assert.doesNotMatch(hero, /required property string detail\b/,
        "a meter is two lines: label and reading, then the meter");
    assert.match(hero, /reading:\s*root\.cpuReading/);
    assert.match(hero, /reading:\s*root\.memoryReading/);
    assert.match(hero, /reading:\s*root\.diskReading/);
    assert.match(hero, /status:\s*SysInfo\.cpuTempKnown \? SysInfo\.cpuTemp \+ " °C" : ""/,
        "temperature joins the CPU reading only when it is known");
    assert.match(hero, /SysInfo\.memUsage >= 95[\s\S]*SysInfo\.memUsage >= 85/);
    assert.match(hero, /SysInfo\.rootFsUsage >= 90[\s\S]*SysInfo\.rootFsUsage >= 80/);
    assert.match(hero, /SysInfo\.cpuTemp >= 80[\s\S]*SysInfo\.cpuTemp >= 65/);
    assert.match(hero,
        /color:\s*severity >= 2 \? Theme\.redBgSoft[\s\S]{0,120}?"transparent"/,
        "healthy metric rows must stay flat and warning-only rows may tint");
});

test("memory reads in GiB, storage in decimal units, details behind Show details", () => {
    const memory = hero.slice(hero.indexOf("memoryReading:"), hero.indexOf("diskReading:"));
    const disk = hero.slice(hero.indexOf("diskReading:"), hero.indexOf("swapDetail:"));
    assert.match(memory, /formatIecBytes\(SysInfo\.memUsedBytes\)/);
    assert.doesNotMatch(memory, /formatStorageBytes/);
    assert.match(disk, /formatStorageBytes\(SysInfo\.rootFsUsedBytes\)/);
    assert.match(disk, /"%1 free"/);
    assert.doesNotMatch(disk, /formatIecBytes/);
    assert.match(hero, /" · " \+ "no swap"/);
    assert.match(hero, /"swap %1"/);

    // Kernel, processor and filesystem are one tap away, not on the card.
    const details = hero.slice(hero.indexOf("readonly property var details:"),
        hero.indexOf("// The installed release"));
    for (const fact of ["SysInfo.cpuModel", "SysInfo.kernelRelease", "SysInfo.rootFsType"])
        assert.ok(details.includes(fact), `${fact} belongs in the details`);
    assert.match(hero, /visible: root\.detailsOpen && root\.details\.length > 0/);
    assert.match(hero, /Accessible\.name: root\.detailsOpen \? "Hide details" : "Show details"/);
});

test("diagnostics wait behind one Show details, kept for the session", () => {
    // 2026-11 UI council: meters, facts and processes collapse behind the
    // system summary; the everyday controls lead.
    assert.match(viewState, /pragma Singleton/);
    assert.match(viewState, /property bool overviewDetails: false/);
    assert.match(qmldir, /^singleton DrawerViewState DrawerViewState\.qml$/m);
    assert.match(hero, /readonly property bool detailsOpen: DrawerViewState\.overviewDetails/);
    assert.match(hero, /DrawerViewState\.overviewDetails = !DrawerViewState\.overviewDetails/);
    const meters = hero.slice(hero.indexOf("visible: root.detailsOpen\n"), hero.indexOf("label: \"CPU\""));
    assert.ok(meters.length > 0 && meters.length < 200, "the meters are part of the details");
    assert.match(overview,
        /DrawerProcesses \{\s*visible: Settings\.drawerOverview\.processes === true\s*&& DrawerViewState\.overviewDetails/,
        "top processes are part of the details, and stop sampling while collapsed");
    // Collapsed, one plain line says how busy the machine is.
    assert.match(hero, /visible: !root\.detailsOpen && root\.summaryShown\.length > 0/);
    assert.match(hero, /model: \["cpu", "memory", "disk"\]/, "a fixed model: a sample updates readings in place");
    for (const key of ["CPU %1%", "Memory %1%", "Disk %1%", "Disk %1% · %2 free"])
        assert.ok(hero.includes(`"${key}"`), `summary reading ${key}`);
    assert.match(hero, /entry\.severity >= 2 \? Theme\.redText[\s\S]{0,80}?entry\.severity === 1 \? Theme\.amber : Theme\.textMid/);
    // The disclosure is a 32 px target in plain words.
    const toggle = hero.slice(hero.indexOf("id: detailsToggle"));
    assert.match(toggle, /height: Math\.max\(Theme\.inlineActionHeight/);
    assert.match(toggle, /root\.detailsOpen \? "Hide details" : "Show details"/);
    assert.doesNotMatch(hero, /"DISK \/"|Disk slash/, "no mount-point jargon");
});

test("unknown readings stay explicit and each metric has one accessible summary", () => {
    for (const known of ["cpuUsageKnown", "cpuTempKnown", "memKnown",
        "swapKnown", "rootFsKnown"])
        assert.match(hero, new RegExp(`SysInfo\\.${known}\\b`));
    assert.match(hero, /"Unavailable"/);
    assert.match(hero, /temperature unavailable/i);
    assert.match(hero, /Memory unavailable/);
    assert.match(hero, /Storage unavailable/);
    assert.match(hero, /Accessible\.role:\s*Accessible\.StaticText/);
    assert.match(hero, /Accessible\.name:\s*metric\.accessibleName/);
    assert.match(hero, /accessibleDescription:\s*SysInfo\.rootFsError/);
});

test("quick toggles keep their names and wear the selected-tile state", () => {
    for (const [glyph, label] of [["dark_mode", "Dark"], ["do_not_disturb_on", "Focus"],
        ["nightlight", "Night"], ["coffee", "Awake"]])
        assert.match(overview, new RegExp(`glyph: "${glyph}"\\s*label: "${label}"`));
    assert.match(overview, /"Focus: silences notifications"/);
    assert.match(drawerTile, /color:\s*on \? Theme\.selectedFill : Theme\.chip/);
    assert.match(drawerTile, /border\.width:\s*on \? Theme\.selectedBorderWidth : 0/);
    assert.match(drawerTile, /border\.color:\s*Theme\.selectedMark/);
    assert.match(drawerTile, /color:\s*root\.on \? Theme\.accentText : Theme\.textMid/,
        "a selected tile's glyph is the accent text colour");
    assert.match(drawerTile, /border\.width:\s*Theme\.focusWidth\(root\.activeFocus\)/);
});

test("a slider without its device fades and says why, with a way to fix it", () => {
    assert.equal((overview.match(/showValue:\s*true/g) || []).length, 2,
        "brightness and volume should both show their current percentage");
    assert.match(sliderRow, /opacity:\s*root\.ready \? 1 : 0\.4/);
    assert.match(sliderRow, /dimmed:\s*!root\.ready/,
        "a missing device must not leave a knob that looks live at 0 %");
    assert.match(sliderRow, /text:\s*root\.ready \? Math\.round\(root\.value \* 100\) \+ "%" : "–"/);
    // The reason sits outside the faded control, at full contrast.
    const control = sliderRow.slice(sliderRow.indexOf("id: control"), sliderRow.indexOf("id: noteLine"));
    assert.doesNotMatch(control, /root\.reason/);
    assert.match(sliderRow, /color:\s*root\.explained \? Theme\.textHi : Theme\.textMid/);
    assert.match(sliderRow, /LinkText\s*\{[\s\S]{0,200}?onClicked:\s*root\.recovery\(\)/);
    assert.match(overview, /ready:\s*Audio\.ready[\s\S]{0,200}?reason:\s*"No output device"[\s\S]{0,80}?recoveryText:\s*"Sound settings"/);
    assert.match(overview, /onRecovery:\s*Settings\.showPanel\("sound"/);
    assert.match(sound, /readonly property string emptyKind: !Pipewire\.ready \? "service"\s*: !Audio\.ready \? "device" : ""/,
        "Sound says why there is no output instead of reporting a 0 % one");
    assert.match(sound, /\/\/ ---- output header[\s\S]{0,80}?visible: root\.emptyKind === ""/);
});

test("drawer scrolls only its body between pinned tabs and a pinned session row", () => {
    const tabs = drawer.indexOf("DrawerTabs {");
    const arrival = drawer.indexOf("DrawerArrival {");
    const viewport = drawer.indexOf("id: bodyViewport");
    const session = drawer.indexOf("DrawerSessionFooter {");
    assert.ok(tabs >= 0 && arrival > tabs && viewport > arrival && session > viewport,
        "tabs, then the scrolling body, then the session row: layout and Tab order");
    assert.match(drawer,
        /bodyHeightLimit:[\s\S]{0,180}?availableHeight[\s\S]{0,180}?drawerTabs\.height/);
    assert.match(drawer, /drawerArrival\.visible \? drawerArrival\.height \+ spacing : 0/);
    assert.match(drawer, /bodyHeightLimit:[\s\S]{0,320}?- sessionFooter\.height - spacing\)/,
        "the pinned row comes out of the body's height");
    assert.match(drawer, /Flickable\s*\{[\s\S]{0,100}?id:\s*bodyFlick/);
    assert.match(drawer, /contentHeight:\s*bodyLoader\.implicitHeight/);
    assert.match(drawer, /ScrollChrome\s*\{[\s\S]{0,100}?target:\s*bodyFlick[\s\S]{0,60}?edgeColor:\s*root\.surfaceColor/);
    assert.match(drawer, /scrollGutter:\s*bodyFlick\.interactive \? Theme\.scaled\(12\)/);
    assert.match(drawer, /width:\s*Math\.max\(0, bodyFlick\.width - root\.scrollGutter\)/);
    assert.match(drawer,
        /onTabChanged:[\s\S]{0,100}?bodyFlick\.contentY = 0/,
        "every tab switch must return its new body to the top");
    assert.match(drawer,
        /onActiveFocusItemChanged\(\)[\s\S]{0,180}?root\.revealFocus\(item\)/,
        "keyboard focus must be revealed inside an overflowed body");
    assert.match(drawer, /const margin = bodyChrome\.fadeSize \+ Theme\.scaled\(4\);/,
        "a revealed control must land clear of the edge fade");
    assert.match(drawer,
        /function handleEscape\(\): bool \{\s*if \(sessionFooter\.confirming\) \{\s*sessionFooter\.cancel\(\);\s*return true;/,
        "Escape answers a pending session question before it closes the drawer");
    assert.match(drawer, /onSessionConfirmRequested:[\s\S]{0,120}?sessionFooter\.ask\(action, origin, version\)/);
});

test("the session row labels Lock, groups the rest, and confirms what ends the session", () => {
    // 2026-11 UI council: three labelled buttons instead of eight bare icons.
    const buttons = [...footer.matchAll(/SessionButton \{\s*id: (\w+)\s*(?:glyph: "(\w+)"\s*)?label: "([^"]+)"/g)]
        .map(match => [match[1], match[2] || "", match[3]]);
    assert.deepEqual(buttons, [["lockButton", "lock", "Lock"], ["powerButton", "power_settings_new", "Power"],
        ["moreButton", "", "More"]]);
    assert.match(footer, /onClicked: \{ Popouts\.close\(\); Session\.lock\(\); \}/);
    assert.match(footer, /menu: powerMenu[\s\S]{0,160}?onClicked: powerMenu\.toggle\(\)/);
    assert.match(footer, /menu: moreMenu[\s\S]{0,160}?onClicked: moreMenu\.toggle\(\)/);
    const entries = name => [...footer.slice(footer.indexOf(`id: ${name}`)).split("onChosen")[0]
        .matchAll(/\{ id: "(\w+)", glyph: "(\w+)", label: "([^"]+)" \}/g)].map(match => match.slice(1));
    assert.deepEqual(entries("powerMenu"), [["sleep", "sleep", "Sleep"], ["reboot", "restart_alt", "Restart…"],
        ["shutdown", "power_settings_new", "Shut down…"], ["logout", "logout", "Log out…"]]);
    assert.deepEqual(entries("moreMenu"), [["settings", "settings", "Settings"],
        ["shortcuts", "keyboard", "Keyboard shortcuts"], ["screenshot", "photo_camera", "Screenshot"]]);
    const run = footer.slice(footer.indexOf("function run(action)"), footer.indexOf("component SessionButton"));
    assert.match(run, /"sleep"\) \{\s*Popouts\.close\(\);\s*Session\.suspend\(\);/, "Sleep acts at once");
    assert.match(run, /action === "reboot" \|\| action === "shutdown" \|\| action === "logout"\) \{\s*ask\(action, powerButton\);/,
        "ending the session asks first, and Cancel returns to Power");
    assert.match(run, /Session\.toggleKeys\(\)/);
    assert.match(run, /Settings\.showPanel\(undefined, Popouts\.hostScreenName\)/);
    assert.match(run, /"screenshot region"/);
    // Buttons: secondary tier, 32 px, named; menus: keyboard, Escape, focus.
    const button = footer.slice(footer.indexOf("component SessionButton"));
    assert.match(button, /height: Math\.max\(Theme\.inlineActionHeight/);
    assert.match(button, /Accessible\.role: menu !== null \? Accessible\.ButtonMenu : Accessible\.Button/);
    assert.match(menu, /closePolicy: Controls\.Popup\.CloseOnEscape \| Controls\.Popup\.CloseOnPressOutsideParent/);
    assert.match(menu, /Qt\.Key_Down\) root\.focusEntry\(index \+ 1\)/);
    assert.match(menu, /Qt\.Key_Escape\) root\.dismiss\(\)/);
    assert.match(menu, /function dismiss\(\) \{\s*close\(\);\s*if \(opener && opener\.visible\)\s*opener\.forceActiveFocus\(\);/);
    assert.match(menu, /height: Math\.max\(Theme\.inlineActionHeight/);
    assert.match(drawer, /if \(sessionFooter\.menuOpen\) \{\s*sessionFooter\.dismissMenu\(\);\s*return true;/,
        "Escape closes an open menu before the drawer");

    const confirm = footer.slice(footer.indexOf("function confirm()"), footer.indexOf("function reset()"));
    assert.match(confirm, /Session\.logout\(\)/);
    assert.match(confirm, /Session\.shutdown\(\)/);
    assert.match(confirm, /Session\.reboot\(\)/);
    assert.match(footer, /cancelButton\.forceActiveFocus\(\)/, "focus moves to Cancel");
    assert.match(footer, /id: cancelButton[\s\S]{0,700}?Keys\.onReturnPressed: root\.confirm\(\)[\s\S]{0,60}?Keys\.onEnterPressed: root\.confirm\(\)[\s\S]{0,60}?onTriggered: root\.cancel\(\)/,
        "Return answers with the default; Cancel's own press cancels");
    assert.match(footer, /function onOpenChanged\(\) \{\s*if \(!Popouts\.open\)\s*root\.reset\(\);/,
        "closing the drawer drops a pending question");
    assert.match(footer, /function reset\(\) \{[\s\S]{0,80}?closeMenus\(\);/, "and an open menu");
    assert.match(footer, /Math\.max\(Theme\.scaled\(52\)/);
});

test("every tab is labelled, and the strip wraps rather than cutting a label", () => {
    for (const [tab, glyph, label] of [["overview", "dashboard", "Overview"], ["sound", "volume_down", "Sound"],
        ["network", "wifi", "Network"], ["bluetooth", "bluetooth", "Bluetooth"], ["power", "battery_5_bar", "Power"],
        ["notifications", "notifications", "Alerts"]])
        assert.match(tabs, new RegExp(`${tab}: \\{ glyph: "${glyph}", label: "${label}"`));
    assert.match(tabs, /name: "Notifications"/, "the tooltip and description keep the full name");
    assert.doesNotMatch(tabs, /showLabel|restingWidth|elide/, "no tab hides or elides its label");
    assert.match(tabs, /layout: DrawerFormat\.tabLayout\(/);
    assert.match(tabs, /columns: root\.layout\.stacked \? 1 : 2/);
    assert.match(tabs, /wrapMode: Text\.Wrap/);
});

test("Sound, Network, Bluetooth and Power share one empty-state pattern", () => {
    assert.match(qmldir, /^DrawerEmptyState DrawerEmptyState\.qml$/m);
    for (const prop of ["glyph", "title", "detail", "actionText"])
        assert.match(emptyState, new RegExp(`property string ${prop}:`));
    assert.match(emptyState, /signal action\(\)/);
    assert.match(emptyState, /visible: root\.actionText !== ""/, "at most one action, none when there is nothing to do");
    assert.equal((emptyState.match(/wrapMode: Text\.Wrap/g) || []).length, 2, "cause and detail wrap");
    for (const [name, source] of [["Sound", sound], ["Network", network], ["Bluetooth", bluetooth], ["Power", power]]) {
        assert.match(source, /DrawerEmptyState \{\s*visible: root\.emptyKind !== ""/, `${name} uses the pattern`);
        assert.match(source, /readonly property string emptyKind:/, `${name} names its empty states`);
    }
    // Missing hardware, turned off and a service that is not running read differently.
    assert.match(sound, /"Sound service isn't running"/);
    assert.match(sound, /"No speakers or headphones"/);
    assert.match(network, /QsNetworking\.Networking\.backend === QsNetworking\.NetworkBackendType\.None/);
    for (const title of ["Network service isn't running", "No network adapter found", "No cable connected",
        "Wi-Fi is blocked", "Wi-Fi is off"])
        assert.ok(network.includes(`"${title}"`), title);
    assert.match(network, /if \(root\.emptyKind === "off"\)\s*WifiState\.setEnabled\(true\)/);
    for (const title of ["Bluetooth service isn't running", "No Bluetooth adapter found", "Bluetooth is blocked",
        "Bluetooth is off"])
        assert.ok(bluetooth.includes(`"${title}"`), title);
    assert.match(bluetooth, /\/sys\/class\/bluetooth\/hci\*/, "an unseen controller is told apart from a stopped service");
    assert.match(bluetooth, /onAction: BluetoothState\.setEnabled\(true\)/);
    assert.match(power, /"Power service isn't running"/);
    assert.match(power, /"No battery"/);
    // No duplicate messages, no jargon, nothing shown for what is not there.
    assert.doesNotMatch(bluetooth, /"Bluetooth unavailable"|"No Bluetooth adapter"/);
    assert.doesNotMatch(sound, /info: "PipeWire"/);
    assert.doesNotMatch(power, /Idle inhibit|"Perf"/);
    assert.match(network, /visible: !Tailscale\.missing\s*width: parent\.width\s*height: 40/,
        "no Tailscale row when it is not installed");
    assert.match(network, /id: wifiToggle\s*visible: root\.wifiPresent/, "no Wi-Fi switch without an adapter");
    assert.match(network, /enabled: !root\.wifiBlocked/);
    assert.match(bluetooth, /DrawerEmptyState \{[\s\S]*?\n    Item \{\s*visible: root\.emptyKind === ""/,
        "no Bluetooth switch without an adapter: the header goes with the empty state");
    assert.match(power, /visible: Battery\.isLaptop && \(BatteryHealth\.supported \|\| !BatteryHealth\.known\)/,
        "battery health only where there is a battery");
});

test("a pending update offers one action; restarting goes through the session row", () => {
    assert.match(overview, /objectName: "overviewUpdates"\s*visible: Settings\.drawerOverview\.updates === true && root\.updateService\.overviewVisible/);
    assert.match(overview, /restartPending: updateService\.page === "restart"/,
        "Restart… appears exactly where Software Update offers Restart Now");
    assert.match(overview, /"Cybex OS %1 is ready"/);
    assert.match(overview,
        /objectName: "overviewUpdateRestart"[\s\S]{0,600}?enabled: !root\.updateService\.runActive && !root\.updateService\.requestPending[\s\S]{0,120}?onTriggered: root\.sessionConfirmRequested\(/);
    assert.doesNotMatch(overview, /Session\.reboot\(\)/,
        "Overview never restarts by itself");
    assert.match(overview,
        /objectName: "overviewUpdateReview"[\s\S]{0,900}?onTriggered: \{\s*Popouts\.close\(\);\s*root\.updateService\.show\(\);/);
    assert.match(footer, /"Restart to install Cybex OS %1\?"/);
});

test("Top processes shows five rows, three when short, and reveals × on demand", () => {
    assert.match(overview, /maxRows: DrawerFormat\.processRows\(root\.bodyHeightBudget/);
    assert.match(drawer, /bodyHeightBudget: availableHeight > 0 \? bodyHeightLimit : 0/,
        "the row count reads the body's envelope, never its own content");
    assert.match(processes, /model: Math\.min\(ProcessList\.limit, root\.maxRows\)/);
    assert.match(processes,
        /revealed: slotHover\.hovered \|\| endButton\.activeFocus \|\| selected/);
    assert.match(processes, /opacity: !slot\.revealed \? 0 : enabled \? 1 : 0\.4/);
    assert.match(processes,
        /selected: row !== null && root\.subject !== null\s*&& root\.subject\.pid === row\.pid && root\.subject\.start === row\.start/,
        "the selected row is the captured PID, not a rank");
    assert.match(processes, /function onConfirmingChanged\(\)[\s\S]{0,300}?cancelLink\.forceActiveFocus\(\)/,
        "a new question takes focus to its Cancel");
    assert.doesNotMatch(processes, /Show all/);
    assert.doesNotMatch(processes, /Timer\s*\{/, "revealing × needs no timer");
});

test("Power no longer owns machine stats", () => {
    assert.doesNotMatch(power, /id:\s*statsGrid/);
    assert.doesNotMatch(power, /SysInfo\.(?:cpuUsage|memUsage|cpuTemp)/);
    assert.doesNotMatch(power, /SysInfo\.(?:acquire|release)\(\)/,
        "opening Power must not start the stats sampler");
});

test("Overview no longer exposes model usage", () => {
    assert.doesNotMatch(overview,
        /MODEL USAGE|DrawerUsageRows|Settings\.drawerOverview\.usage|Usage\./);
    assert.doesNotMatch(drawerSettings,
        /key:\s*"usage"\s*,\s*label:\s*"Model usage"/);
});
