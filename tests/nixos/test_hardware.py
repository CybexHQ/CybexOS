"""Hardware preflight fixtures; no physical hardware is qualified here."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lifecycle'))
from cybexos import hardware
from cybexos.common import Failure

spec = importlib.util.spec_from_file_location('nvidia_catalogue', ROOT / 'scripts/nvidia-hardware-catalogue.py')
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)

CATALOGUE = {'schema': 1, 'nvidia': {
    'open': {'version': '595', 'devices': [{'device': '2684'}, {'device': '2b85'}]},
    'closed': {'version': '580', 'devices': [{'device': '1b80'}, {'device': '2684'}]},
}}


class HardwareAssessmentTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-hardware-')
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.cpu = self.root / 'cpuinfo'
        self.cpu.write_text('vendor_id : AuthenticAMD\nmodel name : AMD Ryzen\n')

    def pci(self, address='0000:01:00.0', vendor='10de', device='2684', cls='030000', driver=''):
        path = self.root / 'bus/pci/devices' / address
        path.mkdir(parents=True)
        for key, value in {'vendor': vendor, 'device': device, 'class': cls,
                           'subsystem_vendor': '1028', 'subsystem_device': '1234'}.items():
            (path / key).write_text('0x' + value)
        if driver:
            (path / 'driver').symlink_to(self.root / 'drivers' / driver)
        return path

    def detect(self, **kwargs):
        return hardware.detect(self.root, self.cpu, catalogue=CATALOGUE, kernel_log='', **kwargs)

    def test_selects_current_open_and_older_closed_by_exact_device(self):
        path = self.pci()
        self.assertIs(self.detect()['nvidiaOpen'], True)
        (path / 'device').write_text('0x1b80')
        found = self.detect()
        self.assertIs(found['nvidiaOpen'], False)
        self.assertEqual(found['blockers'], [])
        with self.assertRaisesRegex(Failure, 'selected NVIDIA driver'):
            hardware.validate_hardware(found, True)
        hardware.validate_hardware(found, False)

    def test_unknown_gpu_and_missing_or_malformed_catalogue_fail_closed(self):
        self.pci(device='ffff')
        for catalogue in (CATALOGUE, {}, [], {'schema': 1, 'nvidia': []},
                          {'schema': 1, 'nvidia': {'open': None, 'closed': {'devices': None}}}):
            with self.subTest(catalogue=catalogue):
                found = hardware.detect(self.root, self.cpu, catalogue=catalogue, kernel_log='')
                self.assertIsNone(found['nvidiaOpen'])
                with self.assertRaisesRegex(Failure, 'No packaged NVIDIA driver'):
                    hardware.validate_hardware(found, True)

    def test_nvidia_chipset_and_audio_devices_do_not_select_graphics_driver(self):
        self.pci(cls='060000')
        self.pci(address='0000:01:00.1', cls='040300')
        found = self.detect()
        self.assertFalse(found['nvidia'])
        self.assertEqual(found['blockers'], [])

    def test_mixed_generation_requires_one_branch_supporting_every_gpu(self):
        self.pci(device='1b80')
        path = self.pci(address='0000:02:00.0')
        self.assertIs(self.detect()['nvidiaOpen'], False)
        (path / 'device').write_text('0x2b85')
        with self.assertRaisesRegex(Failure, 'all detected GPUs'):
            hardware.validate_hardware(self.detect(), False)

    def test_subsystem_specific_ids_do_not_match_another_board(self):
        path = self.pci()
        catalogue = {'schema': 1, 'nvidia': {'open': {'devices': [
            {'device': '2684', 'subvendor': '1028', 'subdevice': '5678'}]}}}
        self.assertTrue(hardware.detect(self.root, self.cpu, catalogue=catalogue)['blockers'])
        (path / 'subsystem_device').write_text('0x5678')
        self.assertIs(hardware.detect(self.root, self.cpu, catalogue=catalogue)['nvidiaOpen'], True)

    def test_network_missing_driver_and_firmware_messages_are_advisory(self):
        path = self.pci(vendor='14e4', device='43a0', cls='028000')
        found = self.detect()
        self.assertIn('no active driver', found['networkIssues'][0])
        self.assertIn('Broadcom STA', found['networkIssues'][1])
        self.assertEqual(found['blockers'], [])  # another adapter can provide internet
        (path / 'driver').symlink_to(self.root / 'drivers/b43')
        found = self.detect()
        self.assertIn('no interface', found['networkIssues'][0])
        interface = self.root / 'class/net/wlan0'
        interface.mkdir(parents=True)
        (interface / 'device').symlink_to(path)
        (interface / 'phy80211').mkdir()
        (interface / 'operstate').write_text('down')
        log = 'Direct firmware load for brcm/optional.bin failed with error -2'
        found = hardware.detect(self.root, self.cpu, catalogue=CATALOGUE, kernel_log=log)
        self.assertEqual(found['networkIssues'], [])
        self.assertEqual(found['firmwareRequests'], ['brcm/optional.bin'])
        self.assertEqual(found['networkDevices'][0]['interfaces'][0]['name'], 'wlan0')

    def test_usb_ethernet_is_detected_and_virtual_interfaces_are_ignored(self):
        usb = self.root / 'bus/usb/devices/1-2'
        usb.mkdir(parents=True)
        for name, value in [('idVendor', '0bda'), ('idProduct', '8153')]:
            (usb / name).write_text(value)
        function = usb / '1-2:1.0'
        function.mkdir()
        (usb.parent / function.name).symlink_to(function)
        (function / 'driver').symlink_to(self.root / 'drivers/r8152')
        interface = self.root / 'class/net/eth0'
        interface.mkdir(parents=True)
        (interface / 'device').symlink_to(function)
        (interface.parent / 'lo').mkdir()
        (interface.parent / 'wg0').mkdir()
        found = self.detect()
        self.assertEqual(len(found['networkDevices']), 1)
        adapter = found['networkDevices'][0]
        self.assertEqual((adapter['bus'], adapter['vendor'], adapter['device'], adapter['driver']),
                         ('usb', '0bda', '8153', 'r8152'))
        self.assertEqual(found['networkIssues'], [])

    def test_live_xps_touchpad_gate_requires_the_exact_supported_platform(self):
        dmi = self.root / 'class/dmi/id'; dmi.mkdir(parents=True)
        (dmi / 'sys_vendor').write_text('Dell Inc.')
        (dmi / 'product_name').write_text('XPS 14 DA14260')
        self.cpu.write_text('model name : Intel Core Ultra 7\n')
        for sku in ('0DB9', '0DBA'):
            (dmi / 'product_sku').write_text(sku)
            self.assertTrue(self.detect()['xps'])
        (dmi / 'product_sku').write_text('unknown')
        self.assertFalse(self.detect()['xps'])
        (dmi / 'product_sku').write_text('0DB9')
        (dmi / 'product_name').write_text('XPS 14 9440')
        # The older CPU signature must not activate this profile.
        self.cpu.write_text('model name : Intel Core i7\n')
        self.assertFalse(self.detect()['xps'])
        (dmi / 'sys_vendor').write_text('Another manufacturer')
        self.cpu.write_text('model name : Intel Core Ultra 7\n')
        self.assertFalse(self.detect()['xps'])

    def test_inventory_keeps_identity_and_never_manufactures_qualification(self):
        self.pci(driver='nouveau')
        etc = self.root / 'etc'; etc.mkdir()
        release = {'version': 'test', 'revision': 'a' * 40, 'narHash': 'sha256-test', 'nixos': 'unstable'}
        (etc / 'release.json').write_text(json.dumps(release))
        dmi = self.root / 'class/dmi/id'; dmi.mkdir(parents=True)
        (dmi / 'product_name').write_text('QA model')
        (dmi / 'product_serial').write_text('DO-NOT-INCLUDE')
        (dmi / 'bios_version').write_text('1.23')
        efivars = self.root / 'firmware/efi/efivars'; efivars.mkdir(parents=True)
        (efivars / 'SecureBoot-test').write_bytes(b'\x07\0\0\0\x01')
        report = hardware.report(self.root, self.cpu, etc=etc, catalogue=CATALOGUE, kernel_log='')
        self.assertEqual(report['release'], release)
        self.assertEqual(report['system']['bios_version'], '1.23')
        self.assertEqual(report['firmware'], {'uefi': True, 'secureBoot': True})
        self.assertEqual(set(report['qualification'].values()), {'not-run'})
        self.assertNotIn('DO-NOT-INCLUDE', json.dumps(report))

    def test_cli_hardware_is_read_only_and_available_in_live_environment(self):
        from cybexos import cli
        output = io.StringIO()
        with patch.object(sys, 'argv', ['cybex', 'hardware']), patch.object(hardware, 'report', return_value={'scope': 'inventory'}), \
                patch.object(cli, 'Engine') as engine, patch.object(cli, 'require_installed') as installed, \
                patch.object(cli.os, 'execv') as privileged, contextlib.redirect_stdout(output):
            cli.main()
        self.assertEqual(json.loads(output.getvalue()), {'scope': 'inventory'})
        engine.assert_not_called(); installed.assert_not_called(); privileged.assert_not_called()


class DriverCatalogueTests(unittest.TestCase):
    def test_historical_and_open_only_gpus_are_excluded_from_wrong_branches(self):
        values = [
            {'devid': '0x1B80', 'features': [], 'name': 'Pascal'},
            {'devid': '0x2684', 'features': ['kernelopen', 'gsp_proprietary_supported']},
            {'devid': '0x2B85', 'features': ['kernelopen']},
            {'devid': '0x0FC0', 'features': ['kernelopen'], 'legacybranch': '470.xx'},
        ]
        result = extractor.catalogue(values, values, '595', '580')['nvidia']
        self.assertEqual(result['open']['devices'], [{'device': '2684'}, {'device': '2b85'}])
        self.assertEqual(result['closed']['devices'], [{'device': '1b80'}, {'device': '2684'}])
        self.assertEqual(result['closed']['version'], '580')

    def test_subsystem_ids_are_preserved_and_duplicate_rows_are_merged(self):
        chip = {'devid': '0x2684', 'subvendorid': '0x1028', 'subdevid': '0x5678',
                'features': ['kernelopen', 'gsp_proprietary_supported']}
        result = extractor.catalogue([chip, chip], [chip], '595', '580')
        self.assertEqual(result['nvidia']['open']['devices'], [{'device': '2684', 'subvendor': '1028', 'subdevice': '5678'}])

    def test_vendor_archive_metadata_is_read_without_executing_shell_stub(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'driver.run'
            payload = io.BytesIO()
            with tarfile.open(fileobj=payload, mode='w:gz') as archive:
                data = json.dumps({'chips': [{'devid': '0x2684'}]}).encode()
                member = tarfile.TarInfo('driver/supported-gpus/supported-gpus.json')
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            path.write_bytes(b'skip=3\nexit 99\n' + payload.getvalue())
            self.assertEqual(extractor.chips(path), [{'devid': '0x2684'}])
            path.write_bytes(b'unrecognized archive')
            with self.assertRaisesRegex(ValueError, 'header'):
                extractor.chips(path)
