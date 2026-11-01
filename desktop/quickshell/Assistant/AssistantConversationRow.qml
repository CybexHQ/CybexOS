pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers

// One conversation in History or under the new box's suggestions: the agent's
// mark, its first question, the latest answer, and when. A question still
// running says so instead of a time; hovering a deletable row offers Delete.
Rectangle {
    id: root

    required property var row
    property bool showPreview: true
    property bool deletable: false
    readonly property string status: AssistantHelpers.liveStatus(root.row, Assistant.turn)
    readonly property bool hovered: mouse.containsMouse || deleteButton.hovered

    signal opened()
    signal deleteRequested()

    implicitHeight: content.implicitHeight + Theme.scaled(14)
    radius: Theme.scaled(9)
    color: root.hovered || root.activeFocus ? Theme.chipHover : "transparent"
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.row.title || ""
    Accessible.description: root.timeLabel()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.opened();
            event.accepted = true;
        } else if (root.deletable && event.key === Qt.Key_Delete) {
            root.deleteRequested();
            event.accepted = true;
        }
    }

    function timeLabel() {
        const at = root.row.updatedAt || 0;
        const time = AssistantHelpers.historyTime(at, Assistant.now);
        const locale = Qt.locale(I18n.language);
        switch (time.kind) {
        case "now": return I18n.tr("now");
        case "minutes": return I18n.format("%1 min", [time.value]);
        case "time": return Qt.formatTime(new Date(at), Settings.clock24 ? "HH:mm" : "h:mm AP");
        case "yesterday": return I18n.tr("Yesterday");
        case "weekday": return locale.toString(new Date(at), "ddd");
        default: return locale.toString(new Date(at), "d MMM");
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
    }

    BrandIcon {
        id: mark
        anchors.left: parent.left
        anchors.leftMargin: Theme.scaled(8)
        anchors.top: parent.top
        anchors.topMargin: Theme.scaled(8)
        width: Theme.iconSmall
        height: Theme.iconSmall
        name: AssistantHelpers.AGENT_ICONS[root.row.agent] || ""
        colorized: true
        tint: Theme.textLow
        normalizeTintSource: true
    }

    Column {
        id: content
        anchors.left: mark.right
        anchors.leftMargin: Theme.scaled(9)
        anchors.right: trailing.left
        anchors.rightMargin: Theme.scaled(8)
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: root.row.title || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textHi
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
        }

        Text {
            width: parent.width
            visible: root.showPreview && text !== ""
            text: root.status === "running" || root.status === "waiting"
                ? (Assistant.turn && Assistant.turn.conversation === root.row.id
                    ? Assistant.turn.step || "" : root.row.preview || "")
                : root.row.preview || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textLow
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
        }
    }

    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(when.visible ? when.implicitWidth : 0, chip.visible ? chip.width : 0,
            deleteButton.visible ? deleteButton.width : 0)
        height: Theme.scaled(24)

        Text {
            id: when
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !chip.visible && !deleteButton.visible
            text: root.timeLabel()
            color: Theme.textFaint
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.metadata
            font.features: Theme.tabularNumberFeatures
        }

        // Working, or the amber "your move".
        Rectangle {
            id: chip
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: (root.status === "running" || root.status === "waiting") && !deleteButton.visible
            width: chipText.implicitWidth + Theme.scaled(12)
            height: Theme.scaled(20)
            radius: Theme.scaled(5)
            color: root.status === "waiting" ? Theme.amberBg : Theme.chip

            Text {
                id: chipText
                anchors.centerIn: parent
                text: root.status === "waiting" ? I18n.tr("Your move") : I18n.tr("Working")
                color: root.status === "waiting" ? Theme.amber : Theme.accentText
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.weight: Theme.weightSemibold
            }
        }

        AssistantButton {
            id: deleteButton
            readonly property bool hovered: deleteHover.hovered
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.deletable && root.hovered
            glyph: "delete"
            accessibleName: I18n.format("Delete “%1”", [root.row.title || ""])
            controlHeight: Theme.scaled(24)
            onTriggered: root.deleteRequested()

            HoverHandler {
                id: deleteHover
            }
        }
    }
}
