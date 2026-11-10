pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/CalendarHelpers.js" as CalendarHelpers

// A Monday-first month: weekday initials over six weeks of dates. Calendar
// colours become small event marks; only three are drawn so a busy date stays
// a date rather than a chart. Today wears the accent pill, as the bar's
// current workspace does; a chosen date is a selected tile
// (docs/shell-states.md). The Day sheet and CalendarPopover share it, and
// each decides what choosing a date does.
Grid {
    id: root

    // Any date in the month shown.
    required property var month
    required property var today
    // The chosen date, or null for none.
    property var selected: null
    // Calendar.events, or [] to draw no marks.
    property var events: []
    property real cellHeight: Theme.scaled(28)

    signal chosen(var date)

    readonly property var first: new Date(month.getFullYear(), month.getMonth(), 1)

    function sameDay(left, right) {
        return !!left && !!right && left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate();
    }

    columns: 7
    rowSpacing: 1

    Repeater {
        // Monday-first initials in the session's language.
        model: [1, 2, 3, 4, 5, 6, 0].map(weekday =>
            Qt.locale().dayName(weekday, Locale.ShortFormat).slice(0, 2))

        delegate: Text {
            required property string modelData
            width: root.width / 7
            height: Math.round(root.cellHeight * 0.75)
            text: modelData
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontMono
            font.pixelSize: Theme.typography.secondary
            font.weight: Theme.weightMedium
            color: Theme.textFaint
        }
    }

    Repeater {
        model: 42

        delegate: Rectangle {
            id: day

            required property int index
            readonly property var cell: {
                const startOffset = (root.first.getDay() + 6) % 7;
                return new Date(root.first.getFullYear(), root.first.getMonth(),
                    1 - startOffset + index);
            }
            readonly property bool inMonth: cell.getMonth() === root.first.getMonth()
                && cell.getFullYear() === root.first.getFullYear()
            readonly property bool isToday: root.sameDay(cell, root.today)
            readonly property bool isSelected: root.sameDay(cell, root.selected)
            readonly property var matches: root.events.length > 0
                ? CalendarHelpers.eventsInRange(root.events,
                    new Date(cell.getFullYear(), cell.getMonth(), cell.getDate()).getTime(),
                    new Date(cell.getFullYear(), cell.getMonth(), cell.getDate() + 1).getTime(), 3)
                : []

            width: root.width / 7
            height: root.cellHeight
            radius: Theme.chipRadius
            color: isToday ? Theme.accent
                : isSelected ? Theme.selectedFill
                : dayMouse.containsMouse ? Theme.hoverFillStrong : "transparent"
            // The keyboard ring replaces the selected border while it shows.
            readonly property int ringWidth: Theme.focusWidth(activeFocus)
            border.width: ringWidth > 0 ? ringWidth
                : isSelected && !isToday ? Theme.selectedBorderWidth : 0
            border.color: ringWidth > 0 ? Theme.focusRing : Theme.selectedMark
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Qt.formatDateTime(cell, "dddd d MMMM")
                + (matches.length > 0 ? ", " + I18n.format("%1 events", [matches.length]) : "")
            Accessible.onPressAction: root.chosen(day.cell)

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                        || event.key === Qt.Key_Space) {
                    root.chosen(day.cell);
                    event.accepted = true;
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: day.matches.length > 0 ? -Theme.scaled(2) : 0
                text: day.cell.getDate()
                font.family: Theme.fontMono
                font.pixelSize: Theme.typography.primary
                font.weight: day.isToday || day.isSelected
                    ? Theme.weightSemibold : Theme.weightRegular
                font.features: Theme.tabularNumberFeatures
                color: day.isToday ? Theme.accentFg
                    : day.inMonth ? Theme.textMid : Theme.textFaint
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                spacing: 2

                Repeater {
                    model: day.matches

                    delegate: Rectangle {
                        required property var modelData
                        width: 3
                        height: 3
                        radius: 2
                        color: day.isToday ? Theme.accentFg : modelData.color
                    }
                }
            }

            MouseArea {
                id: dayMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    day.forceActiveFocus();
                    root.chosen(day.cell);
                }
            }
        }
    }
}
