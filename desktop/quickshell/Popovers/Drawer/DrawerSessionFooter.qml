pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../Common"
import ".."

// The drawer's pinned session row (2026-11 UI review): outside the scrolling
// body, the same on every tab. Three labelled buttons (2026-11 UI council:
// eight bare icons asked people to recognise them): Lock, which acts at
// once; Power, a menu of Sleep, Restart…, Shut down… and Log out…; and More,
// a menu of Settings, Keyboard shortcuts and Screenshot. Sleep acts at once.
// Log out, Restart and Shut down, and Overview's "Restart…" for a staged
// update, turn the row into one question first, so a stray click never ends
// the session.
//
// The question behaves like a small dialog: focus lands on Cancel, Return
// answers with the default (the red button), Space presses whichever button
// has focus, and Escape cancels without closing the drawer
// (DrawerPopover.handleEscape). Closing the drawer drops the question, so a
// later visit never finds one armed.
Item {
    id: root

    // "", "logout", "reboot", "shutdown", "update-reboot" or "update-shutdown".
    property string pending: ""
    // The Cybex OS release a staged update installs, for its question.
    property string updateVersion: ""
    // The control that asked; focus goes back to it when the person cancels.
    property Item returnFocus: null
    // The surface's own bottom padding, counted as part of this row so the
    // 52 px it occupies reaches the drawer's edge.
    property real bottomInset: 0

    readonly property bool confirming: pending !== ""
    readonly property bool menuOpen: powerMenu.opened || moreMenu.opened
    readonly property real zoneHeight: Math.max(Theme.scaled(52),
        (confirming ? confirmRow.implicitHeight : lockButton.height)
            + Theme.scaled(20))
    readonly property string question: pending === "logout"
        ? I18n.tr("Log out? Unsaved work may be lost.")
        : pending === "reboot" ? I18n.tr("Restart now?")
        : pending === "shutdown" ? I18n.tr("Shut down now?")
        : pending === "update-shutdown" ? I18n.tr("Shut down to finish the update?")
        : pending === "update-reboot" ? (updateVersion !== ""
            ? I18n.format("Restart to install Cybex OS %1?", [updateVersion])
            : I18n.tr("Restart to finish the update?"))
        : ""
    readonly property string answer: pending === "logout" ? I18n.tr("Log out")
        : pending === "shutdown" || pending === "update-shutdown" ? I18n.tr("Shut down")
        : I18n.tr("Restart")

    width: parent ? parent.width : 0
    height: Math.max(1, zoneHeight - bottomInset)
    implicitHeight: height
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("Session")

    function ask(action, origin, version) {
        pending = action;
        updateVersion = version || "";
        returnFocus = origin || null;
        Qt.callLater(() => {
            if (root.confirming)
                cancelButton.forceActiveFocus();
        });
    }

    function cancel() {
        const origin = returnFocus;
        pending = "";
        returnFocus = null;
        if (origin && origin.visible)
            origin.forceActiveFocus();
    }

    // The same session actions the row always ran, and the ones Software
    // Update's own "Restart Now" / "Shut Down Now" run for a staged update.
    function confirm() {
        const action = pending;
        pending = "";
        returnFocus = null;
        if (action === "")
            return;
        Popouts.close();
        if (action === "logout")
            Session.logout();
        else if (action === "shutdown" || action === "update-shutdown")
            Session.shutdown();
        else
            Session.reboot();
    }

    function reset() {
        pending = "";
        returnFocus = null;
        closeMenus();
    }

    function closeMenus() {
        powerMenu.close();
        moreMenu.close();
    }

    // Escape with a menu open closes the menu, not the drawer
    // (DrawerPopover.handleEscape).
    function dismissMenu() {
        const opener = powerMenu.opened ? powerButton : moreButton;
        closeMenus();
        opener.forceActiveFocus();
    }

    function run(action) {
        if (action === "sleep") {
            Popouts.close();
            Session.suspend();
        } else if (action === "reboot" || action === "shutdown" || action === "logout") {
            ask(action, powerButton);
        } else if (action === "settings") {
            Settings.showPanel(undefined, Popouts.hostScreenName);
        } else if (action === "shortcuts") {
            Session.toggleKeys();
        } else if (action === "screenshot") {
            Popouts.close();
            Quickshell.execDetached(["sh", "-c", "screenshot region"]);
        }
    }

    // A secondary-tier button (docs/shell-states.md: chip and hairline,
    // 32 px high): a glyph, its label, and a chevron when it opens a menu.
    component SessionButton: Rectangle {
        id: button

        property string glyph: ""
        property string label: ""
        property DrawerMenu menu: null
        property string accessibleName: label
        property string accessibleDescription: ""
        readonly property bool menuOpen: menu !== null && menu.opened
        signal clicked()

        width: buttonRow.implicitWidth + Theme.scaled(10) * 2
        height: Math.max(Theme.inlineActionHeight, buttonLabel.implicitHeight + Theme.scaled(10))
        radius: Theme.chipRadius
        color: menuOpen ? Theme.chipHover : Theme.chip
        border.width: Theme.focusWidth(activeFocus) || 1
        border.color: Theme.focusWidth(activeFocus) > 0 ? Theme.focusRing : Theme.hairline
        activeFocusOnTab: visible && enabled
        Accessible.role: menu !== null ? Accessible.ButtonMenu : Accessible.Button
        Accessible.name: accessibleName
        Accessible.description: accessibleDescription
        Accessible.onPressAction: button.clicked()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space
                    || (button.menu !== null && !button.menuOpen
                        && (event.key === Qt.Key_Up || event.key === Qt.Key_Down))) {
                button.clicked();
                event.accepted = true;
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            hovered: buttonMouse.containsMouse
            pressed: buttonMouse.pressed
            tint: Theme.textHi
            pressPoint: Qt.point(buttonMouse.mouseX, buttonMouse.mouseY)
        }

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: Theme.iconTextSpacing

            Sym {
                visible: button.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: button.glyph
                size: Theme.iconMedium
                color: buttonMouse.containsMouse ? Theme.textHi : Theme.textMid
            }

            Text {
                id: buttonLabel
                anchors.verticalCenter: parent.verticalCenter
                text: button.label
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.control
                font.weight: Theme.weightMedium
                color: Theme.textHi
                Accessible.ignored: true
            }

            // The menu opens upward, over the body.
            Sym {
                visible: button.menu !== null
                anchors.verticalCenter: parent.verticalCenter
                name: button.menuOpen ? "expand_more" : "expand_less"
                size: Theme.iconSmall
                color: Theme.textMid
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                button.forceActiveFocus();
                button.clicked();
            }
        }
    }

    DrawerMenu {
        id: powerMenu
        opener: powerButton
        accessibleName: I18n.tr("Power")
        entries: [
            { id: "sleep", glyph: "sleep", label: I18n.tr("Sleep") },
            { id: "reboot", glyph: "restart_alt", label: I18n.tr("Restart…") },
            { id: "shutdown", glyph: "power_settings_new", label: I18n.tr("Shut down…") },
            { id: "logout", glyph: "logout", label: I18n.tr("Log out…") }
        ]
        onChosen: id => root.run(id)
    }

    DrawerMenu {
        id: moreMenu
        opener: moreButton
        alignEnd: true
        accessibleName: I18n.tr("More")
        entries: [
            { id: "settings", glyph: "settings", label: I18n.tr("Settings") },
            { id: "shortcuts", glyph: "keyboard", label: I18n.tr("Keyboard shortcuts") },
            { id: "screenshot", glyph: "photo_camera", label: I18n.tr("Screenshot") }
        ]
        onChosen: id => root.run(id)
    }

    onVisibleChanged: {
        if (!visible)
            reset();
    }

    Connections {
        target: Popouts
        function onOpenChanged() {
            if (!Popouts.open)
                root.reset();
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.hairlineSoft
    }

    Item {
        id: zone
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.zoneHeight

        // Lock acts at once. Power holds the four ways to end or pause the
        // session, More the rest of the old icon row; every control names
        // itself on screen (2026-11 UI council).
        Row {
            id: sessionActions
            visible: !root.confirming
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.controlSpacing

            SessionButton {
                id: lockButton
                glyph: "lock"
                label: I18n.tr("Lock")
                onClicked: { Popouts.close(); Session.lock(); }
            }

            SessionButton {
                id: powerButton
                glyph: "power_settings_new"
                label: I18n.tr("Power")
                menu: powerMenu
                accessibleDescription: I18n.tr("Sleep, restart, shut down or log out")
                onClicked: powerMenu.toggle()
            }
        }

        Row {
            visible: !root.confirming
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.controlSpacing

            SessionButton {
                id: moreButton
                label: I18n.tr("More")
                menu: moreMenu
                accessibleDescription: I18n.tr("Settings, keyboard shortcuts and screenshot")
                onClicked: moreMenu.toggle()
            }
        }

        Item {
            id: confirmRow
            visible: root.confirming
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: implicitHeight
            implicitHeight: Math.max(questionText.implicitHeight, Theme.inlineActionHeight)

            Text {
                id: questionText
                anchors.left: parent.left
                anchors.leftMargin: Theme.scaled(4)
                anchors.right: confirmButtons.left
                anchors.rightMargin: Theme.controlSpacing
                anchors.verticalCenter: parent.verticalCenter
                text: root.question
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                font.weight: Theme.weightMedium
                color: Theme.textHi
                Accessible.role: Accessible.AlertMessage
                Accessible.name: text
            }

            Row {
                id: confirmButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.controlSpacing

                // Secondary: chip and hairline. Return here answers with the
                // default, as a dialog's default button does; Space presses
                // Cancel itself (ActionButton).
                ActionButton {
                    id: cancelButton
                    objectName: "drawerSessionCancel"
                    label: I18n.tr("Cancel")
                    tint: Theme.textHi
                    fill: Theme.chip
                    hPadding: Theme.scaled(24)
                    border.width: Theme.focusWidth(activeFocus) || 1
                    border.color: Theme.focusWidth(activeFocus) > 0
                        ? Theme.focusRing : Theme.hairline
                    Accessible.description: I18n.format("Return: %1. Escape: cancel.", [root.answer])
                    Keys.onReturnPressed: root.confirm()
                    Keys.onEnterPressed: root.confirm()
                    onTriggered: root.cancel()
                }

                // The destructive default: the red text tone as a fill, with
                // the copy surface as its ink. redText clears 4.5:1 against
                // that surface by construction, so the label does too.
                ActionButton {
                    objectName: "drawerSessionConfirm"
                    label: root.answer
                    tint: Theme.copyReferenceBg
                    fill: Theme.redText
                    focusColor: Theme.copyReferenceBg
                    hPadding: Theme.scaled(24)
                    onTriggered: root.confirm()
                }
            }
        }
    }
}
