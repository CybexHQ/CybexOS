import QtQuick
import "../Common"
import "../Common/ControlIconHelpers.js" as ControlIconHelpers

// The Control Center button's icon as the bar draws it
// (Common/ControlIconHelpers.js): the Cybex OS mark from its SVG, or a Nerd
// Font glyph for the operating system's logo or a chosen icon, in the same
// resting and hover ink as the bar's other marks. The Cybex X alone is drawn
// two-tone so it does not read as a close button (BarBrandIcon). Settings
// previews it with the value being chosen.
Item {
    id: root

    property string value: Settings.controlIcon
    property bool highlighted: false
    property color idleColor: Theme.barIcon
    property color hoverColor: Theme.barTextHi
    readonly property string glyph: ControlIconHelpers.barGlyph(value)
    // Nerd Font icons are drawn a touch larger than their em so their marks
    // match the SVG mark's optical size.
    readonly property int glyphPixels: Math.round(height * 1.1)

    implicitWidth: Theme.barIconSize
    implicitHeight: Theme.barIconSize

    BarBrandIcon {
        anchors.fill: parent
        visible: root.glyph === ""
        name: "cybexos"
        highlighted: root.highlighted
    }

    Text {
        anchors.centerIn: parent
        visible: root.glyph !== ""
        text: root.glyph
        font.family: Theme.fontNerdIcons
        font.pixelSize: root.glyphPixels
        color: root.highlighted ? root.hoverColor : root.idleColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
            ColorAnimation { duration: Theme.chipFadeDuration }
        }
    }
}
