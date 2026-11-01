# Hardware support and qualification

Cybex OS targets fresh installations on Intel and AMD x86-64 UEFI PCs, with
broad Linux drivers. Physical hardware compatibility remains under
qualification. Inclusion of a driver is not a passing test for every chipset
or computer sold under that brand. ARM, Apple Silicon, 32-bit x86 and legacy
BIOS installations do not have a supported image.

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

## Current support levels

| Area | Status and limits |
| --- | --- |
| Intel/AMD CPU, chipsets, SATA/NVMe, USB and virtual devices | Broad in-tree coverage and both microcode families included. Exact boards, firmware and physical installations require the matrix below. |
| Intel/AMD graphics | In-tree `i915/xe/amdgpu/radeon` and Mesa; installed rendering, external displays and sleep need physical qualification. The X1 Pro 370 graphics/input reports are explicit regression targets. |
| NVIDIA desktop and hybrid graphics | Device-based driver selection and simple PRIME offload (one NVIDIA plus one Intel/AMD display GPU in PCI domain zero). Driver builds and selection fixtures do not qualify physical rendering, suspend or complex multi-GPU topologies. Unsupported Kepler/Fermi generations are blocked. |
| Ethernet and Intel/Qualcomm/MediaTek/Realtek Wi-Fi | Broad in-tree drivers and redistributable firmware. Exact PCI/USB IDs, firmware, bands and connection methods need physical qualification. Unbound vendor-specific USB Wi-Fi may appear only in the USB inventory; it cannot be classified reliably from its USB class alone. |
| Broadcom Wi-Fi | Device-specific `brcmfmac/brcmsmac` coverage. `b43` firmware is nonredistributable and absent. Broadcom STA is marked insecure in the pinned Nixpkgs (CVE-2019-9501/9502, possible remote code execution); it is not enabled and insecure-package policy is not relaxed. Use a supported USB Ethernet adapter or USB tethering when required. |
| Disks and firmware RAID | Guided installation accepts whole `sd*`, `vd*`, `nvme*n*` and eMMC/SD (`mmcblk*`) disks of at least 64 GiB with no active mappings/mounts/swap. The review and the erase check the same disk by its serial number, else its WWN, else its kernel device path and size (most virtual disks have no serial). It erases the disk and reserves a 16 GiB ESP. Firmware RAID/RST, dual boot and partition-preserving installations are not qualified targets. |
| Secure Boot | Not supported yet. The installation medium is unsigned, so firmware with Secure Boot on refuses to start it, and the installer stops before erasure while Secure Boot is on. Turn Secure Boot off to install. Signed media, owner key enrollment and module signing are still to be completed and qualified. |
| Exact Dell XPS IPU7 camera | Known private-ABI blocker. The existing guard remains intact; camera initialization fails closed. Update health reports a blocked camera but never holds back or rolls back an update ([Recovery](recovery.md)). This machine is not qualified by omitting its camera or extending a signature without physical frames. |
| Audio, Bluetooth, input, cameras, sleep and docks | Generic Linux support is included. Model-specific routing, haptics, MIPI cameras, fingerprints, suspend and hotplug require physical tests. |
| Matched laptops | Dell XPS 13 DX13260 (0E53/0E54), XPS 14 DA14260 (0DB9), XPS 16 DA16260 (0DBA) and HP ZBook Ultra G1a (board 8D01) get exact-match profiles on the stock kernel; see [matched laptops](laptop-support.md) for each quirk, the BIOS settings they need and what still waits for a newer kernel. |

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
firmware version, kernel and exact release revision/NAR identity are included.

Every checklist entry starts at **not-run**. In a separate reviewed record,
record the ISO filename/SHA-256, boot method, each check's observed result,
test procedure and unresolved errors. Mark inapplicable checks with a reason.
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
| Exact XPS SKU 0DB9/0DBA/0E53/0E54 | Panel, haptics, speakers (XPS 14/16 amplifier probe with CVS; XPS 13 codec path), thermals, sleep and processed camera blocker |
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
