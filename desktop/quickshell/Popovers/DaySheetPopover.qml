pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../Common"

// The Day sheet: the surface the clock (and the weather pill) unrolls under
// the bar — big time, today's sky and the next days' forecast, the month
// with event marks (MonthGrid, shared with CalendarPopover), and the next
// few events. Without a location the sky is a prompt to set one. Attached
// flush under the bar and centred on the bar regardless of which trigger
// opened it (PanelRegistryData `attached` + `centerAnchored`).
Surface {
    id: root

    padding: Theme.scaled(20)
    spacing: Theme.scaled(16)
    implicitWidth: Theme.daySheetWidth

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // The month shown, as an offset from this one. Every open starts on
    // today's month; browsing asks the calendar for that month's events.
    property int monthOffset: 0
    readonly property var shownMonth: new Date(clock.date.getFullYear(),
        clock.date.getMonth() + monthOffset, 1)

    onVisibleChanged: {
        if (visible)
            monthOffset = 0;
    }
    onShownMonthChanged: {
        if (visible && monthOffset !== 0)
            Calendar.ensureMonth(shownMonth, false);
    }

    // The next five days' sky, today first, once a location is set.
    readonly property var forecast: Weather.days.slice(0, 5).map((day, offset) => {
        const date = new Date(clock.date.getFullYear(), clock.date.getMonth(),
            clock.date.getDate() + offset);
        return { date: date, code: day.code, hi: day.hi, lo: day.lo };
    })

    readonly property var events: Calendar.upcoming(3)

    // Keyed on visibility, not construction, so a latched sheet still asks
    // for a fresh window and sky on every open and polls only while shown.
    Claim {
        active: root.visible
        onClaimed: {
            Calendar.acquire();
            Weather.acquire();
        }
        onReleased: {
            Calendar.release();
            Weather.release();
        }
    }

    Row {
        width: parent.width
        spacing: Theme.scaled(24)

        // ---- clock and sky ------------------------------------------------
        Column {
            id: clockColumn
            width: Math.max(Theme.scaled(220), clockText.implicitWidth)
            spacing: 6

            Text {
                id: clockText
                text: Qt.formatDateTime(clock.date,
                    Settings.clock24 ? "HH:mm" : "h:mm AP")
                font.family: Theme.fontNumeric
                font.pixelSize: Theme.typography.clock
                font.weight: Theme.weightSemibold
                font.letterSpacing: -2
                font.features: Theme.tabularNumberFeatures
                color: Theme.textHi
            }

            Text {
                width: parent.width
                text: Qt.formatDateTime(clock.date, "dddd d MMMM")
                wrapMode: Text.Wrap
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
            }

            Row {
                visible: Weather.locationSet
                topPadding: 8
                spacing: 8

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Weather.symbol(Weather.code, Weather.isDay)
                    size: 22
                    color: Weather.ready
                        ? Weather.glyphColor(Weather.code, Weather.isDay)
                        : Theme.textMid
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.ready ? Weather.temp + "°" : "--"
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.typography.title
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textHi
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, clockColumn.width - x)
                    elide: Text.ElideRight
                    text: {
                        if (!Weather.ready)
                            return Weather.offline ? I18n.tr("Offline") : I18n.tr("Loading…");
                        const today = Weather.days.length > 0
                            ? Weather.days[0] : null;
                        return Weather.condition + (today
                            ? " · " + today.hi + "° / " + today.lo + "°" : "");
                    }
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    color: Theme.textFaint
                }
            }

            // The next days at a glance: what the week strip carried.
            Row {
                visible: Weather.locationSet && Weather.ready && root.forecast.length > 1
                topPadding: 4
                spacing: 0

                Repeater {
                    model: root.forecast

                    delegate: Column {
                        id: forecastDay

                        required property var modelData
                        required property int index

                        width: clockColumn.width / 5
                        spacing: 3

                        Accessible.role: Accessible.StaticText
                        Accessible.name: Qt.formatDateTime(modelData.date, "dddd") + ", "
                            + modelData.hi + "° / " + modelData.lo + "°"

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: forecastDay.index === 0 ? I18n.tr("Today")
                                : Qt.formatDateTime(forecastDay.modelData.date, "ddd")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.metadata
                            font.weight: Theme.weightSemibold
                            color: forecastDay.index === 0 ? Theme.accentText : Theme.textFaint
                        }

                        Sym {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.symbol(forecastDay.modelData.code, true)
                            size: Theme.iconMedium
                            color: Weather.glyphColor(forecastDay.modelData.code, true)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: forecastDay.modelData.hi + "°"
                            font.family: Theme.fontNumeric
                            font.pixelSize: Theme.typography.secondary
                            font.weight: Theme.weightSemibold
                            font.features: Theme.tabularNumberFeatures
                            color: Theme.textHi
                        }
                    }
                }
            }

            // Without coordinates there is no sky to describe: a short
            // prompt and the one action that fixes it, which opens the
            // weather widget's own options in Settings.
            Item {
                width: parent.width
                height: Theme.scaled(4)
                visible: !Weather.locationSet
            }

            Rectangle {
                id: locationPrompt

                visible: !Weather.locationSet
                width: parent.width
                height: promptColumn.implicitHeight + Theme.scaled(12) * 2
                radius: Theme.cardRadius
                color: Theme.chip

                Accessible.role: Accessible.Grouping
                Accessible.name: I18n.tr("Weather needs a location")

                Sym {
                    id: promptGlyph
                    x: Theme.scaled(12)
                    y: Theme.scaled(12)
                    name: "map-pin"
                    size: Theme.iconLarge
                    color: Theme.accentText
                }

                Column {
                    id: promptColumn
                    x: promptGlyph.x + promptGlyph.width + Theme.scaled(10)
                    y: Theme.scaled(12)
                    width: Math.max(0, parent.width - x - Theme.scaled(12))
                    spacing: Theme.scaled(8)

                    Text {
                        width: parent.width
                        text: I18n.tr("Add your location to see the weather here.")
                        wrapMode: Text.Wrap
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        color: Theme.textMid
                    }

                    ActionButton {
                        label: I18n.tr("Set location")
                        hPadding: 24
                        tint: Theme.accentText
                        fill: Theme.accentBgSoft
                        onTriggered: {
                            Settings.openWidgetSettings("weather");
                            Settings.showPanel("bar", Popouts.hostScreenName);
                        }
                    }
                }
            }
        }

        // ---- the month ----------------------------------------------------
        Column {
            id: monthColumn
            width: parent.width - clockColumn.width - parent.spacing
            spacing: 4

            Item {
                width: parent.width
                height: Theme.inlineActionHeight

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: monthActions.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(root.shownMonth, "MMMM yyyy")
                    elide: Text.ElideRight
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    font.weight: Theme.weightSemibold
                    color: Theme.textMid
                }

                Row {
                    id: monthActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        visible: root.monthOffset !== 0
                        symbol: "today"
                        tint: Theme.textLow
                        controlSize: Theme.inlineActionHeight
                        accessibleName: I18n.tr("This month")
                        onTriggered: root.monthOffset = 0
                    }

                    IconButton {
                        symbol: "chevron_left"
                        tint: Theme.textLow
                        controlSize: Theme.inlineActionHeight
                        accessibleName: I18n.tr("Previous month")
                        onTriggered: root.monthOffset--
                    }

                    IconButton {
                        symbol: "chevron_right"
                        tint: Theme.textLow
                        controlSize: Theme.inlineActionHeight
                        accessibleName: I18n.tr("Next month")
                        onTriggered: root.monthOffset++
                    }
                }
            }

            // A date opens the calendar app on that day, as the week's
            // cells did.
            MonthGrid {
                width: parent.width
                month: root.shownMonth
                today: clock.date
                events: Calendar.enabled ? Calendar.events : []
                onChosen: date => {
                    Popouts.close();
                    Calendar.openCalendar(date);
                }
            }
        }
    }

    // ---- next events -----------------------------------------------------
    Grid {
        id: eventsGrid
        visible: root.events.length > 0
        width: parent.width
        columns: 3
        columnSpacing: 8

        readonly property real cellWidth: (width - columnSpacing * 2) / 3

        Repeater {
            model: root.events

            delegate: Rectangle {
                id: eventCard

                required property var modelData
                readonly property bool ongoing: {
                    void clock.date;
                    const now = Date.now();
                    return modelData.startMs <= now && now < modelData.endMs;
                }

                width: eventsGrid.cellWidth
                height: 56
                radius: 10
                color: Theme.chip

                Rectangle {
                    id: eventBar
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 28
                    radius: 2
                    color: eventCard.modelData.color
                }

                Column {
                    anchors.left: eventBar.right
                    anchors.leftMargin: 10
                    anchors.right: eventTime.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: eventCard.modelData.summary
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.primary
                        font.weight: Theme.weightMedium
                        color: Theme.textHi
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: {
                            void clock.date;
                            const start = new Date(eventCard.modelData.startMs);
                            const today = new Date();
                            today.setHours(0, 0, 0, 0);
                            const tomorrow = new Date(today);
                            tomorrow.setDate(today.getDate() + 1);
                            const startDay = Calendar.dayStart(start);
                            const day = eventCard.ongoing ? "Now"
                                : startDay === today.getTime() ? "Today"
                                : startDay === tomorrow.getTime() ? "Tomorrow"
                                : Qt.formatDateTime(start, "ddd d MMM");
                            return day + " · " + eventCard.modelData.calendar;
                        }
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.secondary
                        color: Theme.textFaint
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: eventTime
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: eventCard.modelData.allDay ? "all day"
                        : Qt.formatDateTime(new Date(eventCard.modelData.startMs),
                            Settings.clock24 ? "HH:mm" : "h:mm AP")
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.typography.secondary
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: eventCard.ongoing ? Theme.accentText : Theme.textHi
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Popouts.close();
                        Calendar.openCalendar(eventCard.modelData.startMs);
                    }
                }

                Accessible.role: Accessible.Button
                Accessible.name: eventCard.modelData.summary
            }
        }
    }

    // A calendar that timed out still leaves the others' events here; say
    // that some are missing rather than let the week look complete.
    Text {
        visible: Calendar.partialWarning !== "" && Calendar.ready
        width: parent.width
        text: Calendar.partialWarning
        elide: Text.ElideRight
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        color: Theme.textFaint
    }
}
