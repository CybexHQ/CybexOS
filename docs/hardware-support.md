# Hardware support and qualification

Cybex OS targets fresh installations on Intel and AMD x86-64 UEFI PCs, with
broad Linux drivers and stock prebuilt Nixpkgs kernels. Hardware support never
requires a kernel fork, patch, custom configuration or package-set overlay.
Ordinary packaged external modules, such as NVIDIA, remain supported. Physical
hardware compatibility remains under qualification. Inclusion of a driver is
not a passing test for every chipset or computer sold under that brand. Apple
computers (including Intel Macs), ARM, 32-bit x86 and legacy BIOS installations
do not have a supported image.

The [beta.25 audit](hardware-compatibility.md) records the original findings.
The compatibility implementation adds early Intel **and** AMD microcode to the
live image, expands early wired PXE drivers, selects NVIDIA drivers by the
exact packaged support metadata, and adds shared read-only hardware assessment
to the graphical installer, terminal installer and inventory command. It does
not change the machine-owned hardware configuration or personal update inputs.

## What the installer checks

- CPU microcode, kernel and redistributable firmware come from the machine's
  selected Nixpkgs. Both CPU vendors use the same image; there is no separate
  Intel or AMD installation path.
- The PXE initrd includes Intel `e1000/e1000e/igb/igc/ixgbe/i40e/ice`, Realtek
  `r8169/r8152`, Broadcom `tg3/bnx2/bnx2x`, Aquantia `atlantic`, Mellanox
  `mlx4_en/mlx5_core`, and common ASIX/CDC/RNDIS USB Ethernet drivers, alongside
  upstream virtual NICs. Their presence is checked during configuration parity.
  This does not qualify physical PXE or configure Wi-Fi PXE.
- NVIDIA detection considers PCI display devices only. A compact support
  catalogue is extracted at build time from the selected kernel set's stable
  open-module driver and proprietary `legacy_580` driver. Historical entries
  marked for another legacy branch are excluded; subsystem restrictions and
  newer open-only devices are respected. All detected NVIDIA GPUs must share
  a supported branch. The installer recommends open where supported, otherwise
  closed 580. Unsupported combinations and incompatible manual choices stop
  before erasure, independently of the UI. Proprietary application selection
  does not control this necessary driver selection.
- A network adapter without a bound driver or interface produces an advisory
  with its PCI/USB identity. Another working adapter may provide internet.
  Failed firmware requests are collected when kernel logs are readable, but
  optional firmware fallback is not treated as a failure by itself. A loaded
  driver or an installer framebuffer is not a desktop compatibility pass.

## Profile status

`cybex hardware`, `cybex doctor`, and both installers show the matched profile,
support status and known limitations. Installers show these before erasing a
disk. `experimental` means an approved configuration exists but physical
qualification is incomplete; `generic` means no approved model match;
`unsupported` means the profile or platform falls outside the supported scope.
`qualified` requires a real qualification record for the exact tested tuple.
Detection, a loaded driver and a successful build never imply a feature pass.
An unknown PC can continue with generic, unqualified support; existing critical
driver and platform checks still apply.

Fresh installations record `cybexos.hardware.profile` for a matched approved
profile, alongside the existing exact XPS/ZBook and graphics choices. Installed
support metadata lives at `/etc/cybexos/hardware-support.json`; the existing
`hardware-profile.json` continues to describe configured laptop fixes. Inventory
compares the detected profile with those declarations and reports the running
kernel separately from the configured kernel. System Check suggests reviewing
an available or mismatched profile through personal configuration and
`cybex update local`; it does not enable settings automatically. A configured
profile does not prove that the booted hardware behaves as expected.
This does not migrate an installed machine or rewrite personal modules,
explicit camera settings or machine-owned locks.

For an existing Framework 13 AMD 7040 or ThinkPad T14 Gen 5 AMD, review the
detected ID in `cybex hardware` before setting `cybexos.hardware.profile` in
your personal NixOS module. Prepare the change with `cybex update local`,
review the candidate, and use the normal trial boot and confirmation. The
available profile is not enabled by a source update alone.

The Framework profile disables panel self-refresh and gives its Ethernet
expansion card a longer autosuspend delay. The ThinkPad profile disables
embedded-controller wake to address reported sleep battery drain. Each change
has an opt-out under `cybexos.hardware`: `framework13Amd7040.disablePsr`,
`framework13Amd7040.ethernetAutosuspend`, and
`thinkpadT14Gen5Amd.preventEcWakeup`. Set the relevant option to `false` when
testing a fix or retaining a personal setting. Keep the existing power manager
and stock kernel. See the [upstream audit](hardware-research.md) for evidence,
exact model identities, tradeoffs and removal conditions.

## Current support levels

| Area | Status and limits |
| --- | --- |
| Intel/AMD CPU, chipsets, SATA/NVMe, USB and virtual devices | Broad in-tree coverage and both microcode families included. Exact boards, firmware and physical installations require the matrix below. |
| Intel/AMD graphics | In-tree `i915/xe/amdgpu/radeon` and Mesa; installed rendering, external displays and sleep need physical qualification. The X1 Pro 370 graphics/input reports are explicit regression targets. |
| NVIDIA desktop and hybrid graphics | Device-based driver selection and simple PRIME offload (one NVIDIA plus one Intel/AMD display GPU in PCI domain zero). Driver builds and selection fixtures do not qualify physical rendering, suspend or complex multi-GPU topologies. Unsupported Kepler/Fermi generations are blocked. |
| Ethernet and Intel/Qualcomm/MediaTek/Realtek Wi-Fi | Broad in-tree drivers and redistributable firmware. Exact PCI/USB IDs, firmware, bands and connection methods need physical qualification. Unbound vendor-specific USB Wi-Fi may appear only in the USB inventory; it cannot be classified reliably from its USB class alone. |
| Broadcom Wi-Fi | Device-specific `brcmfmac/brcmsmac` coverage. `b43` firmware is nonredistributable and absent. Broadcom STA is marked insecure in the pinned Nixpkgs (CVE-2019-9501/9502, possible remote code execution); it is not enabled and insecure-package policy is not relaxed. Use a supported USB Ethernet adapter or USB tethering when required. |
| Disks and firmware RAID | Guided installation accepts whole `sd*`, `vd*`, `nvme*n*` and eMMC/SD (`mmcblk*`) disks of at least 64 GiB with no active mappings/mounts/swap. The review and the erase check the same disk by its serial number, else its WWN, else its kernel device path and size (most virtual disks have no serial). It erases the disk and reserves a 16 GiB ESP. Firmware RAID/RST, dual boot and partition-preserving installations are not qualified targets. |
| Secure Boot | Not supported yet. The installation medium is unsigned, so firmware with Secure Boot on refuses to start it, and the installer stops before erasure while Secure Boot is on. Firmware verification must not be disabled to bypass this limitation. Signed media, owner key enrollment and module signing are still to be completed and qualified. |
| Exact Dell XPS IPU7 camera | Built-in camera unsupported pending standard upstream support. Fresh installation leaves the experimental camera stack off and uses the stock prebuilt kernel; use a USB webcam. Existing explicitly selected machine-owned camera settings are preserved. A profile match does not qualify camera capture. |
| Audio, Bluetooth, input, cameras, sleep and docks | Generic Linux support is included. Model-specific routing, haptics, MIPI cameras, fingerprints, suspend and hotplug require physical tests. |
| Matched laptops | Experimental profiles cover Framework 13 AMD 7040 and ThinkPad T14 Gen 5 AMD (21MC/21MD), alongside Dell XPS 13 DX13260 (0E53/0E54), XPS 14 DA14260 (0DB9), XPS 16 DA16260 (0DBA) and HP ZBook Ultra G1a (board 8D01). All use the stock kernel; see [matched laptops](laptop-support.md) for each quirk, the BIOS settings they need and what still waits for a newer kernel. |

Internet access to the release/cache is required. A bundled desktop payload
does not remove the network prerequisite. Enterprise Wi-Fi certificates,
captive portals, restricted DNS and real radios are not covered by the earlier
simulated WPA2/WPA3 tests. See [hardware/security blockers](hardware-security.md).

## Collecting a physical qualification record

Use one frozen ISO/source revision for the matrix. On the live image and again
on the installed machine, run:

```console
cybex hardware > hardware-live.json
cybex hardware > hardware-installed.json
```

Run the second command after installation and save the files separately. The
command reads sysfs, release metadata and available kernel firmware diagnostics.
It does not install drivers, reconfigure networking, capture camera images,
flash firmware, suspend, reboot or write to disks. Root can read kernel
diagnostics that a normal user cannot; `firmwareLogAvailable: false` means the
log was unavailable, not that no firmware failures occurred. Serial numbers,
MAC/IP addresses, SSIDs and raw kernel logs are omitted. Device IDs, model,
BIOS/firmware version, kernel, detected profile/status/limits and exact release
revision/NAR identity are included. The independently locked machine Nixpkgs
revision/NAR identity is included when readable; an empty identity means it was
not available, never a guessed revision. Installation evidence also records
the source-tested Nixpkgs identity and the complete hardware assessment.

Every checklist entry starts at **not-run**. In a separate reviewed record,
record the exact Cybex OS revision/NAR identity, Nixpkgs revision/NAR identity,
stock kernel version, detected and configured profile IDs, model/SKU/board and
BIOS version/date. Keep this tuple with the ISO filename/SHA-256, boot method,
each check's observed result, test procedure and unresolved errors. Mark
inapplicable checks with a reason.
Do not turn inventory facts into passes. Use only disposable or explicitly
authorized target disks. Firmware changes and real-machine restarts require
the owner's authorization.

| Required representative machine | Qualification focus |
| --- | --- |
| Older UEFI Intel laptop + Intel Wi-Fi | `i915`, SATA, keyboard/touchpad, audio, battery and sleep |
| Recent Intel laptop | `xe`, NVMe/VMD exposure, SOF, modern Wi-Fi |
| AMD Ryzen desktop | Chipset/USB, Radeon, NVMe/SATA, Realtek 2.5 GbE |
| AMD laptop / Minisforum X1 Pro 370 | Radeon graphics and installer latency regressions, Wi-Fi, suspend |
| NVIDIA desktop and hybrid laptop | Supported newer open branch, Pascal closed 580, PRIME, displays, resume |
| Broadcom x86 laptop | Exact radio/firmware requirement and usable alternative networking |
| USB-C dock/adapters | Realtek/ASIX Ethernet, USB Wi-Fi, display/audio/input hotplug |
| Exact XPS SKU 0DB9/0DBA/0E53/0E54 | Panel, haptics, speakers (XPS 14/16 amplifier probe with CVS; XPS 13 codec path), thermals, sleep and unsupported built-in IPU7 camera |
| HP ZBook Ultra G1a (board 8D01) | OLED/IPS panel, speakers and microphones, ISP4 camera, MT7925 Wi-Fi/Bluetooth after s2idle, PMF profiles, BIOS settings |

For each applicable machine exercise USB boot and physical PXE; network
authentication and HTTPS; disk visibility; encrypted fresh installation;
unlock/password fallback and login; desktop rendering; audio/input/Bluetooth;
repeated suspend/resume; external displays and docks; camera capture/privacy;
and the actual staged updater, trial boot, confirmation and rollback. Keep
password/keyring, firewall and personal data preservation checks in scope.
Secure Boot and the IPU7 camera cannot pass until their existing blockers are
resolved. VM installation/lifecycle evidence belongs in its own record and
does not populate this physical matrix.
