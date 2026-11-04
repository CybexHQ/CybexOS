pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "Common"
import "Common/Format.js" as Format
import "Settings" as SettingsUi

// Dictation history (docs/dictation.md): what was dictated, newest first,
// kept on this computer for as long as Settings → Assistant → Dictation says.
// A dictation that could not be typed waits here to be typed again. Opened
// from the menubar's dictation action (middle click), Super+Ctrl+Shift+X, the
// pill after a failure, and Settings. It takes the keyboard while open (its
// search field) and closes on Escape or a click elsewhere; typing an entry
// again closes it first, so the words go to the window underneath.
PanelWindow {
    id: root

    readonly property bool shown: Dictation.historyOpen
    visible: shown || card.opacity > 0.001
    screen: Screens.focused
    readonly property bool atBottom: Settings.position === "bottom"
    readonly property int barClearance: Theme.barTopMargin + Theme.barHeight + 8
    readonly property bool sharesBarScreen: Screens.hasBar(root.screen)
    anchors {
        top: !atBottom
        bottom: atBottom
        right: true
    }
    // qmllint disable unqualified
    margins {
        top: !atBottom && sharesBarScreen ? barClearance : 12
        bottom: atBottom && sharesBarScreen ? barClearance : 12
        right: 12
    }
    // qmllint enable unqualified
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-dictation-history"
    // As the launcher does: Exclusive takes the keyboard as the window maps;
    // the dismissal grab follows once the window is active (on Hyprland 0.56
    // a grab installed with the map keeps the keyboard from arriving), and
    // then OnDemand lets an outside click reach the grab's dismissal.
    WlrLayershell.keyboardFocus: !shown ? WlrKeyboardFocus.None
        : dismissalGrab.active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    readonly property bool keyboardActive: root.contentItem.Window.active
    property bool dismissalGrabReady: false
    onKeyboardActiveChanged: {
        if (keyboardActive && shown) {
            dismissalGrabReady = true;
            search.forceActiveFocus();
        }
    }

    HyprlandFocusGrab {
        id: dismissalGrab
        active: root.shown && root.dismissalGrabReady
        windows: [root]
        onCleared: Dictation.closeHistory()
    }

    property string query: ""
    property string editing: ""
    property string confirmClear: ""

    onShownChanged: {
        dismissalGrabReady = shown && keyboardActive;
        if (shown) {
            query = "";
            editing = "";
            search.text = "";
            search.forceActiveFocus();
        }
    }

    readonly property string retentionText: {
        switch (Settings.modOpts.indicators.dictationHistory) {
        case "forever": return I18n.tr("Kept until you delete them");
        case "session": return I18n.tr("Not saved, except words that could not be typed");
        default: return I18n.tr("Kept for 30 days");
        }
    }

    function dayLabel(seconds) {
        const date = new Date(seconds * 1000);
        const today = new Date();
        const start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        if (date.getTime() >= start)
            return I18n.tr("Today");
        if (date.getTime() >= start - Format.MS_DAY)
            return I18n.tr("Yesterday");
        return Qt.formatDate(date, "dddd d MMMM");
    }

    function timeLabel(seconds) {
        return Qt.formatTime(new Date(seconds * 1000), Settings.clock24 ? "HH:mm" : "h:mm AP");
    }

    // Day headings between the entries that match the search.
    readonly property var rows: {
        const needle = query.trim().toLowerCase();
        const found = [];
        let day = "";
        for (const entry of Dictation.historyEntries) {
            if (needle !== "" && String(entry.text || "").toLowerCase().indexOf(needle) === -1
                    && String(entry.app || "").toLowerCase().indexOf(needle) === -1)
                continue;
            const label = dayLabel(entry.time || 0);
            if (label !== day) {
                day = label;
                found.push({kind: "day", label: label, key: "day-" + label});
            }
            found.push({kind: "entry", entry: entry, key: entry.id});
        }
        return found;
    }

    Rectangle {
        id: card

        y: root.shown ? 0 : (root.atBottom ? 12 : -12)
        opacity: root.shown ? 1 : 0
        width: Math.min(Theme.scaled(460, Theme.typeScale), (root.screen ? root.screen.width : 1280) - 24)
        height: column.implicitHeight + Theme.scaled(24)
        // The room the list may take: the screen below the bar, less the
        // panel's own rows. Taken from the screen, never from the card, which
        // is as tall as its contents.
        readonly property real listRoom: Math.max(Theme.scaled(120),
            (root.screen ? root.screen.height : 800) - root.barClearance - 36 - Theme.scaled(24)
            - titleRow.height - search.height - footer.height - column.spacing * 3
            - (suggestionBox.visible ? suggestionBox.height + column.spacing : 0))
        radius: Theme.popRadius
        color: Theme.panelSurface
        border.width: 1
        border.color: Theme.popBorder
        clip: true
        Accessible.role: Accessible.Dialog
        Accessible.name: I18n.tr("Dictation history")

        Behavior on opacity {
            NumberAnimation { duration: Theme.panelFadeDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation {
                duration: Theme.panelMotionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        FocusScope {
            anchors.fill: parent
            focus: root.shown
            Keys.onEscapePressed: {
                if (root.editing !== "")
                    root.editing = "";
                else
                    Dictation.closeHistory();
            }

            Column {
                id: column
                x: Theme.scaled(12)
                y: Theme.scaled(12)
                width: card.width - Theme.scaled(24)
                spacing: Theme.scaled(8)

                // ---- heading
                Item {
                    id: titleRow
                    width: parent.width
                    height: Theme.chipHeight

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.scaled(4)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.controlSpacing

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "history"
                            size: Theme.iconMedium
                            color: Theme.textMid
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Dictation history")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.title
                            font.weight: Theme.weightSemibold
                            color: Theme.textHi
                        }
                    }

                    SettingsUi.SettingsAction {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        compact: true
                        glyph: "close"
                        text: I18n.tr("Close")
                        onTriggered: Dictation.closeHistory()
                    }
                }

                SettingsUi.SettingsField {
                    id: search
                    width: parent.width
                    placeholderText: I18n.tr("Search dictations")
                    onTextChanged: root.query = text
                }

                // ---- a correction learned from edits
                Rectangle {
                    id: suggestionBox
                    readonly property var suggestion: Dictation.openSuggestions.length > 0 ? Dictation.openSuggestions[0] : null
                    visible: suggestion !== null
                    width: parent.width
                    height: suggestionRow.implicitHeight + Theme.scaled(16)
                    radius: Theme.chipRadius
                    color: Theme.chip
                    border.width: 1
                    border.color: Theme.stroke

                    Row {
                        id: suggestionRow
                        x: Theme.scaled(10)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.scaled(20)
                        spacing: Theme.controlSpacing

                        Sym {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "sparkles"
                            size: Theme.iconSmall
                            color: Theme.accentText
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSmall - addSuggestion.width - noSuggestion.width - Theme.controlSpacing * 3
                            wrapMode: Text.WordWrap
                            text: suggestionBox.suggestion
                                ? I18n.format(I18n.tr("You changed “%1” to “%2” %3 times. Always write it that way?"),
                                    [suggestionBox.suggestion.heard, suggestionBox.suggestion.write, suggestionBox.suggestion.count])
                                : ""
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            color: Theme.textHi
                        }

                        SettingsUi.SettingsAction {
                            id: addSuggestion
                            anchors.verticalCenter: parent.verticalCenter
                            primary: true
                            text: I18n.tr("Add")
                            onTriggered: Dictation.acceptSuggestion(suggestionBox.suggestion)
                        }

                        SettingsUi.SettingsAction {
                            id: noSuggestion
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("No")
                            onTriggered: Dictation.declineSuggestion(suggestionBox.suggestion)
                        }
                    }
                }

                // ---- the dictations
                Flickable {
                    id: list
                    width: parent.width
                    height: Math.min(entries.implicitHeight, card.listRoom)
                    contentHeight: entries.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                    Column {
                        id: entries
                        width: list.width

                        Text {
                            visible: root.rows.length === 0
                            width: parent.width
                            topPadding: Theme.scaled(18)
                            bottomPadding: Theme.scaled(18)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: !Dictation.historyLoaded ? I18n.tr("Loading…")
                                : root.query !== "" ? I18n.tr("No dictations match.")
                                : I18n.tr("No dictations yet. Press F9 to dictate.")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            color: Theme.textLow
                        }

                        Repeater {
                            model: root.rows

                            Item {
                                id: row
                                required property var modelData
                                readonly property bool heading: modelData.kind === "day"
                                readonly property var entry: modelData.entry || ({})
                                readonly property bool failed: entry.status === "failed"
                                readonly property bool editingThis: root.editing !== "" && root.editing === entry.id
                                width: entries.width
                                // From the parts, not the column's own height, which a
                                // repeated delegate's binding did not follow.
                                height: heading ? dayText.implicitHeight + Theme.scaled(14)
                                    : metaLine.height + entryColumn.spacing + Theme.scaled(16)
                                        + (editingThis ? editor.implicitHeight + entryColumn.spacing + editButtons.implicitHeight
                                            : bodyText.implicitHeight)

                                Text {
                                    id: dayText
                                    visible: row.heading
                                    x: Theme.scaled(4)
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Theme.scaled(4)
                                    text: row.modelData.label || ""
                                    font.family: Theme.fontMenu
                                    font.pixelSize: Theme.typography.metadata
                                    font.weight: Theme.weightSemibold
                                    color: Theme.textLow
                                }

                                Rectangle {
                                    visible: !row.heading
                                    anchors.fill: parent
                                    radius: Theme.chipRadius
                                    color: hover.hovered || row.editingThis ? Theme.hoverFill : "transparent"
                                }

                                HoverHandler {
                                    id: hover
                                    enabled: !row.heading
                                }

                                Column {
                                    id: entryColumn
                                    visible: !row.heading
                                    x: Theme.scaled(8)
                                    y: Theme.scaled(8)
                                    width: parent.width - Theme.scaled(16)
                                    spacing: Theme.scaled(4)

                                    Item {
                                        id: metaLine
                                        width: parent.width
                                        height: Math.max(meta.implicitHeight, Theme.chipHeight)

                                        Text {
                                            id: meta
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - (actions.visible ? actions.width + Theme.controlSpacing : 0)
                                            elide: Text.ElideRight
                                            textFormat: Text.StyledText
                                            text: {
                                                const parts = [root.timeLabel(row.entry.time || 0)];
                                                if (row.entry.app)
                                                    parts.push(row.entry.app);
                                                parts.push(I18n.format(I18n.tr("%1 words"), [row.entry.words || 0]));
                                                if ((row.entry.tidy === "basic" || row.entry.tidy === "polish")
                                                        && row.entry.original && row.entry.original !== row.entry.text)
                                                    parts.push(I18n.tr("tidied"));
                                                if (row.entry.edited)
                                                    parts.push(I18n.tr("edited"));
                                                let line = parts.join(" · ");
                                                if (row.failed)
                                                    line += " · <font color=\"" + Theme.redText + "\">" + I18n.tr("Not typed") + "</font>";
                                                else if (row.entry.status === "copied")
                                                    line += " · " + I18n.tr("copied");
                                                return line;
                                            }
                                            font.family: Theme.fontMenu
                                            font.pixelSize: Theme.typography.metadata
                                            color: Theme.textLow
                                        }

                                        Row {
                                            id: actions
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !row.editingThis && (hover.hovered || row.failed)
                                            spacing: 0

                                            SettingsUi.SettingsAction {
                                                compact: true
                                                glyph: row.failed ? "refresh" : "keyboard"
                                                text: row.failed ? I18n.tr("Type again") : I18n.tr("Type into the window below")
                                                onTriggered: Dictation.typeEntry(row.entry.id)
                                            }
                                            SettingsUi.SettingsAction {
                                                compact: true
                                                glyph: "copy"
                                                text: I18n.tr("Copy")
                                                onTriggered: Dictation.copyEntry(row.entry.id)
                                            }
                                            SettingsUi.SettingsAction {
                                                compact: true
                                                glyph: "pencil"
                                                text: I18n.tr("Correct")
                                                onTriggered: {
                                                    root.editing = row.entry.id;
                                                    editor.text = row.entry.text || "";
                                                    editor.forceActiveFocus();
                                                }
                                            }
                                            SettingsUi.SettingsAction {
                                                compact: true
                                                visible: row.entry.audio === true
                                                glyph: "player-play"
                                                text: I18n.tr("Play recording")
                                                onTriggered: Dictation.playEntry(row.entry.id)
                                            }
                                            SettingsUi.SettingsAction {
                                                compact: true
                                                visible: row.entry.audio === true
                                                glyph: "language"
                                                text: I18n.tr("Transcribe again with the current speech model")
                                                onTriggered: Dictation.retranscribeEntry(row.entry.id)
                                            }
                                            SettingsUi.SettingsAction {
                                                compact: true
                                                glyph: "trash"
                                                text: I18n.tr("Delete")
                                                onTriggered: Dictation.deleteEntry(row.entry.id)
                                            }
                                        }
                                    }

                                    Text {
                                        id: bodyText
                                        visible: !row.editingThis
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: hover.hovered ? 6 : 2
                                        elide: Text.ElideRight
                                        text: row.entry.text || ""
                                        font.family: Theme.fontMenu
                                        font.pixelSize: Theme.typography.secondary
                                        color: Theme.textHi
                                    }

                                    Controls.TextArea {
                                        id: editor
                                        visible: row.editingThis
                                        width: parent.width
                                        wrapMode: TextEdit.Wrap
                                        font.family: Theme.fontMenu
                                        font.pixelSize: Theme.typography.secondary
                                        color: Theme.textHi
                                        selectionColor: Theme.accentBg
                                        selectedTextColor: Theme.textHi
                                        Accessible.name: I18n.tr("Correct the dictation")
                                        background: Rectangle {
                                            radius: Theme.chipRadius
                                            color: Theme.cardFill
                                            border.width: 1
                                            border.color: Theme.accentText
                                        }
                                        Keys.onReturnPressed: event => {
                                            if (event.modifiers & Qt.ShiftModifier) {
                                                event.accepted = false;
                                                return;
                                            }
                                            Dictation.editEntry(row.entry.id, editor.text);
                                            root.editing = "";
                                        }
                                    }

                                    Row {
                                        id: editButtons
                                        visible: row.editingThis
                                        spacing: Theme.controlSpacing

                                        SettingsUi.SettingsAction {
                                            primary: true
                                            text: I18n.tr("Save")
                                            onTriggered: {
                                                Dictation.editEntry(row.entry.id, editor.text);
                                                root.editing = "";
                                            }
                                        }
                                        SettingsUi.SettingsAction {
                                            text: I18n.tr("Cancel")
                                            onTriggered: root.editing = ""
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Corrections you repeat become suggestions.")
                                            font.family: Theme.fontMenu
                                            font.pixelSize: Theme.typography.metadata
                                            color: Theme.textLow
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- retention and the way to Settings
                Item {
                    id: footer
                    width: parent.width
                    height: Theme.chipHeight

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.scaled(4)
                        anchors.right: footerActions.left
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: Dictation.weekWords > 0
                            ? I18n.format(I18n.tr("%1 · %2 words this week"), [root.retentionText, Dictation.weekWords])
                            : root.retentionText
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        color: Theme.textLow
                    }

                    Row {
                        id: footerActions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter

                        SettingsUi.SettingsAction {
                            visible: Dictation.historyEntries.length > 0
                            danger: root.confirmClear === "yes"
                            text: root.confirmClear === "yes" ? I18n.tr("Clear all?") : I18n.tr("Clear")
                            onTriggered: {
                                if (root.confirmClear === "yes") {
                                    Dictation.clearHistory();
                                    root.confirmClear = "";
                                } else {
                                    root.confirmClear = "yes";
                                    clearReset.restart();
                                }
                            }
                        }
                        SettingsUi.SettingsAction {
                            text: I18n.tr("Settings")
                            onTriggered: {
                                Dictation.closeHistory();
                                Dictation.openSettings();
                            }
                        }
                    }

                    Timer {
                        id: clearReset
                        interval: 4000
                        onTriggered: root.confirmClear = ""
                    }
                }
            }
        }
    }
}
