import QtQuick

// The one switch, at the three scales Theme carries (`switchPopover`,
// `switchRow`, `switchCompact`). `metrics.box` is the hit area, `metrics.track`
// the pill drawn centred inside it; the knob follows from the track height.
//
// Popover chrome and settings rows drew this twice with drifted geometry, and
// only the settings copy was keyboard-reachable. That was a real gap rather
// than a theoretical one: a popout takes WlrKeyboardFocus.OnDemand while it is
// open (Bar/BarPopoutWindow.qml), so the Wi-Fi, Bluetooth, Tailscale and DND
// switches sat inside a focused surface with nothing to focus them with.
//
// States (2026-11, docs/shell-states.md): off is a quiet track with a 1 px
// boundary and knob in the per-pack switchOff* tokens, which carry the 3:1
// edge a faint track alone missed; on is the accent track. Keyboard focus is
// a separate ring around the track, never a tint on it, so focus cannot be
// misread as a state. A disabled switch fades itself; whatever explains why
// sits outside it and stays at full contrast.
Item {
    id: root

    property var metrics: Theme.switchPopover
    property bool checked: false
    property string accessibleName: "Toggle"
    signal toggled(bool value)

    readonly property int trackWidth: metrics.track.width
    readonly property int trackHeight: metrics.track.height

    width: metrics.box.width
    height: metrics.box.height
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked
    Accessible.name: accessibleName
    Accessible.onToggleAction: {
        toggleState.pulseCenter();
        root.toggled(!root.checked);
    }

    // Escape and Tab deliberately fall through: the popout's FocusScope owns
    // Escape (Bar/IslandPopout.qml) and Tab is the reason this type exists.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            toggleState.pulseCenter();
            root.toggled(!root.checked); event.accepted = true;
        }
    }

    // The ring stands 1 px clear of the track and stays inside the hit box,
    // where no clipping parent can cut it.
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width, root.trackWidth + (Theme.focusRingWidth + 1) * 2)
        height: Math.min(root.height, root.trackHeight + (Theme.focusRingWidth + 1) * 2)
        radius: height / 2
        color: "transparent"
        visible: border.width > 0
        border.width: Theme.focusWidth(root.activeFocus)
        border.color: Theme.focusRing
    }

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: root.trackWidth
        height: root.trackHeight
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.switchOffTrack
        border.width: root.checked ? 0 : 1
        border.color: Theme.switchOffBorder

        StateLayer {
            id: toggleState
            anchors.fill: parent
            radius: parent.radius
            hovered: toggleMouse.containsMouse
            pressed: toggleMouse.pressed
            tint: root.checked ? Theme.accentFg : Theme.textHi
            pressPoint: Qt.point(toggleMouse.mouseX - track.x,
                toggleMouse.mouseY - track.y)
        }
    }

    Rectangle {
        id: thumb

        readonly property real restingSize: root.checked
            ? root.trackHeight - 4 : root.trackHeight - 8
        readonly property real pressedSize: root.trackHeight - 1

        x: (root.width - root.trackWidth) / 2
            + (root.checked ? root.trackWidth - root.trackHeight / 2
                : root.trackHeight / 2) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: toggleMouse.pressed ? pressedSize : restingSize
        height: width
        radius: height / 2
        color: root.checked ? Theme.accentFg : Theme.switchOffKnob

        Behavior on x {
            NumberAnimation {
                duration: Theme.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Behavior on width {
            NumberAnimation {
                duration: Theme.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }

    MouseArea {
        id: toggleMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.toggled(!root.checked);
        }
    }
}
