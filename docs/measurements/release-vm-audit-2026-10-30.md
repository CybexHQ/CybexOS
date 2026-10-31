# Pre-release VM audit — 2026-10-30–31

## Scope and source identity

The requested scope is VM testing. No physical machine, host desktop, signed-in
external account or public release channel was changed or qualified.

The final testing image is **1.0.0-beta.31**, frozen at Git revision
`c2e6a8f6fe4a6719d40549371e8a062226285c48` and source NAR
`sha256-09S2fvH7mwzOfF4IT2wbtqbG/C4zXIAqcPsxE95p/xQ=`. Its base Nixpkgs
revision is `31ecbaca1bdefa45dffc409f0250bd8039ea0010` (nixos-unstable).
All 42 image/source parity checks passed. Image SHA-256:
`19b3b4cb09614251459b50fa9c6b4df2923cb0d8e5e1ca38c2a44f91d3ff1bf6`;
size: 7,457,329,152 bytes (6.95 GiB). Both fresh plain and encrypted VM
installations passed all 21 installation/authentication milestones and all
12 lifecycle groups, including changed-upstream application and rollback.
The plain VM passed all 194 settings/widget checks on the installed baseline;
nine focused settings checks passed on the updated compositor. Real
Omarchy/MPRIS checks passed on both compositor versions.

The [machine-readable evidence](release-vm-audit-2026-10-30.json) retains the
final image parity hashes, per-case installation/lifecycle results, runtime
audit details, networking checks, PXE verification and resource cleanup.

The build used the exact Git flake revision. Documentation commits after this
freeze do not change the qualified image's source identity. The installed
bundled path input reports revision `uncommitted` because path flakes lack Git
metadata; the installed source NAR is checked against the ISO's exact NAR.

The audit began at checkout `7880cff6` against the previously served 1.0 ISO,
whose frozen source was `3fcd5e37443e7bc2bd6bccce1536b863866e33a5` and SHA-256
was `9096db8346ca8ef820886a5f9097c360adf7cc8f31a7008771aa2c179b382479`.
See [the original image record](iso-1.0-2026-10-30.md). Superseded candidates
below are diagnostic history, not successful final qualification.

## Issues found and fixed

1. **Rolling upstream updates failed with Hyprland 0.57.** The previously pinned
   titlebar plugin used removed headers and renderer APIs. The package now
   selects an exact upstream implementation for the machine compositor:
   0.2.2 for Hyprland 0.56, and 0.3.0 for 0.57. Both retain the native ELF
   build-ID guard and `clear_buttons` support. No Nixpkgs compatibility overlay
   or compositor source build was introduced. Beta.28 then correctly refused
   the new compositor at its runtime-series guard: the allowed series still
   listed only 0.56. Beta.29 includes 0.57 for the actual staged qualification;
   future unknown series remain refused.
2. **The prebuilt guard misread Nix derivation JSON v4.** It now normalizes the
   versioned derivation graph, basename store paths and nested input references,
   and refuses a graph missing a requested derivation. The updater and
   `scripts/check-prebuilt` share this parser. Two regression cases were added.
3. **Rapid idle timeout changes could stop automatic locking.** Repeated
   settings saves exhausted systemd's service-start burst limit. The managed
   hypridle service now permits these intentional restarts and waits two
   seconds before retrying an unexpected failure. A runtime case saves eight
   timeout changes and requires an active service with a new PID each time.
4. **Removing keyboard layouts emitted QML TypeErrors.** Retiring repeater
   delegates now have an empty-layout fallback. Layout switching, reordering,
   discard and restoration were exercised against the actual compositor.

5. **Removing the active keyboard layout disconnected the desktop shell.**
   This was reproduced in both installed VMs and under repeated changes. GDB
   caught `wl_closure_marshal` failing to duplicate a keyboard-map fd with
   `EBADF`: Hyprland's `setKeymap` forced Num Lock, emitted a modifier callback,
   and sent the new map before rebuilding its fd. The vendor input configuration
   no longer forces Num Lock during reloads (`numlock_by_default = false`).
   A controlled guest rerun passed 20 apply/switch/remove cycles with the same
   managed shell PID/invocation and a clean QML journal. The installed runtime
   audit now repeats eight cycles and checks shell identity each time. This
   uses the prebuilt compositor unchanged. Num Lock is no longer forced on.

6. **Upstream Hyprland 0.57 crashed in native configuration verification.**
   Both beta.30 updater builds rejected the candidate before activation. Even
   an almost-empty Lua configuration segfaulted. GDB identified
   `IPC::Socket2::CUnixImpl` registering a Wayland event source before verification
   mode had created an event loop. The checker now remounts its isolated
   filesystem root read-only: it needs no root writes or IPC socket. Socket
   creation is denied before the invalid event-loop call; the prebuilt binary's
   own configuration verifier still runs normally. The controlled guest test
   passed both minimal and complete vendor configuration, and rejected both
   invalid Lua and an unknown native option with exit status 1. No compositor
   rebuild, overlay, ignored exit code or skipped verification was introduced.

The audit also corrected test infrastructure: short Quickshell socket paths,
the Nix DBus/Sway environment, obsolete notification-image harness removal,
settings-gallery navigation, reused application windows, and QEMU's inherited
host configuration. The software UI test now runs unmodified production QML.
Qualifier teardown syncs an idle guest and captures real updater diagnostics.

## Source and isolated runtime checks

The final frozen source reruns are identified explicitly below. Supplemental
engine/build/VM checks passed during the audit before that freeze; those checks
support the investigation and do not replace the final installed-image runs.

- `tests/run` passed after the fixes and again on a writable copy of beta.31's
  frozen source (147.67 seconds): 827 primary Python tests; ancillary
  backend/ownership suites; 1,563 Node cases, with 1,546 passed and 17 skipped.
- `tests/qml-lint` passed 480 QML files and four harnesses, including the native
  notification-image CTest suite. The frozen beta.31 rerun passed in 13.09
  seconds. The copy retained source bytes and executable modes; its short,
  real temporary directory avoided harness assumptions about read-only files,
  Unix socket lengths and symlink resolution.
- Native lifecycle checks passed real private-store operation, authenticated
  local HTTPS delivery and signature rejection.
- Actual Quickshell engine suites passed display backend, plugin management,
  onboarding guide, settings navigation/search/drafts, assistant overlay,
  software application, update UI states, shortcut editing and Model Usage
  popup behavior. Remote account responses were fixtures.
- Nix checks built product/parity, XPS configuration and NVIDIA evaluation /
  kernels. These are build evidence, not physical hardware qualification.
- UEFI VM drivers passed boot selection/trial/fallback, firmware fixtures,
  Hyprland pointer, pointer routing, graphical encrypted unlock, lock/terminal,
  browser/1Password launch/native messaging, and lifecycle recovery. The
  corrected general lifecycle driver passed in 148.47 seconds. Browser and
  1Password account sign-in/autofill were not exercised.
- The corrected ISO's packaged installer passed 48 Rust tests: 29 unit,
  15 interaction and four presentation tests.

## Installed-system audit

The original ISO completed both actual interactive installations through disk
setup, first boot, onboarding and authentication. The encrypted case exercised
LUKS, encryption-gated automatic login once per boot, password fallback,
keyring unlock, and two password-change/reboot round trips. Both reached the
newly advanced upstream staging failure described above. That failure was
recorded as a failure and drove the corrected image.

The original installed desktop audit made 190 assertions across 22 settings
pages, 65 setting entries and options for 21 builtin widgets. Eight initial
failures were investigated: the idle-service and keyboard defects above were
fixed; the remaining failures were stale harness assumptions, then passed
focused reruns. The exercised behavior included:

- Keyboard/touchpad, workspaces, window layouts, native titlebars and default
  application roles.
- Display trial keep/revert/watchdog, multiple outputs, rotation and scale.
- NetworkManager checkpoints, manual IPv4/IPv6, virtual WiFi/hotspot and
  WireGuard activation; no external VPN gateway was used.
- PipeWire virtual microphone/output, default device, volume, mute and balance.
- Notifications, quiet times, stay-awake modes and Hyprsunset start/stop.
- Wallpaper selection/rotation, themes, bar presets/membership/backgrounds,
  widget options, plugin install/update/remove and control-center ordering.
- Persistence/reset/unknown-key preservation, administration windows and
  encrypted restic backup/keyring/snapshot/restore using guest-local data.

Omarchy ran through the real package CLI in installed Hyprland: unmodified
pinned Pomodoro, independent Spacer instances, Media service/native widget,
shared service injection, panel/overlay/menu payloads and replacement bar with
native-bar restoration. Installed package hashes stayed unchanged. A real
local mpv MPRIS player supplied the media title and passed pause/resume.
This qualifies those packages and six supported plugin kinds, not arbitrary
third-party plugins or external streaming services.

The ISO networking audit passed Ethernet unplug/replug, virtual WPA2 scanning,
wrong-password rejection and failed-profile cleanup, HTTPS over WiFi, access
point disappearance/automatic return and NetworkManager restart. It did not
partition a disk.

## Corrected-image qualification

Beta.28 (`8a18213ca8438be7327657c10e6dad57cb695143`, source NAR
`sha256-bPztB+a5QYFQpSyUk+aBdvfieK5AsnHgqiuuBWDI4x4=`, image SHA-256
`c79c25d937e16fcb25e885104fb107f79ec1f312e6225e5744a356c16e2e5978`)
passed all 42 parity checks and the complete ISO networking audit. Its plain
and encrypted VMs each passed all 21 installation/authentication/onboarding
milestones. Both then failed upstream staging at the runtime-series guard
above, with the working system retained. Neither is recorded as a successful
complete lifecycle qualification.

Beta.29 completed all fresh plain/encrypted installation and authentication
milestones, but both settings audits reproduced the keyboard disconnect above.
The plain VM passed the remaining settings/widget cases and the real Omarchy
CLI/MPRIS audit. The stricter identity guard also exposed the harness's own
intentional persistence-test restart; the harness now checks the old invocation
before that restart, then records the intentionally started one. Neither
beta.29 run is counted as complete lifecycle qualification. Both were stopped
before any upstream application, with packaged shell/service restored first.

Beta.30 passed all 21 fresh plain/encrypted installation/authentication milestones.
The plain VM passed all 194 settings/widget assertions across 22 pages and the
real Omarchy CLI/MPRIS audit. Both passed eight keyboard apply/switch/remove
cycles with a stable managed shell and eight rapid idle-service restarts.
The first encrypted run encountered public GitHub API quota exhaustion during
independent upstream discovery and safely stopped without changing the working
system. A fresh rerun proceeded after the quota reset without credentials.
Both cases then reproduced the native verification crash above during actual
upstream staging. Both retained their working generation, restored the packaged
shell, passed desktop health and were stopped and removed. Neither is counted
as complete lifecycle qualification.

Beta.31's encrypted case passed all 21 installation/authentication milestones
and all 12 lifecycle groups. This includes real 6.18.59 → 7.3.0 kernel changes,
confirmation, rollback and restoration; evaluation/build failure; interrupted
staging; unconfirmed-trial fallback; local apply/confirmation/rollback; and
preservation of personal packages, service state, VPN key/configuration,
preferences and widget code/data. It then applied Nixpkgs
`1c89083e451e891152365b799595cf7790a43325` while preserving the Cybex OS NAR.
Hyprland advanced from 0.56.2 to 0.57.0, Mesa from 26.2.5 to 26.2.6 and its
portal from 1.4.1 to 1.5.0. The updated desktop passed nine focused runtime
checks (including eight keyboard cycles) and rollback boot/desktop health.

Beta.31's plain case passed all 21 installation/authentication milestones
and all 12 lifecycle groups, including the same real kernel and changed-upstream
application/confirmation/rollback matrix as the encrypted case. It passed all
194 settings/widget runtime checks across 22 pages, 69 setting entries and
options for 21 builtin widgets. All three Omarchy checks passed, including
real local mpv MPRIS title/pause/resume and package hash preservation. After
applying the same Nixpkgs revision above, all nine focused settings checks and
all three Omarchy checks passed again on Hyprland 0.57.0, followed by rollback
boot and desktop health. Both guests restored the packaged managed shell and
passed its sole-process/current-invocation journal guards before teardown.

The plain case encountered the shared public GitHub API quota during upstream
discovery. It kept its working installation and waited for the advertised
01:00:21 CET reset, then completed without credentials or an API bypass. The
wait was an external test-environment delay, not a passed update or a hidden
failure; actual staging/application ran only after discovery recovered.

## Delivery and cleanup

The final beta.31 image was copied through a unique staging directory outside
the served tree. Its SHA-256 passed in staging and again at
`/data/pxe/iso/cybexos-1.0.0-beta.31.iso` before beta.30 and its checksum were
removed. Superseded beta.28–30 deliveries followed the same verified procedure;
other operating systems' images were left alone.

The beta.31 refresh returned `result: success`; a systemd restart cleared
iVentoy's stale removed-image count. Readiness-aware API polling confirmed
`running`, only beta.31, a count of one and an active `iventoy.service`.
A subsequent served-file `sha256sum -c` passed. Final documented curl API
status/tree/count checks passed without another restart after a Python urllib
management request timed out. No PXE client connections were inspected.

All **24 task-owned resource leases** are closed with no remaining resources,
preserved volumes or cleanup errors. All **22 CI capacity reservations** were
released. Verification found no task-owned process or mount, and every lease
workspace, VM disk, PXE staging directory and short source-test directory was
absent. The duplicate/superseded staging ISOs and their task-owned Nix ISO
outputs were removed by exact path; no global garbage collection was run.

The remaining task logs, screenshots, helper scripts and intermediate JSON in
`/data/tmp/cybexos-release-audit-20261030-E9cTK9` were removed after the useful
results were copied into this record and its JSON evidence. Shared Nix package
caches and pre-existing `~/.local/share/cybexos/images` data were retained.
Final artifact sizes and absence checks are recorded in the JSON evidence.

Retained deliverables are the ISO above (7,457,329,152 bytes / 6.95 GiB),
`/data/pxe/iso/cybexos-1.0.0-beta.31.iso.sha256` (92 bytes), this audit report,
and its linked machine-readable evidence. The ISO/checksum have mode 0644 and
remain available for testing through PXE. The two repository records retain
reviewable results without keeping disposable guest disks or screenshots.

## Evidence limits

This is VM evidence. Physical GPU/camera/peripherals, suspend and power,
Secure Boot, real LAN PXE boot, account sign-in/token renewal, remote VPNs,
cloud integrations and a public signed vendor update were not qualified.
Publisher trust keys remain empty. No release was signed or published, and
these results do not satisfy the physical/security/publication release gate
described in [validation](../validation.md) and [releasing](../releasing.md).
