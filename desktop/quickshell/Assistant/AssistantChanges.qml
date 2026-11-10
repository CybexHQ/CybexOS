pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers
import "../Common/SettingsSearchData.js" as SettingsSearchData

// What an answer changed, one row each, with its own Undo (docs/assistant.md):
// a preference named as Settings names it, where it lives and its old and
// new value (a default resolved to what it was), a file, a widget, an app or
// a routine. A row that cannot be undone any more says why. "Undo all" undoes
// every row that still can, newest first.
Rectangle {
    id: root

    property var changes: []
    property string title: I18n.tr("Changed")
    readonly property var rows: changes.map(change => AssistantHelpers.changeRow(change, SettingsSearchData.ROWS,
        Settings.defaults))
    readonly property var undoable: rows.filter(row => row.undoable)

    visible: rows.length > 0
    height: visible ? column.implicitHeight : 0
    radius: Theme.scaled(10)
    color: "transparent"
    border.width: 1
    border.color: Theme.hairline
    clip: true

    function verb(row) {
        switch (row.action) {
        case "delete": return I18n.tr("Delete");
        case "remove": return I18n.tr("Remove");
        default: return I18n.tr("Undo");
        }
    }

    function why(row) {
        switch (row.status) {
        case "undone": return I18n.tr("Undone");
        case "blocked": return I18n.tr("Changed again later");
        case "changed": return I18n.tr("Changed since");
        default: return "";
        }
    }

    // Words a setting's value can be, in the person's language.
    function value(text) {
        switch (text) {
        case "On": return I18n.tr("On");
        case "Off": return I18n.tr("Off");
        case "default": return I18n.tr("Default");
        case "none": return I18n.tr("None");
        case "empty": return I18n.tr("Empty");
        default: return text;
        }
    }

    function detail(row) {
        if (row.kind === "setting")
            return row.place === "" ? "" : row.place.split(" · ").map(part => I18n.tr(part)).join(" · ");
        switch (row.detail) {
        case "created": return I18n.tr("created");
        case "modified": return I18n.tr("changed");
        case "deleted": return I18n.tr("removed");
        case "removed": return I18n.tr("removed");
        case "installed": return I18n.tr("installed");
        default: return row.detail;
        }
    }

    Column {
        id: column
        width: parent.width

        Item {
            width: parent.width
            height: Theme.scaled(28)

            Rectangle {
                anchors.fill: parent
                color: Theme.chip
                opacity: 0.45
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.scaled(9)
                anchors.verticalCenter: parent.verticalCenter
                text: root.title.toUpperCase()
                color: Theme.textFaint
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightSemibold
                font.letterSpacing: 0.6
            }

            AssistantButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.scaled(3)
                anchors.verticalCenter: parent.verticalCenter
                visible: root.undoable.length > 1
                glyph: "undo"
                label: I18n.tr("Undo all")
                controlHeight: Theme.scaled(24)
                color: "transparent"
                onTriggered: Assistant.undoChanges(root.undoable.map(row => row.id))
            }
        }

        Repeater {
            model: root.rows

            delegate: Item {
                id: row
                required property var modelData
                readonly property bool setting: modelData.kind === "setting"
                width: column.width
                height: Math.max(Theme.scaled(38), labels.implicitHeight + Theme.scaled(10))

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.hairline
                    opacity: 0.6
                }

                Sym {
                    id: glyph
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.scaled(9)
                    anchors.verticalCenter: parent.verticalCenter
                    name: row.modelData.glyph
                    size: Theme.iconSmall
                    color: Theme.textMid
                }

                Column {
                    id: labels
                    anchors.left: glyph.right
                    anchors.leftMargin: Theme.scaled(8)
                    anchors.right: values.left
                    anchors.rightMargin: Theme.scaled(8)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        objectName: "assistantChangeLabel"
                        width: parent.width
                        // Settings' own name for it, as the Settings window shows it.
                        text: row.setting ? I18n.tr(row.modelData.label) : row.modelData.label
                        elide: row.modelData.kind === "file" ? Text.ElideLeft : Text.ElideRight
                        textFormat: Text.PlainText
                        color: row.modelData.status === "undone" ? Theme.textLow : Theme.textHi
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        font.weight: Theme.weightMedium
                        font.strikeout: row.modelData.status === "undone"
                    }

                    Text {
                        objectName: "assistantChangePlace"
                        width: parent.width
                        visible: text !== ""
                        text: root.detail(row.modelData)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Theme.textFaint
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                    }
                }

                Row {
                    id: values
                    anchors.right: action.left
                    anchors.rightMargin: Theme.scaled(6)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.scaled(4)
                    visible: row.setting

                    // Old → new, both resolved: "Off → On", never "default".
                    Text {
                        objectName: "assistantChangeBefore"
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.value(row.modelData.before)
                        textFormat: Text.PlainText
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.typography.secondary
                    }
                    Sym {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow_forward"
                        size: Theme.iconSmall
                        color: Theme.textDim
                    }
                    Text {
                        objectName: "assistantChangeAfter"
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.value(row.modelData.after)
                        textFormat: Text.PlainText
                        color: Theme.textHi
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.typography.secondary
                        font.weight: Theme.weightSemibold
                    }
                }

                Item {
                    id: action
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.scaled(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(undoButton.visible ? undoButton.implicitWidth : 0,
                        reason.visible ? reason.implicitWidth : 0)
                    height: Theme.scaled(28)

                    AssistantButton {
                        id: undoButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.undoable
                        label: root.verb(row.modelData)
                        accessibleName: root.verb(row.modelData) + ": "
                            + (row.setting ? I18n.tr(row.modelData.label) : row.modelData.label)
                        controlHeight: Theme.scaled(28)
                        onTriggered: Assistant.undoChanges([row.modelData.id])
                    }

                    Text {
                        id: reason
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.modelData.undoable && text !== ""
                        text: root.why(row.modelData)
                        color: row.modelData.status === "undone" ? Theme.textFaint : Theme.amber
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                    }
                }
            }
        }
    }
}
