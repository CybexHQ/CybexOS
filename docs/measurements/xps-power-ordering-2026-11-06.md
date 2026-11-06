# XPS power-service ordering — 2026-11-06

The fix commit is `8a1023db0c53b5d74fb3f7536cbaecfd73296c07`, based on
Cybex OS 1.0.22. Intel LPMd now joins `graphical.target`, retaining its ordering
after power-profiles-daemon and UPower. Its former `multi-user.target` link
formed a cycle because PPD starts after that target.

## Checks exercised

- `checks.x86_64-linux.xps-power-ordering` passed using the packaged services,
  generated LPMd override and isolated target graph. The corrected graph has
  no cycle; restoring the old activation link reproduces the cycle. Systemd
  can return success after deleting a job, so the check also inspects its log.
- The same graph was verified in system scope during development: the fixed
  graph had no diagnostics, and the old graph logged the ordering cycle.
- `checks.x86_64-linux.parity` passed, including graphical activation for the
  XPS 14/16 and Panther Lake XPS 13 configurations.
- `nix flake check --no-build --no-write-lock-file --option eval-cache false`
  passed. The initial invocation hit a stale Nix evaluation-cache source;
  disabling that cache resolved it without source or lock changes.
- All three `scripts/check-prebuilt` modes (default, `--nvidia`, `--catalogue`)
  passed with no unexpected package compilation and eight pointer downloads
  checked per mode.

The components of `tests/run` passed across two environments. In the normal
host environment, the default-applications fixture saw host Nix-profile
entries despite its temporary XDG directories. Hiding those profiles in a
Bubblewrap namespace resolved it: all 1,097 primary Python tests completed
with two skipped, the other helper suites passed, and JavaScript reported
1,686 passed, 15 skipped and zero failures. The final Model Usage suite rejects
unmapped root ownership in that user namespace; rerunning
`nix develop -c python3 -B tests/model-usage.py` outside it passed its upstream
tests, settings contract and isolated offscreen QML fixtures. No single
`tests/run` invocation passed in both environments without that split.

No installed staged update, physical power measurement, suspend/resume,
shutdown or reboot was performed for this fix. No ISO was built. These source,
build and dependency-graph checks do not qualify those behaviors.

The temporary test namespaces and task artifacts, including crash dumps from
an early namespace missing the D-Bus machine ID, are disposable and cleaned
up before handoff. Personal declarations, machine inputs and live services
were not changed.
