# Testing ISO beta.26: hardware assessment and driver coverage — 2026-10-30

This image implements the [hardware support policy](../hardware-support.md):
both Intel and AMD early microcode, more wired PXE drivers, NVIDIA selection
from the exact packaged device catalogue, shared installer checks before disk
inspection or erasure, and the read-only `cybex hardware` inventory. Hardware
detection is not represented as a physical compatibility pass.

## Exact source and image

- Version: `1.0.0-beta.26`.
- Frozen image/source revision:
  `2ae0597edbd8734433392df37250e4091fa19f4d` on `main`.
- Source NAR: `sha256-vuPHfgcXLL581QL1hr19ze0ySMHRTogQ3WTW/oXUHOI=`.
- Source: `/nix/store/vmr6qnmmplggl4v8sznvlxsh2vpjwfff-source`.
- Nixpkgs: `nixos-unstable` at
  `31ecbaca1bdefa45dffc409f0250bd8039ea0010`, unchanged.
  `system.stateVersion` is unchanged.
- Linux 7.3.0, Mesa 26.2.5 and Linux firmware 20261019.
- ISO SHA-256:
  `6c1aa470918507a165a570a52e934b29e46462068133ee3b44807272049ed3ec`.
- ISO size: 7,355,400,192 bytes (6.850 GiB).
- Build output:
  `/nix/store/r507fpf14kvdwfd0wh4blizbyis687r4-cybexos-1.0.0-beta.26-x86_64-linux.iso/iso/cybexos-1.0.0-beta.26-x86_64-linux.iso`.

This measurement record was written after the image source was frozen; it is
not part of that NAR. The installed source has the same exact NAR. Its bundled
path input has no Git revision metadata, so the installed release reports
`revision: uncommitted`; the ISO reports the revision above. Qualification
checks the exact NAR and each environment's own release metadata.

## Source, build and image checks

- The complete `tests/run` suite passed at `df13b26d`: 822 Python tests,
  1,546 Node tests passed and 17 skipped, plus the ancillary suites. The only
  subsequent implementation change moves graphics-store refresh before the
  disk-selection guard. Final-source validation includes the kiosk's 47 Rust
  tests (29 unit, 14 interaction and 4 other tests) and the Nix checks below.
- Final-source Nix checks passed: `lifecycle`, `parity`, `product`,
  `xps-system` and `nvidia-kernels`. These checks do not qualify physical
  NVIDIA rendering or the XPS camera.
- Final-source `scripts/check-prebuilt --catalogue` and
  `scripts/check-prebuilt --nvidia` passed. The Nixpkgs cache policy and
  insecure-package policy were preserved.
- The ISO build passed, followed by all 42 `scripts/check-image-parity`
  checks against the frozen source above. The checks include the exact
  hardware catalogue in the live system and bundled installed payload.
- Inspection of the built initrd confirmed `GenuineIntel.bin`,
  `AuthenticAMD.bin` and the added `ice`, `i40e`, `bnx2x`, `mlx4_en`,
  `mlx5_core`, `asix` and `rndis_host` modules. Configuration parity checks
  the complete required early-network list.
- The runtime NVIDIA catalogue contains compact JSON, without the vendor
  installer archives. It was extracted from open 595.112.07 (832 supported
  identities) and closed 580.196.07 (1,046 identities), excluding entries
  assigned to other legacy branches. Fixtures exercise open-supported,
  closed-only, unsupported, subsystem-restricted, open-only and mixed GPU
  selections, and ignore NVIDIA devices outside the display class.

## Installation and staged-updater verification

The isolated run uses the exact image above and the frozen source's
`scripts/qualify-installations --interactive --applications standard --case both --scenario lifecycle`.
It drives the real tty1 graphical installer through QMP keyboard and pointer
input, boots the installed system and exercises the real staged updater.
Virtual hardware inventories retain `not-run` for physical qualification.

The plain installation passed all 19 checked milestones plus the measured
prebuilt transfer (3,372 store paths in 96.957 seconds). Installation took
197 seconds. Live and installed `cybex hardware` reports matched their own
release metadata, reported Linux 7.3.0 and inventoried the virtual devices;
the live network driver was `virtio_net`.

All 10 plain-install lifecycle scenarios passed: automatic preparation,
upstream staging with the vendor channel unavailable, kernel update and
rollback, personal baseline, evaluation failure, build failure, interrupted
stage recovery, unconfirmed-trial fallback, local apply/boot/confirmation,
and rollback with personal configuration persistence. Kernel trial and
rollback exercised 6.18.59 and 7.3.0. The independent upstream staging check
kept the same Nixpkgs revision and did not apply it; this is not evidence of
an update to changed upstream packages.

The encrypted installation also passed all 19 checked milestones and all 10
lifecycle scenarios. Its prebuilt transfer copied 3,367 store paths in 82.501
seconds; installation took 174 seconds. It exercised disk unlock followed by
automatic desktop login and an unlocked keyring. Two real password-change
round trips rejected the old disk key, rebooted successfully with the new
password and unlocked the stored keyring secret. The plain case also passed
two password-change round trips and subsequent password desktop login.

Both cases passed installed source identity, boot menu and quiet-boot checks,
ZFS module/I/O checks, authenticated desktop health, first-login welcome,
keyboard shortcut changes/reset, real SSH/updater authorization prompts and
personal configuration persistence. Both live and installed inventories
remained explicitly unqualified for physical hardware. The complete run
finished successfully in 1,815.881 seconds (30.3 minutes).

## PXE delivery

The completed ISO and checksum were first staged outside the served tree in
`/data/pxe/.hardware-compat-1UvVtIKf`. The served copy then verified against
the SHA-256 above in `/data/pxe/iso`. Only after that verification, beta.25
and its checksum were removed (7,319,273,472 plus 92 bytes). No other
operating system's image was changed.

`refresh_img_list` returned `result: success`; the new image appeared in
`get_img_tree`, but `get_img_summary` retained a stale count of 2. After
`sudo systemctl restart iventoy.service` and retrying an API read that timed
out during startup, `query_status` reported `running`, `get_img_tree` listed
only `cybexos-1.0.0-beta.26.iso` (image 1), `get_img_summary` reported
`count: 1`, and `iventoy.service` was `active`. This verifies delivery and
service state, not a real LAN PXE boot.

The retained testing deliverables are
`/data/pxe/iso/cybexos-1.0.0-beta.26.iso` (7,355,400,192 bytes) and
`/data/pxe/iso/cybexos-1.0.0-beta.26.iso.sha256` (92 bytes).

## Resource cleanup

Qualification used supervised `agent-resource` lease
`952c87b07871486b9461646d62f1e17e` and the CI controller's 16 GiB/4 CPU
capacity reservation. The wrapper exited successfully and closed the
reservation. `agent-resource check` reports the lease `closed`, with no
remaining resources, preserved volumes or errors; its workspace is absent.
An earlier startup attempt failed before creating a VM; its lease
`207c1a18b5614d31adc8c097c7a48d20` was also checked closed and empty.

The task's temporary logs, qualification evidence files and build-output
symlink were removed with
`/home/john/.local/share/cybexos/images/hardware-compat-leew2w`; the empty
private PXE staging directory `/data/pxe/.hardware-compat-1UvVtIKf` was
removed too. Both staging paths and the lease workspace were checked absent,
with no task-owned qualification/QEMU processes or mounts remaining. Shared
Nix store/cache paths and unrelated artifacts were left intact. Only the
served ISO/checksum and repository documentation are retained as testing
deliverables.

## Limits

This is VM installation and lifecycle evidence, not a physical hardware
matrix. No physical Intel/AMD chipset, NVIDIA GPU, radio, dock, camera,
suspend/resume or real LAN PXE boot was qualified by this run. The
[physical procedure](../hardware-support.md#collecting-a-physical-qualification-record)
remains outstanding. No signed published-channel update was exercised.

Secure Boot installation remains blocked before erasure pending signed
media, authenticated payload, enrollment and module signing. The exact XPS
IPU7 camera's private-ABI blocker remains guarded; no camera support was
removed to make qualification pass. Broadcom STA remains disabled because
the pinned package is insecure; nonredistributable `b43` firmware was not
added. No host OS change, host reboot or physical installation was performed.
