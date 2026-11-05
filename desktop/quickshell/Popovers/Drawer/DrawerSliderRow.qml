import QtQuick
import "../../Common"
import ".."

// A drawer slider row: a filled glyph in a fixed lane, the shared HSlider,
// and an optional Geist Mono readout. Overview stacks two of these (light and
// volume); Sound reuses the shape with the readout on.
//
// Without its device (`ready` false) the control fades and hides its knob,
// so it never looks like a live slider at 0 %; `reason` then says why at full
// contrast, with `recoveryText` as the way to fix it (docs/shell-states.md:
// the reason and its recovery action stay enabled). While ready, `detail`
// can name what the slider drives ("Speakers").
Item {
    id: root

    property string glyph: "sunny"
    property real value: 0
    property bool ready: true
    property bool showValue: false
    property string accessibleName: "Slider"
    property string detail: ""
    property string reason: ""
    property string recoveryText: ""
    signal moved(real value)
    signal recovery()

    readonly property bool explained: !ready && reason !== ""
    readonly property string note: explained ? reason : ready ? detail : ""

    width: parent ? parent.width : 0
    height: implicitHeight
    implicitHeight: control.height
        + (note !== "" ? noteLine.implicitHeight + Theme.scaled(2) : 0)

    Item {
        id: control
        width: parent.width
        height: Theme.inlineActionHeight
        opacity: root.ready ? 1 : 0.4

        Sym {
            id: mark
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            name: root.glyph
            size: Theme.iconLarge
            color: Theme.textMid
        }

        HSlider {
            anchors.left: mark.right
            anchors.leftMargin: Theme.controlSpacing
            anchors.right: readout.visible ? readout.left : parent.right
            anchors.rightMargin: readout.visible ? Theme.controlSpacing : 4
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            value: root.ready ? root.value : 0
            enabled: root.ready
            dimmed: !root.ready
            accessibleName: root.accessibleName
            onMoved: v => root.moved(v)
        }

        Text {
            id: readout
            visible: root.showValue
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(Theme.scaled(36), implicitWidth)
            horizontalAlignment: Text.AlignRight
            // No device, no level: a dash rather than a confident 0 %.
            text: root.ready ? Math.round(root.value * 100) + "%" : "–"
            font.family: Theme.fontNumeric
            font.pixelSize: Theme.typography.metadata
            font.weight: Theme.weightSemibold
            font.features: Theme.tabularNumberFeatures
            color: Theme.textMid
        }
    }

    // Under the track, on the slider's own start edge. Outside the faded
    // control, so a reason reads at full contrast and its link stays live.
    Flow {
        id: noteLine
        visible: root.note !== ""
        anchors.top: control.bottom
        anchors.topMargin: Theme.scaled(2)
        x: 4 + Theme.iconLarge + Theme.controlSpacing
        width: Math.max(0, parent.width - x)
        spacing: Theme.iconTextSpacing

        Text {
            width: Math.min(implicitWidth, noteLine.width)
            text: root.note
            wrapMode: Text.Wrap
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            font.weight: root.explained ? Theme.weightMedium : Theme.weightRegular
            color: root.explained ? Theme.textHi : Theme.textMid
        }

        Text {
            visible: root.explained && root.recoveryText !== ""
            text: "·"
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.metadata
            color: Theme.textMid
            Accessible.ignored: true
        }

        LinkText {
            visible: root.explained && root.recoveryText !== ""
            text: root.recoveryText
            font.pixelSize: Theme.typography.metadata
            onClicked: root.recovery()
        }
    }
}
