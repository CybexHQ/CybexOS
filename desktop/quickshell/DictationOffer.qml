pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "Common"
import "Common/SettingsHelpers.js" as SettingsHelpers
import "Popovers"
import "Settings" as SettingsUi

// After the first dictation that typed words (docs/dictation.md): offer the
// enhanced speech model and ask about a second language. It appears where the
// dictation pill was, once the words are typed, and takes the keyboard only
// when clicked, so the window you dictated into keeps its focus. Settings →
// Indicators → Dictation holds the same choices afterwards.
PanelWindow {
    id: root

    readonly property bool shown: Dictation.offerShown
    visible: shown || card.opacity > 0.001
    screen: Screens.focused
    readonly property bool atTop: Settings.osd === "top"
    readonly property int barClearance: Theme.barTopMargin + Theme.barHeight + 12
    readonly property bool sharesBarScreen: Screens.hasBar(root.screen)
    // Clear of the welcome guide's resume pill, which sits at the bottom
    // while the guide is set aside (WelcomeWindow.qml).
    readonly property int welcomeClearance: !atTop && Welcome.open && Welcome.aside ? Theme.scaled(56) : 0
    anchors {
        top: atTop
        bottom: !atTop
    }
    // qmllint disable unqualified
    margins {
        top: atTop && Settings.position === "top" && sharesBarScreen ? barClearance : 12
        bottom: (!atTop && Settings.position === "bottom" && sharesBarScreen ? barClearance : 12) + welcomeClearance
    }
    // qmllint enable unqualified
    readonly property int pad: 48
    implicitWidth: card.width + pad * 2
    implicitHeight: card.height + pad * 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-dictation-offer"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: card
    }

    readonly property string primary: Settings.modOpts.indicators.dictationPrimaryLanguage
    readonly property string secondary: Settings.modOpts.indicators.dictationSecondaryLanguage
    readonly property bool downloading: Dictation.download === "running"
    readonly property bool failed: Dictation.download === "failed"
    readonly property bool ready: Dictation.enhancedInstalled
    readonly property string sizeText: Math.round(Dictation.enhancedSize / 1048576) + " MB"

    // No second language, the system's own language when it is another one,
    // then a few common ones; every other language is in Settings.
    readonly property var languageChoices: {
        const system = String(Quickshell.env("LANG") || "").slice(0, 2);
        const codes = [];
        for (const code of [system, "nl", "de", "fr", "es"]) {
            if (code !== root.primary && codes.indexOf(code) === -1
                    && SettingsHelpers.DICTATION_LANGUAGES.indexOf(code) !== -1)
                codes.push(code);
        }
        if (root.secondary !== "off" && root.secondary !== root.primary
                && codes.indexOf(root.secondary) === -1)
            codes.unshift(root.secondary);
        return [{value: "off", label: I18n.tr("No")}].concat(codes.slice(0, 4).map(
            code => ({value: code, label: I18n.localeName(code)})));
    }

    // Closes itself a moment after the model is ready.
    Timer {
        id: readyClose
        interval: 2500
        onTriggered: Dictation.dismissOffer()
    }

    Connections {
        target: Dictation

        function onEnhancedInstalledChanged() {
            if (Dictation.enhancedInstalled && root.shown)
                readyClose.restart();
        }
    }

    Rectangle {
        id: card

        x: root.pad
        y: root.pad + (root.shown ? 0 : root.atTop ? -16 : 16)
        opacity: root.shown ? 1 : 0
        width: Math.min(Theme.scaled(460, Theme.typeScale), (root.screen ? root.screen.width : 1280) - 64)
        height: column.implicitHeight + Theme.scaled(40)
        radius: Theme.popRadius
        color: Theme.panelSurface
        border.width: 1
        border.color: Theme.popBorder
        Accessible.role: Accessible.Dialog
        Accessible.name: I18n.tr("Make dictation more accurate")

        Behavior on opacity {
            NumberAnimation { duration: Theme.panelFadeDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation {
                duration: Theme.panelMotionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        Keys.onEscapePressed: Dictation.dismissOffer()

        Column {
            id: column
            x: Theme.scaled(20)
            y: Theme.scaled(20)
            width: card.width - Theme.scaled(40)
            spacing: Theme.scaled(12)

            Row {
                spacing: Theme.controlSpacing

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.ready ? "check" : "sparkles"
                    size: Theme.iconMedium
                    color: Theme.accentText
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.ready ? I18n.tr("Enhanced dictation is ready")
                        : I18n.tr("Make dictation more accurate")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.title
                    font.weight: Theme.weightSemibold
                    color: Theme.textHi
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.ready
                    ? I18n.tr("Your next dictation uses the enhanced speech model.")
                    : I18n.tr("Dictation uses the small speech model built into Cybex OS. The enhanced model recognises names, technical words and other languages much better. It runs on this computer: nothing you say leaves it.")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textMid
            }

            // ---- a second language
            Text {
                visible: !root.ready
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.tr("Do you also dictate in another language?")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
            }

            Flow {
                visible: !root.ready
                width: parent.width
                spacing: Theme.scaled(6)

                Repeater {
                    model: root.languageChoices

                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool selected: root.secondary === modelData.value
                        width: chipLabel.implicitWidth + Theme.scaled(22)
                        height: Theme.chipHeight
                        radius: height / 2
                        color: selected ? Theme.accent : chipMouse.containsMouse ? Theme.hoverFill : "transparent"
                        border.width: 1
                        border.color: selected ? Theme.accent : Theme.popBorder
                        activeFocusOnTab: true
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.label
                        Accessible.checked: selected
                        Keys.onSpacePressed: Dictation.setSecondaryLanguage(modelData.value)
                        Keys.onReturnPressed: Dictation.setSecondaryLanguage(modelData.value)

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.control
                            color: chip.selected ? Theme.textOnAccent : Theme.textMid
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Dictation.setSecondaryLanguage(chip.modelData.value)
                        }
                    }
                }
            }

            Text {
                visible: !root.ready && root.secondary !== "off"
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.tr("Dictation recognises which of your two languages you speak.")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                color: Theme.textLow
            }

            // ---- the download
            Column {
                visible: root.downloading
                width: parent.width
                spacing: Theme.scaled(6)

                BlockMeter {
                    width: parent.width
                    height: Theme.scaled(8)
                    value: Dictation.downloadProgress / 100
                    accessibleName: I18n.tr("Download progress")
                }

                Text {
                    text: I18n.format(I18n.tr("Downloading the enhanced model… %1%"), [Dictation.downloadProgress])
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    color: Theme.textLow
                }
            }

            Text {
                visible: root.failed
                width: parent.width
                wrapMode: Text.WordWrap
                text: Dictation.downloadError === "space"
                    ? I18n.tr("There is not enough free disk space for the enhanced model.")
                    : Dictation.downloadError === "checksum"
                        ? I18n.tr("The downloaded model did not match. Nothing was installed.")
                        : I18n.tr("The download did not finish. Check your connection and try again.")
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                color: Theme.redText
            }

            Item {
                width: parent.width
                height: Theme.chipHeight

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.ready && !root.downloading
                    text: I18n.format(I18n.tr("%1 download"), [root.sizeText])
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.metadata
                    color: Theme.textLow
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.controlSpacing

                    SettingsUi.SettingsAction {
                        visible: !root.ready
                        text: root.downloading ? I18n.tr("Cancel download") : I18n.tr("Not now")
                        onTriggered: {
                            if (root.downloading)
                                Dictation.cancelDownload();
                            else
                                Dictation.dismissOffer();
                        }
                    }

                    SettingsUi.SettingsAction {
                        visible: !root.downloading
                        primary: true
                        text: root.ready ? I18n.tr("Done")
                            : root.failed ? I18n.tr("Try again")
                            : I18n.tr("Download")
                        onTriggered: {
                            if (root.ready)
                                Dictation.dismissOffer();
                            else
                                Dictation.downloadEnhanced();
                        }
                    }
                }
            }
        }
    }
}
