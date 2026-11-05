pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../Common"
import ".."

// The drawer's pinned session row (2026-11 UI review): outside the scrolling
// body, the same on every tab. Lock and Suspend act at once. Log out,
// Restart and Shut down, and Overview's "Restart…" for a staged update, turn
// the row into one question first, so a stray click never ends the session.
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
    readonly property real zoneHeight: Math.max(Theme.scaled(52),
        (confirming ? confirmRow.implicitHeight : Theme.inlineActionHeight)
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

        Row {
            id: sessionActions
            visible: !root.confirming
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(2)

            DrawerIconButton {
                glyph: "lock"
                accessibleName: I18n.tr("Lock")
                onClicked: { Popouts.close(); Session.lock(); }
            }

            DrawerIconButton {
                glyph: "sleep"
                accessibleName: I18n.tr("Suspend")
                onClicked: { Popouts.close(); Session.suspend(); }
            }

            DrawerIconButton {
                id: logoutButton
                glyph: "logout"
                accessibleName: I18n.tr("Log out")
                onClicked: root.ask("logout", logoutButton)
            }

            DrawerIconButton {
                id: rebootButton
                glyph: "restart_alt"
                accessibleName: I18n.tr("Restart")
                onClicked: root.ask("reboot", rebootButton)
            }

            DrawerIconButton {
                id: shutdownButton
                glyph: "power_settings_new"
                accessibleName: I18n.tr("Shut down")
                onClicked: root.ask("shutdown", shutdownButton)
            }
        }

        Row {
            visible: !root.confirming
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(2)

            DrawerIconButton {
                glyph: "photo_camera"
                accessibleName: I18n.tr("Screenshot")
                onClicked: {
                    Popouts.close();
                    Quickshell.execDetached(["sh", "-c", "screenshot region"]);
                }
            }

            DrawerIconButton {
                glyph: "keyboard"
                accessibleName: I18n.tr("Keyboard shortcuts")
                onClicked: Session.toggleKeys()
            }

            DrawerIconButton {
                glyph: "settings"
                accessibleName: I18n.tr("Settings")
                onClicked: {
                    const screen = Popouts.hostScreenName;
                    Settings.showPanel(undefined, screen);
                }
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
