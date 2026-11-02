# Cybex OS 1.0.9 release — 2026-11-02

Published [Cybex OS 1.0.9](https://github.com/CybexHQ/CybexOS/releases/tag/v1.0.9)
with `release/publish 1.0.9`, after its dry run and the checks below. GitHub
reports it as the latest release, neither a draft nor a prerelease, published
at `2026-11-02T07:37:59Z`.

## Source and scope

- Annotated tag: `v1.0.9`.
- Exact revision: `1a226496f405f2d27757f5793f08a08b10bf3004`.
- Public GitHub source NAR:
  `sha256-YLpA/r4i7lhShvE7P+9p0NdRuCSs5EdXUc3aqsa0c7E=`.
- `VERSION` and `release/notes.md` name 1.0.9. Nixpkgs, compatibility APIs
  and `system.stateVersion` were not changed.

This releases the [reliability fixes](../../BUGFIX_PROGRESS.md) for interrupted
configuration backups, installer cleanup and power guards, and Flathub task
state and submission races. It also includes the Ventoy startup correction.

The existing [1.0.8 testing ISO](testing-iso-1.0.8-2026-11-02.md) belongs to
an earlier source revision, before the reliability fixes. A new patch version
avoids reusing that installed identity for different content. This is a source
release with no uploaded ISO or checksum; the served 1.0.8 ISO was not replaced.

## Checks on the release commit

- Full `tests/run` in the Nix development shell: **911 Python discovery
  tests passed**, additional Python groups of **25, 5 and 23**, **1,559 Node
  tests passed with 17 skipped**, and the remaining Hermes, plugin, theme and
  Model Usage checks passed.
- `tests/nixos-native`: passed real Nix lock/prefetch, isolated HTTPS release
  discovery/cache, source transfer and retention/GC checks in private stores.
- `nix flake check --no-build --no-write-lock-file --option eval-cache false`:
  passed evaluation of modules, configurations, packages and checks.
- `scripts/check-prebuilt`, `--nvidia` and `--catalogue`, from a clean
  `git archive` of the release commit: all passed, with no unexpected package
  compilation and all **8 pointer-theme downloads** available in each mode.
- Fresh `updater` and `installer-ui` builds from
  `git+file:///home/john/Code/CybexOS?rev=1a226496f405f2d27757f5793f08a08b10bf3004`:
  passed with two jobs and two cores per build, without result links. The
  native installer build also passed **50 Rust tests**; its desktop dependency
  passed its executable/runtime dependency smoke check.
- Public GitHub source prefetch, `VERSION`, notes and updater compatibility
  validation: passed against the revision and NAR above.
- After publication, the production `Fetcher` and `discover()` queried GitHub
  anonymously from a disposable cache: **stable and beta both selected 1.0.9
  at the exact release revision**, with the committed notes. GitHub's latest
  release endpoint and tag resolution independently agreed.
- `release/publish 1.0.9 --dry-run` and `git diff --check`: passed.

Initial offline invocations lacked cached build inputs and could not prepare
the shell/builds; online runs using `cache.nixos.org` passed. The first flake
evaluation encountered an invalid cached source path; fresh evaluation passed.
The checkout's ignored build tree contains an unreadable cache directory, so
the prebuilt checks used the committed archive instead of changing those files.
No input lock or expected hash was changed to make a check pass.

These checks do not qualify actual installation, an installed staged update,
ISO/source parity, boot, physical hardware or security for this revision.
Earlier ISO/VM results retain their own source identity and scope.

## Cleanup

Removed the task's source export, temporary logs and discovery cache after
recording these results. Deleted exactly the four new 1.0.9 package outputs
(desktop, updater, installer screen and installer), after checking their
referrers, freeing **30.01 MiB**. Shared Nix dependencies were left alone.
No VM, container, mount, temporary service or ISO was created. No host service
was deployed, restarted or reconfigured. This record was written after
publication and is not part of the release source NAR.
