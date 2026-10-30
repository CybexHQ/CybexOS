# Software and application defaults

Open **Software** from the application launcher, **Settings → Applications**
or `cybexos-software`. It installs and removes native NixOS packages only; there
are no Flatpak or Flathub apps in Software.

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

**Explore** shows featured apps, eight categories, collections built from the
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

## Application defaults

**Settings → Applications** also selects a browser, terminal, text editor,
PDF viewer, image viewer and video player. These per-account preferences apply
immediately, using GIO's standard MIME associations and `xdg-terminal-exec`'s
standard terminal preference list. System defaults are fallbacks; unrelated
personal associations remain intact. A missing saved choice is retained and
shown as unavailable, while an available application handles launches. An
explicit association changed outside Settings takes precedence.

Cybex OS browser/terminal shortcuts, agent windows, maintenance and firmware
terminals, web apps, and dock suggestions use the same defaults. Chromium-based
selected browsers can open web apps in app mode; other browsers open their URL
normally. Private browsing uses the selected browser's advertised desktop action;
unsupported private actions produce a notification. Explicit `VISUAL`/`EDITOR`
values and personal shortcuts retain their precedence. Arguments are passed as
argv, including filenames and URLs containing spaces; they are not shell code.

The `cybexos-apps` helper offers `status`, `set ROLE DESKTOP_ID`, `browser`,
`browser --private`, `webapp URL`, `terminal [OPTIONS] [-- COMMAND ARGS…]`, and
`edit FILE…`. `cybex software catalogue`, `list`, `search QUERY`,
`check ATTR…`, `stage JSON` and `request ID` expose the native package workflow
for scripting.
