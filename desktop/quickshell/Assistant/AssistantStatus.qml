import QtQuick
import "../Common"

// The one-line status under Wiz while the pointer rests on him
// (docs/assistant.md): a reply ready, what he is working on, a question
// waiting for you, a routine's finding, or an invitation. A click opens the
// box; this only says what the click would find.
AssistantSurface {
    id: root

    padding: Theme.scaled(9)
    spacing: Theme.scaled(1)

    Text {
        width: parent.width
        text: Assistant.status.title
        elide: Text.ElideRight
        color: Theme.textHi
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        font.weight: Theme.weightSemibold
    }

    Text {
        width: parent.width
        visible: text !== ""
        text: Assistant.status.detail || ""
        elide: Text.ElideRight
        textFormat: Text.PlainText
        color: Theme.textLow
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
    }

    Text {
        width: parent.width
        text: Settings.assistantTuck !== "" ? I18n.tr("Click to bring me out")
            : I18n.tr("Click to open · drag to move")
        elide: Text.ElideRight
        color: Theme.textFaint
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.metadata
    }
}
