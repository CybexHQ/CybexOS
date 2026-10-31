# Testing ISO beta.34: installer screen, docks and fallback — 2026-10-31

## Why

beta.33 was network-booted (iVentoy) on a Dell XPS 14 DA14260: Intel Panther
Lake, `xe`, a 2880×1800 panel, and an Apple Studio Display XDR on
Thunderbolt. It failed twice.

**The splash froze at about 70 %.**
- The USB Ethernet adapter (RTL8153) was plugged in behind the display. Its
  traffic ran through a USB3 tunnel that the firmware had made.
- The `thunderbolt` driver, which is not in the medium's initrd, loads in
  stage 2. By default it resets the USB4 host router's ports and tears down
  the tunnels the boot firmware made (`tb_start()` in
  `drivers/thunderbolt/tb.c`, `host_reset=true` in `nhi.c`).
- The journal shows `usb 2-3: USB disconnect` 0.3 s after `thunderbolt`
  registered. The NBD connection serving the ISO went silent after 126 MB
  (iVentoy kept retransmitting), and the root file system stopped answering.
- A USB stick behind a dock or Thunderbolt display fails the same way.

**With the adapter on the laptop, the screen stayed black.**
- `cybexos-installer` panicked at its first frame, every 0.8 s:
  `sw_shadow.rs:47`, `left: 20737800`, `right: 20738048`.
- Drivers round a dumb buffer's allocation up to whole pages: i915/xe,
  amdgpu, nouveau, virtio-gpu and simpledrm to 4 KiB, and Intel discrete
  `xe` to 64 KiB.
- `slint-kms.patch` derived the row length from the mapping's length:
  20738048 / 1800 = 11521 bytes instead of the pitch, 11520. The shadow copy
  then rejected the layout.
- Any frame that is not a whole number of pages crashed this way, on any GPU,
  for example 1440×900, 1600×900, 1680×1050 and 2880×1800. Every size tested
  before was a whole number of pages: 1280×800, 1920×1080 and 2560×1600.
- beta.33 reproduces it in QEMU (virtio-gpu) at 2880×1800 with the same
  numbers: 39 panics, and a one-colour capture.

The same log showed `display zoom 3` while the screen drew on the 2880×1800
panel. The zoom came from the largest mode of any connected output, here the
external display. Zoom 3 puts the 1280×800 canvas's footer, with Continue,
below the panel's edge. An installer review of the medium found this.

## Change

- **`slint-kms.patch`** (`display/swdisplay/dumbbuffer.rs`): the renderer
  receives exactly the frame's pitch × height bytes of a dumb buffer's
  mapping.
- **The zoom** (`installer/kiosk/src/main.rs`, `zoom.rs`) is computed from the
  output Slint opened, after the window exists and before it is shown.
  `CYBEXOS_INSTALLER_RESOLUTION` still overrides it for previews.
- **`cybexos-installer-ui` gains an `ExecStopPost` (`screenFailed`).**
  - A clean exit (a keyboard change) and exit 75 are not failures.
  - Neither is a failure while tty1 is not the active VT. Slint's KMS backend
    cannot hold the display behind the recovery shell (`SeatEvent::Disable`
    is unimplemented upstream).
  - Three failures within a minute send the screen menu's own
    `text-installer` request through `cybexos-installerd --client`. The
    service refuses it while installing.
- **The medium boots with `thunderbolt.host_reset=0`.** Installed systems
  keep the reset. Parity asserts both.
- **`scripts/qualify-installations --display WIDTHxHEIGHT`** sets the virtual
  display size; the default is 1280×800.

## Exact source and image

- Version: `1.0.0-beta.34`.
- Image source revision: `7c8bc7c4dd9f71ea4cf2cacc580bd14bc68cc3eb` on
  `main`, built from a clean tree. The change is `d399d57d`.
- Source NAR: `sha256-+WHjASvQjF1nZKRRa7IS40VhTK4RMrjfuD8ZRkeAVlw=`.
- Nixpkgs: `nixos-unstable` at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`,
  unchanged. `system.stateVersion` is unchanged. Linux 7.3.
- ISO SHA-256: `a405e353f39cf611031e6234f6b0d05535442f97cf069538e8c5ee9bd15aac7a`.
- ISO size: 7,457,329,152 bytes (6.945 GiB).

This record was written after the image was built; it is not part of its
source NAR.

## Checks

On the change tree:

- `nix develop -c tests/run` passed, including 850 Python tests.
- The installer screen package's Rust tests passed: 30 unit tests (one new,
  for the resolution override), 15 interaction tests and 4 presentation tests.
- `checks.x86_64-linux.parity` passed with the new assertions.

On `7c8bc7c4`:

- `scripts/check-prebuilt` passed in its default mode: nothing compiles
  beyond the expected local builds. It ran from an export of the revision; in
  the checkout, `getFlake` stops at the root-owned, ignored
  `image/live-rootfs/__pycache__`.
- `scripts/check-image-parity` passed all 42 checks against this ISO, with
  the flake `git+file:///home/john/Code/CybexOS?rev=7c8bc7c4…`.

**The screen at 2880×1800** (QEMU, virtio-gpu, OVMF, 4 GiB):

| | beta.33 | beta.34 |
| --- | --- | --- |
| Screen | 39 panics, `auto-restart` | `active`, 0 restarts |
| Zoom | — | 2.25 |
| Capture | one colour | the welcome page, 2,661 colours |

beta.34's kernel command line includes `thunderbolt.host_reset=0`.

**Fallback.** Three `SIGABRT`s to the screen produced:
- `The installer screen failed 3 times within a minute (core-dump); asking
  for the text installer.`
- `cybexos-installer-text-switch.service` became active;
- tty1 showed the text installer's development-build question.

## Installation and staged-updater verification

The command was `scripts/qualify-installations --interactive --applications
standard --scenario lifecycle`, through the real tty1 screen. The two cases
ran in parallel, each in its own `agent-resource` lease (`94e4745b…`,
`6a7e7dc1…`); both leases closed with no errors. GitHub's anonymous API
allowance had 55 of 60 calls left at the start.

- **plain**, with `--display 1440x900`, passed all 22 milestones and all 10
  lifecycle scenarios.
  - A 1440×900 frame is 5,184,000 bytes, not a whole number of pages:
    beta.33's screen cannot draw it.
  - `nativeGuiAssertions` recorded the 1440×900 display, and the erase click
    landed on the zoomed screen.
- **encrypted**, at the default 1280×800, passed all 22 milestones and all
  10 lifecycle scenarios.
- The prebuilt store transfer copied 3,381 and 3,376 paths, in 141 s and
  137 s.
- `flathubApps`: `org.vim.Vim` 9.2.1161 (a 17.9 MB download) installed in
  33 s and 35 s and ran.

## PXE delivery

beta.34 was copied to a task staging directory on the same filesystem and
hashed against the build. It was then moved into `/data/pxe/iso`, where its
checksum verified. beta.33 and its checksum were removed (7,457,329,152 plus
92 bytes); no other image was there.

`refresh_img_list` returned `result: success`, and `get_img_tree` listed only
beta.34. `get_img_summary` kept a stale count of 2, so iVentoy was restarted
with the AGENTS.md guard.
- `config.dat` (9,234 bytes) was copied aside first.
- This time the restart logged `Recover: ip:10.10.0.7 mask:255.255.254.0
  gateway:10.10.0.1 pool:[10.10.0.200-10.10.0.219]`, so the copy was not
  needed and was deleted.

Afterwards:
- `query_status` reported `running`;
- `get_img_tree` listed only beta.34 (image 1), and `get_img_summary`
  reported `count: 1`;
- iVentoy listened on its DHCP proxy, TFTP, HTTP, NBD and iSCSI ports;
- `iventoy.service` was `active`.

## Open findings from the medium review

Two independent read-only reviews of the boot path and the running installer
also found issues that beta.34 does not change. They are listed here for
later releases.

**Can stop a boot or an installation:**
- **Secure Boot.** `EFI/BOOT/BOOTX64.EFI` is unsigned (an empty certificate
  table, checked on beta.33). With Secure Boot on, the default on most
  Windows PCs, firmware refuses the medium. Meanwhile
  `docs/hardware-support.md` advises keeping Secure Boot enabled.
- **The recovery shell.** Slint's KMS backend panics on
  `SeatEvent::Disable`: the XPS log shows 48 aborts after Ctrl+Alt+F2. The
  screen restarts when tty1 returns, but four failed starts of 5 s each make
  it request the text installer (from the code; not tested).
- **A missing medium.** With `DefaultDeviceTimeoutSec=5min` and hidden
  status, an unreadable stick shows the splash for five minutes, then an
  emergency shell without a reason.
- **Writing the stick.** `nix-store.squashfs` is over 4 GiB, so file-copy
  writers such as Rufus's ISO mode cannot work. Ventoy was not tested.
  `findiso=` is passed, but nothing in stage 1 reads it. The docs do not say
  how to write the medium.
- **NVIDIA-only machines and laptops in dGPU mode** have no recorded boot.
  nouveau loads in stage 2 after the firmware framebuffer is removed.

**Deliberate policies with a cost:**
- The medium resolves through Google DNS only (`ignore-auto-dns`). This fails
  on networks that block outside DNS.
- eMMC disks are not offered.
- Disks without a serial number are refused. That includes the default
  virtio disks of virt-manager, Proxmox and GNOME Boxes.

**Smaller:**
- Only the first connected output is used; a docked laptop with its lid
  closed draws on the closed panel.
- iVentoy's bundled `dhclient` is "not found" (about 13 s of retries).
- `serial-getty@ttyS0` restarts every 10 s on machines without a UART.
- A few SD-reader and NIC drivers are missing from stage 1.
- There is no RAM check and no zram on the medium.

## Not exercised

- **Real hardware:** the XPS 14 with these fixes, a real iVentoy network boot
  of beta.34, and Secure Boot.
- **A physical Thunderbolt dock or display:** `host_reset=0` is checked only
  on the command line, since QEMU has no USB4.
- **Several monitors:** the zoom fix was not run with more than one output.
  QEMU's single-head display only shows that the zoom follows the opened
  output.
