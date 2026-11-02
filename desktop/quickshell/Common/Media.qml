pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "StatusHelpers.js" as StatusHelpers
import "AudioHelpers.js" as AudioHelpers
import "Format.js" as Format

// Which MPRIS player the shell is talking about, and what can be done to it.
// The bar chip, the media panel, the drawer and the Omarchy media service all
// read `player`, so a player picked in the panel is the one the chip shows.
//
// The automatic choice is playing → paused → first (StatusHelpers), and the
// player already shown keeps its place while it plays. A pick pins a player
// until another one starts playing.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    // Without playerctld's proxy, which would list the same track twice.
    readonly property var listed: StatusHelpers.listedPlayers(players)

    property string pinnedKey: ""
    property var lastPlayingKeys: []
    readonly property var playingKeys: StatusHelpers.playingKeys(players)

    onPlayingKeysChanged: {
        pinnedKey = StatusHelpers.nextPinnedKey(pinnedKey, lastPlayingKeys, playingKeys);
        lastPlayingKeys = playingKeys;
    }

    // The player shown last, which keeps its place while it plays. Recorded
    // after the change settles: writing it from inside the change would
    // re-enter `player`'s own binding.
    property string currentKey: ""
    readonly property var player: StatusHelpers.selectedPlayer(players, pinnedKey, currentKey)
    onPlayerChanged: Qt.callLater(root.rememberPlayer)

    function rememberPlayer() {
        currentKey = StatusHelpers.playerKey(player);
    }
    readonly property var others: StatusHelpers.otherPlayers(players, player)

    // A player with no track is a running app, not something to show — the
    // bar module's auto-rule turns on exactly here.
    readonly property bool hasTrack: player !== null && player.trackTitle !== ""
    readonly property bool playing: player !== null && player.isPlaying

    readonly property string glyph: StatusHelpers.playerGlyph(player)
    readonly property string brandIcon: brandFor(player)
    readonly property string iconSource: resolvePlayerIcon(player)

    // The panel shows the remaining time instead of the length once asked to,
    // for the rest of the session.
    property bool showRemaining: false

    function pin(target) {
        pinnedKey = StatusHelpers.playerKey(target);
    }

    function brandFor(target) {
        return target && StatusHelpers.playerBrand(target) === "youtube" ? "youtube" : "";
    }

    // ---- position -----------------------------------------------------------
    // MprisPlayer.position is read on demand: nothing announces that time
    // passed. One tick a second while something plays keeps the chip's ring
    // and the panel's seek bar current; a seek announces itself at once.
    readonly property real length: player && player.lengthSupported ? Math.max(0, player.length) : 0
    readonly property real position: player && player.positionSupported ? Math.max(0, player.position) : 0
    readonly property real progress: length > 0 ? Format.clamp01(position / length) : 0

    Timer {
        interval: 1000
        repeat: true
        running: root.playing && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    function seek(seconds) {
        if (!player || !player.canSeek || length <= 0)
            return;
        player.position = Math.max(0, Math.min(length, seconds));
    }

    function seekBy(seconds) {
        seek(position + seconds);
    }

    // ---- this player's volume -------------------------------------------------
    // The player's own PipeWire streams, matched the way the audio panel names
    // them. MPRIS volume is the fallback: browsers do not publish it, but their
    // streams are always there.
    readonly property var playbackStreams: AudioHelpers.playbackStreams(
        Pipewire.nodes ? Pipewire.nodes.values : [])
    readonly property var playerStreams: AudioHelpers.streamsForPlayer(
        player, playbackStreams, players)

    PwObjectTracker {
        objects: root.playerStreams
    }

    readonly property var streamAudio: {
        const stream = playerStreams.find(node => node && node.audio);
        return stream ? stream.audio : null;
    }
    readonly property bool mprisVolume: streamAudio === null && player !== null
        && player.volumeSupported && player.canControl
    readonly property bool volumeAvailable: streamAudio !== null || mprisVolume
    readonly property real volume: streamAudio ? Format.clamp01(streamAudio.volume)
        : mprisVolume ? Format.clamp01(player.volume) : 0
    readonly property bool muted: streamAudio ? streamAudio.muted
        : mprisVolume && player.volume <= 0
    property real mprisRestoreVolume: 0.5

    function setVolume(fraction) {
        const value = Format.clamp01(fraction);
        if (streamAudio !== null) {
            for (const node of playerStreams) {
                if (!node || !node.audio)
                    continue;
                node.audio.volume = value;
                if (value > 0 && node.audio.muted)
                    node.audio.muted = false;
            }
        } else if (mprisVolume) {
            player.volume = value;
        }
    }

    function stepVolume(delta) {
        if (volumeAvailable)
            setVolume((muted ? 0 : volume) + delta);
    }

    function toggleMuted() {
        if (streamAudio !== null) {
            const next = !streamAudio.muted;
            for (const node of playerStreams) {
                if (node && node.audio)
                    node.audio.muted = next;
            }
        } else if (mprisVolume) {
            if (player.volume > 0) {
                mprisRestoreVolume = player.volume;
                player.volume = 0;
            } else {
                player.volume = mprisRestoreVolume > 0 ? mprisRestoreVolume : 0.5;
            }
        }
    }

    // ---- the player's window ------------------------------------------------
    // Hyprland does not focus a window for an MPRIS Raise by default, so the
    // dock's own window list is tried first.
    function windowFor(target) {
        return StatusHelpers.playerWindow(target, Dock.windows);
    }

    function canShow(target) {
        return target !== null && (windowFor(target) !== "" || target.canRaise);
    }

    function show(target) {
        if (!target)
            return false;
        const address = windowFor(target);
        if (address !== "" && DesktopWorkspaces.activate(address))
            return true;
        if (target.canRaise) {
            target.raise();
            return true;
        }
        return false;
    }

    // ---- icons ---------------------------------------------------------------
    function resolvedIcon(value) {
        if (!value)
            return "";
        if (value.startsWith("/"))
            return "file://" + value;
        if (value.startsWith("file://") || value.startsWith("data:")
                || value.startsWith("qrc:") || value.startsWith("image://"))
            return value;
        return Quickshell.iconPath(value, true);
    }

    function resolvePlayerIcon(target) {
        if (!target)
            return "";

        // The YouTube shortcut is a Brave --app window, so it has no desktop
        // entry of its own. Its MPRIS URL is classified in the pure helper.
        if (StatusHelpers.playerBrand(target) === "youtube")
            return "";

        const candidates = StatusHelpers.playerIconCandidates(target);
        for (const candidate of candidates) {
            const entry = DesktopEntries.heuristicLookup(candidate);
            if (entry && entry.icon) {
                const source = resolvedIcon(entry.icon);
                if (source !== "")
                    return source;
            }
            const source = resolvedIcon(candidate);
            if (source !== "")
                return source;
        }
        return "";
    }
}
