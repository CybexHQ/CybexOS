# Testing ISO beta.21: latest kernel — 2026-10-30

The installer and every installed hardware profile now default to the machine's
Nixpkgs `linuxPackages_latest`: Linux 7.3 (`uname -r`: `7.3.0`) for this image.
The previous installer pin to 7.2 and the XPS-only latest-kernel default are
removed. A deliberately configured personal kernel override remains supported.

## Exact source and image

- Version: `1.0.0-beta.21`.
- Image and installed-source revision: `c25c92080ef0f174ee928826351c3977263b117e`.
- Source NAR: `sha256-PX2naap/UG88SX5CPxDoRsD/aYya6B0Je6mh3use+vg=`.
- ISO SHA-256: `7b783592e98f4d2864c15351acb316891a2574702ee1ba52fc1fd76c84b872a1`.
- ISO size: 6,940,846,080 bytes (6.464 GiB).
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.21.iso` with
  `cybexos-1.0.0-beta.21.iso.sha256` (92 bytes).

The image and qualification use the same committed Git flake. This later
documentation record is not the image's source revision. `flake.lock` remains
unchanged: Nixpkgs follows `nixos-26.05`, pinned to
`da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36`; `system.stateVersion` is unchanged.

## Hardware compatibility

The shared kernel package set retains ZFS and both supported NVIDIA families.

- ZFS 2.4.4 needs five reviewed OpenZFS Linux 7.3 API backports. They are
  applied only to that exact ZFS/kernel combination when Nixpkgs marks the
  module incompatible. The package keeps Nixpkgs' recipe and compatibility
  check, without globally permitting broken packages. The backports preserve
  the existing pool features and userspace.
- The 595 NVIDIA family uses Nixpkgs' 595.112.07 point release, which includes
  Linux 7.3 fixes, with matching userspace, settings, persistence daemon and
  kernel sources. Its version and hashes come from upstream Nixpkgs revision
  `31ecbaca1bdefa45dffc409f0250bd8039ea0010`. The installed machine's own
  driver recipe and dependencies are reused; no extra Nixpkgs input is added.
- The legacy closed NVIDIA family remains 580.178.04. Both families and
  matching userspace build against 7.3; vendor objtool warnings in the closed
  module build did not prevent completion. This is build evidence, not
  physical GPU qualification.

Both compatibility overrides stop applying when the machine's Nixpkgs provides
the compatible package or advances beyond this kernel combination.

## Build and image verification

The exact source passed all six requested builds: ISO, shared installation
parity, lifecycle, product, XPS system and NVIDIA module/userspace check.
The lifecycle check passed 741 Python tests and 25 system-settings tests. The
installer passed its 33 Rust tests (21 unit, eight interaction and four
presentation). All 41 completed-image/source parity checks passed.

The shared installation check asserts the latest kernel across every default
hardware profile, working ZFS and preservation of a personal kernel override.

## Installation and staged-updater verification

Both plain and encrypted cases passed all 18 milestones and all 10 lifecycle
scenarios. The corrected run took 07:31–08:29 local time (06:31–07:29 UTC).
The test runner is from
`0de5de0c04ad42644051ce677f40b4619e2d9360`; its only change after the image
revision explicitly requests retry after a deliberate kernel rollback. The
image, installed source and runtime packages under test remain the frozen
beta.21 identities above.

Both graphical installations used the standard application selection. The
plain worker took 158 seconds (162.652 seconds observed by the harness); the
encrypted worker took 192 seconds (203.096 seconds observed).
Both passed exact ISO/installed-source identity, live ZFS runtime operations,
installed Linux 7.3.0, quiet boot and the installed boot menu, runtime
encryption policy, desktop configuration and health, first-login welcome,
keyboard shortcuts, desktop authorization, and password/keyring changes
across reboot/login round trips.

Both staged updaters passed automatic preparation and an independent upstream
build from Nixpkgs `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36` to
`08d3a97586f6b6343b3b5e799980773629432610`, left unapplied. The kernel test
then staged, booted and confirmed a task-owned 6.18.57 baseline, removed only
its temporary override, reviewed and applied the kernel update, booted and
confirmed 7.3.0, rolled back and booted 6.18.57, explicitly authorized retry,
and restored and confirmed 7.3.0. The remaining lifecycle scenarios passed
evaluation/build failure, interrupted-stage recovery, unconfirmed-trial
fallback, local apply/boot/confirmation, and rollback with unchanged personal
packages, service state, VPN secret, widget and preferences.

Live ZFS checks loaded the module and exercised pool creation, compressed
file I/O, snapshot/rollback, zvol block I/O, scrub, and export/import.

The first run booted and confirmed 6.18.57, updated and confirmed 7.3.0, then
rolled back and booted 6.18.57. Its final restoration attempt correctly hit the
updater's quarantine for the deliberately rolled-back system. The test had
omitted `cybex update retry-failed`; the updater was not bypassed or changed.
That run was stopped after collecting evidence and the corrected runner was
started with fresh guests.

The QEMU tests ran in supervised `agent-resource` lease
`9d8a732b8cef4aac99536a6388da4f1e`, with a CI host-capacity reservation of
26 GiB and eight CPUs. Each guest used four vCPUs and 12 GiB RAM.

Not exercised: physical hardware or GPU runtime, Secure Boot, a signed public
vendor channel, or a confirmed successful LAN PXE-to-desktop boot. The PXE
server observed a physical UEFI client selecting beta.21; no client-side boot
result has been reported. The VM tests use ordinary UEFI boot and the bundled
unreleased installation source, with its exact NAR identity checked.

## PXE delivery

At the user's request, beta.21 was delivered during VM qualification, after
completed-image/source parity and live 7.3.0/ZFS tests had passed. It was
copied to a task-specific staging directory outside the served tree, hashed
against the build, and atomically moved into `/data/pxe/iso`. Its served
checksum verified before beta.20 and its checksum were removed
(7,106,641,920 bytes plus 92 bytes). No other operating system's image changed.

`refresh_img_list` returned `result: success`. The image summary retained a
stale count, so the idle service was restarted through systemd. Startup
refreshed the list: `query_status` reported `running`, `get_img_tree` listed
only beta.21, `get_img_summary` reported `count: 1`, and `iventoy.service`
was `active`. A physical UEFI client began booting beta.21 before the repeat
manual refresh; no further refresh or restart was attempted during its boot.
That transfer record alone does not establish a successful physical OS boot.

## Cleanup and retained deliverables

Both qualification leases closed: the corrected run above and the initial
`c8e4acf0bd654ddfbcd760755855759b` run. `agent-resource check` reported no
remaining resources, preserved volumes or errors for either. Both CI
reservations ended, QEMU stopped, and the private VM workspaces were removed.

Removed the task's build links, the redundant Nix ISO output
`/nix/store/pya0fagjc0806x6c37awj9paf1p2aj4w-cybexos-1.0.0-beta.21-x86_64-linux.iso`
with targeted `nix store delete` (6,619.31 MiB freed), and the 15 MiB task
directory `/data/tmp/cybexos-kernel-beta21` containing logs, helper scripts and
JSON evidence. Useful results are recorded here. The earlier temporary ZFS
source workspaces were also removed. Normal Nix dependencies and check outputs
remain in the shared cache.

Final checks found no task-owned processes, mounts or VM workspaces. The PXE
service remained active, its status was `running`, and its tree and count
contained exactly beta.21.

Retained for the requested PXE testing: the 6,940,846,080-byte served ISO and
its 92-byte checksum at the paths above, plus this source/validation record.
