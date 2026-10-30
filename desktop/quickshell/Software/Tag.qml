import QtQuick
import "../Common"

// A short fact about an app: "Prebuilt", "Vendor download", its licence.
Rectangle {
    id: root

    property string text: ""
    property string glyph: ""
    // "ok", "vendor" or "" for neutral.
    property string tone: ""

    readonly property color ink: tone === "ok" ? Theme.ok : tone === "vendor" ? Theme.amber : Theme.textMid

    implicitWidth: row.implicitWidth + Theme.scaled(14)
    implicitHeight: label.implicitHeight + Theme.scaled(5)
    radius: Theme.chipRadius - 2
    color: tone === "ok" ? Theme.okBgSoft : tone === "vendor" ? Theme.amberBgSoft : Theme.chip
    Accessible.role: Accessible.StaticText
    Accessible.name: root.text

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.scaled(4)
        Sym {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: root.glyph
            size: Theme.iconTiny
            color: root.ink
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.ink
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightMedium
            textFormat: Text.PlainText
        }
    }
}
