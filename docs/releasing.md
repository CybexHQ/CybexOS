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
   prints the result. A refused promotion changes nothing. An installed
   machine that skipped published releases on its own channel combines their
   notes the same way when it updates
   ([combined updates](updates.md#combined-updates)), so a beta release's
   notes need cover only that release.

### Automatic vendor updates

Packages Nixpkgs maintains update with each machine's Nixpkgs. The vendor
downloads Cybex OS pins itself only move when this repository does, so
`scripts/vendor-pins` lists them and compares each with its upstream release.
The **vendor-updates** workflow (`.github/workflows/vendor-updates.yml`) runs it
daily on a GitHub-hosted runner:

- **Brave Origin, Codex and Claude Code** are updated automatically, each
  only once its download checks out against the vendor's own checksums:
  - Brave Origin follows Brave's stable releases
    (`nix/packages/brave/release.json`), accepted when GitHub's digest and
    Brave's published `.sha256` agree; its check is
    `checks.x86_64-linux.browser-1password`.
  - Codex follows OpenAI's stable releases (`rust-vX.Y.Z`, never the alphas
    in between; `nix/packages/codex/release.json`). The pin is the
    `codex-package` archive OpenAI's installer uses, accepted when GitHub's
    digest and OpenAI's `codex-package_SHA256SUMS` agree.
  - Claude Code follows Anthropic's `latest` channel
    (`nix/packages/claude-code/release.json`): the compressed native build
    its installer downloads, accepted when Anthropic's release key (fingerprint
    `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`, as Claude Code's setup
    documentation publishes it) has signed both release manifests. The
    package build checks the unpacked executable against the signed
    `manifest.json` as well.
  - Codex and Claude Code are the agent CLIs Wiz drives. Both are Cybex OS
    packages built from those prebuilt downloads, never compiled on the
    computer, so an update does not wait for NixOS's build farm. Their check,
    `checks.x86_64-linux.agent-clis`, runs both offline: their versions,
    Codex's bundled tools and its app-server answering Wiz's `initialize`,
    and every Claude Code option Wiz passes.

  One run updates every pin that is behind (`scripts/vendor-pins update
  NAME...`, all or none), builds the packages, runs `nix flake check
  --no-build`, `tests/run` and each updated pin's checks, then
  `release/automatic`: it commits each pin as `Update TITLE to VERSION`, takes
  the next patch version past `VERSION` and the tags, writes release notes
  with a paragraph per update, pushes `main` and runs `release/publish`. The
  release reaches beta only; promoting it stays a person's decision. A failed
  run releases none of them and keeps a `vendor-updates` issue open with the
  attempted updates.

  Before the package checks, `scripts/vendor-downloads` fetches the downloads
  nothing can substitute (unfree vendor files such as the Spotify snap in the
  1Password check's system): from the workflow's Actions cache when it holds
  them, else from the vendor, three times a few minutes apart when its host
  can't be reached (GitHub's runners lost api.snapcraft.io for days from
  2026-11-11). The daily Nixpkgs canary fetches the same set for the current
  pins, so whichever runner reaches a vendor host first fills the cache. A
  cached file enters the Nix store only through its pinned hash. The cache
  keeps one set, the newest.
- **T3 Code, Intel LPMd and Omawrite** are reported, not updated: each needs a
  review beyond its checksum (T3 Code's connected-widget bar API, for
  example). While one is behind upstream, a `vendor-pins-behind` issue lists it.
- The XPS IPU7 camera recipe is never compared or updated automatically.

Run it with **Run workflow** to publish available updates at once, with
`pins` naming only some automatic pins (for example `codex claude-code` while
another pin's update needs a person), or with `rehearse` to run every check
with the current pins without publishing.
`scripts/vendor-pins status` shows the same comparison locally.

### Nixpkgs canary

Machines follow `nixos-unstable` themselves, so a Nixpkgs change that breaks
Cybex OS reaches them without a Cybex OS release. The **nixpkgs-canary**
workflow (`scripts/nixpkgs-canary --build`) evaluates `main` and the newest
beta and stable releases daily against the channel head, Nixpkgs master
(which leads the channel by days) and the next stable branch once it exists.
It evaluates the `product`, `system`, `xps-system` and `nvidia-evaluation`
checks.

It then builds each source's expected local builds for the `product` system
(Cybex OS's own packages and the unfree vendor downloads machines compile
themselves) against the channel head, the only branch NixOS's cache covers.
Evaluation misses a build that only fails: on 2026-11-10 the channel's new
Rust build settings broke Cybex OS's Voxtype build on every machine that
took it. The source's own `scripts/check-prebuilt` names what its machines'
updater holds back until NixOS has built it. A build failure there is
reported as a wait; any other failure is one machines on that release would
hit, such as the codex ChatGPT needed that day, which updaters then still
let through.

An evaluation failure, a build failure machines would hit, or a new evaluation
warning (usually the notice before a removal) keeps a `nixpkgs-canary` issue
open with the error, the module that caused it or the failing build's log;
the issue closes once every source evaluates and builds again. Fix it on
`main` and release before the channel moves on. Machines that receive the
change first wait for that release
([updates](updates.md#when-nixpkgs-drops-something-cybex-os-uses)).

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
ChatGPT is Nixpkgs' maintained `chatgpt` package, so it updates with the
machine Nixpkgs rather than with a Cybex OS release. Cybex OS adds only the
exact-executable AppArmor user-namespace allowance for its Chromium sandbox
(`lib/chatgpt/ChatGPT`) and the package's cache cleanup rule; keep both if
Nixpkgs moves the executable.

Nixpkgs removed `brave` and `brave-origin` on 2026-11-03
([NixOS/nixpkgs#582838](https://github.com/NixOS/nixpkgs/pull/582838)):
browsers there need a committer among their maintainers. Cybex OS keeps the
last Nixpkgs recipe in `nix/packages/brave/make-brave.nix` and pins the
official Origin Debian asset in `nix/packages/brave/release.json`, built
against the machine Nixpkgs' libraries. Cybex OS is now the browser's only
maintainer: the vendor-updates workflow follows every Brave stable release
([automatic vendor updates](#automatic-vendor-updates)), and the Nixpkgs
canary shows when the recipe needs changing for a Nixpkgs rename.
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
