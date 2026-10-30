pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// Pointer themes as a gallery (Settings -> Appearance -> Pointer): each tile
// shows the theme's own arrow, link hand, text beam and busy shape, drawn
// from its files (scripts/pointer_xcursor.py) at one shared scale, so a
// small theme looks small. Hovering a tile plays its busy animation.
//
// The same gallery shows the themes on this computer and those that can be
// downloaded. A download tile carries the download mark and, once clicked,
// a spinner until the theme arrives and is picked (Pointer.pick). A
// downloaded theme that is not in use offers to remove itself on hover, or
// with Delete.
Item {
    id: root

    property var entries: []
    readonly property string current: Pointer.resolved.chosen

    readonly property int gap: Theme.scaled(10)
    // Wide enough for "Bibata Original Classic" in one line.
    readonly property int minimumTile: Theme.scaled(160, Theme.typeScale)
    readonly property int columns: Math.max(2, Math.floor((width + gap) / (minimumTile + gap)))
    readonly property real tileWidth: (width - gap * (columns - 1)) / columns
    readonly property real thumbHeight: Math.round(Math.max(Theme.scaled(56), tileWidth * 0.42))
    // Screen pixels per preview pixel. Four 48 px shapes fill about half the
    // thumb's height and fit its width.
    readonly property real shapeScale: Math.min(thumbHeight * 0.55 / 48,
        (tileWidth - Theme.scaled(28)) / (4 * 48 + 3 * Theme.scaled(4)))
    readonly property real tileHeight: thumbHeight + Theme.scaled(6) + nameMetrics.height

    implicitHeight: entries.length === 0 ? 0
        : Math.ceil(entries.length / columns) * (tileHeight + gap) - gap + Theme.scaled(8)

    TextMetrics {
        id: nameMetrics
        font.family: Theme.fontMenu
        font.pixelSize: Theme.typography.secondary
        text: "Pointer" // i18n: untranslated (a line-height sample, never drawn)
    }

    Repeater {
        model: root.entries

        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool selected: modelData.installed && modelData.id === root.current
            readonly property bool downloading: Pointer.downloading === modelData.id
            readonly property bool removing: Pointer.removing === modelData.id
            readonly property bool canRemove: modelData.removable && !Pointer.inUse(modelData.id)
                && !Pointer.busy
            readonly property bool available: modelData.installed || modelData.downloadable
            readonly property string action: modelData.installed ? I18n.tr("Use")
                : modelData.downloadable ? I18n.tr("Download and use") : I18n.tr("Not available")

            x: (index % root.columns) * (root.tileWidth + root.gap)
            y: Theme.scaled(4) + Math.floor(index / root.columns) * (root.tileHeight + root.gap)
            width: root.tileWidth
            height: root.tileHeight
            activeFocusOnTab: available
            Accessible.role: Accessible.RadioButton
            Accessible.name: tile.modelData.name + ", " + tile.action
            Accessible.checked: tile.selected
            Accessible.onPressAction: Pointer.pick(tile.modelData.id)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    Pointer.pick(tile.modelData.id);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Delete && tile.canRemove) {
                    Pointer.remove(tile.modelData.id);
                    event.accepted = true;
                }
            }

            Rectangle {
                id: thumb
                width: parent.width
                height: root.thumbHeight
                radius: Theme.chipRadius + 1
                color: Theme.chip
                clip: true
                opacity: tile.available ? 1 : 0.45

                // A theme with a roomy canvas is shrunk to fit the tile, never cut.
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.scaled(4)
                    scale: Math.min(1, (thumb.width - Theme.scaled(14)) / Math.max(1, implicitWidth))
                    opacity: tile.downloading || tile.removing ? 0.35 : 1

                    Repeater {
                        model: ["arrow", "hand", "text"]
                        delegate: Image {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            source: tile.modelData.previews[modelData]
                                ? "file://" + tile.modelData.previews[modelData] : ""
                            width: implicitWidth * root.shapeScale
                            height: implicitHeight * root.shapeScale
                            smooth: true
                            mipmap: true
                            asynchronous: true
                        }
                    }
                    PointerBusyShape {
                        anchors.verticalCenter: parent.verticalCenter
                        theme: tile.modelData
                        shapeScale: root.shapeScale
                        playing: tileHover.hovered || tile.activeFocus
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    hovered: tileHover.hovered
                    pressed: tileMouse.pressed
                    focused: tile.activeFocus
                    tint: Theme.textHi
                    pressPoint: Qt.point(tileMouse.mouseX, tileMouse.mouseY)
                }

                Sym {
                    visible: tile.downloading || tile.removing
                    anchors.centerIn: parent
                    name: "progress_activity"
                    size: Theme.iconMedium
                    color: Theme.textHi
                }
            }

            Rectangle {
                anchors.fill: thumb
                anchors.margins: tile.selected ? -3 : 0
                radius: thumb.radius + (tile.selected ? 3 : 0)
                color: "transparent"
                border.width: tile.selected ? 2 : 1
                border.color: tile.selected ? Theme.accent : tile.activeFocus ? Theme.accentText : Theme.hairline
            }

            Rectangle {
                visible: tile.selected
                x: Theme.scaled(6)
                y: thumb.height - height - Theme.scaled(6)
                width: Theme.scaled(18)
                height: width
                radius: width / 2
                color: Theme.accent
                Sym {
                    anchors.centerIn: parent
                    name: "check"
                    size: Theme.scaled(12)
                    color: Theme.textOnAccent
                }
            }

            // Top right: what a click does or what the theme is. A download
            // mark, the person's own theme, or, on hover, removing a download.
            Rectangle {
                id: badge
                readonly property string kind: tile.canRemove && (tileHover.hovered || tile.activeFocus)
                    ? "remove"
                    : !tile.modelData.installed && tile.modelData.downloadable && !tile.downloading ? "download"
                    : tile.modelData.source === "yours" ? "yours" : ""
                visible: kind !== ""
                x: thumb.width - width - Theme.scaled(6)
                y: Theme.scaled(6)
                height: Theme.scaled(20)
                width: kind === "yours" ? yoursText.implicitWidth + Theme.scaled(14) : height
                radius: height / 2
                color: kind === "remove" && removeMouse.containsMouse ? Theme.chipHover : Theme.popBg
                border.width: 1
                border.color: Theme.hairline

                Sym {
                    visible: badge.kind !== "yours"
                    anchors.centerIn: parent
                    name: badge.kind === "remove" ? "delete" : "download"
                    size: Theme.scaled(13)
                    color: badge.kind === "remove" && removeMouse.containsMouse ? Theme.redText : Theme.textMid
                }
                Text {
                    id: yoursText
                    visible: badge.kind === "yours"
                    anchors.centerIn: parent
                    text: I18n.tr("Yours")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.caption
                    font.weight: Theme.weightSemibold
                    color: Theme.textMid
                }
                SettingsTooltip {
                    visible: removeMouse.containsMouse
                    text: I18n.tr("Remove download")
                }
                MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    enabled: badge.kind === "remove"
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Pointer.remove(tile.modelData.id)
                }
            }

            Text {
                y: thumb.height + Theme.scaled(6)
                width: parent.width
                text: tile.downloading ? I18n.tr("Downloading…") : tile.modelData.name
                elide: Text.ElideRight
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                font.weight: tile.selected ? Theme.weightSemibold : Theme.weightMedium
                color: tile.selected ? Theme.textHi : Theme.textLow
            }

            SettingsTooltip {
                visible: tileHover.hovered && !removeMouse.containsMouse
                text: tile.modelData.name + " · " + tile.action
            }

            // Hover belongs to the whole tile, badge included, so moving onto
            // the remove mark does not hide it.
            HoverHandler {
                id: tileHover
                enabled: tile.available
            }

            MouseArea {
                id: tileMouse
                anchors.fill: parent
                z: -1
                enabled: tile.available
                cursorShape: tile.downloading ? Qt.BusyCursor : Qt.PointingHandCursor
                onClicked: {
                    tile.forceActiveFocus();
                    Pointer.pick(tile.modelData.id);
                }
            }
        }
    }
}
