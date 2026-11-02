import QtQuick
import "../Common"

// One choice in the box's agent and model menu: a label, an optional brand
// mark and a grey note, ticked when it is the current choice.
Rectangle {
    id: root

    property string label: ""
    property string detail: ""
    property string glyphBrand: ""
    property bool checked: false

    signal chosen()

    height: Theme.scaled(28)
    radius: Theme.scaled(6)
    color: mouse.containsMouse && enabled ? Theme.chipHover : "transparent"
    opacity: enabled ? 1 : 0.5
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.label
    Accessible.description: root.detail
    Accessible.checked: root.checked
    Accessible.onPressAction: {
        if (root.enabled)
            root.chosen();
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.scaled(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(7)

        BrandIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyphBrand !== ""
            width: Theme.iconSmall
            height: Theme.iconSmall
            name: root.glyphBrand
            colorized: true
            tint: Theme.textMid
            normalizeTintSource: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(6)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.detail !== ""
            text: root.detail
            color: Theme.textFaint
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
        }

        Sym {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.checked
            name: "check"
            size: Theme.iconSmall
            color: Theme.accentText
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.chosen()
    }
}
