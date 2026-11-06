# Curated PC hardware research — 2026-11-06

This audit adds experimental configuration support, not physical qualification.
The scope is non-Apple Intel/AMD x86_64 UEFI PCs on **stock prebuilt Nixpkgs
kernels**. No kernel fork, patch, configuration rebuild, package-set overlay,
new power manager or bootloader is imported. Packaged external modules remain
permitted by the existing policy; this catalogue adds none.

## Frozen research sources

| Source | Reviewed identity |
| --- | --- |
| Omarchy latest release | GitHub `releases/latest` returned [v4.5.0](https://github.com/basecamp/omarchy/releases/tag/v4.5.0), published `2026-11-05T05:36:53Z`; resolved commit [`ac2690cd7be4f47e4a255f5e2e78d904d436b068`](https://github.com/basecamp/omarchy/tree/ac2690cd7be4f47e4a255f5e2e78d904d436b068). |
| Omarchy packages | [`d9b1747fae3a664a74255d94f0c9a7b05b12850d`](https://github.com/omacom/omarchy-pkgs/tree/d9b1747fae3a664a74255d94f0c9a7b05b12850d), the package repository HEAD at research time. It is an independently moving package snapshot, **not** asserted to be the exact packages installed by every v4.5.0 machine. |
| nixos-hardware | [`d645c71a58dbae3eb17ff551a07aea13a541cb1a`](https://github.com/NixOS/nixos-hardware/tree/d645c71a58dbae3eb17ff551a07aea13a541cb1a). Research-only pin; no new flake input or lock change. |
| Nixpkgs | Existing lock [`31ecbaca1bdefa45dffc409f0250bd8039ea0010`](https://github.com/NixOS/nixpkgs/tree/31ecbaca1bdefa45dffc409f0250bd8039ea0010), currently `nixos-unstable` until the planned 26.11 transition. Evaluated latest kernel `7.3`; existing firmware package `20261019`. |
| Cybex OS baseline | `c169b7a0`, especially [matched laptops](laptop-support.md), [hardware support](hardware-support.md), [hardware security](hardware-security.md), and the exact-model gates in `hardware.nix`. Existing physical observations are not a complete installation/lifecycle qualification. |

The inventory covered Omarchy's entire `install/hardware` and
`install/user/hardware` trees, its hardware predicate helpers, the x86 package
recipe and all 188 `.patch` files listed in that recipe. The recipe inventory and targeted patch diffs were inspected
as source, never applied or built. The patch-family decisions below are a
policy audit, not a claim that every backport was compared with upstream. The nixos-hardware snapshot contained 895
Nix/Markdown files, including 760 `.nix` files. A repository-wide policy screen
located kernel, overlay, power-manager and bootloader settings; selected
Framework/ThinkPad import closures were then reviewed in detail. This is not a
line-by-line correctness review or physical test of every upstream model.

## Catalogue and matching contract

[lifecycle/cybexos/hardware-profiles.json](../lifecycle/cybexos/hardware-profiles.json)
is the one list of approved IDs, exact identities, provenance, version bounds,
workaround removal conditions and limits. `approved` permits selecting a
configuration; it does **not** mean tested hardware. Every entry is
`experimental`, with physical qualification `not-run` and no qualification
record.

`support_for(sysroot=Path('/sys'), *, kernel=None, catalogue=None)` in
[hardware_profiles.py](../lifecycle/cybexos/hardware_profiles.py) returns
`profileId`, `profileName`, `status`, `summary`, `limitations` and `sources`, plus
kernel/test metadata. It accepts a decoded schema-1 catalogue or JSON path for
fixtures. It reads sysfs and packaged JSON only, without commands, writes,
firmware loading or device binding. Architecture comes from `os.uname()`; CPU
vendor is checked when sysfs exposes its modalias. Missing CPU modalias is not
a claim that a CPU was qualified. Apple vendor/board identities, non-x86_64,
non-Intel/AMD vendor codes when available, and absent UEFI are unsupported.

DMI values are exact, case-sensitive strings after trimming sysfs whitespace.
Omarchy’s generic `omarchy-hw-match` searches product name/family using a
case-insensitive regex. Cybex OS deliberately does not inherit that matching.
No model substring, broad vendor rule, arbitrary regex or fuzzy matching is
used. ThinkPad identification additionally requires a complete ten-character
alphanumeric MTM, the approved four-character machine type, and the exact
product version. Unknown/unlisted DMI spellings, malformed catalogue rules,
unapproved entries and ambiguous matches yield no profile ID. An out-of-range
or unreadable kernel version also yields no selectable ID. No injected status
or inventory result can promote a profile to `qualified` in schema 1.

| Approved ID | Required identity | Configuration and current limits |
| --- | --- | --- |
| `dell-xps-13-dx13260-wcl` | `Dell Inc.`, `XPS 13 DX13260` or `DX13260`, SKU `0E53` | Existing XPS options, stock kernel ≥7.3. No built-in camera support. |
| `dell-xps-13-dx13260-ptl` | Same product, SKU `0E54` | Existing XPS options, stock kernel ≥7.3. Speaker fallback until 7.4; built-in camera unsupported. |
| `dell-xps-14-da14260` | `Dell Inc.`, `XPS 14 DA14260` or `DA14260`, SKU `0DB9` | Existing XPS options, stock kernel ≥7.3. Existing PSR/LOBF quirk additionally requires measured EDID `30e4c607`; built-in IPU7 camera blocked. |
| `dell-xps-16-da16260` | `Dell Inc.`, `XPS 16 DA16260` or `DA16260`, SKU `0DBA` | Existing XPS options, stock kernel ≥7.3. No extrapolated XPS 14 panel quirk; built-in IPU7 camera blocked. |
| `hp-zbook-ultra-g1a` | `HP`, exact `HP ZBook Ultra G1a 14 inch Mobile Workstation PC` or `HP ZBook Ultra G1a`, board `8D01` | Existing ZBook options, stock kernel ≥7.3. Regional order SKU is not an identity key. PMF Smart PC remains opt-in; ISP4 capture requires physical checking. |
| `framework-13-amd-7040` | `Framework`, `Laptop 13 (AMD Ryzen 7040Series)` | New narrowly translated settings, stock kernel ≥6.8; evaluated on 7.3. PSR hang workaround and exact RTL8156 Ethernet expansion-card delay. |
| `lenovo-thinkpad-t14-gen5-amd` | `LENOVO`, `product_version=ThinkPad T14 Gen 5`, complete MTM of type `21MC`/`21MD` | New EC wake workaround, stock kernel ≥6.8; evaluated on 7.3. Excludes P14s, Intel T14, T14s and Snapdragon models. |

Framework's exact vendor/product values come from the upstream AMD-authored
[kernel DMI quirk a55bdad5dfd1](https://github.com/torvalds/linux/commit/a55bdad5dfd1efd4ed9ffe518897a21ca8e4e193),
which also explains the BIOS 03.03 keyboard-wake tradeoff. Lenovo's
[vendor BIOS readme](https://download.lenovo.com/pccbbs/mobiles/r2luj25w.txt)
identifies T14 Gen 5 types **21MC/21MD**, separately from P14s Gen 5 types
**21ME/21MF**. The profile's additional DMI version gate deliberately fails
closed if firmware uses an unlisted spelling. Marketing names alone cannot
select either profile.

[nix/modules/hardware-profiles.nix](../nix/modules/hardware-profiles.nix) reads
the same JSON for its nullable enum `cybexos.hardware.profile`. It writes the
full catalogue plus `selectedProfile`, `selected` and `configuredKernel` to
`/etc/cybexos/hardware-support.json` on installed systems and the live medium.
The existing `/etc/cybexos/hardware-profile.json` remains owned by
`hardware.nix`. Catalogue selection alone does not enable legacy XPS/ZBook
booleans: the fresh installer must retain its existing exact SKU, panel and
camera decisions alongside the new profile ID. Existing personal settings
and machine locks are not rewritten or refreshed.

Manual `hardware.profile` selection is an explicit owner assertion of the
model identity, as with existing hardware options; Nix evaluation cannot read
the future target's DMI. Automatic selection must go through `support_for()`.
The generic live medium carries metadata without choosing a model. The module
never probes the build host to choose target settings.

## Adopted nixos-hardware equivalents

All source links below use the reviewed nixos-hardware revision.

| Decision | Upstream setting and evidence | Cybex OS action / removal condition |
| --- | --- | --- |
| Adopt | [Framework common AMD](https://github.com/NixOS/nixos-hardware/blob/d645c71a58dbae3eb17ff551a07aea13a541cb1a/framework/13-inch/common/amd.nix) sets `hardware.amdgpu.dcDebugMask.disablePsr=true`, citing [Framework display hangs](https://community.frame.work/t/fedora-kde-becomes-suddenly-slow/58459) and [AMD issue 3647](https://gitlab.freedesktop.org/drm/amd/-/issues/3647). The upstream [bit map](https://github.com/NixOS/nixos-hardware/blob/d645c71a58dbae3eb17ff551a07aea13a541cb1a/common/gpu/amd/dc-debug-mask.nix) assigns PSR-disable bit 16. | Exact Framework 7040 profile supplies `amdgpu.dcdebugmask=0x10`. `framework13Amd7040.disablePsr=false` permits personal masks or fixed-kernel testing. Costs idle power. No established upper fixed-version bound: remove after upstream retires it **and** physical display/suspend testing passes. |
| Adopt | [Framework common](https://github.com/NixOS/nixos-hardware/blob/d645c71a58dbae3eb17ff551a07aea13a541cb1a/framework/13-inch/common/default.nix) adds `0bda:8156` Ethernet expansion-card USB autosuspend delay `20`. | Same exact USB rule, only under the Framework 7040 profile. `framework13Amd7040.ethernetAutosuspend=false` opts out. Remove after upstream retirement and physical reconnect/throughput/sleep checks. It cannot match other USB IDs. |
| Adopt | [ThinkPad T14 Gen 5 AMD](https://github.com/NixOS/nixos-hardware/blob/d645c71a58dbae3eb17ff551a07aea13a541cb1a/lenovo/thinkpad/t14/amd/gen5/default.nix) sets `acpi.ec_no_wakeup=1` for EC wake drain, citing [Linux ACPI discussion](https://lore.kernel.org/all/ZnFYpWHJ5Ml724Nv@ohnotp/). Direct lore fetch returned HTTP 403; the pinned Nix source was readable. | Same parameter, restricted to approved 21MC/21MD profile. `thinkpadT14Gen5Amd.preventEcWakeup=false` opts out. Lid/keyboard/AC/dock wake behavior needs checking. No proven fixed BIOS/kernel upper bound; retire only with upstream guidance and measured physical suspend/wake evidence. |
| Already upstream | Framework wake-on-AC workaround `<6.7`, headset `snd-hda-intel model=dell-headset-multi` `<6.6.8`, `rtc_cmos.use_acpi_alarm=1` `<6.8`, and Raphael `amdgpu.sg_display=0` only `6.2–<6.6`. | None is added: our profile minimum 6.8 exceeds those ranges, and the current release selects 7.3. The Raphael-specific setting is not inferred for Phoenix hardware. |
| Already present | Framework fwupd, CPU microcode, AMD KMS/Mesa, firmware, SSD fstrim, and preference for PPD over TLP. | Existing shared NixOS/Cybex configuration owns these; no duplicate daemon or CPU-policy override. |
| Deferred | Framework optional audio enhancement, the Omarchy AMD input-card profile switch, IIO sensor enablement, and Framework EC tooling/module. | Speaker chassis/card names and microphone routes need physical evidence. No `pactl` mutation, speaker retuning, extra EC module or forced sensor service is added. Packaged external modules are permitted in principle, but not needed for these fixes. |
| Deferred | ThinkPad generic ancestors' `acpi_backlight=native`, `psmouse.synaptics_intertouch=0`, TrackPoint settings and `amd_pstate=active`; conditional kernel upgrades for pre-5.2/5.8/5.16 systems. | Older ancestors are not proof those input quirks are needed on T14 Gen 5. Modern stock defaults handle P-state; PPD owns policy. No kernel replacement or global touchpad setting is copied. |

These are attributed equivalents, not a broad upstream import. Existing
personal modules can disable each workaround, retain EC wake, or supply a
personal `amdgpu.dcdebugmask` after disabling the profile PSR switch. Other
personal kernel parameters are merged and retained.

## Omarchy userspace and installation audit

All paths in this table are relative to the pinned
[Omarchy tree](https://github.com/basecamp/omarchy/tree/ac2690cd7be4f47e4a255f5e2e78d904d436b068).
The inventory starts from
[`install/hardware/all.sh`](https://github.com/basecamp/omarchy/blob/ac2690cd7be4f47e4a255f5e2e78d904d436b068/install/hardware/all.sh);
its leaf scripts, user scripts and matching helpers were inspected.

| Disposition | Scripts / fixes | Reason and Cybex equivalent |
| --- | --- | --- |
| Already present | `bluetooth.sh`, `network.sh`, `vulkan.sh`, `intel/sof-firmware.sh`, redistributable firmware, firmware update command | Existing Bluetooth, NetworkManager, graphics/Mesa and fwupd services. Nixpkgs [all-firmware.nix](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/nixos/modules/hardware/all-firmware.nix) includes SOF with redistributable firmware. No Arch package commands or competing network setup. |
| Already present for exact XPS | `dell-xps-touchpad-haptics.sh`, `intel/lpmd.sh`, `intel/thermald.sh`, `intel/video-acceleration.sh`, `speaker-tuning.sh` | Existing gated XPS haptic, thermal, Intel media, LPMd and speaker-filter services. Do not widen LPMd to every Intel CPU by model-number guess or overwrite speaker routing. Broader old Intel/GMA video support is deferred pending component evidence. |
| Already upstream / intentionally omitted | `intel/fred.sh`, `intel/fix-wifi7-eht.sh`, `dell-xps13-ptl-speaker-firmware.sh`, `dell-xps13-sidecar-amps.sh` | Existing laptop research records FRED default since 7.1, updated BE211 firmware, shipped Cirrus aliases and in-kernel sidecar selection. Do not disable Wi-Fi 7 globally or replace firmware with another speaker variant. Existing 0E54 codec fallback remains bounded `<7.4`. |
| Already present with stricter policy | `nvidia.sh` and `omarchy-hw-nvidia*` | Cybex selects from exact **packaged** GPU metadata, requires one branch supporting every display GPU, and preserves NVIDIA/PRIME options and the prebuilt guard. No vendor-substring selection or Omarchy driver-version pin. |
| Already present, still blocked | `intel/ipu7-camera.sh` | Existing exact XPS component gate and ABI guard remain authoritative. A camera package being installable is not working camera capture. No ABI bypass, HM1092 kernel revert or invented success. |
| Deferred | ASUS `fix-asus-ptl-display-backlight.sh`, `fix-asus-ptl-b9406-display.sh`, `fix-asus-ptl-b9406-touchpad.sh`, `fix-z13-touchpad.sh`; `asus-rog.sh`; user ASUS mixer/mic scripts | Useful exact-device leads (B9406 Pixart `093a:4f05`; GZ302 keyboard `0b05:1a30`), but no Cybex target inventory or test evidence. Do not turn these into generic ASUS quirks or clear personal WirePlumber routes. |
| Deferred | Lenovo `fix-yoga-pro7-bass-speakers.sh`; user Framework `fix-f13-amd-audio-input.sh` | A Yoga 9i codec pin model copied onto another laptop and a global “Family 17h/19h” card match need exact codec/UCM validation. Do not force an audio profile based on CPU-family labels. |
| Deferred | `framework16.sh`, `framework/qmk-hid.sh` | Framework 16 keyboard RGB/QMK access is a different model/peripheral from Framework 13 7040. No broad unprivileged HID rule added. |
| Deferred | `fix-elgato-camlink-4k.sh` | Replacing a user's raw USB camera with a loopback pipeline is an optional peripheral behavior, requiring exact device/format and runtime tests. Not a laptop-enablement prerequisite. |
| Deferred | `surface.sh`, `fix-surface-keyboard.sh` | Some stock Surface input/Marvell support can work, but selecting initrd modules from the current host's loaded modules is not evidence of target support. No whole Surface family is labelled supported. Patched linux-surface is rejected separately. |
| Deferred | `fix-tuxedo-backlight.sh` | Broad TUXEDO/Slimbook matching plus an extra driver and competing-module removal needs exact-model evidence. Do not delete another operator's modules or disable compatibility checks. |
| Already upstream | `fix-yt6801-ethernet-adapter.sh` | Omarchy itself now uses in-tree `dwmac-motorcomm`, with no fresh DKMS fallback. Cybex retains stock drivers; no migration/removal logic. |
| Deferred / personal preference | `fix-fkeys.sh`, `fix-synaptic-touchpad.sh`, user `fix-nouveau-cursor.sh`, `dell/xps13-text-scaling.sh`, `vm-no-animations.sh`, global USB autosuspend setting | No forced F-key mode, generic Synaptics transport override, compositor cursor policy, text size, animations or global USB change without exact need. Existing personal desktop/input preferences remain untouched. |
| Deferred | `set-wireless-regdom.sh` | Regulatory database already present. A timezone is not a reliable current radio country; no guessed domain or live radio mutation. |
| Rejected, security | `fix-bcm43xx.sh` | `broadcom-wl-dkms` is not an acceptable generic fallback: the pinned [Broadcom STA package](https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/pkgs/os-specific/linux/broadcom-sta/default.nix) lists CVE-2019-9501/9502. Keep stock drivers/redistributable firmware and disclose unsupported radios; no insecure-package allowance. |
| Rejected, outside scope/security | `apple/*`, Apple-specific `pacman.sh`; `qualcomm/*`, `gb10/*`, `n1x.sh`, `fix-n1x-gpu-memory.sh`, `nvidia/dgx-spark-boot.sh`, ASUS H7407BA speaker package, Lenovo Yoga Slim 7x/T14s Gen 6 camera | Apple and ARM/NVIDIA N1x/Snapdragon/GB10 are outside this image. No unsigned `SigLevel=Never` repository, device tree, bootloader change or custom platform kernel. T14s Gen 6 21N1/21N2 is not the AMD T14 Gen 5. |
| Not imported | `pacman.sh`, `platform-setup.sh`, `nvidia-apps.sh`, provision/first-boot/boot-rebuild dispatch | Distribution packaging and mutable provisioning are not NixOS hardware fixes. Preserve existing NixOS fresh-install and staged-update paths. |

## Omarchy x86 kernel patch audit

The independently pinned package
[`linux-omarchy/PKGBUILD`](https://github.com/omacom/omarchy-pkgs/blob/d9b1747fae3a664a74255d94f0c9a7b05b12850d/pkgbuilds/linux-omarchy/PKGBUILD)
uses Linux **7.2.15**, BORE and ADIOS, with 188 patch files. Its patch set is
not a checklist of gaps in Nixpkgs **7.3**. Every patch is rejected **as a
patch import**, even if technically desirable; matching stock-kernel settings
are assessed separately. Generic backport bundles are not asserted missing or
already merged without individual commit comparison. The numbered families
below cover the entire recipe (including non-hardware/performance changes).

| Recipe patch family | Decision |
| --- | --- |
| `0010–0147` Arch base, O3, BORE, TLB/preemption, scheduler/cluster/NOHZ changes; `0150` ADIOS | Reject custom kernel/performance policy. No demonstrated model requirement and no permitted stock configuration equivalent. |
| `0210–0297` PM updates, Zen5 TLB, zsmalloc/MGLRU/KSM/MM, Zstd/BMI2/crypto, AF_ALG restrictions, EFI lockdown/platform keyring | Reject patch/config rebuild. Security fixes remain the selected Nixpkgs kernel's responsibility; never turn off Secure Boot/lockdown or relax signature policy to claim hardware support. |
| `0300–0360` Btrfs/FUSE/VFS, EDID adaptive sync, GPU memory cgroups | Reject patch import. Keep stock filesystem/graphics behavior; no speculative configuration substitute. |
| `0400–0443` Intel ALPM, PSR/Panel Replay, XPS 13/14/16 exact subsystem quirks, stolen framebuffers, DSB/FBC/Xe3 bandwidth | Existing XPS stock parameters reproduce selected display behavior with documented power cost, not complete patch parity. XPS 14 PSR/LOBF remains exact panel/SKU only. Remaining driver changes require an upstream kernel, not a fork or broad disablement. |
| `0450–0481` AMD HDMI VRR/ALLM/FRL/VTEM, DSC, user queues, OLED brightness, SDP/replay, YCbCr, PCON and DCN buffer changes | Reject patches; defer absent upstream stock support. No broad AMD/HDMI/VRR workaround inferred from one panel or adapter. |
| `0510–0532` Sound/ASoC/SoundWire bundles, RT766, ASUS G733ZW, Acer A314-23P, XPS SOF/sidecar IDs, ACP7x sleep, Behringer USB audio | XPS 0E54's existing codec fallback is bounded `<7.4`; linux-firmware supplies model tuning. Remaining fixes stay with upstream stock kernels; do not reroute unrelated codecs or add custom kernel configuration. Apple CS420x quirk is outside scope. |
| `0541–0552` CVS IDs/GPIO/sensor-node ordering, laptop camera bridges/orientations, IMX471 power/gain, IPU7 cleanup, USBIO reset-resume, HM1092 revert | Existing XPS CVS load order avoids the shared speaker GPIO contention without claiming camera functionality. Reject HM1092 revert and other driver patches. Camera remains explicitly blocked; no generic ACPI override or ABI-signature expansion. |
| `0560–0572` Input/HID bundles, ASUS I2C timing and report/worker fixes, Magic Mouse null dereference | Reject kernel patches; input defects without a source-backed stock userspace equivalent are deferred. No global HID/I2C timing change. |
| `0601–0620` Thunderbolt/USB/xHCI, tunnel rescan, UCSI silent completion/early CCI poll, USB strings | Reject kernel patches; XPS USB-C stalls and dock/sleep limits are disclosed. No userspace reset/unbind that can hang a controller. |
| `0660–0681` MT7922 USB ID, iwlwifi dead firmware, btintel PCIe reset/D-state/cache/PM/parser, Broadcom D3/4-way-handshake | Reject patches; current stock radio support/firmware is authoritative. No broad Wi-Fi 7 disablement, insecure STA or controller cycling. |
| `0700–0713` PCI speed, JMB585 DMA, Intel VMD enumeration/IDs/flushes, Toshiba AHCI alias, DG1 reset, AMD IOMMU/perfopt | Reject patches; preserve DMA isolation and stock hardware discovery. Existing XPS `intel_iommu=on` is independently documented; do not disable IOMMU or firmware security. |
| `0740–0808` hwmon/platform bundles, Acer/Casper power resources, Dell GPIO polarity, Razer lid, s2idle GPE, PMF teardown, battery hooks, Chrome USBPD, MSI backlight, AMD SFH tablet mode | Reject driver patches and custom configs. Existing ZBook Smart PC opt-out remains reversible; new ThinkPad EC wake parameter comes from exact nixos-hardware evidence, not a global PM substitute. Apple SMC is outside scope. |
| `0850–0863`, `8204–8225` futex ABI, module/ftrace, MM compaction/hints, Xe reclaim/shrinker/hibernation/VM changes | Reject kernel patching/performance fork. No stock configuration can faithfully emulate these implementation changes. |

## Wider nixos-hardware policy screen

The screen found 24 files mentioning `kernelPatches`, 105 mentioning
`boot.kernelPackages` (including read-only references), 12 mentioning
`structuredExtraConfig`, 12 mentioning `nixpkgs.overlays`, and 25 mentioning
`boot.loader.` across the full snapshot. These counts include out-of-scope
architectures and tests; they are review leads, not defect counts. No
`allowInsecure` or `permittedInsecure` setting appeared. Findings relevant to
our PC scope:

| Family / source | Disposition |
| --- | --- |
| Microsoft Surface common kernel | Reject broad import: explicitly builds linux-surface 6.19.8 with a pinned downstream patch set. Generic Surface stock features are not equivalent to that support claim. |
| Dell XPS 17 9700 common | Reject `boot.kernelPatches` with `extraConfig` for SoundWire. Firmware/thermald already exist; older-model configuration is not evidence for DA14260/DA16260/DX13260. |
| ASUS ProArt PX13 HN7306EAC | Its module says TAS2783 patches are merged at ≥7.2 and firmware at ≥20260519. Those components are already newer at our pin. Deferred model profile: remaining UCM overrides, hard-coded sound-card addresses, mixer changes and no-suspend rules need target inventory and physical audio tests. No old patch/firmware backport imported. |
| Lenovo X1 Extreme Gen 2 | Reject Bumblebee package overlay and broad old Xorg/virtual-output assumptions. Existing device-based NVIDIA generation selection and explicit PRIME remain authoritative. |
| Common CPU/GPU/Wi-Fi minimum-kernel selections, Raphael scatter/gather quirk, Intel/AMD generations | Usually obsolete gates on the current stock 7.3 pin, not permission to select another package set. Read version conditions before copying any workaround. |
| Common laptop TLP, model TuneD/TLP settings, GPD Win 2 boot graphics, older Dell boot settings | Do not import profile ancestry that can choose power/boot behavior. Preserve PPD ownership and current bootloader. |
| Other ASUS, Lenovo, Dell, HP, Acer, MSI, GPD, Clevo/TUXEDO and desktop entries | Deferred exact-model expansion. The tree supplies useful leads but not a universal brand profile or proof of component identity. Prioritize exact inventories and reproducible faults before adding settings. |
| Apple, SBC/ARM/RISC-V, vendor BSP kernels and board boot images | Outside scope; no import or support claim. |

## Validation and remaining work

The dedicated Python fixtures exercise every approved identity; Dell model/SKU
cross-products; Framework siblings and near matches; ThinkPad P14s/T14s and
malformed MTMs; ZBook regional SKU/board mismatch; Apple/ARM/BIOS/CPU exclusions;
malformed/injected/ambiguous catalogues; numeric kernel bounds; and refusal to
manufacture qualification. They also guard module ownership boundaries.

The small [Nix evaluation check](../nix/tests/hardware-profiles.nix) evaluates
every profile, tests opt-outs and retained personal kernel parameters, rejects
unknown IDs and an older stock kernel for XPS, checks live metadata, and
compares kernel derivation, kernel patches, overlays, external modules,
bootloader and PPD/TLP/TuneD settings with the baseline. Building it produces
only a text evidence derivation, not a kernel or system.

Integration adds regression coverage for generic custom-kernel rejection, the
existing `Dell XPS 14 DA14260` identity, real-catalogue detection through
inventory, retained XPS component choices and camera exclusion, and detected
versus configured profiles. Diagnostics distinguish the running kernel from
configuration metadata and recognize existing XPS/ZBook declarations.

The combined `nix develop -c tests/run` passed: 1,083 discovered Python tests,
1,681 JavaScript tests (18 skipped), and the additional helper/runtime suites.
`nix flake check --no-build` passed, including all profile/kernel-policy and
installation-parity evaluations. `scripts/check-prebuilt` passed against the
Git-filtered Nix source snapshot; a direct path evaluation encountered an
unrelated unreadable ignored build directory in the working checkout. The
audit found no unexpected Nixpkgs compilation and checked all eight pointer
theme cache downloads.

Nix builds passed for `desktop`, `updater`, `installer-ui`, the `kernel-policy`,
`hardware-profiles` and `parity` reports, and complete generic `system` and
`xps-system` configurations. The stock Linux 7.3 kernel was fetched from the
NixOS cache; no kernel or experimental camera stack was compiled. These
outputs were built without activating them or starting their services.

No ISO, physical machine, installation VM, service restart, firmware update,
suspend or staged updater run was performed for this work. All models still
need the physical installation/device/sleep/update checklist in
[hardware support](hardware-support.md). In particular, the XPS built-in camera
is an accepted missing feature here, not evidence of full support.
