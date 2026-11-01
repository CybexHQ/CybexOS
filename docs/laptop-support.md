# Matched laptops: Dell XPS 2026 and HP ZBook Ultra G1a

Cybex OS runs these laptops on the stock Nixpkgs kernel (Linux 7.3,
`linuxPackages_latest`), linux-firmware and Mesa. It never ships a patched
kernel. Where an upstream fix has not reached that kernel, the matched profile
uses a stock-kernel equivalent: a parameter, a module option, a load order or
a userspace service. It also records what only a newer kernel can fix.

The installer detects each model and writes its profile into the new
machine's `/etc/nixos/machine.nix`. Every match is exact: no other laptop
receives these quirks.

- **XPS:** `cybexos.hardware.xps = { enable = true; sku = "…"; panel = "…"; camera = …; }`.
- **ZBook:** `cybexos.hardware.zbookUltraG1a.enable = true`.

A machine installed before its model was recognised can add the same line
itself. Nothing migrates it automatically.

None of this is physical qualification. The profiles are checked by unit tests,
configuration parity and system builds. Each laptop still needs the physical
checklist in [hardware support](hardware-support.md).

## Identification

| Model | Matched by | Platform |
| --- | --- | --- |
| Dell XPS 14 DA14260 | Dell, product `XPS 14`/`DA14260`, SKU `0DB9`, Core Ultra CPU | Panther Lake, Xe3 `8086:b080` |
| Dell XPS 16 DA16260 | Dell, product `XPS 16`/`DA16260`, SKU `0DBA`, Core Ultra CPU | Panther Lake |
| Dell XPS 13 DX13260 | Dell, product `DX13260`, SKU `0E54` | Panther Lake |
| Dell XPS 13 DX13260 | Dell, product `DX13260`, SKU `0E53` | Wildcat Lake |
| HP ZBook Ultra G1a 14" | vendor `HP`, board `8D01`, product `ZBook Ultra G1a` | AMD Ryzen AI Max (Strix Halo), Radeon 8040S–8060S |

The ZBook's product SKU is a regional order number (for example
`A3ZJ3ET#UUW`), so it is not matched. The NVIDIA N1x (Arm) XPS 16 is outside
the x86_64 image.

## Dell XPS 13, 14 and 16 (2026)

| Area | XPS 14 / 16 | XPS 13 |
| --- | --- | --- |
| Display | Panel Replay is off through the kernel's own quirk. On the measured XPS 14 LG OLED (EDID `30e4c607`): `xe.enable_psr=0`, with Link Off Between Frames off before the first modeset ([compatibility item 9](hardware-compatibility.md)). LG panels get `xe.enable_dpcd_backlight=1`. | Panther Lake: `xe.enable_psr=1 xe.enable_panel_replay=0` (PSR1 only). Wildcat Lake: `xe.enable_panel_replay=0`. |
| Speakers | `intel_cvs` does not autoload (see below). Cirrus CS35L57 firmware comes from linux-firmware. A PipeWire voicing filter and limiter, measured on the XPS 14 and shared by the XPS 16, follows the volume keys. | Sidecar CS35L56 amplifiers are chosen by the kernel's own subsystem quirk. On `0E54`, until Linux 7.4: `snd_soc_sof_sdw quirk=1` (see below). |
| Touchpad | Synaptics haptic daemon at the configured intensity, with its I2C controller kept awake. | The same daemon, started only when a Synaptics `VEN_06CB` touchpad is present. |
| Power | power-profiles-daemon, adaptive thermald, Intel LPMd with Intel's Panther Lake policy. | The same. Wildcat Lake (`0E53`) has no LPMd: the pinned LPMd has only Intel's Panther Lake policy. |
| Storage | `intel_iommu=on`, so a DRAM-less SSD gets its host memory buffer (below). | The same. |
| Media | intel-media-driver, VPL and the compute runtime. | The same. |
| Microphone mute light | `platform::micmute` follows the default microphone (all laptops, below). | The same. |
| Camera | Processed IPU7 stack, still blocked (below). | Not enabled; not reviewed for this model. |
| Wi-Fi | Intel BE211 with the stock driver and firmware, plus the wireless regulatory database (all machines). | Intel BE213 (Wildcat Lake), the same. |

### Why each XPS quirk exists

- **XPS 14/16 speakers and the camera share a GPIO.** The camera's vision
  chip driver, `intel_cvs`, requests the speaker-ID pin (`INTC10BC:01` pin 20)
  as its wake line. It autoloads at boot before SOF has probed the
  amplifiers, so all four fail with `-EBUSY: Failed to get spk-id-gpios`, and
  no sound card appears ([SOF #11152](https://github.com/thesofproject/sof/issues/11152)).
  - The amplifiers read and release that pin while probing. Cybex OS therefore
    blacklists `intel_cvs` from autoloading, and the camera initializer loads it
    explicitly once every amplifier on SoundWire has bound. It gives up after
    60 s rather than take the line from them.
  - Upstream, `intel_cvs` stops claiming the GPIO in
    [ed447e2b1da9](https://git.kernel.org/torvalds/c/ed447e2b1da9) (Linux 7.4).
    Its IRQ lookup then marks the shared pin active-low, which can skew the
    speaker IDs of amplifiers that probe later, so the load order stays.
- **XPS 13 Panther Lake speakers.** Linux 7.3 has the cs42l43 speaker-ID quirk
  for `0E53` only. On `0E54` the two sidecar amplifiers find no speaker ID,
  miss their firmware and stay silent.
  - The fix, [7da2aca12375](https://git.kernel.org/torvalds/c/7da2aca12375), is
    in Linux 7.4. 7.3.1 does not have it.
  - Until then, `snd_soc_sof_sdw quirk=1` drives the speakers from the
    codec's own amplifier: audible, with less bass. On the same symptom,
    [Omarchy #11228](https://github.com/omacom/omarchy/issues/11228) confirmed
    this on hardware.
  - Cybex OS never substitutes another speaker variant's amplifier tuning.
- **XPS SSD host memory buffer.** The firmware opts into DMA protection, so
  Linux turns the IOMMU on but maps internal devices 1:1. The XPS 14's
  DRAM-less SanDisk SN7100S asks for a 64 MiB host memory buffer, and the NVMe
  driver can then offer only eight 4 MiB pieces. Every boot and resume logs
  `nvme nvme0: failed to allocate host memory buffer`, and the drive runs
  without its cache.
  - `intel_iommu=on` translates DMA, which gives the buffer as one segment.
    It was verified across boot and s2idle on a DA14260
    ([Omarchy #16683](https://github.com/omacom/omarchy/issues/16683)).
  - It applies to every XPS profile, which share the SSD options.
- **XPS 13 display.** Dell's kernel quirks are not upstream:
  - On Panther Lake they keep PSR1 only.
  - On Wildcat Lake they make Panel Replay exit on every update. Upstream's
    Panel Replay delivers about 40 % of scrolled frames late
    ([drm/xe #8930](https://gitlab.freedesktop.org/drm/xe/kernel/-/work_items/8930)).
  - The parameters reproduce these without a patched kernel, at some idle power
    cost. Both are display-wide: Panel Replay is also off on external
    DisplayPort 2 monitors. If Wildcat Lake still shows DSB or selective-fetch
    errors, add `xe.enable_psr=1`.
- **Not carried over from Omarchy:**
  - `fred=on` — FRED is on by default since Linux 7.1.
  - `iwlwifi disable_11be=Y` — the BE211 Wi-Fi 7 collapse was a firmware bug,
    fixed in the firmware linux-firmware now ships.
  - Omarchy's Cirrus firmware alias package — linux-firmware 20261019 has
    every `10280e54` file.
  - Its sidecar-amplifier module option — 7.3 selects the sidecar amplifiers
    by subsystem ID.

### XPS limits that need the laptop or a newer kernel

- **Camera.** The processed camera stays fail-closed for two reasons:
  - The IPU7 PSYS private-ABI guard rejects Linux 7.3's layout
    ([hardware security](hardware-security.md)).
  - Linux 7.3's ipu-bridge lists the Himax HM1092 IR sensor (`HIMX1092`), which
    has no driver. The ISYS sensor graph therefore never completes, and the
    OV08X40 colour sensor gets no subdevice.

  Omarchy reverts that entry in its kernel. A stock-kernel fix needs an
  out-of-tree HM1092 driver or an ACPI override built from this laptop's own
  tables. Both, like extending the ABI signature, need real frames from
  `xps-ipu7-camera-frame-check` on the laptop before they can ship.

  Linux 7.4 also makes the ipu6 driver claim IPU7 by default, so revisit the
  camera stack when 7.4 arrives.
- **Panel Replay power saving.** Omarchy patches Panel Replay to exit on each
  update instead of switching it off.
- **USB-C power-delivery commands** can wait 10 s when the EC completes a
  command without notifying (Omarchy's UCSI polling patch).
- **Intel Bluetooth after sleep.** btintel PCIe sleep fixes are in Linux 7.4.
  Rebinding the controller after resume is not shipped as a workaround: its
  failure mode has not been seen on these laptops, and unbinding a hung
  controller can hang the kernel.
- **The camera's USB bridge after sleep** (Omarchy's USBIO reset-resume patch)
  loses its GPIO setup across a USB reset. A USB reset-resume quirk would
  re-probe the bridge under its consumers instead, so this waits for the kernel.
- **LPMd on the XPS 13 Wildcat Lake.** Intel's Wildcat Lake policy exists only
  in LPMd's current development line, which also rewrites the Panther Lake
  policy. It needs a measured update on the laptops, not a silent version bump.
- **XPS 16 OLED.** It shares the XPS 14's panel controller, but its PSR
  behaviour has not been measured. Add its EDID to the PSR/LOBF quirk only after
  measuring it.

## HP ZBook Ultra G1a

Omarchy has no code for this laptop. It runs on generic Strix Halo support, as
here. On Linux 7.3 with linux-firmware 20261019:

| Area | Status |
| --- | --- |
| Display and GPU | `amdgpu` (DCN 3.5.1, GC 11.5.1) loads in the initrd with its firmware. The panel is either a 2880×1800 120 Hz OLED (touch, PSR-SU) or a 1920×1200 IPS. |
| Speakers | Realtek ALC245 with four CS35L54 amplifiers. The kernel finds them through ACPI, and linux-firmware has the `cs35l54-b0-dsp1-misc-103c8d01` tuning. |
| Microphones | ACP 7.0 PDM array; alsa-ucm-conf adds it as the digital microphone. |
| Camera | OV05C10 through the in-tree AMD ISP4 driver (since Linux 7.2), using `amdgpu/isp_4_1_1.bin`. PipeWire uses it directly through V4L2. It must be enabled in the BIOS. |
| Wi-Fi / Bluetooth | MediaTek MT7925 (`14c3:7925`) and its USB Bluetooth, plus the wireless regulatory database for 6 GHz. |
| Fingerprint, touchpad | Synaptics `06cb:0106` (libfprint) with fprintd; I2C-HID touchpad and, on OLED models, an ELAN touchscreen. |
| Power | amd-pmf and hp-wmi platform profiles through power-profiles-daemon; s2idle only. |
| NPU | `amdxdna` binds (NPU5 firmware is present). Nixpkgs has no XRT userspace to use it. |

The profile turns off amd-pmf's **Smart PC** policies
(`amd_pmf smart_pc_support=0`):

- On BIOS 01.05.07 and later, the policy engine fails after s2idle and logs
  `TEE enact cmd failed` every second.
- Linux 7.3 reinitialises the engine after hibernation, not after s2idle.
- The static power slider and power profiles keep working without it.
- To keep the BIOS policies, set `cybexos.hardware.zbookUltraG1a.smartPc = true`.

### BIOS settings this model depends on

- **Pluton on.** Without it, firmware lacks `MSFT0201` and s2idle resume fails.
  It is under the BIOS security settings.
- **Camera on** for the camera to appear at all.
- **A current BIOS** (fwupd offers updates through LVFS). 01.04.03 and
  01.04.05 can freeze at boot.
- **Battery Health Manager.** Charge limits are a BIOS setting ("Maximize my
  battery health", about 80 %); Linux has no charge-threshold interface for
  this model.
- **Fans** are EC-controlled; Linux has no fan control.

### ZBook items not configured, and why

- **Chromium-family browser hangs on Strix Halo** (an SMU deadlock started by
  the video processing engine,
  [drm/amd 5171](https://gitlab.freedesktop.org/drm/amd/-/work_items/5171)) are
  fixed in Linux 7.3 by `a8b749c5c5af` ("drm/amdgpu/vpe: Force collaborate
  sync after TRAP"), so the reported workarounds (VA-API off, VPE disabled
  with `amdgpu.ip_block_mask`) are not needed.
- **OLED flicker** has no report on this panel. If it appears, the
  `amdgpu.dcdebugmask` values for Replay (`0x400`) and PSR (`0x10`) can be
  tested.
- **GPU memory for local models.** BIOS UMA and `ttm.pages_limit` are a
  per-user workload choice, not a default.
- **NFC** (NXP `NXP8013`) and the **IR camera** have no Linux driver.
- **MT7925 resume and Bluetooth reset fixes** landed after Linux 7.3 and arrive
  with a later kernel.

## Every laptop: microphone mute light

Laptop drivers light their microphone-mute LED (`platform::micmute` on Dell,
`hda::micmute` on HP) from an ALSA capture switch. The SoundWire and AMD ACP
digital microphones these laptops use have none: PipeWire mutes them in
software, so the light never changed.

The `micmute-led` user service, `cybexos-micmute-led`, starts on every
installed machine that has a `*::micmute` LED:

- It follows the default microphone's mute state, from the key, the Sound
  drawer or any other control.
- It sets the LED through logind's `SetBrightness`, which lets the
  foreground session's owner change LEDs without root.

Omarchy instead flips the matching ALSA capture switch from its mute key.

## cybex doctor

The system check's `laptop` entry ([system check](system-check.md)) reads the
same identification:

- **No profile.** A recognised laptop without its profile gets a suggestion
  naming the exact line to add.
- **XPS 14/16.** It reports speaker amplifiers that did not start.
- **ZBook Ultra G1a.** It reports Pluton turned off and the BIOS releases that
  freeze. A camera turned off in the BIOS is a note, not a problem.
- **XPS 13 Panther Lake.** A note says when the speakers are on the codec's own
  amplifier path.

The installed profile is recorded in `/etc/cybexos/hardware-profile.json`.

## Sources

- Omarchy, read on 2026-11-01:
  - [omacom/omarchy](https://github.com/omacom/omarchy) `quattro` at `7eedd17`;
  - [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) at `9e1b0d6`, including the `linux-omarchy` 7.2.14 patch set;
  - the patch numbers named above.
- Linux 7.3 source (`linux-7.3.tar.xz`, Nixpkgs `31ecbaca`) and the 7.3.1 changelog.
- Code references: `drivers/media/i2c/cvs/core.c`, `sound/soc/codecs/cs35l56-shared.c`,
  `drivers/spi/spi-cs42l43.c`, `sound/soc/intel/boards/sof_sdw.c`,
  `drivers/platform/x86/amd/pmf/core.c`.
- The linux-firmware 20261019 tree in Nixpkgs, checked for the files above.
- ZBook identification and logs:
  - [a public boot log](https://github.com/lfrancke/amd-pmf-hibernate);
  - [linux-hardware.org probes](https://linux-hardware.org/?probe=134ee0d587);
  - the [HP forum report](https://h30434.www3.hp.com/t5/Business-Notebooks/HP-ZBook-Ultra-G1a-Issues-after-bios-upgrade-to-1-05-07/td-p/9664151)
    of the PMF error loop;
  - [Ubuntu certification 202507-37016](https://ubuntu.com/certified/202507-37016).
- ZBook Pluton and BIOS reports:
  - [the ISP4 driver thread](https://lkml.org/lkml/2025/11/21/1519) (Pluton and `MSFT0201`);
  - [HP ZBook Ultra G1a / EliteBook X G1a BIOS issues](https://gist.github.com/jeffnash/65073bcf920db181d4ca763a814f2fe5);
  - [kernel bug 221019](https://lkml.iu.edu/2601.3/06165.html) (the PMF error loop).
- XPS SSD host memory buffer: [Omarchy #16683](https://github.com/omacom/omarchy/issues/16683).
