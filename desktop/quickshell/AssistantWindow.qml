pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Common"
import "Assistant"
import "Common/AssistantHelpers.js" as AssistantHelpers

// The Cybex OS Assistant on screen (docs/assistant.md): the character, and the
// box under it — the composer, the working box or the reply.
//
// One overlay surface covering the output the character is on, taking input
// only on the character and the box. A layer surface belongs to one output,
// so a drag that ends on another display moves the character there and the
// surface follows. The layer is neither blurred nor animated by Hyprland
// (looknfeel.lua), which is what makes a full-output surface affordable.
//
// Resting the pointer on him shows his status (Settings: assistantHover);
// a click or Super+I opens the box and gives it the keyboard. A click or
// Super+I on a closed box starts a new conversation (Assistant.openFresh).
//
// He keeps out of the way: dragged near a corner or side he lands there,
// pushed past a side edge he tucks away with only his hat showing, and a
// pointer that sweeps over him without stopping makes him fade and lets its
// clicks through to the window underneath (assistantFade).
PanelWindow {
    id: root

    readonly property real size: Assistant.characterSize
    // The bar's band at the top, kept clear by the default place and the box.
    readonly property real topReserve: Settings.position === "top"
        ? Theme.barHeight + Theme.barTopMargin : 0
    readonly property var resting: Assistant.restingPlace(root.width, root.height)
    // One Wiz at a time: while the welcome guide covers the screen, its own
    // Wiz stands in for this one, which is hidden and takes no input.
    readonly property bool covered: Welcome.coversAssistant
    readonly property string tuck: Settings.assistantTuck

    property bool dragging: false
    // A button went down on the character and has not come up yet.
    property bool pressing: false
    property real dragX: 0
    property real dragY: 0
    // Both at once, once per pointer move: Wiz reads its velocity from this.
    property point dragPoint: Qt.point(0, 0)
    property point pressWindow: Qt.point(0, 0)
    property point pressBubble: Qt.point(0, 0)
    // Shown, he flies in from just past the top-right corner to his place.
    // A surface maps before the compositor sizes it, so until the size has
    // arrived he waits in that corner and nothing animates: otherwise he
    // would sweep in from the left edge, where a zero width puts him.
    property bool entered: false
    property bool settled: false
    readonly property real bubbleX: dragging ? dragX : !entered ? root.width
        : tuck !== "" ? AssistantHelpers.tuckedX(tuck, root.size, root.width) : resting.x
    readonly property real bubbleY: dragging ? dragY : entered ? resting.y : -root.size
    readonly property var dockPlace: AssistantHelpers.dockPlacement(
        { x: root.bubbleX, y: root.bubbleY }, root.size,
        { width: root.width, height: root.height }, Theme.scaled(360), root.topReserve)

    // One surface at a time: History wins, then another conversation read
    // while a question runs, the working box, the reply and the composer.
    readonly property bool showHistory: Assistant.historyOpen
    readonly property bool readingOther: Assistant.busy && Assistant.composing
        && Assistant.continuing !== "" && Assistant.continuing !== Assistant.busyConversation
    readonly property bool showWorking: Assistant.busy && !Assistant.tucked && !showHistory && !readingOther
    readonly property bool showReply: Assistant.replyOpen && !Assistant.composing && !Assistant.busy
        && !showHistory
    readonly property bool showComposer: Assistant.composing && !showHistory
        && (!Assistant.busy || readingOther)
    readonly property bool boxOpen: (showComposer || showWorking || showReply || showHistory)
        && !Assistant.capturing && !covered && tuck === ""
    // The box steps out of the way while the character is dragged.
    readonly property bool dockShown: boxOpen && !dragging

    // ---- the wide view ------------------------------------------------------------
    // Long answers, and a conversation being read, open beside Wiz in the wide
    // view once it is chosen (Expand); its edge drags to resize it.
    property real wideWidth: Settings.assistantExpandedWidth
    readonly property bool wide: Settings.assistantExpanded
        && (showReply || showHistory || (showComposer && Assistant.continuing !== ""))
    readonly property var widePlace: AssistantHelpers.expandedPlacement({ x: root.bubbleX, y: root.bubbleY },
        root.size, { width: root.width, height: root.height }, Theme.scaled(root.wideWidth), root.topReserve)

    // The keyboard goes to the box only when it was asked for. Exclusive
    // first, so the compositor hands it over without a click; then OnDemand
    // under a focus grab, so a click anywhere else takes it back (the
    // launcher's arrangement, LauncherWindow.qml).
    readonly property bool keyboardWanted: Assistant.focusRequested && !covered
        && (showComposer || showHistory || showWorking)
    readonly property bool keyboardActive: root.contentItem.Window.active
    property bool grabReady: false
    onKeyboardActiveChanged: {
        if (keyboardActive && keyboardWanted)
            grabReady = true;
    }
    onKeyboardWantedChanged: {
        if (!keyboardWanted)
            grabReady = false;
        else if (keyboardActive)
            grabReady = true;
    }

    screen: Assistant.screen
    // Not root.screen: the window writes that back as it maps, which would
    // loop through this binding.
    visible: Assistant.shown && Assistant.screen !== null
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-assistant"
    // Follows the open box, not its drawing: a drag that hides the box
    // must not change the surface's keyboard mode under the held button.
    WlrLayershell.keyboardFocus: !root.boxOpen ? WlrKeyboardFocus.None
        : root.keyboardWanted && !grab.active ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.OnDemand

    mask: Region {
        item: characterMask

        Region {
            item: dockMask
        }

        Region {
            item: pressMask
        }

        Region {
            item: statusMask
        }

        // Nothing at all while covered: an empty region intersected last.
        Region {
            intersection: root.covered ? Intersection.Intersect : Intersection.Combine
        }
    }

    HyprlandFocusGrab {
        id: grab
        active: root.keyboardWanted && root.grabReady && root.visible
        windows: [root]
        onCleared: {
            root.grabReady = false;
            Assistant.focusRequested = false;
            Assistant.focusLost();
        }
    }

    // The welcome guide's Wiz hopped here and hands over: this one lands.
    // Later, once showing him has made him live.
    Connections {
        target: Welcome
        function onAssistantArrived() {
            Qt.callLater(character.arrive);
        }
    }

    // ---- entrance ------------------------------------------------------------
    Component.onCompleted: Qt.callLater(root.enter)
    onVisibleChanged: {
        if (!visible) {
            // Animation off first, so he jumps back to the corner unseen.
            settled = false;
            entered = false;
            faded = false;
        }
        Qt.callLater(root.enter);
    }
    onWidthChanged: Qt.callLater(root.enter)
    onHeightChanged: Qt.callLater(root.enter)

    function enter() {
        if (entered || !visible || width <= 0 || height <= 0)
            return;
        if (covered) {
            // The welcome guide's own Wiz hops to this place, so this one is
            // there already when he is uncovered.
            entered = true;
            settled = true;
        } else {
            // Animation on first, so the move to his place is the flight.
            settled = true;
            entered = true;
        }
    }

    // ---- hover ---------------------------------------------------------------
    readonly property bool pointerInside: characterHover.hovered || dockHover.hovered
    // The status line while the pointer rests on him (assistantHover
    // "status"); Assistant.statusShown reports whether it is on screen.
    property bool statusShown: false
    // A sweep is two quick samples in a row; a pointer warped in is one.
    property int fastSamples: 0
    // He has faded and lets clicks through to the window underneath.
    property bool faded: false
    property point lastHover: Qt.point(0, 0)
    property double lastHoverAt: 0

    // Resting means staying put this long; a pass does nothing.
    Timer {
        id: rest
        interval: 520
        onTriggered: {
            if (!characterHover.hovered || root.dragging || root.boxOpen)
                return;
            if (Settings.assistantHover === "open" && !Assistant.busy && !Assistant.replyOpen
                    && !Assistant.composing && !Assistant.historyOpen && root.tuck === "")
                Assistant.openComposer(false);
            else if (Settings.assistantHover !== "nothing" || root.tuck !== "")
                root.statusShown = true;
        }
    }

    Timer {
        id: leaveGrace
        interval: 700
        onTriggered: {
            if (!root.pointerInside)
                Assistant.hoverEnded();
        }
    }

    onPointerInsideChanged: {
        if (pointerInside)
            leaveGrace.stop();
        else
            leaveGrace.restart();
    }

    function pointerMoved(point) {
        const now = Date.now();
        // The first point after entering only sets where he was entered.
        if (lastHoverAt === 0) {
            lastHover = point;
            lastHoverAt = now;
            return;
        }
        const dx = point.x - lastHover.x;
        const dy = point.y - lastHover.y;
        const elapsed = Math.max(1, now - lastHoverAt);
        const speed = Math.sqrt(dx * dx + dy * dy) / elapsed;
        lastHover = point;
        lastHoverAt = now;
        if (Math.abs(dx) + Math.abs(dy) > 2) {
            rest.restart();
            statusShown = false;
        }
        fastSamples = speed > 0.9 && elapsed < 60 ? fastSamples + 1 : 0;
        // A sweep across him on the way somewhere: step aside.
        if (Settings.assistantFade && fastSamples >= 2 && !boxOpen && !dragging && !pressing && tuck === ""
                && !Assistant.waiting)
            fade();
    }

    function fade() {
        faded = true;
        rest.stop();
        statusShown = false;
        cursorProbe.poll();
    }

    // ---- where the pointer is while he is faded --------------------------------------
    // Faded, he takes no input, so the pointer is read from Hyprland: he
    // returns once it leaves his surroundings, or rests on him.
    QtObject {
        id: cursorProbe
        property double stillSince: 0
        property point last: Qt.point(-1, -1)

        function poll() {
            if (root.faded && !cursorReader.running)
                cursorReader.running = true;
        }

        function seen(x, y) {
            if (!root.faded || !root.screen)
                return;
            const localX = x - root.screen.x;
            const localY = y - root.screen.y;
            const margin = Theme.scaled(48);
            const near = localX > character.x - margin && localX < character.x + root.size + margin
                && localY > character.y - margin && localY < character.y + root.size + margin;
            const over = localX > character.x && localX < character.x + root.size
                && localY > character.y && localY < character.y + root.size;
            const moved = Math.abs(localX - last.x) + Math.abs(localY - last.y) > 3;
            last = Qt.point(localX, localY);
            if (moved || !over)
                stillSince = Date.now();
            if (!near || (over && Date.now() - stillSince > 500)) {
                root.faded = false;
                if (over)
                    rest.restart();
            }
        }
    }

    Process {
        id: cursorReader
        command: ["hyprctl", "cursorpos"]
        stdout: SplitParser {
            onRead: line => {
                const match = /^\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/.exec(line);
                if (match)
                    cursorProbe.seen(parseFloat(match[1]), parseFloat(match[2]));
            }
        }
    }

    Timer {
        interval: 90
        repeat: true
        running: root.faded && root.visible
        onTriggered: cursorProbe.poll()
    }

    // ---- snapping and tucking --------------------------------------------------------
    readonly property var zones: AssistantHelpers.snapZones({ width: root.width, height: root.height },
        root.size, root.topReserve)
    readonly property var snapZone: dragging ? AssistantHelpers.snapTarget({ x: dragX, y: dragY }, zones) : null
    readonly property string tuckWanted: dragging
        ? AssistantHelpers.tuckSide(lastPointer.x, pressWindow.x - pressBubble.x, root.size, root.width) : ""

    Item {
        id: stage
        anchors.fill: parent
        // Hidden for the screenshot it is about to take.
        opacity: Assistant.capturing ? 0 : 1
        visible: !root.covered

        // Where a drop would land, shown only while dragging.
        Repeater {
            model: root.dragging && root.tuckWanted === "" ? root.zones : []

            delegate: Rectangle {
                required property var modelData
                readonly property bool target: root.snapZone !== null && root.snapZone.id === modelData.id
                x: modelData.x - Theme.scaled(8)
                y: modelData.y - Theme.scaled(8)
                width: root.size + Theme.scaled(16)
                height: root.size + Theme.scaled(16)
                radius: Theme.scaled(14)
                color: target ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.06)
                border.width: 1.5
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, target ? 0.9 : 0.45)
            }
        }

        // The edge he would tuck behind.
        Rectangle {
            visible: root.dragging && root.tuckWanted !== ""
            x: root.tuckWanted === "left" ? 0 : root.width - width
            y: 0
            width: Theme.scaled(6)
            height: root.height
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
        }

        // A file dragged over him: drop it to attach.
        Rectangle {
            id: dropRing
            visible: characterDrop.containsDrag
            x: character.x - Theme.scaled(8)
            y: character.y - Theme.scaled(8)
            width: root.size + Theme.scaled(16)
            height: width
            radius: width / 2
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
            border.width: 2
            border.color: Theme.accent
        }

        // ---- the character ------------------------------------------------------
        Wiz {
            id: character
            x: root.bubbleX
            y: root.bubbleY
            width: root.size
            height: root.size
            pose: Assistant.pose
            level: composer.level
            recording: Assistant.listening
            hovered: characterHover.hovered
            unread: Assistant.unread
            boxAbove: root.dockPlace.above
            opacity: root.faded ? 0.22 : 1
            rotation: root.tuck === "left" ? 12 : root.tuck === "right" ? -12 : 0
            scale: dragArea.pressed && !root.dragging ? 0.94 : root.dragging ? 1.06 : 1
            dragPoint: root.dragPoint
            grab: Qt.point(root.pressWindow.x - root.pressBubble.x, root.pressWindow.y - root.pressBubble.y)
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("Cybex OS Assistant")
            Accessible.description: Assistant.busy ? I18n.tr("Working. Click to tuck the box away.")
                : I18n.tr("Click to ask a question. Drag to move.")

            Behavior on x {
                enabled: root.settled && !root.dragging && !Theme.reducedMotion
                NumberAnimation { duration: Theme.expandDuration; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: root.settled && !root.dragging && !Theme.reducedMotion
                NumberAnimation { duration: Theme.expandDuration; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reducedMotion
                NumberAnimation {
                    duration: Theme.pressDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.springCurve
                }
            }
            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: Theme.chipFadeDuration }
            }
            Behavior on rotation {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: Theme.expandDuration; easing.type: Easing.OutCubic }
            }

            HoverHandler {
                id: characterHover
                onHoveredChanged: {
                    root.lastHoverAt = 0;
                    root.fastSamples = 0;
                    if (hovered) {
                        rest.restart();
                    } else {
                        rest.stop();
                        root.statusShown = false;
                    }
                }
                onPointChanged: {
                    character.lookX = AssistantHelpers.clamp(
                        (point.position.x - character.width / 2) / (character.width / 2), -1, 1);
                    character.lookY = AssistantHelpers.clamp(
                        (point.position.y - character.height / 2) / (character.height / 2), -1, 1);
                    root.pointerMoved(point.position);
                }
            }

            DropArea {
                id: characterDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                onDropped: drop => {
                    if (drop.hasUrls) {
                        Assistant.attachUrls(drop.urls);
                        drop.accept();
                    }
                }
            }
        }

        // "Drop to attach", beside the ring.
        AssistantSurface {
            visible: characterDrop.containsDrag
            x: AssistantHelpers.clamp(character.x + root.size / 2 - width / 2, AssistantHelpers.EDGE,
                root.width - width - AssistantHelpers.EDGE)
            y: character.y + root.size + Theme.scaled(12)
            width: dropLabel.implicitWidth + Theme.scaled(20)
            padding: Theme.scaled(8)

            Text {
                id: dropLabel
                text: I18n.tr("Drop to attach")
                color: Theme.textHi
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                font.weight: Theme.weightSemibold
            }
        }

        // Keep pointer coordinates on the stationary output, independent of
        // the character's movement, press scale and playful drag rotation.
        // Moving the MouseArea with the character feeds those transforms back
        // into its local mouse coordinates and can reduce a drag to a wobble.
        MouseArea {
            id: dragArea
            anchors.fill: parent
            preventStealing: true
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

            onPressed: mouse => {
                const local = character.mapFromItem(dragArea, mouse.x, mouse.y);
                if (!character.contains(local) || root.faded) {
                    // A press that never came up (released on another
                    // output) leaves no full-output region behind.
                    root.pressing = false;
                    mouse.accepted = false;
                    return;
                }
                root.pressing = true;
                root.statusShown = false;
                root.pressWindow = Qt.point(mouse.x, mouse.y);
                root.pressBubble = Qt.point(character.x, character.y);
                root.lastPointer = root.pressWindow;
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                // In window coordinates; the press keeps the pointer, so
                // positions beyond this output still arrive here.
                const dx = mouse.x - root.pressWindow.x;
                const dy = mouse.y - root.pressWindow.y;
                if (!root.dragging && !AssistantHelpers.dragged(dx, dy))
                    return;
                if (!root.dragging) {
                    root.dragX = root.pressBubble.x;
                    root.dragY = root.pressBubble.y;
                    root.dragging = true;
                    Assistant.dragging = true;
                    rest.stop();
                }
                root.dragX = AssistantHelpers.clamp(root.pressBubble.x + dx, -root.size * 0.6,
                    root.width - root.size * 0.4);
                root.dragY = AssistantHelpers.clamp(root.pressBubble.y + dy, 0, root.height - root.size);
                root.dragPoint = Qt.point(root.dragX, root.dragY);
                root.lastPointer = Qt.point(mouse.x, mouse.y);
            }
            onReleased: {
                root.pressing = false;
                if (root.dragging)
                    root.finishDrag();
                else
                    Assistant.characterClicked();
            }
            onCanceled: {
                root.pressing = false;
                if (root.dragging)
                    root.finishDrag();
            }
        }

        // ---- the status line ---------------------------------------------------
        AssistantStatus {
            id: statusCard
            readonly property bool shown: root.statusShown && !root.boxOpen && !root.dragging && !root.faded
            onShownChanged: Assistant.statusShown = shown
            width: Math.min(Theme.scaled(240), root.width - AssistantHelpers.EDGE * 2)
            x: AssistantHelpers.clamp(character.x + root.size / 2 - width / 2, AssistantHelpers.EDGE,
                root.width - width - AssistantHelpers.EDGE)
            y: root.dockPlace.above ? character.y - height - Theme.scaled(8) : character.y + root.size + Theme.scaled(8)
            opacity: shown ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: Theme.popoutFadeInDuration }
            }

            HoverHandler {
                id: statusHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.statusShown = false;
                    Assistant.characterClicked();
                }
            }
        }

        // ---- the box ----------------------------------------------------------
        Item {
            id: dock

            readonly property Item current: root.showHistory ? history
                : root.showWorking ? working
                : root.showReply ? replyCard : root.showComposer ? composer : null
            readonly property real room: root.wide ? root.widePlace.height : root.dockPlace.room

            x: root.wide ? root.widePlace.x : root.dockPlace.x
            width: root.wide ? root.widePlace.width : root.dockPlace.width
            height: current ? current.height : 0
            y: root.wide ? root.widePlace.y
                : root.dockPlace.above ? root.dockPlace.anchorY - height : root.dockPlace.anchorY
            opacity: root.dockShown ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: Theme.popoutFadeInDuration }
            }

            HoverHandler {
                id: dockHover
            }

            AssistantComposer {
                id: composer
                width: parent.width
                visible: root.showComposer
                room: dock.room
            }

            AssistantHistory {
                id: history
                width: parent.width
                visible: root.showHistory
                room: dock.room
            }

            AssistantWorking {
                id: working
                width: parent.width
                visible: root.showWorking
                room: dock.room
            }

            AssistantReply {
                id: replyCard
                width: parent.width
                visible: root.showReply
                room: dock.room
            }

            // The wide view's inner edge: drag to make it wider or narrower.
            Rectangle {
                visible: root.wide
                x: root.widePlace.onLeft ? -Theme.scaled(9) : parent.width + Theme.scaled(4)
                y: Math.round(parent.height / 2 - height / 2)
                width: Theme.scaled(5)
                height: Theme.scaled(44)
                radius: width / 2
                color: resizeArea.containsMouse || resizeArea.pressed ? Theme.textMid : Theme.hairline

                MouseArea {
                    id: resizeArea
                    anchors.fill: parent
                    anchors.margins: -Theme.scaled(6)
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor
                    property real startX: 0
                    property real startWidth: 0
                    onPressed: mouse => {
                        startX = mapToItem(stage, mouse.x, 0).x;
                        startWidth = root.wideWidth;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        const moved = (mapToItem(stage, mouse.x, 0).x - startX) / Theme.scaled(1);
                        root.wideWidth = AssistantHelpers.clamp(startWidth + (root.widePlace.onLeft ? -moved : moved),
                            420, 1200);
                    }
                    onReleased: Settings.set("assistantExpandedWidth", Math.round(root.wideWidth))
                }
            }
        }

        // What the input mask admits of the box: nothing while it is hidden.
        Item {
            id: dockMask
            x: dock.x - (root.wide ? Theme.scaled(16) : 0)
            y: dock.y
            width: root.dockShown ? dock.width + (root.wide ? Theme.scaled(32) : 0) : 0
            height: root.dockShown ? dock.height : 0
        }

        // The character's own region; none while he is faded, so clicks reach
        // the window underneath.
        Item {
            id: characterMask
            x: character.x
            y: character.y
            width: root.faded ? 0 : character.width
            height: root.faded ? 0 : character.height
        }

        Item {
            id: statusMask
            x: statusCard.x
            y: statusCard.y
            width: statusCard.shown ? statusCard.width : 0
            height: statusCard.shown ? statusCard.height : 0
        }

        // While the button is held the whole output takes the pointer, so
        // every motion of a drag arrives here even before the character's
        // own region has caught up with the pointer.
        Item {
            id: pressMask
            width: root.pressing ? stage.width : 0
            height: root.pressing ? stage.height : 0
        }
    }

    // The resize handle follows the setting when it changes elsewhere.
    Connections {
        target: Settings
        function onAssistantExpandedWidthChanged() {
            root.wideWidth = Settings.assistantExpandedWidth;
        }
    }

    property point lastPointer: Qt.point(0, 0)

    // A drop on this output stays here, or lands in a corner or side zone
    // near it, or tucks him behind the side edge it went past. One past the
    // output's edge onto another display lands there, under the pointer.
    function finishDrag() {
        const outputs = Quickshell.screens.map(s => ({ x: s.x, y: s.y, width: s.width, height: s.height }));
        const globalX = root.screen.x + root.lastPointer.x;
        const globalY = root.screen.y + root.lastPointer.y;
        const index = AssistantHelpers.outputAt(outputs, globalX, globalY);
        const target = index >= 0 ? Quickshell.screens[index] : root.screen;
        const grabX = root.pressWindow.x - root.pressBubble.x;
        const grabY = root.pressWindow.y - root.pressBubble.y;
        if (target !== root.screen) {
            if (Settings.assistantTuck !== "")
                Settings.set("assistantTuck", "");
            Assistant.moveTo(target.name,
                AssistantHelpers.clamp(globalX - target.x - grabX, 0, target.width - root.size),
                AssistantHelpers.clamp(globalY - target.y - grabY, 0, target.height - root.size));
        } else if (root.tuckWanted !== "") {
            Assistant.moveTo(root.screen.name, root.tuckWanted === "left" ? 0 : root.width - root.size,
                root.dragY);
            Assistant.tuckTo(root.tuckWanted);
        } else {
            if (Settings.assistantTuck !== "")
                Settings.set("assistantTuck", "");
            const zone = root.snapZone;
            Assistant.moveTo(root.screen.name, zone ? zone.x : AssistantHelpers.clamp(root.dragX, 0,
                root.width - root.size), zone ? zone.y : root.dragY);
        }
        root.dragging = false;
        Assistant.dragging = false;
    }
}
