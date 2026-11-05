pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../../Common"
import "../../Common/PanelRegistryData.js" as PanelRegistry

// The drawer's tab strip. The current tab carries its icon and label on the
// shared selected state (docs/shell-states.md: accent tint, an inset accent
// edge along its foot, accent icon, textHi label) with the design's 12px side
// padding; the others compress to icons sharing the remaining width, so the
// strip holds one row at every drawer width, and hover stays the neutral
// chip. Selecting a tab reopens the popout under that tab's canonical panel
// name — same name space as the bar glyphs and IPC — which keeps the surface
// exactly where it is. The Notifications tab counts arrivals the drawer took
// instead of a toast until it is shown (Notifs.unread).
Rectangle {
    id: root

    property string current: "overview"

    readonly property var tabMeta: ({
        overview: { glyph: "dashboard", label: I18n.tr("Overview") },
        sound: { glyph: "volume_down", label: I18n.tr("Sound") },
        network: { glyph: "wifi", label: I18n.tr("Network") },
        bluetooth: { glyph: "bluetooth", label: I18n.tr("Bluetooth") },
        power: { glyph: "battery_5_bar", label: I18n.tr("Power") },
        notifications: { glyph: "notifications", label: I18n.tr("Notifications") }
    })

    // Order and visibility come from the Drawer settings page. A tab the user
    // switched off stays reachable through its bar glyph and IPC name; while
    // it is presented it joins the strip so the current tab is never unnamed.
    readonly property var tabs: Settings.drawerTabs
        .filter(entry => (entry.on || entry.id === current)
            && tabMeta[entry.id] !== undefined)
        .map(entry => ({
            tab: entry.id,
            glyph: tabMeta[entry.id].glyph,
            label: tabMeta[entry.id].label,
            rotate: tabMeta[entry.id].rotate === true
        }))

    readonly property int unreadCount: Notifs.unread.length
    readonly property real tabPadding: Theme.controlSpacing
    readonly property real tabIconSize: Theme.iconMedium
    readonly property real usableWidth: Math.max(0, tabRow.width - tabRow.spacing * (tabs.length - 1))
    readonly property real restingWidth: Math.min(Theme.scaled(28), usableWidth / Math.max(1, tabs.length))
    readonly property real selectedWidth: Math.min(tabPadding * 2 + tabIconSize
        + Theme.iconTextSpacing + Math.ceil(selectedMetrics.advanceWidth) + 1,
        Math.max(0, usableWidth - restingWidth * (tabs.length - 1)))

    function activateTab(index, focusTab) {
        if (index < 0 || index >= tabs.length)
            return;
        const tab = tabs[index].tab;
        // Focus moves before the tab does: activeFocusOnTab follows the
        // current tab, and Qt refuses to clear it on the segment that still
        // holds focus (see Settings/PillRow). Another tab of the same drawer
        // keeps the drawer on its side of the screen.
        if (focusTab) {
            const target = tabRepeater.itemAt(index);
            if (target) target.forceActiveFocus();
        }
        const name = PanelRegistry.nameForTab(tab);
        if (name !== "")
            Popouts.openPanel(name, Popouts.island);
        // Leaving a tab switched off in settings drops it from the strip and
        // rebuilds the segments, so look the new one up again once it has.
        if (focusTab) {
            Qt.callLater(() => {
                const item = tabRepeater.itemAt(root.tabs.findIndex(entry => entry.tab === tab));
                if (item && !item.activeFocus) item.forceActiveFocus();
            });
        }
    }

    TextMetrics {
        id: selectedMetrics
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.navigation
        font.weight: Theme.weightSemibold
        text: root.tabMeta[root.current] ? I18n.tr(root.tabMeta[root.current].label) : ""
    }

    height: Math.max(Theme.scaled(42), Theme.typography.navigation + Theme.controlSpacing * 2)
    radius: 10
    color: Theme.chip

    Row {
        id: tabRow
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2

        Repeater {
            id: tabRepeater
            model: root.tabs

            delegate: Rectangle {
                id: segment

                required property var modelData
                readonly property bool on: modelData.tab === root.current
                required property int index
                readonly property bool showLabel: on && width >= root.tabPadding * 2
                    + root.tabIconSize + Theme.iconTextSpacing + Theme.typography.navigation
                width: root.tabs.length === 1 ? root.usableWidth : on ? root.selectedWidth
                    : Math.max(0, (root.usableWidth - root.selectedWidth) / (root.tabs.length - 1))
                readonly property bool counted: modelData.tab === "notifications"
                    && root.unreadCount > 0

                height: parent.height
                radius: 8
                color: on ? Theme.selectedFill : "transparent"
                border.width: Theme.focusWidth(activeFocus)
                border.color: Theme.focusRing
                activeFocusOnTab: on
                Accessible.selected: on
                Accessible.onPressAction: root.activateTab(index, true)
                Controls.ToolTip.visible: segmentMouse.containsMouse || activeFocus
                Controls.ToolTip.text: I18n.tr(modelData.label)
                Keys.onPressed: event => {
                    let next = index;
                    if (event.key === Qt.Key_Left) next = Math.max(0, index - 1);
                    else if (event.key === Qt.Key_Right) next = Math.min(root.tabs.length - 1, index + 1);
                    else if (event.key === Qt.Key_Home) next = 0;
                    else if (event.key === Qt.Key_End) next = root.tabs.length - 1;
                    else if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter
                            && event.key !== Qt.Key_Space) return;
                    root.activateTab(next, true);
                    event.accepted = true;
                }

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.expandDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.springCurve
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.iconTextSpacing

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.tabIconSize
                        height: root.tabIconSize

                        Sym {
                            anchors.centerIn: parent
                            name: segment.modelData.glyph
                            size: root.tabIconSize
                            rotation: segment.modelData.rotate === true ? 90 : 0
                            color: segment.on ? Theme.accentText : Theme.textFaint
                        }
                    }

                    Text {
                        visible: segment.showLabel
                        width: Math.max(0, segment.width - root.tabPadding * 2 - root.tabIconSize - Theme.iconTextSpacing)
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr(segment.modelData.label)
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.navigation
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }
                }

                // The selected tab's inset accent edge along its foot, kept
                // inside the rounded corners.
                Rectangle {
                    visible: segment.on
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: segment.radius
                    anchors.rightMargin: segment.radius
                    height: Theme.selectedEdgeWidth
                    radius: height / 2
                    color: Theme.selectedMark
                }

                // Kept notifications on the resting Notifications tab, in the
                // same place the bar's bell wears its dot — unless the count
                // below says more.
                Rectangle {
                    visible: segment.modelData.tab === "notifications"
                        && !segment.on && !segment.counted && Notifs.count > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 8
                    anchors.topMargin: 7
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                }

                // The unread count: arrivals the open drawer took instead of
                // a toast. It sits over the icon's top end, outside the label,
                // and is drawn last so nothing in the segment covers it.
                Rectangle {
                    id: countBadge
                    visible: segment.counted
                    z: 2
                    x: segment.showLabel
                        ? segment.width - width - Theme.scaled(2)
                        : Math.min(segment.width - width,
                            segment.width / 2 + root.tabIconSize / 2 - Theme.scaled(4))
                    y: Theme.scaled(2)
                    height: Math.max(Theme.scaled(16), countLabel.implicitHeight + 2)
                    width: Math.max(height, countLabel.implicitWidth + Theme.scaled(8))
                    radius: height / 2
                    color: Theme.accent
                    border.width: 2
                    border.color: Theme.barSurface

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: root.unreadCount > 99 ? "99+" : String(root.unreadCount)
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        font.weight: Theme.weightBold
                        font.features: Theme.tabularNumberFeatures
                        color: Theme.accentFg
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    hovered: segmentMouse.containsMouse && !segment.on
                    pressed: segmentMouse.pressed
                    tint: Theme.textHi
                    pressPoint: Qt.point(segmentMouse.mouseX, segmentMouse.mouseY)
                }

                MouseArea {
                    id: segmentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.activateTab(segment.index, true);
                    }
                }

                Accessible.role: Accessible.PageTab
                Accessible.name: segment.counted
                    ? I18n.format("%1, %2 unread", [segment.modelData.label, root.unreadCount])
                    : segment.modelData.label
            }
        }
    }
}
