pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// "What Wiz did": one line per tool the agent used, in plain words, with
// what it was pointed at in grey (docs/assistant.md). Cybex OS's own desktop
// tools carry the accent. Folded under its count after a short answer.
Column {
    id: root

    property var steps: []
    property bool folded: true

    visible: steps.length > 0
    spacing: Theme.scaled(2)

    Item {
        width: root.width
        height: Theme.scaled(28)

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(4)

            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: root.folded ? "chevron_right" : "expand_more"
                size: Theme.iconSmall
                color: Theme.textLow
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.steps.length === 1 ? I18n.tr("What Wiz did · 1 step")
                    : I18n.format("What Wiz did · %1 steps", [root.steps.length])
                color: Theme.textMid
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
            }
        }

        // A 32 px target around the 28 px line.
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -Theme.scaled(2)
            anchors.bottomMargin: -Theme.scaled(2)
            cursorShape: Qt.PointingHandCursor
            onClicked: root.folded = !root.folded
        }

        Accessible.role: Accessible.Button
        Accessible.name: root.folded ? I18n.tr("Show what Wiz did") : I18n.tr("Hide what Wiz did")
    }

    Column {
        visible: !root.folded
        x: Theme.scaled(8)
        width: root.width - x
        spacing: Theme.scaled(1)

        Repeater {
            model: root.folded ? [] : root.steps

            delegate: Item {
                id: step
                required property var modelData
                width: parent.width
                height: Theme.scaled(20)

                Rectangle {
                    x: 0
                    width: 1
                    height: parent.height
                    color: Theme.hairline
                }

                Sym {
                    id: mark
                    x: Theme.scaled(10)
                    anchors.verticalCenter: parent.verticalCenter
                    name: step.modelData.tool ? "auto_awesome" : "check"
                    size: Theme.iconSmall
                    color: step.modelData.tool ? Theme.accentText : Theme.textFaint
                }

                Text {
                    id: label
                    anchors.left: mark.right
                    anchors.leftMargin: Theme.scaled(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - mark.width - Theme.scaled(80))
                    text: step.modelData.label
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: Theme.textLow
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                }

                Text {
                    anchors.left: label.right
                    anchors.leftMargin: Theme.scaled(8)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: step.modelData.detail || ""
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    color: Theme.textFaint
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.typography.metadata
                }
            }
        }
    }
}
