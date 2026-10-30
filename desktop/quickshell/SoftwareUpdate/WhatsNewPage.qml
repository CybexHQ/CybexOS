import QtQuick
import QtQuick.Controls as Controls
import "../Common"
import "../Common/UpdatesHelpers.js" as Helpers
import "../Common/NotesHelpers.js" as NotesHelpers
import "../Common/ExternalUrl.js" as ExternalUrl
import "../Assistant" as AssistantUi

// What's new in a kept Cybex OS release: its release notes and important
// changes, as the update's review showed them, read from the worker's
// record (UpdatesHelpers.keptRelease). Nothing is fetched. Back returns to
// the status.
Item {
    id: root

    property var release: ({ version: "", notes: "", components: [] })
    property string pose: "happy"
    signal back()

    // The shell's Markdown, its links in the accent; release notes never
    // load images or raw HTML.
    readonly property string notes: NotesHelpers.styleMarkdownLinks(Helpers.releaseNotes(release.notes),
        Theme.accentText.toString())

    Item {
        id: header
        width: parent.width
        height: backButton.height + Theme.scaled(24)
        UpdateButton {
            id: backButton
            objectName: "updateBack"
            x: Theme.scaled(16)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "arrow-left"
            text: I18n.tr("Back")
            onTriggered: root.back()
        }
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: column.implicitHeight + Theme.scaled(40)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        Controls.ScrollBar.vertical: Controls.ScrollBar {}

        Column {
            id: column
            width: Math.min(flick.width - Theme.scaled(56), Theme.scaled(560))
            x: Math.round((flick.width - width) / 2)
            spacing: Theme.scaled(10)

            // Decorative: the heading says it.
            AssistantUi.Wiz {
                objectName: "updateWiz"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.scaled(112)
                height: width
                pose: root.pose
                Accessible.ignored: true
            }

            Text {
                objectName: "updateTitle"
                width: parent.width
                text: I18n.format("What's new in Cybex OS %1", [root.release.version])
                color: Theme.textHi
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.heading
                font.weight: Theme.weightSemibold
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            SectionTitle {
                text: I18n.tr("Release notes")
            }
            Rectangle {
                width: parent.width
                height: notesText.implicitHeight + Theme.scaled(28)
                radius: Theme.chipRadius + 3
                color: Theme.cardFill
                border.width: 1
                border.color: Theme.hairlineSoft
                Text {
                    id: notesText
                    objectName: "updateReleaseNotes"
                    x: Theme.scaled(16)
                    y: Theme.scaled(14)
                    width: parent.width - Theme.scaled(32)
                    text: root.notes !== "" ? root.notes : I18n.tr("No release notes were published for this version.")
                    textFormat: root.notes !== "" ? Text.MarkdownText : Text.PlainText
                    color: root.notes !== "" ? Theme.textMid : Theme.textDim
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    wrapMode: Text.Wrap
                    // Only web links open, in the browser.
                    onLinkActivated: link => {
                        const url = ExternalUrl.safeHttpUrl(link);
                        if (url !== "") Qt.openUrlExternally(url);
                    }
                    HoverHandler {
                        cursorShape: notesText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }

            SectionTitle {
                visible: root.release.components.length > 0
                text: I18n.tr("Important changes")
            }
            ComponentChanges {
                width: parent.width
                components: root.release.components
            }
        }
    }
}
