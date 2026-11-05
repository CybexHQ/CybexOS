import QtQuick
import "../Common"

// A settings button in one of three tiers (2026-11, docs/shell-states.md).
// Tertiary by default: copy and an icon on a hover layer. `secondary` gives
// it the chip and a hairline, for an action that matters but is not the next
// step. `primary` fills it with the accent for the one action a group, bar or
// dialog leads with (Apply, Keep changes, Add account); a group has at most
// one. `danger` inks a tertiary action red.
Rectangle {
    id: root

    property string text: ""
    property string glyph: ""
    property bool compact: false
    property bool danger: false
    property bool primary: false
    property bool secondary: false
    // An icon-only action names itself in a tip; a labeled one needs none.
    property string tooltip: compact ? text : ""
    signal triggered()

    readonly property color ink: primary ? Theme.textOnAccent
        : danger ? Theme.redText : Theme.textMid
    readonly property bool filled: primary || secondary
    readonly property bool ringShown: Theme.focusWidth(activeFocus) > 0
    // Every tier answers to at least a 32 px target, the quiet ones included,
    // without growing the 28 px chip the rows are laid out around.
    readonly property real hitInsetX: Math.min(0, (width - Theme.inlineActionHeight) / 2)
    readonly property real hitInsetY: Math.min(0, (height - Theme.inlineActionHeight) / 2)

    width: compact ? Theme.chipHeight : actionRow.implicitWidth + (filled ? 24 : 16)
    height: Theme.chipHeight
    radius: Theme.chipRadius
    color: primary ? Theme.accent : secondary ? Theme.chip : "transparent"
    // The keyboard ring replaces the secondary hairline while it shows. On the
    // accent fill an accent ring would vanish, so a primary takes textHi.
    border.width: ringShown ? Theme.focusRingWidth : secondary ? 1 : 0
    border.color: ringShown ? (primary ? Theme.textHi : Theme.focusRing) : Theme.hairline
    opacity: enabled ? 1 : 0.4
    activeFocusOnTab: enabled && visible
    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: {
        if (!root.enabled)
            return;
        actionState.pulseCenter();
        root.triggered();
    }

    SettingsTooltip {
        visible: root.tooltip !== "" && (mouse.containsMouse || root.ringShown)
        text: root.tooltip
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            if (!root.enabled)
                return;
            actionState.pulseCenter();
            root.triggered(); event.accepted = true;
        }
    }

    StateLayer {
        id: actionState
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        focused: root.activeFocus
        tint: root.primary ? Theme.textOnAccent : root.danger ? Theme.red : Theme.textHi
        pressPoint: Qt.point(mouse.mouseX + root.hitInsetX, mouse.mouseY + root.hitInsetY)
    }

    Row {
        id: actionRow
        anchors.centerIn: parent
        spacing: Theme.iconTextSpacing

        // One icon system. Undo, close and back used to be typographic arrows
        // drawn in the menu face, which only worked while that face happened
        // to carry them: JetBrains Mono has no ↺, so every reset control in
        // the workspace fell back to whatever glyph the fontconfig chain
        // offered. Tabler icons is a set the shell installs and checks.
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph !== ""
            name: root.glyph
            size: Theme.iconSmall
            symWeight: 450
            color: root.ink
        }
        Text {
            visible: !root.compact
            text: root.text
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            font.weight: root.primary ? Theme.weightSemibold : Theme.weightMedium
            color: root.ink
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.leftMargin: root.hitInsetX
        anchors.rightMargin: root.hitInsetX
        anchors.topMargin: root.hitInsetY
        anchors.bottomMargin: root.hitInsetY
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.triggered();
        }
    }
}
