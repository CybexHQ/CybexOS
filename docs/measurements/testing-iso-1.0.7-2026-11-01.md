# Testing ISO 1.0.7: Wiz's conversation history — 2026-11-01

## Why

The first ISO with Wiz's conversation history (`7318e217`): every question
belongs to a conversation, a click on Wiz opens a new one unless the last one
still needs you, and History lists, searches, reopens, deletes and clears
conversations ([assistant](../assistant.md)). It also carries every change
since the last ISO built from this tree, 1.0.0, including those released as
1.0.3–1.0.6 without media: the XPS 13 and ZBook Ultra G1a profiles, the
system check's laptop check and the updater's restart-free installs.

## Exact source and image

- Version: `1.0.7` (`VERSION` only, `781d7ce6`).
- Image source revision: `781d7ce615876a857a5d1ac17e5cb5e76bfae887` on
  `main`, built from a clean tree with
  `nix build 'git+file:///home/john/Code/CybexOS?rev=781d7ce6…#packages.x86_64-linux.iso'`.
- Source NAR: `sha256-+gfVcz+yPGZseb6Kp85ZkjhNXkOQ2EHRnQdCRoA3Db4=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged since 1.0.0. `system.stateVersion` is unchanged.
- ISO: `cybexos-1.0.7-x86_64-linux.iso`, served as `cybexos-1.0.7.iso`.
- ISO SHA-256: `b936c0660fb322d83b6b2cb48232541349760f8ed993c0f622b20559814d9911`.
- ISO size: 7,457,329,152 bytes (6.945 GiB).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

On `781d7ce6`:

- `nix develop -c tests/run` passed: 899 Python tests in the main suite,
  1,559 Node tests and the remaining suites.
- `scripts/check-prebuilt` (default mode, from a `git archive` export of the
  revision) passed: only configuration and the expected local builds.
- `scripts/check-image-parity` passed all 43 checks against this ISO.

On the change tree (`7318e217`, same shell and service sources):

- `tests/assistant-overlay.py` passed with the real Quickshell and the real
  assistant service under headless Sway: History, opening and continuing a
  conversation (Claude Code resumed that conversation's own session), a real
  pointer click on Wiz starting a new conversation, delete, restore and
  clear, with no QML errors.
- `tests/qml-lint` passed.

## Installation and staged-updater verification

`scripts/qualify-installations --interactive --applications standard
--scenario lifecycle`, through the real tty1 installer screen. The two cases
ran in parallel, each in its own `agent-resource` lease with its VM disks in
the lease workspace (`7598bdb5…`, `091cf679…`); both leases closed with no
remaining resources or errors.

- **plain**, with `--display 1440x900 --disk virtio-without-serial`, passed
  all 22 milestones and all 10 lifecycle scenarios.
- **encrypted**, at the default 1280×800 on a virtio disk with a serial
  number, passed all 22 milestones and all 10 lifecycle scenarios.
- Both installed systems reported the ISO's release identity: 1.0.7,
  `781d7ce6`, the NAR above.
- The prebuilt store transfer copied 3,384 and 3,380 paths, in 172 s and
  160 s.
- Lifecycle scenarios: automatic preparation, an upstream update with an
  unavailable vendor download, a kernel update and rollback, the personal
  baseline, evaluation and build failures, interrupted-stage recovery, the
  unconfirmed-trial fallback, local apply with boot confirmation, and
  rollback with personal files kept.

## PXE delivery

The ISO was copied to a task staging directory on the same filesystem,
hashed against the build, and moved into `/data/pxe/iso` with its checksum,
where it verified. The previous image, the Fedora-based
`cybexos-1.0.2.iso`, and its checksum were removed (5,309,857,792 plus 84
bytes). Its `build.json`, `packages.txt` and `qualification.json` were left
in place.

`refresh_img_list` returned `result: success` and `get_img_tree` listed only
1.0.7, but `get_img_summary` kept a stale count of 4. iVentoy was restarted
with the AGENTS.md guard: `config.dat` (9,234 bytes) was copied aside first,
and the restart logged `Recover: ip:10.10.0.7 mask:255.255.254.0
gateway:10.10.0.1 pool:[10.10.0.200-10.10.0.219]`, so the copy was not needed
and was deleted. Afterwards `query_status` reported `running`, the list and
the summary showed only `cybexos-1.0.7.iso` (`count: 1`), and
`iventoy.service` was `active`.

## Not exercised

- Wiz's history on the installed desktop: qualification does not sign in an
  agent or open the assistant. It was checked in the real shell under
  headless Sway only, so Hyprland's focus grab (closing the box with a click
  elsewhere) was not exercised.
- Real hardware, a real iVentoy network boot of 1.0.7, Secure Boot.
