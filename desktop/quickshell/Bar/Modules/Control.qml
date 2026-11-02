import QtQuick
import ".."
import "../../Common"

BarModule {
    id: root
    moduleId: "control"

    BarChip {
        id: controlButton
        host: root.host
        panelName: "control"
        isle: root.isle
        anchorItem: root.groupAnchor ?? controlButton
        hPadding: 5
        tooltip: I18n.tr("Control Center")
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("Control Center")

        // Settings -> Control Center -> Button icon; the fish prompt shows
        // the same icon.
        ControlIconGlyph {
            objectName: "controlIcon"
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.barIconSize
            height: Theme.barIconSize
            highlighted: controlButton.held || controlButton.hovered
        }
    }
}
