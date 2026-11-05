import QtQuick

// Reports a window's input modality to FocusModality. Place one as the last
// child of a window's content, filling it. It sees every pointer press first
// (it sits above everything) and declines it at once, so the press still
// reaches whatever is underneath; it never takes hover, wheel or keys.
//
// Focus that moves while no press happened in the last moment came from the
// keyboard (Tab, arrows, a shortcut) or from code acting on a key, and
// reveals focus rings. A window that is shown starts without them.
MouseArea {
    id: root

    anchors.fill: parent
    z: 1000000
    acceptedButtons: Qt.AllButtons
    hoverEnabled: false
    propagateComposedEvents: true
    // A MouseArea is never a tab stop; it is not an accessible control either.
    Accessible.ignored: true

    onPressed: mouse => {
        FocusModality.pointer();
        pointerQuiet.restart();
        mouse.accepted = false;
    }
    onWheel: wheel => {
        wheel.accepted = false;
    }

    Timer {
        id: pointerQuiet
        interval: 400
    }

    Connections {
        target: root.Window.window
        enabled: target !== null

        function onActiveFocusItemChanged() {
            const window = root.Window.window;
            if (!window || !window.active || pointerQuiet.running)
                return;
            if (window.activeFocusItem)
                FocusModality.key();
        }

        // A window coming up or regaining activation places its initial
        // focus itself; that is not the person navigating, so it shows no
        // ring until the first Tab or arrow move.
        function onVisibleChanged() {
            root.settle();
        }

        function onActiveChanged() {
            root.settle();
        }
    }

    function settle() {
        const window = root.Window.window;
        if (!window || !window.visible)
            return;
        FocusModality.pointer();
        pointerQuiet.restart();
    }
}
