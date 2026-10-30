# Cybex OS 1.0 ISO — 2026-10-30

## Source identity and scope

- Release metadata: `1.0.0`; requested media name: `cybexos-1.0.iso`.
- Frozen revision: `3fcd5e37443e7bc2bd6bccce1536b863866e33a5`.
- Source NAR: `sha256-hIxhAsdmUeefJ9p94yF9oLir4owG9X2rrdrBFwTTh6o=`.
- Source: `/nix/store/cymjrq4ggb4mgb9prq3bl0nv6la8fa7b-source`.
- Nixpkgs remains `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`.
- `system.stateVersion` remains `26.05`.

This record is written after source freeze and is not part of the image's NAR.
The image is a final-version bundled-source installation medium. Publisher
trust keys remain empty: no release was signed, published or promoted to a
public update channel. The installer verifies the bundled source's NAR against
the medium's committed identity and labels it as bundled; it does not claim a
publisher signature. Configured publisher authentication failures still block
installation and never fall back to the bundle.

## Changes

- Final media proceed with **Get started**, without beta/test-build consent.
  Disk review, erase confirmation, encryption and password protections remain.
- The pinned KMS/libinput backend now forwards wheel, finger and continuous
  scroll events. Lists enable mouse dragging; the scrollbar accepts thumb
  dragging and track clicks. Duplicate legacy axis events are ignored.
- Model Usage checks the Codex account before requesting subscription quotas,
  isolates the quota probe from an inherited OpenAI API key, explains API-key
  accounts, classifies missing/expired sign-in errors, and asks Codex to refresh
  a rejected managed sign-in once. Claude accepts its CLI OAuth-token environment
  sign-in, includes the CLI usage header, and rereads credentials after checking
  an expired sign-in with its own CLI. Neither collector sends model prompts or
  manages refresh tokens. Runtime changes are retained in the vendor integration
  patch. Real account access and successful real token renewal were not qualified.
- Brave is the proprietary installation's declared browser, including XHTML and
  additional browser schemes, with its default-browser policy enabled. Personal
  saved application choices are not rewritten by the installer.
- The default Stay awake primary-click duration is **Until off**. Saved durations
  remain personal preferences; idle inhibition itself still starts off.

## Source and package checks

- `nix develop -c tests/run` passed: 825 Python tests in the main suite;
  1,563 Node tests (1,546 passed, 17 skipped), plus ancillary suites.
- Model Usage native authentication regressions, vendor-patch round trip and
  shared QML worker-lifetime tests passed.
- The packaged KMS installer passed 48 Rust tests: 29 unit tests, 15 interaction
  tests and 4 presentation tests. The interaction suite exercises rendered log
  scrolling by wheel, content drag and scrollbar drag.
- The frozen source's Nix parity check passed.
- `scripts/check-prebuilt --catalogue` and `--nvidia` passed against the frozen
  source, preserving the prebuilt Nixpkgs policy. The host checkout contains an
  unrelated inaccessible ignored rootfs directory, so these checks ran from the
  frozen Nix-store source rather than recursively importing that checkout.

## Completed image verification

- Built from the frozen source above: `cybexos-1.0.iso`.
- Size: 7,457,329,152 bytes (6.945 GiB).
- SHA-256: `9096db8346ca8ef820886a5f9097c360adf7cc8f31a7008771aa2c179b382479`.
- All 42 `scripts/check-image-parity` checks passed against this image and the
  frozen source. These cover bundled source, installer binary/service, desktop,
  updater, package payload and hardware configuration identities.
- The payload's real Hyprland configuration verification passed.

## Installation and staged-updater verification

The frozen source's `scripts/qualify-installations --interactive
--applications standard --case both --scenario lifecycle` ran against the
same image SHA-256. Both guests use four vCPUs and 12 GiB RAM under supervised
`agent-resource` lease `8de6277ee6d646989601a02eae4253cb`, with a CI host-capacity
reservation of 16 GiB and four CPUs. No host installation or desktop is changed.

The installer scrolling test closes Customize apps and the frozen test driver
then assumes Enter will select Continue. Customize retains focus, so a
supplementary real QMP pointer click selects Continue. The checkout's driver
now selects Continue explicitly. This is a test-navigation correction after
source freeze; it changes no runtime code or ISO identity.

- **Plain passed** every milestone and all 10 lifecycle scenarios. The installer
  worker took 216 seconds (224.217 seconds observed), transferring 3,372 prebuilt
  store paths in 113.041 seconds.
- **Encrypted passed** every milestone and all 10 lifecycle scenarios. The
  installer worker took 186 seconds (203.733 seconds observed), transferring
  3,367 prebuilt store paths in 93.549 seconds.

Both guests' `cybexos-apps effective-defaults` and `xdg-settings`
reported `brave-browser.desktop`; the managed Brave policy was enabled. The
real KMS wheel, content drag and scrollbar drag each changed rendered list
pixels. No development-consent step appeared on the final medium.

Installed source checks require the same exact source NAR as the ISO. A
bundled path input has no Git revision metadata, so installed `release.json`
reports `revision: uncommitted` while the ISO records the frozen Git revision.
The qualifier records this distinction rather than asserting that the path
input has an independently authenticated Git revision.

Both lifecycles passed automatic preparation; independent upstream staging
with the unpublished vendor channel; an actual Linux 6.18.59 → 7.3.0 kernel
update and rollback; a personal baseline; evaluation and build failures;
interrupted staging recovery; unconfirmed-trial fallback; confirmed local
application; and explicit rollback with personal state preserved. Upstream
staging used the same Nixpkgs revision (no newly changed Nixpkgs packages were
applied). Password changes passed two real PAM/worker round trips and rebooted
with the login keyring unlocked after each change. The encrypted case also
rejected the old disk key after each password change and reached automatic
SDDM login after disk unlock, once per boot, without typing at the greeter.

Not exercised: physical hardware, a real PXE client boot, Secure Boot, a signed
public update channel, or live Codex/Claude account quotas and token renewal.

## PXE delivery

The image was copied outside the served ISO tree on the PXE filesystem, hashed
against both the image-parity and installation-qualified identity, then moved
to `/data/pxe/iso/cybexos-1.0.iso`. Its hash verified again before the older
image was removed. The initial unprivileged staging-directory creation was
rejected by the parent directory's permissions before any files changed;
the same guarded delivery completed with sudo.

Removed only `/data/pxe/iso/cybexos-1.0.0-beta.27.iso` (7,457,329,152 bytes)
and its 92-byte checksum. No other operating system's images were changed.

`refresh_img_list` returned `result: success`, and the tree listed the final
filename, but the summary retained a stale count of 2. After a systemd restart
of `iventoy.service`, another refresh returned success; `query_status` reported
`running`, `get_img_tree` listed only `cybexos-1.0.iso` (image 1),
`get_img_summary` reported `count: 1`, and the service was `active`.
No PXE client connections were inspected or used to delay these operations.

## Cleanup and retained deliverables

The supervised qualification lease closed; `agent-resource check` reported no
remaining resources, preserved volumes or errors. Its workspace and both VM
disks disappeared, the CI capacity holder exited, and final process/mount
checks found no task-owned workloads or mounts.

Removed the 4.4 MiB task directory
`/home/john/.local/share/cybexos/images/final10-7hh3s_7g`, including screenshots,
logs, evidence JSON, helper scripts, upstream scratch files and output links.
Removed the task-created qualifier bytecode file. The PXE staging directory
was removed by its delivery context manager; no `.final10-*` directories remain.
Final checks confirmed the staging and lease workspace are absent (zero
remaining disk usage).

After delivery, targeted `nix store delete` removed only the duplicate ISO
output `/nix/store/1vla59vdqmf69wnqrpxwin7r3mis0c6y-cybexos-1.0.iso`, freeing
7,111.86 MiB. Normal shared build dependencies and package/check outputs remain
in the Nix cache. No global pruning was requested.

Retained deliverables: `/data/pxe/iso/cybexos-1.0.iso` (7,457,329,152 bytes),
`/data/pxe/iso/cybexos-1.0.iso.sha256` (82 bytes), and this repository record.
The ISO and checksum have mode 0644, and `sha256sum -c` passed on the final
served file after cleanup. The ISO directory contains exactly this Cybex OS
image and its checksum.
