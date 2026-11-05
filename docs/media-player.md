# Music player in the menubar

The menubar's media chip shows what an MPRIS player is playing. Its panel
controls the player. The chip hides itself when no player has a track. The
code is `desktop/quickshell/Bar/Modules/Media.qml` (the chip),
`Popovers/MediaPopover.qml` (the panel) and `Common/Media.qml` (which player,
its position and its volume).

## The chip

The chip shows the cover, the title and artist, and a play/pause button. It
keeps one width while you use it: nothing unfolds under the pointer, so the
modules beside it never move.

- The ring around the button shows how far the track has played. It is grey
  while paused and absent when the player reports no length.
- While paused, the title dims and the cover loses most of its colour.
- When a second player has something to show, its cover sits behind the
  first.
- A player with no cover shows its brand, its desktop-entry icon or a
  media-type glyph.
- A title too long for the chip ends in an ellipsis. Under the pointer it
  slowly drifts back and forth through its full length (not with reduced
  motion).
- A new track slides into place.

| Input | Action |
| --- | --- |
| Click the chip | Open or close the panel |
| Click the button | Play or pause |
| Middle-click | Next track |
| Wheel | This player's volume, ±5 %, with the volume OSD naming the player |

The media module's settings (**Settings → Bar**) keep its title order (title · artist, artist ·
title, or title only) and its maximum width. The chip is as wide as that
maximum allows and the bar has room for: in a side column it ends 12 px short
of the centre group, the title shortening first (`BarGeometry.fitMenubar`).
Below about eight characters the title goes and the chip keeps only the cover
and the button; with less room still, the chip moves to the bar's **More**
menu before the clock, the workspaces or the right cluster give anything up.

## The panel

From top to bottom:

- **Header:** the player's name and whether it is playing, and a button
  that shows the player's window.
- **Track:** the cover, the title (two lines), the artist and the album. The
  cover's colours wash the top of the panel.
- **Seek bar:** it thickens under the pointer and shows the time there. A
  drag seeks once, on release. Click the end time to show the time remaining
  instead (for the session). A player with no length that cannot seek shows
  **Live**.
- **Transport:** shuffle, previous, play/pause, next and repeat, centred.
  Shuffle and repeat show a dot while on, and repeat-one has its own mark.
  They are hidden for players that do not support them.
- **Volume:** this player's own volume, with a mute button.
- **Other players:** every other player with a track, playing ones first.
  Click a row to bring that player to the top. Its button plays or pauses it
  where it is.

Keys: **Space** plays or pauses, **←/→** seek 10 s, **Shift+←/→** skip,
**↑/↓** change the volume, **Tab** moves between controls, and **Esc** closes
the panel. A focused control keeps its own keys: a slider takes the arrows,
and Space on a row plays that row's player.

## Which player

The chip, the panel, the drawer's Now Playing card and the Omarchy media
service all show `Media.player`:

1. A player picked in the panel stays until another player *starts*
   playing. Players that were already playing do not take over.
2. Otherwise, the player already shown stays while it plays. Starting a
   second one from the list does not swap them.
3. Otherwise, the first playing player, then the first paused one, then the
   first known one.

playerctld re-publishes another player, so it is never listed.

## Volume

The volume belongs to the player's PipeWire playback streams. A stream belongs
to the player when its `application.process.id` matches the process ID in the
player's bus name (`….instance<pid>`, as Chromium, VLC and mpv use).
Otherwise the stream belongs to the player when the audio panel would give it
that player's name. A player without a matching stream falls back to its MPRIS
`Volume`, if it has one. Browsers do not report an MPRIS volume, but their
streams are always there.

## Showing the player's window

Hyprland does not focus a window for an MPRIS `Raise` by default. The header
button therefore activates the player's window from the dock's window list
first, and calls `Raise` only when it finds none. A YouTube web app only
matches its own window, never just any window of its browser. The button is
hidden when neither works.

## Testing

`tests/media-player.py` runs the real shell under a private headless Sway and
D-Bus session, with three fake MPRIS players:

- a music app that plays, with covers;
- a browser YouTube web app on a live stream;
- a video player with no cover.

Real pointer input (wlr-virtual-pointer) and the keyboard drive the chip and
the panel, and every action is checked against what the fake player received.
It renders with OpenGL on llvmpipe, because the software backend draws no
MultiEffect. Set `CYBEXOS_MEDIA_SCREENSHOTS=DIR` to keep the screenshots and
`CYBEXOS_MEDIA_THEME=light` for the light theme.

```bash
nix develop -c python3 -B tests/media-player.py
```

The test has no PipeWire, so it exercises the MPRIS volume path. The stream
path is covered by `streamsForPlayer` in `tests/quickshell/audio-output.test.cjs`.
