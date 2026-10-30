pragma ComponentBehavior: Bound
import QtQuick
import "../Common"

// "Try it": six places that each ask for one pointer shape, among them the
// ones rarely met on purpose (busy, resize, not allowed). The choice above
// is already live, so this is the real pointer that Hyprland draws, not a
// picture of it; each place also shows the shape it asks for. The text
// field is where Hide while typing can be tried.
Rectangle {
    id: root

    property var theme: null
    property bool mirrored: false

    readonly property var places: [
        { shape: "arrow", label: I18n.tr("Pointer"), cursor: Qt.ArrowCursor },
        { shape: "hand", label: I18n.tr("Link"), cursor: Qt.PointingHandCursor },
        { shape: "text", label: I18n.tr("Text"), cursor: Qt.IBeamCursor },
        { shape: "busy", label: I18n.tr("Busy"), cursor: Qt.WaitCursor },
        { shape: "resize", label: I18n.tr("Resize"), cursor: Qt.SizeHorCursor },
        { shape: "forbidden", label: I18n.tr("Not allowed"), cursor: Qt.ForbiddenCursor }
    ]
    readonly property int pad: Theme.scaled(8)
    readonly property int gap: Theme.scaled(6)
    readonly property int columns: width >= Theme.scaled(420, Theme.typeScale) ? 6 : 3
    readonly property real placeWidth: (width - pad * 2 - gap * (columns - 1)) / columns
    readonly property real placeHeight: Theme.scaled(64, Theme.typeScale)
    readonly property real shapeScale: Theme.scaled(26) / 48

    implicitHeight: pad * 2 + Math.ceil(places.length / columns) * (placeHeight + gap) - gap
    radius: Theme.chipRadius + 2
    color: Theme.chip

    Repeater {
        model: root.places

        delegate: Rectangle {
            id: place
            required property var modelData
            required property int index
            readonly property bool typing: modelData.shape === "text"

            x: root.pad + (index % root.columns) * (root.placeWidth + root.gap)
            y: root.pad + Math.floor(index / root.columns) * (root.placeHeight + root.gap)
            width: root.placeWidth
            height: root.placeHeight
            radius: Theme.chipRadius
            color: placeHover.hovered ? Theme.chipHover : "transparent"
            border.width: 1
            border.color: placeHover.hovered ? Theme.stroke : Theme.hairline
            Accessible.role: Accessible.StaticText
            Accessible.name: modelData.label + " " + I18n.tr("pointer")

            HoverHandler {
                id: placeHover
                cursorShape: place.modelData.cursor
            }

            Item {
                id: picture
                visible: !place.typing
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.scaled(6)
                width: parent.width
                height: parent.height - label.height - Theme.scaled(10)

                Image {
                    visible: place.modelData.shape !== "busy"
                    anchors.centerIn: parent
                    source: root.theme && root.theme.previews[place.modelData.shape]
                        ? "file://" + root.theme.previews[place.modelData.shape] : ""
                    width: implicitWidth * root.shapeScale
                    height: implicitHeight * root.shapeScale
                    mirror: root.mirrored && (place.modelData.shape === "arrow" || place.modelData.shape === "hand")
                    smooth: true
                    mipmap: true
                    asynchronous: true
                }
                PointerBusyShape {
                    visible: place.modelData.shape === "busy"
                    anchors.centerIn: parent
                    theme: root.theme
                    shapeScale: root.shapeScale
                    playing: placeHover.hovered
                }
            }

            // A field to type into: the text beam over it, and the pointer
            // hiding as the keys go down when that is switched on.
            Rectangle {
                visible: place.typing
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.scaled(8)
                width: parent.width - Theme.scaled(12)
                height: Theme.scaled(26, Theme.typeScale)
                radius: Theme.chipRadius - 2
                color: Theme.chip
                border.width: field.activeFocus ? 1 : 0
                border.color: Theme.accent

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: Theme.scaled(7)
                    anchors.rightMargin: Theme.scaled(7)
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    color: Theme.textHi
                    selectByMouse: true
                    Accessible.name: I18n.tr("Try typing")

                    Text {
                        visible: field.text === "" && !field.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Type…")
                        font: field.font
                        color: Theme.textFaint
                    }
                }
            }

            Text {
                id: label
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.scaled(6)
                width: parent.width - Theme.scaled(8)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: place.modelData.label
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.caption
                color: placeHover.hovered ? Theme.textHi : Theme.textLow
            }
        }
    }
}
