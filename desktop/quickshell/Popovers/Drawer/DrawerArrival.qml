pragma ComponentBehavior: Bound
import QtQuick
import "../../Common"
import "../../Common/PanelRegistryData.js" as PanelRegistry

// What the open drawer shows of a notification it took instead of a toast
// (the 2026-11 collision rule, NotifPolicy.drawerRoute), directly under the
// tabs:
//
// - a one-line strip for five seconds — source mark · "App · Title — body" ·
//   Show — that opens the Notifications tab when clicked. It never takes
//   focus: it is gone before a keyboard could reach it, and the tab's
//   persistent count (DrawerTabs) is what lasts;
// - a banner for a critical arrival, pinned until it is opened, acted on or
//   dismissed (Notifs.pinned). It persists, so its two buttons are focusable.
//
// Neither shows while the Notifications tab is current: the list itself
// takes the arrival at its top.
Item {
    id: root

    property string currentTab: ""
    signal openNotifications()

    readonly property bool listShown: currentTab === "notifications"
    readonly property var banner: !listShown && Notifs.pinned.length > 0 ? Notifs.pinned[0] : null
    readonly property var arrival: !listShown && Notifs.arrival
        && (!banner || Notifs.arrival.key !== banner.key) ? Notifs.arrival : null

    // Opens the tab the way the strip's own tabs do: by the panel name that
    // presents it, which keeps the drawer on its side of the screen and tells
    // Notifs the tab is being read.
    function open() {
        const name = PanelRegistry.nameForTab("notifications");
        if (name !== "")
            Popouts.openPanel(name, Popouts.island);
        root.openNotifications();
    }

    implicitHeight: column.implicitHeight
    // From the revealers' own state, not their `visible`: a hidden parent
    // reports its children hidden too, which would latch this off for good.
    visible: bannerReveal.reveal || stripReveal.reveal
        || bannerReveal.implicitHeight > 0.5 || stripReveal.implicitHeight > 0.5

    Column {
        id: column
        width: parent.width
        spacing: Theme.controlSpacing

        Revealer {
            id: bannerReveal
            width: parent.width
            orientation: Qt.Vertical
            reveal: root.banner !== null

            Rectangle {
                id: bannerCard

                // Held through the exit animation: the entry the banner was
                // showing, once it is handled.
                property var shown: null
                readonly property var entry: root.banner || shown || ({})

                width: bannerReveal.width
                height: bannerRow.implicitHeight + Theme.controlSpacing * 2
                radius: Theme.chipRadius + 3
                color: bannerMouse.containsMouse ? Qt.tint(Theme.redBgSoft, Theme.chip) : Theme.redBgSoft
                border.width: 1
                border.color: Theme.redBorder
                Accessible.role: Accessible.AlertMessage
                Accessible.name: I18n.format("Critical notification from %1: %2",
                    [entry.displayAppName || "", entry.displaySummary || ""])

                Connections {
                    target: root
                    function onBannerChanged() {
                        if (root.banner)
                            bannerCard.shown = root.banner;
                    }
                }
                Component.onCompleted: shown = root.banner

                MouseArea {
                    id: bannerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open()
                }

                Row {
                    id: bannerRow
                    x: Theme.controlSpacing + 2
                    y: Theme.controlSpacing
                    width: parent.width - x * 2
                    spacing: Theme.controlSpacing + 2

                    NotifIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.scaled(28)
                        height: Theme.scaled(28)
                        iconSize: Theme.scaled(20, Theme.typeScale)
                        monogramSize: Theme.typography.secondary
                        framed: true
                        urgent: true
                        entry: bannerCard.entry
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.scaled(28) - bannerShow.width
                            - bannerDismiss.width - parent.spacing * 3
                        spacing: Theme.scaled(1)

                        Text {
                            width: parent.width
                            text: (bannerCard.entry.displayAppName || "")
                                + (bannerCard.entry.displaySummary
                                    ? " · " + bannerCard.entry.displaySummary : "")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.primary
                            font.weight: Theme.weightSemibold
                            color: Theme.textHi
                        }

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: bannerCard.entry.displayBody || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            color: Theme.textHi
                        }
                    }

                    NotifButton {
                        id: bannerShow
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Show")
                        Accessible.description: I18n.tr("Open the Notifications tab")
                        onTriggered: root.open()
                    }

                    Rectangle {
                        id: bannerDismiss
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.scaled(24)
                        height: width
                        radius: Theme.chipRadius
                        color: dismissMouse.containsMouse || activeFocus
                            ? Theme.hoverFillStrong : "transparent"
                        activeFocusOnTab: bannerReveal.reveal
                        border.width: Theme.focusWidth(activeFocus)
                        border.color: Theme.focusRing
                        Accessible.role: Accessible.Button
                        Accessible.name: bannerCard.entry.displayAppName
                            ? I18n.format("Dismiss notification from %1", [bannerCard.entry.displayAppName])
                            : I18n.tr("Dismiss notification from this app")
                        Accessible.onPressAction: Notifs.dismiss(bannerCard.entry)
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space || event.key === Qt.Key_Delete) {
                                Notifs.dismiss(bannerCard.entry);
                                event.accepted = true;
                            }
                        }

                        Sym {
                            anchors.centerIn: parent
                            name: "close"
                            size: Theme.iconMedium
                            color: dismissMouse.containsMouse ? Theme.textHi : Theme.textMid
                        }

                        MouseArea {
                            id: dismissMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.dismiss(bannerCard.entry)
                        }
                    }
                }
            }
        }

        Revealer {
            id: stripReveal
            width: parent.width
            orientation: Qt.Vertical
            reveal: root.arrival !== null

            Rectangle {
                id: strip

                property var shown: null
                readonly property var entry: root.arrival || shown || ({})

                width: stripReveal.width
                height: Math.max(Theme.scaled(40), stripText.implicitHeight + Theme.controlSpacing * 2)
                radius: Theme.chipRadius + 3
                // A chip, not an accent field: Show carries the accent.
                color: stripMouse.containsMouse ? Theme.chipHover : Theme.chip
                border.width: 1
                border.color: Theme.hairlineSoft
                Accessible.role: Accessible.Button
                Accessible.name: I18n.format("New notification from %1: %2",
                    [entry.displayAppName || "", entry.displaySummary || ""])
                Accessible.description: I18n.tr("Open the Notifications tab")
                Accessible.onPressAction: root.open()

                Connections {
                    target: root
                    function onArrivalChanged() {
                        if (root.arrival)
                            strip.shown = root.arrival;
                    }
                }
                Component.onCompleted: shown = root.arrival

                MouseArea {
                    id: stripMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open()
                }

                NotifIcon {
                    id: stripIcon
                    x: Theme.controlSpacing + 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.scaled(22)
                    height: Theme.scaled(22)
                    iconSize: Theme.scaled(16, Theme.typeScale)
                    monogramSize: Theme.typography.metadata
                    wellColor: Theme.chipHover
                    framed: true
                    entry: strip.entry
                }

                // "App · Title — body" on one line; the app keeps its weight
                // and the rest gives way first.
                Row {
                    id: stripText
                    anchors.left: stripIcon.right
                    anchors.leftMargin: Theme.controlSpacing + 2
                    anchors.right: stripShow.left
                    anchors.rightMargin: Theme.controlSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        id: stripApp
                        width: Math.min(implicitWidth, stripText.width * 0.45)
                        text: strip.entry.displayAppName || ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }

                    Text {
                        width: Math.max(0, stripText.width - stripApp.width)
                        text: [strip.entry.displaySummary || "", strip.entry.displayBody || ""]
                            .filter(part => part !== "")
                            .map((part, index) => (index === 0 ? " · " : " — ") + part.replace(/\s+/g, " "))
                            .join("")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        color: Theme.textMid
                    }
                }

                Text {
                    id: stripShow
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.controlSpacing + 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Show")
                    textFormat: Text.PlainText
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightMedium
                    color: Theme.accentText
                }
            }
        }
    }
}
