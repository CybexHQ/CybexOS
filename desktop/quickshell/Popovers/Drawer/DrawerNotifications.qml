pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../Common"
import "../../Assistant"

// The drawer's Notifications tab: the recent hour's cards, an EARLIER block
// for the rest, newest first, and the Focus switch — the same Focus as the
// Overview's tile. Cards reuse the shared NotifCard anatomy the toasts draw,
// app on each card's meta line, with 24 px expand and dismiss targets. An
// arrival while the tab is showing lands at the top, briefly lit; one that
// came while another tab was showing was counted on the tab instead
// (DrawerArrival, NotifPolicy.drawerRoute). Dismissing a card from the
// keyboard hands focus to its neighbour.
Column {
    id: root

    property double nowMs: Date.now()
    readonly property var entries: Notifs.entries
    // Entries are newest first, so the recent hour is a prefix. The clock
    // tick only moves this int; the lists below re-slice when it actually
    // changes, not every 30 s, and the ScriptModels keep each surviving
    // card (its expansion and focus) across a re-slice.
    readonly property int recentCount: {
        const index = entries.findIndex(entry =>
            root.nowMs - entry.arrived >= 3600 * 1000);
        return index === -1 ? entries.length : index;
    }
    readonly property var recent: entries.slice(0, recentCount)
    readonly property var earlier: entries.slice(recentCount)
    // Cards for entries that arrive after this moment are new to the person
    // looking at the list.
    readonly property double shownAt: Date.now()

    readonly property var cardStyle: ({
        face: Theme.fontMenu,
        header: Theme.typography.notification,
        body: Theme.typography.notification,
        bodyColor: Theme.textMid,
        bodyLines: 3,
        bodyLeading: 1.25,
        stampFace: Theme.fontNumeric,
        stampSize: Theme.fontCaption,
        target: Theme.scaled(24),
        closeAlways: true,
        close: Theme.iconMedium,
        closeColor: Theme.textMid,
        pill: Theme.fontCaption
    })

    // The card at `index` in the list as it now stands — the one after a
    // dismissed card, or the last — else the Focus switch.
    function focusCardAt(index) {
        const total = recentCards.count + earlierCards.count;
        const at = Math.min(index, total - 1);
        const card = at < 0 ? null : at < recentCards.count
            ? recentCards.itemAt(at) : earlierCards.itemAt(at - recentCards.count);
        if (card)
            card.forceActiveFocus();
        else
            focusSwitch.forceActiveFocus();
    }

    function dismiss(card) {
        const refocus = card.holdsFocus;
        const index = root.entries.findIndex(entry => entry.key === card.entry.key);
        Notifs.dismiss(card.entry);
        if (refocus)
            Qt.callLater(() => root.focusCardAt(index));
    }

    width: parent ? parent.width : 0
    spacing: Theme.scaled(14)

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    // ---- header ----------------------------------------------------------
    Item {
        width: parent.width
        height: Math.max(Theme.scaled(28), focusRow.implicitHeight)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.recent.length > 0
                    ? I18n.format("%1 new", [root.recent.length])
                    : Notifs.count === 0 ? I18n.tr("All clear") : I18n.tr("Quiet hour")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.title
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.earlier.length > 0
                text: I18n.format("%1 earlier", [root.earlier.length])
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
            }
        }

        // Focus, labelled, as a switch: the Overview's tile and the bar's
        // indicators read the same Notifs.dnd.
        Row {
            id: focusRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.controlSpacing + 2

            // The label toggles too, as a settings row's does.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: focusLabels.implicitWidth
                height: focusLabels.implicitHeight

                Column {
                    id: focusLabels

                    Text {
                        anchors.right: parent.right
                        text: I18n.tr("Focus")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.control
                        font.weight: Theme.weightSemibold
                        color: Theme.textHi
                    }

                    Text {
                        anchors.right: parent.right
                        text: I18n.tr("Silences notifications")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        color: Theme.textMid
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.setDnd(!Notifs.dnd)
                }
            }

            Toggle {
                id: focusSwitch
                anchors.verticalCenter: parent.verticalCenter
                metrics: Theme.switchCompact
                checked: Notifs.dnd
                accessibleName: I18n.tr("Focus: silences notifications")
                onToggled: value => Notifs.setDnd(value)
            }
        }
    }

    NotifSnoozes { width: parent.width }

    // ---- cards -----------------------------------------------------------
    Column {
        width: parent.width
        spacing: 4

        Repeater {
            id: recentCards

            model: ScriptModel {
                values: root.recent
            }

            delegate: NotifCard {
                id: recentCard

                required property var modelData
                // Lit for a moment when it arrives while the list is open.
                property bool fresh: modelData.arrived > root.shownAt

                entry: modelData
                style: root.cardStyle
                nowMs: root.nowMs
                allowTextExpansion: true
                keyboardEnabled: true
                showIcon: true
                framedIcon: true
                iconWell: Theme.chipHover
                iconExtent: Theme.scaled(32)
                iconSize: Theme.scaled(22, Theme.typeScale)
                width: parent.width
                radius: 10
                color: recentCard.urgent ? Theme.redBgSoft
                    : recentCard.fresh ? Theme.selectedFill
                    : recentCard.hovered ? Theme.chipHover : Theme.chip
                border.width: recentCard.fresh ? 1 : 0
                border.color: Theme.selectedMark
                onActivated: Notifs.activate(recentCard.entry)
                onCloseRequested: root.dismiss(recentCard)

                Timer {
                    running: recentCard.fresh
                    interval: 1600
                    onTriggered: recentCard.fresh = false
                }
            }
        }

        // Nothing kept at all: Wiz rests where the cards would be, asleep
        // while Focus holds notifications back. Idle he holds still between
        // a blink or a glance, so an open, empty centre draws next to nothing.
        Loader {
            active: Notifs.count === 0
            visible: active
            width: parent.width

            sourceComponent: Item {
                implicitHeight: emptyColumn.implicitHeight + Theme.scaled(20)

                Column {
                    id: emptyColumn
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Theme.scaled(4)

                    Wiz {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.scaled(64)
                        height: Theme.scaled(64)
                        pose: Notifs.dnd ? "asleep" : "idle"
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("Nothing new")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.primary
                        font.weight: Theme.weightSemibold
                        color: Theme.textMid
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("You're all caught up.")
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        color: Theme.textDim
                    }
                }
            }
        }

        // Only older notifications: nothing new this hour.
        Item {
            visible: root.recent.length === 0 && Notifs.count > 0
            width: parent.width
            height: 64

            Column {
                anchors.centerIn: parent
                spacing: 6

                Sym {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "notifications_off"
                    size: 20
                    color: Theme.textFaint
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Nothing new")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    color: Theme.textFaint
                }
            }
        }

        Item {
            visible: root.earlier.length > 0
            width: parent.width
            height: 26

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: I18n.tr("EARLIER")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.section
                font.weight: Theme.weightSemibold
                font.letterSpacing: 0.6
                color: Theme.textFaint
            }
        }

        Repeater {
            id: earlierCards

            model: ScriptModel {
                values: root.earlier
            }

            delegate: NotifCard {
                id: earlierCard

                required property var modelData

                entry: modelData
                style: root.cardStyle
                nowMs: root.nowMs
                allowTextExpansion: true
                keyboardEnabled: true
                framedIcon: true
                iconExtent: Theme.scaled(32)
                iconSize: Theme.scaled(22, Theme.typeScale)
                width: parent.width
                radius: 10
                opacity: 0.75
                padV: 8
                color: earlierCard.hovered ? Theme.chipHover : "transparent"
                onActivated: Notifs.activate(earlierCard.entry)
                onCloseRequested: root.dismiss(earlierCard)
            }
        }
    }

    // Nothing kept, nothing to say or clear: Wiz's empty state ends the tab.
    DrawerFooter {
        visible: Notifs.count > 0
        info: Notifs.count === 0 ? ""
            : Notifs.count === 1 ? I18n.tr("1 notification kept")
            : I18n.format("%1 notifications kept", [Notifs.count])
        actionText: Notifs.count > 0 ? I18n.tr("Clear all") : ""
        onActionClicked: Notifs.clearAll()
    }
}
