pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../Common"
import "../Common/ShortcutEditor.js" as Helpers

// The Super+digit and Super+letter keys as a keyboard, in installer keycaps,
// from the same model as Settings → Keyboard → Shortcuts (ShortcutEditor.js)
// and with the same meanings and legend words as its map
// (Settings/ShortcutKeyboardMap.qml): a key in use is lit and names its
// action; a free key is plain, with a dashed outline; a protected key
// carries a lock and a key held twice an amber edge and a warning mark. A
// name that does not fit on its key whole shows its group's icon instead of
// an elided word. One key is a tab stop and the arrows move between keys.
Column {
    id: root
    property var map: Helpers.keyboardMap(Keybindings.actions, Keybindings.userBinds)
    readonly property var allKeys: [].concat.apply([], map)
    property string selected: ""
    property int focusRow: 1
    property int focusColumn: 0
    readonly property var selectedKey: allKeys.find(key => key.combo === selected) || null
    readonly property real gap: Kiosk.px(6)
    readonly property real unit: Math.floor((width - gap * 9) / 10.5)
    readonly property var offsets: [0, 0.5, 0.75, 1.25]
    readonly property int used: allKeys.filter(key => !key.free).length
    signal activated(var key)
    spacing: gap

    component KeyRow: Row {
        property Repeater keys: null
        function keyAt(column: int): Item { return keys ? keys.itemAt(column) : null; }
    }

    // A free key's outline: dashed, so it reads apart from a lit key
    // without relying on colour.
    component DashedOutline: Shape {
        id: outline
        property color stroke: Kiosk.faint
        property real cornerRadius: Kiosk.px(8)
        ShapePath {
            strokeColor: outline.stroke
            strokeWidth: Math.max(1, Kiosk.px(1))
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 3]
            fillColor: "transparent"
            PathRectangle {
                x: 0.5
                y: 0.5
                width: Math.max(0, outline.width - 1)
                height: Math.max(0, outline.height - 1)
                radius: outline.cornerRadius
            }
        }
    }

    // One legend entry, in Settings' words: a small key drawn the way the
    // map draws that state, and its name.
    component Legend: Row {
        id: legend
        // "used", "free", "protected", "shared" or "user".
        property string kind: "used"
        property string text
        // The mark a protected or twice-held key carries.
        readonly property string mark: kind === "shared" ? "warning" : kind === "protected" ? "lock" : ""
        spacing: Kiosk.px(7)
        Rectangle {
            id: swatch
            anchors.verticalCenter: parent.verticalCenter
            width: Kiosk.px(18)
            height: width
            radius: Kiosk.px(4)
            color: legend.kind === "free" ? "transparent" : Kiosk.accentSoft
            border.width: legend.kind === "free" ? 0 : Math.max(1, Kiosk.px(1))
            border.color: legend.kind === "shared" ? Kiosk.amber : Kiosk.accentLine
            DashedOutline {
                anchors.fill: parent
                visible: legend.kind === "free"
                cornerRadius: swatch.radius
            }
            KioskIcon {
                anchors.centerIn: parent
                visible: legend.mark !== ""
                name: legend.mark
                designSize: 11
                color: legend.kind === "shared" ? Kiosk.amber : Kiosk.faint
            }
            KioskText {
                anchors.centerIn: parent
                visible: legend.kind === "user"
                text: "Aa" // i18n: untranslated (type sample)
                size: 10
                font.italic: true
                tone: "fog"
            }
        }
        KioskText {
            anchors.verticalCenter: parent.verticalCenter
            text: legend.text
            size: 12.5
            tone: "fog"
        }
    }

    function label(owner) {
        if (!owner)
            return "";
        const workspace = Helpers.workspaceNumber(owner.label);
        return workspace ? I18n.format("Workspace %1", [workspace]) : I18n.actionLabel(owner.label);
    }
    function choose(key) {
        selected = key.combo;
        activated(key);
    }
    function focusKey(row, column) {
        const target = Helpers.mapMove(map, row, column, "");
        const line = rows.itemAt(target.row) as KeyRow;
        const item = line ? line.keyAt(target.column) : null;
        if (item)
            item.forceActiveFocus();
        focusRow = target.row;
        focusColumn = target.column;
    }

    Repeater {
        id: rows
        model: root.map
        delegate: KeyRow {
            id: line
            required property var modelData
            required property int index
            x: Math.round(root.offsets[index] * (root.unit + root.gap))
            spacing: root.gap
            Repeater {
                id: keyRepeater
                model: line.modelData
                Component.onCompleted: line.keys = keyRepeater
                delegate: Rectangle {
                    id: cap
                    required property var modelData
                    readonly property bool lit: !modelData.free
                    readonly property bool chosen: root.selected === modelData.combo
                    readonly property bool current: root.focusRow === modelData.row && root.focusColumn === modelData.column
                    readonly property bool user: !!modelData.owner && modelData.owner.source === "user"
                    readonly property string group: modelData.owner ? modelData.owner.group
                        : modelData.reservedBy ? modelData.reservedBy.group : ""
                    width: root.unit
                    height: Kiosk.px(52)
                    radius: Kiosk.px(8)
                    color: chosen ? Kiosk.accent : lit ? Kiosk.accentSoft : Kiosk.bgDeep
                    // A free key's edge is the dashed outline below, until it
                    // is hovered or chosen.
                    border.width: lit || chosen || keyMouse.containsMouse ? Math.max(1, Kiosk.px(1)) : 0
                    border.color: chosen ? Kiosk.accent : modelData.shared ? Kiosk.amber
                        : lit ? (keyMouse.containsMouse ? Kiosk.accent : Kiosk.accentLine) : Kiosk.line2
                    activeFocusOnTab: current
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.format("Super+%1: %2", [modelData.key,
                        modelData.free ? I18n.tr("Free") : modelData.reservedBy ? I18n.actionLabel(modelData.reservedBy.label) : root.label(modelData.owner)])
                    Accessible.onPressAction: root.choose(modelData)
                    Keys.onPressed: event => {
                        const move = {[Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up",
                            [Qt.Key_Down]: "down", [Qt.Key_Home]: "home", [Qt.Key_End]: "end"}[event.key];
                        if (move) {
                            const next = Helpers.mapMove(root.map, cap.modelData.row, cap.modelData.column, move);
                            root.focusKey(next.row, next.column);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (!event.isAutoRepeat) root.choose(cap.modelData);
                            event.accepted = true;
                        }
                    }
                    DashedOutline {
                        anchors.fill: parent
                        visible: !cap.lit && !cap.chosen && !keyMouse.containsMouse
                        cornerRadius: cap.radius
                    }
                    // The lower edge of a physical key.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Math.max(1, Kiosk.px(1))
                        height: Kiosk.px(2)
                        radius: Kiosk.px(1)
                        color: cap.chosen ? "transparent" : Qt.rgba(1, 1, 1, 0.04)
                    }
                    KioskFocusRing { visible: cap.activeFocus; gap: 3; baseRadius: cap.radius }
                    KioskText {
                        x: Kiosk.px(7)
                        y: Kiosk.px(5)
                        text: cap.modelData.key
                        mono: true
                        size: 13
                        font.weight: Font.Bold
                        tone: cap.chosen ? "onAccent" : cap.lit ? "accent" : "faint"
                    }
                    // Protected before held twice: a lock says more about
                    // what you can do with the key.
                    KioskIcon {
                        visible: cap.modelData.protected || cap.modelData.shared
                        anchors.right: parent.right
                        anchors.rightMargin: Kiosk.px(5)
                        y: Kiosk.px(6)
                        name: cap.modelData.protected ? "lock" : "warning"
                        designSize: 11
                        color: cap.chosen ? Kiosk.accentInk : cap.modelData.protected ? Kiosk.faint : Kiosk.amber
                    }
                    // Two lines at word boundaries, or the group's icon when
                    // the name does not fit whole.
                    TextMetrics {
                        id: longestWord
                        font: keyLabel.font
                        text: keyLabel.text.split(/\s+/).reduce((longest, word) => word.length > longest.length ? word : longest, "")
                    }
                    KioskText {
                        id: keyLabel
                        x: Kiosk.px(6)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Kiosk.px(5)
                        width: parent.width - Kiosk.px(10)
                        visible: cap.lit
                        // Laid out even when it gives way, so `truncated`
                        // keeps answering.
                        opacity: truncated ? 0 : 1
                        text: cap.modelData.reservedBy ? I18n.actionLabel(cap.modelData.reservedBy.label) : root.label(cap.modelData.owner)
                        size: 9.5
                        font.italic: cap.user
                        tone: cap.chosen ? "onAccent" : "fog"
                        wrapMode: longestWord.advanceWidth <= width ? Text.WordWrap : Text.NoWrap
                        maximumLineCount: wrapMode === Text.NoWrap ? 1 : 2
                        elide: Text.ElideRight
                        lineHeight: 0.9
                    }
                    KioskIcon {
                        visible: cap.lit && keyLabel.truncated
                        x: Kiosk.px(6)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Kiosk.px(6)
                        name: Helpers.groupGlyph(cap.group)
                        designSize: 13
                        color: cap.chosen ? Kiosk.accentInk : Kiosk.fog
                    }
                    MouseArea {
                        id: keyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.focusKey(cap.modelData.row, cap.modelData.column);
                            root.choose(cap.modelData);
                        }
                    }
                }
            }
        }
    }

    // The legend, in Settings' words: only the states the map shows.
    Flow {
        width: parent.width
        topPadding: Kiosk.px(6)
        spacing: Kiosk.px(18)

        Legend { kind: "used"; text: I18n.tr("In use") }
        Legend { kind: "free"; text: I18n.tr("Free") }
        Legend {
            kind: "protected"
            visible: root.allKeys.some(key => key.protected)
            text: I18n.tr("Protected")
        }
        Legend {
            kind: "shared"
            visible: root.allKeys.some(key => key.shared)
            text: I18n.tr("Used more than once")
        }
        Legend {
            kind: "user"
            visible: root.allKeys.some(key => key.owners.some(owner => owner.source === "user"))
            text: I18n.tr("Italic: hand-written")
        }
    }
}
