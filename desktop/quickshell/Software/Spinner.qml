import QtQuick
import "../Common"

// A busy indicator that turns only while Software is open and motion is on.
Sym {
    id: root

    name: "loader-2"
    size: Theme.iconSmall

    RotationAnimator on rotation {
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.visible && Software.open && !Theme.reducedMotion
    }
}
