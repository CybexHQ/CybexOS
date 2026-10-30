"""Prebuilt-only staging: dry-run parsing, build classification, engine guard.

Fixture tests at the command boundary; real cache behaviour is covered by
scripts/check-prebuilt and installation qualification.
"""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import test_lifecycle as lifecycle
from cybexos import prebuilt
from cybexos.common import atomic, read
from cybexos.engine import NotPrebuilt


def store(letter, name):
    return '/nix/store/' + letter * 32 + '-' + name


ROOT = store('r', 'nixos-system-cybexos.drv')
CONFIG = store('c', 'etc.drv')
HELLO = store('h', 'hello-2.12.drv')
VENDOR = store('v', 'spotify-1.2.drv')
SOURCE = store('s', 'spotify.deb.drv')
TOOL = store('t', 'patchelf-wrapper.drv')


def node(*inputs, **env):
    return {'outputs': {'out': {'path': store('o', 'out')}}, 'env': env, 'inputDrvs': {i: {} for i in inputs}}


GRAPH = {
    ROOT: node(CONFIG, VENDOR, preferLocalBuild='1'),
    CONFIG: node(HELLO),                                        # no source: configuration
    HELLO: node(src=store('x', 'hello.tar.gz')),                # a Nixpkgs package from source
    VENDOR: node(SOURCE, TOOL, src=store('y', 'spotify.deb')),  # unfree, expected
    SOURCE: {'outputs': {'out': {'path': store('z', 'deb'), 'hash': 'abc'}}, 'env': {}, 'inputDrvs': {}},
    TOOL: node(src=store('w', 'tool')),                         # needed only by the vendor package
}


def shown(graph):
    def run(*args, **kwargs):
        assert args[:3] == ('nix', 'derivation', 'show'), args
        return json.dumps({path: graph[path] for path in args[3:] if path in graph})
    return run


class Parsing(unittest.TestCase):
    def test_plural_and_singular_dry_run_output(self):
        plan = prebuilt.parse_dry_run(
            'these 2 derivations will be built:\n'
            f'  {HELLO}\n  {VENDOR}\n'
            'these 231 paths will be fetched (233.03 MiB download, 798.93 MiB unpacked):\n'
            f'  {store("a", "gtk4")}\n')
        self.assertEqual(plan['build'], [HELLO, VENDOR])
        self.assertEqual(plan['fetch'], [store('a', 'gtk4')])
        self.assertEqual(plan['downloadBytes'], int(233.03 * 1024 ** 2))
        single = prebuilt.parse_dry_run(f'this derivation will be built:\n  {HELLO}\n'
                                        f'this path will be fetched (1.50 GiB download, 4 GiB unpacked):\n  {store("b", "x")}\n')
        self.assertEqual((single['build'], single['downloadBytes']), ([HELLO], int(1.5 * 1024 ** 3)))
        self.assertEqual(prebuilt.parse_dry_run('warning: Git tree is dirty\n'), {'build': [], 'fetch': [], 'downloadBytes': 0})

    def test_kinds_include_structured_attributes(self):
        self.assertEqual(prebuilt.kind(GRAPH[SOURCE]), 'fetch')
        self.assertEqual(prebuilt.kind(GRAPH[ROOT]), 'trivial')
        structured = {'outputs': {}, 'env': {'__json': json.dumps({'allowSubstitutes': False, 'src': 'x'})}}
        self.assertEqual(prebuilt.kind(structured), 'trivial')
        self.assertEqual(prebuilt.kind(GRAPH[CONFIG]), 'configuration')
        self.assertEqual(prebuilt.kind(GRAPH[HELLO]), 'compile')
        self.assertEqual(prebuilt.name(HELLO), 'hello-2.12')


class Classification(unittest.TestCase):
    def test_compiles_below_configuration_but_not_below_expected_builds(self):
        found = prebuilt.compiles(shown(GRAPH), list(GRAPH), root=ROOT, expected=[VENDOR])
        self.assertEqual(found, ['hello-2.12'])

    def test_unexpected_vendor_package_is_reported_once_without_its_inputs(self):
        found = prebuilt.compiles(shown(GRAPH), list(GRAPH), root=ROOT)
        self.assertEqual(found, ['hello-2.12', 'spotify-1.2'])

    def test_without_a_root_every_unexpected_compile_counts(self):
        self.assertEqual(prebuilt.compiles(shown(GRAPH), list(GRAPH), expected=[VENDOR]), ['hello-2.12', 'patchelf-wrapper'])


class EngineGuard(unittest.TestCase):
    setUp = lifecycle.EngineTests.setUp

    def plan(self, expected):
        original = self.engine.run
        def run(*args, **kwargs):
            args = tuple(map(str, args))
            if args[:2] == ('nix', 'build') and '--dry-run' in args:
                self.assertTrue(kwargs.get('diagnostics'))
                self.assertIn('--no-update-lock-file', args)
                return 'these 2 derivations will be built:\n' + ''.join(f'  {d}\n' for d in (ROOT, HELLO))
            if args[:3] == ('nix', 'eval', '--raw'):
                return ROOT
            if args[:3] == ('nix', 'eval', '--json') and any(a.endswith('.cybexosExpectedBuilds') for a in args):
                return json.dumps(expected)
            if args[:3] == ('nix', 'derivation', 'show'):
                return shown({ROOT: node(HELLO, preferLocalBuild='1'), HELLO: GRAPH[HELLO]})(*args)
            return original(*args, **kwargs)
        run.observer = None
        run.log = None
        self.engine.run = run

    def test_upstream_candidate_that_would_compile_is_refused_before_building(self):
        self.plan([])
        with self.assertRaises(NotPrebuilt) as raised:
            self.engine.stage('upstream')
        self.assertEqual(raised.exception.names, ['hello-2.12'])
        status = read(self.engine.status_path)
        self.assertEqual((status['state'], status['notPrebuilt']), ('failed', ['hello-2.12']))
        self.assertIn("NixOS hasn't finished building 1 package", status['error'])
        self.assertIn('Nothing was changed', status['error'])
        self.assertEqual(lifecycle.config_digest(self.config), self.sentinel)
        builds = [c for c in self.runner.calls if c[:2] == ('nix', 'build') and '--dry-run' not in c]
        self.assertEqual(builds, [], 'the full build never starts')

    def test_expected_local_builds_pass(self):
        self.plan([HELLO])
        record = self.engine.stage('upstream')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')
        self.assertIsNone(read(self.engine.status_path)['notPrebuilt'])
        self.assertTrue(record['reviewToken'])

    def test_personal_configuration_previews_are_not_checked(self):
        self.plan([])
        self.engine.stage('local')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')


class PackagesOnly(unittest.TestCase):
    def setUp(self):
        lifecycle.EngineTests.setUp(self)
        atomic(self.config / 'local/software.json', {'schema': 1, 'packages': []})
        shutil.rmtree(self.base / 'deployed')
        lifecycle.copy_config(self.config, self.base / 'deployed')

    def systems(self, base, params=('quiet', 'quiet')):
        kernel = base / 'kernel-image'; kernel.write_text('k')
        paths = []
        for name, value in zip(('old', 'new'), params):
            system = base / name; system.mkdir()
            (system / 'kernel').symlink_to(kernel)
            (system / 'initrd').symlink_to(kernel)
            (system / 'kernel-params').write_text(value)
            paths.append(str(system))
        return paths

    def test_only_software_declaration_and_same_boot_qualify(self):
        tx = self.base / 'tx'
        lifecycle.copy_config(self.base / 'deployed', tx / 'config')
        atomic(tx / 'config/local/software.json', {'schema': 1, 'packages': ['gimp']})
        with tempfile.TemporaryDirectory() as directory:
            old, new = self.systems(Path(directory))
            record = {'changeKind': 'software', 'system': new, 'previousSystem': old}
            self.assertTrue(self.engine.packages_only(record, tx))
            self.assertFalse(self.engine.packages_only(record | {'changeKind': 'update'}, tx))
            (tx / 'config/local/personal.nix').write_text('{ services.foo.enable = true; }')
            self.assertFalse(self.engine.packages_only(record, tx), 'other personal edits need a trial boot')
        with tempfile.TemporaryDirectory() as directory:
            (tx / 'config/local/personal.nix').write_text('# packages, VPN, services sentinel\n{}')
            old, new = self.systems(Path(directory), ('quiet', 'quiet splash'))
            self.assertFalse(self.engine.packages_only({'changeKind': 'software', 'system': new, 'previousSystem': old}, tx))

    def test_software_install_becomes_the_default_without_a_trial_boot(self):
        record = self.engine.stage('local', software={'packages': ['gimp'], 'previous': []}, request_id='c' * 32)
        with patch.object(type(self.engine), 'packages_only', return_value=True):
            self.engine.apply(record['id'], record['reviewToken'])
        calls = self.runner.calls
        self.assertIn(('cybexos-boot-trial', '--commit', lifecycle.NEW_SYSTEM), calls)
        self.assertNotIn(('cybexos-boot-trial', lifecycle.NEW_SYSTEM, lifecycle.OLD_SYSTEM), calls)
        status = read(self.engine.status_path)
        self.assertEqual((status['state'], status['restart']), ('done', 'None'))
        self.assertFalse(self.engine.pending_path.exists())
        self.assertTrue((self.engine.tx(record['id']) / 'good.json').is_file())
        self.assertEqual(read(self.working / 'local/software.json')['packages'], ['gimp'])

    def test_other_software_changes_still_use_a_trial_boot(self):
        record = self.engine.stage('local', software={'packages': ['gimp'], 'previous': []}, request_id='c' * 32)
        self.engine.apply(record['id'], record['reviewToken'])
        self.assertIn(('cybexos-boot-trial', lifecycle.NEW_SYSTEM, lifecycle.OLD_SYSTEM), self.runner.calls)
        self.assertEqual(read(self.engine.status_path)['state'], 'awaiting-boot')


if __name__ == '__main__':
    unittest.main()
