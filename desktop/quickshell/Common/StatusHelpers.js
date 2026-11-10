// Pure status helpers shared by the bar and its popovers: percentage
// normalization, battery charge semantics, media player selection and marks.
// Keep this file free of Qt APIs so the same logic stays testable under Node.
//
// The battery and media functions take the service object itself (or null)
// rather than pre-read values: QML captures property reads made inside an
// imported helper, so a binding on `chargeState(device)` still re-evaluates
// when the device's state changes.

// ---- percentages ---------------------------------------------------------

// UPower reports 0..100 while some devices report 0..1, and Networking's
// signalStrength arrives 0..1 in this backend, so a value at or below 1 is
// read as a fraction. A literal 1% therefore reads as 100% — the same trade
// the three call sites each made separately before this was shared.
function normalizePercent(value) {
    var number = Number(value);
    if (!isFinite(number))
        return NaN;
    return number <= 1 ? number * 100 : number;
}

// Charge level of a UPower device, unrounded. No device (or an unreadable
// reading) is 0, so consumers can bind this straight to a real property.
function batteryPercent(device) {
    if (!device)
        return 0;
    var pct = normalizePercent(device.percentage);
    return isFinite(pct) ? pct : 0;
}

// Wi-Fi signal as whole percent, with -1 for "no reading" so callers can
// tell an unknown strength from a genuine 0%.
function signalPercent(strength) {
    if (strength === undefined || strength === null)
        return -1;
    var pct = normalizePercent(strength);
    return isFinite(pct) ? Math.round(pct) : -1;
}

// ---- battery -------------------------------------------------------------

// org.freedesktop.UPower.Device's published State values, which Quickshell's
// UPowerDeviceState enum mirrors. Kept numeric so this module needs no Qt
// import; status-helpers.test.cjs pins them against the installed qmltypes.
var BATTERY_STATE = {
    Unknown: 0,
    Charging: 1,
    Discharging: 2,
    Empty: 3,
    FullyCharged: 4,
    PendingCharge: 5,
    PendingDischarge: 6
};

// PendingCharge includes firmware charge preservation: AC is connected but
// no energy is entering the battery. Never promise time-to-full in that state.
function chargeState(device) {
    var state = device ? device.state : undefined;
    if (state === BATTERY_STATE.Charging)
        return "charging";
    if (state === BATTERY_STATE.PendingCharge)
        return "pending-charge";
    if (state === BATTERY_STATE.FullyCharged)
        return "full";
    return "discharging";
}

// Charging or already full: what the bar's glyph and accent color mean.
function isPluggedIn(device, onBattery) {
    if (typeof onBattery === "boolean")
        return !onBattery;
    return chargeState(device) !== "discharging";
}

function batteryStatus(state, pluggedIn, limited) {
    if (!pluggedIn)
        return "On battery";
    if (state === "charging")
        return "Charging";
    if (state === "full")
        return "Fully charged";
    return limited ? "Plugged in · Charge limited" : "Plugged in · Not charging";
}

// ---- media ---------------------------------------------------------------

// Quickshell's MprisPlaybackState enum; pinned by the same qmltypes test as
// BATTERY_STATE above.
var PLAYBACK_STATE = {
    Stopped: 0,
    Playing: 1,
    Paused: 2
};

// Semantic Tabler icon names. Players are
// identified by media type: a browser
// gets the globe, a video player the film mark, everything else the note.
var PLAYER_GLYPH = {
    spotify: "graphic_eq",
    firefox: "public",
    chromium: "public",
    edge: "public",
    youtube: "smart_display",
    video: "movie",
    generic: "music_note"
};

function textValue(value) {
    return value === undefined || value === null ? "" : String(value);
}

function playerIdentity(player) {
    if (!player)
        return "";
    return (textValue(player.identity) + " "
        + textValue(player.desktopEntry) + " "
        + textValue(player.dbusName)).toLowerCase();
}

// Browser MPRIS players identify as the browser even for an --app window.
// xesam:url is the one reliable distinction for the YouTube webapp used here.
function playerBrand(player) {
    if (!player)
        return "";
    if (playerIdentity(player).includes("youtube"))
        return "youtube";
    var metadata = player.metadata || {};
    var url = textValue(metadata["xesam:url"]).toLowerCase();
    if (/(?:^|:\/\/)(?:[^./]+\.)?(?:youtube\.com|youtu\.be)(?:[\/:?#]|$)/.test(url))
        return "youtube";
    return "";
}

// Names to try against Quickshell's desktop-entry index. The MPRIS hint wins,
// then known package ids bridge players whose hint is only a short name (the
// Spotify Flatpak says `spotify`, for example), and the display identity is a
// final heuristic for everything else.
function playerIconCandidates(player) {
    if (!player)
        return [];

    var candidates = [];
    function add(value) {
        value = textValue(value).trim();
        if (value !== "" && !candidates.some(function (candidate) {
            return candidate.toLowerCase() === value.toLowerCase();
        }))
            candidates.push(value);
    }

    add(player.desktopEntry);
    var id = playerIdentity(player);
    if (id.includes("spotify"))
        add("com.spotify.Client");
    // Chromium browsers all name their MPRIS bus chromium.instance<pid>, so
    // the browser itself goes before Chromium.
    if (id.includes("chrome"))
        add("google-chrome");
    if (id.includes("brave"))
        add("brave-browser");
    if (id.includes("firefox"))
        add("org.mozilla.firefox");
    if (id.includes("chromium"))
        add("chromium");
    if (id.includes("edge") || id.includes("msedge"))
        add("microsoft-edge");
    add(player.identity);
    return candidates;
}

// Which mark a player gets in the bar chip and in the popover's source
// switcher. Order matters: a browser playing a YouTube tab keeps its browser
// mark, and only players naming YouTube themselves take the YouTube one.
function playerGlyph(player) {
    if (!player)
        return PLAYER_GLYPH.generic;
    var id = playerIdentity(player);
    if (id.includes("spotify"))
        return PLAYER_GLYPH.spotify;
    if (id.includes("firefox") || id.includes("zen"))
        return PLAYER_GLYPH.firefox;
    if (id.includes("chromium") || id.includes("chrome") || id.includes("brave"))
        return PLAYER_GLYPH.chromium;
    if (id.includes("edge"))
        return PLAYER_GLYPH.edge;
    if (id.includes("youtube"))
        return PLAYER_GLYPH.youtube;
    if (id.includes("mpv") || id.includes("vlc") || id.includes("video"))
        return PLAYER_GLYPH.video;
    return PLAYER_GLYPH.generic;
}

// The player the shell speaks for: whatever is playing, else whatever is
// paused, else the first one known. The popover prepends its own manual
// source override and falls back to exactly this.
function activePlayer(players) {
    if (!players || players.length === 0)
        return null;
    var playing = players.find(function (player) {
        return player.isPlaying;
    });
    if (playing !== undefined)
        return playing;
    var paused = players.find(function (player) {
        return player.playbackState === PLAYBACK_STATE.Paused;
    });
    return paused !== undefined ? paused : players[0];
}

// ---- the shell's player ----------------------------------------------------

// A stable name for a player across list rebuilds. The bus name is unique per
// running player; the identity only stands in for test fixtures without one.
function playerKey(player) {
    if (!player)
        return "";
    return textValue(player.dbusName) || textValue(player.identity);
}

// playerctld re-publishes whichever player it last saw, so listing it beside
// that player would show the same track twice.
function isProxyPlayer(player) {
    return textValue(player && player.dbusName).toLowerCase().indexOf("playerctld") !== -1
        || textValue(player && player.desktopEntry).toLowerCase() === "playerctld";
}

function listedPlayers(players) {
    return (players || []).filter(function (player) {
        return player && !isProxyPlayer(player);
    });
}

// The keys of the players that are playing now, in list order.
function playingKeys(players) {
    return listedPlayers(players).filter(function (player) {
        return player.isPlaying;
    }).map(playerKey);
}

// A player picked in the media panel stays the shell's player until another
// one starts playing. Players that were already playing when it was picked
// do not take over again; only a newly started one does.
function nextPinnedKey(pinnedKey, previousPlaying, currentPlaying) {
    if (!pinnedKey)
        return "";
    var before = previousPlaying || [];
    var started = (currentPlaying || []).some(function (key) {
        return key !== pinnedKey && before.indexOf(key) === -1;
    });
    return started ? "" : pinnedKey;
}

// The pinned player while it exists. Otherwise the player already shown
// stays while it plays, so starting a second one from the panel's list does
// not swap the two under the pointer; after that, the automatic choice.
function selectedPlayer(players, pinnedKey, currentKey) {
    var listed = listedPlayers(players);
    function byKey(key) {
        return key ? listed.find(function (player) {
            return playerKey(player) === key;
        }) : undefined;
    }
    var pinned = byKey(pinnedKey);
    if (pinned !== undefined)
        return pinned;
    var current = byKey(currentKey);
    if (current !== undefined && current.isPlaying)
        return current;
    return activePlayer(listed);
}

// Every other player that has something to show, playing ones first.
function otherPlayers(players, current) {
    var others = listedPlayers(players).filter(function (player) {
        return player !== current && textValue(player.trackTitle) !== "";
    });
    return others.filter(function (player) { return player.isPlaying; })
        .concat(others.filter(function (player) { return !player.isPlaying; }));
}

// The chip's text in the configured order. The title is always the brighter
// half, so the caller needs to know which half it is.
function chipText(format, title, artist) {
    title = textValue(title);
    artist = textValue(artist);
    if (format === "title" || artist === "")
        return { first: title, second: "", titleFirst: true };
    if (format === "artist-title")
        return { first: artist, second: title, titleFirst: false };
    return { first: title, second: artist, titleFirst: true };
}

// The window that belongs to a player, from the dock's window list
// ({ address, appId, entryId }). A YouTube web app only matches its own
// window, never just any window of the browser it runs in.
function playerWindow(player, windows) {
    if (!player)
        return "";
    var list = windows || [];
    function match(predicate) {
        var found = list.find(function (win) {
            return win && predicate(textValue(win.appId).toLowerCase(),
                textValue(win.entryId).toLowerCase());
        });
        return found !== undefined ? textValue(found.address) : "";
    }
    if (playerBrand(player) === "youtube")
        return match(function (appId, entryId) {
            return appId.indexOf("youtube") !== -1 || entryId.indexOf("youtube") !== -1;
        });
    var names = playerIconCandidates(player).map(function (name) {
        return name.toLowerCase();
    });
    return match(function (appId, entryId) {
        return names.some(function (name) {
            return name === appId || name === entryId
                || (entryId !== "" && name + ".desktop" === entryId);
        });
    });
}

var exported = {
    normalizePercent: normalizePercent,
    batteryPercent: batteryPercent,
    signalPercent: signalPercent,
    BATTERY_STATE: BATTERY_STATE,
    chargeState: chargeState,
    batteryStatus: batteryStatus,
    isPluggedIn: isPluggedIn,
    PLAYBACK_STATE: PLAYBACK_STATE,
    PLAYER_GLYPH: PLAYER_GLYPH,
    playerBrand: playerBrand,
    playerIconCandidates: playerIconCandidates,
    playerGlyph: playerGlyph,
    activePlayer: activePlayer,
    playerKey: playerKey,
    isProxyPlayer: isProxyPlayer,
    listedPlayers: listedPlayers,
    playingKeys: playingKeys,
    nextPinnedKey: nextPinnedKey,
    selectedPlayer: selectedPlayer,
    otherPlayers: otherPlayers,
    chipText: chipText,
    playerWindow: playerWindow
};

if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
