# Testing ISO beta.22: Wiz everywhere — 2026-10-30

Wiz, the assistant's character, now shows the system's state beyond the
assistant ([assistant](../assistant.md#wiz-elsewhere)): the installer's system
check, installation, done, stopped and failed screens; the welcome guide's
Hello (a new `greeting` pose and his only words), Connect (asleep until an
agent is signed in) and Ready (the system check), then a hop to his corner;
every Software Update status page and a What's New page once a new Cybex OS
version is kept; **Ask Wiz** when the launcher finds nothing; the empty
notification centre; still pictures at disk unlock, on the lock screen and in
kitty's `fastfetch`. The `assistantCharacter` setting and its still logo are
removed; Wiz is the only character.

## Exact source and image

- Version: `1.0.0-beta.22`.
- Image source revision: `e77c4aa315a677ef6b4dfc24f907938edcdeb37c`. The
  image was built from that tree before it was committed (a Git flake with
  `dirtyRev` `556cf0da…-dirty`), so the ISO and both installed systems report
  revision `uncommitted`; the commit's NAR hash is identical.
- Source NAR: `sha256-ewag4LHesdYU45R0mnQ2zzkbq/n63YgdjszcK8iUZrU=`.
- ISO SHA-256: `31a4af9c0acc74f13e65105d09ff1d85544991e091a47c7da766dc99b374e7c4`.
- ISO size: 6,940,846,080 bytes (6.464 GiB).
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.22.iso` with
  `cybexos-1.0.0-beta.22.iso.sha256` (92 bytes).

The `AGENTS.md` change that ignores PXE client connections and this record
were written after the image was built; neither is part of its source NAR.
`flake.lock` and `system.stateVersion` are unchanged.

## Build and source verification

- Builds from that source all passed: the ISO, `installer-ui` (its check phase
  runs the kiosk's Rust tests), and the checks `parity` (shared installation
  contract), `lifecycle`, `product`, `xps-system`, `nvidia-kernels` and
  `nvidia-evaluation`.
- `tests/run`: 743 lifecycle Python tests, 25 system-settings tests and the
  Node suite (1539 tests: 1522 passed, 17 skipped, none failed) passed.
  `tests/qml-lint`: 446 QML files and 4 harnesses without errors.
  `scripts/export-wiz --check` passed.
- Real shell under a private headless compositor, one engine at a time:
  `welcome-guide.py`, `update-flow.py`, `assistant-overlay.py`,
  `settings-pages.py` and `shortcut-editor.py` passed.
- New NixOS VM checks, run through `agent-resource`: `plymouth-unlock`
  (a LUKS volume unlocked in a systemd initrd through the theme: asleep,
  listening, sorry after a wrong passphrase, happy, then gone) and
  `lock-terminal` (themed and vendor hyprlock with Wiz beside the field;
  `fastfetch` in kitty drawing him) passed.
- `scripts/check-image-parity`: all 41 completed-image/source parity checks
  passed.

## Installation and staged-updater verification

`scripts/qualify-installations --case both --scenario lifecycle --interactive`
passed for plain and encrypted installations: all 18 milestones and all 10
lifecycle scenarios each, from 09:11 to 10:20 local time. That covers exact
ISO/installed-source identity, the installer's graphical flow, installed boot
and quiet boot, the boot menu, runtime encryption, desktop configuration and
health, the first-login welcome guide, keyboard shortcuts, desktop
authorization and shared password changes, then automatic preparation, an
upstream-only update with the vendor channel unavailable, a kernel update and
rollback, evaluation and build failures, interrupted staging, the unconfirmed
trial fallback, local apply/boot/confirmation, and rollback with personal
packages, services, VPN secret, widget and preferences preserved.

Its screenshots showed Wiz working above the installer's step list and
greeting on the guide's Hello on real Hyprland.

The run used supervised `agent-resource` lease
`9bf981a739bf48b1ad05b7b06b0d59bf` and a CI host-capacity reservation of
26 GiB and eight CPUs; each guest had four vCPUs and 12 GiB RAM.

Not exercised: physical hardware, displays or HiDPI panels, Secure Boot, and a
signed vendor channel. The guide's hand-off flight to the corner and the
launcher's Ask Wiz were verified only under headless Sway (qualification closes
the guide through IPC). What's New was verified with a fixture status, not
through a real kept vendor release.

## PXE delivery

At the user's request, beta.22 was delivered during qualification, after
image/source parity had passed. It was copied to a task staging directory on
the same filesystem, hashed against the build, and moved into `/data/pxe/iso`,
where its checksum verified. beta.21 and its checksum were then removed
(6,940,846,080 bytes plus 92 bytes); no other operating system's image changed.
An established LAN client connection to iVentoy was ignored, as the user
instructed (now in `AGENTS.md`).

`refresh_img_list` returned `result: success` and `get_img_tree` listed only
beta.22, but `get_img_summary` kept a stale count of 2. After
`sudo systemctl restart iventoy.service`, `query_status` reported `running`,
`get_img_tree` listed only beta.22, `get_img_summary` reported `count: 1`, and
`iventoy.service` was `active`.

## Cleanup and retained deliverables

All leases of this work, including the qualification and its reservation,
closed with no remaining resources, preserved volumes or errors. Build links,
task logs, screenshots and the redundant Nix ISO output were removed. Retained
for the requested PXE testing: the served ISO and its checksum.
