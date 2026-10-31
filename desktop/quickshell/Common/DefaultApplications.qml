pragma Singleton
import QtQuick
import Quickshell

// This account's default apps through cybexos-apps: what each role uses,
// Cybex OS's pick for it, the installed apps that can do it, and a choice
// waiting for its app to finish installing. Requests run one at a time, in
// order, and each answers with the full status.
Singleton {
    id: root
    property var roles: ({})
    property bool loaded: false
    property var waiting: []
    readonly property bool busy: client.busy || waiting.length > 0
    readonly property string error: client.error
    // Choices that waited for their app and took effect with this status.
    signal settled(var roles)

    function request(args) {
        waiting = waiting.concat([args]);
        pump();
    }
    function pump() {
        if (client.busy || waiting.length === 0)
            return;
        const next = waiting[0];
        waiting = waiting.slice(1);
        if (!client.run(["cybexos-apps"].concat(next)))
            waiting = [next].concat(waiting);
    }
    function refresh() {
        if (!waiting.some(args => args[0] === "status"))
            request(["status"]);
    }
    function select(role, id) { request(["set", role, id]); }
    // Use an app as soon as it is installed; Software installs it meanwhile.
    function selectWhenInstalled(role, id) { request(["set", role, id, "--when-installed"]); }
    // Back to Cybex OS's pick: forget this account's choice for the role.
    function reset(role) { request(["reset", role]); }
    function cancel(role) { request(["cancel", role]); }

    JsonCommand {
        id: client
        onCompleted: value => {
            root.roles = value.roles || ({});
            root.loaded = true;
            const settled = value.settled || [];
            if (settled.length > 0)
                root.settled(settled);
        }
    }
    Connections {
        target: client
        function onBusyChanged() {
            if (!client.busy)
                Qt.callLater(root.pump);
        }
    }
}
