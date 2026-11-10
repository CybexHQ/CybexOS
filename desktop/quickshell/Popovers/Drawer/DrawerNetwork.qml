pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking as QsNetworking
import "../../Common"
import "../../Common/NetworkHelpers.js" as NetworkHelpers
import ".."

// The drawer's Network tab: the active Wi-Fi connection and its vitals, the
// in-range networks, the Tailscale row, a VPN switch when a VPN profile
// exists, the DNS selector, and the live throughput metrics. Share and Speed test hand off to the network
// overlay, which already owns those two flows.
//
// With nothing to connect through it says why in the drawer's one
// empty-state pattern (DrawerEmptyState): the network service is not
// running, there is no adapter or no cable, or Wi-Fi is blocked or off —
// with at most one way out. Rows for things that are not there (Tailscale
// when it is not installed, DNS without the network service, readings
// without a connection) stay out of sight.
Column {
    id: root

    // NetworkManager answered at startup (Quickshell's backend is fixed then).
    readonly property bool serviceDown:
        QsNetworking.Networking.backend === QsNetworking.NetworkBackendType.None
    readonly property bool wifiPresent: WifiState.device !== null
    readonly property bool wifiBlocked: wifiPresent && !QsNetworking.Networking.wifiHardwareEnabled
    readonly property bool wired: EthernetState.connected
    readonly property bool online: wired || WifiState.connected
    // "" while there is something to show; otherwise why there is not.
    readonly property string emptyKind: wired ? ""
        : serviceDown ? "service"
        : !wifiPresent ? (!EthernetState.known || EthernetState.devices.length > 0
            ? "cable" : "hardware")
        : wifiBlocked ? "blocked"
        : !WifiState.enabled ? "off" : ""
    readonly property bool cableMissing: emptyKind === "cable"

    readonly property var networks: NetworkDetails.groupedNetworks.all
    // Every network snapshot (on NetworkManager events, scan changes and a
    // 10 s safety poll) regroups the list into a fresh array. Handing that to
    // the Repeater rebuilt every row each time — wiping a half-typed password
    // and its focus — so the rows are keyed by SSID instead: a string property
    // only notifies when the six visible networks or their order really
    // change, and each row reads its live entry from `networks`.
    readonly property string networkKey: NetworkHelpers.networkListKey(networks, 6)
    readonly property var networkSsids: NetworkHelpers.networkListIds(networkKey)
    readonly property var activeNetwork: NetworkDetails.activeWifiNetwork
    readonly property var internetPing: NetworkDetails.internetPing
    // The SSID whose credential entry is unfolded, "" while none is.
    property string credentialSsid: ""
    property string credentialSecurity: ""
    property string credentialError: ""
    // What has been typed for credentialSsid. Held here rather than only in
    // the row's field, because a reorder still rebuilds rows.
    property string credentialPassword: ""

    width: parent ? parent.width : 0
    spacing: Theme.scaled(14)

    Claim {
        active: root.visible
        onClaimed: {
            NetworkDetails.acquire();
            EthernetState.acquire();
            Tailscale.acquireLive();
        }
        onReleased: {
            NetworkDetails.release();
            EthernetState.release();
            Tailscale.releaseLive();
        }
    }

    function beginConnect(network) {
        credentialError = "";
        // A row outliving its scan entry has no security to act on.
        if (network.missing)
            return;
        const security = NetworkHelpers.classifySecurity(
            network.profileSecurity || network.security);
        if (!security.supported)
            return;
        const iface = NetworkDetails.snapshot && NetworkDetails.snapshot.wifi
            ? NetworkDetails.snapshot.wifi.interface : "";
        if (network.profileUuid) {
            NetworkDetails.runWifiAction({
                action: "connect", ssid: network.ssid, uuid: network.profileUuid,
                interface: iface,
                security: network.profileSecurity || network.security, saved: true
            });
            foldCredentials();
            return;
        }
        if (!security.password && !security.identity) {
            NetworkDetails.runWifiAction({
                action: "connect", ssid: network.ssid, interface: iface,
                security: network.security
            });
            foldCredentials();
            return;
        }
        credentialPassword = "";
        credentialSsid = network.ssid;
        credentialSecurity = network.security;
    }

    function foldCredentials() {
        credentialSsid = "";
        credentialPassword = "";
    }

    function submitPassword(password) {
        if (password === "") {
            credentialError = "Enter the network password.";
            return;
        }
        const iface = NetworkDetails.snapshot && NetworkDetails.snapshot.wifi
            ? NetworkDetails.snapshot.wifi.interface : "";
        const accepted = NetworkDetails.runWifiAction({
            action: "connect", ssid: credentialSsid, interface: iface,
            security: credentialSecurity, password: password
        });
        if (accepted) {
            foldCredentials();
            credentialError = "";
        }
    }

    function metricValue(label) {
        const ping = internetPing;
        switch (label) {
        case "Ping":
            return ping && ping.latency >= 0 ? Math.round(ping.latency) + " ms" : "--";
        case "Loss":
            return ping ? ping.loss + "%" : "--";
        case "Down":
            return NetworkHelpers.formatRate(NetworkDetails.downloadRate);
        case "Up":
            return NetworkHelpers.formatRate(NetworkDetails.uploadRate);
        }
        return "--";
    }

    DrawerEmptyState {
        visible: root.emptyKind !== ""
        glyph: root.cableMissing ? "lan" : "wifi_off"
        title: root.emptyKind === "service" ? I18n.tr("Network service isn't running")
            : root.emptyKind === "hardware" ? I18n.tr("No network adapter found")
            : root.emptyKind === "cable" ? I18n.tr("No cable connected")
            : root.emptyKind === "blocked" ? I18n.tr("Wi-Fi is blocked")
            : I18n.tr("Wi-Fi is off")
        detail: root.emptyKind === "service"
            ? I18n.tr("Wi-Fi and wired connections can't be managed until it starts.")
            : root.emptyKind === "hardware"
            ? I18n.tr("This computer has no Wi-Fi or network port the system can use.")
            : root.emptyKind === "cable" ? I18n.tr("Plug in a network cable to go online.")
            : root.emptyKind === "blocked"
            ? I18n.tr("Turn off airplane mode or the wireless switch on this computer.")
            : I18n.tr("Turn it on to see networks nearby.")
        actionText: root.emptyKind === "off" ? I18n.tr("Turn on")
            : root.emptyKind === "service" || root.emptyKind === "cable"
            ? I18n.tr("Network settings") : ""
        onAction: {
            if (root.emptyKind === "off")
                WifiState.setEnabled(true);
            else
                Settings.showPanel("network", Popouts.hostScreenName);
        }
    }

    // ---- header ----------------------------------------------------------
    Item {
        visible: root.emptyKind === ""
        width: parent.width
        height: 40

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: wifiToggle.visible ? wifiToggle.left : parent.right
            anchors.rightMargin: wifiToggle.visible ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.wired ? I18n.tr("Ethernet")
                    : WifiState.connected ? WifiState.name : I18n.tr("Wi-Fi")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.title
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    if (!root.online)
                        return I18n.tr("Not connected");
                    const parts = [];
                    if (WifiState.connected && WifiState.signal >= 0)
                        parts.push(WifiState.signal + "%");
                    const band = root.activeNetwork
                        ? NetworkHelpers.bandForFrequency(
                            root.activeNetwork.frequency) : "";
                    if (band !== "")
                        parts.push(band + " GHz");
                    if (root.internetPing && root.internetPing.latency >= 0)
                        parts.push(Math.round(root.internetPing.latency) + " ms");
                    parts.push("↓" + NetworkHelpers.formatRate(
                        NetworkDetails.downloadRate));
                    return parts.join(" · ");
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
                elide: Text.ElideRight
            }
        }

        // Only for a Wi-Fi adapter that is there, and faded while a switch
        // or airplane mode blocks it.
        Toggle {
            id: wifiToggle
            visible: root.wifiPresent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            metrics: Theme.switchCompact
            checked: WifiState.enabled
            enabled: !root.wifiBlocked
            accessibleName: "Wi-Fi"
            onToggled: value => WifiState.setEnabled(value)
        }
    }

    // ---- networks --------------------------------------------------------
    Column {
        visible: WifiState.enabled && root.emptyKind === ""
        width: parent.width
        spacing: 2

        Repeater {
            model: root.networkSsids

            delegate: Column {
                id: netEntry

                // The SSID; everything else is read live from root.networks.
                required property string modelData
                readonly property var network:
                    NetworkHelpers.networkBySsid(root.networks, modelData)
                readonly property bool current: network.connected === true
                readonly property bool unfolded:
                    root.credentialSsid === modelData
                readonly property string failure:
                    NetworkDetails.wifiError(modelData)

                // A fresh field starts from what was already typed.
                onUnfoldedChanged: {
                    if (unfolded)
                        passwordInput.text = root.credentialPassword;
                }

                width: parent ? parent.width : 0
                spacing: 2

                Rectangle {
                    id: netRow
                    width: parent.width
                    height: 36
                    radius: Theme.rowRadius
                    color: netEntry.current || netMouse.containsMouse
                        ? Theme.chip : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.chipFadeDuration }
                    }

                    Sym {
                        id: netMark
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        name: netEntry.network.signal >= 66 ? "wifi"
                            : netEntry.network.signal >= 33
                            ? "network_wifi_2_bar" : "network_wifi_1_bar"
                        size: 16
                        color: netEntry.current ? Theme.accentText : Theme.textMid
                    }

                    Text {
                        anchors.left: netMark.right
                        anchors.leftMargin: 12
                        anchors.right: netSecurity.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: netEntry.network.ssid
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.primary
                        font.weight: netEntry.current
                            ? Theme.weightSemibold : Theme.weightMedium
                        color: netEntry.current ? Theme.textHi : Theme.textMid
                        elide: Text.ElideRight
                    }

                    Text {
                        id: netSecurity
                        anchors.right: netLock.visible ? netLock.left : parent.right
                        anchors.rightMargin: netLock.visible ? 6 : 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: netEntry.current ? "Connected"
                            : netEntry.network.known ? "Saved"
                            : NetworkHelpers.classifySecurity(
                                netEntry.network.security).label
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        color: Theme.textFaint
                    }

                    Sym {
                        id: netLock
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !netEntry.current
                            && (netEntry.network.security || "") !== ""
                            && (netEntry.network.security || "") !== "--"
                        name: "lock"
                        size: 13
                        color: Theme.textFaint
                    }

                    MouseArea {
                        id: netMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (netEntry.current)
                                return;
                            if (netEntry.unfolded)
                                root.foldCredentials();
                            else
                                root.beginConnect(netEntry.network);
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: (netEntry.current ? "Connected to "
                        : "Connect to ") + netEntry.network.ssid
                }

                // Inline credential entry for a secured network the shell has
                // no profile for.
                Rectangle {
                    visible: netEntry.unfolded
                    width: parent.width
                    height: 36
                    radius: Theme.rowRadius
                    color: Theme.chip

                    TextInput {
                        id: passwordInput
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: connectLink.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.control
                        color: Theme.textHi
                        echoMode: TextInput.Password
                        clip: true
                        focus: netEntry.unfolded
                        onAccepted: root.submitPassword(text)
                        onTextChanged: {
                            if (netEntry.unfolded)
                                root.credentialPassword = text;
                        }
                        // A reorder while the entry is open recreates this
                        // row: carry the typed text and the keyboard across.
                        Component.onCompleted: {
                            if (!netEntry.unfolded)
                                return;
                            text = root.credentialPassword;
                            cursorPosition = text.length;
                            forceActiveFocus();
                        }

                        Text {
                            visible: passwordInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Password")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.control
                            color: Theme.textFaint
                        }
                    }

                    LinkText {
                        id: connectLink
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Connect")
                        onClicked: root.submitPassword(passwordInput.text)
                    }
                }

                Text {
                    visible: (netEntry.failure !== "" && !netEntry.current)
                        || (netEntry.unfolded && root.credentialError !== "")
                    width: parent.width - 16
                    x: 8
                    text: netEntry.unfolded && root.credentialError !== ""
                        ? root.credentialError : netEntry.failure
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    color: Theme.redText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ---- tailscale · vpn · dns ------------------------------
    Column {
        visible: root.emptyKind === ""
        width: parent.width
        spacing: 2

        // Tailscale only where it is installed.
        Item {
            visible: !Tailscale.missing
            width: parent.width
            height: 40

            BrandIcon {
                id: tsMark
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                name: "tailscale"
            }

            Text {
                id: tsLabel
                anchors.left: tsMark.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Tailscale")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.control
                font.weight: Theme.weightMedium
                color: Theme.textHi
            }

            Text {
                anchors.left: tsLabel.right
                anchors.leftMargin: 10
                anchors.right: tsToggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Tailscale.connected
                    ? [Tailscale.host, Tailscale.ip].filter(s => s !== "").join(" · ")
                    : Tailscale.statusText
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
                elide: Text.ElideRight
            }

            Toggle {
                id: tsToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                metrics: Theme.switchCompact
                checked: Tailscale.running
                enabled: !Tailscale.busy
                accessibleName: "Tailscale"
                onToggled: value => Tailscale.setRunning(value)
            }
        }

        LinkText {
            visible: !Tailscale.missing && !Tailscale.connected
            text: Tailscale.needsApproval ? "View approval status"
                : Tailscale.authPending ? "Continue sign-in"
                : Tailscale.needsLogin ? "Sign in to Tailscale" : "Tailscale connection details"
            onClicked: Tailscale.showSetup()
        }

        // A VPN switch only for people who have a VPN profile: the one in
        // use, else the one used last. Every profile, and import, is in
        // Settings -> Network.
        Item {
            id: vpnRow

            readonly property var vpn: NetworkHelpers.preferredVpn(NetworkDetails.vpnProfiles)
            readonly property string uuid: vpn ? vpn.uuid : ""
            readonly property string pending: uuid !== "" && NetworkDetails.vpnBusyUuid === uuid
                ? NetworkDetails.vpnBusyAction : ""
            readonly property string failure: uuid !== "" ? NetworkDetails.vpnError(uuid) : ""

            visible: vpn !== null
            width: parent.width
            height: 40

            Sym {
                id: vpnMark
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                name: "security"
                size: 16
                color: NetworkHelpers.isVpnActive(vpnRow.vpn) ? Theme.accentText : Theme.textMid
            }

            Text {
                id: vpnName
                anchors.left: vpnMark.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.5)
                text: vpnRow.vpn ? vpnRow.vpn.name : ""
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.control
                font.weight: Theme.weightMedium
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                anchors.left: vpnName.right
                anchors.leftMargin: 10
                anchors.right: vpnToggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: NetworkHelpers.vpnStateText(vpnRow.vpn, vpnRow.pending)
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textFaint
                elide: Text.ElideRight
            }

            Toggle {
                id: vpnToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                metrics: Theme.switchCompact
                checked: vpnRow.pending !== "" ? vpnRow.pending === "connect"
                    : NetworkHelpers.isVpnActive(vpnRow.vpn)
                enabled: NetworkDetails.vpnBusyUuid === ""
                accessibleName: "VPN " + vpnName.text
                onToggled: value => NetworkDetails.runVpnAction({
                    action: value ? "connect" : "disconnect", uuid: vpnRow.uuid
                })
            }
        }

        Text {
            visible: vpnRow.visible && vpnRow.failure !== ""
            width: parent.width - 16
            x: 8
            text: vpnRow.failure
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            color: Theme.redText
            wrapMode: Text.WordWrap
        }

        // DNS is NetworkManager's to change.
        Item {
            visible: !root.serviceDown
            width: parent.width
            height: 40

            Sym {
                id: dnsMark
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                name: "dns"
                size: 16
                color: Theme.textMid
            }

            Text {
                anchors.left: dnsMark.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("DNS")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.control
                font.weight: Theme.weightMedium
                color: Theme.textHi
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: dnsRow.implicitWidth + 4
                height: 26
                radius: 7
                color: Theme.chip
                opacity: NetworkDetails.dnsBusy ? 0.5 : 1

                Row {
                    id: dnsRow
                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: ["Automatic", "Cloudflare", "Google"]

                        delegate: Rectangle {
                            id: dnsChoice

                            required property string modelData
                            readonly property bool on:
                                NetworkDetails.dnsProvider === modelData

                            width: dnsChoiceText.implicitWidth + 14
                            height: 22
                            radius: 5
                            color: on ? Theme.chipHover : "transparent"

                            Text {
                                id: dnsChoiceText
                                anchors.centerIn: parent
                                text: dnsChoice.modelData === "Automatic"
                                    ? "Auto" : dnsChoice.modelData
                                font.family: Theme.fontMenu
                                font.pixelSize: Theme.typography.control
                                font.weight: Theme.weightSemibold
                                color: dnsChoice.on ? Theme.textHi : Theme.textFaint
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!dnsChoice.on)
                                        NetworkDetails.setDns(
                                            dnsChoice.modelData, []);
                                }
                            }

                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: dnsChoice.on
                            Accessible.name: "DNS " + dnsChoice.modelData
                        }
                    }
                }
            }
        }
    }

    // ---- metrics ---------------------------------------------------------
    // Readings of a connection, so only while there is one.
    Grid {
        id: metricsGrid
        visible: root.emptyKind === "" && root.online
        width: parent.width
        columns: 2
        columnSpacing: 6
        rowSpacing: 6

        readonly property real cellWidth: (width - columnSpacing) / 2

        // A fixed model: an array literal of live values was a new model on
        // every sample, and rebuilt all four cells each time.
        Repeater {
            model: ["Ping", "Loss", "Down", "Up"]

            delegate: Rectangle {
                id: metricCell

                required property string modelData

                width: metricsGrid.cellWidth
                height: 36
                radius: 10
                color: Theme.chip

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr(metricCell.modelData)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    color: Theme.textFaint
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.metricValue(metricCell.modelData)
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.typography.secondary
                    font.weight: Theme.weightSemibold
                    font.features: Theme.tabularNumberFeatures
                    color: Theme.textHi
                }
            }
        }
    }

    // Share hands out the Wi-Fi network in use; a speed test needs a
    // connection. The empty state carries its own action instead.
    DrawerFooter {
        visible: root.emptyKind === ""
        info: {
            const primary = NetworkDetails.primary;
            const raw = primary && primary.ipv4 ? String(primary.ipv4) : "";
            return raw.split("/")[0];
        }
        secondaryText: WifiState.connected ? I18n.tr("Share") : ""
        actionText: root.online ? I18n.tr("Speed test") : I18n.tr("Network settings")
        onSecondaryClicked: {
            const iface = NetworkDetails.activeWifiInterface;
            Popouts.close();
            NetworkOverlayState.openQr(Screens.byName(Popouts.hostScreenName), iface);
        }
        onActionClicked: {
            if (!root.online) {
                Settings.showPanel("network", Popouts.hostScreenName);
                return;
            }
            const iface = NetworkDetails.primaryInterface;
            Popouts.close();
            NetworkOverlayState.openSpeedTest(
                Screens.byName(Popouts.hostScreenName), iface);
        }
    }
}
