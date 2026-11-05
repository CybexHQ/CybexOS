pragma ComponentBehavior: Bound
import QtQuick
import "NotifHelpers.js" as Helpers

// A card's actions, per the 2026-11 anatomy (NotifHelpers.actionPlan): up to
// two buttons — the sender's own first, then the shell's verification-code,
// Ask Wiz and link shortcuts — and everything else (further sender actions,
// snoozes) under More. Only a staged update's next step takes the accent
// (Notifs.primaryAction); the rest are secondary, chip and hairline. A card
// with buttons shows them at rest; one with only More shows it while hovered
// or focused. Each row is a Revealer, which keeps its controls alive through
// their exit so the card closes around them instead of snapping shorter.
Column {
    id: root

    required property var entry
    property string face: Theme.fontMenu
    property int pixelSize: Theme.fontCaption
    property bool keyboardEnabled: false
    // The card is hovered or holds focus.
    property bool reveal: false
    // False for a collapsed group card: the actions belong to its members.
    property bool available: true

    property var items: []
    property var plan: Helpers.actionPlan([], null)
    property bool moreOpen: false
    property var focusedPills: []
    readonly property int focusedActions: focusedPills.length
    readonly property bool hasFocusedAction: focusedActions > 0
    readonly property bool hasButtons: available && plan.buttons.length > 0
    readonly property bool hasMore: available && plan.more.length > 0

    function sameActions(a, b) {
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++) {
            const x = a[i], y = b[i];
            if (x !== y && !(x.kind && x.kind === y.kind && x.text === y.text
                    && x.value === y.value && x.minutes === y.minutes))
                return false;
        }
        return true;
    }

    // Rebuilding the rows recreates every pill, dropping the focus one of
    // them holds, so an unchanged plan is left alone.
    function refreshItems() {
        items = Notifs.secondaryActions(entry);
        const next = Helpers.actionPlan(items, Notifs.primaryAction(entry));
        if (next.primary !== plan.primary || !sameActions(next.buttons, plan.buttons)
                || !sameActions(next.more, plan.more))
            plan = next;
    }

    function noteFocus(item, focused) {
        const next = focusedPills.filter(other => other !== item);
        if (focused)
            next.push(item);
        if (next.length !== focusedPills.length)
            focusedPills = next;
    }

    function moveFocus(item, forward) {
        const next = item.nextItemInFocusChain(forward);
        if (next)
            next.forceActiveFocus();
    }

    onRevealChanged: {
        refreshItems();
        if (!reveal)
            moreOpen = false;
    }
    Connections {
        target: Notifs
        function onSnoozesChanged() { root.refreshItems(); }
    }
    onEntryChanged: {
        moreOpen = false;
        refreshItems();
    }
    Component.onCompleted: refreshItems()

    spacing: Theme.iconTextSpacing
    // From the rows' own state, not their `visible`: a hidden parent reports
    // its children hidden too, which would latch this off for good.
    visible: buttonRow.reveal || moreRow.reveal
        || buttonRow.implicitHeight > 0.5 || moreRow.implicitHeight > 0.5

    Component {
        id: pillDelegate

        Rectangle {
            id: pill

            required property var modelData
            // Its row says whether it is showing and which pill leads. Taken
            // from the parent imperatively: a delegate being torn down loses
            // its parent after this file's ids are gone, and a binding on
            // `parent` would then re-run against them.
            property var row: null
            readonly property bool shown: row !== null && row.shown === true
            readonly property bool primary: row !== null && row.lead !== null
                && modelData === row.lead
            readonly property bool lit: pillMouse.containsMouse || activeFocus

            height: Math.max(Theme.chipHeight, root.pixelSize + Theme.iconTextSpacing * 2)
            width: Math.min(root.width, pillText.implicitWidth + Theme.controlSpacing * 2 + 2,
                Theme.scaled(180))
            radius: Theme.chipRadius
            color: primary ? (lit ? Theme.accentHover : Theme.accent)
                : (lit ? Theme.chipHover : Theme.chip)
            activeFocusOnTab: root.keyboardEnabled && root.reveal && pill.shown
            // Secondary keeps its hairline; the focus ring replaces it, and
            // on the accent fill the ring is ink so it still shows.
            border.width: Theme.focusWidth(activeFocus) || (primary ? 0 : 1)
            border.color: Theme.focusWidth(activeFocus) > 0
                ? (primary ? Theme.textHi : Theme.focusRing) : Theme.hairline
            Accessible.role: Accessible.Button
            Accessible.name: pillText.text
            Accessible.description: pill.modelData.kind === "link" ? pill.modelData.value
                : pill.modelData.kind === "copy-code" ? pill.modelData.value : ""
            Accessible.onPressAction: Notifs.invoke(root.entry, pill.modelData)

            onParentChanged: {
                if (parent)
                    row = parent;
            }
            Component.onCompleted: {
                if (parent)
                    row = parent;
            }
            onActiveFocusChanged: root.noteFocus(pill, activeFocus)
            // A focused pill can go with a rebuilt row; it must not leave the
            // card believing it still holds focus.
            Component.onDestruction: {
                if (root)
                    root.noteFocus(pill, false);
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    Notifs.invoke(root.entry, pill.modelData);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                    root.moveFocus(pill, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                    root.moveFocus(pill, false);
                    event.accepted = true;
                }
            }

            Text {
                id: pillText
                anchors.centerIn: parent
                width: parent.width - Theme.controlSpacing * 2
                text: Helpers.singleLine(pill.modelData.text)
                textFormat: Text.PlainText
                font.family: root.face
                font.pixelSize: root.pixelSize
                font.weight: pill.primary ? Theme.weightSemibold : Theme.weightMedium
                color: pill.primary ? Theme.accentFg : Theme.textHi
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.keyboardEnabled)
                        pill.forceActiveFocus();
                    Notifs.invoke(root.entry, pill.modelData);
                }
            }

            Behavior on color {
                ColorAnimation { duration: Theme.chipFadeDuration }
            }
        }
    }

    Revealer {
        id: buttonRow
        width: root.width
        orientation: Qt.Vertical
        reveal: root.hasButtons || (root.hasMore && root.reveal)

        Flow {
            width: root.width
            spacing: Theme.iconTextSpacing

            readonly property bool shown: buttonRow.reveal
            readonly property var lead: root.plan.primary >= 0
                ? root.plan.buttons[root.plan.primary] : null

            Repeater {
                model: root.available ? root.plan.buttons : []
                delegate: pillDelegate
            }

            // Tertiary: text and a chevron in the same hit box as a button.
            Rectangle {
                id: moreButton

                readonly property bool lit: moreMouse.containsMouse || activeFocus

                visible: root.hasMore
                height: Math.max(Theme.chipHeight, root.pixelSize + Theme.iconTextSpacing * 2)
                width: moreContent.implicitWidth + Theme.controlSpacing * 2
                radius: Theme.chipRadius
                color: lit ? Theme.chip : "transparent"
                activeFocusOnTab: root.keyboardEnabled && root.reveal && visible
                border.width: Theme.focusWidth(activeFocus)
                border.color: Theme.focusRing
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("More actions")
                Accessible.onPressAction: root.moreOpen = !root.moreOpen

                onActiveFocusChanged: root.noteFocus(moreButton, activeFocus)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        root.moreOpen = !root.moreOpen;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.moveFocus(moreButton, true);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        root.moveFocus(moreButton, false);
                        event.accepted = true;
                    }
                }

                Row {
                    id: moreContent
                    anchors.centerIn: parent
                    spacing: Theme.scaled(2)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("More")
                        textFormat: Text.PlainText
                        font.family: root.face
                        font.pixelSize: root.pixelSize
                        font.weight: Theme.weightMedium
                        color: moreButton.lit ? Theme.textHi : Theme.textMid
                    }

                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.moreOpen ? "expand_less" : "expand_more"
                        size: Theme.iconSmall
                        color: moreButton.lit ? Theme.textHi : Theme.textMid
                    }
                }

                MouseArea {
                    id: moreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.keyboardEnabled)
                            moreButton.forceActiveFocus();
                        root.moreOpen = !root.moreOpen;
                    }
                }
            }
        }
    }

    Revealer {
        id: moreRow
        width: root.width
        orientation: Qt.Vertical
        reveal: root.moreOpen && root.hasMore

        Flow {
            width: root.width
            spacing: Theme.iconTextSpacing

            readonly property bool shown: moreRow.reveal
            readonly property var lead: null

            Repeater {
                model: root.available ? root.plan.more : []
                delegate: pillDelegate
            }
        }
    }
}
