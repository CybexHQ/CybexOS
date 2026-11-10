pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../Common"
import "../Common/ShortcutEditor.js" as Helpers

// The Super+letter and Super+digit keys, drawn as a keyboard, each with the
// action it runs. Used by Settings → Keyboard → Shortcuts; the welcome guide
// draws the same model and the same meanings in installer keycaps
// (Welcome/KioskKeyMap.qml).
//
// One meaning in both maps (2026-11 council review, where Settings lit its
// free keys and the guide its bound ones): a key in use is lit and names its
// action; a free key is plain, with a dashed outline; a protected key carries
// a lock and a key held twice an amber edge and a warning mark. Colour is
// never the only cue. An action name that does not fit on its key whole
// shows its group's icon instead of an elided word; the key's tip, its
// accessible name and the detail under the map always name it in full.
//
// Choosing a bound key asks to edit its action; choosing a free key offers
// to make it open an app, a website, a web app or a command. The detail area
// below the legend is always there, so the page does not jump as keys are
// chosen. One key is a tab stop; the arrows move between keys (roving
// focus) and the detail follows them.
Column {
    id: root

    property var actions: Keybindings.actions
    property var userBinds: Keybindings.userBinds
    // While keybindings.json is rejected the map only shows what is bound.
    property bool readOnly: Keybindings.readOnly
    readonly property var map: Helpers.keyboardMap(actions, userBinds)
    readonly property var allKeys: [].concat.apply([], map)
    // The key whose details show under the map, by combination.
    property string selected: ""
    property int focusRow: 1
    property int focusColumn: 0
    readonly property var selectedKey: allKeys.find(key => key.combo === selected) || null
    readonly property real unit: Math.floor((width - Theme.scaled(3) * 9) / 10.5)
    readonly property real keyHeight: Math.min(Theme.scaled(64), Math.max(Theme.scaled(48), unit * 0.92))
    readonly property var offsets: [0, 0.5, 0.75, 1.25]
    signal editRequested(string id)
    signal addRequested(string combo, string type)

    spacing: Theme.settingsContentSpacing

    component KeyRow: Row {
        property Repeater keys: null
        function keyAt(column: int): Item { return keys ? keys.itemAt(column) : null; }
    }

    // A free key's outline: dashed, so it reads apart from a lit key
    // without relying on colour.
    component DashedOutline: Shape {
        id: outline
        property color stroke: Theme.textFaint
        property real cornerRadius: Theme.scaled(6)
        ShapePath {
            strokeColor: outline.stroke
            strokeWidth: 1
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

    // One legend entry: a small key drawn the way the map draws that state,
    // and its name. The guide's map uses the same words.
    component Legend: Row {
        id: legend
        // "used", "free", "protected", "shared" or "user".
        property string kind: "used"
        property string text
        // The mark a protected or twice-held key carries.
        readonly property string mark: kind === "shared" ? "warning" : kind === "protected" ? "lock" : ""
        spacing: Theme.iconTextSpacing
        Rectangle {
            id: swatch
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSmall + Theme.scaled(6)
            height: width
            radius: Theme.scaled(3)
            color: legend.kind === "free" ? "transparent" : Theme.accentAlpha(0.16)
            border.width: legend.kind === "free" ? 0 : 1
            border.color: legend.kind === "shared" ? Theme.amber : Theme.accentAlpha(0.55)
            DashedOutline {
                anchors.fill: parent
                visible: legend.kind === "free"
                cornerRadius: swatch.radius
            }
            Sym {
                anchors.centerIn: parent
                visible: legend.mark !== ""
                name: legend.mark
                size: Theme.iconSmall - Theme.scaled(2)
                color: legend.kind === "shared" ? Theme.amber : Theme.textFaint
            }
            Text {
                anchors.centerIn: parent
                visible: legend.kind === "user"
                text: "Aa" // i18n: untranslated (type sample)
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                font.italic: true
                color: Theme.textMid
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: legend.text
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            color: Theme.textFaint
        }
    }

    function label(owner) {
        if (!owner)
            return "";
        const workspace = Helpers.workspaceNumber(owner.label);
        return workspace ? I18n.format("Workspace %1", [workspace]) : I18n.actionLabel(owner.label);
    }
    function describe(key) {
        if (key.free)
            return I18n.tr("Free");
        if (key.reservedBy)
            return I18n.format("Kept for %1", [I18n.actionLabel(key.reservedBy.label)]);
        let text = label(key.owner);
        if (key.shared)
            text = I18n.format("%1 and %2 more", [text, key.owners.length - 1]);
        if (key.owner.source === "user")
            text = I18n.format("%1 (hand-written)", [text]);
        return text;
    }
    function activate(key) {
        selected = key.combo;
        if (!readOnly && key.owner && key.owner.editable && !key.shared)
            editRequested(key.owner.id);
    }
    function focusKey(row, column) {
        const target = Helpers.mapMove(map, row, column, "");
        // Focus first: the current key is the tab stop (see PillRow).
        const line = keyRows.itemAt(target.row) as KeyRow;
        const item = line ? line.keyAt(target.column) : null;
        if (item)
            item.forceActiveFocus();
        focusRow = target.row;
        focusColumn = target.column;
        // The detail follows the keyboard, so every key's full name can be
        // read without choosing it.
        const key = map[target.row] ? map[target.row][target.column] : null;
        if (key)
            selected = key.combo;
    }

    Column {
        width: parent.width
        spacing: Theme.scaled(3)

        Repeater {
            id: keyRows
            model: root.map

            delegate: KeyRow {
                id: line
                required property var modelData
                required property int index
                x: Math.round(root.offsets[index] * (root.unit + spacing))
                spacing: Theme.scaled(3)

                Repeater {
                    id: keyRepeater
                    model: line.modelData
                    Component.onCompleted: line.keys = keyRepeater

                    delegate: Rectangle {
                        id: keyCap
                        required property var modelData
                        readonly property bool current: root.focusRow === modelData.row && root.focusColumn === modelData.column
                        readonly property bool chosen: root.selected === modelData.combo
                        readonly property bool user: !!modelData.owner && modelData.owner.source === "user"
                        // Lit: the key does something while Super is held.
                        readonly property bool lit: !modelData.free
                        readonly property string group: modelData.owner ? modelData.owner.group
                            : modelData.reservedBy ? modelData.reservedBy.group : ""
                        width: root.unit
                        height: root.keyHeight
                        radius: Theme.scaled(6)
                        color: lit ? Theme.accentAlpha(chosen ? 0.28 : 0.16)
                            : chosen ? Theme.chipHover : "transparent"
                        // A free key's edge is the dashed outline below until it
                        // is chosen; a chosen key takes a 2 px edge in its ink.
                        border.width: chosen ? 2 : lit ? 1 : 0
                        border.color: modelData.shared ? Theme.amber
                            : lit ? (chosen ? Theme.accentText : Theme.accentAlpha(0.55))
                            : Theme.textMid
                        activeFocusOnTab: current
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.format("Super+%1: %2", [modelData.key, root.describe(modelData)])
                        Accessible.description: modelData.protected ? I18n.tr("A protected shortcut always keeps this key.") : ""
                        Accessible.onPressAction: root.activate(modelData)

                        Keys.onPressed: event => {
                            const move = { [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up",
                                [Qt.Key_Down]: "down", [Qt.Key_Home]: "home", [Qt.Key_End]: "end" }[event.key];
                            if (move) {
                                const next = Helpers.mapMove(root.map, modelData.row, modelData.column, move);
                                root.focusKey(next.row, next.column);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                keyState.pulseCenter();
                                root.activate(modelData);
                                event.accepted = true;
                            }
                        }

                        DashedOutline {
                            anchors.fill: parent
                            visible: !keyCap.lit && !keyCap.chosen
                            cornerRadius: keyCap.radius
                        }

                        StateLayer {
                            id: keyState
                            anchors.fill: parent
                            radius: parent.radius
                            hovered: keyMouse.containsMouse
                            pressed: keyMouse.pressed
                            tint: keyCap.lit ? Theme.accent : Theme.textHi
                            pressPoint: Qt.point(keyMouse.mouseX, keyMouse.mouseY)
                        }

                        // The keyboard ring, apart from the chosen key's edge.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: Theme.focusWidth(keyCap.activeFocus)
                            border.color: Theme.focusRing
                        }

                        Text {
                            x: Theme.scaled(6)
                            y: Theme.scaled(4)
                            text: keyCap.modelData.key
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.typography.control
                            font.weight: Theme.weightBold
                            color: keyCap.lit ? Theme.accentText : Theme.textFaint
                        }
                        // Protected before held twice: a lock says more about
                        // what you can do with the key.
                        Sym {
                            visible: keyCap.modelData.protected || keyCap.modelData.shared
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.scaled(4)
                            y: Theme.scaled(5)
                            name: keyCap.modelData.protected ? "lock" : "warning"
                            size: Theme.iconSmall
                            color: keyCap.modelData.protected ? Theme.textFaint : Theme.amber
                        }
                        // Two lines at word boundaries. A name that does not
                        // fit whole (a word wider than the key, a third line)
                        // gives way to its group's icon rather than an elided
                        // "Worksp…"; the tip and the detail name it in full.
                        TextMetrics {
                            id: longestWord
                            font: keyLabel.font
                            text: keyLabel.text.split(/\s+/).reduce((longest, word) => word.length > longest.length ? word : longest, "")
                        }
                        Text {
                            id: keyLabel
                            x: Theme.scaled(5)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.scaled(3)
                            width: parent.width - Theme.scaled(8)
                            visible: keyCap.lit
                            // Laid out even when it gives way, so `truncated`
                            // keeps answering.
                            opacity: truncated ? 0 : 1
                            text: keyCap.modelData.reservedBy ? I18n.actionLabel(keyCap.modelData.reservedBy.label)
                                : root.label(keyCap.modelData.owner)
                            wrapMode: longestWord.advanceWidth <= width ? Text.WordWrap : Text.NoWrap
                            maximumLineCount: wrapMode === Text.NoWrap ? 1 : 2
                            elide: Text.ElideRight
                            lineHeight: 0.9
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.metadata
                            font.italic: keyCap.user
                            color: keyCap.modelData.reservedBy || keyCap.user ? Theme.textFaint : Theme.textMid
                        }
                        Sym {
                            visible: keyCap.lit && keyLabel.truncated
                            x: Theme.scaled(5)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.scaled(5)
                            name: Helpers.groupGlyph(keyCap.group)
                            size: Theme.iconSmall
                            color: Theme.textMid
                        }

                        MouseArea {
                            id: keyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.focusKey(keyCap.modelData.row, keyCap.modelData.column);
                                root.activate(keyCap.modelData);
                            }
                        }
                        // The full name under the pointer; made only while
                        // hovered, so forty keys do not each hold a popup.
                        Loader {
                            anchors.fill: parent
                            active: keyMouse.containsMouse
                            sourceComponent: SettingsTooltip {
                                visible: true
                                text: I18n.format("Super+%1: %2", [keyCap.modelData.key, root.describe(keyCap.modelData)])
                            }
                        }
                    }
                }
            }
        }
    }

    // The legend, in the guide's words: only the states the map shows.
    Flow {
        width: parent.width
        spacing: Theme.panelSectionSpacing

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

    // What the chosen key does, in full. Always present and never shorter
    // than a key's name and one row of actions, so choosing keys does not
    // move the page.
    Rectangle {
        id: detail
        objectName: "shortcutMapDetail"
        width: parent.width
        height: Math.max(detailBody.implicitHeight, Theme.settingsControlHeight * 2 + Theme.iconTextSpacing)
            + Theme.controlSpacing * 2
        radius: Theme.chipRadius
        color: Theme.cardFill
        border.width: 1
        border.color: Theme.hairlineSoft

        Column {
            id: detailBody
            x: Theme.controlSpacing
            y: Theme.controlSpacing
            width: parent.width - Theme.controlSpacing * 2
            spacing: Theme.iconTextSpacing

            Text {
                width: parent.width
                visible: root.selectedKey === null
                wrapMode: Text.Wrap
                text: I18n.tr("Choose a key to see what it does.")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.control
                color: Theme.textFaint
            }
            Row {
                visible: root.selectedKey !== null
                width: parent.width
                spacing: Theme.controlSpacing
                ShortcutKeycaps {
                    id: detailCaps
                    keys: root.selectedKey ? [root.selectedKey.combo] : []
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - detailCaps.width - parent.spacing)
                    wrapMode: Text.Wrap
                    text: !root.selectedKey ? ""
                        : root.selectedKey.free ? (root.readOnly ? I18n.tr("This key is free.") : I18n.tr("This key is free. Make it open:"))
                        : root.describe(root.selectedKey)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    font.weight: Theme.weightMedium
                    color: Theme.textHi
                }
            }
            Text {
                width: parent.width
                visible: text !== ""
                wrapMode: Text.Wrap
                text: !root.selectedKey ? ""
                    : root.readOnly ? I18n.tr("Shortcuts cannot be changed until keybindings.json is reset.")
                    : root.selectedKey.free ? ""
                    : root.selectedKey.reservedBy ? I18n.tr("A protected shortcut always keeps this key.")
                    : root.selectedKey.protected ? I18n.format("%1 always keeps this key. You can give it other keys as well.",
                        [root.label(root.selectedKey.owner)])
                    : root.selectedKey.owner.source === "user" ? I18n.tr("Set in ~/.config/cybexos/hypr/user.lua. Change it there.")
                    : root.selectedKey.shared ? root.selectedKey.owners.map(owner => root.label(owner)).join(", ")
                    : !root.selectedKey.owner.editable ? I18n.tr("This shortcut cannot be changed here.")
                    : I18n.actionLabel(root.selectedKey.owner.group)
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
            }
            Flow {
                width: parent.width
                spacing: Theme.iconTextSpacing
                visible: root.selectedKey !== null && root.selectedKey.free && !root.readOnly

                Repeater {
                    model: [{ type: "app", label: I18n.tr("An app"), glyph: "apps" },
                        { type: "url", label: I18n.tr("A website"), glyph: "language" },
                        { type: "webapp", label: I18n.tr("A web app"), glyph: "web" },
                        { type: "command", label: I18n.tr("A command"), glyph: "terminal" }]
                    delegate: SettingsAction {
                        required property var modelData
                        text: modelData.label
                        glyph: modelData.glyph
                        onTriggered: root.addRequested(root.selected, modelData.type)
                    }
                }
            }
            Flow {
                width: parent.width
                spacing: Theme.iconTextSpacing
                visible: root.selectedKey !== null && root.selectedKey.shared && !root.readOnly

                Repeater {
                    model: root.selectedKey && root.selectedKey.shared
                        ? root.selectedKey.owners.filter(owner => owner.editable) : []
                    delegate: SettingsAction {
                        required property var modelData
                        text: I18n.format("Edit %1", [I18n.actionLabel(modelData.label)])
                        glyph: "edit"
                        onTriggered: root.editRequested(modelData.id)
                    }
                }
            }
        }
    }
}
