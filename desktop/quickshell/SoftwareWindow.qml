import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Common"
import "Software" as SoftwareUi

// Software: Explore, install and remove native apps. Opened from the
// launcher, Settings → Applications and `cybexos-software`. Every install is
// one checked, prebuilt system change; closing the window never interrupts it.
FloatingWindow {
    id: window

    title: "Cybex OS Software" // i18n: untranslated (compositor identity)
    visible: Software.open
    color: Theme.panelSurface
    // The window opens on the focused output (below); size it for that one.
    readonly property var output: Screens.focused
    implicitWidth: Math.min(Theme.scaled(1100, Theme.contentScale),
        output ? output.width - Theme.panelPadding * 2 : 1100)
    implicitHeight: Math.min(Theme.scaled(740),
        output ? output.height - Theme.barHeight - Theme.panelPadding * 2 : 740)
    minimumSize: Qt.size(760, 520)
    onClosed: Software.close()
    onVisibleChanged: {
        if (visible) {
            screen = Screens.focused;
            minimized = false;
        }
    }

    Connections {
        target: Software
        function onPresent() {
            window.minimized = false;
            Hyprland.dispatch('hl.dsp.focus({ window = "title:^Cybex OS Software$" })');
        }
    }

    SoftwareUi.SoftwareView {
        anchors.fill: parent
        focus: true
    }
}
