"""Exact hardware support metadata and policy, without physical qualification."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lifecycle'))
from cybexos import hardware_profiles as profiles

CATALOGUE = json.loads((ROOT / 'lifecycle/cybexos/hardware-profiles.json').read_text())


class HardwareProfileTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-profile-')
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root / 'firmware/efi').mkdir(parents=True)
        self.dmi = self.root / 'class/dmi/id'
        self.dmi.mkdir(parents=True)
        uname = os.uname_result(('Linux', 'fixture', '7.3', '', 'x86_64'))
        mock = patch.object(profiles.os, 'uname', return_value=uname)
        mock.start()
        self.addCleanup(mock.stop)

    def identity(self, **values):
        for path in self.dmi.iterdir():
            path.unlink()
        for key, value in values.items():
            (self.dmi / key).write_text(value)

    def support(self, **kwargs):
        return profiles.support_for(self.root, kernel=kwargs.pop('kernel', '7.3'),
                                    catalogue=kwargs.pop('catalogue', CATALOGUE), **kwargs)

    def test_every_curated_identity_matches_and_never_claims_qualification(self):
        for profile in CATALOGUE['profiles']:
            for rule in profile['matches']:
                values = {key: value[0] for key, value in rule['dmi'].items()}
                if 'machineTypes' in rule:
                    values['product_name'] = rule['machineTypes'][0] + 'CTO1WW'
                with self.subTest(profile=profile['id']):
                    self.identity(**values)
                    result = self.support()
                    self.assertEqual(result['profileId'], profile['id'])
                    self.assertEqual(result['status'], 'experimental')
                    self.assertEqual(result['testStatus']['physical'], 'not-run')
                    self.assertTrue(result['configurationSupported'])
                    self.assertEqual(json.loads(json.dumps(result)), result)
                    self.assertTrue(result['sources'])
                    self.assertTrue(result['limitations'])

    def test_dell_model_sku_cross_product_is_not_accepted(self):
        for product, sku in [('XPS 14 DA14260', '0DBA'), ('XPS 16 DA16260', '0DB9'),
                             ('XPS 13 9350', '0E54'), ('XPS 14 9440', '0DB9'),
                             ('XPS 16 DX16263', '0DBA'), ('XPS 13 DX13260 Engineering Sample', '0E54')]:
            with self.subTest(product=product, sku=sku):
                self.identity(sys_vendor='Dell Inc.', product_name=product, product_sku=sku)
                self.assertIsNone(self.support()['profileId'])

    def test_vendor_generation_and_near_product_strings_do_not_match(self):
        for vendor, product in [('Other Framework vendor', 'Laptop 13 (AMD Ryzen 7040Series)'),
                                ('Framework', 'Laptop 13 (AMD Ryzen AI 300 Series)'),
                                ('Framework', 'Laptop 16 (AMD Ryzen 7040Series)'),
                                ('Framework', 'Laptop 13 (AMD Ryzen 7040Series) Pro'),
                                ('framework', 'Laptop 13 (AMD Ryzen 7040Series)')]:
            with self.subTest(vendor=vendor, product=product):
                self.identity(sys_vendor=vendor, product_name=product)
                self.assertIsNone(self.support()['profileId'])
        self.identity(sys_vendor='Framework\n', product_name='Laptop 13 (AMD Ryzen 7040Series)\n')
        self.assertEqual(self.support()['profileId'], 'framework-13-amd-7040')

    def test_zbook_requires_model_vendor_and_board_without_regional_sku(self):
        self.identity(sys_vendor='HP', product_name='HP ZBook Ultra G1a 14 inch Mobile Workstation PC',
                      board_name='8D01', product_sku='REGIONAL#ORDER')
        self.assertEqual(self.support()['profileId'], 'hp-zbook-ultra-g1a')
        for key, value in [('board_name', '8D02'), ('product_name', 'HP ZBook Power G1a'),
                           ('sys_vendor', 'Other HP')]:
            path = self.dmi / key
            before = path.read_text()
            path.write_text(value)
            self.assertIsNone(self.support()['profileId'])
            path.write_text(before)

    def test_thinkpad_requires_exact_version_and_valid_complete_machine_type(self):
        for product in ('21MCCTO1WW', '21MD0012US'):
            self.identity(sys_vendor='LENOVO', product_version='ThinkPad T14 Gen 5', product_name=product)
            self.assertEqual(self.support()['profileId'], 'lenovo-thinkpad-t14-gen5-amd')
        for product in ('21MC', '21MCCTO1WWextra', '21ME0012US', '21N10012US', '21MC-TO1WW'):
            self.identity(sys_vendor='LENOVO', product_version='ThinkPad T14 Gen 5', product_name=product)
            self.assertIsNone(self.support()['profileId'])
        self.identity(sys_vendor='LENOVO', product_version='ThinkPad T14s Gen 5', product_name='21MCCTO1WW')
        self.assertIsNone(self.support()['profileId'])

    def test_out_of_scope_platforms_never_select_even_an_exact_profile(self):
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)')
        (self.root / 'firmware/efi').rmdir()
        self.assertEqual(self.support()['status'], 'unsupported')
        (self.root / 'firmware/efi').mkdir()
        self.identity(sys_vendor='Apple Inc.', product_name='MacBookPro16,1')
        self.assertEqual(self.support()['status'], 'unsupported')
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)', board_vendor='Apple Inc.')
        self.assertEqual(self.support()['status'], 'unsupported')
        with patch.object(profiles.os, 'uname', return_value=os.uname_result(('Linux', '', '7.3', '', 'aarch64'))):
            self.assertEqual(self.support()['status'], 'unsupported')
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)')
        alias = self.root / 'devices/system/cpu/modalias'
        alias.parent.mkdir(parents=True)
        alias.write_text('cpu:type:x86,ven000Afam0006mod0000:feature:')
        self.assertEqual(self.support()['status'], 'unsupported')
        for vendor in ('0000', '0002'):
            alias.write_text(f'cpu:type:x86,ven{vendor}fam0006mod0000:feature:')
            self.assertEqual(self.support()['status'], 'experimental')

    def test_kernel_bounds_are_numeric_and_do_not_select_invalid_configurations(self):
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)')
        for kernel in ('6.7.12', '', 'unknown', '7.3.garbage', '7.3-rc1', 703):
            with self.subTest(kernel=kernel):
                result = self.support(kernel=kernel)
                self.assertIsNone(result['profileId'])
                self.assertEqual(result['status'], 'unsupported')
        for kernel in ('6.8', '7.3.0', '7.3.1-nixos', '7.10.2'):
            self.assertIsNotNone(self.support(kernel=kernel)['profileId'])
        for bounds in ({}, {'minimum': 'garbage'}, {'minimum': '6.8', 'maximumExclusive': 'unknown'}):
            malformed = copy.deepcopy(CATALOGUE)
            malformed['profiles'][-2]['kernel'] = bounds
            self.assertEqual(self.support(catalogue=malformed)['status'], 'unsupported')
        bounded = copy.deepcopy(CATALOGUE)
        bounded['profiles'][-2]['kernel']['maximumExclusive'] = '7.4'
        self.assertEqual(self.support(kernel='7.4', catalogue=bounded)['status'], 'unsupported')

    def test_injected_catalogue_paths_unapproved_and_ambiguous_entries_fail_closed(self):
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)')
        for catalogue in ({}, [], {'schema': 1, 'profiles': None}, {'schema': 99, 'profiles': CATALOGUE['profiles']}):
            self.assertEqual(self.support(catalogue=catalogue)['status'], 'generic')
        injected = copy.deepcopy(CATALOGUE)
        selected = injected['profiles'][-2]
        selected['approved'] = False
        self.assertIsNone(self.support(catalogue=injected)['profileId'])
        selected['approved'] = True
        injected['profiles'].append(copy.deepcopy(selected))
        self.assertIsNone(self.support(catalogue=injected)['profileId'])
        path = self.root / 'catalogue.json'
        path.write_text(json.dumps(CATALOGUE))
        self.assertEqual(self.support(catalogue=path)['profileId'], 'framework-13-amd-7040')
        path.write_text('{')
        self.assertEqual(self.support(catalogue=path)['status'], 'generic')

    def test_malformed_match_rules_cannot_become_vendor_wide_profiles(self):
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)')
        for rule in ({}, {'dmi': {}}, {'dmi': {'sys_vendor': ['Framework']}},
                     {'dmi': {'sys_vendor': ['Framework'], 'product_name': []}},
                     {'dmi': {'sys_vendor': ['Framework'], 'product_name': '*'}},
                     {'dmi': {'sys_vendor': ['Framework'], 'product_name': ['Laptop 13 (AMD Ryzen 7040Series)']}, 'unknown': True}):
            injected = copy.deepcopy(CATALOGUE)
            injected['profiles'][-2]['matches'] = [rule]
            self.assertIsNone(self.support(catalogue=injected)['profileId'])

    def test_injected_claim_of_qualification_is_never_promoted_or_mutated(self):
        self.identity(sys_vendor='Framework', product_name='Laptop 13 (AMD Ryzen 7040Series)')
        injected = copy.deepcopy(CATALOGUE)
        injected['profiles'][-2].update(status='qualified', testStatus={'physical': 'passed'})
        before = copy.deepcopy(injected)
        result = self.support(catalogue=injected)
        self.assertEqual(result['status'], 'experimental')
        self.assertEqual(result['testStatus']['physical'], 'not-run')
        result['limitations'].append('caller-owned')
        self.assertEqual(injected, before)


class CataloguePolicyTests(unittest.TestCase):
    def test_catalogue_has_provenance_bounds_removal_conditions_and_no_qualification_claim(self):
        self.assertEqual(CATALOGUE['scope']['kernelPolicy'], 'stock-prebuilt-nixpkgs')
        ids = [p['id'] for p in CATALOGUE['profiles']]
        self.assertEqual(len(ids), len(set(ids)))
        for p in CATALOGUE['profiles']:
            with self.subTest(profile=p['id']):
                self.assertEqual(p['status'], 'experimental')
                self.assertEqual(p['qualification'], {'status': 'not-run', 'record': None})
                self.assertTrue(p['kernel']['minimum'])
                self.assertIn('maximumExclusive', p['kernel'])
                self.assertTrue(p['sources'])
                self.assertTrue(p['limitations'])
                for source in p['sources']:
                    self.assertTrue(source['url'].startswith(('https://', 'docs/')))
                    if source['project'] in ('nixos-hardware', 'Nixpkgs', 'Omarchy'):
                        self.assertRegex(source['revision'], r'^[0-9a-f]{40}$')
                for workaround in p['workarounds']:
                    self.assertTrue(workaround['removeWhen'])
                    self.assertTrue(workaround['kernel']['minimum'])
                    self.assertIn('maximumExclusive', workaround['kernel'])

    def test_profile_module_has_no_kernel_power_boot_or_personal_state_takeover(self):
        module = (ROOT / 'nix/modules/hardware-profiles.nix').read_text()
        # Behavioral Nix checks are in nix/tests/hardware-profiles.nix. This
        # ownership guard also catches introducing a transitive profile import.
        for assignment in ('boot.kernelPackages =', 'boot.kernelPatches =', 'structuredExtraConfig =',
                           'nixpkgs.overlays =', 'services.tlp.enable =', 'services.tuned.enable =',
                           'services.power-profiles-daemon.enable =', 'boot.loader.',
                           'activationScripts', '/etc/nixos', 'imports ='):
            self.assertNotIn(assignment, module)
        self.assertIn('builtins.fromJSON (builtins.readFile ../../lifecycle/cybexos/hardware-profiles.json)', module)
        self.assertIn('lib.types.enum ids', module)
        self.assertIn('"cybexos/hardware-support.json"', module)
        self.assertNotIn('"cybexos/hardware-profile.json"', module)
