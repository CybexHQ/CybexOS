# Releases

A Cybex OS release is a published GitHub release of `CybexHQ/CybexOS` with a
semantic tag (`v1.2.3`, `v1.2.3-beta.1`) on a commit whose `VERSION` file holds
the same version. The GitHub repository is the trust root: there are no
publisher keys, signed manifests or channel documents, and installed machines
need no GitHub account or credential. A release is always installed by exact
commit and content (NAR) identity, never by following a moving branch.

## Channels

Each machine follows a release channel. **Stable** takes the newest published
release that is neither marked as a prerelease nor has a prerelease version;
**beta** takes the newest published release of either kind, so a beta machine
is never behind stable. Drafts and tags that are not semantic versions are
ignored. Only Cybex OS releases follow the channel: NixOS package updates are
selected independently and never consult releases.

A release reaches beta first. `release/publish` creates it as a GitHub
prerelease; `release/promote` later clears that flag on the same release, so
stable machines install exactly the tag, commit and content that beta machines
already ran. Nothing is rebuilt and the version does not change. A release
that is never promoted stays beta-only, and stable machines move straight to
the next promoted one (1.0.17 to 1.0.19, skipping 1.0.18). Versions stay plain
`MAJOR.MINOR.PATCH`; a `-beta.N` or `-rc.N` version is possible but can never
reach stable.

The machine's configuration declares its channel
(`cybexos.updates.channel`; the installer writes the medium's, stable for a
final ISO). An administrator can choose the other one at runtime with
`cybex update channel stable|beta` or **Get beta releases** in Settings →
Bar & Control Center → Updates; Software Update itself offers no channel
choice. The choice is kept in
`/var/lib/cybexos/update-channel.json`, so it needs no rebuild and survives a
generation rollback; choosing the declared channel again removes it.
`cybex update channel` without an argument and `cybex update status`
(`channel`) report `{selected, declared, override}`.

A machine is never moved back to an older version. After moving from beta to
stable, or when its release is withdrawn, it can run a newer version than its
channel's newest release. Discovery then reports the neutral state `ahead`
(`installed`, and the channel's newest as `available`): no error, no update
indicator, and Software Update's up-to-date page says that Cybex OS updates
resume with the channel's next release. NixOS package updates continue. A Cybex OS update
prepared on beta becomes stale when the machine moves to stable, and
installation checks the channel again; moving to beta keeps a prepared
update, since every stable release is on beta too.

## What an installed machine checks

`cybex update check` and `cybex update stage cybexos` read the release listing
and resolve the selected tag to its exact commit through the GitHub API: only
`api.github.com`, with bounded responses and an ETag cache (GitHub does not
count a conditional 304 against its anonymous rate limit). Staging then:

1. downloads that commit once with `nix flake prefetch` and records the
   content hash of what it received;
2. reads the release's own `VERSION` and `release/compatibility.json` from that
   download. The version must equal the tag; the schema, configuration and
   plugin APIs, minimum updater API, architecture and NixOS branch must suit
   this machine;
3. locks the machine flake to `github:CybexHQ/CybexOS/<commit>` and requires the
   lock's revision and NAR to equal what it checked.

All of this precedes evaluation of the selected code. A version older than the
installed one is refused (explicit generation rollback is separate), and so is
a published version whose commit or content changed after this machine
installed it. An endpoint failure means unknown availability, never current.
Interrupted downloads do not change the working lock.

The security boundary is the repository: whoever can push a `v*` tag and
publish a release reaches every machine on that channel. Require two-factor
authentication for maintainers, protect `v*` tags and the default branch, and
review what a release contains before publishing it.

Installation media install only their own bundled source
([installation](installation.md#release-identity)); a release published later
never changes what a tested ISO installs.

## Publishing

Development commits may be pushed directly to `main`. To publish a release:

1. Set `VERSION` to a new version (tags are never reused), write
   `release/notes.md`, commit and push to `main`.
2. Qualify that exact commit as far as the release needs (below).
3. Run `release/publish VERSION` from a clean `main` equal to `origin/main`.
   It checks the version against `VERSION`, `release/compatibility.json` and
   the notes, refuses an existing tag, creates and pushes the annotated
   `vVERSION` tag and creates the GitHub release with `gh` as a prerelease:
   it reaches beta machines only. Pass asset paths (an ISO and its checksum)
   to upload them with the release, or `--dry-run` to only report the result.
   `--stable` publishes straight to both channels and marks the release as
   the latest. Keep it for an urgent fix, or a release that needs no beta
   period; a prerelease version refuses it.
4. Once the release has proven itself on beta, run
   `release/promote VERSION`. It changes nothing about the release's source:
   it clears the prerelease flag, marks it as the latest and replaces its notes
   with stable notes. Before that it checks that every stable machine can
   install it:
   - it is a published, final version, still a prerelease, and newer than the
     current stable release;
   - it has been on beta for at least 24 hours (`--soak HOURS` changes the
     minimum; `--now` skips it for an urgent fix);
   - its `release/compatibility.json` suits the current stable release:
     `minUpdater` at most that release's updater API, the same schema,
     configuration and plugin APIs, all of its architectures and its NixOS
     branch.

   Stable machines skip the beta releases in between, so their What's New
   should cover those too. Promotion proposes combined notes, the release's
   own followed by a section per skipped beta release, and opens them in
   `$VISUAL`/`$EDITOR` when run in a terminal. `--notes FILE` supplies them
   instead. It asks for confirmation (`--yes` skips it) and `--dry-run` only
   prints the result. A refused promotion changes nothing.

Fix forward on `main`: there are no maintenance branches. When stable needs a
fix while beta carries changes that are not ready, revert those on `main` or
publish the fix as the next version and promote it at once. A fix built on an
older branch would give beta machines a newer version without beta's changes.

Raise `minUpdater` in `release/compatibility.json` only with an overlap release
that the previous updater can install, and promote that overlap release before
one that requires it: `release/promote` refuses a release the current stable
updater cannot install. Installed machines refuse a release that changes
`configurationApi` or `pluginApi`.

## Qualification

A workflow does not gate releases; their quality is the owner's decision. Run
**NixOS qualification** on demand from the Actions page. It does not run
automatically on pushes, pull requests or releases.

Full Nix/product/image jobs require a `cybexos-isolated` self-hosted runner;
standard hosted runners do not provide enough space for the complete desktop,
build dependencies, ISO copies and installation VMs. Provision a fresh,
single-job disposable x86_64 Linux VM with at least 256 GiB of disk, 32 GiB
RAM, four CPU cores and accessible nested KVM. The preflight requires 160 GiB
free for the Nix store plus 32 GiB for work (192 GiB when they share a
filesystem), at least 24 GiB available memory, and KVM for VM/image jobs.
Build concurrency is bounded to two builds and four cores per build.
Discard the runner, workspace and attached disks after each job. It must have
no workstation data, persistent credentials, production network access or
production PXE mount. Runner provisioning and isolation are owner-managed, not
an instruction to enroll the running workstation as a runner.

Nixpkgs supplies Quickshell, Qt, Hyprland, applications and fonts through the
machine's nixos-unstable Nixpkgs input and upstream binary cache, prebuilt.
Cybex OS supplies the desktop interface, assets, native notification-image
module and extensions. Narrow Intel camera/OMaWrite/font source pins are source
derivations, not another Nixpkgs universe; requalify their ABI/license
constraints when updating them. Before publishing, `scripts/check-prebuilt`,
`--nvidia` and `--catalogue` must report no build beyond the expected ones
([Prebuilt packages only](updates.md#prebuilt-packages-only)).
T3 Code is an exact hashed upstream nightly AppImage wrapped with Nixpkgs, the
client the connected widget was reviewed with; Nixpkgs' `t3code` is the 0.1.2
release. Replace that source recipe with the maintained Nixpkgs package after
product runtime qualification; its successful wrapper build is not desktop
validation.
Nixpkgs now also packages ChatGPT for x86_64 Linux; it is not adopted yet. The
Linux recipe pins OpenAI's versioned Debian pool object and SHA-256, reviewed against the signed
OpenAI repository metadata; it executes no distribution maintainer scripts or
repository enrollment. Preserve the Chromium sandbox and exact-executable
AppArmor user-namespace allowance when updating it. Replace the recipe with a
maintained native Nixpkgs Linux package after runtime qualification.

Brave Origin reuses the selected Nixpkgs Chromium wrapper/libraries and pins the
official Origin Debian asset. Nixpkgs now has a maintained `brave-origin`
package with different desktop and executable names; adopt it only together
with the browser defaults and `checks.x86_64-linux.browser-1password`. Review
both exact proprietary package pins on every vendor release.
They remain part of the explicit proprietary-application choice and require
installed runtime, security and redistribution qualification.

Origin keeps its own profile, `BraveSoftware/Brave-Origin`, where 1Password
installs its browser host only since 8.12.42, and only once it has run; Cybex OS
also installs that host in Chromium's system directory. Run
`checks.x86_64-linux.browser-1password` on every Origin or 1Password update: it
checks that Origin still finds the host, that 1Password still accepts the
Origin executable, and that the entry still matches 1Password's own.

The maintained NetworkManager Libreswan plugin uses Nixpkgs sources and a
scoped helper-path correction: the selected recipe points to `libexec/`, while
Libreswan 5 installs its daemon/controller helpers in `libexec/ipsec/`.
Build-time assertions check each replacement target. Cybex OS uses the native
NixOS `ipsec.service` to manage the backend; the plugin's legacy standalone
startup expects a removed `_stackmanager` helper. A working managed service is
therefore required and must pass installed health qualification.
Remove the override after the upstream recipe is
corrected and the installed VPN path qualifies; it does not suppress or patch
the archived vpnc plugin's vulnerabilities.
The reviewed desktop runtime series live in `desktop/runtime-compatibility.json`;
a candidate outside that matrix fails staging until qualified.

No durable Cybex OS binary cache is configured. Before advertising fast public
updates, provision a public Nix cache (for example an object-store-backed Nix
cache or Cachix), publish its independent Nix cache signing public key and
substituter URL, and prebuild each release/architecture. Add cache trust through
the shared module after reviewing that key. GitHub Actions artifacts and GitHub
Release download archives are not a public Nix binary cache. Source builds remain
possible. Redistribution/license review remains required for the actual payload.

Physical/security qualification should include mandatory access control and
firewall evidence. Record enforced profile/process coverage, negative access
probes and packet-level policy behavior. AppArmor being enabled alone cannot
satisfy the mandatory access control check.
