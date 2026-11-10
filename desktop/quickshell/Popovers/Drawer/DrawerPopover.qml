pragma ComponentBehavior: Bound
import QtQuick
import "../../Common"
import "../../Common/PanelRegistryData.js" as PanelRegistry
import ".."

// The edge drawer: the one surface every status glyph opens, per the 2026-09
// redesign (Claude Design project 8cf85161, direction 2). A tab strip —
// Overview · Sound · Network · Bluetooth · Power · Notifications — sits above the
// tab body; the popout host attaches the surface flush under the bar and pins
// it to the right screen edge (PanelRegistryData `attached` + `edge`).
//
// Each established popout name (control, audio, wifi, battery, notifications,
// usage, …) presents one tab of this same component, so IPC names, the bar's
// held states and hover-crossing all keep working unchanged. The host keys
// its slots by source, so every one of those names reuses this same instance
// and a tab switch swaps content in place instead of cross-fading a clone.
//
// Only the body scrolls. The tabs stay above it and the session row
// (DrawerSessionFooter) stays pinned below it on every tab, so Lock and
// Restart are one click away however long a tab is. Tab order follows the
// layout: tabs, then the body, then the session row.
Surface {
    id: root

    property string tab: "overview"

    padding: Theme.panelPadding
    spacing: Theme.scaled(14)
    implicitWidth: Theme.drawerWidth

    readonly property real bodyHeightLimit: availableHeight > 0
        ? Math.max(1, availableHeight - padding * 2
            - drawerTabs.height - spacing
            - (drawerArrival.visible ? drawerArrival.height + spacing : 0)
            - sessionFooter.height - spacing)
        : Math.max(1, bodyLoader.implicitHeight)
    // The same envelope for content that adapts to it (Overview's process
    // rows); 0 while the host gives none, so nothing reads its own height.
    readonly property real bodyHeightBudget: availableHeight > 0 ? bodyHeightLimit : 0
    // Values, links and switches stay 12 px clear of the scroll thumb's lane
    // (ScrollChrome: 2 px margin, 3 px thumb) while the body scrolls. Only a
    // body that already overflows narrows, and narrowing only makes it taller,
    // so the gutter cannot toggle itself back off.
    readonly property real scrollGutter: bodyFlick.interactive ? Theme.scaled(12) + 5 : 0

    onTabChanged: {
        bodyFlick.cancelFlick();
        bodyFlick.contentY = 0;
    }

    function bodyContains(item) {
        let cursor = item;
        while (cursor) {
            if (cursor === bodyFlick.contentItem)
                return true;
            cursor = cursor.parent;
        }
        return false;
    }

    // Escape answers a pending session question, or closes the session row's
    // open menu, first; only then does it close the drawer
    // (PopoutPanel.handleEscape).
    function handleEscape(): bool {
        if (sessionFooter.confirming) {
            sessionFooter.cancel();
            return true;
        }
        if (sessionFooter.menuOpen) {
            sessionFooter.dismissMenu();
            return true;
        }
        return false;
    }

    function revealFocus(item) {
        if (!item || !bodyFlick.interactive || !bodyContains(item))
            return;
        Qt.callLater(() => {
            if (!item || !item.visible || !root.bodyContains(item))
                return;
            const point = item.mapToItem(bodyFlick.contentItem, 0, 0);
            // Clear of the body's 24 px edge fades, not under them.
            const margin = bodyChrome.fadeSize + Theme.scaled(4);
            const itemHeight = Math.max(item.height, item.implicitHeight || 0);
            let next = bodyFlick.contentY;
            if (point.y < bodyFlick.contentY + margin)
                next = point.y - margin;
            else if (point.y + itemHeight
                    > bodyFlick.contentY + bodyFlick.height - margin)
                next = point.y + itemHeight - bodyFlick.height + margin;
            bodyFlick.contentY = Math.max(0, Math.min(next,
                bodyFlick.contentHeight - bodyFlick.height));
        });
    }

    Component.onCompleted: {
        const name = Popouts.currentName;
        tab = PanelRegistry.drawerTab(name) || "overview";
    }

    // Follow the presenting name while it is a drawer name. When another
    // surface takes over (drawerTab resolves to ""), this instance is the
    // outgoing half of a cross-fade and must keep showing what it showed.
    Connections {
        target: Popouts

        function onChanged() {
            if (!Popouts.open)
                return;
            const tab = PanelRegistry.drawerTab(Popouts.currentName);
            if (tab === "")
                return;
            root.tab = tab;
        }
    }

    DrawerTabs {
        id: drawerTabs
        width: parent.width
        current: root.tab
    }

    // New notifications that arrive while the drawer covers their corner
    // land here instead of as a toast over the drawer.
    DrawerArrival {
        id: drawerArrival
        width: parent.width
        currentTab: root.tab
        onOpenNotifications: root.tab = "notifications"
    }

    Item {
        id: bodyViewport

        width: parent.width
        height: implicitHeight
        implicitHeight: Math.min(bodyLoader.implicitHeight,
            root.bodyHeightLimit)
        clip: true

        Flickable {
            id: bodyFlick

            anchors.fill: parent
            contentWidth: width
            contentHeight: bodyLoader.implicitHeight
            interactive: contentHeight > height + 1
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            flickDeceleration: 3000
            clip: true

            Loader {
                id: bodyLoader

                width: Math.max(0, bodyFlick.width - root.scrollGutter)
                sourceComponent: root.tab === "sound" ? soundTab
                    : root.tab === "network" ? networkTab
                    : root.tab === "bluetooth" ? bluetoothTab
                    : root.tab === "power" ? powerTab
                    : root.tab === "notifications" ? notificationsTab
                    : overviewTab
            }
        }

        // A 24 px fade at whichever edge still has content past it.
        ScrollChrome {
            id: bodyChrome
            anchors.fill: parent
            target: bodyFlick
            edgeColor: root.surfaceColor
        }
    }

    DrawerSessionFooter {
        id: sessionFooter
        width: parent.width
        bottomInset: root.padding
    }

    Connections {
        target: root.Window.window
        enabled: target !== null
        function onActiveFocusItemChanged() {
            const item = root.Window.window
                ? root.Window.window.activeFocusItem : null;
            if (item)
                root.revealFocus(item);
        }
    }

    Component {
        id: overviewTab
        DrawerOverview {
            bodyHeightBudget: root.bodyHeightBudget
            onSessionConfirmRequested: (action, origin, version) =>
                sessionFooter.ask(action, origin, version)
        }
    }

    Component {
        id: soundTab
        DrawerSound {}
    }

    Component {
        id: networkTab
        DrawerNetwork {}
    }

    Component {
        id: bluetoothTab
        DrawerBluetooth {}
    }

    Component {
        id: powerTab
        DrawerPower {}
    }

    Component {
        id: notificationsTab
        DrawerNotifications {}
    }
}
