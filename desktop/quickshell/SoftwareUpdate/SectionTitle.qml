import QtQuick
import "../Common"

// A small capitalised heading over one of a page's cards.
Text {
    width: parent ? parent.width : 0
    topPadding: Theme.scaled(10)
    color: Theme.textDim
    font.family: Theme.fontMenu
    font.pixelSize: Theme.typography.metadata
    font.weight: Theme.weightSemibold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
    textFormat: Text.PlainText
}
