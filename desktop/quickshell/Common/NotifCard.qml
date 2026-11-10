pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Notifications
import "NotifHelpers.js" as Helpers

// The notification card anatomy (2026-11), drawn by both the toast overlay
// and the drawer's Notifications tab: source icon (monogram fallback) · a
// meta line with the app and its time · the title on its own line, two lines
// at most · the body, which gives up a line once the card carries buttons ·
// up to two action buttons, the rest under More (NotifActions). Toasts show
// × in place of the time while hovered; the drawer keeps 24 px expand and
// dismiss targets beside it. A nested centre row (showApp false) folds its
// title into the meta line, under a header that already names the app.
//
// Surface chrome stays with the caller. This is a Rectangle, so `color`,
// `border` and `radius` are set at the call site the ordinary way, and extra
// children — the toast's countdown bar, the centre's nested separator —
// parent into it like any other child.
//
// Callers share Theme.typography.notification for message copy. The style
// object carries presentation differences (targets, timestamps, line limits).
Rectangle {
    id: card

    required property var entry
    required property var style
    property real nowMs: 0
    property int padH: 12
    property int padV: 12
    // The centre hides the icon exactly when it hides the app name (a nested
    // row under a source header already says which app it came from); the
    // toast hides it on the Notifications settings page's own switch.
    property bool showIcon: true
    property bool showApp: true
    property int groupCount: 1
    property bool groupUrgent: false
    property int iconExtent: 28
    property int iconSize: 28
    property bool framedIcon: false
    // The icon well's fill: a step above whatever the card itself is.
    property color iconWell: Theme.chip
    // Toasts can trade their compact resting height for the complete text
    // while the pointer is holding their expiry timer. History rows instead
    // opt into an explicit disclosure so merely moving through them never
    // reflows the panel.
    property bool expandTextOnHover: false
    property bool allowTextExpansion: false
    property bool textExpandedByUser: false
    // Notification history participates in keyboard traversal; toast windows
    // deliberately do not request keyboard focus.
    property bool keyboardEnabled: false

    signal activated
    signal closeRequested

    readonly property bool urgent: groupUrgent
        || entry.urgency === NotificationUrgency.Critical
    readonly property bool hovered: cardHover.hovered
    readonly property bool holdsFocus: activeFocus || closeButton.activeFocus
        || textDisclosure.activeFocus || notificationActions.hasFocusedAction
    readonly property bool textExpanded: textExpandedByUser
        || (expandTextOnHover && hovered)
    readonly property bool textTruncated: header.truncated
        || (summary.visible && summary.truncated)
        || (bodyText.visible && bodyText.truncated)
    readonly property bool showTextDisclosure: allowTextExpansion
        && (textExpandedByUser || textTruncated)
    readonly property bool actionable: groupCount > 1 || Notifs.canActivate(entry)
    readonly property int bodyLines: Helpers.bodyLineLimit(card.style.bodyLines,
        notificationActions.hasButtons)
    // Real, not int: a card's height is text metrics plus padding and lands
    // on fractions, and truncating it costs a pixel that then shifts every
    // card below this one.
    readonly property real contentHeight: cardContent.implicitHeight + card.padV * 2

    height: contentHeight
    activeFocusOnTab: keyboardEnabled
    Accessible.role: actionable ? Accessible.Button : Accessible.StaticText
    Accessible.name: (entry.displayAppName || "Notification")
        + (entry.displaySummary ? ": " + entry.displaySummary : "")
    Accessible.description: (entry.displayBody || "")
        + ((entry.occurrences || 1) > 1
            ? " · " + I18n.format("Repeated %1 times", [entry.occurrences]) : "")
    Accessible.onPressAction: {
        if (card.actionable)
            card.activated();
    }

    Keys.onPressed: event => {
        if (card.actionable && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space)) {
            card.activated();
            event.accepted = true;
        } else if (card.keyboardEnabled && event.key === Qt.Key_Delete) {
            card.closeRequested();
            event.accepted = true;
        } else if (card.keyboardEnabled
                && (event.key === Qt.Key_Right || event.key === Qt.Key_Down)) {
            card.moveFocus(card, true);
            event.accepted = true;
        } else if (card.keyboardEnabled
                && (event.key === Qt.Key_Left || event.key === Qt.Key_Up)) {
            card.moveFocus(card, false);
            event.accepted = true;
        }
    }

    function toggleTextExpansion() {
        textExpandedByUser = !textExpandedByUser;
    }

    function moveFocus(item, forward) {
        const next = item.nextItemInFocusChain(forward);
        if (next)
            next.forceActiveFocus();
    }

    onEntryChanged: textExpandedByUser = false

    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        enabled: card.actionable
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (card.keyboardEnabled)
                card.forceActiveFocus();
            card.activated();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: Theme.focusWidth(card.activeFocus)
        border.color: Theme.focusRing
    }

    TextMetrics {
        id: stampReserve
        // The widest relative time this card shows, so the meta line keeps
        // its width as "now" becomes "12m".
        font.family: card.style.stampFace
        font.pixelSize: card.style.stampSize
        font.weight: Theme.weightMedium
        text: "88m"
    }

    Row {
        id: cardContent
        x: card.padH
        y: card.padV
        width: parent.width - card.padH * 2
        spacing: card.showIcon ? Theme.scaled(10) : 0

        NotifIcon {
            visible: card.showIcon
            width: card.iconExtent
            height: card.iconExtent
            iconSize: card.iconSize
            framed: card.framedIcon
            wellColor: card.iconWell
            entry: card.entry
            urgent: card.urgent
        }

        Column {
            width: cardContent.width
                - (card.showIcon ? card.iconExtent + cardContent.spacing : 0)
            spacing: Theme.scaled(2)

            // Line 1: the source and its time. Its trailing controls keep
            // one target height so the title below never moves on hover.
            Item {
                width: parent.width
                height: Math.max(header.implicitHeight, trailing.height)

                Text {
                    id: header
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - trailing.width - Theme.controlSpacing
                    text: card.showApp ? card.entry.displayAppName
                        : (card.entry.displaySummary || card.entry.displayAppName)
                    font.family: card.style.face
                    font.pixelSize: card.showApp
                        ? Theme.typography.metadata : card.style.header
                    font.weight: card.showApp
                        ? Theme.weightMedium : Theme.weightSemibold
                    color: card.showApp ? Theme.textLow : Theme.textHi
                    wrapMode: card.textExpanded ? Text.Wrap : Text.NoWrap
                    elide: card.textExpanded ? Text.ElideNone : Text.ElideRight
                }

                // [count] [time | ×] [expand] for toasts and nested rows,
                // [count] [expand] [time] [×] for the drawer, whose × is
                // always there. An expand slot is reserved whenever the
                // card allows one: letting `textTruncated` add its width
                // creates a binding loop at runtime.
                Item {
                    id: trailing

                    readonly property real target: card.style.target
                    readonly property real gap: Theme.scaled(2)
                    readonly property bool closeBeside: card.style.closeAlways
                    readonly property real countWidth: card.groupCount > 1
                        ? countPill.width + gap : 0
                    readonly property real stampWidth: Math.ceil(Math.max(
                        stampReserve.advanceWidth, stamp.implicitWidth))
                    readonly property real stampSlot: closeBeside
                        ? stampWidth : Math.max(stampWidth, target)
                    readonly property real expandWidth: card.allowTextExpansion
                        ? target + gap : 0
                    readonly property real expandX: closeBeside
                        ? countWidth : countWidth + stampSlot + gap
                    readonly property real stampRight: closeBeside
                        ? countWidth + expandWidth + stampSlot
                        : countWidth + stampSlot
                    // × and the disclosure keep their drawn size, but each
                    // answers to at least a 32 px target (negative margins:
                    // the hit area reaches past the drawing). Where the two
                    // sit side by side, 2 px apart, they meet halfway.
                    readonly property real hitInset: Math.min(0,
                        (target - Theme.inlineActionHeight) / 2)
                    readonly property bool adjacent: !closeBeside && card.allowTextExpansion

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: countWidth + expandWidth + stampSlot
                        + (closeBeside ? gap + target : 0)
                    height: target

                    // Collapsed-group count. The toast never groups, so this
                    // never renders there.
                    Rectangle {
                        id: countPill
                        visible: card.groupCount > 1
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: countText.implicitWidth + 12
                        height: Theme.chipInnerHeight
                        radius: Theme.chipRadius
                        color: "transparent"

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: card.groupCount
                            font.family: card.style.face
                            font.pixelSize: card.style.pill
                            font.weight: Theme.weightMedium
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.textMid
                        }
                    }

                    // A toast's time and × share one spot, so the card never
                    // reflows when the pointer enters.
                    Text {
                        id: stamp
                        x: trailing.stampRight - width
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: trailing.closeBeside
                            || !(card.hovered || closeButton.activeFocus) ? 1 : 0
                        text: Notifs.timeAgo(card.entry.arrived, card.nowMs)
                        font.family: card.style.stampFace
                        font.pixelSize: card.style.stampSize
                        font.weight: Theme.weightMedium
                        font.features: Theme.tabularNumberFeatures
                        color: Theme.textLow

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.chipFadeDuration / 2
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        id: textDisclosure

                        visible: card.showTextDisclosure
                        x: trailing.expandX
                        anchors.verticalCenter: parent.verticalCenter
                        width: trailing.target
                        height: width
                        radius: Theme.chipRadius
                        color: disclosureMouse.containsMouse || activeFocus
                            ? Theme.hoverFillStrong : "transparent"
                        activeFocusOnTab: visible && card.keyboardEnabled
                        border.width: Theme.focusWidth(activeFocus)
                        border.color: Theme.focusRing

                        Accessible.role: Accessible.Button
                        Accessible.name: card.textExpandedByUser
                            ? "Collapse notification text"
                            : "Show full notification"
                        Accessible.onPressAction: card.toggleTextExpansion()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                card.toggleTextExpansion();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                                card.moveFocus(textDisclosure, true);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                                card.moveFocus(textDisclosure, false);
                                event.accepted = true;
                            }
                        }

                        Sym {
                            anchors.centerIn: parent
                            name: card.textExpandedByUser
                                ? "expand_less" : "expand_more"
                            size: card.style.close
                            color: disclosureMouse.containsMouse
                                || textDisclosure.activeFocus
                                ? Theme.textHi : Theme.textDim
                        }

                        MouseArea {
                            id: disclosureMouse
                            anchors.fill: parent
                            anchors.leftMargin: trailing.adjacent ? -trailing.gap / 2 : trailing.hitInset
                            anchors.rightMargin: trailing.hitInset
                            anchors.topMargin: trailing.hitInset
                            anchors.bottomMargin: trailing.hitInset
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                textDisclosure.forceActiveFocus();
                                card.toggleTextExpansion();
                            }
                        }
                    }

                    Rectangle {
                        id: closeButton

                        readonly property bool shown: trailing.closeBeside
                            || card.hovered || activeFocus

                        x: trailing.closeBeside ? trailing.width - width
                            : trailing.stampRight - width
                        anchors.verticalCenter: parent.verticalCenter
                        width: trailing.target
                        height: width
                        radius: Theme.chipRadius
                        opacity: shown ? 1 : 0
                        color: closeMouse.containsMouse || activeFocus
                            ? Theme.hoverFillStrong : "transparent"
                        activeFocusOnTab: card.keyboardEnabled
                        border.width: Theme.focusWidth(activeFocus)
                        border.color: Theme.focusRing
                        Accessible.role: Accessible.Button
                        Accessible.name: card.entry.displayAppName
                            ? I18n.format("Dismiss notification from %1", [card.entry.displayAppName])
                            : I18n.tr("Dismiss notification from this app")
                        Accessible.onPressAction: card.closeRequested()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space
                                    || event.key === Qt.Key_Delete) {
                                card.closeRequested();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                                card.moveFocus(closeButton, true);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                                card.moveFocus(closeButton, false);
                                event.accepted = true;
                            }
                        }

                        Sym {
                            anchors.centerIn: parent
                            name: "close"
                            size: card.style.close
                            color: closeMouse.containsMouse
                                ? Theme.textHi : card.style.closeColor
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            anchors.leftMargin: trailing.hitInset
                            anchors.rightMargin: trailing.adjacent ? -trailing.gap / 2 : trailing.hitInset
                            anchors.topMargin: trailing.hitInset
                            anchors.bottomMargin: trailing.hitInset
                            enabled: closeButton.shown
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (card.keyboardEnabled)
                                    closeButton.forceActiveFocus();
                                card.closeRequested();
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.chipFadeDuration / 2
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                }
            }

            // Line 2: the title on its own line.
            Text {
                id: summary
                textFormat: Text.PlainText
                visible: card.showApp && card.entry.displaySummary !== ""
                width: parent.width
                text: card.entry.displaySummary === "Verification notification"
                    ? I18n.tr("Verification notification") : card.entry.displaySummary || ""
                font.family: card.style.face
                font.pixelSize: card.style.header
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                wrapMode: Text.Wrap
                maximumLineCount: card.textExpanded
                    ? 2147483647 : Helpers.TITLE_LINES
                elide: card.textExpanded ? Text.ElideNone : Text.ElideRight
            }

            Text {
                id: bodyText
                textFormat: Text.PlainText
                visible: text !== "" && card.bodyLines > 0
                width: parent.width
                text: card.entry.displayBody === "Content redacted"
                    ? I18n.tr("Content redacted") : card.entry.displayBody || ""
                font.family: card.style.face
                font.pixelSize: card.style.body
                color: card.urgent ? Theme.textHi : card.style.bodyColor
                wrapMode: Text.Wrap
                maximumLineCount: card.textExpanded
                    ? 2147483647 : Math.max(1, card.bodyLines)
                elide: card.textExpanded ? Text.ElideNone : Text.ElideRight
                lineHeight: card.style.bodyLeading
            }

            Text {
                visible: (card.entry.occurrences || 1) > 1
                text: I18n.format("Repeated %1 times", [card.entry.occurrences || 1])
                font.family: card.style.face
                font.pixelSize: card.style.pill
                color: Theme.textDim
            }

            NotifActions {
                id: notificationActions
                width: parent.width
                topPadding: Theme.scaled(6)
                entry: card.entry
                available: card.groupCount === 1
                reveal: card.groupCount === 1 && (card.hovered || card.activeFocus
                    || closeButton.activeFocus || textDisclosure.activeFocus
                    || notificationActions.hasFocusedAction)
                keyboardEnabled: card.keyboardEnabled
                face: card.style.face
                pixelSize: card.style.pill
            }
        }
    }

    Behavior on color {
        ColorAnimation { duration: Theme.chipFadeDuration }
    }
}
