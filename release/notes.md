# Cybex OS 1.0.26

The desktop now uses the installer's typefaces: Space Grotesk for text and JetBrains Mono for numbers, keys and labels. If you chose a font yourself, you keep it; pick Space Grotesk under Settings → Appearance to switch. Secondary text is easier to read in every theme, switches are larger, and light mode gives panels and notifications a visible edge.

The menubar's workspace dots are larger and easier to click, and the Control Center button sits in its own chip, which lights up while the Control Center is open.

The Control Center's tabs now have names. The buttons at the bottom are Lock, Power (Sleep, Restart, Shut down, Log out) and More. The system meters and process list are folded under **Show details**. Sound, Network, Bluetooth and Power each say in plain words when there's nothing to show, with at most one button to fix it.

Settings no longer shows "Saved" next to changes that are still waiting. The review sheet groups changes by when they take effect. The keyboard maps in Settings and the Welcome guide now agree: lit keys are in use and outlined keys are free. The Shortcuts page has a single search field.

Software uses plainer words: apps say **Open source** or **From the maker**, NixOS apps are added to a queue that you then install, and apps without an icon show their first letter. Software Update buttons use sentence case, and before you keep a new version it shows which version you're on and which one you'd go back to.

Wiz names the settings it changes the way Settings does, and its Copy and Terminal buttons are labelled.

The empty workspace overview offers to open an app. The clock popover shows the whole month and asks for your location if weather has none. Notes invites you to write your first note, and notifications no longer cover the Welcome guide's top bar.

In the installer, the review page no longer cuts off the start of its labels or its Change links, the system check shows full details, and if an installation fails it now starts by saying what happened to your disk. Its helper text is easier to read.

Spotify, ChatGPT, 1Password and the other bundled Chromium and Electron apps now always open as native Wayland windows, from the launcher, links and the terminal alike.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
