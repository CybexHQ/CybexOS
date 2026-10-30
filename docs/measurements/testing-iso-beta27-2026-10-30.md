# Testing ISO beta.27: native display drivers in stage 1, and proprietary-app qualification — 2026-10-30

On beta.25 the Minisforum X1 Pro 370 (Ryzen AI 9 HX 370, Radeon 890M
`1002:150e`, PCI class `0x0380`) booted through iVentoy showed no splash or
progress bar, and **Show all boot messages** showed garbled text, while the
boot menu and the installer screen looked right. The same machine showed the
same corruption on [Oct 23](pxe-boot-2026-10-23.md): Linux's view of the
firmware framebuffer is unusable there, and the native driver is not.

## Cause

- beta.2 ([graphics](installer-graphics-beta2-2026-10-23.md)) started the
  native display drivers in stage 1. The shared hardware module did that only
  for `cybexos.enable`; when the medium became the tty1 installer (2730bd4e,
  Oct 24) it set `installationMedium` instead, and the drivers silently left
  its initrd. The same gap had kept early microcode off the medium until
  beta.26.
- beta.24 then drew the splash on that framebuffer on purpose
  (`plymouth.use-simpledrm`), because the initrd had no native driver.
- beta.25's iVentoy client log from the X1 Pro shows simpledrm from 1.85 s,
  the medium's command line with `splash plymouth.use-simpledrm`, and the ISO
  attached over NBD at 15.5 s. Nothing in stage 1 failed; the screen did.

## Change

- `nix/modules/default.nix`: amdgpu, radeon, i915, xe and virtio_gpu are
  available in stage 1 on the medium and installed systems alike. Installed
  systems still add nouveau (`hardware.nix`): with it the medium's initrd is
  1.4 GB, without it 110 MB (58 MB before).
- `nix/modules/installer.nix`: no `plymouth.use-simpledrm`. The splash waits
  for the native driver and takes the firmware framebuffer after Plymouth's
  eight-second device timeout (NVIDIA until nouveau loads in stage 2; until
  then GRUB's last frame stays). The udev rule that makes Plymouth re-probe a
  new DRM device also runs in the initrd.
- `scripts/qualify-installations`: with the standard selection the reviewed
  plan must keep proprietary applications on, 1Password must be installed, the
  open welcome guide's Connect step must offer it, and `cybex software check`
  must rate every unfree catalogue app as a vendor download that compiles
  nothing (`proprietaryApplications`). The minimal selection checks the
  reverse.

On a slim task ISO of this change in QEMU: with virtio-gpu, GRUB's loading logo
stayed until the native driver drew the splash and bar at 7 s, with no dark
frame; with standard VGA (no stage-1 driver) the splash appeared at about 9.5 s;
**Install with basic graphics** showed it on the firmware framebuffer at 6 s.

## Exact source and image

- Version: `1.0.0-beta.27`.
- Image source revision: `b07b93c09b2f8f7d6af0a57a4650fe32c6637e80` on `main`,
  built from a clean tree.
- Source NAR: `sha256-R0Io1/GaRst70bhC/u41WdS8FvtISxt3Wo5n5LzGeJo=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged; `system.stateVersion` is unchanged. Linux 7.3.0.
- ISO SHA-256: `2f5a4b16cfe2b79c9fdba3900cdff4737a2cb24c9cf80f671670ef4ee75b964a`.
- ISO size: 7,457,329,152 bytes (6.945 GiB). Its initrd is 110,588,402 bytes,
  with the five drivers above, 687 amdgpu firmware files, no nouveau, and the
  re-probe rule in `99-local.rules`.
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.27.iso` with
  `cybexos-1.0.0-beta.27.iso.sha256` (92 bytes).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

- `nix develop -c tests/run`: 822 Python and 1,563 Node tests (1,546 passed,
  17 skipped) and the other suites passed.
- `checks.x86_64-linux.parity` (now asserting the stage-1 drivers, no nouveau
  on the medium, no `plymouth.use-simpledrm` and the initrd rule) and the ISO
  built. Real Hyprland `--verify-config` passed on the payload system.
- `scripts/check-image-parity` against `b07b93c0`: all 42 checks passed.

## Installation and staged-updater verification

`scripts/qualify-installations --interactive --applications standard
--scenario lifecycle`, through the real tty1 screen:

- **Plain** passed: every milestone, including `proprietaryApplications`
  (1Password installed, Connect card `available`, Discord, Chrome, Obsidian,
  Postman, Slack, Spotify, Vivaldi, VS Code and Zoom rated prebuilt vendor
  downloads), and all 10 lifecycle scenarios.
- **Encrypted** first **failed** at the start of its lifecycle: the guest's
  update check met GitHub's anonymous API rate limit ("Cannot qualify
  independent upstream discovery"). beta.26's qualification on the same host
  address had used it shortly before. Its installation and first-login
  milestones, `proprietaryApplications` included, had passed. A rerun of the
  encrypted case at 19:24, with 47 of 60 calls left, passed every milestone
  and all 10 lifecycle scenarios.

Both runs used `agent-resource` leases (`ef00d7f3…`, `aea8353a…`), which closed
with nothing left.

Not exercised: the X1 Pro itself or any physical GPU, a real PXE boot through
iVentoy, Secure Boot, and NVIDIA machines' stage-1 fallback.

## PXE delivery

beta.27 was copied to a task staging directory on the same filesystem, hashed
against the build and moved into `/data/pxe/iso`, where its checksum verified.
beta.26 and its checksum were removed (7,355,400,192 plus 92 bytes); no other
operating system's image changed. `refresh_img_list` returned `result: success`
and `get_img_tree` listed only beta.27, but `get_img_summary` kept a stale
count of 2. After `sudo systemctl restart iventoy.service`, `query_status`
reported `running`, `get_img_tree` listed only beta.27 (image 1),
`get_img_summary` reported `count: 1`, and `iventoy.service` was `active`.
