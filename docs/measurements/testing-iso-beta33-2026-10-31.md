# Testing ISO beta.33: default apps in Software — 2026-10-31

## Change

- **Software's home** starts with *Your default apps*: nine everyday jobs
  ([docs](../software-and-defaults.md#default-apps)). They are web browser,
  terminal, text editor, files, email, music, videos, documents and images.
  - Each card shows the app doing the job, and whether Cybex OS or you
    chose it.
  - A card opens a picker of apps Cybex OS has checked work for the job. It
    shows what keeps working with Cybex OS and how each app would arrive, and
    says what choosing one will do.
  - An installed app takes over at once. A NixOS app is installed through the
    install list, then takes over. A Flathub app installs for the account
    first.
  - Every switch has Undo. *Reset to Cybex picks* forgets the account's
    choices. An app's own page offers the same switch.
  - Settings → Applications covers the same nine jobs.
- **`cybexos-apps`** gains:
  - the files, email and music roles;
  - a choice that waits for its app to be installed;
  - `reset` and `cancel`;
  - `files`: Super+E opens the selected file manager;
  - Gmail and Outlook handlers for email links. They declare no MIME type,
    so they never become a default by accident.

  Alacritty and foot receive Cybex OS's window options directly. The dock
  suggests the chosen file manager.
- **Ghostty, Alacritty and foot** follow the shell's theme like kitty: there
  are new theme targets, and accounts get seeded configurations.
- **The Software catalogue** has `roles`. It was regenerated, which refreshed
  install counts and download sizes and fixed Chromium's desktop entry ID.

## Exact source and image

- Version: `1.0.0-beta.33`.
- Image source revision: `a7f608389683be12c9774e9fc86296ccc7ba1677` on `main`,
  built from a clean tree. The feature is `7485caed`.
- Source NAR: `sha256-nm8vnRrRgXIkYzRpj51XyxRTTEwj6vYV39kpefVE7pY=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged. `system.stateVersion` is unchanged. Linux 7.3.
- ISO SHA-256: `a102303e9dba1547b0dda399d941897431fe40eadfccce5b3e6d477b2ce5a5a3`.
- ISO size: 7,457,329,152 bytes (6.945 GiB).
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.33.iso` with
  `cybexos-1.0.0-beta.33.iso.sha256` (92 bytes).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

On the feature tree (`7485caed`, the same content without the VERSION
change):

- `nix develop -c tests/run` passed: 850 Python tests, 1,554 Node tests and
  the other suites.
- `tests/qml-lint` passed with no new warnings.
- `tests/software-app.py` passed. It drives the real Software app in
  Quickshell under headless Sway, now with a default-apps scenario:
  - Firefox at once, with Undo;
  - Ghostty through the install list;
  - Thunderbird from Flathub;
  - Reset to Cybex picks;
  - the switch from Firefox's page.

On `a7f60838`:

- These checks passed:
  - `checks.x86_64-linux.parity`;
  - `vm`, the lifecycle VM (240 s);
  - `hyprland-pointer` (70 s), with its new default-apps section: the roles
    and Cybex OS's picks, a web mail handler chosen and reset,
    `cybexos-apps files` opening Nautilus in real Hyprland, and the seeded
    terminal configurations and themes.
- `scripts/check-prebuilt` passed in its default, `--nvidia` and
  `--catalogue` modes: nothing compiles.
- Real Hyprland `--verify-config` passed on the payload system. The payload's
  `sw/bin` must come first on `PATH`, because the sandbox's `/bin/sh` links to
  the first `bash` it finds.
- `scripts/check-image-parity` passed all 42 checks against this ISO with the
  flake `git+file:///home/john/Code/CybexOS?rev=a7f60838…`. A `path:` copy of
  the same files has no Git revision, so its release file, `/etc` and system
  differ.

## Installation and staged-updater verification

The command was `scripts/qualify-installations --interactive --applications
standard --scenario lifecycle --case both`, through the real tty1 screen. It
started once GitHub's anonymous API limit had reset (59 of 60 calls left).

- **plain** passed all 22 milestones and all 10 lifecycle scenarios.
- **encrypted** passed all 22 milestones and all 10 lifecycle scenarios.
- The prebuilt store transfer copied 3,381 and 3,376 paths, in 103 s and
  114 s.
- `flathubApps`: `org.vim.Vim` 9.2.1161 (a 17.9 MB download) installed in
  30 s and 16 s, ran in its sandbox, and was removed.

The VM tests and the qualification ran in `agent-resource` leases
(`da9dd395…`, `c7569e4a…`), which closed with no errors.

Not exercised:

- physical hardware, a real PXE boot through iVentoy, and Secure Boot;
- switching a default app through Software in an installed session, with a
  real NixOS or Flathub install of the chosen app;
- Ghostty, Alacritty and foot running with the theme;
- email links through Gmail or Outlook in a real browser;
- the minimal application selection.

## PXE delivery

beta.33 was copied to a task staging directory on the same filesystem and
hashed against the build. It was then moved into `/data/pxe/iso`, where its
checksum verified. beta.32 and its checksum were removed (7,457,329,152 plus
92 bytes); no other image was there.

`refresh_img_list` returned `result: success`, and `get_img_tree` listed only
beta.33. `get_img_summary` kept a stale count of 2, so iVentoy was restarted
with the AGENTS.md guard: `config.dat` was copied aside first.

**The restart came up with defaults again, as with beta.32.**
- The stopping process took 12 s and saved a `config.dat` without the network
  settings (9,222 bytes; the copy had 9,234).
- The new process logged `Recover: ip:0.0.0.0` and looped in auto-restart.
- The unit was stopped. The copy, which holds 10.10.0.7 at the same offset as
  `/data/pxe/config-backups/initial-config.tar.gz`, was put back, and the unit
  was started.
- PXE was down for about a minute (14:46:47–14:47:42).

The log then showed these settings recovered:
- `Recover: ip:10.10.0.7 mask:255.255.254.0 gateway:10.10.0.1 pool:[10.10.0.200-10.10.0.219]`;
- HTTP 16000, NBD 10809, iSCSI 3260, TFTP 5/3;
- both Windows 11 bypasses;
- deny-mode MAC and user filters.

Afterwards:
- `query_status` reported `running`;
- `get_img_tree` listed only beta.33 (image 1), and `get_img_summary`
  reported `count: 1`;
- iVentoy listened on its DHCP proxy, TFTP, HTTP, NBD and iSCSI ports;
- `iventoy.service` was `active`.

The defaults it had saved were kept in the task's staging directory for review
and then deleted.
