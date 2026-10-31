# Production ISO 1.0.0 — 2026-10-31

The first ISO without a prerelease tag. It also carries the medium review's
fixes for booting and installing on more computers.

## Change

**Production media.**
- `VERSION` is `1.0.0`. The boot menu, installer, release metadata, system
  label (`CybexOS-1.0.0-26.11`) and file name (`cybexos-1.0.iso`, served as
  `cybexos-1.0.0.iso`) carry no tag. The update channel defaults to `stable`.
- `release/keys/trust.json` holds two owner-generated Ed25519 public keys,
  valid from 2026-10-31 to 2031-10-31: `cybexos-release-2026-10` (purpose
  `release`) and `cybexos-channel-2026-10` (purpose `channel`). Installed
  machines can therefore verify later releases and channels.
- A keyed final medium first looks for its own signed release. If that
  cannot be read (not published yet, or offline), it installs its own
  content-verified source, labelled *bundled source verified*, without the
  development-build question. A release that is read must still verify and
  match the medium; that never falls back.

**Repository identity.**
- Updates follow `CybexHQ/CybexOS`, which the release and promote workflows
  publish to. Development moved there on 2026-10-29.
- Before this change the updater still looked for releases, channels and
  sources at `DigitalPals/CybexOS`.
- A machine installed from the bundled source names that store path as its
  Cybex OS input; its first authenticated release update replaces it with
  the release's GitHub revision.

**Installer.**
- **eMMC/SD disks** (`mmcblk*`, never the boot or RPMB areas) are targets.
  The disk list shows them as eMMC or SD card. `nixos-generate-config`
  records their host driver for the installed initrd.
- **Disks without a serial number** (most virtual disks) are identified by
  WWN, else by kernel device path and size. That identity is checked between
  the review and the erase.
- **The recovery shell.** Losing the VT no longer panics in Slint's
  unimplemented seat `Disable`. The screen exits cleanly; its restart waits
  for tty1, then draws the service's state again. The seat is polled while
  the screen runs.
- **A missing medium.** If the medium is still missing after two minutes
  (was five), stage 1 quits the splash and explains, in plain text, how to
  write the medium and what to check.

**Docs and tools.**
- The docs say how to write the stick (raw image only; not Rufus's ISO
  mode, because `nix-store.squashfs` exceeds FAT32's 4 GB limit). They also
  say Secure Boot must be off to install: the medium is unsigned, and the
  installer refuses while Secure Boot is on.
- `scripts/qualify-installations` gains
  `--disk virtio|virtio-without-serial|emmc`.

## Exact source and image

- Version: `1.0.0`.
- Image source revision: `7e6efbbf8a5cb820e16e94297ca1e768c41dad98` on
  `main`, built from a clean tree. The changes are `9f994f84`, `c3e9eab2`,
  `60b2a8d5` (VERSION) and `7e6efbbf`.
- Source NAR: `sha256-h6aGSjyzISG5WBYdxN/E/WdiQqz+GeSleOolyMiFxxc=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged. `system.stateVersion` is unchanged. Linux 7.3.
- ISO SHA-256: `759cde1037a30d6d6fb762caef84510c22b9eaf87884efa8978abbb16f6ea569`.
- ISO size: 7,457,329,152 bytes (6.945 GiB).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

On the change tree:

- `nix develop -c tests/run` passed, with 858 Python tests. New tests cover:
  - the bundled fallback (unpublished, and offline);
  - a published release that fails its signature or identity check;
  - device-path and WWN disk identity;
  - eMMC disk paths.
- The installer screen's Rust tests passed: 30, 15 and 4.
- `checks.x86_64-linux.parity` passed. It asserts the Thunderbolt option,
  the missing-medium unit, the two-minute device wait and the fallback hook.
- A sign-and-verify round trip through `release/manage.py` passed for both
  keys. A channel key used for a release signature was rejected.

On `7e6efbbf`:

- `scripts/check-image-parity` passed all 42 checks against this ISO.
- `scripts/check-prebuilt` passed from an export of the revision.

**VM probes** (QEMU, virtio-gpu at 2880×1800, OVMF, 4 GiB):
- **The screen** drew the welcome page at zoom 2.25 with no restarts.
  `thunderbolt.host_reset=0` was on the command line.
- **Leaving for tty2:**
  - the screen logged `the session lost its seat; exiting to be restarted`;
  - it restarted once and waited (`activating`), with no text-installer
    switch;
  - back on tty1, it drew again within 15 s, still with one restart.
- **Three `SIGABRT`s** produced `The installer screen failed 3 times within
  a minute (core-dump); asking for the text installer`. The text installer
  opened on tty1 with *Cybex OS 1.0.0 • bundled source verified* and no
  development-build question. It then stopped at *No installation disks
  found*, because the probe VM had no disk.
- **The medium's kernel and initrd without the ISO:** after 2 minutes the
  splash ended and the help text appeared on the console.

## Installation and staged-updater verification

The command was `scripts/qualify-installations --interactive --applications
standard --scenario lifecycle`, through the real tty1 screen. The two cases
ran in parallel, each in its own `agent-resource` lease (`e88585f1…`,
`17de27b4…`); both leases closed with no errors.

- **plain**, with `--display 1440x900 --disk virtio-without-serial`, passed
  all 22 milestones and all 10 lifecycle scenarios.
  - The disk had no serial number. The disk step listed and preselected it,
    and the review and erase checks passed on its device identity.
  - A 1440×900 frame is not a whole number of pages; this is the screen
    crash fixed in beta.34.
- **encrypted**, at the default 1280×800 on the serial-numbered virtio disk,
  passed all 22 milestones and all 10 lifecycle scenarios.
- Both installed the medium's bundled source through the keyed fallback
  (`v1.0.0` is not published), with no development-build question.
- The prebuilt store transfer copied 3,381 and 3,376 paths, in 104 s and
  127 s.
- `flathubApps`: `org.vim.Vim` installed in 21 s and 16 s and ran.

The same two cases had also passed on `60b2a8d5`, which lacked only the
missing-medium text fix.

**eMMC was not qualified in QEMU.** On `60b2a8d5`, an install-only run onto
QEMU 11.1's emulated eMMC (`sdhci-pci` with `emmc`, 80 GiB) behaved as
follows:
- It listed and selected `/dev/mmcblk0` and wrote both partitions.
- `mkfs.ext4` took about 50 minutes: the emulated device carried out its
  discard by writing the whole partition, and the image grew to 65 GB.
- Mounting the new file system then failed with `can't read superblock on
  /dev/mmcblk0p2`.

A probe on this ISO with an 8 GiB emulated eMMC showed this is the
emulator, not the installer:
- The disk identified as an MMC device with serial `0xdeadbeef`, and
  partitioning worked.
- Even `mkfs.ext4 -E nodiscard` ended in `mmc0: Card stuck being busy!`,
  followed by write I/O errors on `mmcblk0` and the same mount failure.

QEMU's `emmc` device was written for BMC boards and does not work with
Linux's SDHCI driver here. Installation onto eMMC is enabled but unverified
until it runs on real eMMC hardware.

## PXE delivery

1.0.0 was copied to a task staging directory on the same filesystem and
hashed against the build. It was then moved into `/data/pxe/iso` as
`cybexos-1.0.0.iso`, where its checksum verified. beta.34 and its checksum
were removed; no other image was there.

`refresh_img_list` returned `result: success`, and `get_img_tree` listed only
1.0.0. `get_img_summary` kept a stale count of 2, so iVentoy was restarted
with the AGENTS.md guard.
- `config.dat` (9,234 bytes) was copied aside first.
- The restart logged `Recover: ip:10.10.0.7 mask:255.255.254.0
  gateway:10.10.0.1 pool:[10.10.0.200-10.10.0.219]`, so the copy was not
  needed and was deleted.

Afterwards:
- `query_status` reported `running`;
- `get_img_tree` listed only `cybexos-1.0.0.iso` (image 1), and
  `get_img_summary` reported `count: 1`;
- iVentoy listened on its DHCP proxy, TFTP, HTTP, NBD and iSCSI ports;
- `iventoy.service` was `active`.

## Not exercised

- **Real hardware:** the XPS 14, a real iVentoy network boot of 1.0.0,
  Secure Boot, and an installation onto eMMC.
- **A physical Thunderbolt dock or display, and several monitors.**
- **A published signed release or channel.** No `v1.0.0` release exists, so
  the signed path was not taken. The keyed medium's 404 fallback was
  exercised in every installation above.
- **The initrd's maintenance shell** did not appear on the console after the
  missing-medium help in the VM test. This was not investigated.
- **Cosmetic:** the text installer's ASCII logo renders as stray characters
  in the console font.
