# Testing ISO beta.23: prebuilt-only NixOS unstable, software profiles and the new Software — 2026-10-30

Cybex OS now follows **nixos-unstable** and installs prebuilt packages only
([updates](../updates.md#prebuilt-packages-only)): Hyprland 0.56.2 and its
libraries, hypridle 0.1.8 and NVIDIA 595.112.07 come from cache.nixos.org, so
the compatibility overlay and pins are gone, and Hyprland, its portal, Xwayland
and glibc locales use NixOS's cached builds. The staged updater dry-runs every
update and Software change and refuses one that would compile Nixpkgs
packages. Software-only changes become the default without a trial boot.
Codex is always installed, Claude Code whenever unfree packages are allowed.
The installer gains a Software step with six profiles, and Software becomes a
store ([software and defaults](../software-and-defaults.md)). This image also
contains Wiz everywhere (beta.22) and the onboarding polish from `main`.

## Exact source and image

- Version: `1.0.0-beta.23`.
- Image and installed-source revision:
  `57db36ac993204f6a376ca581b3b98b6417d0183` (branch `feat/prebuilt-software`),
  built from a clean tree, so the ISO and installed systems report it.
- Source NAR: `sha256-AEDkJHXF0Qz9/HSmkxvLMtQyZAcKI4IYXl8zIoGjhPE=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`
  (2026-10-27): NixOS 26.11, Linux 7.3, Qt 6.12.0, Quickshell 0.3.2.
  `system.stateVersion` is unchanged (26.05).
- ISO SHA-256: `00fef7e044ff1530bc594b7ff9f5541c43626cb7988d75cbcee376afaebcbab8`.
- ISO size: 7,319,273,472 bytes (6.817 GiB); it now carries the Development
  profile's free apps.
- Served ISO: `/data/pxe/iso/cybexos-1.0.0-beta.23.iso` with
  `cybexos-1.0.0-beta.23.iso.sha256` (92 bytes).

## Prebuilt packages

`scripts/check-prebuilt` walks a system's build plan against cache.nixos.org,
independent of this host's store. All three modes exit 0, with no Nixpkgs
package compiled:

| Mode | Built locally | Expected local builds |
|---|---|---|
| default product | 465 | 21 |
| `--nvidia` | 476 | 28 |
| `--catalogue` (every Software profile app) | 492 | 25 |

Locally built derivations are configuration (22 NixOS-generated, sourceless
steps such as pam.d, the initrd, setuid wrappers and AppArmor rules), trivial
local-only steps, and expected builds: Cybex OS's own packages, unfree vendor
downloads (1Password, Brave Origin, ChatGPT, Claude Code, Spotify, Steam,
NVIDIA) and kernel modules. On stable 26.05 the same product compiled 111
packages, Hyprland alone about 3.5 minutes per update.

The catalogue generator dropped apps NixOS had not built at this revision
(Thunderbird, Lutris, Bottles, digiKam, 0 A.D., Amberol, Celestia) or that
lack metadata. A later run picks them up once they are prebuilt.

## Qt 6.12 findings

Moving to unstable brought Qt 6.12, with two runtime changes the shell
relied on, both fixed and guarded by `tests/quickshell/qt612-compatibility.test.cjs`:

- A QML signal's `var` argument arrives as a sequence when it holds an array;
  `Array.isArray()` is false for it. Every check also accepts `instanceof
  Array`. Without this Software Update never reached "ready".
- QtQuick adds a `Color` type that wins over the `qs.Commons` palette
  singleton. The kit uses a qualified import, and the plugin runtime copy
  rewrites third-party Omarchy plugins the same way.

`qmllint` 6.12 also reads Quickshell's opaque qmltypes placeholders as
memberless types; `tests/qml-lint` lints against a copy without them.
`desktop/runtime-compatibility.json` now lists Qt 6.12.

The staged-updater VM test found that NixOS 26.11 makes the setuid `pkexec`
wrapper opt-in. Every privileged desktop request uses it, so the lifecycle
module enables it and parity asserts it.

## Build and source verification

- Builds from the exact source passed: the ISO, `installer-ui` (its 46 Rust
  tests), `desktop`, and the checks `parity`, `lifecycle`, `system`,
  `product`, `xps-system`, `nvidia-kernels` and `nvidia-evaluation`.
- `tests/run` passed: 786 Python tests (19 skipped), 25 system-settings tests,
  the Node suite (1554 tests: 1537 passed, 17 skipped), plugin packages and
  the Model Usage contract. `tests/qml-lint`: 476 QML files and 4 harnesses
  without errors.
- Real shell under private headless compositors, one at a time on Qt 6.12:
  `update-flow`, `software-app`, `welcome-guide`, `settings-pages`,
  `shortcut-editor`, `wallpaper-picker`, `user-plugins` and
  `assistant-overlay` passed on the merged tree; `display-settings` and
  `keybindings-model` passed on this branch before the last merges.
  (`notification-images` and `model-usage-popup` need harness changes on this
  host; `settings-runtime` runs only as root in a guest.)
- `checks.x86_64-linux.vm` (the real staged updater in a NixOS VM, run through
  `agent-resource` with `QEMU_OPTS=-no-user-config`) passed in 159 s: a real
  Software change through the new prebuilt check in an offline guest, apply,
  local previews and an interrupted build.
- `scripts/check-image-parity`: all 41 completed-image/source checks passed.

## Installation and staged-updater verification

`scripts/qualify-installations --case both --scenario lifecycle --interactive`
passed for plain and encrypted installations in 30 minutes: all 18
milestones and 10 lifecycle scenarios each. The new installer Software step was
driven through the real tty1 screen (Development profile, with Wiz waiting),
and the review showed "Software: Development · on this USB stick". The
upstream scenario found nixos-unstable still at the locked revision, so it
staged that revision through the prebuilt check; a genuinely newer revision
was not exercised. The run used supervised `agent-resource` lease
`37cf49cc72704e9a92ca5399d33009cb` with a CI reservation of 26 GiB and eight
CPUs.

Not exercised: physical hardware, Secure Boot, a signed vendor channel, a
real Software install through the desktop's authorization dialog on an
installed system, and the prebuilt check refusing a real uncached revision
(covered by unit tests).

## PXE (iVentoy) with systemd stage 1

NixOS 26.11 removed the scripted initrd that iVentoy 1.0.41's NixOS hook
patched. The medium's initrd unit `cybexos-network-medium` now runs that hook
(`/ventoy/hook/nixos/ventoy_disk.sh`) when iVentoy injected it.

Verified against the real iVentoy service, without changing its
configuration: a KVM guest booted beta.23's kernel and iVentoy's per-client
initrd, read by HTTP range requests from `/viso/id/1/...`, with no local
medium. The hook found the NIC by MAC, attached the ISO through iVentoy's NBD
export (`/dev/nbd0`, `IMG1`), uploaded its client log, and stage 1 mounted
`CYBEXOS_INSTALL` and its squashfs, switched to NixOS 26.11 and started the
installer screen. The NBD connection stayed up after the switch to the real
root. As in the 2026-10-23 check, QEMU's NAT network needed the guest address
(10.0.2.15) set in a test-only overlay; on the LAN iVentoy supplies the
client's real address. iVentoy's bundled DHCP client does not configure the
interface in this initrd, so the hook uses that static fallback, as it did
for beta.22's physical boot. A physical LAN boot was not performed.

## PXE delivery

After qualification, beta.23 was copied to a task staging directory on the
same filesystem, hashed against the build, and moved into `/data/pxe/iso`,
where its checksum verified. beta.22 and its checksum were removed
(6,940,846,080 plus 92 bytes); no other operating system's image changed.
`refresh_img_list` returned `result: success` and `get_img_tree` listed only
beta.23, but `get_img_summary` kept a stale count of 2. After
`sudo systemctl restart iventoy.service`, `query_status` reported `running`,
`get_img_tree` listed only beta.23 (image 1), `get_img_summary` reported
`count: 1`, and `iventoy.service` was `active`.
