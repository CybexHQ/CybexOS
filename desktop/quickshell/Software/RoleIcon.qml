import QtQuick
import Quickshell
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// An app that can do an everyday job: the icon shipped with the catalogue,
// else its desktop entry's, or a web mail service's glyph on an accent tile.
Item {
    id: root

    property var option: null
    property string desktop: ""
    property real size: Theme.scaled(36)

    readonly property bool glyph: !!(option && option.glyph)
    readonly property var entry: {
        void DesktopEntries.applications.values;
        const ids = Helpers.entryIds([desktop]);
        return ids.length === 1 ? DesktopEntries.byId(ids[0]) : null;
    }

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    AppIcon {
        anchors.fill: parent
        visible: !root.glyph
        app: root.option && root.option.icon ? { id: root.option.id } : null
        icon: root.entry ? root.entry.icon : ""
        size: root.size
    }
    Rectangle {
        anchors.fill: parent
        visible: root.glyph
        radius: Math.round(root.size * 0.24)
        color: Theme.accentAlpha(Theme.dark ? 0.18 : 0.14)
        Sym {
            anchors.centerIn: parent
            name: root.glyph ? root.option.glyph : ""
            size: Math.round(root.size * 0.55)
            color: Theme.accentText
        }
    }
}
