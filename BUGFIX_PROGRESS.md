# Bugfix investigation

## Scope and baseline

- Started 2026-11-01 on `thebeast`, source HEAD `ad748393`.
- Existing user work: untracked `docs/website-concept/`; leave untouched.
- Read `AGENTS.md`, contribution, ownership, installation, update, recovery and
  validation documentation. NixOS modules define the shared contract; Python
  lifecycle/installer workers own persistent state; Quickshell is their UI.
- Priorities: staged update/apply/recovery, installer worker lifecycle, personal
  configuration preservation, and desktop/backend contracts. Browser simulation
  is separate from the native product.
- `ci-platform run` does not support this repository. Use source/fixture checks
  with disposable local test data. No deployment, release, PXE changes, host
  configuration changes, or live desktop testing is authorized by this task.
- Temporary logs/data used `/tmp/cybexos-bugfix-9s6k_s6d`; removed after recording
  results below. No deployment, push, live service change or host reboot performed.

## Findings and fixes

### 1. Interrupted configuration copies could lose rollback backups (fixed)

- Trigger: rollback's personal backup fails partway through (for example I/O
  failure), then recovery retries. `restore()` accepted the existing partial
  directory and selected the previous configuration without backing up missing
  personal modules. Working selections also exposed unfinished copies.
- Reproduced before the fix with copy fault injection: an incomplete destination
  remained, and recovery finished with a personal module absent from its backup.
- `copy_config()` now prepares and syncs the complete tree in a temporary sibling
  directory, renames it into place, and syncs the parent. Failed copies are removed;
  executable bits and Git exclusions are preserved.
- Regression tests cover retry after interrupted copy and rollback preserving
  edits after an interrupted backup. Targeted lifecycle/request/maintenance tests:
  **115 passed**.
- The first broad run caught a missing-parent regression in atomic copying;
  restored `copytree()`'s parent-creation behavior and verified the affected
  prebuilt/software cases before the next full run.

### 2. Failed unmounts could recursively delete an installed filesystem (fixed)

- Trigger: an installation fails after mounting the target, and recursive unmount
  also fails. `TemporaryDirectory` cleanup still removed the target's files.
- Reproduced with disposable directory contents and command fixtures for plain
  and encrypted installations: both lost the target sentinel before the fix.
- Workspace cleanup now requires a successfully unmounted target and checks for
  a mount even when the mount command itself was interrupted. It retains a busy
  target and its encryption mapping, recording the path in the private log and
  stderr. Normal unmount/close/cleanup still runs. Installation docs updated.
- Regression tests cover unmount failure, ordinary cleanup, and an interrupted
  mount command after the mount took effect. No real disks or mounts were used.

### 3. Restarting the installer service enabled power during installation (fixed)

- The service deliberately leaves its installing worker alive on restart. Its
  replacement reports an error when that worker holds the exclusive lock, but
  power actions only checked the replacement's `installing` phase.
- Two regressions failed before the fix: a socket-driven shutdown during the
  busy-worker error, and shutdown during startup before the new worker reports.
- The daemon now probes the real installer lock at startup and before power
  actions when another worker may be running. Reboot, poweroff and firmware setup
  remain refused until that worker releases the lock. A ready owned worker clears
  this guard; ordinary idle/finished power actions still work.

### 4. Flathub mistook a failed systemd query for a dead worker (fixed)

- A bus/query error returned `False` from `unit_active()`, causing status to
  report a live install as failed and allowing its task record to be replaced.
- Return-code/state fixtures reproduced this, including a stopping worker being
  treated as already gone. Unknown queries now remain unknown, and stopping
  workers remain busy. Regression verifies a second request cannot overwrite it.

### 5. Flathub submission races replaced or misreported active tasks (fixed)

- `start()` released its task lock before `systemd-run` accepted the service.
  After the ten-second liveness grace period, another caller could replace the
  queued task because the first unit did not exist yet. A later startup failure
  could also write its error onto the replacement record.
- Reproduced with a delayed submission and a second request while the first was
  queued. Submission and its error publication now retain the request lock.
- Final review reproduced another edge: submission can time out after its worker
  starts or finishes. The error handler overwrote either state as failed and
  permitted replacement of a running task. Two additional tests failed before
  the fix, including an actual worker thread blocked inside its Flatpak command.
  Failure publication now also takes the worker lock and only fails an unclaimed
  queued task. Running and completed workers keep their own outcome.
- Targeted lifecycle, installer, daemon, Flathub, request and maintenance checks:
  **260 passed**; final Flathub regressions: **15 passed**.

## Reviewed areas and remaining questions

- Traced source discovery/trust, lock ownership, stage/review/apply, health,
  confirmation, rollback/recovery, automatic updates, and GC retention.
- Reviewed installer disk guards, source identity, credential handling, worker
  protocol, daemon/power/network transitions, and cleanup.
- Reviewed Flathub request/worker/state handling and Software integration;
  sampled desktop settings persistence, password coordination, firmware progress,
  and backup/restore boundaries. No confirmed additional finding in these samples.
- Mixed installed/missing batch removal was investigated with the pinned Flatpak
  **1.18.4**, a tiny local app repository and a private installation. The real
  `flathub.work()` removed the installed app even with the missing ID first;
  the suspicion was disproved and no change was made.
- Full native desktop, browser simulation, assistant, device drivers and physical
  hardware have not received an exhaustive audit. Existing qualification blockers
  remain documented in `docs/validation.md`.

## Validation

- Host-Python baseline: **899 tests passed, 25 skipped**, then `tests/run` stopped
  at missing `websockets` (environment dependency, not a repository failure).
- The existing offline Nix development shell supplies the required tools.
  Baseline `nix develop --offline --no-write-lock-file -c tests/run`: **passed**
  (147.8 seconds); all **899 Python tests passed**; Node reported **1,559 passed,
  17 skipped**. Additional helper,
  plugin, theme and Model Usage checks passed. Full log is temporary.
- Final full suite passed after all fixes:
  `NIX_CONFIG='extra-experimental-features = nix-command flakes' nix develop --offline --no-write-lock-file -c tests/run`.
  **911 Python discovery tests passed** (12 added regressions), additional Python
  groups of **25, 5 and 23**, **1,559 Node tests passed, 17 skipped**, plus plugin,
  theme and Model Usage checks. Added tests include pre-fix reproductions and
  checks that successful cleanup and existing behavior remain intact.
- Native integration passed with
  `NIX_CONFIG='extra-experimental-features = nix-command flakes' nix develop --offline --no-write-lock-file -c python3 -B tests/nixos-native`.
  Exercised real Nix locks/prefetch, isolated HTTPS release discovery/cache,
  source transfer, and retention/GC in private stores. The first attempt exposed
  missing nested-command experimental flags on this Debian host; enabling them
  only in the test environment resolved it without host changes.
- `nix --extra-experimental-features 'nix-command flakes' flake check --no-build --offline --no-write-lock-file`: **passed**.
- Final offline package rebuild passed:
  `nix --extra-experimental-features 'nix-command flakes' build .#updater .#installer-ui --no-link --offline --no-write-lock-file --max-jobs 2 --cores 2`.
  No checkout result links were created. `git diff --check` passed.
- The complete suite emits existing asynchronous/resource-warning diagnostics;
  these were also present in the baseline and did not fail the checks.
- Source/fixture tests do not constitute installed-system, staged-updater, boot,
  hardware or release qualification. Record the exact checks actually run.

## Completion and remaining scope

- Reviewed every implementation/test diff, including cleanup ordering, missing
  destination parents, lock ordering, and preserving worker outcomes on timeouts.
- Removed the temporary logs/data directory after recording results. Removed
  exactly four newly built package outputs (two build rounds, **3.97 MiB** freed)
  after verifying no roots or external referrers; shared dependencies were left
  alone. No ISOs, VM disks, containers, temporary services or mounts were created.
  No task-owned test/build process or mount remains. No retained task artifacts
  beyond the requested source changes, regression tests and this progress log.
- Nix's roots query automatically removed dangling auto-root links while finding
  roots; no shared-store garbage collection or dependency deletion was requested.
- Existing untracked `docs/website-concept/` remains untouched. Concurrent edits
  to `nix/modules/installer.nix` and `nix/tests/parity.nix` appeared at 22:57 after
  the final suite/build; left untouched and excluded from this task's validation
  claims. Changes are local and uncommitted. The user's no-deployment constraint
  leaves host services untouched; affected packages were rebuilt for validation.
- No confirmed unfixed finding remains. Installed-system staged-updater,
  ISO/source parity, boot and physical hardware qualification remain unperformed.
  Full desktop, browser simulation, assistant and driver audits are also outside
  the reviewed scope. A supported isolated NixOS qualification environment is
  the next step for installation/runtime confidence; `docs/validation.md` tracks
  the existing qualification blockers.
