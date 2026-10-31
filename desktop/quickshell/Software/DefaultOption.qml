pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// One app in a job's picker: what it is, what keeps working with Cybex OS
// and what doesn't, and how it would arrive. Click selects; double-click uses.
Rectangle {
    id: root

    // A roleOption row ({option, source, desktop}), or an installed app that
    // is not among the job's options ({other: {value, label}}).
    property var row: ({})
    property bool selected: false
    property bool current: false
    property bool pick: false
    signal chosen()
    signal confirmed()

    readonly property var option: row.option || null
    readonly property string name: option ? option.name : row.other ? row.other.label : ""
    readonly property var notes: option ? Helpers.perks(option, Software.catalogue.allowUnfree === true) : []

    function tag() {
        switch (row.source) {
        case "installed":
            return { tone: "ok", glyph: "check", text: I18n.tr("Installed") };
        case "web":
            return { tone: "", glyph: "world", text: I18n.tr("In your browser") };
        case "nixos": {
            const size = Helpers.size(option.downloadBytes);
            return { tone: "ok", glyph: "bolt", text: size !== "" ? I18n.format("Prebuilt · ≈ %1", [size]) : I18n.tr("Prebuilt") };
        }
        case "vendor":
            return { tone: "vendor", glyph: "download", text: I18n.tr("Vendor download") };
        case "flathub":
            return { tone: "", glyph: "shield-lock", text: I18n.tr("Flathub") };
        }
        return row.other ? { tone: "ok", glyph: "check", text: I18n.tr("Installed") } : null;
    }

    objectName: "softwareDefaultOption"
    implicitHeight: Math.max(icon.height, copy.implicitHeight) + Theme.scaled(22)
    radius: Theme.chipRadius + 4
    color: selected ? Theme.accentAlpha(Theme.dark ? 0.14 : 0.11) : "transparent"
    border.width: selected || activeFocus ? 1 : 0
    border.color: selected ? Theme.accentAlpha(0.55) : Theme.accentText
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.name: name
    Accessible.description: option ? option.summary || "" : ""
    Accessible.onPressAction: root.chosen()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space) {
            root.chosen();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.chosen();
            root.confirmed();
            event.accepted = true;
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        hovered: mouse.containsMouse && !root.selected
        pressed: mouse.pressed
        rippleEnabled: false
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.chosen()
        onDoubleClicked: {
            root.chosen();
            root.confirmed();
        }
    }

    Rectangle {
        id: radio
        x: Theme.scaled(12)
        y: Theme.scaled(11) + (icon.height - height) / 2
        width: Theme.scaled(18)
        height: width
        radius: width / 2
        color: root.selected ? Theme.accent : "transparent"
        border.width: root.selected ? 0 : 1.5
        border.color: Theme.stroke
        Rectangle {
            anchors.centerIn: parent
            visible: root.selected
            width: parent.width * 0.4
            height: width
            radius: width / 2
            color: Theme.textOnAccent
        }
    }
    RoleIcon {
        id: icon
        anchors.left: radio.right
        anchors.leftMargin: Theme.scaled(12)
        y: Theme.scaled(11)
        option: root.option
        desktop: root.row.desktop || (root.row.other ? root.row.other.value : "")
        size: Theme.scaled(40)
    }
    Column {
        id: copy
        anchors.left: icon.right
        anchors.leftMargin: Theme.scaled(12)
        anchors.right: source.left
        anchors.rightMargin: Theme.scaled(10)
        y: Theme.scaled(11)
        spacing: Theme.scaled(3)
        Flow {
            width: parent.width
            spacing: Theme.scaled(7)
            Text {
                objectName: "softwareDefaultOptionName"
                text: root.name
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                textFormat: Text.PlainText
            }
            Rectangle {
                visible: root.pick
                implicitWidth: pickLabel.implicitWidth + Theme.scaled(14)
                implicitHeight: pickLabel.implicitHeight + Theme.scaled(4)
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.stroke
                Text {
                    id: pickLabel
                    anchors.centerIn: parent
                    text: I18n.tr("Cybex pick")
                    color: Theme.textMid
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightSemibold
                    textFormat: Text.PlainText
                }
            }
            Rectangle {
                visible: root.current
                implicitWidth: useLabel.implicitWidth + Theme.scaled(14)
                implicitHeight: useLabel.implicitHeight + Theme.scaled(4)
                radius: height / 2
                color: Theme.accent
                Text {
                    id: useLabel
                    anchors.centerIn: parent
                    text: I18n.tr("In use")
                    color: Theme.textOnAccent
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightSemibold
                    textFormat: Text.PlainText
                }
            }
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.option ? root.option.summary || "" : ""
            color: Theme.textMid
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Flow {
            width: parent.width
            visible: root.notes.length > 0
            topPadding: Theme.scaled(2)
            spacing: Theme.scaled(12)
            Repeater {
                model: root.notes
                delegate: Row {
                    id: perk
                    required property var modelData
                    spacing: Theme.scaled(4)
                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: perk.modelData.yes ? "check" : "minus"
                        size: Theme.iconTiny
                        color: perk.modelData.yes ? Theme.ok : Theme.textDim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Software.perkLabel(perk.modelData.key, perk.modelData.yes)
                        color: perk.modelData.yes ? Theme.textMid : Theme.textDim
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }
    Tag {
        id: source
        readonly property var value: root.tag()
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(12)
        y: Theme.scaled(11) + (icon.height - height) / 2
        visible: value !== null
        tone: value ? value.tone : ""
        glyph: value ? value.glyph : ""
        text: value ? value.text : ""
    }
}
