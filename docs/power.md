# Lid handling and external displays

The installed system's lid policy is defined in `nix/modules/power.nix` and
`desktop/power/lid_guard.py`. It uses DRM connector `status`, independently of
the compositor's outputs, DPMS and the connector's `enabled` state.

- A connected external display inhibits logind's `handle-lid-switch` action,
  including with the lid closed and the display turned off by hypridle.
- Losing the last external connection while the lid is already closed keeps
  that inhibitor for three seconds. Reconnecting cancels the deadline. Further
  disconnected events do not extend it, and the deadline samples DRM again.
- Three seconds matches `external-monitor-toggle` and covers subsecond
  DisplayPort retraining without a long delay after a real unplug.
- With the lid open and no external connection, no lid inhibitor is held.
  Closing an undocked laptop therefore still suspends immediately.

Logind's three lid actions default to `suspend`: ordinary, external power and
docked. The selective inhibitor supplies the display policy instead of
logind's enabled-output/dock-switch heuristic. Once it is released, logind
rechecks the closed lid and requests normal suspend. Hypridle's sleep delay
inhibitor and `before_sleep_cmd = cybexos-session-action lock` still secure the
session before sleep. Manual suspend and the 30-minute battery-only idle rule
are unaffected because the guard never inhibits `sleep` or `idle`.

The service starts before the login screen. It watches DRM udev events and
logind's lid property rather than polling ACPI. Systemd retains the inhibitor
file descriptor across service restarts so an update cannot expose a closed
lid to logind between processes. The replacement takes a fresh inhibitor
before releasing the inherited one; a disconnect during a restart gets a fresh
three-second grace. Stopping the unit releases the stored descriptor. The
service is required by updater health checks. The live installer keeps its
separate no-suspend policy; its offline installed-system payload uses the same
power module as an ordinary installation.

For diagnosis, inspect `journalctl -b -u cybexos-lid-guard -u systemd-logind`,
`systemd-inhibit --list`, and `/sys/class/drm/card*-*/status`. A connected output
must retain the lid inhibitor even when its `enabled` file reads `disabled`.

Regression checks are `tests/nixos/test_lid_guard.py`, the existing
`tests/quickshell/session-action.test.cjs`, `checks.x86_64-linux.parity` and
`checks.x86_64-linux.lid-guard`. The latter uses real logind, real DRM udev
events and a virtual input lid in a disposable NixOS VM. DRM connection files
and the final sleep operation are fixtures; physical DPMS, firmware
suspend/resume and the desktop lock screen still need hardware qualification.
The lifecycle VM also checks that the actual staged updater includes the
service and its required health declaration in the candidate system.

On 2026-11-02, the 18 lid regressions and 13 existing session-action tests
passed, as did `nix flake check --no-build`, the parity build and the lifecycle
source build (980 Python tests, its integration scripts and 25 system-settings
tests). The lid VM passed in 29 seconds, covering DPMS-disabled connection,
short dropout, sustained disconnect, immediate undocked lid close, manual
suspend, guard restart, logind restart and inhibitor teardown. The lifecycle
VM passed in 203 seconds, including real local updater staging, candidate
service/health checks and interrupted-worker recovery. This exercised staging,
not applying an update or an ISO installation. No workstation configuration
was changed and no physical laptop suspend/resume was performed.
