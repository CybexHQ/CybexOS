import QtQuick
import "../Common"
import "../Common/SettingsHelpers.js" as SettingsHelpers

// A short status beside the action that settles it (2026-11 action tiers,
// docs/shell-states.md): a dot and one or two words on a tint of the same
// hue, so a row's state reads apart from its title and its button. The dot
// and the words carry the meaning together; colour is never the only cue.
//
// `tone` is info | ok | amber | red | neutral. Info sits on the neutral chip
// rather than an accent field: the accent is a mark here, as everywhere.
Rectangle {
    id: root

    property string text: ""
    property string tone: "info"

    readonly property color fill: tone === "red" ? Theme.redBgSoft
        : tone === "amber" ? Theme.amberBgSoft
        : tone === "ok" ? Theme.okBgSoft
        : Theme.chip
    readonly property color baseInk: tone === "red" ? Theme.redText
        : tone === "amber" ? Theme.amber
        : tone === "ok" ? Theme.ok
        : tone === "neutral" ? Theme.textMid
        : Theme.accentText
    // The status inks clear 4.5:1 over the plain panel; a tint under them
    // can take that away (light red did), so the words are held to 4.5:1
    // over the tint laid on the least favourable backdrop.
    readonly property color ink: SettingsHelpers.ensureContrast(baseInk.toString(),
        SettingsHelpers.mixHex(Theme.copyReferenceBg.toString(),
            Qt.rgba(fill.r, fill.g, fill.b, 1).toString(), fill.a), 4.5)
    readonly property color dotColor: tone === "red" ? Theme.red
        : tone === "neutral" ? Theme.textFaint
        : ink

    visible: text !== ""
    implicitWidth: pillRow.implicitWidth + Theme.scaled(18)
    implicitHeight: Math.max(Theme.scaled(22), label.implicitHeight + Theme.scaled(6))
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: fill
    Accessible.role: Accessible.StaticText
    Accessible.name: root.text

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: Theme.iconTextSpacing

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.scaled(7)
            height: width
            radius: width / 2
            color: root.dotColor
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightSemibold
            color: root.ink
            Accessible.ignored: true
        }
    }
}
