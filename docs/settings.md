# Settings

The Settings window (Super+, or **Cybex OS Settings** in the launcher) is the
shell's own preferences and the system settings it manages. This page records
how it is organised since the October 2026 redesign; the code is
`desktop/quickshell/Settings/` with the page list in `Common/Settings.qml`.

## Layout

- **Rail.** At the top, Search opens the palette. Below it come **Home** and
  three groups of six pages:
  - **Personalize:** Appearance, Wallpaper, Bar & Control Center, Workspaces &
    dock, Notifications and Plugins.
  - **Devices:** Displays, Sound, Network, Touchpad, Keyboard and Power.
  - **System:** Security, Online accounts, Assistant, Applications, Region &
    language and Backup & storage.

  Every page has its own glyph. The rail fits without scrolling at the default
  size, which is 960 × 700 at a 12 px base and about 1120 × 817 at the default
  14 px. In a shorter window it scrolls. Below about 860 units of width it
  compresses to its glyphs.

  The current page is a selected row in the
  [shared state system](shell-states.md): an accent tint, a 3 px edge on its
  leading side, the accent on its icon and the label in `textHi`. Hover is the
  neutral chip and keyboard focus is only the ring, which shows while the
  keyboard is in use. When a page changes from elsewhere (Back, a Home
  reading, a search), focus moves with the selection, so the ring is never on
  one page while another is selected. In the icon rail every page and the
  search glyph name themselves in a tip on hover and on keyboard focus, and
  as their accessible name; a page with changes waiting adds that to both
  ("Touchpad: changes waiting"). The icon rail also shows "Press / to search
  pages" once above the page, as a plain tip with an info mark rather than a
  filled box, so it is never taken for a second search field. Dismissing it,
  opening the palette or closing the window retires it. The window keeps no
  state on disk, so this lasts for the session.
- **Header.** It holds Back (also Alt+Left), then the page and what it is
  about, the save state ("Saving… / Saved", with Undo after a reset), the
  **Changes** chip and Close. While the chip shows, it is the only status:
  "Saved" beside "1 change waiting" read as if the waiting change were saved,
  so the brief saving note steps back. Errors and Undo still show. Back walks the pages visited since the window
  opened. Closing the window forgets that trail.
- **Tabs.** A page that holds more than one view shows underlined tabs above its
  content:
  - **Keyboard:** Layouts and Shortcuts.
  - **Backup & storage:** Backups, Recovery points and Disk space.

  Tabs only switch the view. A segmented control only ever changes a value, so
  the two never look alike.

## Home

Home replaces About. From top to bottom it shows:

1. The computer's name, release and hardware, and the update state as a
   status pill over a secondary **Software Update…** action. While an item
   under Needs attention already opens Software Update (a restart, a ready
   change, firmware updates), the hero keeps only its pill, so the page has
   one way into Software Update at a time.
2. One strip with storage, battery (memory on a desktop), backups and network.
   Storage and backups open Backup & storage, network opens Network and
   battery opens Power. Memory has no page, so it is plain text, not a button.
   Storage is in decimal units ("412 GB free", "of 1 TB") and memory in whole
   GiB ("31 GiB").
3. **Needs attention**. This lists:
   - unapplied changes;
   - a system change being prepared, ready to review, or waiting for a restart;
   - backups that are not set up;
   - the [system check](system-check.md)'s problems and suggestions.

   Each item has a status pill (a dot and a word or two) beside its one
   action. The most urgent item's action is the group's only primary, and the
   others are secondary. The system check row runs `cybex doctor` again.
4. **Recently changed**. These are the settings changed in this window, each
   with Show and Undo.
5. **About this computer**. This holds shell health, the Welcome guide and the
   settings file.
6. **Reset all**, in a group of its own.

Actions follow the three tiers in [shell states](shell-states.md): primary,
secondary and tertiary. Every tier has at least a 32 px target. A disabled
action keeps its shape but not its call to action: a primary trades the
accent for the chip and hairline, and every tier's copy and icon take
`Theme.textDisabled`, dimmed but still about 3:1, rather than a fade. Below about
560 px of content column (`SettingsPage.compact`), Home reflows instead of
eliding. The update state moves under the identity, the four readings go two
by two and wrap, and an attention item puts its pill and action on a line
under its title. An attention item also stacks when its title would not fit
beside them. The theme and pointer galleries mark the chosen tile with a 2 px
`textHi` frame and an accent check. In a narrow column the theme previews drop
to 72 px, and Appearance keeps its order.

Recently changed keeps at most eight entries in
`~/.local/state/cybexos/shell/settings-recent.json`. It records only settings
that the search index can name, and only while the window is open; Control
Center toggles are not recorded. Undo restores the value the entry started
from. An entry whose setting has moved on since then is not shown.

## Search palette

"/", Ctrl+K or Ctrl+F opens the palette over the window. It searches:

- pages;
- settings, each with its current value;
- actions, such as opening Software Update, running the system check, changing
  the password, adding a fingerprint or a shortcut, backing up now, or opening
  the settings file.

The index is `Common/SettingsSearchData.js`: `ROWS`, with hidden `terms` such as
"dnd" or "vrr", and `ACTIONS`. Enter goes to the row and highlights it.
Ctrl+Enter switches a setting on or off in place.

## Changes

Most settings apply as they change. These drafts wait for Apply instead:

- touchpad, keyboard layouts and shortcuts, which apply to the session;
- the system timezone and language, and recovery-point cleanup, which build a
  system change.

They are kept for the session in `InputDrafts`, `Keybindings`, `RegionDrafts`
and `RetentionDraft`, so leaving a page keeps them. The rail marks each page
that has a draft. The header's chip counts the drafts, and **Review changes**
lists every one with its old value. Nothing in the sheet has happened yet, so
it groups the drafts by what Apply will do: **Takes effect when you apply**
(session drafts) and **Takes effect after a restart** (a system change, with
the **Administrator** tag). Its scrim covers the whole window, rail included,
and its footer holds the one Apply: a page's own Apply bar steps back while
the sheet is open (`SettingsChanges.reviewOpen`), and a keep-or-revert trial
keeps its countdown in view.

Apply settles each session draft one at a time. It then prepares at most one
system change, because the updater keeps one deployment at a time. A
timezone and a language chosen together are one request (`cybex config region`
with two triples), so one generation and one restart. Recovery-point cleanup is
a separate maintenance preview, prepared after the regional change is applied.

Settings that build a system change say so on their group heading with
**Administrator · restart**. Sudo and SSH Server say **Administrator**, because
they need authorization but no restart ([sudo](sudo.md), [SSH Server](ssh.md)).
Once a system change is prepared, the chip follows it through preparing,
review in Software Update, and restarting to finish.

Displays and Network edits stay on their own page and do not join Changes.
Applying either starts a keep-or-revert trial. Leaving the page reverts a
running trial and drops edits that were not applied.

## Pointer

**Appearance → Pointer** chooses the pointer's style, size and hand, and when
Hyprland hides it. Like the rest of Appearance, a change applies at once,
without Apply, and the next login starts with it.

- **The gallery.** It shows each theme's arrow, link hand, text beam and busy
  pointer from the theme's own files. Hovering a tile plays its busy animation.
  The gallery has two parts:
  - **On this computer:**
    - the twelve Bibata variants and Adwaita, which every installation has;
    - downloads;
    - any other XCursor theme on `XCURSOR_PATH`. One under the home folder is
      marked **Yours**.
  - **Download:** the rest of `desktop/quickshell/assets/pointers/catalogue.json`.
- **Downloads.** The machine records each downloadable package's exact store
  path at its own Nixpkgs in `/etc/cybexos/pointers.json`, without making it
  part of the system. Choosing such a theme substitutes that path from the
  configured binary cache:
  - The command is `nix-store --realise PATH --add-root ~/.local/state/cybexos/pointer/roots/PACKAGE`.
  - Nix checks the signature, and nothing is compiled.
  - The theme is then linked into `~/.local/share/icons`. A name already taken
    there is the person's own and is left alone.
  - Hovering a downloaded theme that is not in use offers **Remove download**,
    which drops the links and the root. Nix frees the space at its next
    collection.
  - `scripts/check-prebuilt` fails a release whose recorded paths
    cache.nixos.org does not hold.
  - The previews ship with the shell. `scripts/render-pointer-previews` redraws
    them from the catalogue's packages after a catalogue or Nixpkgs change.
- **Applying.** `Common/Pointer.qml` resolves the choice:
  - A picked theme that is no longer installed falls back to the
    installation's own, from `XCURSOR_THEME`.
  - **Left-handed** uses a theme's mirrored variant (Bibata `-Right`, Phinger
    `-left`). It is unavailable for a theme without one.
  - **Size** is 24, 32, 48 or 64 px before each display's scale.

  `scripts/pointer.py apply` then runs `hyprctl setcursor`, sets Hyprland's
  own `XCURSOR_THEME` and `XCURSOR_SIZE` (`hl.env`, for what key bindings
  start), sets GTK's `cursor-theme` and `cursor-size` keys and updates the
  systemd/D-Bus activation environment. A choice that differs from the
  installation's own is recorded in `~/.local/state/cybexos/pointer/session.env`.
  `cybexos-session` exports it before Hyprland starts, so the next login draws
  it from the first frame.
- **X11 applications.** Under XWayland an application draws its own pointer.
  Chromium-based ones such as Spotify take the theme from GTK, which on X11
  reads XSETTINGS, never `XCURSOR_THEME`. `cybexos-xsettings.service`
  (xsettingsd, through `cybexos-runtime exec xsettings`) serves the pointer
  from `~/.local/state/cybexos/pointer/xsettings.conf`. `apply` rewrites that
  file and reloads the service. It also merges `Xcursor.theme` and
  `Xcursor.size` into the X resources, which plain Xlib applications read and
  whose change makes Chromium reload its pointers, and gives the X root window
  the new arrow (`xsetroot`).
- **Wayland first.** Spotify, Brave, 1Password, ChatGPT and T3 Code explicitly
  select `--ozone-platform=wayland` in their executable launchers, so desktop
  entries, shortcuts, URL handlers and terminal launches use the same backend.
  Software uses the same Spotify, 1Password and ChatGPT wrappers. The machine's
  original packages remain intact. `NIXOS_OZONE_WL=1` also asks Nixpkgs wrappers
  for other Chromium/Electron apps (VS Code, Discord, Obsidian) to prefer
  Wayland; it is not a guarantee for every downloaded or third-party app.
  Firefox and Qt use the session's native Wayland settings; GTK apps select
  Wayland in the Wayland session. XWayland remains available for X11-only
  applications, including Steam and games that require it. Hyprland then draws
  their pointer (cursor-shape-v1), and they render at each display's scale
  instead of being drawn at 1× and doubled.
- **Launching.** The launcher, the dock, Software and the assistant start
  applications with `Pointer.launch()`: the desktop entry's command, as
  `DesktopEntry.execute()` runs it, with the pointer last applied. The shell's
  own environment is still the one from login.
- **Hiding.** Hide while typing and Hide when idle (3, 10 or 20 seconds;
  Hyprland's limit is 20) are Hyprland's `cursor:hide_on_key_press` and
  `cursor:inactive_timeout`. `looknfeel.lua` reads them from `shell.json` as the
  compositor starts. Settings applies a change through `hyprctl eval`.
- **Limits.**
  - Applications that let Hyprland draw their pointer change at once. One
    exception: Hyprland keeps the image already on screen until a surface sets
    the pointer again (`setcursor` only reloads the theme), so the new style
    shows as soon as the pointer moves onto something else.
  - Some applications draw their own pointer and read the theme when they
    start, among them Xlib and Java ones under XWayland. They change when
    reopened.
  - A terminal, or another application, already open passes the pointer from
    when it started to what it starts, until the next login.
  - The login screen keeps Bibata Modern Classic: it is system configuration.
- **Scripting.** `cybexos-runtime ipc pointer` provides:
  - `status`;
  - `use THEME`, which downloads the theme first when it is not on this
    computer;
  - `remove THEME`;
  - `refresh`.

## Page ids

IPC (`cybexos-runtime ipc settings open ID`), the launcher and other views open
pages by id. Ids from before the redesign still work:

- `about` opens `home`;
- `shortcuts` opens `keyboard` on Shortcuts;
- `storage` opens `backup` on Disk space;
- `modules`, `widgets` and `drawer` open `bar`;
- `system` opens `power`.

`Settings.showPanel(page, screen, key)` chooses the tab a legacy id or a moved
row names (`legacyTabs`, `keyTabs`). Otherwise it opens a tabbed page on its
first view.

## Tests

- `tests/settings-pages.py` runs the real shell under a private headless Sway.
  It opens every page and tab and follows the legacy ids. It also drives Back,
  the icon rail's one-time search tip ("/" opens the palette and retires it),
  the palette (Enter and Ctrl+Enter), Recently changed with Undo, and two
  drafts reviewed and applied from the Changes sheet. A recording `cybex`
  checks that the sheet sends one combined `cybex config region` call. Its
  Pointer section lists stand-in themes and one of the person's own. It
  applies a size and hand through recording fakes and shows a download that
  cannot reach the cache. Run it through `nix develop` with grim and wtype.
- `checks.x86_64-linux.pointer` (`nix/tests/pointer.nix`) is the end-to-end
  check, in a real Hyprland session. It runs these steps:
  1. Download Hackneyed through the shell from a local binary cache holding its
     real NAR.
  2. Check the root and the link.
  3. Check what Hyprland draws, in a screen copy.
  4. Check GTK, the activation environment, XSETTINGS and the X resources,
     and the pointer of an application the launcher or Hyprland starts.
  5. Apply edited settings when the shell starts.
  6. Sign out and in again, and check that Hyprland starts with the pointer.
  7. Remove the download, after which Nix may collect it.
- `checks.x86_64-linux.wayland-scale` (`nix/tests/wayland-scale.nix`) runs
  Spotify on a 2× display, through XWayland and natively. It measures how
  sharp each draws in a screen copy and checks that both show the chosen
  pointer over Spotify's window.
- `tests/nixos/test_pointer.py` covers the XCursor reader, `scripts/pointer.py`
  and `cybexos-session`'s record. `tests/quickshell/pointer.test.cjs` covers the
  resolution, the schema, the catalogue and its previews, and `looknfeel.lua`.
- `tests/quickshell/settings-*.test.cjs` hold the page model, search, palette,
  Changes and Recently changed contracts. `settings-states.test.cjs` covers the
  state system, the action tiers and Home's narrow-column reflow.
- `tests/settings-runtime.py` is the installed-VM audit of every page and tab;
  see [the settings audit](measurements/settings-audit-2026-10-27.md).
