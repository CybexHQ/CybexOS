# Software catalogue

`sources.json` is the curated list behind **Software** and the installer's
software profiles: each app's Nixpkgs attribute, AppStream ID, category and
subcategory, plus the profiles, featured apps and display-name overrides.

`catalogue.json` and `icons/` are generated from it by
`scripts/software-catalogue` (see its header for the command). The generator:

- resolves every attribute in the repository's locked Nixpkgs and keeps only
  apps NixOS has prebuilt in cache.nixos.org, or unfree vendor downloads that
  NixOS never caches. Missing, broken and not-yet-built packages are dropped
  and listed, so a later run picks them up once NixOS has built them;
- adds Flathub AppStream metadata: name, summary, description (Flatpak
  packaging notes removed), developer, licence, brand colours, screenshot URLs
  and installs over the last 30 days, which ranks **Popular**;
- re-encodes each app's 128 px Flathub icon into `icons/<id>.png`;
- gives what each profile includes besides its apps an icon too (below);
- records each app's desktop file names from its NixOS output and the
  compressed download beyond the default installation, per app and per
  profile.

Its `roles` list the apps Software's home offers for each everyday job
(browser, terminal, editor, files, mail, music, video, pdf, image; the names
`cybexos-apps` uses), see [Default apps](#default-apps).

Regenerate before each release, after updating `flake.lock`.
`scripts/software-catalogue --check` verifies the catalogue against
`sources.json` and the icons without network access.

Screenshots are not shipped. Software loads them from Flathub's media server
when someone opens an app's page. Icons and screenshots belong to their
projects and identify the apps; names and logos remain their owners'
trademarks.

## Default apps

`roles` lists, per job, the apps Cybex OS has checked work for it, in the
order the picker shows them. Every option names its exact desktop entry
(`desktop`), the one `cybexos-apps set` makes the default, and a short
`summary`. It also has one of:

- `included`: Cybex OS installs it (Brave, Firefox, Kitty and the other
  defaults). Software offers it only where it is installed.
- `web`: a Cybex OS mail handler in `desktop/` that opens a web mail service
  in the browser, drawn with a `glyph`.
- `attribute`: the Nixpkgs package to install. The generator keeps the option
  only while NixOS has prebuilt it (or it is an unfree vendor download), and
  checks that the package really installs `desktop`.
- `flathub`: the Flathub app installed for the account when NixOS has no
  prebuilt package (or none at all). Its desktop entry is the Flathub ID plus
  `.desktop`.

`perks` are the notes the picker shows about how the app works with Cybex OS;
Software words each one. `-key` marks one the app gives up, such as
`-1password` ("Add the 1Password extension yourself"). Keys:

- `1password`: the 1Password extension and desktop app work together;
- `webapps`: web apps open in their own windows;
- `theme`: follows the Cybex theme;
- `tabs`: tabs and splits;
- `sandbox`: runs in a sandbox;
- `projects`: opens folders as projects;
- `terminal`: runs in your terminal;
- `kde`: brings KDE libraries (used as `-kde`);
- `library`: a music library and playlists;
- `annotate`: annotate and fill in forms;
- `noinstall`: nothing to install.

An option with the same id as a catalogue app uses that app's icon, name and
page. Any other option needs an icon. It takes Flathub's icon (from its
`flathub` or `appstream` ID), or, for an app Flathub doesn't carry, the
package's own `icon` file from cache.nixos.org (a hicolor `share/icons`
path). Ghostty, Alacritty, foot and Thunar use theirs this way. These icons
belong to their projects too.

## What a profile includes

A profile's `includes` lists what it brings besides its apps, such as Docker
or Steam. The installer's Software step shows these beside the apps. An entry
with an `id` gets `icons/<id>.png`. With an `appstream` ID, the icon comes from
Flathub like an app's. Without one, the generator renders `marks/<id>.svg` with
librsvg at 112 px, centred in 128 like a Flathub icon. An entry without an `id`
has no icon, and the installer shows a two-letter monogram.

| Mark | Source | Revision | Local treatment |
| --- | --- | --- | --- |
| `t3code.svg` | [T3 Code production logo](https://github.com/pingdotgg/t3code/blob/a3a8cbd60539b4af4de8f96c892dbd07a2b6c041/assets/prod/logo.svg) | `a3a8cbd60539b4af4de8f96c892dbd07a2b6c041` | None; byte-identical. |
| `docker.svg` | [Simple Icons: `docker`](https://github.com/simple-icons/simple-icons/blob/4a79bb55697c85b8bc9f3caa22be747e0277ad4f/icons/docker.svg) | `4a79bb55697c85b8bc9f3caa22be747e0277ad4f` | Upstream path, filled with Simple Icons' Docker blue `#2496ED`. |
| `podman.svg` | [Podman logo](https://github.com/podman-container-tools/podman/blob/a655633f2dcf3cce60bfce63d383d4e8e1ae67a2/logo/podman-logo-source.svg) | `a655633f2dcf3cce60bfce63d383d4e8e1ae67a2` | Wordmark and metadata removed, cropped to the seal mark, octagon filled white as on its light page. |
| `mangohud.svg` | [MangoHud icon](https://github.com/flightlessmango/MangoHud/blob/992103e4fb744897826de04ea00a2f71e7018214/data/io.github.flightlessmango.mangohud.svg) (v0.8.4, as in Nixpkgs) | `992103e4fb744897826de04ea00a2f71e7018214` | None; byte-identical. |

Simple Icons is CC0 1.0, T3 Code and MangoHud are MIT, and Podman is Apache
2.0. Their notices are in `marks/THIRD_PARTY_LICENSES.md`, which ships with the
icons as `THIRD_PARTY_LICENSES.md`.
