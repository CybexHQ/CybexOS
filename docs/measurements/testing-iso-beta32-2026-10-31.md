# Testing ISO beta.32: Flathub in Software, downloaded programs and AppImages — 2026-10-31

## Change

- **Software** has a second source, Flathub ([docs](../software-and-defaults.md#flathub)).
  Search lists Flathub apps the catalogue does not show. An app's page shows
  the sandbox access the app asks for. Installs go to the signed-in account
  only (`flatpak --user`), right away, without authorization or a restart.
  Installed and Updates have Flathub sections. A catalogue app NixOS cannot
  install yet offers its Flathub version. Each account gets the `flathub`
  remote once, at its first sign-in, from the repository file that ships with
  Cybex OS; `cybexos.features.flathub` turns the source off.
- **Downloaded programs** run through nix-ld, with the libraries NixOS's
  AppImage runtime uses, and binfmt starts AppImages. Nothing compiles; the
  product closure grows by about 10 MB.
- **AGENTS.md**: Nixpkgs follows the latest stable NixOS release and takes no
  packages from `nixos-unstable`; this tree stays on `nixos-unstable` until
  NixOS 26.11 ships.
- **Qualification** has a `flathubApps` milestone: a real app from
  flathub.org is installed, run and removed in the installed session.

## Exact source and image

- Version: `1.0.0-beta.32`.
- Image source revision: `c4d30909d739d958fe03ddb48629005a9b1c4137` on `main`,
  built from a clean tree.
- Source NAR: `sha256-JnRJQAMBE7VlEOoaARpr7sn8uE4x7AD5ROcT2TIhRt4=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged; `system.stateVersion` is unchanged. Linux 7.3.0.
- ISO SHA-256: `82e9fcede0a94e0fffcf9bd6021ddaa77f9acae4d854ffbefd3b153cbccf999b`.
- ISO size: 7,457,329,152 bytes (6.945 GiB).
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.32.iso` with
  `cybexos-1.0.0-beta.32.iso.sha256` (92 bytes).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

On the development tree of `fb616358` (the feature and policy commits):

- `nix develop -c tests/run`: 840 Python tests (19 skipped), 1,565 Node tests
  (1,548 passed, 17 skipped) and the other suites passed; `tests/qml-lint`
  passed with no new warnings.
- `tests/software-app.py`: the real Software app in Quickshell under headless
  Sway, including Flathub search, an app page, install → open, Installed with a
  confirmed removal, Flathub updates and the offer on a blocked catalogue app.
- `checks.x86_64-linux.parity`, `hyprland-pointer` (with the new
  software-flexibility checks) and `vm` (the lifecycle VM) passed.
- `scripts/check-prebuilt`: nothing compiles.

On `c4d30909`: real Hyprland `--verify-config` passed on the payload system,
and `scripts/check-image-parity` passed all 42 checks against this ISO.

## Installation and staged-updater verification

`scripts/qualify-installations --interactive --applications standard
--scenario lifecycle --case both`, through the real tty1 screen:

- **First run, source `323d020a`** (ISO `f4b01aa1…3a89`): both cases passed
  21 of 22 milestones and all 10 lifecycle scenarios. `flathubApps` got as far
  as the sandboxed run: the remote existed after the first sign-in, search and
  details came from flathub.org, `org.vim.Vim` installed through the transient
  user service, its launcher and icon were exported, and the shell's data path
  held them. `flatpak run` exited 0, but the check took Flatpak's note about
  a data path without its exports (the `runuser` environment had none) as
  Vim's version line. `c4d30909` starts the app with the shell's
  `XDG_DATA_DIRS`, as a launcher does, and finds the version line. The ISO was
  rebuilt; the number had not been served.
- **Second run, this ISO**, started once GitHub's anonymous API limit had reset
  (10 of 60 calls were left after the first run): **plain** and **encrypted** passed
  all 22 milestones and all 10 lifecycle scenarios. `flathubApps`:
  `org.vim.Vim` 9.2.1161, a 17.9 MB download, installed in 21 s and 16 s,
  ran in its sandbox ("VIM - Vi IMproved 9.2"), and was removed with its
  runtimes.

Both runs used `agent-resource` leases (`511756fa…`, `631d6eef…`), which
closed with no errors.

Not exercised: physical hardware, a real PXE boot through iVentoy, Secure Boot,
Flathub apps' fonts, icons, pointer theme and portals under Hyprland, a real
AppImage, and the minimal application selection.

## PXE delivery

beta.32 was copied to a task staging directory on the same filesystem, hashed
against the build and moved into `/data/pxe/iso`, where its checksum verified.
beta.31 and its checksum were removed (7,457,329,152 plus 92 bytes); no other
operating system's image changed. `refresh_img_list` returned `result: success`
and `get_img_tree` listed only beta.32, but `get_img_summary` kept a stale
count of 2, as with beta.27.

**The restart that followed broke PXE for about six minutes.** iVentoy's log
shows the new process starting at 11:39:21 while `data/config.dat` was absent
("can not stat, skip recovery"): it came up with defaults (DHCP server IP
`0.0.0.0`), could not auto-start PXE and exited. systemd restarted it every
five seconds, and each stop saved the defaults back. The unit was stopped, the
rollback archive's `config.dat` (`/data/pxe/config-backups/initial-config.tar.gz`,
the unit file unchanged since) was installed, and the service started again.
Every recovered setting matched the last good start at 00:25:34: ProxyNet mode
4 on 10.10.0.7/23, gateway 10.10.0.1, pool 10.10.0.200–219, HTTP 16000, NBD
10809, iSCSI 3260, TFTP 5/3, both Windows 11 bypasses, deny-mode MAC and user
filters. Afterwards `query_status` reported `running`, `get_img_tree` listed
only beta.32 (image 1), `get_img_summary` reported `count: 1`, iVentoy was
listening on its DHCP proxy, TFTP, HTTP and NBD ports, and `iventoy.service`
was `active`. The defaults it had saved were kept in the task's staging
directory for review and then deleted.
