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

## Stay awake and idle timers

The menubar's Stay awake control holds a systemd idle inhibitor through
`Common/SysInfo.qml`. Its Off state must release both an existing inhibitor
and a process start queued before Quickshell's post-reload hook. Process
synchronization follows the derived `idleInhibited` property's change signal;
the mode's earlier signal can still observe the previous derived value. A
request reenabled while the previous process is stopping resumes after exit.

On 2026-11-04, a real Quickshell regression reproduced an inhibitor surviving
an Off startup policy and an expired remembered request. External preference
changes could also leave the process running with Stay awake off. The fix
cancels queued starts and observes the updated enabled state. It preserves
timed requests across shell reloads and keeps the existing battery-only idle
suspend and external-display lid policies.

`python3 -B -m unittest discover -s tests/nixos -p test_idle_inhibit.py -v`
loads the production singleton in a private, windowless Quickshell. It checks
Off startup, remembered requests, expired timers, preference changes,
unplugging and rapid off/on requests. Settings, battery state, the inhibitor
command and service restarts are fixtures: no live desktop or real logind
inhibitor is changed. This tests QML/process behavior, not physical sleep.

Validation on 2026-11-04: the six real-engine idle regressions, 1,030 Python
source tests, the lifecycle integration scripts, 25 system-settings tests,
99 focused JavaScript tests and linting of 506 QML files passed. The desktop
package and ISO/source parity check built successfully. The actual staged
updater was exercised in disposable lifecycle VMs but did not reach Ready:
the offline fixture lacked bootstrap and ShellCheck outputs; carrying those
cached outputs allowed the prebuilt check to pass, then further missing
Nixpkgs build inputs failed to download (including libssh2 security patches).
The experimental fixture changes were discarded. No update was applied to
the workstation and no physical suspend/resume was tested.
