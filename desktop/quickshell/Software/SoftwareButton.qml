import QtQuick
import "../Common"

// Software's buttons: one accent-filled primary action per surface, quiet
// outlined ones, and "queued" for an app already in the install queue. Over
// brand artwork a view passes its own `foreground`, and for its main action
// a `solidFill` with `solidInk`: a solid button that contrasts with any
// brand colour, where the accent could be blue on blue.
Rectangle {
    id: root

    property string text: ""
    property string glyph: ""
    property bool primary: false
    property bool quiet: false
    property bool queued: false
    property bool big: false
    property bool busy: false
    property color foreground: "transparent"
    property color solidFill: "transparent"
    property color solidInk: "transparent"
    property string accessibleName: text
    signal triggered()

    readonly property bool custom: foreground.a > 0
    readonly property bool solid: solidFill.a > 0
    readonly property color ink: solid ? solidInk : primary ? Theme.textOnAccent
        : custom ? foreground : queued ? Theme.accentText : Theme.textHi
    // The pointer target reaches 32 px even where the button is drawn smaller.
    readonly property real hitPad: Math.max(0, (Theme.scaled(32) - height) / 2)

    implicitWidth: content.implicitWidth + Theme.scaled(big ? 36 : 24)
    implicitHeight: Theme.scaled(big ? 38 : 30)
    radius: Theme.chipRadius + (big ? 2 : 0)
    color: solid ? solidFill : primary ? Theme.accent
        : custom ? Qt.rgba(foreground.r, foreground.g, foreground.b, quiet ? 0 : 0.14)
        : queued ? Theme.accentAlpha(0.16)
        : quiet ? "transparent" : Theme.hoverFill
    border.width: activeFocus ? 2 : (queued || quiet) ? 1 : 0
    border.color: activeFocus ? (solid ? solidInk : primary ? Theme.textHi : Theme.accentText)
        : custom ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35)
        : queued ? Theme.accentAlpha(0.5) : Theme.stroke
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: enabled && visible
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.onPressAction: {
        if (root.enabled)
            root.triggered();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (root.enabled)
                root.triggered();
            event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse && root.enabled
        pressed: mouse.pressed
        focused: false
        tint: root.ink
        pressPoint: Qt.point(mouse.mouseX, mouse.mouseY - root.hitPad)
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.scaled(6)
        Spinner {
            visible: root.busy
            anchors.verticalCenter: parent.verticalCenter
            size: root.big ? Theme.iconMedium : Theme.iconSmall
            color: root.ink
        }
        Sym {
            visible: root.glyph !== "" && !root.busy
            anchors.verticalCenter: parent.verticalCenter
            name: root.glyph
            size: root.big ? Theme.iconMedium : Theme.iconSmall
            color: root.ink
        }
        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.ink
            font.family: Theme.fontMenu
            font.pixelSize: root.big ? Theme.typography.control : Theme.typography.secondary
            font.weight: Theme.weightSemibold
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -root.hitPad
        anchors.bottomMargin: -root.hitPad
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled)
                root.triggered();
        }
    }
}
