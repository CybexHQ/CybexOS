# Testing ISO beta.20: Wiz — 2026-10-30

Wiz replaces the Cybex X mascot as the assistant's character, and reacts
when he is dragged (docs/assistant.md, "The character").

![Wiz under Hyprland: idle, hovered, carried, startled, landed](testing-iso-beta20-wiz-hyprland-2026-10-30.png)

## Exact source and image

- Version: `1.0.0-beta.20`.
- Build revision: `9b76b1a89e53b7a0e6e8fe486c46fa2ce82e11f1` (`Set VERSION to
  1.0.0-beta.20`, on top of `17a8165b`, the Wiz commit).
- Source NAR: `sha256-p/pLcqUll6orgJDAw05GK9M2B4J84iO/TFoOQ6V6o3M=`.
- ISO SHA-256: `22abbd17dbbf8d61ebac4e10925f49f17be9a5bde8112409638522f0e3e78318`.
- ISO size: 7,106,641,920 bytes (6.619 GiB).
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.20.iso` with
  `cybexos-1.0.0-beta.20.iso.sha256` (92 bytes).

The image was built from the exact committed Git flake after increasing only
`VERSION` from beta.19. Both commits were pushed to `origin/main` first. This
record is a later documentation-only commit; its revision is not the image's
source identity.

## What changed

- **Wiz.** The assistant's character is a small figure in a charcoal cloak
  under a crooked hat with the red Cybex band (`assistantCharacter: wiz`, the
  default; `mark` keeps the still logo). He shows the turn: listening,
  thinking, working, needs input, finished, happy, sorry, asleep. He is 88 px
  (scaled) and stands free.
- **Cheap to keep on screen.** `Common/WizRig.js` holds his artwork, poses and
  timing; `scripts/export-wiz` renders it into still SVG layers
  (`assets/wiz/`), which `Assistant/Wiz.qml` draws once at their final size and
  moves with declarative animation and Animators. Idle holds still between
  blinks, glances and a rare wobble of the hat. Loops run only while a turn
  works or you talk. A waiting question pulses three times, then every 8 s.
- **Dragged, he panics.** A startled jump with "?!", sweat and his feet out;
  he swings from where he is held, his hat and feet trailing the pointer's
  motion, the hat shoved down when lifted and floating off when he drops,
  stretched along any drag so a diagonal reads as one. Quick back-and-forths
  make him dizzy. A drop lands with a thud and dust, his hat a beat later and
  crooked.

## Character measurements

Measured on development snapshots of this change in a headless Sway session
with Qt 6.11.2 on Mesa llvmpipe (this host has no GPU), with an 88 px character
in a 200×200 window, against the Canvas implementation in the supplied design
package. The main thread is what a GPU does not take away.

| Version, state | Frames/s | Main thread | Whole process |
| --- | --- | --- | --- |
| Supplied Canvas, idle | 60 | 2.9% | 5.2% |
| Supplied Canvas, working | 60 | 4.4% | 6.4% |
| Wiz, idle | 5–9 | ~0.1% | 0.2% |
| Wiz, listening (box open) | 2.3 | ~0.05% | 0.1% |
| Wiz, needs input | 15 | ~0.1% | 0.3% |
| Wiz, thinking or working | 60 | 0.1–0.16% | 2.6% |
| Wiz, asleep | 0 | 0 | 0 |

A scripted drag drew frames continuously while he was held and for about three
seconds after the drop (landing and a dizzy spell), then returned to blinks and
glances. A non-library JavaScript import in Qt 6.11 can run its top level
before `Math` exists, in a component's first instance inside a Repeater; the
rig therefore computes nothing at load time, and a test loads it without
`Math`.

## Build and static verification

The exact source passed:

- `nix build EXACT-SOURCE#iso`, with two build jobs and eight cores per job.
- The installer package's 33 Rust tests (21 unit, eight interaction, four
  presentation), and the desktop package's smoke checks.
- `checks.x86_64-linux.lifecycle`: 741 Python unit cases and 25
  system-settings cases.
- `checks.x86_64-linux.parity`, the shared installation contract.
- All 41 completed-image/source parity checks (`scripts/check-image-parity`).

The development snapshot passed `tests/run` (741 Python and 1,520 Node cases,
16 skipped for tools this host lacks) and `qml-lint` over 444 files and four
harnesses. `tests/assistant-overlay.py` drove the real Quickshell and assistant
service under headless Sway: Wiz listened while the box was open, was carried
in the middle of all four pointer drags and landed after each, celebrated a
finished turn and showed needs-input for an approval card, with no QML errors.
`checks.x86_64-linux.hyprland-pointer` passed all five drag scenarios and the
click checks under real Hyprland with no assistant QML errors. The committed
source then dropped one unused property; `qml-lint` and the Wiz tests were
repeated on it.

## Installation and staged-updater verification

`scripts/qualify-installations ISO --case both --scenario lifecycle
--interactive` ran from 23:25 to 00:19.

- **plain-install: passed.** Real tty1 Slint installation with the standard
  application selection; 202 seconds in the installer worker (203.919 seconds
  observed by the harness).
- **encrypted-install: passed.** Real tty1 Slint installation with the standard
  application selection; 201 seconds in the installer worker (203.421 seconds
  observed by the harness).

Both cases passed all 16 milestones: ISO and installed source identity, native
GUI assertions, installed boot and serial password login, automatic update
policy, quiet boot, the installed boot menu's seven checks, runtime
encryption, the desktop configuration check, the welcome first login, the
keyboard-shortcut runtime, authenticated desktop health, desktop authorization
and shared password changes (two round trips through the real packaged worker
and PAM, rebooting with a password desktop login and the login keyring
unlocked by the changed password).

Both cases passed all nine lifecycle scenarios: automatic preparation,
upstream staging with an unpublished vendor channel, a personal baseline,
evaluation failure, build failure, interrupted stage recovery, unconfirmed
trial fallback, local apply with boot confirmation, and rollback with
unchanged personal state. Upstream staging advanced Nixpkgs from
`da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36` to
`08d3a97586f6b6343b3b5e799980773629432610` in both guests, unapplied.

The QEMU tests ran in supervised `agent-resource` lease
`7f26339dbb904d2997d3d68f1c74b31f`, with a CI host-capacity reservation of
26 GiB and eight CPUs. Each guest used four vCPUs and 12 GiB RAM.

Not exercised: physical hardware, Secure Boot (systemd-boot), a signed public
channel, a PXE boot of this image, and Wiz inside the installed guests (the
character is hidden until shown from the menubar).

## PXE delivery

The completed image was copied outside the served tree, hashed against the
parity-verified build and moved into `/data/pxe/iso`, where its checksum
verified again. iVentoy's last client transfer was at 17:19 and a DHCP probe at
19:49 downloaded nothing, so beta.19 and its checksum were removed
(7,120,576,512 bytes). No other operating system's image was changed.

`refresh_img_list` returned `result: success` and `get_img_tree` listed exactly
beta.20, but `get_img_summary` still counted three images. With no client
active, `iventoy.service` was restarted through systemd; a second refresh
returned success, `query_status` reported `running`, `get_img_tree` listed
exactly beta.20, `get_img_summary` reported `count: 1`, and the service was
`active`.

## Cleanup and retained deliverables

The qualification lease closed and `agent-resource check` reported no remaining
resources, preserved volumes or errors; both VMs stopped and their workspace
was removed. The CI reservation ended with its holder. Every earlier lease of
this task (headless Sway measurements, the overlay test and the Hyprland VM
test) also closed. No task processes or mounts remained.

Removed the task-owned Nix ISO output
`/nix/store/x2g8kg6wzqs5ibvz2ffa85iad0yx3dk4-cybexos-1.0.0-beta.20-x86_64-linux.iso`
with targeted `nix store delete` (6,777.42 MiB freed), and the task directories
`/data/tmp/cxw20` (logs, parity and qualification evidence, screenshots, helper
scripts, build links) and the scratch measurements and storyboard under
`/tmp`. Normal Nix build dependencies and check outputs remain in the shared
build cache.

Retained: the served ISO and its 92-byte checksum, and this record with its
one capture.
