pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../../Common"
import "../../Common/PanelRegistryData.js" as PanelRegistry
import "DrawerFormat.js" as DrawerFormat

// The drawer's tab strip. Every tab carries its icon and a short label
// (2026-11 UI council: a strip of bare icons asked people to recognise
// them), the label under the icon so six fit one row. Tabs take their
// natural width plus an equal share of the rest; when the labels do not fit
// whole — a narrow drawer, a larger text size or a longer translation — the
// strip wraps onto more rows instead of cutting a label short
// (DrawerFormat.tabLayout). The current tab wears the shared selected state
// (docs/shell-states.md: accent tint, an inset accent edge along its foot,
// accent icon, textHi label); hover stays the neutral chip.
//
// Selecting a tab reopens the popout under that tab's canonical panel name —
// same name space as the bar glyphs and IPC — which keeps the surface
// exactly where it is. The Notifications tab counts arrivals the drawer took
// instead of a toast until it is shown (Notifs.unread).
Rectangle {
    id: root

    property string current: "overview"

    // `label` is what the tab shows; `name` the full name, for the tooltip
    // and assistive technology when the two differ.
    readonly property var tabMeta: ({
        overview: { glyph: "dashboard", label: I18n.tr("Overview"), name: I18n.tr("Overview") },
        sound: { glyph: "volume_down", label: I18n.tr("Sound"), name: I18n.tr("Sound") },
        network: { glyph: "wifi", label: I18n.tr("Network"), name: I18n.tr("Network") },
        bluetooth: { glyph: "bluetooth", label: I18n.tr("Bluetooth"), name: I18n.tr("Bluetooth") },
        power: { glyph: "battery_5_bar", label: I18n.tr("Power"), name: I18n.tr("Power") },
        notifications: { glyph: "notifications", label: I18n.tr("Alerts"), name: I18n.tr("Notifications") }
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
            name: tabMeta[entry.id].name,
            rotate: tabMeta[entry.id].rotate === true
        }))

    readonly property int unreadCount: Notifs.unread.length
    readonly property real tabIconSize: Theme.iconMedium
    // The least room either side of a label; the layout shares out the rest.
    readonly property real tabPadding: Theme.scaled(4)
    readonly property real tabGap: 2
    readonly property real innerWidth: Math.max(0, width - 6)

    // Measured in the selected weight, so selecting a tab never reflows the
    // strip. Reading the font ties the widths to the text size as well.
    readonly property var labelWidths: labelMetrics.font.pixelSize > 0
        ? tabs.map(entry => Math.ceil(labelMetrics.advanceWidth(entry.label)))
        : tabs.map(() => 0)
    readonly property var layout: DrawerFormat.tabLayout(
        labelWidths.map(w => Math.max(tabIconSize, w) + tabPadding * 2),
        labelWidths.map(w => tabIconSize + Theme.iconTextSpacing + w + tabPadding * 2),
        innerWidth, tabGap)
    readonly property real labelHeight: Math.ceil(labelMetrics.height)
    readonly property real segmentHeight: layout.stacked
        ? Math.max(Theme.scaled(44), tabIconSize + Theme.scaled(2) + labelHeight + Theme.scaled(6) * 2)
        : Math.max(Theme.scaled(34), Math.max(tabIconSize, labelHeight) + Theme.controlSpacing * 2)

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

    FontMetrics {
        id: labelMetrics
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.navigation
        font.weight: Theme.weightSemibold
    }

    height: segmentHeight * layout.rows + tabGap * (layout.rows - 1) + 6
    radius: 10
    color: Theme.chip

    Grid {
        id: tabGrid
        x: 3
        y: 3
        width: root.innerWidth
        columns: Math.max(1, root.layout.columns)
        columnSpacing: root.tabGap
        rowSpacing: root.tabGap

        Repeater {
            id: tabRepeater
            model: root.tabs

            delegate: Rectangle {
                id: segment

                required property var modelData
                required property int index
                readonly property bool on: modelData.tab === root.current
                readonly property bool counted: modelData.tab === "notifications"
                    && root.unreadCount > 0
                readonly property bool renamed: modelData.name !== modelData.label

                width: root.layout.widths[index] || 0
                height: root.segmentHeight
                radius: 8
                color: on ? Theme.selectedFill : "transparent"
                border.width: Theme.focusWidth(activeFocus)
                border.color: Theme.focusRing
                activeFocusOnTab: on
                Accessible.selected: on
                Accessible.onPressAction: root.activateTab(index, true)
                // The label is on the tab; a tooltip adds only a fuller name.
                Controls.ToolTip.visible: renamed
                    && (segmentMouse.containsMouse || (activeFocus && FocusModality.keyboard))
                Controls.ToolTip.text: modelData.name
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

                Behavior on color {
                    ColorAnimation { duration: Theme.chipFadeDuration }
                }

                // Icon over label in one row; icon beside label once the
                // strip has wrapped onto rows of wider cells.
                Grid {
                    id: tabContent
                    anchors.centerIn: parent
                    columns: root.layout.stacked ? 1 : 2
                    columnSpacing: Theme.iconTextSpacing
                    rowSpacing: Theme.scaled(2)
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter

                    Item {
                        id: tabIcon
                        width: root.tabIconSize
                        height: root.tabIconSize

                        Sym {
                            anchors.centerIn: parent
                            name: segment.modelData.glyph
                            size: root.tabIconSize
                            rotation: segment.modelData.rotate === true ? 90 : 0
                            color: segment.on ? Theme.accentText : Theme.textMid
                        }
                    }

                    Text {
                        // Wider than the whole strip only at the narrowest
                        // single column; it wraps there rather than eliding.
                        width: Math.min(implicitWidth, Math.max(0, segment.width - root.tabPadding * 2
                            - (root.layout.stacked ? 0 : root.tabIconSize + Theme.iconTextSpacing)))
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: segment.modelData.label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.navigation
                        font.weight: segment.on ? Theme.weightSemibold : Theme.weightMedium
                        color: segment.on ? Theme.textHi : Theme.textMid
                        Accessible.ignored: true
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

                // Kept notifications on the resting Notifications tab, at the
                // icon's top end, where the bar's bell wears its dot — unless
                // the count below says more.
                Rectangle {
                    visible: segment.modelData.tab === "notifications"
                        && !segment.on && !segment.counted && Notifs.count > 0
                    x: tabContent.x + tabIcon.x + tabIcon.width - Theme.scaled(3)
                    y: tabContent.y + tabIcon.y - Theme.scaled(1)
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                }

                // The unread count: arrivals the open drawer took instead of
                // a toast. It sits over the icon's top end — at the cell's end
                // when the label is beside the icon — and is drawn last so
                // nothing in the segment covers it.
                Rectangle {
                    id: countBadge
                    visible: segment.counted
                    z: 2
                    x: root.layout.stacked
                        ? Math.min(segment.width - width,
                            tabContent.x + tabIcon.x + tabIcon.width - Theme.scaled(4))
                        : segment.width - width - Theme.scaled(2)
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
                Accessible.description: segment.renamed ? segment.modelData.name : ""
            }
        }
    }
}
