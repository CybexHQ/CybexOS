import QtQuick
import "../Common"

// One item under Home's "Needs attention" (2026-11): what needs the person,
// a status pill saying where it stands, and the one action that settles it.
// It keeps a settings row's lanes — the mark gutter, the label lane, the
// controls ending on the page's one right-hand edge, the reset column kept
// clear, the explanation on the hint line below — but it reflows instead of
// eliding: a narrow column (below ~560 px, `compactWidth`) or a title too
// long to share its line moves the pill and the action onto a line of their
// own under the title, and the title wraps.
Item {
    id: root

    default property alias actions: actionRow.data
    property string title: ""
    property string detail: ""
    property string status: ""
    // info | ok | amber | red | neutral, as StatusPill.
    property string tone: "info"
    property bool divider: true
    property real compactWidth: Theme.scaled(560, Theme.typeScale)

    readonly property int markInset: Theme.settingsMarkInset
    readonly property int undoWidth: Theme.chipHeight
    readonly property real contentRight: width - undoWidth
    readonly property real actionsWidth: actionRow.implicitWidth
    readonly property real controlsWidth: (pill.visible ? pill.width : 0)
        + (pill.visible && actionsWidth > 0 ? Theme.controlSpacing : 0) + actionsWidth
    // The title's room beside the controls, and what it would need there.
    readonly property real wideTitleRoom: contentRight - markInset - controlsWidth - Theme.controlSpacing
    readonly property bool stacked: width < compactWidth || titleMetrics.advanceWidth > wideTitleRoom
    // Pill and action share the stacked line unless even that is too short.
    readonly property bool actionsBelowPill: stacked && pill.visible && actionsWidth > 0
        && pill.width + Theme.controlSpacing + actionsWidth > contentRight - markInset
    readonly property bool narrow: width < Theme.settingsNarrowWidth

    readonly property int rowPad: stacked ? Theme.scaled(5) : Theme.scaled(7)
    readonly property int hintGap: Theme.scaled(5)
    readonly property real controlLine: Theme.settingsControlHeight
    // SettingsPage.revealFocus brings a row in whole when it finds these.
    readonly property string hintTone: "info"
    readonly property real wideLine: Theme.panelRowHeight + rowPad * 2
    readonly property real lineHeight: stacked
        ? controlsTop + controlLine * (actionsBelowPill ? 2 : 1) + Theme.scaled(2)
        : wideLine
    readonly property real controlsTop: stacked
        ? rowPad + titleText.height + Theme.scaled(6) : 0

    height: lineHeight + (hintLine.visible ? hintLine.height + hintGap + Theme.scaled(2) : 0)
        + (stacked ? rowPad : 0)

    TextMetrics {
        id: titleMetrics
        font: titleText.font
        text: root.title
    }

    // Between two items, as between two settings rows.
    Rectangle {
        visible: root.divider && root.y > 0 && !root.narrow
        x: root.markInset
        y: -Math.ceil(Theme.settingsRowSpacing / 2) - 1
        width: Math.max(0, root.width - root.markInset)
        height: 1
        color: Theme.hairlineSoft
    }

    Text {
        id: titleText
        x: root.markInset
        y: root.stacked ? root.rowPad : (root.wideLine - height) / 2
        width: root.stacked ? Math.max(0, root.contentRight - root.markInset)
            : Math.max(0, root.wideTitleRoom)
        text: root.title
        wrapMode: root.stacked ? Text.Wrap : Text.NoWrap
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.control
        color: Theme.textHi
    }

    StatusPill {
        id: pill
        text: root.status
        tone: root.tone
        x: root.stacked ? root.markInset : actionRow.x - (actionRow.width > 0 ? Theme.controlSpacing : 0) - width
        y: root.stacked ? root.controlsTop + (root.controlLine - height) / 2
            : (root.wideLine - height) / 2
    }

    Row {
        id: actionRow
        x: root.contentRight - width
        y: (root.actionsBelowPill ? root.controlsTop + root.controlLine
                : root.stacked ? root.controlsTop : 0)
            + ((root.stacked ? root.controlLine : root.wideLine) - height) / 2
        spacing: Theme.iconTextSpacing
    }

    SettingsHint {
        id: hintLine
        y: root.lineHeight - (root.stacked ? 0 : root.rowPad) + root.hintGap
        width: root.contentRight
        text: root.detail
    }
}
