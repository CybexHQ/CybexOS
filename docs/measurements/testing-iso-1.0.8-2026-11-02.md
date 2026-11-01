# Testing ISO 1.0.8: starting from a Ventoy stick — 2026-11-02

## Why

A tester's Ventoy stick reached emergency mode with 1.0.7. Reproduced with
Ventoy 1.1.18 in a UEFI VM: both of Ventoy's modes, "normal" and "grub2",
start the ISO's boot menu through Ventoy's own GRUB. That GRUB renames every
`init=` kernel parameter to `vtit=` and adds `rdinit=/vtoy/vtoy`. Ventoy did
map and mount the medium correctly (`/dev/mapper/ventoy`, labelled
`CYBEXOS_INSTALL`; the squashfs and store overlay mounted), but
`initrd-find-nixos-closure` failed: "No init= parameter on the kernel command
line". `c98d610f` adds `cybexos-ventoy-init`, which, only in that case,
restores `init=` over `/proc/cmdline` in stage 1
([installation](../installation.md#writing-the-installation-medium)).

## Exact source and image

- Version: `1.0.8` (`VERSION` only, `b2166aee`).
- Image source revision: `b2166aee88513bd901488e0a44e067226bdd24b6` on
  `main`, built with
  `nix build 'git+file:///home/john/Code/CybexOS?rev=b2166aee…#packages.x86_64-linux.iso'`.
  Other uncommitted work in the checkout was not part of the build.
- Source NAR: `sha256-uVsCBRe+uWYVPLonVEhFW0Fyli8DWBAf5Mr0GGOjW3c=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged since 1.0.0. `system.stateVersion` is unchanged.
- ISO: `cybexos-1.0.8-x86_64-linux.iso`, served as `cybexos-1.0.8.iso`.
- ISO SHA-256: `22e72fa78a7da2d4f7328166ce26096a2e11d73afd17900a02d3d1b4da782c09`.
- ISO size: 7,457,329,152 bytes (6.945 GiB).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

On `b2166aee`, from a `git archive` export:

- `nix develop -c tests/run` passed: 899 Python tests in the main suite,
  1,559 Node tests and the remaining suites.
- `scripts/check-prebuilt` (default mode) passed: only configuration and the
  expected local builds.
- `scripts/check-image-parity` passed all 43 checks against this ISO,
  including the new `cybexos-ventoy-init` assertions in `nix/tests/parity.nix`.

## Ventoy

Ventoy 1.1.18 (`ventoy-1.1.18-linux.tar.gz`, SHA-256 matching the release's
`sha256.txt`) installed with `Ventoy2Disk.sh -I` onto a 9 GiB loop-backed
image, the ISO copied onto its exFAT partition, booted under OVMF (Secure Boot
off) as a QEMU `usb-storage` stick with a 40 GiB virtio disk and user-mode
networking, in an `agent-resource` lease.

- 1.0.7, both modes: emergency mode, `initrd-find-nixos-closure.service`
  failed, `/proc/cmdline` held `vtit=/nix/store/…/init` and
  `rdinit=/vtoy/vtoy`. Restoring `init=` by hand from the emergency shell and
  continuing reached the installer.
- 1.0.8, grub2 mode and normal mode: each reached the installer without
  intervention, with the release verified as "Cybex OS 1.0.8, Bundled
  installation source".
- The disk step listed the Ventoy stick as unusable ("Selected disk is
  mounted or smaller than 64 GiB"): `lsblk` shows the mounted
  `/dev/mapper/ventoy` (`/iso`) beneath it. That stick was also under 64 GiB,
  so the reason covers both conditions here.
- On a test build of the same change, the ISO attached directly as a USB
  stick (no Ventoy) still started normally: the unit's conditions skipped it
  and `/proc/cmdline` carried `init=`. In stage 2, `/proc/cmdline` shows
  Ventoy's original line again; the overlay only lasts through stage 1.

Not exercised: physical hardware, Ventoy's legacy BIOS mode, Secure Boot with
Ventoy's enrolled key, and other Ventoy versions.

## Installation and staged-updater verification

`scripts/qualify-installations --interactive --applications standard
--scenario lifecycle`, through the real tty1 installer screen. The two cases
ran in parallel, each in its own `agent-resource` lease with its VM disks in
the lease workspace (`f75995f8…`, `5d663a24…`); both leases closed with no
remaining resources or errors.

- **plain**, with `--display 1440x900 --disk virtio-without-serial`, passed
  all 22 milestones and all 10 lifecycle scenarios.
- **encrypted**, at the default 1280×800 on a virtio disk with a serial
  number, passed all 22 milestones and all 10 lifecycle scenarios.
- Both installed systems reported the ISO's release identity: 1.0.8 with the
  NAR above (bundled path inputs carry no Git revision, as before).
- The prebuilt store transfer copied 3,384 and 3,380 paths, in 124 s and
  156 s.

## PXE delivery

The ISO was copied into the task staging directory on the same filesystem,
hashed against the build, and moved into `/data/pxe/iso` with its checksum,
where it verified. `cybexos-1.0.7.iso` and its checksum were removed; the
1.0.2 `build.json`, `packages.txt` and `qualification.json` were left in
place.

`refresh_img_list` returned `result: success` and `get_img_tree` listed only
1.0.8, but `get_img_summary` kept a stale count of 2. iVentoy was restarted
with the AGENTS.md guard: `config.dat` (9,234 bytes) was copied aside first,
and the restart logged `Recover: ip:10.10.0.7 mask:255.255.254.0
gateway:10.10.0.1 pool:[10.10.0.200-10.10.0.219]`, so the copy was not needed
and was deleted. Afterwards `query_status` reported `running`, the list and
the summary showed only `cybexos-1.0.8.iso` (`count: 1`), and
`iventoy.service` was `active`.

Not published as a GitHub release.
