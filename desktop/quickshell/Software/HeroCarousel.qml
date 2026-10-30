pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SoftwareHelpers.js" as Helpers

// The featured apps, one at a time, in their own brand colours. It turns by
// itself only while Software is open, the pointer and focus are elsewhere
// and motion is on. Screenshots come from Flathub on an app's page only: a
// slide shows one once that page has loaded it, else the app's icon is the art.
FocusScope {
    id: root

    property var apps: []
    property int current: 0
    readonly property int count: apps.length

    implicitHeight: Theme.scaled(224)
    activeFocusOnTab: true
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("Featured apps")

    function step(delta) {
        if (count > 0)
            current = (current + delta + count) % count;
    }
    onCountChanged: current = Math.min(current, Math.max(0, count - 1))

    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)

    HoverHandler { id: hover }
    Timer {
        interval: 8000
        repeat: true
        running: Software.open && root.visible && root.count > 1 && !hover.hovered
            && !root.activeFocus && !Theme.reducedMotion
        onTriggered: root.step(1)
    }

    Repeater {
        model: root.apps
        delegate: Rectangle {
            id: slide
            required property var modelData
            required property int index
            readonly property bool active: index === root.current
            readonly property color base: Helpers.brand(modelData, Software.category(modelData), Theme.dark)
            readonly property bool darkText: Helpers.darkInk(base.toString())
            readonly property color ink: darkText ? "#1d1b26" : "#f7f5f0"
            readonly property string shot: Software.shownScreenshot(modelData)
            readonly property real artCentre: width - Math.min(height * 0.95, width * 0.24)

            anchors.fill: parent
            radius: Theme.chipRadius + 7
            border.width: 1
            border.color: Theme.hairlineSoft
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: slide.base }
                GradientStop { position: 0.55; color: Helpers.mix(slide.base.toString(), slide.darkText ? "#ffffff" : "#000000", 0.08) }
                GradientStop { position: 1; color: Helpers.mix(slide.base.toString(), slide.darkText ? "#ffffff" : "#000000", 0.30) }
            }
            opacity: active ? 1 : 0
            visible: opacity > 0
            enabled: active
            Behavior on opacity {
                NumberAnimation { duration: Theme.surfaceDuration; easing.type: Easing.OutCubic }
            }

            // The art: a screenshot its page loaded, tilted, or the icon on
            // soft rings. Both stay inside the rounded slide.
            Repeater {
                model: slide.shot === "" ? [0.86, 0.62] : []
                delegate: Rectangle {
                    required property real modelData
                    width: slide.height * modelData
                    height: width
                    radius: width / 2
                    x: slide.artCentre - width / 2
                    y: (slide.height - height) / 2
                    color: Qt.rgba(slide.ink.r, slide.ink.g, slide.ink.b, modelData > 0.7 ? 0.05 : 0.07)
                }
            }
            AppIcon {
                visible: slide.shot === ""
                app: slide.modelData
                size: Theme.scaled(120)
                x: slide.artCentre - width / 2
                y: (slide.height - height) / 2
            }
            Item {
                visible: slide.shot !== ""
                height: slide.height - Theme.scaled(48)
                width: Math.min(slide.width * 0.46, height * 16 / 9)
                x: slide.width - width - Theme.scaled(30)
                y: (slide.height - height) / 2
                rotation: -3
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: Theme.scaled(8)
                    anchors.leftMargin: -Theme.scaled(3)
                    anchors.bottomMargin: -Theme.scaled(6)
                    radius: Theme.chipRadius + 3
                    color: Qt.rgba(0, 0, 0, 0.26)
                }
                MediaFrame {
                    anchors.fill: parent
                    radius: Theme.chipRadius + 3
                    source: slide.shot
                    sourceWidth: 1040
                }
            }

            Column {
                x: Theme.scaled(28)
                y: Theme.scaled(24)
                width: Math.min(parent.width * 0.5, Theme.scaled(440))
                spacing: Theme.scaled(8)
                Text {
                    text: I18n.tr("EDITOR'S PICK")
                    color: Qt.rgba(slide.ink.r, slide.ink.g, slide.ink.b, 0.72)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    font.weight: Theme.weightSemibold
                    font.letterSpacing: 1.6
                    textFormat: Text.PlainText
                }
                Row {
                    spacing: Theme.scaled(12)
                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        app: slide.modelData
                        size: Theme.scaled(44)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Theme.scaled(380))
                        text: slide.modelData.name || ""
                        color: slide.ink
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.display
                        font.weight: Theme.weightBold
                        font.letterSpacing: -0.6
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
                Text {
                    width: parent.width
                    text: slide.modelData.summary || ""
                    color: Qt.rgba(slide.ink.r, slide.ink.g, slide.ink.b, 0.82)
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.primary
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            Row {
                x: Theme.scaled(28)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.scaled(34)
                spacing: Theme.scaled(8)
                AppAction {
                    objectName: slide.active ? "softwareHeroInstall" : ""
                    app: slide.modelData
                    big: true
                    prominent: true
                    foreground: slide.ink
                }
                SoftwareButton {
                    objectName: slide.active ? "softwareHeroDetails" : ""
                    big: true
                    quiet: true
                    foreground: slide.ink
                    text: I18n.tr("Details")
                    accessibleName: I18n.format("Details about %1", [slide.modelData.name || ""])
                    onTriggered: Software.openApp(slide.modelData.id)
                }
            }
        }
    }

    Row {
        x: Theme.scaled(28)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.scaled(14)
        spacing: Theme.scaled(6)
        visible: root.count > 1
        Repeater {
            model: root.count
            delegate: Rectangle {
                id: dot
                required property int index
                readonly property var slideItem: root.apps[index]
                readonly property color ink: Helpers.darkInk(Helpers.brand(root.apps[root.current],
                    Software.category(root.apps[root.current]), Theme.dark)) ? "#1d1b26" : "#f7f5f0"
                width: index === root.current ? Theme.scaled(18) : Theme.scaled(7)
                height: Theme.scaled(7)
                radius: height / 2
                color: Qt.rgba(ink.r, ink.g, ink.b, index === root.current ? 0.9 : 0.32)
                Behavior on width {
                    NumberAnimation { duration: Theme.chipFadeDuration }
                }
                Accessible.role: Accessible.Button
                Accessible.name: I18n.format("Show %1", [(dot.slideItem || {}).name || ""])
                Accessible.onPressAction: root.current = dot.index
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.scaled(4)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.current = dot.index
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.activeFocus
        color: "transparent"
        radius: Theme.chipRadius + 7
        border.width: 2
        border.color: Theme.accentText
    }
}
