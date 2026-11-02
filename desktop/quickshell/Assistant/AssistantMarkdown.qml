pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"
import "../Common/AssistantHelpers.js" as AssistantHelpers
import "../Common/T3CodeHelpers.js" as T3CodeHelpers

// A reply as Wiz shows it: prose as Markdown, and each fenced code block in
// its own well with the language and a Copy button (docs/assistant.md). Only
// web and mail links open; the agent wrote them.
Column {
    id: root

    property string text: ""
    property color color: Theme.textHi
    property bool plain: false
    readonly property var blocks: plain ? [{ kind: "text", text: text }] : AssistantHelpers.markdownBlocks(text)
    // The link under the pointer in any prose block, for the cursor.
    property string hoveredLink: ""

    spacing: Theme.scaled(8)

    Repeater {
        model: root.blocks

        delegate: Loader {
            id: block
            required property var modelData
            width: root.width
            sourceComponent: modelData.kind === "code" ? codeBlock : proseBlock

            Component {
                id: proseBlock

                TextEdit {
                    width: block.width
                    readOnly: true
                    selectByMouse: true
                    textFormat: root.plain ? TextEdit.PlainText : TextEdit.MarkdownText
                    text: root.plain ? block.modelData.text
                        : T3CodeHelpers.styleMarkdownLinks(block.modelData.text, Theme.accentText.toString())
                    wrapMode: TextEdit.Wrap
                    color: root.color
                    selectionColor: Theme.accentSoft
                    selectedTextColor: Theme.textHi
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    onLinkActivated: link => {
                        if (/^(https?|mailto):/i.test(link))
                            Quickshell.execDetached(["xdg-open", link]);
                    }
                    onHoveredLinkChanged: root.hoveredLink = hoveredLink

                    HoverHandler {
                        cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                    }
                }
            }

            Component {
                id: codeBlock

                Rectangle {
                    width: block.width
                    height: codeHeader.height + codeText.contentHeight + Theme.scaled(16)
                    radius: Theme.scaled(9)
                    color: Theme.well
                    border.width: 1
                    border.color: Theme.hairline
                    clip: true

                    Item {
                        id: codeHeader
                        width: parent.width
                        height: Theme.scaled(26)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.scaled(9)
                            anchors.verticalCenter: parent.verticalCenter
                            text: block.modelData.lang
                            color: Theme.textFaint
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.typography.metadata
                        }

                        AssistantButton {
                            id: copyCode
                            property bool copied: false
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.scaled(2)
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: copied ? "check" : "content_copy"
                            label: copied ? I18n.tr("Copied") : I18n.tr("Copy")
                            controlHeight: Theme.scaled(22)
                            color: "transparent"
                            onTriggered: {
                                Quickshell.clipboardText = block.modelData.text;
                                copied = true;
                                copiedReset.restart();
                            }

                            Timer {
                                id: copiedReset
                                interval: 1600
                                onTriggered: copyCode.copied = false
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.hairline
                        }
                    }

                    TextEdit {
                        id: codeText
                        x: Theme.scaled(10)
                        y: codeHeader.height + Theme.scaled(7)
                        width: parent.width - Theme.scaled(20)
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        text: block.modelData.text
                        wrapMode: TextEdit.WrapAnywhere
                        color: Theme.textHi
                        selectionColor: Theme.accentSoft
                        selectedTextColor: Theme.textHi
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.typography.control
                    }
                }
            }
        }
    }
}
