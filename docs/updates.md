# Independent updates

The machine owns `/etc/nixos/flake.nix` and `flake.lock`:

```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
inputs.cybexos.url = "github:CybexHQ/CybexOS/EXACT_RELEASE_REVISION";
inputs.cybexos.inputs.nixpkgs.follows = "nixpkgs";
```

Add personal inputs explicitly and make their Nixpkgs follow the same root.
The updater rejects duplicate Nixpkgs universes and unrelated lock changes.
Upstream binaries use `cache.nixos.org`; no extra cache key is implicitly trusted.

The installer and every installed hardware profile default to
`linuxPackages_latest` from that same nixos-unstable Nixpkgs input. Upstream staging
therefore advances the kernel with Nixpkgs, without a separate kernel input or
a hardware-specific series pin. Personal `boot.kernelPackages` declarations
remain machine-owned. The narrow Linux 7.3 ZFS backport in
`nix/kernel-packages.nix` keeps the installation medium's filesystem support
enabled until Nixpkgs supplies a compatible ZFS release; unsupported future
kernel/module combinations still fail their normal compatibility checks.
NVIDIA drivers come from that kernel package set's own Nixpkgs driver
packages: the open modules follow NVIDIA's `stable` driver branch (595 for
Linux 7.3), and the supported 580 closed branch remains independently selected.

Hyprland, hypridle and their libraries come from Nixpkgs unchanged; there is
no compatibility overlay. Other upstream inputs continue to advance independently.

`cybex update check` checks upstream and Cybex OS independently. An unreachable
source is unknown/unavailable, never reported current. Nixpkgs checks identify
available revisions; preview builds expose the actual package closure changes.
The menubar shows one icon only when a source has confirmed an available
update. There are no source counts, zero badges or success/error icons.

## Software Update

**Software Update** is the one place to review and install system updates. The
menubar icon, Control Center's **Review** button, the launcher's **Software
Update** application and **Open Software Update…** action, and
`cybexos-software-update` (`cybexos-runtime ipc updates open`) all open it.
Closing the window never interrupts an update; the supervised worker owns it.
The window belongs to the shell, and activation or restoration restarts
`quickshell.service` when NixOS restarts the changed user unit. An open app
records that in `$XDG_RUNTIME_DIR/cybexos-software-update-open`, keyed to the
compositor session, so the replacement shell reopens it on the installing page
and it shows the result. Closing the app clears the marker; a new login never
reopens it. The first update that installs this behavior is applied by a shell
that lacks it, so its window still closes once.
Control Center keeps pending deployments and failures reachable even when there
is no update indicator.

The app shows one page at a time: checking, up to date, updates available,
getting the update ready, ready to install, installing, restart to finish,
finishing after the restart, and a problem page. Worker state wins over
discovery, so a prepared or restarting update is shown even when a source
cannot be checked.

Every page lays its content in one centred column of at most 560 px; the
window keeps its size, and the ready page's action bar spans it. Times such as
**Last checked today at 07:03** follow the clock's 12/24-hour setting, as the
menubar does. Release notes are prose: at most 72 characters a line, at
`Theme.proseLineHeight`, in the interface font.

Wiz, the assistant's character, heads every status page in the pose language
he uses everywhere ([the assistant](assistant.md)); `UpdatesHelpers.statusPose`
maps the page to it. He thinks while checking and while finishing after the
restart, works while preparing, installing or restoring, and waits with his
amber pip when the next step is the person's: a restart or shutdown, a
confirmation that failed, an interrupted or outdated preparation. He listens
when the app asks whether everything works, is happy when the system is up to
date, is sorry after a failure, a rollback or an unreachable source, and
sleeps in the live session. An available update shows him idle with the
unread pip. He never speaks, and stays out of the review of what changes, the
menubar icon and notifications. The page's primary button carries its tone:
amber after a warning or failure, when the next step is the person's.

Preparation downloads and builds a candidate without activating it. The ready
page then lists what people recognise first:

- **Important changes**: Cybex OS, the NixOS build (shown by date within one
  release), the Linux kernel, Mesa or NVIDIA graphics drivers, device firmware
  files and Hyprland, from old version to new. Each installed system declares
  these exact versions in `/etc/cybexos/components.json`; nothing is inferred
  from store path names. A system built before the manifest lists no
  components, and the review still works.
- **Apps**: installed packages with a visible `.desktop` entry, by their own
  name and icon.
- Release notes of a new Cybex OS version. One update installs the
  channel's newest release, so it also brings every release this machine
  skipped; their notes come along (see [combined updates](#combined-updates)).
- A count of the remaining background components. Opening it shows programs
  without a window, the net size change, the exact `nix store diff-closures`
  output, the build log, update history, the source choice and **Discard
  Prepared Update**.

Same-version rebuilds are not shown as changes, and no store paths, hashes,
transaction IDs or tokens appear outside the technical details. The worker
publishes this grouping as `highlights` in `cybex update status`, and the
review token covers it with the package changes and closure diff. Nixpkgs does
not label security fixes, so the app does not claim them.

**Install update** asks for authorization and is offered only after the
candidate passes its checks. A new personal configuration edit invalidates the
preview and requires preparation again. Finished failures (failed, interrupted
or rolled back) can be dismissed; dismissal, like discarding a preview,
preserves files and logs. Recovery that still needs attention cannot be
dismissed.

### What's new after an update

When a confirmed update, kept by the person or by automatic confirmation,
moved Cybex OS to a new version, the up-to-date page reads **You're on Cybex OS
VERSION**. Wiz nods and sparkles once as the page comes into view and settles
into happy, and **What's new** opens a page in the same window with that
release's notes and its important changes (component versions, old to new).
**Back** or Escape returns. Notes render as Markdown without images or raw
HTML, so the page fetches nothing; only web links open, in the browser.

The data is the worker's completed record: after confirmation, `cybex update
status` still carries the reviewed transaction's `scope`, `installedVersion`,
`availableVersion`, `notes` and `highlights` until the next preparation
replaces them, so no other state is kept. Only a `cybexos` or `both` scope
counts, because those set both versions afresh. An update of NixOS packages
alone keeps the installed Cybex OS version and shows the ordinary up-to-date
page.

Each kept release is announced once per person. With Software Update closed,
one notification, **Cybex OS VERSION is ready** (*See what's new.*), takes the
place of **Update complete**, and its action opens What's New. With the app
open, the page itself is the announcement. The announced version is
remembered in `$XDG_STATE_HOME/cybexos/software-update.json`, so neither a
shell restart nor a new login repeats it.

## Automatic preparation and confirmation

Two machine policies live in `/var/lib/cybexos/update-automatic.json`. Both
default to on. An unreadable file turns both off.

```sh
cybex update automatic prepare on|off   # download and prepare in the background
cybex update automatic confirm on|off   # keep a trial boot that passes its checks
cybex update channel stable|beta        # which Cybex OS releases to follow
```

Changing either asks for administrator authorization. Software Update's up to
date page and **Settings → Bar & Control Center → Updates** offer the same switches;
`cybex update status` reports both as `automatic`.

**Background preparation** is `cybexos-update-auto.service`, started by its
timer (15 minutes after boot, then every 6 hours, randomized) and by the
desktop when a check finds a new update. The desktop waits ten minutes after
sign-in unless the person checks explicitly. The unit runs only on AC power
(`ConditionACPower`) and skips metered or likely metered NetworkManager
connections. It submits an ordinary supervised `stage` request only when the
updater is idle or done and an update is available. It prepares each target
(personal configuration digest plus available source identities) once:
discarded or installed targets are not prepared again, and a failure of its own
is retried for a new target or after a day. A prepared update that a newer
set would supersede is prepared again ([combined updates](#combined-updates)).
Other ready, stale, restarting, recovering and failed changes belong to the
person, so it leaves them alone. Installing a prepared update still requires
authorization.

### Combined updates

Updates arrive together, not one restart each. Discovery offers only the
channel's newest Cybex OS release, and one preparation combines it with the
newest NixOS packages and available device firmware. A machine on 1.0.18
with 1.0.19, 1.0.20 and 1.0.21 published installs 1.0.21 once.

Its notes cover every release it includes. `cybex update check` and the
prepared update carry `releases`, newest first, and `notes`, which are then
the newest release's own notes, a line naming the releases it also includes,
and each skipped release's notes under **From Cybex OS VERSION**, the shape
`release/promote` gives stable notes. The oldest sections are left out when
the whole would exceed 100,000 characters. A single release keeps its notes
unchanged.

A prepared update waiting for review is prepared again when something newer
would replace it: at once for a newer Cybex OS release, and for newer NixOS
packages alone only once it is three days old, since nixos-unstable moves
every day or two and a review rebuilt for each snapshot would never settle.
A preview background preparation made takes in every available source. One
the person prepared keeps its sources: an update of NixOS packages alone is
not given a release they left out. Personal Software, configuration and
cleanup previews, and firmware-only updates, are never prepared again.

The prepared update stays installable until the new one has built and passed
its checks; only then does it replace it. While the new one prepares, Software
Update shows its progress (one request runs at a time). When it does not
finish, the status returns to the prepared update with a `replacement` record
(`scope`, `version`, `state` `failed` or `waiting`, `error`, `notPrebuilt`,
`requestId`), the request still fails with its error, and the review's
**Cybex OS VERSION is available** card says why and that the update below can
be installed now. Background preparation tries the same newer set again after
a day, or straight away when the set changes. A worker killed mid-way is
reported as interrupted, as any preparation is; prepare again.

**Automatic confirmation** is `cybexos-update-confirm.service`. Twenty seconds
after the signed-in shell sees a trial boot awaiting login, it starts the unit,
which submits the same `confirm` request as **Confirm this boot** did. Health
checks still decide: the system services, Hyprland, exactly one managed
Quickshell and its journal must pass. If confirmation fails, or the policy is
off, the app asks the person to keep the version or go back to the previous
one. Restarting without keeping it returns to the previous generation, as
before. A notification reports a completed update; a new Cybex OS release is
announced with its What's New instead.

Both units take no input. They read the policy and the updater's own state as
root. A polkit rule lets an active local session of a `wheel` member start
exactly these two units without a password; every other unit start, and every
install, rollback or policy change, still requires authorization.

A missing/untrusted Cybex OS channel does not prevent selecting a confirmed
NixOS package update. Unavailable sources are explained and excluded from the
selected scope. Flathub apps update separately, right away, from Software's
Updates tab ([Flathub](software-and-defaults.md#flathub)); the system review
covers the NixOS generation and Cybex OS source.

Before the first Cybex OS release is published on a machine's channel, an empty
release listing is neutral: the unpublished source is hidden and contributes no
error. Confirmed NixOS package updates remain selected and can be prepared and
installed independently. An unavailable release repository, an invalid listing,
a tag that does not name an exact commit, a downgrade and a release whose own
`VERSION` or compatibility declaration does not fit remain errors
([releases](releasing.md)).

An upstream discovery failure keeps `upstream.state` at `unreachable` and
explains that the Nixpkgs package-source status is unknown. A confirmed GitHub
API rate-limit response or HTTP 429 suggests retrying later; HTTP 403 without
rate-limit evidence is reported as access denied. Recognized server, DNS, TLS,
connection and timeout errors have separate guidance. Other Nix failures leave
the cause unknown and suggest checking network access and Nix configuration.
Malformed metadata also leaves the status unknown. Cybex OS discovery still runs
after an upstream failure, so each source keeps its own result.

Discovery creates no deployment or transaction log. Its public error includes
this read-only diagnostic command, which can be run locally without elevation:

```sh
nix flake metadata --refresh --json github:NixOS/nixpkgs/nixos-unstable
```

Checks classify command diagnostics internally and publish only static guidance;
they do not log the raw discovery output. The command above may show private
URLs or configuration details: inspect its output locally and redact secrets
before sharing it. Checks do not retry automatically or require an account or
authentication token.

Device firmware is included in the regular **Software Update** flow. Checks
refresh fwupd's signed metadata; a firmware-only update uses the same
**Prepare update → Install update** actions when the OS sources are current.
The ready page lists each device and its old/new firmware versions. Preparation
never flashes hardware. The reviewed device releases are bound to the review
token, and installation rejects changed versions instead of silently adding
new releases. A failed firmware check remains unknown, rather than up to date;
it does not block a separately available OS update.

The supervised worker installs firmware after successful OS activation, or on
its own when only firmware is available. Closing the app or restarting the
shell leaves the worker running. Software Update displays device progress,
unplug/replug instructions, failures and the need for a restart or full
shutdown. Keep external power connected. Firmware changes are outside the Nix
transaction and are not reverted by a generation rollback. A device failure
does not roll back a successfully activated OS. Reboots and shutdowns remain
explicit. The optional terminal CLI is `cybexos-firmware-update interactive`;
the desktop has no separate firmware button or terminal launch.

`cybex update stage upstream|cybexos|both|local` pins and checks a selected
release before evaluation, snapshots the entire personal configuration and
updates only the chosen inputs. Cybex OS-only updates include its source-declared
vendor dependency graph while preserving root upstream/personal inputs. They
never select code from a moving branch. After a failed combined preview, select
only the available NixOS package source
to retain installed Cybex OS; that combination must build and pass candidate
checks too. The equivalent CLI action is `cybex update stage upstream`.

Every stage/apply/discard/rollback/confirm request returns `accepted`, a
`requestId` and its `cybexos-update@ID.service` unit. Acceptance means the request
was queued. `cybex update request ID` returns its durable queued/running/done/
failed result. `cybex update status` includes that result separately from the
current deployment, so preflight errors cannot disappear on the next poll or
shell reload. The reader detects a dead preparation worker as interrupted;
interrupted activation/recovery requires restoration. An unknown worker status
blocks duplicate requests until it can be checked. Authentication cancellation
and helper startup/timeout errors are visible in the review.

`cybex update status` returns the structured `packageChanges`, `highlights`,
full built diff, transaction, review token and `automatic` policy.
`cybex update discard ID` clears an unapplied ready or stale preview, or
dismisses a finished failure; it cannot discard a pending generation or
recovery that needs attention.
`cybex update apply ID TOKEN` runs under a supervised systemd worker and rejects
stale review tokens or intervening personal edits. No widget/module is removed
to make evaluation or runtime checks pass. Actual build progress is phase-based;
private transaction logs hold build diagnostics. After a deliberate reboot and
authenticated desktop login, `cybex update confirm` validates system services,
Hyprland, exactly one managed Quickshell and its current journal.
The app distinguishes **Restart to finish** (before the trial boot) from
finishing after signing in. It never requests a second restart for
confirmation. **Go back to the previous version** and **Try restoring
again** remain explicit when confirmation fails or recovery needs attention.
The question after the restart names both versions beside its buttons (**This
version** and **Previous version**: the Cybex OS release, else the NixOS build,
else the kernel, from `UpdatesHelpers.trialVersions`) and asks you to try what
you use every day before keeping it. Buttons and labels are in sentence case.

A failed deployment is quarantined by complete system identity. Inspect the
cause before using `cybex update retry-failed ID` to explicitly allow another
preview of it. Retry permission covers prior failures of that exact system and
is consumed only after a successful preview. Recovery is separate from
normal updates; a channel
cannot use a lower semantic version as a normal update.

nixos-unstable is a rolling branch: advancing it is routine, including when
its NixOS version moves on (26.11, then later). Release metadata and
`/etc/cybexos/release.json` name the branch (`"nixos": ["unstable"]`), not a
version. Never change `system.stateVersion` as part of a routine update.

## Prebuilt packages only

Every Nixpkgs package comes prebuilt from the configured cache
(`cache.nixos.org`). Before it builds a candidate, preparation of a NixOS
package update, a Cybex OS update or a Software change dry-runs the complete
system against this computer's store and caches
(`lifecycle/cybexos/prebuilt.py`). If anything beyond the expected builds below
would compile, it stops before building: the status is `failed`, its phase
"Waiting for NixOS to finish building this change", `notPrebuilt` names the
packages, and nothing changes. Software Update presents this result as
**Waiting for NixOS packages**, lists the packages and keeps **Check Again**
available. It retains that explanation after a restart, and does not show a
new-update indicator for the exact candidate already held back. A different
Nixpkgs revision, Cybex OS release or available firmware still gets an indicator.
Unknown candidate identities never suppress an indicator.

NixOS builds nixos-unstable continuously, so a later revision normally passes.
With automatic preparation enabled, background preparation retries a package
hold for a changed source or personal configuration, or after a day, including
holds first encountered manually. Other manual failures and personal Software
changes still need the person's attention. Personal configuration previews
(`local`) are not checked.

### When Nixpkgs drops something Cybex OS uses

Nixpkgs sometimes removes or renames a package or option (Brave, on
2026-11-03). The candidate system then stops evaluating, and an update with a
new Nixpkgs revision cannot be prepared until Cybex OS no longer depends on it.
When evaluation of such an update fails, preparation evaluates the same
candidate again with the installed Nixpkgs (`lifecycle/cybexos/
compatibility.py`). If that succeeds, the new Nixpkgs is the cause, and Nix's
error names the module that used what is gone:

- **A Cybex OS module.** The status keeps `incompatible` (origin `cybexos`,
  the file and Nixpkgs' message) and the phase "Waiting for a Cybex OS release
  that supports the new Nixpkgs". Software Update shows **Waiting for a Cybex
  OS update** with that message. This is a hold like the package wait above:
  background preparation retries it after a day, or at once when a new Cybex
  OS release or Nixpkgs revision appears, and an already prepared update stays
  installable.
- **A personal module** (in `/etc/nixos` or a personal input). The error names
  the file but not its message, which stays in the private log; status files
  are readable by every user. The person updates that file.
- **No module named.** Treated as a hold, like a Cybex OS module.

When the installed Nixpkgs fails as well, the failure is an ordinary one. The
nixpkgs-canary workflow catches these changes before machines receive them
([releasing](releasing.md#nixpkgs-canary)).

Two kinds of change become the default generation once activation and its
health checks pass, without a trial boot or restart:

- a Software change that only alters the installed packages, with personal
  configuration unchanged apart from `local/software.json`;
- an update (Cybex OS, NixOS or both, without device firmware) that changes
  nothing starting the computer and logging in use.

Both also require an unchanged boot path, compared by content between the two
generations: the kernel, early-boot image (initrd) and boot options, and the
login screen. The login screen check covers SDDM's unit and configuration, the
PAM files for password login, the greeter and the encryption-gated automatic
login, and the `cybexos-session` script it starts (not that script's
desktop-environment wrapper, which names each release's packages). Activation
does not restart the login screen, so only a boot shows that a changed one still
works. Every other change keeps the trial boot.

### Desktop services during activation

Adding or removing apps never restarts the desktop. The shell
(`quickshell.service`) and the assistant (`cybexos-assistant.service`) find
the machine's packages through `/run/current-system/sw/bin`, which activation
moves, rather than through the `system-path` store path, which names every
installed app. Their unit files, the only thing switch-to-configuration
compares, therefore stay the same, and a new app is on their `PATH` at once.

A change to either service itself still reaches it:

- The shell restarts during activation; the screen goes blank for a moment.
  Apps the shell started (the launcher, the dock and app shortcuts all start
  them through Quickshell) run inside `quickshell.service` and close with it.
- Activation never restarts the assistant (`X-RestartIfChanged=false`), so an
  update it applies for the person cannot end the answer that reports it.
  Once its unit has changed, the service restarts itself into the new one
  after nothing has run for two minutes: no question running or waiting, no
  waiting routine, nothing being spoken. It exits with status 75, which the
  unit maps to a restart (`RestartForceExitStatus`). With conversations kept
  only for the session (`assistantHistory: "session"`) it waits for the next
  login instead, so the restart never discards them. The last answer is kept
  across the restart. "Always in this conversation" answers are not, so the
  next tool use asks again.

Preparing a change compares both units between the running and the built
system. `cybex update status` reports the result before anything is applied:
`sessionRestarts` lists `{id, unit, when}` (`when` is `apply` or `idle`), and
`desktopRestart` is the sentence to show the person, empty when nothing
restarts. Both are part of the review token. To keep releases that leave
these alone restart-free, the boot splash and the automatic-login encryption
check are packages named without the release version, and the session file
starts `/run/current-system/sw/bin/cybexos-session`;
`checks.x86_64-linux.parity` asserts that a new release version with changed
desktop and updater packages leaves the whole boot path identical.

Cybex OS's modules
use NixOS's cached default builds: Hyprland and its portal as Nixpkgs builds
them, Xwayland without a font path, and every glibc locale. What builds on the
computer by design:

- Cybex OS's own packages and hardware stacks, and its NetworkManager
  Libreswan path fix;
- unfree vendor downloads, which NixOS never caches: Brave Origin,
  1Password, Spotify, ChatGPT, Claude Code, Steam and NVIDIA's userspace,
  with NVIDIA's 32-bit EGL platform libraries for Steam;
- out-of-tree kernel modules (NVIDIA, the XPS camera, the medium's ZFS);
- the machine's own configuration: initrd, PAM, setuid wrappers, dconf.

A package you deliberately build from source goes in
`cybexos.updates.expectedBuilds` in your personal configuration. Releases run
`scripts/check-prebuilt`, `--nvidia` and `--catalogue` (every Software profile
app); each lists any other build and exits 1.

## Release delivery

Cybex OS updates arrive only as published GitHub releases of `CybexHQ/CybexOS`;
there are no publisher keys or channel documents ([releases](releasing.md)).
An installed machine never follows a branch: a release that is not published,
or that is a draft, is not offered. It follows the stable or the beta release
channel ([channels](releasing.md#channels)): new releases reach beta first and
stable once promoted. **Get beta releases** in Settings → Bar & Control
Center → Updates and `cybex update channel stable|beta` choose it; like the
automatic policies, a change asks for administrator authorization. Software
Update offers no channel choice and does not name the channel. A machine running a newer version
than its channel's newest release (after leaving beta) waits for that
channel's next release instead of going back, and says so on the up-to-date
page. An unpublished channel is quietly skipped;
other delivery failures remain visible. Independent NixOS package updates remain
usable when their source check succeeds.

See [the investigation](measurements/update-system-audit-2026-10-26.md) for the
original failures and [the implementation record](measurements/update-system-fix-2026-10-26.md)
for validation scope.
