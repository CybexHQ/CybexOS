pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../../Common"
import "../../Common/SysInfoHelpers.js" as SysInfoHelpers
import "DrawerFormat.js" as DrawerFormat
import ".."

// Overview's system summary: which system this is, then how its core
// resources are doing. It stays independent of drawer section settings:
// opening the Cybex OS button always answers both.
//
// One identity line ("Cybex OS 1.0.17 · NixOS 26.11", as Settings Home
// writes it) and the machine with its uptime; then CPU, memory and disk as
// two-line meters, a label and its full reading over a segmented meter, so
// the reading never has to be cut short. Storage is decimal and memory
// binary (docs/shell-states.md). Kernel, processor, filesystem and swap size
// wait behind Details.
Rectangle {
    id: root

    // View state, not a setting: Details stays as it was left while the
    // shell runs.
    property bool detailsOpen: false
    property string releaseVersion: ""

    width: parent ? parent.width : 0
    height: implicitHeight
    implicitHeight: heroContent.implicitHeight + Theme.scaled(24)
    radius: Theme.rowRadius + 2
    color: Theme.chip
    border.width: 1
    border.color: Theme.hairlineSoft

    readonly property int logoSize: Theme.scaled(32)
    readonly property bool cybexosIdentity:
        SysInfo.osId.toLowerCase() === "nixos" && SysInfo.osName !== ""
    readonly property string osRelease:
        [SysInfo.osName, SysInfo.osVersion].filter(Boolean).join(" ")
    readonly property string identityLine: cybexosIdentity
        ? [root.releaseVersion !== "" ? "Cybex OS " + root.releaseVersion : "Cybex OS",
            root.osRelease].filter(Boolean).join(" · ")
        : root.osRelease !== "" ? root.osRelease
        : I18n.tr("System information unavailable")
    readonly property string fullModel:
        DrawerFormat.fullModel(SysInfo.deviceVendor, SysInfo.deviceModel)
    readonly property string machineModel:
        DrawerFormat.compactModel(SysInfo.deviceVendor, SysInfo.deviceModel)
    readonly property string machineLine: [
        root.machineModel || I18n.tr("Device model unavailable"),
        SysInfo.uptimeKnown
            ? I18n.format("up %1", [DrawerFormat.shortUptime(SysInfo.uptimeSecs)]) : ""
    ].filter(Boolean).join(" · ")

    readonly property string cpuReading: SysInfo.cpuUsageKnown
        ? Math.round(SysInfo.cpuUsage) + "%" : I18n.tr("Unavailable")
    readonly property string memoryReading: {
        if (!SysInfo.memKnown)
            return I18n.tr("Memory unavailable");
        const used = DrawerFormat.pair(SysInfoHelpers.formatIecBytes(SysInfo.memUsedBytes),
            SysInfoHelpers.formatIecBytes(SysInfo.memTotalBytes));
        if (!SysInfo.swapKnown)
            return used;
        if (SysInfo.swapTotalBytes === 0)
            return used + " · " + I18n.tr("no swap");
        return used + " · " + I18n.format("swap %1",
            [SysInfoHelpers.formatIecBytes(SysInfo.swapUsedBytes)]);
    }
    readonly property string diskReading: SysInfo.rootFsKnown
        ? DrawerFormat.pair(SysInfoHelpers.formatStorageBytes(SysInfo.rootFsUsedBytes),
            SysInfoHelpers.formatStorageBytes(SysInfo.rootFsTotalBytes))
            + " · " + I18n.format("%1 free",
                [SysInfoHelpers.formatStorageBytes(SysInfo.rootFsAvailableBytes)])
        : I18n.tr("Storage unavailable")
    readonly property string swapDetail: !SysInfo.swapKnown ? ""
        : SysInfo.swapTotalBytes === 0 ? I18n.tr("No swap")
        : I18n.format("%1 used of %2", [SysInfoHelpers.formatIecBytes(SysInfo.swapUsedBytes),
            SysInfoHelpers.formatIecBytes(SysInfo.swapTotalBytes)])

    // What Details lists; a fact the system did not report is left out.
    readonly property var details: [
        { label: I18n.tr("Model"), value: root.fullModel !== root.machineModel ? root.fullModel : "" },
        { label: I18n.tr("Processor"), value: SysInfo.cpuModel },
        { label: I18n.tr("Kernel"), value: SysInfo.kernelRelease },
        { label: I18n.tr("Filesystem"), value: SysInfo.rootFsType },
        { label: I18n.tr("Swap"), value: root.swapDetail }
    ].filter(row => row.value !== "")

    // The installed release, read the way Settings Home reads it.
    FileView {
        path: "/etc/cybexos/release.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                root.releaseVersion = String(JSON.parse(text()).version || "");
            } catch (error) {
                root.releaseVersion = "";
            }
        }
        onLoadFailed: root.releaseVersion = ""
    }

    component MetricRow: Rectangle {
        id: metric

        required property string label
        required property bool known
        required property real percent
        required property string reading
        property string status: ""
        property color statusColor: Theme.textMid
        property color meterColor: Theme.accent
        property int severity: 0
        property string accessibleDescription: ""
        required property string accessibleName

        // The reading moves under its label only when both no longer fit
        // on one line (a large text size, a narrow drawer).
        readonly property bool stacked: metricLabel.implicitWidth + Theme.controlSpacing
            + metricReadingRow.implicitWidth > metricContent.width

        width: parent ? parent.width : 0
        height: implicitHeight
        implicitHeight: metricContent.implicitHeight + Theme.scaled(10)
        radius: Theme.rowRadius
        color: severity >= 2 ? Theme.redBgSoft
            : severity === 1 ? Theme.amberBgSoft : "transparent"

        Accessible.role: Accessible.StaticText
        Accessible.name: metric.accessibleName
        Accessible.description: metric.accessibleDescription

        Column {
            id: metricContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.scaled(4)
            anchors.rightMargin: Theme.scaled(4)
            anchors.topMargin: Theme.scaled(5)
            spacing: Theme.scaled(5)

            Item {
                width: parent.width
                height: metric.stacked
                    ? metricLabel.implicitHeight + Theme.scaled(2) + metricReadingRow.height
                    : Math.max(metricLabel.implicitHeight, metricReadingRow.height)

                Text {
                    id: metricLabel
                    y: metric.stacked ? 0
                        : (parent.height - implicitHeight) / 2
                    text: metric.label
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightSemibold
                    font.letterSpacing: 0.7
                    color: Theme.textMid
                    Accessible.ignored: true
                }

                Row {
                    id: metricReadingRow

                    x: metric.stacked ? 0 : parent.width - width
                    y: metric.stacked ? metricLabel.implicitHeight + Theme.scaled(2)
                        : (parent.height - height) / 2
                    spacing: Theme.scaled(5)

                    Text {
                        id: metricReading

                        width: Math.min(implicitWidth, metricContent.width)
                        text: metric.reading
                        wrapMode: Text.Wrap
                        font.family: Theme.fontNumeric
                        font.pixelSize: Theme.typography.secondary
                        font.weight: Theme.weightMedium
                        font.features: Theme.tabularNumberFeatures
                        color: metric.known ? Theme.textHi : Theme.textMid
                        Accessible.ignored: true
                    }

                    Text {
                        visible: metric.status !== ""
                        text: "· " + metric.status
                        font.family: Theme.fontNumeric
                        font.pixelSize: Theme.typography.secondary
                        font.weight: Theme.weightMedium
                        font.features: Theme.tabularNumberFeatures
                        color: metric.statusColor
                        Accessible.ignored: true
                    }
                }
            }

            BlockMeter {
                width: parent.width
                height: Theme.scaled(6)
                value: metric.known ? metric.percent / 100 : 0
                fillColor: metric.meterColor
                trackColor: Theme.hairline
                dimmed: !metric.known
                Accessible.ignored: true
            }
        }
    }

    Column {
        id: heroContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.scaled(12)
        spacing: Theme.scaled(8)

        Item {
            width: parent.width
            height: Math.max(root.logoSize, identity.implicitHeight)

            Item {
                id: mark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.logoSize
                height: root.logoSize

                BrandIcon {
                    anchors.fill: parent
                    name: "cybexos"
                    visible: root.cybexosIdentity
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !root.cybexosIdentity
                    radius: Theme.rowRadius
                    color: Theme.chipHover

                    Sym {
                        anchors.centerIn: parent
                        name: "computer"
                        size: Theme.iconLarge
                        color: Theme.accentText
                    }
                }
            }

            Column {
                id: identity
                anchors.left: mark.right
                anchors.leftMargin: Theme.scaled(10)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.scaled(2)

                Text {
                    width: parent.width
                    text: root.identityLine
                    wrapMode: Text.Wrap
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    font.weight: Theme.weightSemibold
                    color: Theme.textHi
                }

                Text {
                    width: parent.width
                    text: root.machineLine
                    wrapMode: Text.Wrap
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textMid
                }
            }
        }

        Column {
            width: parent.width
            spacing: 0

            MetricRow {
                label: I18n.tr("CPU")
                known: SysInfo.cpuUsageKnown
                percent: SysInfo.cpuUsage
                reading: root.cpuReading
                // Temperature joins the reading only when a sensor reports it.
                status: SysInfo.cpuTempKnown ? SysInfo.cpuTemp + " °C" : ""
                statusColor: SysInfo.cpuTemp >= 80 ? Theme.redText
                    : SysInfo.cpuTemp >= 65 ? Theme.amber : Theme.textHi
                severity: !SysInfo.cpuTempKnown ? 0
                    : SysInfo.cpuTemp >= 80 ? 2
                    : SysInfo.cpuTemp >= 65 ? 1 : 0
                accessibleName: "CPU, " + (SysInfo.cpuUsageKnown
                    ? Math.round(SysInfo.cpuUsage) + " percent utilization"
                    : "utilization unavailable") + ", "
                    + (SysInfo.cpuModel !== "" ? SysInfo.cpuModel
                        : "processor model unavailable") + ", "
                    + (SysInfo.cpuTempKnown
                        ? SysInfo.cpuTemp + " degrees Celsius"
                        : "temperature unavailable")
            }

            MetricRow {
                label: I18n.tr("MEMORY")
                known: SysInfo.memKnown
                percent: SysInfo.memUsage
                reading: root.memoryReading
                meterColor: !SysInfo.memKnown ? Theme.accent
                    : SysInfo.memUsage >= 95 ? Theme.red
                    : SysInfo.memUsage >= 85 ? Theme.amber : Theme.accent
                severity: !SysInfo.memKnown ? 0
                    : SysInfo.memUsage >= 95 ? 2
                    : SysInfo.memUsage >= 85 ? 1 : 0
                accessibleName: "Memory, " + (SysInfo.memKnown
                    ? Math.round(SysInfo.memUsage) + " percent, "
                        + SysInfoHelpers.formatIecBytes(SysInfo.memUsedBytes)
                            + " used of "
                        + SysInfoHelpers.formatIecBytes(SysInfo.memTotalBytes)
                    : "unavailable") + ", "
                    + (!SysInfo.swapKnown ? "swap unavailable"
                        : SysInfo.swapTotalBytes === 0 ? "no swap"
                        : SysInfoHelpers.formatIecBytes(SysInfo.swapUsedBytes)
                            + " swap used of "
                            + SysInfoHelpers.formatIecBytes(SysInfo.swapTotalBytes))
            }

            MetricRow {
                label: I18n.tr("DISK /")
                known: SysInfo.rootFsKnown
                percent: SysInfo.rootFsUsage
                reading: root.diskReading
                meterColor: !SysInfo.rootFsKnown ? Theme.accent
                    : SysInfo.rootFsUsage >= 90 ? Theme.red
                    : SysInfo.rootFsUsage >= 80 ? Theme.amber : Theme.accent
                severity: !SysInfo.rootFsKnown ? 0
                    : SysInfo.rootFsUsage >= 90 ? 2
                    : SysInfo.rootFsUsage >= 80 ? 1 : 0
                accessibleName: "Disk slash, " + (SysInfo.rootFsKnown
                    ? Math.round(SysInfo.rootFsUsage) + " percent, "
                        + SysInfoHelpers.formatStorageBytes(SysInfo.rootFsUsedBytes)
                            + " used of "
                        + SysInfoHelpers.formatStorageBytes(SysInfo.rootFsTotalBytes) + ", "
                        + SysInfoHelpers.formatStorageBytes(SysInfo.rootFsAvailableBytes)
                            + " available, filesystem " + SysInfo.rootFsType
                    : "unavailable" + (SysInfo.rootFsError !== ""
                        ? ", " + SysInfo.rootFsError : ""))
                accessibleDescription: SysInfo.rootFsError
            }
        }

        // ---- details -----------------------------------------------------
        Rectangle {
            id: detailsToggle
            visible: root.details.length > 0
            x: -Theme.scaled(6)
            width: detailsRow.implicitWidth + Theme.scaled(12)
            height: Math.max(Theme.scaled(24), detailsRow.implicitHeight + Theme.scaled(6))
            radius: Theme.chipRadius
            color: "transparent"
            border.width: Theme.focusWidth(activeFocus)
            border.color: Theme.focusRing
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: root.detailsOpen ? I18n.tr("Hide details") : I18n.tr("Show details")
            Accessible.onPressAction: root.detailsOpen = !root.detailsOpen

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.detailsOpen = !root.detailsOpen;
                    event.accepted = true;
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                hovered: detailsMouse.containsMouse
                pressed: detailsMouse.pressed
                pressPoint: Qt.point(detailsMouse.mouseX, detailsMouse.mouseY)
            }

            Row {
                id: detailsRow
                anchors.centerIn: parent
                spacing: Theme.scaled(4)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Details")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightMedium
                    color: Theme.accentText
                }

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.detailsOpen ? "expand_less" : "expand_more"
                    size: Theme.iconSmall
                    color: Theme.accentText
                }
            }

            MouseArea {
                id: detailsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    detailsToggle.forceActiveFocus();
                    root.detailsOpen = !root.detailsOpen;
                }
            }
        }

        // A label lane as wide as the longest label, then values that wrap.
        Column {
            id: detailList
            visible: root.detailsOpen && root.details.length > 0
            width: parent.width
            spacing: Theme.scaled(3)

            // Reading the font ties the lane to the text size as well.
            readonly property real lane: detailMetrics.font.pixelSize > 0
                ? Math.ceil(root.details.reduce((widest, row) =>
                    Math.max(widest, detailMetrics.advanceWidth(row.label)), 0))
                : 0

            FontMetrics {
                id: detailMetrics
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
            }

            Repeater {
                model: root.details

                delegate: Item {
                    id: detailRow

                    required property var modelData

                    width: detailList.width
                    height: Math.max(detailLabel.implicitHeight, detailValue.implicitHeight)
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData.label + ", " + modelData.value

                    Text {
                        id: detailLabel
                        width: detailList.lane
                        text: detailRow.modelData.label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        color: Theme.textMid
                        Accessible.ignored: true
                    }

                    Text {
                        id: detailValue
                        x: detailList.lane + Theme.controlSpacing
                        width: Math.max(0, parent.width - x)
                        text: detailRow.modelData.value
                        wrapMode: Text.Wrap
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        color: Theme.textHi
                        Accessible.ignored: true
                    }
                }
            }
        }
    }
}
