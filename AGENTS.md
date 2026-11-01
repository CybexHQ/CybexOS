# Repository agent instructions

## Git workflow

- Direct commits and pushes to `main` are supported. Do not require a pull
  request or passing GitHub Actions checks before pushing.
- The NixOS qualification workflow runs manually. Ordinary pushes, pull
  requests and releases do not start it.

## NixOS installation and lifecycle contract

- NixOS is the sole supported operating system. Target fresh installations.
  Do not add installation migration, compatibility shims, or alternate
  provisioning/update paths.
- `nix/modules` defines the shared installation contract for the ISO, installed
  system, configuration tools and lifecycle. `install` and `bootstrap` invoke
  the same fresh installer, available only in the live environment.
- Vendor files are immutable. Personal modules and machine-owned locks belong
  in `/etc/nixos`; secrets/state stay outside the Nix store. Never overwrite
  personal packages, services, VPNs, widgets, preferences, data or skills to make
  an update pass. Never implicitly refresh unrelated personal inputs.
- Nixpkgs always follows the **latest stable NixOS release** (`nixos-YY.MM`),
  not the rolling `nixos-unstable` branch. Move to each new release once it is
  out (May and November) as a qualified Cybex OS update. Take no packages from
  `nixos-unstable` or another branch: Quickshell, Hyprland, Qt and the rest stay
  at the release's versions. The kernel stays `linuxPackages_latest`, which the
  release itself keeps current. Until NixOS 26.11 ships (planned 2026-11-23)
  the tree still follows `nixos-unstable`; moving to 26.11 is the next branch
  change.
- Nixpkgs is selected independently of Cybex OS. Its packages come prebuilt
  from cache.nixos.org, guarded by the updater's prebuilt check
  (`lifecycle/cybexos/prebuilt.py`, `nix/modules/prebuilt.nix`). Only Cybex
  OS's own packages, unfree vendor downloads, kernel modules and machine
  configuration build locally; fix an uncached Nixpkgs build through
  configuration, never an overlay, and check releases with
  `scripts/check-prebuilt`. Cybex OS follows the machine Nixpkgs and is pinned
  to a published GitHub release's exact revision and NAR identity. Do not change
  `system.stateVersion` during routine updates.
- Preserve password fallback, encryption-gated automatic login after disk
  unlock (once per boot, keyring unlocked from the disk passphrase), firewall
  protections and supported hardware. Hardware stack
  failure blocks qualification; it must not silently remove support or disable
  Secure Boot.
- Validate changes through the actual staged updater. Source/fixture tests and
  a Nix build are not end-to-end installation, runtime or physical hardware
  qualification. Test ISO/source parity and use the exact same source identity
  for release artifacts and qualification. Record what was actually exercised.
- Do not modify the running workstation, partition existing systems, publish
  releases, or reboot the host without explicit authorization. Use isolated
  build/test environments and preserve unrelated work.

## ISO testing location

- Always place completed ISOs for testing in `/data/pxe/iso`.
- The PXE host is **thebeast (`10.10.0.7`)**, reached with
  `ssh john@10.10.0.7`. Its `/data/pxe/README.md` documents the service.
  A development machine's directory with the same path is not the served tree;
  copy the verified final ISO/checksum to the Beast before refreshing it.
- Build in a unique task-specific staging directory, then copy the completed
  ISO and its SHA-256 checksum into `/data/pxe/iso`.
- Serve only the latest Cybex OS ISO. Every new ISO goes to PXE and iVentoy is
  refreshed. Once its checksum verifies in `/data/pxe/iso`, remove every older
  `cybexos-*.iso` and its `.sha256` from that directory before the refresh.
  Leave other operating systems' images alone. If the copy or checksum fails,
  keep the existing images. Always ignore PXE client connections, such as
  an established connection to iVentoy's port 10809: they never block
  removing an older image, a refresh or a restart, so don't check for them or
  wait on them. Local staging copies follow the cleanup rules below.
- ISOs are production builds without a prerelease tag: `VERSION` is a final
  version (`1.0.0` from 2026-10-31, after `1.0.0-beta.34`). Each new ISO takes
  the next version. Before freezing its source, increment the patch number in
  `VERSION` (for example `1.0.0` to `1.0.1`) past the highest version in
  `VERSION` and `/data/pxe/iso`, so the boot menu, release metadata and file
  name agree. `VERSION` is the only file to change; test fixtures pin their
  own versions. Change the major or minor number only by a deliberate release
  decision. Serve the build's ISO as `cybexos-<VERSION>.iso` with
  `cybexos-<VERSION>.iso.sha256` naming that file, for example
  `cybexos-1.0.1.iso`, without date or task suffixes. Never reuse a served
  number; rebuilds before the copy keep it.
- After adding, replacing, or removing a testing ISO, refresh iVentoy's image
  list before handoff. Finish copying and verifying the checksum first; keep
  incomplete ISOs outside the served ISO tree. Use ASCII filenames without
  spaces and permissions that allow iVentoy to read the files.
- Prefer **ISO Management → Refresh** in the PXE host's iVentoy web UI
  (`http://10.10.0.7:26000`; deployment details are in the Beast's
  `/data/pxe/README.md`).
  On the PXE host, the equivalent requests below were verified with iVentoy
  1.0.41. They use the installed UI's internal API, so recheck
  `http://127.0.0.1:26000/vtoy_image.html` after an iVentoy upgrade:

  ```bash
  curl --fail-with-body --silent --show-error --max-time 30 \
    -H 'Content-Type: application/json' \
    -d '{"method":"refresh_img_list"}' http://127.0.0.1:26000/iventoy/json
  curl --fail-with-body --silent --show-error --max-time 10 \
    -H 'Content-Type: application/json' \
    -d '{"method":"query_status"}' http://127.0.0.1:26000/iventoy/json
  curl --fail-with-body --silent --show-error --max-time 10 \
    -H 'Content-Type: application/json' \
    -d '{"method":"get_img_tree"}' http://127.0.0.1:26000/iventoy/json
  ```

- Require `result: success` from refresh; HTTP success alone is insufficient.
  If busy, wait for the current operation before retrying. Poll `query_status`
  until refresh completes, require PXE status `running`, and verify the
  expected filename in `get_img_tree` (and absence of any removed filename).
  Also check `systemctl is-active iventoy.service`.
- Refresh normally keeps the service running. If it fails or leaves stale
  entries/counts, use `sudo systemctl restart iventoy.service`, then repeat
  the status/list checks.
  A restart can bring iVentoy up with defaults (DHCP server `0.0.0.0`): it
  cannot start PXE and loops. This happened on both restarts on 2026-10-31.
  Once `/opt/iventoy/data/config.dat` was missing at start; once the stopping
  process itself saved it without the network settings. Copy `config.dat`
  aside first, and afterwards require the log's `Recover: ip:10.10.0.7` line. If it
  is missing, stop the unit, put the copy (or the one in
  `/data/pxe/config-backups/initial-config.tar.gz`) back, and start it.
  Use systemd rather than launching a second `iventoy.sh` process. The unit's
  `-R start` restores PXE with its saved configuration; see
  [upstream startup documentation](https://www.iventoy.com/en/doc_start.html).
  Local deployment details are in `/data/pxe/README.md`.

## Build and test artifact cleanup

- Clean up disposable artifacts created during your task before final handoff,
  including failed/retried image builds, test ISOs, VM disks, extracted root
  filesystems, temporary logs, and screenshots. This includes outputs outside
  the checkout, especially `~/.local/share/cybexos/images/`.
- Use a unique task-specific output directory and track what you create.
  Arrange cleanup with traps or `finally` blocks where practical so failures
  and interruptions also clean up. Stop task-owned VMs/processes and unmount
  task-owned mounts before removing their files.
- Retain only requested deliverables and artifacts still needed for review or
  unresolved diagnostics. Remove intermediate and superseded attempts; record
  useful findings in repository documentation instead of retaining large
  images solely as evidence. Report any retained artifacts with their paths,
  sizes, and reason for keeping them in the final handoff.
- Delete only artifacts you created or have verified are disposable and within
  the user's authorized cleanup scope. Do not infer that another task's files
  are stale from their name or age alone. Never blanket-delete
  `~/.local/share/cybexos`: it can also contain active releases, runtime
  configuration, user themes/plugins, and persistent data.
- Verify cleanup at the end of the task by checking the output directories
  and their disk usage. Do not leave orphaned build/test processes or mounts.

## Live Quickshell testing

- Keep exactly one live Quickshell menubar. The normal live instance is the
  process owned by `quickshell.service`; never leave a source-tree `qs -d` or
  `qs -p` process running beside it.
- At the start and end of every live shell test, automatically compare
  `systemctl --user show quickshell.service -p MainPID --value` with every PID
  returned by `pgrep -x qs`. Inspect each extra PID's command line and cgroup,
  then terminate only confirmed unmanaged/developer instances. Never use a
  blanket `pkill qs`.
- Prefer deploying the configuration and testing through
  `quickshell.service`. If a direct source-tree `qs -d -p ...` session is
  necessary, stop `quickshell.service` first and arrange cleanup that always
  terminates the developer process and restores the service, including when
  the test fails or is interrupted.
- A live test is not complete until `quickshell.service` is active, its
  `MainPID` is the sole remaining `qs` PID, and the current invocation's
  journal has been checked for QML errors.
- Scope process comparisons to the authenticated user's UID; another user's
  independent desktop session is not an unmanaged menubar. Updater health
  reports extra developer processes without terminating them. The live-test
  guard may terminate only the confirmed task/developer instances above.
- Count Nixpkgs' Qt-wrapped Quickshell (`.quickshell-wrapped`, with Linux
  `comm` truncated to `.quickshell-wra`) in these comparisons as well as
  `pgrep -x qs`; the wrapper is the same upstream executable, not a second shell.
