pragma Singleton
import QtQuick
import Quickshell

// Keyboard modality for focus rings (2026-11 state system,
// docs/shell-states.md). A ring is a promise about where the next key will
// act, so it shows only while the person is driving the shell from the
// keyboard: focus that moves without a pointer press just before it reveals
// rings, and the next pointer press hides them again. The first Tab after a
// click therefore always shows where it went.
//
// Plain Qt Quick Items carry no focus reason, so each window's
// FocusModalityObserver reports pointer presses and focus moves here. One
// value serves every window: the person has one pair of hands.
Singleton {
    id: root

    property bool keyboard: false

    function pointer() {
        if (root.keyboard)
            root.keyboard = false;
    }

    function key() {
        if (!root.keyboard)
            root.keyboard = true;
    }
}
