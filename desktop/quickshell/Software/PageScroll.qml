import QtQuick
import QtQuick.Controls as Controls
import "../Common"

// A page's scrolling column. Keyboard focus moving onto a control below or
// above the view scrolls it into sight.
Flickable {
    id: root

    default property alias content: column.data
    property real margin: Theme.scaled(26)
    property real spacing: Theme.scaled(14)
    readonly property real innerWidth: column.width
    readonly property Item focusedItem: Window.activeFocusItem

    contentWidth: width
    contentHeight: column.implicitHeight + Theme.scaled(22) * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar {}

    function reveal(item) {
        for (let node = item; node; node = node.parent) {
            if (node === column) {
                const point = item.mapToItem(column, 0, 0);
                const top = point.y + column.y - Theme.scaled(12);
                const bottom = point.y + column.y + item.height + Theme.scaled(12);
                if (top < contentY)
                    contentY = Math.max(0, top);
                else if (bottom > contentY + height)
                    contentY = Math.min(Math.max(0, contentHeight - height), bottom - height);
                return;
            }
        }
    }
    onFocusedItemChanged: {
        if (focusedItem && visible)
            reveal(focusedItem);
    }

    Column {
        id: column
        x: root.margin
        y: Theme.scaled(22)
        width: root.width - root.margin * 2
        spacing: root.spacing
    }
}
