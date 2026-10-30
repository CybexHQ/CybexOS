pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// The install list, then the one system change it becomes: checked (nothing
// compiles), prepared by the supervised worker, installed after
// authorization with the current system kept as a fallback, then opened.
Rectangle {
    id: root

    readonly property string phase: Software.phase
    readonly property bool flight: Software.flowActive
    readonly property var rows: {
        if (!flight)
            return Software.queue;
        if (Software.flowItems.length > 0)
            return Software.flowItems;
        const change = Software.flowChange;
        return change.installs.map(name => Software.item(name, "install"))
            .concat(change.removals.map(name => Software.item(name, "remove")));
    }
    readonly property var installs: Helpers.installs(rows)
    readonly property var removals: Helpers.removals(rows)
    readonly property var queueState: Software.queueState
    readonly property string names: rows.map(row => row.name).join(", ")
    readonly property string installNames: installs.map(row => row.name).join(", ")
    readonly property string removeNames: removals.map(row => row.name).join(", ")
    readonly property var openable: installs.map(row => Software.appsByAttribute[row.attribute])
        .filter(app => !!app && Software.canOpenApp(app))
    readonly property var progress: Software.preparation
    readonly property string blocked: Software.blockReason
    readonly property bool confirming: phase === "ready"
    readonly property bool busy: ["checking", "authorizing", "preparing", "installing"].includes(phase)
        || (phase === "ready" && Updates.requestPending)

    function lead() {
        switch (phase) {
        case "checking":
            return I18n.tr("Checking that nothing needs compiling…");
        case "blocked":
            return I18n.tr("Some apps can't be installed yet");
        case "authorizing":
            return I18n.tr("Waiting for authorization…");
        case "preparing":
            // A change adopted from elsewhere names its apps only once built.
            return names !== "" ? I18n.format("Getting %1 ready…", [names]) : I18n.tr("Getting your software change ready…");
        case "ready":
            if (names === "")
                return I18n.tr("Your software change is ready to install");
            return removals.length === 0 ? I18n.format("Ready to install %1", [names])
                : installs.length === 0 ? I18n.format("Ready to remove %1", [names])
                : I18n.tr("Ready to apply these changes");
        case "installing":
            return installs.length > 0 ? I18n.format("Installing %1…", [installNames])
                : removals.length > 0 ? I18n.format("Removing %1…", [removeNames]) : I18n.tr("Installing your software change…");
        case "done":
            return removals.length === 0 ? I18n.format("%1 installed", [names])
                : installs.length === 0 ? I18n.format("%1 removed", [names]) : I18n.tr("Your changes are installed");
        case "failed":
            return I18n.tr("The change couldn't be installed");
        }
        if (removals.length === 0)
            return installs.length === 1 ? I18n.format("1 app to install: %1", [names])
                : I18n.format("%1 apps to install: %2", [installs.length, names]);
        if (installs.length === 0)
            return removals.length === 1 ? I18n.format("1 app to remove: %1", [names])
                : I18n.format("%1 apps to remove: %2", [removals.length, names]);
        return I18n.format("Install %1 · remove %2", [installNames, removeNames]);
    }

    function detail() {
        switch (phase) {
        case "checking":
            return names;
        case "blocked": {
            const stuck = queueState.blocked.map(name => (Software.appsByAttribute[name] || {}).name || name).join(", ");
            return I18n.format("NixOS hasn't finished building %1 yet. Try again after the next update.", [stuck]);
        }
        case "authorizing":
            return I18n.tr("Preparing a system change asks for your password.");
        case "preparing":
            return progress.fraction >= 0
                ? I18n.format("Downloading prebuilt packages · %1 of %2", [Helpers.size(progress.done) || "0 kB", Helpers.size(progress.expected)])
                : I18n.tr("Downloading prebuilt packages and checking the change. You can keep browsing.");
        case "ready":
            return Updates.requestFailure || I18n.tr("Checked and ready. Your current system stays as a fallback.");
        case "installing":
            return I18n.tr("This takes a moment. Keep your computer on.");
        case "done":
            return installs.length > 0
                ? I18n.tr("Find them in the launcher, or open one now. Restart when convenient to finish; until then your previous system stays the default.")
                : I18n.tr("Restart when convenient to finish; until then your previous system stays the default.");
        case "failed":
            return Software.failure || I18n.tr("Nothing on your computer was changed.");
        }
        if (blocked === "restart")
            return I18n.tr("Restart your computer to finish the last system change, then install these.");
        if (blocked === "busy")
            return I18n.tr("Another system change is being prepared. Install these when it's done.");
        if (blocked === "pending")
            return I18n.tr("A prepared system change is waiting in Software Update. Install or discard it first.");
        if (blocked === "unavailable")
            return I18n.tr("Apps can be installed once Cybex OS is installed on this computer.");
        if (Software.flowError !== "")
            return Software.flowError;
        if (queueState.state === "blocked")
            return I18n.tr("Some of these can't be installed yet: NixOS hasn't finished building them.");
        if (installs.length === 0)
            return I18n.tr("Your current system stays as a fallback.");
        const size = Helpers.size(queueState.downloadBytes);
        const vendor = queueState.vendor > 0;
        if (queueState.state === "checking")
            return size !== "" ? I18n.format("≈ %1 download · checking that everything is prebuilt…", [size])
                : I18n.tr("Checking that everything is prebuilt…");
        if (vendor)
            return size !== "" ? I18n.format("≈ %1 download plus vendor downloads · nothing to compile · you can keep browsing", [size])
                : I18n.tr("Vendor downloads · nothing to compile · you can keep browsing");
        return size !== "" ? I18n.format("≈ %1 download · all prebuilt, nothing to compile · you can keep browsing", [size])
            : I18n.tr("Nothing to download · all prebuilt · you can keep browsing");
    }

    readonly property bool problem: phase === "failed" || (phase === "idle" && (Software.flowError !== "" || blocked !== ""))
        || (phase === "ready" && Updates.requestFailure !== "")

    objectName: "softwareQueueBar"
    visible: rows.length > 0 || phase !== "idle" || Software.flowError !== ""
    implicitHeight: Math.max(Theme.scaled(68), copy.implicitHeight + Theme.scaled(22))
    color: Theme.surfaceStrong
    Accessible.role: Accessible.StatusBar
    Accessible.name: lead()
    Accessible.description: detail()

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.stroke
    }

    Row {
        id: stack
        x: Theme.scaled(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: -Theme.scaled(10)
        Repeater {
            model: root.rows.slice(0, 5)
            delegate: Rectangle {
                id: chip
                required property var modelData
                width: Theme.scaled(36)
                height: width
                radius: Theme.chipRadius + 2
                color: Theme.background
                border.width: 1
                border.color: Theme.hairlineSoft
                AppIcon {
                    anchors.centerIn: parent
                    app: Software.appsByAttribute[chip.modelData.attribute] || null
                    size: Theme.scaled(30)
                }
                Rectangle {
                    visible: chip.modelData.action === "remove"
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -Theme.scaled(3)
                    width: Theme.scaled(16)
                    height: width
                    radius: width / 2
                    color: Theme.red
                    Sym {
                        anchors.centerIn: parent
                        name: "minus"
                        size: Theme.iconTiny
                        color: "#ffffff"
                    }
                }
            }
        }
    }

    Column {
        id: copy
        anchors.left: stack.right
        anchors.leftMargin: Theme.scaled(22)
        anchors.right: buttons.left
        anchors.rightMargin: Theme.scaled(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(3)
        Row {
            width: parent.width
            spacing: Theme.scaled(8)
            Spinner {
                visible: root.busy
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accentText
            }
            Sym {
                visible: !root.busy && (root.phase === "done" || root.problem)
                anchors.verticalCenter: parent.verticalCenter
                name: root.problem ? "alert-triangle" : "circle-check"
                size: Theme.iconSmall
                color: root.problem ? Theme.amber : Theme.ok
            }
            Text {
                objectName: "softwareQueueTitle"
                width: parent.width - x
                text: root.lead()
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        Text {
            objectName: "softwareQueueDetail"
            width: parent.width
            text: root.detail()
            color: root.phase === "failed" || (root.phase === "idle" && root.blocked === "" && Software.flowError !== "") ? Theme.redText
                : root.problem ? Theme.amber : Theme.textDim
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.secondary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Rectangle {
            id: bar
            objectName: "softwareQueueProgress"
            visible: root.phase === "preparing" || root.phase === "installing"
            width: Math.min(parent.width, Theme.scaled(420))
            height: Theme.scaled(5)
            radius: height / 2
            color: Theme.stroke
            clip: true
            Accessible.role: Accessible.ProgressBar
            Accessible.name: I18n.tr("Progress")
            Rectangle {
                id: fill
                readonly property bool measured: root.phase === "preparing" && root.progress.fraction >= 0
                height: parent.height
                radius: height / 2
                color: Theme.accent
                width: measured ? parent.width * root.progress.fraction : parent.width * 0.3
                x: measured ? 0 : sweep.position * (parent.width * 1.3) - parent.width * 0.3
                Behavior on width {
                    enabled: fill.measured
                    NumberAnimation { duration: Theme.chipFadeDuration }
                }
            }
            // Indeterminate: a short sweep, only while open and moving is allowed.
            NumberAnimation {
                id: sweep
                property real position: 0
                target: sweep
                property: "position"
                from: 0
                to: 1
                duration: 1400
                loops: Animation.Infinite
                running: !fill.measured && bar.visible && Software.open && !Theme.reducedMotion
            }
        }
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: Theme.scaled(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.scaled(8)

        SoftwareButton {
            objectName: "softwareQueueClear"
            visible: root.phase === "idle" || root.phase === "blocked"
            quiet: true
            text: I18n.tr("Clear")
            onTriggered: Software.clearQueue()
        }
        SoftwareButton {
            objectName: "softwareQueueDetails"
            visible: ["preparing", "installing", "failed"].includes(root.phase)
                || (root.phase === "idle" && ["busy", "pending", "restart"].includes(root.blocked))
            quiet: true
            text: root.phase === "idle" ? I18n.tr("Software Update…") : I18n.tr("Details")
            onTriggered: Software.openSoftwareUpdate()
        }
        SoftwareButton {
            objectName: "softwareQueueCancel"
            visible: root.phase === "ready"
            quiet: true
            enabled: !Updates.requestPending && Updates.actions.discard
            text: I18n.tr("Cancel")
            accessibleName: I18n.tr("Cancel this change")
            onTriggered: Software.cancelChange()
        }
        SoftwareButton {
            objectName: "softwareQueueDismiss"
            visible: root.phase === "done" || root.phase === "failed"
            quiet: true
            text: I18n.tr("Dismiss")
            onTriggered: Software.dismiss()
        }
        SoftwareButton {
            objectName: "softwareQueuePrimary"
            visible: root.phase !== "checking" && root.phase !== "authorizing" && root.phase !== "preparing"
                && root.phase !== "installing" && !(root.phase === "done" && root.openable.length === 0)
            big: true
            primary: true
            glyph: root.confirming ? "lock" : ""
            busy: root.phase === "ready" && Updates.requestPending
            enabled: root.phase === "idle" ? root.blocked === "" && Software.loaded && root.queueState.state !== "blocked"
                : root.phase === "ready" ? !Updates.requestPending && Updates.actions.apply
                : true
            text: root.phase === "blocked" ? (root.queueState.installs > root.queueState.blocked.length || root.queueState.removals > 0
                    ? I18n.tr("Install the others") : I18n.tr("Remove from list"))
                : root.phase === "ready" ? (Updates.requestPending ? I18n.tr("Waiting for authorization…") : I18n.tr("Install now"))
                : root.phase === "done" ? I18n.format("Open %1", [root.openable.length > 0 ? root.openable[0].name : ""])
                : root.phase === "failed" ? I18n.tr("Try again")
                : root.removals.length === 0 ? (root.installs.length === 1 ? I18n.tr("Install 1 app") : I18n.format("Install %1 apps", [root.installs.length]))
                : root.installs.length === 0 ? (root.removals.length === 1 ? I18n.tr("Remove 1 app") : I18n.format("Remove %1 apps", [root.removals.length]))
                : I18n.format("Apply %1 changes", [root.rows.length])
            onTriggered: {
                if (root.phase === "blocked") {
                    const others = root.queueState.installs > root.queueState.blocked.length || root.queueState.removals > 0;
                    Software.dropBlocked();
                    if (others)
                        Software.install();
                } else if (root.phase === "ready") {
                    Software.confirm();
                } else if (root.phase === "done") {
                    Software.openApplication(root.openable[0]);
                } else if (root.phase === "failed") {
                    Software.retry();
                } else {
                    Software.install();
                }
            }
        }
    }
}
