import QtQuick
import "../Common"

// Software's buttons: one accent-filled primary action per surface, quiet
// outlined ones, and "queued" for an app already on the install list. Over
// brand artwork a view passes its own `foreground`.
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
    property string accessibleName: text
    signal triggered()

    readonly property bool custom: foreground.a > 0
    readonly property color ink: primary ? Theme.textOnAccent : queued ? Theme.accentText
        : custom ? foreground : Theme.textHi

    implicitWidth: content.implicitWidth + Theme.scaled(big ? 36 : 24)
    implicitHeight: Theme.scaled(big ? 38 : 30)
    radius: Theme.chipRadius + (big ? 2 : 0)
    color: primary ? Theme.accent : queued ? Theme.accentAlpha(0.16)
        : custom ? Qt.rgba(foreground.r, foreground.g, foreground.b, quiet ? 0 : 0.14)
        : quiet ? "transparent" : Theme.hoverFill
    border.width: activeFocus ? 2 : (queued || quiet) ? 1 : 0
    border.color: activeFocus ? (primary ? Theme.textHi : Theme.accentText)
        : queued ? Theme.accentAlpha(0.5)
        : custom ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35) : Theme.stroke
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
        pressPoint: Qt.point(mouse.mouseX, mouse.mouseY)
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
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled)
                root.triggered();
        }
    }
}
