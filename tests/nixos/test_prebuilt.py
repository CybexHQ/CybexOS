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
from cybexos.common import Failure
from cybexos.engine import NotPrebuilt


def store(letter, name):
    return '/nix/store/' + letter * 32 + '-' + name


ROOT = store('r', 'nixos-system-cybexos.drv')
CONFIG = store('c', 'etc.drv')
HELLO = store('h', 'hello-2.12.drv')
VENDOR = store('v', 'spotify-1.2.drv')
SOURCE = store('s', 'spotify.deb.drv')
TOOL = store('t', 'patchelf-wrapper.drv')
KERNEL = store('k', 'linux-7.3.drv')
IMAGE = store('i', 'linux-image-7.3.drv')


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
        # Nix 2.34 (format version 4) keeps only output paths in `env`.
        package = {'outputs': {}, 'env': {'out': store('o', 'out')}, 'structuredAttrs': {'src': store('x', 'source')}}
        self.assertEqual(prebuilt.kind(package), 'compile')
        local = {'outputs': {}, 'env': {'out': store('o', 'out')}, 'structuredAttrs': {'preferLocalBuild': True}}
        self.assertEqual(prebuilt.kind(local), 'trivial')
        self.assertEqual(prebuilt.kind(GRAPH[CONFIG]), 'configuration')
        self.assertEqual(prebuilt.kind(GRAPH[HELLO]), 'compile')
        self.assertEqual(prebuilt.name(HELLO), 'hello-2.12')


class Classification(unittest.TestCase):
    def test_kernel_image_rebuild_is_refused_even_below_expected_builds(self):
        # Nixpkgs rebuild-image.nix uses the kernel dev build tree and only
        # runs the image install target: no karch or modules_install marker.
        attrs = {'pname': 'linux-image', 'src': store('d', 'linux-7.3-dev') + '/lib/modules/7.3/build',
                 'installTargets': ['install'], 'preferLocalBuild': True}
        for image in (node(**attrs), dict(node(), structuredAttrs=attrs),
                      node(__json=json.dumps(attrs))):
            with self.subTest(image=image):
                graph = {ROOT: node(VENDOR), VENDOR: node(IMAGE, src='module'), IMAGE: image}
                self.assertEqual(prebuilt.kind(image), 'compile')
                for root in (None, ROOT):
                    for kernel_only in (False, True):
                        self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=root,
                            expected=[VENDOR, IMAGE], kernel_only=kernel_only), ['linux-image-7.3'])

    def test_kernel_attribution_follows_each_root_without_pruning_compiled_dependencies(self):
        graph = {ROOT: node(VENDOR), VENDOR: node(KERNEL, src='package'),
                 KERNEL: node(pname='linux'), HELLO: node(preferLocalBuild='1')}
        for root, expected in ((ROOT, ['linux-7.3']), (HELLO, []), (CONFIG, [])):
            with self.subTest(root=root):
                self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=root,
                                                  kernel_only=True), expected)
        # Ordinary classification still reports the package as well as its
        # kernel dependency; expected builds cannot suppress that dependency.
        self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=ROOT), ['linux-7.3', 'spotify-1.2'])
        self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=ROOT, expected=[VENDOR]), ['linux-7.3'])

    def test_kernel_cannot_hide_behind_expected_builds_or_local_flags(self):
        for env in ({'pname': 'linux', 'src': 'source'},
                    {'pname': 'linux', 'preferLocalBuild': '1'},
                    {'pname': 'linux', 'allowSubstitutes': ''},
                    {'pname': 'renamed-kernel', 'karch': 'x86_64', 'installTargets': ['install', 'modules_install']}):
            with self.subTest(env=env):
                # Even an expected external module can depend on a kernel
                # that the dry run would compile. Scan before pruning it.
                graph = {ROOT: node(VENDOR), VENDOR: node(KERNEL, src='module'), KERNEL: node(**env)}
                self.assertEqual(prebuilt.kind(graph[KERNEL]), 'compile')
                for root in (None, ROOT):
                    self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=root,
                                                      expected=[VENDOR, KERNEL]), ['linux-7.3'])

    def test_structured_kernel_is_protected_but_external_modules_stay_allowed(self):
        kernel = dict(node(), structuredAttrs={'pname': 'linux', 'preferLocalBuild': True})
        graph = {ROOT: node(KERNEL, VENDOR), KERNEL: kernel, VENDOR: node(src='nvidia-source')}
        self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=ROOT,
                                          expected=[KERNEL, VENDOR]), ['linux-7.3'])
        graph.pop(KERNEL)
        graph[ROOT] = node(VENDOR)
        self.assertEqual(prebuilt.compiles(shown(graph), list(graph), root=ROOT, expected=[VENDOR]), [])

    def test_versioned_nix_metadata_cannot_hide_an_uncached_dependency(self):
        # Captured installed Nix format: version 4 wraps the graph, uses
        # store basenames, moves inputDrvs to inputs.drvs, and moves a
        # structured-attributes package's attributes (here opencode 2.2.5,
        # missed on 2026-11-04) from env to structuredAttrs.
        structured = store('p', 'opencode-2.2.5.drv')
        source = dict(GRAPH, **{CONFIG: node(HELLO, structured), structured: {
            'outputs': {'out': {'path': store('q', 'opencode-2.2.5')}}, 'inputDrvs': {},
            'env': {'out': store('q', 'opencode-2.2.5')}, 'structuredAttrs': {'src': store('x', 'source')}}})
        graph = {}
        for path, info in source.items():
            value = dict(info)
            value['inputs'] = {'drvs': {Path(key).name: {'outputs': ['out'], 'dynamicOutputs': {}}
                                       for key in value.pop('inputDrvs')}}
            value['outputs'] = {'out': {'path': Path(info['outputs']['out']['path']).name}}
            graph[Path(path).name] = value
        def run(*args, **kwargs):
            return json.dumps({'version': 4, 'derivations': graph})
        self.assertEqual(prebuilt.compiles(run, list(source), root=ROOT, expected=[VENDOR]), ['hello-2.12', 'opencode-2.2.5'])
        self.assertEqual(prebuilt.show(run, [ROOT])[ROOT]['outputs']['out']['path'], store('o', 'out'))

    def test_missing_or_malformed_metadata_never_passes_as_prebuilt(self):
        malformed = dict(GRAPH[ROOT], structuredAttrs='{}')
        for data in ({}, {'version': 4, 'derivations': []}, {ROOT: {}}, [], {ROOT: malformed}):
            with self.subTest(data=data), self.assertRaises(Failure):
                prebuilt.compiles(lambda *args, **kwargs: json.dumps(data), [ROOT], root=ROOT)

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
        self.assertEqual(status['inputs']['nixpkgs']['rev'], lifecycle.REV_NEW)
        self.assertEqual(status['baseline'], self.sentinel)
        self.assertEqual(lifecycle.config_digest(self.config), self.sentinel)
        builds = [c for c in self.runner.calls if c[:2] == ('nix', 'build') and '--dry-run' not in c]
        self.assertEqual(builds, [], 'the full build never starts')

    def test_expected_local_builds_pass(self):
        self.plan([HELLO])
        record = self.engine.stage('upstream')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')
        self.assertIsNone(read(self.engine.status_path)['notPrebuilt'])
        self.assertTrue(record['reviewToken'])

    def kernel_plan(self, pname='linux'):
        self.plan([HELLO])
        original = self.engine.run
        def run(*args, **kwargs):
            if args[:3] == ('nix', 'derivation', 'show'):
                return shown({ROOT: node(HELLO), HELLO: node(pname=pname, preferLocalBuild='1')})(*args)
            return original(*args, **kwargs)
        run.observer = None
        run.log = None
        self.engine.run = run

    def test_kernel_build_is_refused_before_any_build_even_when_expected(self):
        self.kernel_plan()
        with self.assertRaises(NotPrebuilt):
            self.engine.stage('upstream')
        builds = [c for c in self.runner.calls if c[:2] == ('nix', 'build') and '--dry-run' not in c]
        self.assertEqual(builds, [])
        self.assertEqual(prebuilt.waiting_packages(read(self.engine.status_path)), ['hello-2.12'])

    def test_personal_configuration_preview_also_refuses_kernel_compile(self):
        self.kernel_plan()
        with self.assertRaisesRegex(NotPrebuilt, 'would compile a Linux kernel'):
            self.engine.stage('local')
        builds = [c for c in self.runner.calls if c[:2] == ('nix', 'build') and '--dry-run' not in c]
        self.assertEqual(builds, [])
        self.assertEqual(lifecycle.config_digest(self.config), self.sentinel)
        status = read(self.engine.status_path)
        self.assertEqual(status['changeKind'], 'configuration')
        self.assertEqual(prebuilt.waiting_packages(status), [])
        self.assertEqual(status['phase'], 'Staging failed; working system retained')
        self.assertIn('would compile a Linux kernel', status['error'])
        self.assertNotIn('after NixOS', status['retry'])

    def test_personal_image_rebuild_is_refused_before_building_or_changing_locks(self):
        self.kernel_plan(pname='linux-image')
        locked = (self.config / 'flake.lock').read_bytes()
        with self.assertRaisesRegex(NotPrebuilt, 'would compile a Linux kernel'):
            self.engine.stage('local')
        self.assertEqual((self.config / 'flake.lock').read_bytes(), locked)
        self.assertEqual(lifecycle.config_digest(self.config), self.sentinel)
        self.assertFalse(any(call[:2] == ('nix', 'build') and '--dry-run' not in call for call in self.runner.calls))
        self.assertEqual(prebuilt.waiting_packages(read(self.engine.status_path)), [])

    def test_personal_configuration_previews_keep_other_package_build_choices(self):
        self.plan([])
        self.engine.stage('local')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')


class Waiting(unittest.TestCase):
    def setUp(self):
        self.status = {'state': 'failed', 'changeKind': 'update', 'notPrebuilt': ['opencode-2.2.5'], 'inputs': {
            'nixpkgs': {'rev': 'nixpkgs-revision'}, 'cybexos': {'rev': 'cybexos-revision'}}}
        self.sources = {'upstream': {'state': 'available', 'available': 'nixpkgs-revision'},
                        'cybexos': {'state': 'current'}}

    def test_only_a_typed_prebuilt_refusal_is_waiting(self):
        self.assertEqual(prebuilt.waiting_packages(self.status), ['opencode-2.2.5'])
        for names in (None, [], 'opencode', [None], ['']):
            self.assertEqual(prebuilt.waiting_packages(self.status | {'notPrebuilt': names}), [])
        for state in ('ready', 'activating', 'interrupted', 'recovery-failed'):
            self.assertEqual(prebuilt.waiting_packages(self.status | {'state': state}), [])

    def test_a_hold_matches_exact_sources_and_never_hides_new_ones(self):
        self.assertEqual(prebuilt.hold_target(self.status, self.sources), 'same')
        for name, source in (('upstream', {'state': 'available', 'available': 'new-nixpkgs'}),
                             ('cybexos', {'state': 'available', 'revision': 'new-cybexos'}),
                             ('firmware', {'state': 'available'})):
            self.assertEqual(prebuilt.hold_target(self.status, self.sources | {name: source}), 'changed')
        self.assertEqual(prebuilt.hold_target(self.status | {'inputs': {}}, self.sources), 'unknown')
        self.assertEqual(prebuilt.hold_target(self.status, {}), 'unknown')
        self.assertEqual(prebuilt.hold_target(self.status | {'notPrebuilt': []}, self.sources), '')

    def test_personal_failures_never_become_update_holds(self):
        for kind in ('configuration', 'region', 'maintenance', 'software', None):
            status = self.status | {'changeKind': kind}
            with self.subTest(kind=kind):
                self.assertEqual(prebuilt.waiting_packages(status), [])
                self.assertEqual(prebuilt.hold_target(status, self.sources), '')


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


class UnchangedBoot(unittest.TestCase):
    """An update that leaves starting the computer and logging in alone."""
    def setUp(self):
        lifecycle.EngineTests.setUp(self)

    def generation(self, base, name, changes=None):
        """A generation's boot path as files: (relative path, content) changes apply."""
        system = base / name
        files = {'kernel-params': 'quiet', 'etc/systemd/system/display-manager.service': '[Service]\nExecStart=sddm',
                 'etc/sddm.conf.d/00-nixos.conf': '[General]\nSessionDir=/nix/store/sessions',
                 'etc/pam.d/login': 'auth unix', 'etc/pam.d/sddm': 'auth unix', 'etc/pam.d/sddm-greeter': 'auth permit',
                 'etc/pam.d/sddm-autologin': 'auth requisite pam_exec.so quiet /nix/store/check/bin/check',
                 'desktop/bin/.cybexos-session-wrapped': 'exec Hyprland', 'desktop/bin/cybexos-session': 'wrapper ' + name}
        files.update(changes or {})
        for relative, value in files.items():
            if value is None:
                continue
            path = system / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
        for link, target in (('kernel', base / 'kernel-image'), ('initrd', base / (files.get('@initrd') or 'initrd-image'))):
            target.touch()
            (system / link).symlink_to(target)
        (system / 'sw/bin').mkdir(parents=True)
        (system / 'sw/bin/cybexos-session').symlink_to(system / 'desktop/bin/cybexos-session')
        return str(system)

    def test_only_an_unchanged_kernel_image_options_login_screen_and_session_qualify(self):
        cases = {
            'the session wrapper alone': ({'desktop/bin/cybexos-session': 'another release wrapper'}, True),
            'boot options': ({'kernel-params': 'quiet video=DP-2:d'}, False),
            'early-boot image': ({'@initrd': 'other-initrd-image'}, False),
            'automatic-login check': ({'etc/pam.d/sddm-autologin': 'auth requisite pam_exec.so quiet /nix/store/new/bin/check'}, False),
            'password login': ({'etc/pam.d/login': 'auth unix nullok'}, False),
            'login screen configuration': ({'etc/sddm.conf.d/00-nixos.conf': '[General]\nSessionDir=/nix/store/other'}, False),
            'another configuration file': ({'etc/sddm.conf.d/10-theme.conf': '[Theme]'}, False),
            'login screen unit': ({'etc/systemd/system/display-manager.service': '[Service]\nExecStart=other'}, False),
            'session script': ({'desktop/bin/.cybexos-session-wrapped': 'exec Hyprland --verbose'}, False),
        }
        for name, (changes, expected) in cases.items():
            with self.subTest(change=name), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                record = {'changeKind': 'update', 'system': self.generation(base, 'new', changes),
                          'previousSystem': self.generation(base, 'old')}
                self.assertEqual(self.engine.boot_unchanged(record), expected)
                if expected:
                    for kind in ('configuration', 'software', 'region', 'maintenance'):
                        self.assertFalse(self.engine.boot_unchanged(record | {'changeKind': kind}), kind)
                    firmware = {'devices': [{'id': 'bios', 'needsReboot': True}]}
                    self.assertFalse(self.engine.boot_unchanged(record | {'firmware': firmware}), 'firmware restarts')
                    self.assertTrue(self.engine.boot_unchanged(record | {'firmware': {'devices': []}}))
        self.assertFalse(self.engine.boot_unchanged({'changeKind': 'update', 'system': '/missing/new',
                                                     'previousSystem': '/missing/old'}))

    def test_update_with_an_unchanged_boot_path_needs_no_restart(self):
        record = self.engine.stage('upstream')
        with patch.object(type(self.engine), 'boot_unchanged', return_value=True):
            self.engine.apply(record['id'], record['reviewToken'])
        calls = self.runner.calls
        self.assertIn(('cybexos-boot-trial', '--commit', lifecycle.NEW_SYSTEM), calls)
        self.assertNotIn(('cybexos-boot-trial', lifecycle.NEW_SYSTEM, lifecycle.OLD_SYSTEM), calls)
        status = read(self.engine.status_path)
        self.assertEqual((status['state'], status['restart']), ('done', 'None'))
        self.assertIn('no restart is needed', status['phase'])
        self.assertFalse(self.engine.pending_path.exists())
        self.assertTrue((self.engine.tx(record['id']) / 'good.json').is_file())

    def test_update_that_changes_the_boot_path_keeps_its_trial_boot(self):
        record = self.engine.stage('upstream')
        self.engine.apply(record['id'], record['reviewToken'])
        self.assertIn(('cybexos-boot-trial', lifecycle.NEW_SYSTEM, lifecycle.OLD_SYSTEM), self.runner.calls)
        self.assertEqual(read(self.engine.status_path)['state'], 'awaiting-boot')


if __name__ == '__main__':
    unittest.main()
