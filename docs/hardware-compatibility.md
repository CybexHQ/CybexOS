# Installer hardware compatibility audit — 2026-10-30

This is the beta.25 baseline audit, before the compatibility implementation.
See [current hardware policy and qualification](hardware-support.md) for the
changes, remaining limits and the physical test procedure.

Cybex OS has a broad driver base for mainstream Intel and AMD x86-64 UEFI
computers. The current evidence does **not** establish broad physical hardware
compatibility. Driver inclusion, a working installer screen, and a working
installed desktop are separate requirements.

This review evaluated the pinned NixOS configuration and inspected its existing
built kernel-module and firmware trees. It reviewed recorded qualification; it
did not boot another VM, install a physical machine, or change running services.

## Scope and source identity

- Reviewed checkout: `d3070f169d9c5618e62a78f2f2e599bfc2b4186e`.
- Current testing ISO: `1.0.0-beta.25`, built from
  `8c507ed57dbc8d3de4c506852747962b15bade95`. The checkout differs only by the
  beta.25 measurement document and screenshot; implementation and inputs match.
- Nixpkgs: `nixos-unstable`, revision
  `31ecbaca1bdefa45dffc409f0250bd8039ea0010`.
- Evaluated kernel: Linux `7.3` (`7.3.0` module directory); Mesa `26.2.5`;
  `linux-firmware` `20261019`.
- The ISO imports NixOS's minimal installation CD, which enables
  `hardware.enableAllHardware`. This brings a general storage/USB/virtualization
  initrd rather than limiting installation to one motherboard or CPU brand.
- The ISO and installed payload both enable redistributable firmware and
  NetworkManager. They use the same selected kernel and merged firmware tree.
  Hardware-specific settings are generated with `nixos-generate-config` and
  retained in the machine-owned `/etc/nixos/hardware-configuration.nix`.

Sources: [flake](../flake.nix), [kernel selection](../nix/kernel-packages.nix),
[shared module](../nix/modules/default.nix), [ISO module](../nix/modules/installer.nix),
[installation worker](../installer/cybexos-install),
[beta.25 evidence](measurements/testing-iso-beta25-2026-10-30.md).
Upstream defaults are linked at the exact reviewed revision below.

## Expected coverage

“Included” means the evaluated configuration or built module tree provides the
component. It does not certify every device marketed under that brand.
Matching PCI/USB IDs, required firmware, ACPI/BIOS behavior, and board-specific
quirks still determine whether an individual computer works.

| Area | Included support | Practical limit |
| --- | --- | --- |
| Intel processors | x86-64 target; no Intel-only or model-specific CPU restriction in the installer | Requires UEFI; no physical Intel installation matrix. Installed systems enable Intel microcode updates, but the live ISO does not. |
| AMD processors | Same x86-64 image, including AMD chipset/storage and Radeon drivers | No physical AMD installation matrix. Earlier Minisforum X1 Pro 370 reports describe graphics corruption and later input latency; current-image resolution is unverified. |
| Other CPU architectures | Only `x86_64-linux` is exported by the flake and machine template | ARM/Snapdragon, Apple Silicon, Raspberry Pi, and 32-bit x86 have no supported installer image. |
| Intel graphics | `i915` and `xe`; Mesa in the installed desktop | New and old GPU generations, external displays and suspend still require physical tests. |
| AMD graphics | `amdgpu` and `radeon`, with firmware; Mesa in the installed desktop | No current physical Radeon qualification; a loaded KMS driver alone does not prove the Hyprland desktop works. |
| NVIDIA graphics | Installer uses Nouveau or firmware graphics; installed system can select packaged NVIDIA drivers and simple PRIME offload | Driver generation must be chosen correctly. Multi-GPU/multi-domain setups and older unsupported generations need explicit handling. |
| SATA, NVMe and chipsets | `ahci`, `nvme`, many legacy ATA/SATA drivers, USB storage/UAS, and selected SCSI controllers | Broad kernel support is not every storage controller. Intel `vmd` exists in the full module tree; firmware RAID/RST configurations are not qualified installation targets. |
| Wired networking | Intel `e1000e`, `igb`, `igc`, `ixgbe`, `i40e`, `ice`; Realtek `r8169`/`r8152`; Broadcom `tg3`/`bnx2`; Aquantia `atlantic`; Mellanox `mlx5_core`; ASIX USB Ethernet | These are verified module-tree entries. PXE has a smaller early driver set. Exact revisions, link speeds and docks are physically untested. |
| Intel Wi-Fi | `iwlwifi` and related modules, with firmware | Exact radio/firmware combinations and Wi-Fi 6E/7 bands are unqualified. |
| Qualcomm/Atheros Wi-Fi | `ath9k`, `ath10k_pci`, `ath11k_pci`, `ath12k`, with firmware where required | Board/calibration data and newer devices still need verification. |
| MediaTek Wi-Fi | `mt76` family, including `mt7921e` and `mt7925e`, with firmware | No physical radio matrix. |
| Realtek Wi-Fi | In-tree drivers including `rtw88_8822be`, `rtw89_8852be`, `rtw89_8922ae`, with firmware | Vendor-only/out-of-tree USB adapters are not automatically covered. Absence of vendor `r8125` does not imply RTL8125 Ethernet is unsupported: `r8169` explicitly matches PCI ID `10ec:8125`. |
| Broadcom Wi-Fi | `brcmfmac`, `brcmsmac` and `b43` kernel modules; redistributable Broadcom firmware | `b43` firmware is absent and proprietary `wl`/Broadcom STA is absent. Support is device-specific, not universal. |
| Input and peripherals | USB HID, I2C HID, multitouch, Bluetooth USB, UVC webcams, HDA/USB audio and SOF modules/firmware; installed PipeWire/Bluetooth services | Fingerprints, laptop speakers, MIPI cameras, docking, sleep and hotplug often need model-specific work and physical tests. |

The installer deliberately avoids requiring a working accelerated desktop: it
draws with Slint's CPU renderer through KMS/DRM, offers a `nomodeset` basic
graphics entry, and falls back to the text installer. These improve the chance
of completing setup. They do not supply a software-rendered replacement for a
working installed Hyprland graphics stack.

## Concrete gaps and restrictions

1. **UEFI only; Secure Boot installation is blocked.** `check_platform()` refuses
   legacy BIOS and unprovisioned Secure Boot before erasure. Signed media,
   enrollment, payload authentication and external-module trust remain release
   blockers. The kiosk currently tells users to turn Secure Boot off; that
   instruction conflicts with the repository's hardware/security contract and
   is not an accepted compatibility solution. See
   [the worker](../installer/cybexos-install), [kiosk messaging](../installer/kiosk/src/ui.rs)
   and [hardware/security blockers](hardware-security.md).
2. **Broadcom coverage has a known firmware/driver hole.** Evaluation gives
   `hardware.enableAllFirmware = false` and
   `networking.enableB43Firmware = false`. The merged firmware tree contains
   `brcm/` but no `b43/`, and the only extra ISO kernel package is ZFS, not
   Broadcom STA. A device needing these missing components can have no working
   Wi-Fi even though a Broadcom kernel module exists. Proprietary application
   selection is not a driver-installation mechanism.
3. **PXE support is narrower than networking after USB boot.** The ISO explicitly
   includes these early NIC modules:
   `r8169`, `r8152`, `igc`, `igb`, `e1000e`, `e1000`, `ixgbe`, `tg3`, `bnx2`,
   `atlantic`, `ax88179_178a`, `cdc_ether`, `cdc_ncm`; upstream adds virtual NICs.
   Other included full-system drivers such as `ice`, `i40e` and `mlx5_core` are
   absent from the evaluated initrd list. A NIC can work after booting USB but
   fail to attach the network ISO. Wi-Fi PXE is not configured.
4. **NVIDIA detection does not select the correct GPU generation.**
   `nvidiaOpen` defaults to `true`. Open modules use the stable driver
   (`595.112.07` at this pin) for supported Turing-or-newer GPUs; the closed
   choice defaults to `legacy_580` (`580.196.07`) for Maxwell/Pascal/Volta.
   The user must choose the latter for older supported cards. The detector
   tests for any NVIDIA PCI vendor ID, rather than checking supported display
   IDs/generations; older NVIDIA chipset devices can therefore also trigger
   driver selection. There is no guided Kepler/Fermi legacy-driver path.
   Automatic PRIME only handles one NVIDIA plus one Intel/AMD GPU in PCI domain
   zero. See [detection](../installer/cybexos-install),
   [defaults](../installer/cybexos-installerd) and [driver policy](../nix/modules/hardware.nix).
5. **The live ISO does not load early CPU microcode updates.** Both evaluated
   `hardware.cpu.intel.updateMicrocode` and
   `hardware.cpu.amd.updateMicrocode` are `false` on the ISO, with no prepended
   microcode image; both are `true` on the installed payload. The defaults live
   inside the `cybexos.enable` branch, which the installer-only ISO does not
   enable. This does not exclude either CPU vendor, but leaves the installer
   reliant on platform-provided early microcode. Presence of `amd-ucode/` in
   the firmware tree is not evidence of an early microcode update.
6. **The installer takes whole disks only.** Accepted whole-disk paths are
   `/dev/sd*`, `/dev/vd*`, `/dev/nvme*n*` and eMMC/SD `/dev/mmcblk*` (never
   their boot or RPMB areas). The review and the erase check the same disk by
   its serial number, else its WWN, else its kernel device path and size, so
   disks without a serial (most virtual disks) are accepted. A disk needs at
   least **64 GiB** (not a marketed 64 GB), no mounts/swap/active mappings,
   and is fully erased. The layout reserves a
   16 GiB ESP. RAID/LVM/multipath targets and dual-boot partitioning are not
   provided by the guided fresh installer. See [disk validation](../installer/cybexos-install)
   and [shared layout](../nix/modules/default.nix).
7. **Internet is required even with the bundled desktop payload.** Preflight
   requires HTTPS to `cache.nixos.org`; NVIDIA and unbundled applications still
   download. A missing Wi-Fi driver therefore matters even with an offline
   payload. WPA2 and WPA3 have virtual-radio evidence; enterprise certificates,
   hidden networks, captive portals and physical radios do not. The helper's
   simple enterprise flow uses PEAP/MSCHAPv2, not every 802.1X method. The
   editable Google DNS default also needs qualification on restricted networks.
8. **The exact Dell XPS camera profile has a known blocker.** The IPU7
   private-ABI guard rejects the selected kernel layout; the camera stack
   builds but initialization fails closed; update health reports it without
   holding back updates. Generic webcam
   support does not resolve this machine-specific issue. See
   [the existing camera blocker](hardware-security.md). Linux 7.3's ipu-bridge
   also lists the HM1092 IR sensor, which has no driver, so the sensor graph
   never completes ([matched laptops](laptop-support.md)).
9. **The XPS 14 OLED panel needs PSR and LOBF off.** On SKU 0DB9 with the LG
   panel (EDID `30e4c607`), PSR2 selective fetch produced full-screen black
   flashes at 120 Hz (`Selective fetch area calculation failed in pipe A`), so
   `nix/modules/hardware.nix` boots with `xe.enable_psr=0`. Without PSR, kernel
   7.3's Xe driver enables Link Off Between Frames (LOBF) on that panel instead:
   its link then dropped about every 3.1 s (DPCD lane status `00 00 80 00`), and
   each retrain (`intel_encoder_link_check_work_fn`) power-cycled the panel for
   about 1.2 s under the display modeset lock. Hyprland waited in
   `drm_modeset_lock`, freezing the screen and delaying key releases into key
   repeats. Xe has no LOBF parameter; `xps-panel-link.service` writes 1 to
   `/sys/kernel/debug/dri/*/eDP-1/i915_edp_lobf_debug` before the display
   manager starts (`i915_edp_lobf_info` then reports LOBF disabled). With it,
   compositor responses stayed under 20 ms instead of 1.1 s freezes every 3 s.
   Both quirks cost some idle power and apply to no other panel or machine.

RAM is displayed with a warning below about 8 GiB, rather than a qualified hard
minimum. The optional run-from-memory boot entry recommends at least 16 GB.
No broad low-memory or old-CPU/full-application qualification is recorded.

## What has actually been tested

- **Current beta.25:** plain and encrypted installations through the real
  graphical installer and all ten recorded staged-updater lifecycle scenarios
  passed in QEMU UEFI guests. The report explicitly excludes physical hardware,
  real PXE boot and Secure Boot. See [beta.25](measurements/testing-iso-beta25-2026-10-30.md).
- **Networking on an earlier beta.2 snapshot:** the actual installer,
  NetworkManager and simulated `mac80211_hwsim` radios exercised WPA2, WPA3,
  wrong passwords, reconnection and HTTPS. This is useful workflow evidence;
  it does not qualify real Intel/Realtek/MediaTek/Qualcomm/Broadcom radios or
  requalify beta.25. See [network audit](measurements/installer-network-partitioning-2026-10-24.md).
- **Driver builds on beta.23:** both NVIDIA module families, the XPS system,
  product and ISO built. Compilation does not qualify those devices. See
  [beta.23](measurements/testing-iso-beta23-2026-10-30.md).
- **PXE on beta.23:** an isolated guest used the real iVentoy service with a
  test-only NAT address adjustment. This did not qualify an unmodified physical
  LAN client. See the same beta.23 record.
- **Earlier physical feedback:** the X1 Pro 370 showed graphics corruption on
  an older image, and later installer input/display latency was reported.
  These reports identify regression targets, not proof that beta.25 still has
  those failures or that it fixes them. See
  [graphics](measurements/installer-graphics-beta2-2026-10-23.md) and
  [latency](measurements/installer-kms-latency-2026-10-24.md).

The project's [hardware qualification](hardware-security.md) and
[validation status](validation.md) already distinguish declarations/builds
from physical qualification. No representative physical pass matrix was found
in the reviewed records.

## Recommended qualification before claiming broad compatibility

Use one frozen ISO/source identity and record model, firmware version, CPU/GPU,
network PCI/USB IDs, loaded drivers and firmware errors for each machine.

| Representative machine | Main coverage |
| --- | --- |
| Older UEFI Intel laptop with Intel Wi-Fi | `i915`, older platform/input/audio, SATA and battery/sleep |
| Recent Intel laptop with newer graphics | `xe`, NVMe/VMD exposure, SOF audio and modern Wi-Fi |
| AMD Ryzen desktop | AMD chipset/USB, Radeon, NVMe/SATA and Realtek 2.5 GbE |
| AMD laptop or Minisforum X1 Pro 370 | Integrated Radeon, the reported graphics/input regressions, MediaTek/Realtek Wi-Fi where fitted |
| NVIDIA desktop and hybrid laptop | Turing-or-newer open modules, Maxwell/Pascal closed 580, PRIME, external outputs and resume |
| Broadcom-equipped x86 laptop | `brcmfmac` versus `b43`/STA firmware and driver requirements |
| USB-C dock and adapters | Realtek/ASIX Ethernet, USB Wi-Fi, display hotplug, input and audio |
| Exact matched XPS 0DB9/0DBA | Existing panel/haptic/audio/power quirks and the blocked processed camera |

For each relevant machine, check USB boot, applicable physical PXE boot,
network authentication/downloads, disk visibility, encrypted fresh installation,
unlock/login, desktop rendering, audio/input, suspend/resume, external displays,
and an actual staged update, trial boot, confirmation and rollback. Use disposable
or explicitly authorized disks. Secure Boot requires completing its existing
release blockers before a passing test is possible.

Prioritize the identified compatibility gaps, then publish the physical matrix
with exact device IDs. Until that exists, a defensible description is:
**“Targets Intel and AMD x86-64 UEFI PCs, with broad Linux drivers; physical
hardware compatibility remains under qualification.”**

## Pinned upstream references

- [NixOS installation CD base](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/nixos/modules/installer/cd-dvd/installation-cd-base.nix)
- [General hardware/initrd coverage](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/nixos/modules/hardware/all-hardware.nix)
- [Redistributable versus additional firmware](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/nixos/modules/hardware/all-firmware.nix)
- [Generated machine hardware configuration](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/nixos/modules/installer/tools/nixos-generate-config.pl)
- [NVIDIA options and supported branches](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/nixos/modules/hardware/video/nvidia.nix)
- [NVIDIA package versions](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/pkgs/os-specific/linux/nvidia-x11/default.nix)
