const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("./shell.cjs");

const H = load("StatusHelpers.js");

function player(identity, desktopEntry = "", extra = {}) {
    return {
        identity,
        desktopEntry,
        isPlaying: false,
        playbackState: H.PLAYBACK_STATE.Stopped,
        ...extra,
    };
}

// ---- percentages ---------------------------------------------------------

test("percentages normalize whichever scale the backend reports", () => {
    assert.equal(H.normalizePercent(0.42), 42);
    assert.equal(H.normalizePercent(1), 100);
    assert.equal(H.normalizePercent(42), 42);
    assert.equal(H.normalizePercent(100), 100);
    assert.equal(H.normalizePercent(0), 0);
});

test("battery percent falls back to zero rather than to an unusable reading", () => {
    assert.equal(H.batteryPercent({ percentage: 0.735 }), 73.5);
    assert.equal(H.batteryPercent({ percentage: 73.5 }), 73.5);
    assert.equal(H.batteryPercent(null), 0);
    assert.equal(H.batteryPercent(undefined), 0);
    assert.equal(H.batteryPercent({}), 0);
});

test("signal percent rounds and keeps -1 for an unknown strength", () => {
    assert.equal(H.signalPercent(0.674), 67);
    assert.equal(H.signalPercent(67.4), 67);
    assert.equal(H.signalPercent(0), 0);
    assert.equal(H.signalPercent(undefined), -1);
    assert.equal(H.signalPercent(null), -1);
    // Never NaN: the popover scales icon opacity by this value.
    assert.equal(H.signalPercent("weak"), -1);
});

// ---- battery -------------------------------------------------------------

test("charge state separates active charging, preservation and full", () => {
    const state = H.BATTERY_STATE;
    assert.equal(H.chargeState({ state: state.Charging }), "charging");
    assert.equal(H.chargeState({ state: state.PendingCharge }), "pending-charge");
    assert.equal(H.chargeState({ state: state.FullyCharged }), "full");
    assert.equal(H.chargeState({ state: state.Discharging }), "discharging");
    assert.equal(H.chargeState({ state: state.PendingDischarge }), "discharging");
    assert.equal(H.chargeState({ state: state.Empty }), "discharging");
    assert.equal(H.chargeState({ state: state.Unknown }), "discharging");
    assert.equal(H.chargeState(null), "discharging");
});

test("power source is independent of charge state and preservation is explained", () => {
    const paused = { state: H.BATTERY_STATE.PendingCharge };
    assert.equal(H.isPluggedIn(paused), true);
    assert.equal(H.isPluggedIn(paused, true), false);
    assert.equal(H.isPluggedIn({ state: H.BATTERY_STATE.Discharging }, false), true);
    assert.equal(H.batteryStatus("pending-charge", true, true), "Plugged in · Charge limited");
    assert.equal(H.batteryStatus("pending-charge", true, false), "Plugged in · Not charging");
    assert.equal(H.batteryStatus("charging", true, true), "Charging");
    assert.equal(H.batteryStatus("full", true, true), "Fully charged");
    assert.equal(H.batteryStatus("pending-charge", false, true), "On battery");
});

test("bar and popover agree: a full battery is plugged in but not charging", () => {
    const full = { state: H.BATTERY_STATE.FullyCharged };
    assert.equal(H.chargeState(full) === "charging", false);
    assert.equal(H.isPluggedIn(full), true);
    assert.equal(H.isPluggedIn({ state: H.BATTERY_STATE.Charging }), true);
    assert.equal(H.isPluggedIn({ state: H.BATTERY_STATE.Discharging }), false);
    assert.equal(H.isPluggedIn(null), false);
});

// ---- media ---------------------------------------------------------------

test("player glyphs cover every source the bar and the popover can show", () => {
    const glyph = H.PLAYER_GLYPH;
    assert.equal(H.playerGlyph(player("Spotify", "spotify")), glyph.spotify);
    assert.equal(H.playerGlyph(player("Firefox", "firefox")), glyph.firefox);
    assert.equal(H.playerGlyph(player("Zen Browser", "zen")), glyph.firefox);
    assert.equal(H.playerGlyph(player("Chromium", "chromium")), glyph.chromium);
    assert.equal(H.playerGlyph(player("Google Chrome", "google-chrome")), glyph.chromium);
    assert.equal(H.playerGlyph(player("Brave", "brave-browser")), glyph.chromium);
    assert.equal(H.playerGlyph(player("Microsoft Edge", "msedge")), glyph.edge);
    assert.equal(H.playerGlyph(player("YouTube Music", "youtube-music")), glyph.youtube);
    assert.equal(H.playerGlyph(player("mpv", "mpv")), glyph.video);
    assert.equal(H.playerGlyph(player("VLC media player", "vlc")), glyph.video);
    assert.equal(H.playerGlyph(player("Rhythmbox", "rhythmbox")), glyph.generic);
    assert.equal(H.playerGlyph(null), glyph.generic);
});

test("player glyphs match on the desktop entry and ignore case", () => {
    assert.equal(H.playerGlyph(player("", "org.mozilla.firefox")), H.PLAYER_GLYPH.firefox);
    assert.equal(H.playerGlyph(player("SPOTIFY", "")), H.PLAYER_GLYPH.spotify);
});

test("a browser playing a YouTube tab keeps its browser mark", () => {
    // The branch order is what decides this, so it is worth pinning: a
    // Chrome PWA identifies as YouTube Music but is still Chrome.
    assert.equal(
        H.playerGlyph(player("YouTube Music", "chrome-youtube-music")),
        H.PLAYER_GLYPH.chromium);
    assert.equal(
        H.playerGlyph(player("Firefox", "firefox", { trackTitle: "youtube" })),
        H.PLAYER_GLYPH.firefox);
});

test("media brands recognize YouTube webapps from their MPRIS URL", () => {
    assert.equal(H.playerBrand(player("Google Chrome", "google-chrome", {
        dbusName: "org.mpris.MediaPlayer2.chromium.instance42",
        metadata: { "xesam:url": "https://www.youtube.com/watch?v=abc" },
    })), "youtube");
    assert.equal(H.playerBrand(player("Brave", "", {
        dbusName: "org.mpris.MediaPlayer2.brave.instance42",
        metadata: { "xesam:url": "https://www.youtube.com/watch?v=abc" },
    })), "youtube");
    assert.equal(H.playerBrand(player("Brave", "brave-browser", {
        metadata: { "xesam:url": "https://music.youtube.com/watch?v=abc" },
    })), "youtube");
    assert.equal(H.playerBrand(player("YouTube Music", "chrome-youtube-music")),
        "youtube");
    assert.equal(H.playerBrand(player("Brave", "brave-browser", {
        metadata: { "xesam:url": "https://example.com/youtube.com/watch" },
    })), "");
});

test("player icon candidates bridge MPRIS names to installed desktop entries", () => {
    assert.deepEqual(H.playerIconCandidates(player("Spotify", "spotify")),
        ["spotify", "com.spotify.Client"]);
    assert.deepEqual(H.playerIconCandidates(player("Brave", "")),
        ["brave-browser", "Brave"]);
    // Every Chromium browser's bus is chromium.instance<pid>: the browser
    // itself comes first, its desktop entry or not.
    const bus = { dbusName: "org.mpris.MediaPlayer2.chromium.instance42" };
    assert.deepEqual(H.playerIconCandidates(player("Google Chrome", "google-chrome", bus)),
        ["google-chrome", "chromium", "Google Chrome"]);
    assert.deepEqual(H.playerIconCandidates(player("Google Chrome", "", bus)),
        ["google-chrome", "chromium", "Google Chrome"]);
    assert.deepEqual(H.playerIconCandidates(player("Brave", "", bus)),
        ["brave-browser", "chromium", "Brave"]);
    assert.deepEqual(H.playerIconCandidates(player("Chromium", "", bus)), ["chromium"]);
    assert.deepEqual(H.playerIconCandidates(player("Firefox", "org.mozilla.firefox")),
        ["org.mozilla.firefox", "Firefox"]);
    assert.deepEqual(H.playerIconCandidates(player("Rhythmbox", "rhythmbox")),
        ["rhythmbox"]);
    assert.deepEqual(H.playerIconCandidates(null), []);
});

test("the active player is playing, else paused, else the first known", () => {
    const stopped = player("Rhythmbox");
    const paused = player("Firefox", "firefox", {
        playbackState: H.PLAYBACK_STATE.Paused,
    });
    const playing = player("Spotify", "spotify", {
        isPlaying: true,
        playbackState: H.PLAYBACK_STATE.Playing,
    });

    assert.equal(H.activePlayer([stopped, paused, playing]), playing);
    assert.equal(H.activePlayer([stopped, paused]), paused);
    assert.equal(H.activePlayer([stopped]), stopped);
    assert.equal(H.activePlayer([]), null);
    assert.equal(H.activePlayer(undefined), null);
});

test("a picked player stays the shell's player until another one starts playing", () => {
    const spotify = player("Spotify", "spotify", { dbusName: "org.mpris.MediaPlayer2.spotify",
        isPlaying: true, playbackState: H.PLAYBACK_STATE.Playing, trackTitle: "Glass Harbour" });
    const brave = player("Brave", "brave-browser", { dbusName: "org.mpris.MediaPlayer2.chromium.instance42",
        playbackState: H.PLAYBACK_STATE.Paused, trackTitle: "Lo-fi beats" });
    const mpv = player("mpv", "mpv", { dbusName: "org.mpris.MediaPlayer2.mpv", trackTitle: "" });
    const proxy = player("Spotify", "", { dbusName: "org.mpris.MediaPlayer2.playerctld",
        isPlaying: true, playbackState: H.PLAYBACK_STATE.Playing, trackTitle: "Glass Harbour" });
    const all = [proxy, spotify, brave, mpv];

    // playerctld mirrors another player and is never listed.
    assert.deepEqual(H.listedPlayers(all), [spotify, brave, mpv]);
    assert.equal(H.selectedPlayer(all, ""), spotify);
    assert.deepEqual(H.playingKeys(all), ["org.mpris.MediaPlayer2.spotify"]);

    // Picking the paused browser wins over the playing Spotify.
    const pinned = H.playerKey(brave);
    assert.equal(H.selectedPlayer(all, pinned), brave);
    // Spotify was already playing when the browser was picked: the pin holds.
    assert.equal(H.nextPinnedKey(pinned, ["org.mpris.MediaPlayer2.spotify"],
        ["org.mpris.MediaPlayer2.spotify"]), pinned);
    // The pinned player starting is not "another one".
    assert.equal(H.nextPinnedKey(pinned, [], [pinned]), pinned);
    // A newly started player takes over.
    assert.equal(H.nextPinnedKey(pinned, [pinned], [pinned, "org.mpris.MediaPlayer2.mpv"]), "");
    assert.equal(H.nextPinnedKey("", [], ["org.mpris.MediaPlayer2.mpv"]), "");
    // A pin on a player that has quit falls back to the automatic choice.
    assert.equal(H.selectedPlayer([spotify], pinned), spotify);

    // Without a pin, the player shown keeps its place while it plays, even
    // when another one starts (from the panel's list) ahead of it.
    const video = player("mpv", "mpv", { dbusName: "mpv", isPlaying: true, trackTitle: "Lecture" });
    assert.equal(H.selectedPlayer([video, spotify], "", H.playerKey(spotify)), spotify);
    assert.equal(H.selectedPlayer([video, spotify], "", ""), video);
    const stopped = { ...spotify, isPlaying: false, playbackState: H.PLAYBACK_STATE.Paused };
    assert.equal(H.selectedPlayer([video, stopped], "", H.playerKey(stopped)), video,
        "a paused current player gives way to one that plays");

    // The others: everything else with a track, playing first.
    const radio = player("Radio", "radio", { dbusName: "radio", isPlaying: true, trackTitle: "News" });
    assert.deepEqual(H.otherPlayers([proxy, spotify, brave, mpv, radio], spotify), [radio, brave]);
    assert.deepEqual(H.otherPlayers([], null), []);
});

test("the chip's text keeps the configured order and marks which half is the title", () => {
    assert.deepEqual(H.chipText("title-artist", "Salt Road", "Hollis Fern"),
        { first: "Salt Road", second: "Hollis Fern", titleFirst: true });
    assert.deepEqual(H.chipText("artist-title", "Salt Road", "Hollis Fern"),
        { first: "Hollis Fern", second: "Salt Road", titleFirst: false });
    assert.deepEqual(H.chipText("title", "Salt Road", "Hollis Fern"),
        { first: "Salt Road", second: "", titleFirst: true });
    assert.deepEqual(H.chipText("artist-title", "Salt Road", ""),
        { first: "Salt Road", second: "", titleFirst: true });
    assert.deepEqual(H.chipText("title-artist", undefined, null),
        { first: "", second: "", titleFirst: true });
});

test("a player's window comes from the dock's list, and a web app only matches its own", () => {
    const windows = [
        { address: "a1", appId: "brave-browser", entryId: "brave-browser" },
        { address: "b2", appId: "brave-www.youtube.com__-Default", entryId: "brave-youtube.desktop" },
        { address: "c3", appId: "Spotify", entryId: "com.spotify.Client" },
        { address: "d4", appId: "google-chrome", entryId: "google-chrome" },
        { address: "e5", appId: "chrome-www.youtube.com__-Default", entryId: "cybexos-webapp-youtube" },
    ];
    assert.equal(H.playerWindow(player("Spotify", "spotify"), windows), "c3");
    assert.equal(H.playerWindow(player("Brave", "brave-browser"), windows), "a1");
    const youtube = player("Brave", "brave-browser", { metadata: { "xesam:url": "https://www.youtube.com/watch?v=x" } });
    assert.equal(H.playerWindow(youtube, windows), "b2");
    assert.equal(H.playerWindow(youtube, windows.slice(0, 1)), "",
        "a YouTube player never falls back to an unrelated browser window");
    const chrome = player("Google Chrome", "google-chrome", { dbusName: "org.mpris.MediaPlayer2.chromium.instance7" });
    assert.equal(H.playerWindow(chrome, windows), "d4");
    const chromeYoutube = { ...chrome, metadata: { "xesam:url": "https://www.youtube.com/watch?v=y" } };
    assert.equal(H.playerWindow(chromeYoutube, windows.slice(2)), "e5");
    assert.equal(H.playerWindow(player("mpv", "mpv"), windows), "");
    assert.equal(H.playerWindow(null, windows), "");
});

// ---- enum mirrors --------------------------------------------------------
//
// The two enums above are mirrored numerically so the helpers stay free of Qt
// imports. Check them against the installed type information, so a
// Quickshell upgrade that renumbers either one fails here rather than silently
// reporting the wrong battery state. The gate requires Quickshell (CI installs
// it too), so a missing type file is a broken install, not a reason to skip.

function qmlRoot() {
    const candidates = [
        process.env.QT_INSTALL_QML,
        "/nix/store/test-qtdeclarative/lib/qt-6/qml",
        "/usr/lib/qt6/qml",
    ];
    return candidates.find(dir => dir && fs.existsSync(dir)) ?? null;
}

function enumValues(file, component) {
    const source = fs.readFileSync(file, "utf8");
    const block = source.slice(source.indexOf(`name: "${component}"`));
    assert.ok(block !== "", `${component} missing from ${file}`);
    const match = block.match(/values:\s*\[([^\]]*)\]/);
    assert.ok(match, `${component} declares no plain enum value list`);
    const names = match[1].match(/"([^"]+)"/g).map(name => name.slice(1, -1));
    return Object.fromEntries(names.map((name, index) => [name, index]));
}

const root = qmlRoot();
const skip = root === null ? "Qt QML directory not found" : false;

test("the mirrored UPower device states match the installed enum", { skip }, () => {
    const file = path.join(root, "Quickshell/Services/UPower",
        "quickshell-service-upower.qmltypes");
    assert.ok(fs.existsSync(file), `${file} missing (nix develop)`);
    assert.deepEqual(
        enumValues(file, "qs::service::upower::UPowerDeviceState"),
        H.BATTERY_STATE);
});

test("the mirrored Mpris playback states match the installed enum", { skip }, () => {
    const file = path.join(root, "Quickshell/Services/Mpris",
        "quickshell-service-mpris.qmltypes");
    assert.ok(fs.existsSync(file), `${file} missing (nix develop)`);
    assert.deepEqual(
        enumValues(file, "qs::service::mpris::MprisPlaybackState"),
        H.PLAYBACK_STATE);
});
