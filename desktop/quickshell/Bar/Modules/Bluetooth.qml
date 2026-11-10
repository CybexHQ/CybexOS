import QtQuick
import ".."
import "../../Common"

// Bluetooth gets its own detail target. The bar's auto-rule keeps it off
// screen unless something is actually connected.
BarModule {
    id: root

    moduleId: "bt"

    BarChip {
        id: chip

        host: root.host
        panelName: "bluetooth"
        isle: root.isle
        anchorItem: root.groupAnchor ?? chip
        tooltip: I18n.tr("Bluetooth connected")
        tooltipAlign: 1

        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: BluetoothState.enabled ? "bluetooth" : "bluetooth_disabled"
            size: Theme.barIconSize
            // Not connected is dimmed in the readable disabled ink (Wifi.qml).
            color: BluetoothState.connected ? chip.fg : Theme.barTextDisabled
        }
    }
}
