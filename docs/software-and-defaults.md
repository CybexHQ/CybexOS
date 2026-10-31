# Software and application defaults

Open **Software** from the application launcher, **Settings → Applications**
or `cybexos-software`. Its home starts with [your default apps](#default-apps),
the apps doing each everyday job, which you can switch in a click. It has two
sources. NixOS packages come first: they are
part of the system, staged and rolled back with it. [Flathub](#flathub) is the
second: sandboxed apps installed for your account right away, outside system
generations. [Programs from outside both](#programs-from-outside-nixos-and-flathub)
also run.

## Prebuilt only

Cybex OS installs prebuilt packages. Free apps come from NixOS's binary cache
(cache.nixos.org) and are labelled **Prebuilt**; nothing compiles on your
computer. Unfree vendor apps (Spotify, Discord, Slack, Zoom, Obsidian,
VS Code, Chrome and others) are never in the NixOS cache: Nix unpacks the
vendor's own download, so they are labelled **Vendor download**. They are
unavailable while proprietary apps are turned off for the machine.

Before anything is staged, `cybex software check ATTR…` dry-runs the machine's
own packages (`path:/etc/nixos#nixosConfigurations.cybexos.pkgs.ATTR`, the same
package universe search uses) against its store and configured caches. Nothing
is built. A free package NixOS has not built yet (a new release still in
NixOS's build queue, or a personal override) would compile, so Software blocks
it calmly: "NixOS hasn't finished building this yet. Try again after the next
update." Anything needed only to unpack an unfree vendor download is expected.
The check reports the exact download; the catalogue's figure (the compressed
download beyond the default installation) is an estimate until then.

## Explore, categories and app pages

**Explore** starts with [your default apps](#default-apps). Under **Discover**
it shows featured apps, eight categories, collections built from the
installer's profiles (**Install all** adds a collection's missing apps), and the
most popular apps by Flathub's install counts. A category page has subcategory
filters, an Editor's choice and every app in it by popularity. An app page
shows how it arrives, its licence, the download, its version in this system,
its Nixpkgs attribute, a description and similar apps.

The app catalogue (`desktop/software/catalogue.json` and its icons, see
`desktop/software/README.md`) ships with Cybex OS in
`/run/current-system/sw/share/cybexos/software`. Icons ship too. Screenshots
are not shipped: Software loads them from Flathub's media server only when you
open an app's page, and says so on that page. Once a page has loaded a
screenshot, the featured carousel and Editor's choice may show it for the rest
of the session; otherwise they use the app's icon and brand colour.
`cybex software catalogue` merges the shipped catalogue with the machine: what
is installed and by whom, each app's version in the machine's own locked
Nixpkgs (evaluated offline and cached per configuration identity), and whether
an app is unavailable here.

**Search** matches catalogue apps by name, summary, developer and category,
then lists **More packages** from the machine's full Nixpkgs, including
personal overlays. The first full search indexes package metadata locally and
takes a while; later searches use a cache that is invalidated when the machine
configuration changes. Discovery neither refreshes inputs nor creates a second
package universe. A package from that list is checked before Install is
offered.

## The install list

**Install** adds an app to a list at the bottom of the window ("Added"); you can
keep browsing. **Install N apps** checks the whole list, then stages one
change: the supervised worker builds the complete system from prebuilt
packages, showing download progress. When it is ready, **Install now** asks
for authorization and applies it, the same serialized, checked deployment,
trial boot, confirmation and rollback path as system updates. Your current
system stays as a fallback. Afterwards **Open** starts the app through its
desktop entry; restart when convenient to finish, as for any system change.
Removing apps uses the same list.

Closing Software does not cancel a change. Cancelled authorization, a worker
failure, or a change started elsewhere (a system update being prepared or
awaiting review, or a restart still pending) is explained in the list, and
nothing is changed. A change adopted after a shell restart continues where it
was.

## Who installed what

**Installed** groups apps by owner, from `/etc/cybexos/software.json`. Each
inventory package lists its `origins`: `software` (Software's selections),
`cybexos` (Cybex OS's own modules), `nixos` (NixOS modules those enable) or
`personal` (any other definition file: the machine's `/etc/nixos` modules and
the inputs it imports).

- **Added by you**: Software's own selections. Remove or open them here.
- **Included with Cybex OS**: open only; they update with the system.
- **From your configuration**: personal modules; read-only here. Change them in
  `/etc/nixos`.

Apps (catalogue entries and packages with a desktop entry) come first; other
packages are folded under **Other packages**. The fresh machine template
imports `local/software.nix` and stores selections in
`/etc/nixos/local/software.json`. Software edits only that declaration in a
staged copy. Removing a Software selection never removes another module's
package declaration. Personal Nix profiles retain their own tools. No migration
or alternate installation/update path is provided.

## Updates

Apps update together with the system in **Software Update**, all prebuilt. The
**Updates** tab only reads: when an update has been prepared it lists the
installed apps whose versions change (with a count on the tab) and opens
Software Update to install it; otherwise it says your apps are up to date and
can check for updates.

## Flathub

Search lists **From Flathub** between the catalogue's apps and **More
packages**: apps from [flathub.org](https://flathub.org) that the catalogue
does not already show, with a tick for a developer Flathub verified. An app's
page loads its details, screenshots and download size from Flathub when it
opens, and lists the sandbox access the app asks for (all your files, your
home folder, devices, commands outside the sandbox, the older X11 display
system, the network). **Install** starts at once, for your account only
(`flatpak --user`): no authorization, no system change and no restart.
**Open** starts it; **Remove** asks for a second press, then removes it and
any runtime nothing else uses. The app's data in `~/.var/app` stays.

A catalogue app NixOS cannot install yet (it would compile, or NixOS marks it
unavailable) offers **View on Flathub** on its page. One already installed
from Flathub opens from the catalogue as well. NixOS remains the first
source: an installable catalogue app is never sent elsewhere.

**Installed** groups Flathub apps under **From Flathub**; ones installed for
everyone on the computer (`flatpak --system`, an administrator's choice) are
listed there read-only. **Updates** checks this account's Flathub apps when it
opens, at most every ten minutes, or with **Check**; **Update all** updates
them right away. Flathub apps are not part of Software Update's review, its
trial boot or a system rollback.

Proprietary Flathub apps follow the computer's proprietary choice, as NixOS
vendor apps do. Each account gets the `flathub` remote once, at its first
sign-in, from the copy of Flathub's repository file that ships with Cybex OS
(`lifecycle/cybexos/flathub.flatpakrepo`, signing key
`6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE`); Software adds it again
only for an explicit install. A remote you remove or change stays as you left
it. Installs, updates and removals run in a transient user service
(`cybexos-flathub-ID.service`), so closing Software or restarting the shell
does not interrupt them; Software follows the change from its record in
`~/.local/state/cybexos/software/`, and Flatpak's own output stays in the
private `flathub.log` there. `cybex software flathub status`, `search QUERY`,
`app ID`, `updates`, `install ID…`, `remove ID…` and `update [ID…]` expose the
same workflow.

Turn Flathub off in Software for a computer with
`cybexos.features.flathub = false;` in `/etc/nixos/local/`. Flatpak itself
(`services.flatpak.enable`) stays available for the command line; already
installed Flathub apps can still be removed.

## Programs from outside NixOS and Flathub

Programs downloaded as plain Linux binaries (vendor tarballs, language
toolchains, Python wheels, editor extensions) expect the standard dynamic
loader and common libraries. [nix-ld](https://github.com/nix-community/nix-ld)
provides both, with the libraries NixOS's own AppImage runtime uses
(`programs.nix-ld`). AppImages start directly: binfmt hands them to
`appimage-run` (`programs.appimage`). Both are NixOS defaults that a personal
module can turn off. Software that installs system services or kernel modules,
or writes into `/usr`, still needs a Nix package; Distrobox (with Podman)
offers another distribution's user space for the rest.

## Default apps

Cybex OS picks the app for each everyday job, and **Software's home** shows
them first, under **Your default apps**, above everything to discover. Nine
jobs have a card: web browser, terminal, text editor, files, email, music,
videos, documents (PDF) and images. Each card names the app doing the job and
who chose it: **Cybex pick** (what the machine's configuration declares) or
**Your choice**. Nothing handles email links until you choose, so that card
says **Choose an app**. These choices are per account and apply at once.

A card opens the job's picker. It says what the job controls (Super+B and
private windows for the browser, Super+Return and Cybex OS's own terminal
windows for the terminal, Super+E for files) and lists a short set of apps
Cybex OS has checked work for it. For each one it shows what keeps working
with Cybex OS and what doesn't, such as the 1Password extension, web apps in
their own windows, or following the Cybex theme. It also shows how the app
would arrive: already **Installed**, **Prebuilt** with its download, a
**Vendor download**, or from **Flathub**. Installed apps that can do the job
but are not on the list follow under **Also on this computer**, and **Find
another … in Software** searches for more. The footer says what choosing
will do before you press anything.

- **An installed app** takes over at once.
- **A NixOS app** goes on the install list, which starts preparing the change
  right away. You confirm with your password, as for any app. The app takes
  over once it is installed, with no restart.
- **A Flathub app** (one NixOS has no prebuilt package for, such as
  Thunderbird, Amberol or Zen Browser) installs for your account with no
  password, then takes over.
- **Gmail** and **Outlook** in your browser handle email links with nothing
  to install. Cybex OS ships the two hidden handlers
  (`cybexos-mail-gmail.desktop`, `cybexos-mail-outlook.desktop`). They open a
  new message, with the link's recipients, subject and body, in the selected
  browser.

A choice that waits for its app is kept by `cybexos-apps`, so closing Software
or restarting the shell loses nothing. It applies the next time the app is
there, within a day. Software drops it when the install fails or the app is
taken off the install list. Each switch shows a note with **Undo**, which
puts back what was there before. **Reset to Cybex picks** appears once any
job differs from Cybex OS's pick: it forgets this account's choices and
leaves installed apps installed. The app that did a job before stays
installed. An app's own page offers the same switch: "Use Firefox as your web
browser?".

The curated lists live in `desktop/software/sources.json` (see
`desktop/software/README.md`). The catalogue generator keeps an option only
while NixOS has it prebuilt, or Flathub has it.

### Terminals and the Cybex theme

Kitty, Ghostty, Alacritty and foot all follow the shell's appearance: its
colours, its sixteen terminal colours and its text size. Each account gets a
small configuration for them at sign-in, only where it has none of its own.
Those files include Cybex OS's defaults (`desktop/defaults/`) and the
generated theme in `~/.local/state/cybexos/theme/`:

- `~/.config/kitty/kitty.conf`;
- `~/.config/ghostty/config`, which loads the defaults, then the theme, then
  your own `~/.config/ghostty/personal.conf`;
- `~/.config/alacritty/alacritty.toml`;
- `~/.config/foot/foot.ini`.

Kitty and Ghostty windows change with the appearance at once (SIGUSR1 and
SIGUSR2). Alacritty reloads the file itself. foot uses it for each new window.

xdg-terminal-exec passes Cybex OS's window options (title, app ID, working
directory, keeping the window open after a command) only to terminals whose
desktop entries declare how. Alacritty's and foot's don't, so `cybexos-apps
terminal` gives those two their own `--title`, `--class`/`--app-id`,
`--working-directory` and `--hold` options. Update and maintenance windows
therefore stay open in every listed terminal.

### How defaults apply

**Settings → Applications** chooses among the apps already installed for the
same nine jobs. **Choose in Software…** opens the picker above to install
another. Both use GIO's standard MIME associations (`inode/directory` for
files, `x-scheme-handler/mailto` for email, the common audio types for music)
and `xdg-terminal-exec`'s terminal preference list. System defaults are
fallbacks; unrelated personal associations remain intact. A missing saved
choice is retained and shown as unavailable, while an available application
handles launches. An explicit association changed outside Settings takes
precedence.

Cybex OS's browser, terminal and Files shortcuts, agent windows, maintenance
and firmware terminals, web apps and dock suggestions use the same defaults.
Super+E opens the selected file manager (`cybexos-apps files`). Chromium-based
browsers (Brave, Chromium, Chrome, Vivaldi) open web apps in app mode; other
browsers open their URL normally. Private browsing uses the selected browser's
advertised desktop action; unsupported private actions produce a notification.
Explicit `VISUAL`/`EDITOR` values and personal shortcuts retain their
precedence. Arguments are passed as argv, including filenames and URLs
containing spaces; they are not shell code.

The `cybexos-apps` helper offers:

- `status`;
- `set ROLE DESKTOP_ID [--when-installed]`;
- `reset ROLE` (back to Cybex OS's pick) and `cancel ROLE` (forget a waiting
  choice);
- `browser` and `browser --private`;
- `webapp URL`;
- `terminal [OPTIONS] [-- COMMAND ARGS…]`;
- `files [PATH…]`;
- `edit FILE…`;
- `mailto gmail|outlook [ADDRESS]`.

`cybex software catalogue`, `list`, `search QUERY`, `check ATTR…`,
`stage JSON` and `request ID` expose the native package workflow for
scripting.
