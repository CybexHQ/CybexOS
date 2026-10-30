pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "Common"
import "Common/WindowCommands.js" as WindowCommands
import "Assistant" as Character
import "Welcome" as Guide

// The welcome guide fills the focused screen like the installer did: an
// overlay layer with the installer's palette, its 1280×800 canvas centred
// and zoomed by the installer's rule. While the person uses something the
// guide opened, or any window or shell surface appears, the guide steps
// aside and leaves a resume pill at the bottom of the screen. Closing the
// 1Password window the Connect step opened brings it back; Resume closes it.
//
// Leaving for the desktop closes the windows the Connect step's sign-ins
// opened, as their close buttons would. The guide stays up until they are
// gone, or two seconds: one that asks first, over unsaved work, still asks.
//
// One Wiz at a time: while the guide covers the screen, its own Wiz stands
// in for the assistant's, which AssistantWindow hides. Finishing hands him
// over. On the assistant's display, with motion, he shrinks and hops from
// Ready to the assistant's resting place while the guide fades, and the
// assistant's Wiz lands there. Otherwise the guide just closes and the
// assistant's Wiz lands where he is.
Scope {
    id: root
    readonly property Item contentItem: guide.contentItem
    property var closing: []
    readonly property bool closingWindows: closing.some(address => DesktopWorkspaces.isLive(address))
    readonly property bool shown: Welcome.open && !Welcome.aside || closingWindows
    // A peek shows the desktop as it is, the assistant's Wiz included.
    readonly property bool covering: root.shown && !view.peeking || Welcome.handOff === "flying"
    // Finished: the assistant's Wiz lands once nothing covers him any more.
    property bool arriving: false
    Binding { target: Welcome; property: "coversAssistant"; value: root.covering }
    onCoveringChanged: {
        if (root.covering || !root.arriving) return;
        root.arriving = false;
        Welcome.assistantArrived();
    }
    // Shell surfaces a shortcut can open over the guide. They are transient:
    // the guide comes back when they close, unless a window opened meanwhile.
    // Super+I counts: the assistant's box, or a question being recorded, and
    // the guide waits while the assistant works on what was asked.
    readonly property bool shellSurface: Launcher.open || Overview.open || Session.keysOpen
        || Assistant.composing && Assistant.focusRequested || Assistant.listening || Assistant.transcribing
    onShellSurfaceChanged: {
        if (shellSurface && root.shown) Welcome.stepAside(true);
        else if (!shellSurface && Welcome.aside && Welcome.asideTransient) resumeLater.restart();
    }
    Timer {
        id: resumeLater
        interval: 700
        onTriggered: {
            if (Welcome.aside && Welcome.asideTransient && !root.shellSurface && !Assistant.busy) Welcome.resume();
        }
    }
    Connections {
        target: Hyprland
        enabled: Welcome.hasHyprland && Welcome.open
        function onRawEvent(event) {
            if (event.name === "openwindow") {
                resumeLater.stop();
                Welcome.stepAside(false);
                Welcome.windowOpened(event.data);
            } else if (event.name === "closewindow") {
                Welcome.windowClosed(event.data);
            }
        }
    }
    Timer { id: closingDeadline; interval: 2000; onTriggered: root.closing = [] }
    Connections {
        target: Welcome
        // Each address is checked right before its dispatch: Hyprland closes
        // the active window for one it cannot find.
        function onCloseWindows(addresses) {
            if (!Welcome.hasHyprland) return;
            const live = addresses.filter(address => DesktopWorkspaces.isLive(address));
            for (const address of live) {
                const command = WindowCommands.closeWindow(address);
                if (command !== "") Hyprland.dispatch(command);
            }
            root.closing = live;
            if (live.length > 0) closingDeadline.restart();
        }
        function onOpenChanged() {
            if (Welcome.open) {
                root.cancelHandOff();
                guide.screen = Screens.byName(Welcome.screenName) ?? Screens.focused;
            }
            Qt.callLater(view.focusInitial);
        }
        function onPresent() { Qt.callLater(view.focusInitial); }
        function onFinishing() { root.handOver(); }
    }

    // ---- the hand-off ----------------------------------------------------------
    // Set once when it starts; the flight below reads them then.
    property point flightFrom: Qt.point(0, 0)
    property point flightTo: Qt.point(0, 0)
    property real flightApex: 0
    property real flightSize: 0
    property real flightScale: 1
    property int flightUp: 0
    property int flightDown: 0
    property string flightPose: "idle"
    function handOver() {
        root.arriving = true;
        const perch = view.perch;
        const output = guide.screen;
        if (!perch || !perch.visible || !perch.animated || !Assistant.shown || !output
                || Assistant.screenName !== output.name)
            return;
        const from = perch.mapToItem(guide.contentItem, 0, 0);
        const to = Assistant.restingPlace(guide.width, guide.height);
        // A hop: up to just above the higher end and down onto his place,
        // each half as long as a throw would take (the root of its height).
        const apex = Math.max(0, Math.min(from.y, to.y) - Guide.Kiosk.px(70));
        const rise = Math.sqrt(Math.max(1, from.y - apex));
        const fall = Math.sqrt(Math.max(1, to.y - apex));
        root.flightFrom = from;
        root.flightTo = Qt.point(to.x, to.y);
        root.flightApex = apex;
        root.flightSize = perch.width;
        root.flightScale = Assistant.characterSize / perch.width;
        root.flightUp = Math.round(880 * rise / (rise + fall));
        root.flightDown = 880 - root.flightUp;
        flyer.x = from.x;
        flyer.y = from.y;
        flyer.scale = 1;
        // The guide fades instead of waiting for Connect's windows to close.
        root.closing = [];
        closingDeadline.stop();
        // He takes off as he sat on Ready, and is happy on the way.
        root.flightPose = perch.pose;
        Welcome.handOff = "flying";
        root.flightPose = "happy";
        flight.restart();
    }
    // Both land at once, and the guide's Wiz goes a moment later, so the
    // swap to the assistant's surface shows no gap.
    function touchDown() {
        Welcome.handOff = "landed";
        (flyer.item as Character.Wiz)?.arrive();
        settle.restart();
    }
    function cancelHandOff() {
        flight.stop();
        settle.stop();
        root.arriving = false;
        Welcome.handOff = "";
        fader.opacity = 1;
    }
    Timer {
        id: settle
        interval: 160
        onTriggered: {
            Welcome.handOff = "";
            fader.opacity = 1;
        }
    }
    // Plain animations, not Animators: they finish on the GUI thread's clock
    // whether or not the window renders, so the guide never stays up.
    ParallelAnimation {
        id: flight
        NumberAnimation {
            target: flyer
            property: "x"
            from: root.flightFrom.x
            to: root.flightTo.x
            duration: root.flightUp + root.flightDown
        }
        SequentialAnimation {
            NumberAnimation {
                target: flyer
                property: "y"
                from: root.flightFrom.y
                to: root.flightApex
                duration: root.flightUp
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: flyer
                property: "y"
                from: root.flightApex
                to: root.flightTo.y
                duration: root.flightDown
                easing.type: Easing.InQuad
            }
        }
        NumberAnimation {
            target: flyer
            property: "scale"
            from: 1
            to: root.flightScale
            duration: root.flightUp + root.flightDown
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: fader
            property: "opacity"
            from: 1
            to: 0
            duration: 450
            easing.type: Easing.OutCubic
        }
        onFinished: root.touchDown()
    }

    PanelWindow {
        id: guide
        visible: root.shown || Welcome.handOff !== ""
        screen: Screens.focused
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-welcome"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible) Qt.callLater(view.focusInitial)
        Binding {
            target: Guide.Kiosk
            property: "zoom"
            value: Guide.Kiosk.zoomFor(guide.width, guide.height, guide.screen ? guide.screen.devicePixelRatio : 1)
        }
        // The guide, which fades out as Wiz leaves it.
        Item {
            id: fader
            anchors.fill: parent
            enabled: Welcome.handOff === ""
            // The installer's page colour beyond the canvas, gone while peeking.
            Rectangle {
                anchors.fill: parent
                color: Guide.Kiosk.bg
                opacity: view.peeking ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            Guide.WelcomeView {
                id: view
                x: Math.round((parent.width - width) / 2)
                y: Math.max(0, Math.round((parent.height - height) / 2))
            }
        }
        // Ready's Wiz on his way to the assistant's corner, drawn at his
        // perch's size and shrunk on the way: only moved, never redrawn.
        Loader {
            id: flyer
            active: Welcome.handOff !== ""
            width: root.flightSize
            height: root.flightSize
            transformOrigin: Item.TopLeft
            sourceComponent: Character.Wiz {
                objectName: "welcomeFlyer"
                pose: root.flightPose
            }
        }
    }

    PanelWindow {
        id: pill
        visible: Welcome.open && Welcome.aside
        screen: guide.screen
        anchors.bottom: true
        // PanelWindow.margins is a Quickshell group qmllint cannot resolve.
        // qmllint disable unqualified
        margins { bottom: Guide.Kiosk.px(28) }
        // qmllint enable unqualified
        implicitWidth: resume.width
        implicitHeight: resume.height
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-welcome-resume"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Guide.ResumePill { id: resume }
    }
}
