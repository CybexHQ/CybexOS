"""Read-only hardware assessment shared by installation and qualification."""
import json
import os
from pathlib import Path
import re
import subprocess

from .common import Failure

CATALOGUE = Path('/etc/cybexos/hardware-drivers.json')
PCI_ADDRESS = re.compile(r'([0-9a-fA-F]{4}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})\.([0-7])')
CAMERA_LIMIT = 'Built-in IPU7 camera is unsupported pending standard upstream support. Use a USB webcam.'


def generic_support():
    return {'profileId': None, 'profileName': 'Generic PC', 'status': 'generic',
            'summary': 'No verified hardware profile. Compatibility needs testing on this computer.',
            'limitations': [], 'sources': []}


def hardware_support(sysroot=Path('/sys'), *, kernel=None, catalogue=None):
    """Consume the profile catalogue without making it an installation gate.

    Older/incomplete media and malformed catalogue results remain explicitly
    unqualified. Driver preflight still runs independently of this information.
    """
    fallback = generic_support()
    try:
        from .hardware_profiles import support_for
        value = support_for(Path(sysroot), kernel=kernel, catalogue=catalogue)
        if (not isinstance(value, dict)
                or not (value.get('profileId') is None or isinstance(value.get('profileId'), str) and value['profileId'])
                or not isinstance(value.get('profileName'), str) or not value['profileName']
                or value.get('status') not in ('experimental', 'generic', 'unsupported', 'qualified')
                or not isinstance(value.get('summary'), str)
                or not isinstance(value.get('limitations'), list)
                or not all(isinstance(item, str) for item in value['limitations'])
                or not isinstance(value.get('sources'), list)
                or not all(isinstance(item, dict) for item in value['sources'])):
            return fallback
        # Copy lists: adding observed limitations must not mutate the catalogue.
        return dict(value, limitations=list(value['limitations']), sources=list(value['sources']))
    except (ImportError, OSError, ValueError, TypeError, KeyError):
        return fallback


def support_lines(hardware):
    """Short terminal copy; JSON consumers keep the complete structured record."""
    support = hardware.get('support') or generic_support()
    identity = support['profileName']
    if support.get('profileId'):
        identity += ' (' + support['profileId'] + ')'
    return [f"Hardware: {identity} · {support['status']}", support['summary'],
            *support['limitations'], 'Detection does not verify that every feature works.']


def text(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ''


def driver(path):
    link = path / 'driver'
    return link.resolve().name if link.is_symlink() else ''


def pci_devices(sysroot):
    result = []
    for path in sorted((sysroot / 'bus/pci/devices').glob('*')):
        address = PCI_ADDRESS.fullmatch(path.name)
        if address is None:
            continue
        values = {key: text(path / name).removeprefix('0x').lower() for key, name in (
            ('vendor', 'vendor'), ('device', 'device'), ('class', 'class'),
            ('subvendor', 'subsystem_vendor'), ('subdevice', 'subsystem_device'))}
        if not all(re.fullmatch(r'[0-9a-f]{4}', values[key]) for key in ('vendor', 'device')):
            continue
        domain, bus, slot, function = [int(v, 16) for v in address.groups()]
        result.append({**values, 'address': path.name, 'bus': 'pci', 'driver': driver(path),
                       'busId': f'PCI:{bus}:{slot}:{function}' if domain == 0 else '', 'interfaces': []})
    return result


def network_devices(sysroot, pci):
    devices = {d['address']: dict(d, interfaces=[]) for d in pci if d['class'].startswith('02')}
    for interface in sorted((sysroot / 'class/net').glob('*')):
        device = interface / 'device'
        if not device.exists():
            continue  # loopback, bridges, VPNs and other virtual interfaces
        path = device.resolve()
        parents = [path, *path.parents]
        match = next((devices[p.name] for p in parents if p.name in devices), None)
        if match is None:
            usb = next((p for p in parents if (p / 'idVendor').is_file() and (p / 'idProduct').is_file()), None)
            if usb is None:
                continue
            match = devices.setdefault(usb.name, {'address': usb.name, 'bus': 'usb',
                'vendor': text(usb / 'idVendor'), 'device': text(usb / 'idProduct'), 'interfaces': []})
        match['driver'] = driver(device) or match.get('driver', '')
        match['interfaces'].append({'name': interface.name, 'wireless': (interface / 'phy80211').exists(),
                                    'state': text(interface / 'operstate')})
    return list(devices.values())


def firmware_requests(log):
    # Failed optional probes can precede a successful fallback; never promote
    # these messages alone to a blocking compatibility verdict.
    names = re.findall(r'(?:Direct firmware load for |firmware: failed to load )([A-Za-z0-9_./+\-]+)', log)
    return sorted({name for name in names if not name.startswith('/') and '..' not in name.split('/')})[:32]


def nvidia_selection(devices, catalogue):
    nvidia = [d for d in devices if d['vendor'] == '10de' and d['class'].startswith('03')]
    if not nvidia:
        return {'present': False, 'open': False, 'closed': False, 'recommendedOpen': None, 'blockers': []}
    catalogue = catalogue if isinstance(catalogue, dict) else {}
    branches = catalogue.get('nvidia', {}) if catalogue.get('schema') == 1 else {}
    branches = branches if isinstance(branches, dict) else {}
    def branch_data(branch):
        value = branches.get(branch)
        return value if isinstance(value, dict) else {}
    def supported(device, branch):
        entries = branch_data(branch).get('devices', [])
        if not isinstance(entries, list):
            return False
        return any(all(device.get(key) == value for key, value in entry.items())
                   for entry in entries if isinstance(entry, dict) and 'device' in entry
                   and set(entry) <= {'device', 'subvendor', 'subdevice'})
    allowed = {branch: all(supported(device, branch) for device in nvidia) for branch in ('open', 'closed')}
    blockers = []
    if not any(allowed.values()):
        ids = ', '.join('10de:' + device['device'] for device in nvidia)
        blockers.append(f'No packaged NVIDIA driver supports all detected GPUs ({ids}). '
                        'This installer cannot select a supported graphics stack; no disk has been erased.')
    return {'present': True, **allowed, 'recommendedOpen': True if allowed['open'] else False if allowed['closed'] else None,
            'versions': {branch: branch_data(branch).get('version', '') for branch in ('open', 'closed')},
            'blockers': blockers}


def detect(sysroot=Path('/sys'), cpuinfo=Path('/proc/cpuinfo'), *, catalogue=None, kernel_log=None,
           profile_catalogue=None, kernel=None):
    sysroot = Path(sysroot)
    if catalogue is None:
        try:
            catalogue = json.loads(CATALOGUE.read_text())
        except (OSError, ValueError):
            catalogue = {}
    pci = pci_devices(sysroot)
    displays = [d for d in pci if d['class'].startswith('03')]
    selection = nvidia_selection(displays, catalogue)
    nvidia = [d['busId'] for d in displays if d['vendor'] == '10de']
    intel = [d['busId'] for d in displays if d['vendor'] == '8086']
    amd = [d['busId'] for d in displays if d['vendor'] == '1002']
    prime = {'enable': len(nvidia) == 1 and len(intel) + len(amd) == 1 and all(nvidia + intel + amd),
             'nvidiaBusId': nvidia[0] if len(nvidia) == 1 else '',
             'intelBusId': intel[0] if len(intel) == 1 else '',
             'amdgpuBusId': amd[0] if len(amd) == 1 else ''}
    vendor, product, sku, board = [text(sysroot / 'class/dmi/id' / name)
                                   for name in ('sys_vendor', 'product_name', 'product_sku', 'board_name')]
    cpu = text(cpuinfo)
    # The XPS 14/16 SKUs predate this platform on older models, so they also
    # need the Core Ultra CPU. The XPS 13's model number is unique to the 2026
    # design; its Wildcat Lake SKU (0E53) is not sold as Core Ultra.
    xps = 'Dell' in vendor and (
        (any(s in product for s in ('XPS 14', 'XPS 16', 'DA14260', 'DA16260'))
         and sku in ('0DB9', '0DBA') and ('Panther' in cpu or 'Ultra' in cpu))
        or ('DX13260' in product and sku in ('0E53', '0E54')))
    # HP keys the ZBook Ultra G1a by its board ID; its product SKU is regional.
    zbook = vendor == 'HP' and board == '8D01' and 'ZBook Ultra G1a' in product
    acpi = any('OVTI08F4' in p.name for p in (sysroot / 'bus/acpi/devices').glob('*'))
    panel = ''
    for path in sorted((sysroot / 'class/drm').glob('*eDP-*/edid')):
        try:
            data = path.read_bytes()
            if len(data) >= 12:
                panel = data[8:12].hex()
        except OSError:
            pass
    network = network_devices(sysroot, pci)
    issues = []
    for device in network:
        identity = f'{device["vendor"]}:{device["device"]}'
        if not device.get('driver'):
            issues.append(f'Network adapter {identity} has no active driver. Try a supported USB Ethernet adapter or USB tethering.')
        elif not device['interfaces']:
            issues.append(f'Network adapter {identity} has a driver but no interface. Check its firmware and hardware switch.')
        if device['vendor'] == '14e4' and not device['interfaces']:
            issues.append('Some Broadcom radios need firmware unavailable in this image. The insecure Broadcom STA driver is not enabled.')
    log_available = kernel_log is not None
    if kernel_log is None:
        kernel_log = ''
        if sysroot == Path('/sys'):
            try:
                result = subprocess.run(['dmesg', '--level=err,warn', '--color=never'], text=True,
                                        capture_output=True, timeout=5)
                if result.returncode == 0:
                    log_available = True
                    kernel_log = result.stdout[-256 * 1024:]
            except (OSError, subprocess.SubprocessError):
                pass
    firmware = firmware_requests(kernel_log)
    if issues and firmware:
        issues.append('Firmware requests failed: ' + ', '.join(firmware[:4]) + '. Some requests can be optional.')
    graphics_detail = 'Desktop compatibility is checked after installation.'
    if selection['present'] and selection['recommendedOpen'] is not None:
        graphics_detail = 'NVIDIA driver selected automatically for the detected devices.'
    elif displays and any(not d['driver'] for d in displays):
        graphics_detail = 'A native display driver is not active. Basic graphics can run setup; the desktop still needs a working driver.'
    support = hardware_support(sysroot, kernel=kernel, catalogue=profile_catalogue)
    camera_detected = xps and acpi and any(d['vendor'] == '8086' and d['device'] == 'b05d' for d in pci)
    if camera_detected and CAMERA_LIMIT not in support['limitations']:
        support['limitations'].append(CAMERA_LIMIT)
    return {'support': support,
            'nvidia': selection['present'], 'nvidiaOpen': selection['recommendedOpen'], 'nvidiaSelection': selection,
            'nvidiaPrime': prime, 'xps': xps, 'sku': sku, 'panel': panel, 'zbookUltraG1a': zbook,
            # Fresh installs use stock Nixpkgs kernels. Detection is not consent
            # to build the experimental camera stack on this machine.
            'camera': False, 'cameraDetected': camera_detected,
            'graphicsDevices': displays, 'networkDevices': network, 'networkIssues': issues,
            'firmwareRequests': firmware, 'firmwareLogAvailable': log_available,
            'blockers': selection['blockers'], 'graphicsDetail': graphics_detail}


def validate_hardware(hardware, nvidia_open):
    if hardware.get('blockers'):
        raise Failure(' '.join(hardware['blockers']))
    selection = hardware.get('nvidiaSelection')
    if hardware.get('nvidia') and selection and not selection.get('open' if nvidia_open else 'closed'):
        raise Failure('The selected NVIDIA driver does not support all detected GPUs. '
                      'Use the automatically recommended driver. No disk has been erased.')


def configured_support(assessment, etc):
    """Compare configured declarations with detection, not boot-time behavior."""
    def metadata(name):
        try:
            value = json.loads((etc / name).read_text())
            return value if isinstance(value, dict) and value.get('schema') == 1 else {}
        except (OSError, ValueError):
            return {}

    configured = metadata('hardware-support.json')
    legacy = metadata('hardware-profile.json')
    support = assessment['support']
    detected = support.get('profileId') or support.get('matchedProfileId')
    selected = configured.get('selectedProfile')
    selected = selected if isinstance(selected, str) else None
    kernel = configured.get('configuredKernel')
    kernel = kernel if isinstance(kernel, str) else None
    live = configured.get('installationMedium') is True
    needs_legacy = bool(detected and (detected.startswith('dell-xps-') or detected == 'hp-zbook-ultra-g1a'))
    legacy_enabled = bool(
        (assessment['xps'] and legacy.get('xps') == assessment['sku'])
        or (assessment['zbookUltraG1a'] and legacy.get('zbookUltraG1a') is True))
    guidance = ''
    if live:
        state, summary = 'live', 'The installer will record the selected profile during fresh installation.'
    elif selected and selected != detected:
        state, summary = 'mismatch', 'The configured profile differs from the detected hardware.'
        guidance = 'Review the hardware settings in your personal configuration before staging an update.'
    elif detected and ((needs_legacy and legacy_enabled) or (not needs_legacy and selected == detected)):
        state, summary = 'configured', 'The detected hardware profile is configured; runtime behavior still needs checking.'
    elif detected and configured:
        state, summary = 'available', 'A profile is available for this computer but its settings are not configured.'
        if needs_legacy:
            guidance = 'Review the Laptop fixes check and hardware support documentation before enabling the profile.'
        else:
            guidance = (f'To enable it, add cybexos.hardware.profile = "{detected}"; to your personal NixOS module, '
                        'then prepare and review the change with cybex update local through the normal staged updater.')
    elif not detected and configured:
        state, summary = 'generic', 'No approved catalogue profile matches this computer.'
    else:
        state, summary = 'unknown', 'Configured hardware profile information is unavailable.'
    return {'state': state, 'profileId': selected, 'detectedProfileId': detected,
            'legacyProfileConfigured': legacy_enabled, 'configuredKernel': kernel,
            'installationMedium': live, 'summary': summary, 'guidance': guidance}


def report(sysroot=Path('/sys'), cpuinfo=Path('/proc/cpuinfo'), *, etc=Path('/etc/cybexos'),
           machine_lock=Path('/etc/nixos/flake.lock'), **assessment_options):
    """Collect device facts without changing hardware, networks, disks or firmware.

    Omit serial numbers, UUIDs, MAC/IP addresses, SSIDs and raw kernel logs.
    An inventory is useful evidence for a qualification record, never a pass.
    """
    sysroot, etc = Path(sysroot), Path(etc)
    assessment = detect(sysroot, cpuinfo, **assessment_options)
    try:
        release = json.loads((etc / 'release.json').read_text())
    except (OSError, ValueError):
        release = {}
    release = {key: release[key] for key in ('version', 'revision', 'narHash', 'nixos') if key in release} if isinstance(release, dict) else {}
    nixpkgs = {}
    try:
        # Read only the independently owned root input; never refresh the lock
        # or include personal input URLs in a shareable inventory.
        from .inputs import identity
        locked = identity(json.loads(Path(machine_lock).read_text()), 'nixpkgs')
        if isinstance(locked, dict):
            nixpkgs = {key: locked[key] for key in ('rev', 'narHash') if isinstance(locked.get(key), str)}
    except (OSError, ValueError, TypeError, KeyError, Failure):
        pass
    cpu = {}
    for line in text(cpuinfo).splitlines():
        key, separator, value = line.partition(':')
        if separator and key.strip() in ('vendor_id', 'model name', 'cpu family', 'model', 'stepping'):
            cpu.setdefault(key.strip(), value.strip())
    usb = []
    for path in sorted((sysroot / 'bus/usb/devices').glob('*')):
        vendor, device = text(path / 'idVendor'), text(path / 'idProduct')
        if not all(re.fullmatch('[0-9a-fA-F]{4}', value) for value in (vendor, device)):
            continue
        interfaces = [{'address': interface.name, 'class': text(interface / 'bInterfaceClass'),
                       'driver': driver(interface)}
                      for interface in sorted(path.parent.glob(path.name + ':*'))]
        usb.append({'address': path.name, 'vendor': vendor.lower(), 'device': device.lower(),
                    'class': text(path / 'bDeviceClass'), 'driver': driver(path), 'interfaces': interfaces})
    disks = []
    for path in sorted((sysroot / 'block').glob('*')):
        if path.name.startswith(('loop', 'ram', 'zram', 'dm-')):
            continue
        sectors = text(path / 'size')
        disks.append({'name': path.name, 'sizeBytes': int(sectors) * 512 if sectors.isdecimal() else None,
                      'model': text(path / 'device/model'), 'removable': text(path / 'removable') == '1'})
    secure_boot = None
    for variable in (sysroot / 'firmware/efi/efivars').glob('SecureBoot-*'):
        try:
            value = variable.read_bytes()
            if len(value) == 5 and value[4] in (0, 1):
                secure_boot = bool(value[4])
        except OSError:
            pass
    return {'schema': 'cybexos.hardware-inventory.v1', 'scope': 'Read-only inventory; no hardware qualification performed',
            'release': release, 'nixpkgs': nixpkgs, 'support': assessment['support'],
            'configuration': configured_support(assessment, etc),
            'kernel': os.uname().release, 'architecture': os.uname().machine,
            'system': {key: text(sysroot / 'class/dmi/id' / key) for key in
                       ('sys_vendor', 'product_name', 'product_sku', 'board_vendor', 'board_name', 'bios_vendor', 'bios_version', 'bios_date')},
            'firmware': {'uefi': (sysroot / 'firmware/efi').is_dir(), 'secureBoot': secure_boot},
            'cpu': cpu, 'pciDevices': pci_devices(sysroot), 'usbDevices': usb, 'disks': disks,
            'assessment': assessment,
            'qualification': {name: 'not-run' for name in (
                'usbBoot', 'pxeBoot', 'secureBoot', 'network', 'storage', 'encryptedInstallation', 'login',
                'graphics', 'audio', 'input', 'bluetooth', 'suspendResume', 'externalDisplays', 'camera',
                'stagedUpdate', 'trialBootConfirmation', 'rollback')}}
