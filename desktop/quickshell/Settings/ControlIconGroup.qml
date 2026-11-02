pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../Common"
import "../Common/ControlIconHelpers.js" as ControlIconHelpers
import "../Bar" as BarUi

// Settings -> Bar & Control Center -> Control Center -> Button icon: the
// Control Center button's icon on the bar, which the fish prompt shows too
// (Common/ControlIconHelpers.js). Three choices: the Cybex OS mark, the
// operating system's logo, or any Nerd Font icon, searched by name in the
// catalogue that ships with the shell (assets/nerd-icons). A preview shows
// the bar button and the prompt as they will look.
SettingsGroup {
    id: root

    objectName: "controlIconGroup"
    title: I18n.tr("Button icon")

    readonly property var icon: ControlIconHelpers.parse(Settings.controlIcon)
    // The search opens with the custom tile and stays open while a custom
    // icon is chosen.
    property bool picking: false
    readonly property bool pickerShown: picking || icon.mode === "custom"
    property var catalogue: ({})
    property bool catalogueLoaded: false
    property string query: ""
    readonly property var results: catalogueLoaded
        ? ControlIconHelpers.search(catalogue, query, 72) : []

    readonly property int tileGap: Theme.scaled(10)
    readonly property real tileWidth: (width - tileGap * 2) / 3
    readonly property int swatch: Theme.scaled(44)

    function choose(value) {
        Settings.set("controlIcon", value);
    }

    // Read only once the search is first shown: 11,000 names the bar never needs.
    FileView {
        path: root.pickerShown ? Quickshell.shellDir + "/assets/nerd-icons/glyphs.json" : ""
        printErrors: false
        onLoaded: {
            try {
                root.catalogue = JSON.parse(text()).glyphs || ({});
                root.catalogueLoaded = true;
            } catch (e) {
                console.warn("the Nerd Font icon catalogue is invalid:", e);
            }
        }
    }

    SettingsHint {
        width: parent.width
        text: I18n.tr("Shown on the bar and in the terminal prompt.")
    }

    // ---- the three choices ------------------------------------------------
    Item {
        width: parent.width
        height: choices.height

        Row {
            id: choices
            spacing: root.tileGap

            Repeater {
                model: [
                    { mode: "cybex", value: "cybex", label: I18n.tr("Cybex OS"), detail: I18n.tr("Default") },
                    { mode: "os", value: "os", label: I18n.tr("Operating system"), detail: "NixOS" },
                    { mode: "custom", value: "", label: I18n.tr("Custom icon"),
                        detail: root.icon.mode === "custom" ? ControlIconHelpers.title(root.icon.name)
                            : I18n.tr("Pick any icon") }
                ]

                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property bool selected: root.icon.mode === modelData.mode
                    objectName: "controlIconChoice-" + modelData.mode
                    width: root.tileWidth
                    height: root.swatch + Theme.scaled(26) + labels.height
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.label + ", " + modelData.detail
                    Accessible.checked: selected
                    Accessible.onPressAction: activate()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            tile.activate();
                            event.accepted = true;
                        }
                    }

                    function activate() {
                        if (modelData.mode === "custom") {
                            root.picking = true;
                            Qt.callLater(() => search.forceActiveFocus());
                        } else {
                            root.picking = false;
                            root.choose(modelData.value);
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.chipRadius + 3
                        color: tile.selected ? Theme.chip : Theme.cardFill
                        border.width: tile.selected ? 2 : 1
                        border.color: tile.selected ? Theme.accent
                            : tile.activeFocus ? Theme.accentText : Theme.hairline

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            hovered: tileMouse.containsMouse
                            pressed: tileMouse.pressed
                            focused: tile.activeFocus
                            tint: Theme.textHi
                            pressPoint: Qt.point(tileMouse.mouseX, tileMouse.mouseY)
                        }
                    }

                    Rectangle {
                        id: swatchBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Theme.scaled(12)
                        width: root.swatch
                        height: root.swatch
                        radius: Theme.chipRadius + 1
                        color: Theme.barSurface

                        BarUi.ControlIconGlyph {
                            anchors.centerIn: parent
                            visible: tile.modelData.mode !== "custom" || root.icon.mode === "custom"
                            width: Theme.scaled(22)
                            height: width
                            value: tile.modelData.mode === "custom" ? Settings.controlIcon
                                : tile.modelData.value
                            highlighted: tile.selected
                        }
                        Sym {
                            anchors.centerIn: parent
                            visible: tile.modelData.mode === "custom" && root.icon.mode !== "custom"
                            name: "search"
                            size: Theme.iconMedium
                            color: Theme.barIcon
                        }
                    }

                    Column {
                        id: labels
                        anchors.top: swatchBox.bottom
                        anchors.topMargin: Theme.scaled(8)
                        width: parent.width
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.label
                            elide: Text.ElideRight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            font.weight: tile.selected ? Theme.weightSemibold : Theme.weightMedium
                            color: Theme.textHi
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.detail
                            elide: Text.ElideRight
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.caption
                            color: Theme.textLow
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            tile.forceActiveFocus();
                            tile.activate();
                        }
                    }
                }
            }
        }
    }

    // ---- any icon -----------------------------------------------------------
    Column {
        id: picker
        objectName: "controlIconPicker"
        visible: root.pickerShown
        width: parent.width
        spacing: Theme.scaled(8)

        SettingsField {
            id: search
            objectName: "controlIconSearch"
            width: parent.width
            placeholderText: I18n.tr("Search icons: terminal, rocket, cat…")
            Accessible.name: I18n.tr("Search icons")
            maximumLength: 60
            onTextEdited: root.query = text
        }

        Grid {
            id: grid
            readonly property int cell: Theme.scaled(40)
            readonly property int glyphPixels: Theme.scaled(20)
            columns: Math.max(4, Math.floor((parent.width + spacing) / (cell + spacing)))
            spacing: Theme.scaled(6)

            Repeater {
                model: root.results

                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property string value: ControlIconHelpers.custom(modelData.name, modelData.code)
                    readonly property bool selected: Settings.controlIcon === value
                    objectName: "controlIconResult"

                    function pick() {
                        cell.forceActiveFocus();
                        root.choose(cell.value);
                    }
                    width: grid.cell
                    height: grid.cell
                    radius: Theme.chipRadius
                    color: selected ? Theme.chip : Theme.cardFill
                    border.width: selected ? 2 : cell.activeFocus ? 1 : 0
                    border.color: selected ? Theme.accent : Theme.accentText
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: ControlIconHelpers.title(modelData.name)
                    Accessible.description: ControlIconHelpers.setLabel(modelData.name)
                    Accessible.checked: selected
                    Accessible.onPressAction: pick()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Space) {
                            cell.pick();
                            event.accepted = true;
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        hovered: cellMouse.containsMouse
                        pressed: cellMouse.pressed
                        focused: cell.activeFocus
                        tint: Theme.textHi
                        pressPoint: Qt.point(cellMouse.mouseX, cellMouse.mouseY)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: ControlIconHelpers.glyph(cell.modelData.code)
                        font.family: Theme.fontNerdIcons
                        font.pixelSize: grid.glyphPixels
                        color: cell.selected || cellMouse.containsMouse ? Theme.textHi : Theme.textMid
                    }

                    SettingsTooltip {
                        visible: cellMouse.containsMouse
                        text: ControlIconHelpers.title(cell.modelData.name) + " · "
                            + ControlIconHelpers.setLabel(cell.modelData.name)
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cell.pick()
                    }
                }
            }
        }

        SettingsHint {
            width: parent.width
            text: !root.catalogueLoaded ? I18n.tr("Loading icons…")
                : root.results.length === 0 ? I18n.tr("No icon matches that name.")
                : I18n.tr("Icons from Nerd Fonts. The bar and the terminal draw the same one.")
        }
    }

    // ---- preview --------------------------------------------------------------
    Item {
        objectName: "controlIconPreview"
        width: parent.width
        height: previewRow.height

        Row {
            id: previewRow
            spacing: root.tileGap

            // The prompt as fish draws it (assets/EDM115-newline2.omp.json):
            // the icon segment, then the folder, in the theme's own colours.
            Rectangle {
                id: terminal
                width: Math.max(Theme.scaled(220), root.width - barPreview.width - root.tileGap)
                height: promptLines.height + Theme.scaled(24)
                radius: Theme.chipRadius + 1
                color: "#0c0b10"
                border.width: 1
                border.color: Theme.hairline
                Accessible.role: Accessible.StaticText
                Accessible.name: I18n.tr("Terminal prompt preview")

                Column {
                    id: promptLines
                    x: Theme.scaled(14)
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property int line: Theme.scaled(24)
                    readonly property int textSize: Theme.scaled(14)

                    Row {
                        height: promptLines.line
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "╭─"
                            font.family: Theme.fontNerdIcons
                            font.pixelSize: promptLines.textSize
                            color: "#f8f8f2"
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: promptIcon.width + Theme.scaled(22)
                            height: promptLines.line
                            color: "#282a36"
                            Item {
                                id: promptIcon
                                anchors.centerIn: parent
                                readonly property string text: ControlIconHelpers.promptText(
                                    Settings.controlIcon, Settings.controlIconPrompt)
                                width: Theme.scaled(16)
                                height: width
                                BrandIcon {
                                    anchors.fill: parent
                                    visible: promptIcon.text.codePointAt(0) === ControlIconHelpers.CYBEX_CODEPOINT
                                    name: "cybexos"
                                    colorized: true
                                    tint: "#f8f8f2"
                                    normalizeTintSource: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: promptIcon.text.codePointAt(0) !== ControlIconHelpers.CYBEX_CODEPOINT
                                    text: promptIcon.text === ControlIconHelpers.PROMPT_OS
                                        ? ControlIconHelpers.glyph(ControlIconHelpers.NIXOS_CODE) : promptIcon.text
                                    font.family: Theme.fontNerdIcons
                                    font.pixelSize: promptLines.textSize
                                    color: "#f8f8f2"
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            font.family: Theme.fontNerdIcons
                            font.pixelSize: promptLines.line
                            color: "#282a36"
                            Rectangle {
                                anchors.fill: parent
                                z: -1
                                color: "#cccccc"
                            }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: folder.implicitWidth + Theme.scaled(14)
                            height: promptLines.line
                            color: "#cccccc"
                            Text {
                                id: folder
                                anchors.centerIn: parent
                                text: "\u{F0256} ~"
                                font.family: Theme.fontNerdIcons
                                font.pixelSize: promptLines.textSize
                                color: "#282a36"
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            font.family: Theme.fontNerdIcons
                            font.pixelSize: promptLines.line
                            color: "#cccccc"
                        }
                    }
                    Text {
                        height: promptLines.line
                        verticalAlignment: Text.AlignVCenter
                        text: "╰─ >"
                        font.family: Theme.fontNerdIcons
                        font.pixelSize: promptLines.textSize
                        color: "#f8f8f2"
                    }
                }
            }

            // The bar button, at rest and pointed at.
            Rectangle {
                id: barPreview
                width: barRow.width + Theme.scaled(16)
                height: terminal.height
                radius: Theme.chipRadius + 1
                color: Theme.barSurface
                border.width: 1
                border.color: Theme.hairline
                Accessible.role: Accessible.StaticText
                Accessible.name: I18n.tr("Bar button preview")

                Row {
                    id: barRow
                    anchors.centerIn: parent
                    spacing: Theme.scaled(6)
                    Repeater {
                        model: [false, true]
                        delegate: Rectangle {
                            required property bool modelData
                            width: Theme.roundButton
                            height: Theme.roundButton
                            radius: Theme.chipRadius
                            color: modelData ? Theme.hoverFillStrong : "transparent"
                            BarUi.ControlIconGlyph {
                                anchors.centerIn: parent
                                width: Theme.barIconSize
                                height: Theme.barIconSize
                                highlighted: parent.modelData
                            }
                        }
                    }
                }
            }
        }
    }

    SwitchRow {
        width: parent.width
        label: I18n.tr("Use in terminal prompt")
        description: I18n.tr("Off: the prompt shows the operating system's icon")
        settingKey: "controlIconPrompt"
    }
}
