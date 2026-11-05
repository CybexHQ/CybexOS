pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../Common"
import "../Common/Format.js" as Format
import "../Common/SysInfoHelpers.js" as SysInfoHelpers
import "LocalTime.js" as LocalTime

// Home (2026-10 redesign): this computer at a glance, and what needs the
// person. It replaces About: the identity and update state sit at the top,
// storage, battery, backups and network in one strip under them, then
// anything waiting — unapplied changes, a system change to review or
// restart into, backups that are not set up, the read-only system check's
// findings — then the settings changed recently, each with Undo, and last
// what About held: shell health, the Welcome guide, the settings file and
// Reset all. Every row reads as label, value and action on the page's one
// control edge, as everywhere else in Settings.
//
// 2026-11 (docs/shell-states.md): actions come in three tiers with at most
// one primary per group, each attention item carries a status pill beside
// its action, and below ~560 px of column (`compact`) the page reflows
// rather than eliding — the update state moves under the identity, the
// readings go two by two and wrap, and attention items stack.
SettingsPage {
    id: page
    objectName: "settingsHomePage"

    property string releaseVersion: ""
    property double nowMs: Date.now()

    // The shell's own status colours: green healthy, amber running with a
    // problem, red not running. The accent is a mark, not a verdict.
    readonly property color healthColor: !ShellHealth.serviceActive ? Theme.red
        : !ShellHealth.healthy || ShellHealth.issueCount > 0 ? Theme.amber
        : Theme.connected

    readonly property string versionLine: [
        page.releaseVersion !== "" ? "Cybex OS " + page.releaseVersion : "Cybex OS",
        [SysInfo.osName, SysInfo.osVersion].filter(Boolean).join(" ")
    ].filter(Boolean).join(" · ")
    readonly property string hardwareLine: {
        const vendor = SysInfo.deviceVendor, model = SysInfo.deviceModel;
        const device = model.toLowerCase().startsWith(vendor.toLowerCase()) ? model
            : [vendor, model].filter(Boolean).join(" ");
        const cpu = SysInfo.cpuModel.replace(/\((R|TM|tm|r)\)/g, "").replace(/\s+CPU\b.*$/, "")
            .replace(/\s+\d+-Core Processor$/, "").replace(/\s+/g, " ").trim();
        return [device, cpu, page.memoryTotal].filter(Boolean).join(" · ");
    }
    // Memory in binary units, labelled as such, and as a whole number: a
    // total reads the way the RAM was bought ("31 GiB"), where the drawer's
    // live readings keep their decimal.
    readonly property string memoryTotal: SysInfo.memTotalBytes > 0
        ? SysInfoHelpers.formatIecBytes(Math.round(SysInfo.memTotalBytes / 1073741824) * 1073741824) : ""

    // One short line for the update state, most urgent first.
    readonly property string updateLabel: Updates.rebootRecommended ? I18n.tr("Restart to finish")
        : Updates.ready ? (Updates.deployment.changeKind === "update" ? I18n.tr("Update ready to install")
            : I18n.tr("System change ready"))
        : Updates.runActive ? I18n.tr("Preparing…")
        : Updates.hasUpdates ? I18n.tr("Updates available")
        : Updates.sourcesLoaded ? I18n.tr("Up to date")
        : I18n.tr("Not checked yet")
    readonly property string updateTone: Updates.rebootRecommended || Updates.ready || Updates.hasUpdates
        || Updates.runActive ? "info" : Updates.sourcesLoaded ? "ok" : "neutral"

    // What Home lists under "Needs attention", most urgent first. Each entry
    // carries its words and the one action that settles it.
    readonly property var attention: {
        const list = [];
        const changes = SettingsChanges.count;
        if (SettingsChanges.deploymentState === "restart")
            list.push({ id: "restart", tone: "info", status: I18n.tr("Restart needed"),
                title: I18n.tr("Restart to finish the system change"),
                detail: I18n.tr("It is built and checked. The previous system stays as a recovery point."),
                action: I18n.tr("Software Update…") });
        else if (SettingsChanges.deploymentState === "review")
            list.push({ id: "review", tone: "info", status: I18n.tr("Ready"),
                title: I18n.tr("A system change is ready to review"),
                detail: I18n.tr("Review it in Software Update, then restart to use it."),
                action: I18n.tr("Review…") });
        else if (SettingsChanges.deploymentState === "preparing")
            list.push({ id: "preparing", tone: "amber", status: I18n.tr("In progress"),
                title: I18n.tr("Preparing a system change"),
                detail: Updates.runPhaseLabel || I18n.tr("You can keep working or close Settings."), action: "" });
        if (changes > 0)
            list.push({ id: "changes", tone: "info", status: I18n.tr("Not applied"),
                title: changes === 1 ? I18n.tr("1 change waiting to be applied")
                    : I18n.format("%1 changes waiting to be applied", [changes]),
                detail: SettingsChanges.pages.map(id => Settings.pageInfo(id).label).join(", "),
                action: I18n.tr("Review…") });
        if (Backup.status.valid && !Backup.configured)
            list.push({ id: "backup", tone: "amber", status: I18n.tr("Not set up"),
                title: I18n.tr("Personal files aren’t backed up"),
                detail: I18n.tr("Back up to a drive or an SSH server, protected by a recovery key."),
                action: I18n.tr("Set up…") });
        for (const check of Doctor.attention)
            list.push({ id: "check:" + check.id, tone: check.state === "problem" ? "red" : "amber",
                status: check.state === "problem" ? I18n.tr("Problem") : I18n.tr("Suggestion"),
                title: Doctor.sentence(check), detail: I18n.tr("Found by the system check"),
                action: page.checkAction(check.id) });
        return list;
    }
    // The group's one primary: the most urgent item that has an action.
    readonly property int leadAttention: attention.findIndex(item => item.action !== "")

    function checkAction(id) {
        switch (id) {
        case "firmware-updates": return I18n.tr("Software Update…");
        case "storage": return I18n.tr("Disk space…");
        case "battery": return I18n.tr("Power…");
        case "audio": return I18n.tr("Sound…");
        case "time": return I18n.tr("Region…");
        }
        return Assistant.connected ? I18n.tr("Ask the assistant") : "";
    }

    function show(target, tab, key) {
        if (tab)
            Settings.setTab(target, tab);
        Settings.page = target;
        if (key) {
            Settings.highlightKey = "";
            Settings.highlightKey = key;
        }
    }

    function act(item) {
        switch (item.id) {
        case "restart":
        case "review":
            Updates.show();
            return;
        case "changes":
            SettingsChanges.reviewRequested();
            return;
        case "backup":
            page.show("backup", "backups");
            return;
        case "check:firmware-updates":
            Updates.show();
            return;
        case "check:storage":
            page.show("backup", "storage");
            return;
        case "check:battery":
            page.show("power");
            return;
        case "check:audio":
            page.show("sound");
            return;
        case "check:time":
            page.show("region");
            return;
        }
        if (item.id.startsWith("check:") && Assistant.connected)
            Assistant.checkSystem();
    }

    function openConfig() {
        Settings.saveNow();
        Qt.callLater(() => {
            Settings.closePanel();
            Quickshell.execDetached(["xdg-open", Settings.filePath]);
        });
    }

    Claim {
        active: page.visible && Settings.panelOpen
        onClaimed: SysInfo.acquire()
        onReleased: SysInfo.release()
    }
    Binding {
        target: Backup
        property: "watched"
        value: page.visible && Settings.panelOpen
    }
    // The page loads asynchronously, often already visible, so a visibility
    // edge alone would leave the first open showing a stale probe.
    Component.onCompleted: {
        ShellHealth.refresh();
        Doctor.refreshIfStale();
        Backup.refresh();
    }
    onVisibleChanged: {
        if (visible) {
            ShellHealth.refresh();
            Doctor.refreshIfStale();
        }
    }
    Timer {
        interval: 60000
        running: page.visible
        repeat: true
        onTriggered: page.nowMs = Date.now()
    }
    FileView {
        path: "/etc/cybexos/release.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                page.releaseVersion = String(JSON.parse(text()).version || "");
            } catch (error) {
                page.releaseVersion = "";
            }
        }
    }

    // One cell of the glance strip: a caption, a reading, a quieter line and,
    // for storage, a meter. A cell with a page to go to is a button and shows
    // a chevron while it is hovered or holds keyboard focus; one without
    // (memory) is plain text, with no button semantics at all. Copy wraps
    // rather than elides, so "412 GB free" keeps its meaning at any width.
    component GlanceCell: Item {
        id: cell
        property string caption: ""
        property string value: ""
        property string detail: ""
        property string destination: ""
        property real meter: -1
        property bool warn: false
        property bool interactive: true
        signal activated()

        readonly property bool pointed: cellMouse.containsMouse
        readonly property bool ringShown: Theme.focusWidth(activeFocus) > 0

        implicitHeight: cellColumn.implicitHeight + Theme.scaled(24)
        activeFocusOnTab: interactive
        Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
        Accessible.name: cell.caption + ", " + cell.value + (cell.detail !== "" ? ", " + cell.detail : "")
        Accessible.description: cell.interactive && cell.destination !== ""
            ? I18n.format("Opens %1", [cell.destination]) : ""
        Accessible.onPressAction: {
            if (cell.interactive)
                cell.activated();
        }
        Keys.onPressed: event => {
            if (cell.interactive && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space)) {
                cellState.pulseCenter();
                cell.activated();
                event.accepted = true;
            }
        }

        StateLayer {
            id: cellState
            anchors.fill: parent
            visible: cell.interactive
            hovered: cell.pointed
            pressed: cellMouse.pressed
            tint: Theme.textHi
            pressPoint: Qt.point(cellMouse.mouseX, cellMouse.mouseY)
        }

        // The keyboard ring, inside the cell so the strip's edge cannot clip it.
        Rectangle {
            anchors.fill: parent
            visible: cell.ringShown
            radius: Theme.chipRadius
            color: "transparent"
            border.width: Theme.focusWidth(cell.activeFocus)
            border.color: Theme.focusRing
        }

        Sym {
            id: chevron
            visible: cell.interactive && (cell.pointed || cell.ringShown)
            x: parent.width - width - Theme.scaled(8)
            y: cellColumn.y
            name: "chevron_right"
            size: Theme.iconSmall
            color: Theme.textMid
        }

        Column {
            id: cellColumn
            x: Theme.settingsMarkInset
            y: Theme.scaled(12)
            width: parent.width - x - Theme.scaled(10) - (cell.interactive ? chevron.width : 0)
            spacing: Theme.scaled(4)

            Text {
                width: parent.width
                text: cell.caption.toUpperCase()
                wrapMode: Text.Wrap
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightSemibold
                font.letterSpacing: 1
                color: Theme.textFaint
            }
            Text {
                width: parent.width
                text: cell.value
                wrapMode: Text.Wrap
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.title
                font.weight: Theme.weightSemibold
                color: cell.warn ? Theme.amber : Theme.textHi
            }
            Rectangle {
                visible: cell.meter >= 0
                width: parent.width
                height: Theme.scaled(4)
                radius: height / 2
                color: Theme.chipHover
                Rectangle {
                    width: parent.width * Format.clamp01(cell.meter)
                    height: parent.height
                    radius: parent.radius
                    color: cell.meter > 0.9 ? Theme.amber : Theme.textMid
                }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: cell.detail
                wrapMode: Text.Wrap
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                color: Theme.textFaint
            }
        }

        MouseArea {
            id: cellMouse
            anchors.fill: parent
            enabled: cell.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.activated()
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.settingsGroupSpacing

        Column {
            width: parent.width
            spacing: Theme.scaled(18)

            // The identity, and the update state beside it; in a narrow
            // column the state moves under the identity instead of
            // squeezing the name, and every line wraps rather than elides.
            Item {
                id: hero
                width: parent.width
                readonly property real identityHeight: Math.max(logo.height, heroText.implicitHeight)
                readonly property real rightEdge: width - Theme.chipHeight
                height: page.compact ? identityHeight + Theme.scaled(12) + heroSide.height
                    : Math.max(identityHeight, heroSide.height)

                // The mark is drawn for charcoal, so it keeps its own tile in
                // a light theme too, as an application icon does.
                Rectangle {
                    id: logo
                    x: Theme.settingsMarkInset
                    y: page.compact ? (hero.identityHeight - height) / 2 : (hero.height - height) / 2
                    width: Theme.scaled(50)
                    height: width
                    radius: Theme.scaled(12)
                    color: Theme.darkBackground
                    border.width: Theme.dark ? 1 : 0
                    border.color: Theme.hairlineSoft
                    BrandIcon {
                        anchors.centerIn: parent
                        width: parent.width * 0.74
                        height: width
                        name: "cybexos"
                    }
                }
                Column {
                    id: heroText
                    x: logo.x + logo.width + Theme.scaled(16)
                    y: page.compact ? (hero.identityHeight - implicitHeight) / 2
                        : (hero.height - implicitHeight) / 2
                    width: Math.max(0, (page.compact ? hero.rightEdge
                        : heroSide.x - Theme.controlSpacing) - x)
                    spacing: Theme.scaled(2)

                    Text {
                        width: parent.width
                        text: SysInfo.host !== "" ? SysInfo.host : I18n.tr("This computer")
                        wrapMode: Text.Wrap
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.heading
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }
                    Text {
                        width: parent.width
                        text: page.versionLine
                        wrapMode: Text.Wrap
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        color: Theme.textFaint
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: page.hardwareLine
                        wrapMode: Text.Wrap
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        color: Theme.textFaint
                    }
                }
                // The update state as a pill over its action, or beside it
                // under the identity when the column is narrow.
                Item {
                    id: heroSide
                    readonly property real gap: Theme.scaled(8)
                    readonly property real rowWidth: updatePill.width + gap + updateAction.width
                    width: page.compact ? rowWidth : Math.max(updatePill.width, updateAction.width)
                    height: page.compact ? Math.max(updatePill.height, updateAction.height)
                        : updatePill.height + gap + updateAction.height
                    // Under the copy when the row fits there, else under the mark.
                    x: !page.compact ? hero.rightEdge - width
                        : heroText.x + rowWidth <= hero.rightEdge ? heroText.x : logo.x
                    y: page.compact ? hero.identityHeight + Theme.scaled(12) : (hero.height - height) / 2

                    StatusPill {
                        id: updatePill
                        x: page.compact ? 0 : parent.width - width
                        y: page.compact ? (parent.height - height) / 2 : 0
                        text: page.updateLabel
                        tone: page.updateTone
                    }
                    SettingsAction {
                        id: updateAction
                        x: page.compact ? updatePill.width + heroSide.gap : parent.width - width
                        y: page.compact ? (parent.height - height) / 2 : updatePill.height + heroSide.gap
                        secondary: true
                        text: I18n.tr("Software Update…")
                        onTriggered: Updates.show()
                    }
                }
            }

            // The glance strip: four readings between hairlines, each one with
            // a page a way into it. Four across, or two by two in a narrow
            // column; the cells of a row share its height.
            Item {
                id: glance
                width: parent.width
                readonly property int columns: page.compact ? 2 : 4
                readonly property real cellWidth: (width - (columns - 1)) / columns
                readonly property real firstRowHeight: columns === 4
                    ? Math.max(storageCell.implicitHeight, secondCell.implicitHeight,
                        backupCell.implicitHeight, networkCell.implicitHeight)
                    : Math.max(storageCell.implicitHeight, secondCell.implicitHeight)
                readonly property real secondRowHeight: columns === 4 ? 0
                    : Math.max(backupCell.implicitHeight, networkCell.implicitHeight)
                readonly property real secondRowY: 2 + firstRowHeight
                height: columns === 4 ? firstRowHeight + 2 : secondRowY + secondRowHeight + 1

                function cellX(index) {
                    return (index % columns) * (cellWidth + 1);
                }
                function cellY(index) {
                    return index < columns ? 1 : secondRowY;
                }
                function cellHeight(index) {
                    return index < columns ? firstRowHeight : secondRowHeight;
                }

                Rectangle { width: parent.width; height: 1; color: Theme.hairlineSoft }
                Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Theme.hairlineSoft }
                Rectangle {
                    visible: glance.columns === 2
                    y: glance.secondRowY - 1
                    width: parent.width
                    height: 1
                    color: Theme.hairlineSoft
                }
                Repeater {
                    // Between two cells of a row: three across, or one per row.
                    model: glance.columns === 4 ? [1, 2, 3] : [1, 3]
                    delegate: Rectangle {
                        required property int modelData
                        x: glance.cellX(modelData) - 1
                        y: glance.cellY(modelData)
                        width: 1
                        height: glance.cellHeight(modelData)
                        color: Theme.hairlineSoft
                    }
                }

                GlanceCell {
                    id: storageCell
                    x: glance.cellX(0)
                    y: glance.cellY(0)
                    width: glance.cellWidth
                    height: glance.cellHeight(0)
                    caption: I18n.tr("Storage")
                    value: SysInfo.rootFsKnown
                        ? I18n.format("%1 free", [SysInfoHelpers.formatStorageBytes(SysInfo.rootFsAvailableBytes)]) : "—"
                    meter: SysInfo.rootFsKnown ? SysInfo.rootFsUsage / 100 : -1
                    warn: SysInfo.rootFsKnown && SysInfo.rootFsUsage > 90
                    detail: SysInfo.rootFsKnown
                        ? I18n.format("of %1", [SysInfoHelpers.formatStorageBytes(SysInfo.rootFsTotalBytes)]) : ""
                    destination: I18n.tr(Settings.pageInfo("backup").label)
                    onActivated: page.show("backup", "storage")
                }
                GlanceCell {
                    id: secondCell
                    x: glance.cellX(1)
                    y: glance.cellY(1)
                    width: glance.cellWidth
                    height: glance.cellHeight(1)
                    caption: Battery.isLaptop ? I18n.tr("Battery") : I18n.tr("Memory")
                    value: Battery.isLaptop ? I18n.format("%1%", [Math.round(Battery.percent)])
                        : page.memoryTotal !== "" ? page.memoryTotal : "—"
                    detail: Battery.isLaptop ? Battery.statusText
                        : SysInfo.memKnown ? I18n.format("%1% in use", [Math.round(SysInfo.memUsage)]) : ""
                    warn: Battery.isLaptop && Battery.percent < 15 && !Battery.pluggedIn
                    // Memory has no page of its own to open.
                    interactive: Battery.isLaptop
                    destination: I18n.tr(Settings.pageInfo("power").label)
                    onActivated: page.show("power")
                }
                GlanceCell {
                    id: backupCell
                    x: glance.cellX(2)
                    y: glance.cellY(2)
                    width: glance.cellWidth
                    height: glance.cellHeight(2)
                    caption: I18n.tr("Backups")
                    value: !Backup.status.valid ? "—"
                        : !Backup.configured ? I18n.tr("Not set up")
                        : Backup.running ? I18n.tr("Backing up…")
                        : Backup.status.lastSuccess !== ""
                        ? LocalTime.fromText(Backup.status.lastSuccess, page.nowMs, Settings.clock24, I18n.tr("Done"))
                        : I18n.tr("None yet")
                    warn: Backup.status.valid && (!Backup.configured || Backup.status.stale)
                    detail: Backup.configured ? Backup.status.destination.display : I18n.tr("Personal files")
                    destination: I18n.tr(Settings.pageInfo("backup").label)
                    onActivated: page.show("backup", "backups")
                }
                GlanceCell {
                    id: networkCell
                    x: glance.cellX(3)
                    y: glance.cellY(3)
                    width: glance.cellWidth
                    height: glance.cellHeight(3)
                    caption: I18n.tr("Network")
                    value: WifiState.connected ? WifiState.name
                        : NetworkStatus.online ? I18n.tr("Online") : I18n.tr("Offline")
                    warn: NetworkStatus.known && !NetworkStatus.online
                    detail: WifiState.connected ? I18n.format("Wi-Fi · %1%", [WifiState.signal])
                        : NetworkStatus.online ? I18n.tr("Wired") : ""
                    destination: I18n.tr(Settings.pageInfo("network").label)
                    onActivated: page.show("network")
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("Needs attention")

            Repeater {
                model: page.attention
                delegate: AttentionRow {
                    id: attentionRow
                    required property var modelData
                    required property int index
                    width: parent.width
                    title: modelData.title
                    detail: modelData.detail
                    status: modelData.status
                    tone: modelData.tone
                    // The most urgent item leads with the group's one primary;
                    // the others stay secondary beside it.
                    SettingsAction {
                        visible: attentionRow.modelData.action !== ""
                        text: attentionRow.modelData.action
                        primary: attentionRow.index === page.leadAttention
                        secondary: !primary
                        Accessible.name: attentionRow.modelData.action + ", " + attentionRow.modelData.title
                        onTriggered: page.act(attentionRow.modelData)
                    }
                }
            }
            // The check itself reads like the items it finds: a pill with its
            // verdict, and a sentence for anything longer (a failed run's
            // reason), so nothing has to elide in a narrow column.
            AttentionRow {
                width: parent.width
                property string searchAnchor: "home-checks"
                title: I18n.tr("System check")
                status: Doctor.running ? I18n.tr("Checking…")
                    : Doctor.report === null ? (Doctor.error !== "" ? I18n.tr("Could not run") : I18n.tr("Not checked yet"))
                    : Doctor.attention.length === 0 ? I18n.tr("Everything looks good")
                    : Doctor.attention.length === 1 ? I18n.tr("1 thing to look at")
                    : I18n.format("%1 things to look at", [Doctor.attention.length])
                tone: Doctor.running || Doctor.report === null ? "neutral"
                    : Doctor.attention.length > 0 ? "amber" : "ok"
                detail: Doctor.report !== null
                    ? I18n.tr("Read-only; nothing leaves this computer. Checked ")
                        + LocalTime.fromText(Doctor.report.checkedAt, page.nowMs, Settings.clock24, "")
                    : (Doctor.error !== "" && !Doctor.running ? Doctor.error + " " : "")
                        + I18n.tr("Read-only; nothing leaves this computer.")
                SettingsAction {
                    text: Doctor.running ? I18n.tr("Checking") : I18n.tr("Check again")
                    glyph: "refresh"
                    enabled: !Doctor.running
                    onTriggered: Doctor.refresh()
                }
            }
        }

        SettingsGroup {
            width: parent.width
            visible: SettingsRecent.rows.length > 0
            title: I18n.tr("Recently changed")

            Repeater {
                model: SettingsRecent.rows.slice(0, 5)
                delegate: ValueRow {
                    id: recentRow
                    required property var modelData
                    width: parent.width
                    label: modelData.label
                    value: modelData.values ? modelData.before + " → " + modelData.after : ""
                    hint: modelData.pageLabel + " · " + modelData.when
                    SettingsAction {
                        text: I18n.tr("Show")
                        Accessible.name: I18n.tr("Show ") + recentRow.modelData.label
                        onTriggered: {
                            if (recentRow.modelData.widget !== "")
                                Settings.openWidgetSettings(recentRow.modelData.widget);
                            page.show(recentRow.modelData.page, recentRow.modelData.tab, recentRow.modelData.anchor);
                        }
                    }
                    SettingsAction {
                        text: I18n.tr("Undo")
                        glyph: "undo"
                        Accessible.name: I18n.tr("Undo ") + recentRow.modelData.label
                        onTriggered: SettingsRecent.undo(recentRow.modelData)
                    }
                }
            }
        }

        SettingsGroup {
            width: parent.width
            title: I18n.tr("About this computer")

            ValueRow {
                width: parent.width
                label: I18n.tr("Desktop shell")
                dotColor: page.healthColor
                value: ShellHealth.busy ? I18n.tr("Checking…") : ShellHealth.statusLabel
                hint: ShellHealth.issueCount > 0
                    ? (ShellHealth.integrationIssues.concat(ShellHealth.recentWarnings))[0] || ""
                    : ShellHealth.serviceActive
                    ? "PID " + ShellHealth.servicePid + " · " + I18n.tr("up ") + ShellHealth.uptimeLabel()
                        + (ShellHealth.deploymentId !== ""
                            ? " · " + I18n.tr("deployment ") + ShellHealth.deploymentId.slice(0, 10) + " " + ShellHealth.deploymentStatus : "")
                        + (ShellHealth.deploymentCheckedAt
                            ? " · " + I18n.tr("checked ") + LocalTime.fromText(ShellHealth.deploymentCheckedAt,
                                page.nowMs, Settings.clock24, ShellHealth.deploymentCheckedAt) : "")
                    : (ShellHealth.refreshError || I18n.tr("Inactive"))
                hintTone: ShellHealth.issueCount > 0 ? "warning" : "info"
                SettingsAction {
                    text: ShellHealth.busy ? I18n.tr("Checking") : I18n.tr("Refresh")
                    glyph: "refresh"
                    Accessible.name: I18n.tr("Refresh shell health")
                    onTriggered: ShellHealth.refresh()
                }
            }
            ValueRow {
                width: parent.width
                label: I18n.tr("Welcome guide")
                hint: I18n.tr("Make yourself at home. Continue where you left off.")
                SettingsAction {
                    text: I18n.tr("Open")
                    Accessible.name: I18n.tr("Open the welcome guide")
                    onTriggered: Welcome.show("")
                }
            }
            ValueRow {
                width: parent.width
                label: I18n.tr("Settings file")
                hint: "~/.config/cybexos/shell.json"
                SettingsAction {
                    text: I18n.tr("Open")
                    glyph: "open_in_new"
                    Accessible.name: I18n.tr("Open the settings file")
                    onTriggered: page.openConfig()
                }
            }
        }

        // Reset all gets a group of its own rather than a place under Open,
        // where a slip lands on it; the header's Undo still covers it.
        SettingsGroup {
            width: parent.width
            title: I18n.tr("Reset")

            ValueRow {
                width: parent.width
                label: I18n.tr("Reset all settings")
                hint: I18n.tr("Every page back to its defaults. You can undo for 8 seconds.")
                SettingsAction {
                    text: I18n.tr("Reset all")
                    glyph: "restart_alt"
                    danger: true
                    onTriggered: Settings.resetAll()
                }
            }
        }
    }
}
