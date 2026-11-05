pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import "../../Common"
import "DrawerFormat.js" as DrawerFormat
import ".."

// The drawer's Overview tab, everyday controls first (2026-11 UI review):
// quick toggles, the two sliders, now playing, a pending update, the system
// summary, then the top processes. That order is also what stays above the
// fold on a 1280×720 laptop. The person's drawerOverview choices still hide
// any optional section; the system summary is always there. Session actions
// live in the drawer's pinned row (DrawerSessionFooter), not here.
// Everything here is a summary — each row's own tab or panel carries the
// detail.
Column {
    id: root

    property var updateService: Updates
    // DrawerPopover's body height while the host gives one, otherwise 0.
    property real bodyHeightBudget: 0
    // A question for the pinned session row: Overview's update restart.
    signal sessionConfirmRequested(string action, Item origin, string version)

    // The updater's own "restart to finish" page (UpdatesHelpers.page):
    // installed, and waiting only for the restart Software Update would
    // otherwise offer as "Restart Now".
    readonly property bool restartPending: updateService.page === "restart"
    readonly property bool shutdownRequired: restartPending
        && !!(updateService.deployment.firmware || {}).needsShutdown
    // The Cybex OS release this update brings, when it brings one.
    readonly property string updateRelease: {
        const deployment = updateService.deployment || {};
        if (deployment.scope !== "cybexos" && deployment.scope !== "both")
            return "";
        return deployment.availableVersion
            || ((updateService.sources || {}).cybexos || {}).available || "";
    }

    width: parent ? parent.width : 0
    spacing: Theme.scaled(12)

    // The summary's live metrics and brightness share one watcher claim.
    // Keyed on visibility, not construction: the drawer's `control` instance
    // stays latched by the popout host.
    Claim {
        active: root.visible
        onClaimed: SysInfo.acquire()
        onReleased: SysInfo.release()
    }

    // ---- quick toggles ---------------------------------------------------
    Grid {
        visible: Settings.drawerOverview.tiles === true
        width: parent.width
        columns: 4
        columnSpacing: Theme.scaled(6)
        rowSpacing: Theme.scaled(6)

        readonly property real tileWidth: (width - columnSpacing * 3) / 4

        DrawerTile {
            width: parent.tileWidth
            glyph: "dark_mode"
            label: I18n.tr("Dark")
            description: I18n.tr("Dark mode")
            on: Settings.themeMode === "dark"
            onToggled: Settings.set("themeMode",
                Settings.themeMode === "dark" ? "light" : "dark")
        }

        DrawerTile {
            width: parent.tileWidth
            glyph: "do_not_disturb_on"
            label: I18n.tr("Focus")
            description: I18n.tr("Focus: silences notifications")
            on: Notifs.dnd
            onToggled: Notifs.setDnd(!Notifs.dnd)
        }

        DrawerTile {
            width: parent.tileWidth
            glyph: "nightlight"
            label: I18n.tr("Night")
            description: I18n.tr("Night light")
            on: SysInfo.nightLight
            onToggled: SysInfo.toggleNightLight()
        }

        DrawerTile {
            width: parent.tileWidth
            glyph: "coffee"
            label: I18n.tr("Awake")
            description: I18n.tr("Stay awake")
            on: SysInfo.idleInhibited
            onToggled: SysInfo.toggleIdleInhibited()
        }
    }

    // ---- sliders --------------------------------------------------------
    Column {
        visible: Settings.drawerOverview.sliders === true
        width: parent.width
        spacing: Theme.scaled(4)

        // Brightness stays out of the way until a display answers: -1 is
        // "not read yet" as well as "nothing to adjust" (SysInfo), and a
        // desktop without either would show a dead row forever.
        DrawerSliderRow {
            glyph: "sunny"
            visible: SysInfo.brightness >= 0
            value: Math.max(0, SysInfo.brightness) / 100
            showValue: true
            accessibleName: I18n.tr("Screen brightness")
            onMoved: v => SysInfo.setBrightness(v * 100)
        }

        DrawerSliderRow {
            glyph: Audio.muted || Audio.volume === 0 ? "volume_off"
                : Audio.volume < 50 ? "volume_down" : "volume_up"
            value: Audio.level
            ready: Audio.ready
            showValue: true
            detail: Audio.outputName
            reason: I18n.tr("No output device")
            recoveryText: I18n.tr("Sound settings")
            accessibleName: I18n.tr("Output volume")
            onMoved: v => Audio.setVolume(v)
            onRecovery: Settings.showPanel("sound", Popouts.hostScreenName)
        }
    }

    // ---- now playing ---------------------------------------------------
    Rectangle {
        visible: Media.hasTrack && Settings.drawerOverview.media === true
        width: parent.width
        height: Math.max(Theme.scaled(64), mediaText.implicitHeight + Theme.scaled(20))
        radius: Theme.rowRadius + 2
        color: Theme.chip
        border.width: 1
        border.color: Theme.hairlineSoft

        Item {
            id: art
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.scaled(44)
            height: Theme.scaled(44)

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.chipHover

                Sym {
                    anchors.centerIn: parent
                    name: Media.glyph
                    size: Theme.iconLarge
                    color: Theme.textMid
                    visible: artImage.status !== Image.Ready
                }
            }

            Image {
                id: artImage
                anchors.fill: parent
                source: Media.player ? Media.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(88, 88)
                visible: status === Image.Ready
            }
        }

        Column {
            id: mediaText
            anchors.left: art.right
            anchors.leftMargin: Theme.scaled(12)
            anchors.right: transport.left
            anchors.rightMargin: Theme.controlSpacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: Media.player ? Media.player.trackTitle : ""
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    if (!Media.player)
                        return "";
                    const artist = Media.player.trackArtist;
                    const app = Media.player.identity;
                    return artist !== "" && app !== ""
                        ? artist + " · " + app : (artist || app);
                }
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.secondary
                color: Theme.textMid
                elide: Text.ElideRight
            }
        }

        Row {
            id: transport
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            DrawerIconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "skip_previous"
                width: Theme.scaled(30)
                height: Theme.scaled(30)
                enabled: Media.player !== null && Media.player.canGoPrevious
                accessibleName: I18n.tr("Previous track")
                onClicked: Media.player.previous()
            }

            Rectangle {
                id: playButton

                readonly property bool playing: Media.player !== null
                    && Media.player.playbackState === MprisPlaybackState.Playing

                anchors.verticalCenter: parent.verticalCenter
                width: Theme.scaled(32)
                height: Theme.scaled(32)
                radius: width / 2
                color: Theme.accent
                activeFocusOnTab: true
                border.width: Theme.focusWidth(activeFocus)
                border.color: Theme.accentFg
                Accessible.role: Accessible.Button
                Accessible.name: playing ? I18n.tr("Pause") : I18n.tr("Play")
                Accessible.onPressAction: playButton.toggle()

                function toggle() {
                    if (Media.player)
                        Media.player.togglePlaying();
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) {
                        playButton.toggle();
                        event.accepted = true;
                    }
                }

                Sym {
                    anchors.centerIn: parent
                    name: playButton.playing ? "pause" : "play_arrow"
                    size: Theme.iconMedium
                    color: Theme.accentFg
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        playButton.forceActiveFocus();
                        playButton.toggle();
                    }
                }
            }

            DrawerIconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "skip_next"
                width: Theme.scaled(30)
                height: Theme.scaled(30)
                enabled: Media.player !== null && Media.player.canGoNext
                accessibleName: I18n.tr("Next track")
                onClicked: Media.player.next()
            }
        }
    }

    // ---- pending update --------------------------------------------------
    // One compact card with one action, shown by the updater's own rule
    // (Updates.overviewVisible). A finished install asks to restart; the
    // pinned session row confirms it and then restarts through Session, as
    // Software Update's "Restart Now" does. Anything else opens Software
    // Update, which owns review, install and recovery.
    Rectangle {
        objectName: "overviewUpdates"
        visible: Settings.drawerOverview.updates === true && root.updateService.overviewVisible
        width: parent.width
        height: Math.max(Theme.scaled(56),
            Math.max(updateCopy.implicitHeight, Theme.inlineActionHeight) + Theme.scaled(20))
        radius: Theme.rowRadius + 2
        color: Theme.chip
        border.width: 1
        border.color: Theme.hairlineSoft

        Accessible.role: Accessible.StaticText
        Accessible.name: updateTitle.text + ". " + updateDetail.text

        Rectangle {
            id: updatesBadge
            anchors.left: parent.left
            anchors.leftMargin: Theme.scaled(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.scaled(32)
            height: Theme.scaled(32)
            radius: Theme.rowRadius + 2
            color: root.updateService.error !== "" ? Theme.amberBgSoft : Theme.chipHover

            Sym {
                anchors.centerIn: parent
                name: root.restartPending ? "restart_alt"
                    : root.updateService.hasUpdates || root.updateService.ready
                        ? "download" : "info"
                size: Theme.iconMedium
                color: root.updateService.error !== "" ? Theme.amber : Theme.accentText
            }
        }

        Column {
            id: updateCopy
            anchors.left: updatesBadge.right
            anchors.leftMargin: Theme.scaled(12)
            anchors.right: updateActions.left
            anchors.rightMargin: Theme.controlSpacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.scaled(2)

            Text {
                id: updateTitle
                width: parent.width
                text: root.restartPending && root.updateRelease !== ""
                    ? I18n.format("Cybex OS %1 is ready", [root.updateRelease])
                    : root.updateService.summary
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.primary
                font.weight: Theme.weightSemibold
                color: Theme.textHi
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.ignored: true
            }

            Text {
                id: updateDetail
                width: parent.width
                visible: text !== ""
                // A title that already names the release needs no scope
                // after it; one line keeps the summary above the fold.
                text: root.restartPending
                    ? (root.shutdownRequired ? I18n.tr("Shut down to finish") : I18n.tr("Restart to finish"))
                        + (root.updateRelease !== "" ? "" : " · " + root.updateService.scopeLabel)
                    : root.updateService.hasUpdates || root.updateService.ready
                        || root.updateService.runActive
                    ? root.updateService.scopeLabel
                    : root.updateService.checkedLabel
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                color: Theme.textMid
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
        }

        Item {
            id: updateActions
            anchors.right: parent.right
            anchors.rightMargin: Theme.scaled(10)
            anchors.verticalCenter: parent.verticalCenter
            width: root.restartPending ? restartAction.width : reviewAction.width
            height: Theme.inlineActionHeight

            // Primary: the one next step. Asks first, in the session row.
            ActionButton {
                id: restartAction
                objectName: "overviewUpdateRestart"
                visible: root.restartPending
                anchors.right: parent.right
                label: root.shutdownRequired ? I18n.tr("Shut down…") : I18n.tr("Restart…")
                fill: Theme.accent
                tint: Theme.accentFg
                focusColor: Theme.accentFg
                hPadding: Theme.scaled(24)
                enabled: !root.updateService.runActive && !root.updateService.requestPending
                onTriggered: root.sessionConfirmRequested(
                    root.shutdownRequired ? "update-shutdown" : "update-reboot",
                    restartAction, root.updateRelease)
            }

            ActionButton {
                id: reviewAction
                objectName: "overviewUpdateReview"
                visible: !root.restartPending
                anchors.right: parent.right
                label: root.updateService.hasUpdates || root.updateService.ready
                    ? I18n.tr("Review") : I18n.tr("Details")
                fill: root.updateService.hasUpdates || root.updateService.ready
                    ? Theme.accent : Theme.chipHover
                tint: root.updateService.hasUpdates || root.updateService.ready
                    ? Theme.accentFg : Theme.textHi
                focusColor: root.updateService.hasUpdates || root.updateService.ready
                    ? Theme.accentFg : Theme.focusRing
                hPadding: Theme.scaled(24)
                onTriggered: {
                    Popouts.close();
                    root.updateService.show();
                }
            }
        }
    }

    // ---- system summary --------------------------------------------------
    DrawerSystemHero {
        width: parent.width
    }

    // ---- top processes -------------------------------------------------
    // Hidden, it reads nothing: its sampler is claimed by visibility.
    DrawerProcesses {
        visible: Settings.drawerOverview.processes === true
        width: parent.width
        maxRows: DrawerFormat.processRows(root.bodyHeightBudget, Theme.scaled(640))
    }
}
