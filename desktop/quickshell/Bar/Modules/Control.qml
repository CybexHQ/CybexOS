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
        // A chip, so the far-right mark reads as a button rather than a
        // close button (2026-11 review); open, it lights with an accent edge.
        restFill: Theme.barChip
        border.width: held ? 1 : 0
        border.color: Theme.barAccent
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
