"""Software request tests through the actual staged engine, with command fixtures."""
import json
from pathlib import Path
import re
import shutil
import unittest
from unittest.mock import patch

import test_lifecycle as lifecycle
from cybexos.common import CommandFailure, Failure, atomic, read
from cybexos.engine import config_digest, copy_config
from cybexos import software


class SoftwareTests(unittest.TestCase):
    setUp = lifecycle.EngineTests.setUp

    def prepare_machine(self):
        atomic(self.config / 'local/software.json', {'schema':1, 'packages':[]})
        shutil.rmtree(self.base / 'deployed')
        copy_config(self.config, self.base / 'deployed')

    def test_staged_install_apply_and_rollback_preserve_personal_configuration_and_locks(self):
        self.prepare_machine()
        baseline = config_digest(self.working)
        locked = (self.config / 'flake.lock').read_bytes()
        record = self.engine.stage('local', software={'packages':['hello'], 'previous':[]}, request_id='c' * 32)
        self.assertEqual(config_digest(self.working), baseline)
        self.assertEqual(read(self.engine.tx(record['id']) / 'config/local/software.json')['packages'], ['hello'])
        self.assertEqual((self.engine.tx(record['id']) / 'config/flake.lock').read_bytes(), locked)
        self.assertFalse(any(call[:3] == ('nix', 'flake', 'update') for call in self.runner.calls))
        self.assertEqual(record['requestId'], 'c' * 32)
        self.engine.apply(record['id'], record['reviewToken'])
        self.assertEqual(read(self.working / 'local/software.json')['packages'], ['hello'])
        self.assertEqual((self.working / 'local/personal.nix').read_text(), '# packages, VPN, services sentinel\n{}')
        self.engine.rollback(record['id'])
        self.assertEqual(read(self.working / 'local/software.json')['packages'], [])
        self.assertEqual((self.working / 'flake.lock').read_bytes(), locked)

    def test_stale_choices_unknown_schemas_and_expression_injection_are_rejected(self):
        self.prepare_machine()
        baseline = config_digest(self.working)
        for value in ['hello; import /tmp/evil', 'a..b', '../hello', '"hello"', 'a/${builtins.abort "oops"}']:
            with self.subTest(value=value), self.assertRaises(Failure):
                self.engine.stage('local', software={'packages':[value], 'previous':[]})
        with self.assertRaises(Failure):
            self.engine.stage('local', software={'packages':['hello'], 'previous':['git']})
        self.assertEqual(config_digest(self.working), baseline)
        atomic(self.config / 'local/software.json', {'schema':2, 'packages':[]})
        with self.assertRaises(Failure): software.prepare(self.config, {'packages':[], 'previous':[]})

    def test_catalogue_uses_effective_machine_packages_offline_and_invalidates_on_personal_edits(self):
        self.prepare_machine()
        installed = self.base / 'inventory.json'
        atomic(installed, {'schema':1, 'selected':[], 'packages':[]})
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            return json.dumps([{'attribute':'hello', 'name':'hello', 'version':'1', 'description':'A friendly application'},
                               {'attribute':'python3Packages.foo', 'name':'foo', 'version':'2', 'description':'Python tool'}])
        args = dict(config=self.working, installed=installed, cache=self.base / 'cache', run=run)
        found = software.search('friendly', **args)
        self.assertEqual([p['attribute'] for p in found['results']], ['hello'])
        software.search('python', **args)
        self.assertEqual(len(calls), 1)
        self.assertIn('--offline', calls[0]); self.assertIn('--no-update-lock-file', calls[0])
        self.assertIn('software-catalogue.nix', calls[0][-1])
        (self.config / 'local/personal.nix').write_text('# personal overlay changed\n{}')
        software.search('hello', **args)
        self.assertEqual(len(calls), 2)

    def test_catalogue_refuses_a_configuration_changed_during_indexing(self):
        self.prepare_machine()
        def run(*args, **kwargs):
            (self.config / 'local/personal.nix').write_text('changed')
            return '[]'
        with self.assertRaisesRegex(Failure, 'changed while indexing'):
            software.search(config=self.config, cache=self.base / 'cache', run=run)

    def test_supervised_requests_keep_distinct_payloads_and_report_worker_crashes(self):
        from unittest.mock import patch
        from types import SimpleNamespace
        from cybexos.cli import enqueue, request_status
        state = self.base / 'requests-state'
        with patch('cybexos.cli.subprocess.run'):
            one = enqueue(state, 'software', {'packages':['hello'], 'previous':[]})
            two = enqueue(state, 'software', {'packages':['git'], 'previous':[]})
        self.assertNotEqual(one['requestId'], two['requestId'])
        self.assertEqual(read(state / 'requests' / (one['requestId'] + '.json'))['packages'], ['hello'])
        path = state / 'request-status' / (one['requestId'] + '.json')
        atomic(path, read(path) | {'createdAt':0, 'state':'running'})
        result = SimpleNamespace(returncode=0, stdout='ActiveState=failed\nResult=signal\n')
        with patch('cybexos.cli.subprocess.run', return_value=result):
            self.assertEqual(request_status(one['requestId'], state)['state'], 'failed')
        with self.assertRaises(Failure): request_status('../secret', state)


def store(letter, name):
    return '/nix/store/' + letter * 32 + '-' + name


SHIPPED = {'schema': 1, 'nixpkgs': 'abc', 'featured': ['gimp'],
    'categories': [{'id': 'create', 'name': 'Create', 'summary': 'Graphics', 'icon': 'palette', 'color': '#ff9f5a',
                    'subcategories': [{'id': 'photo', 'name': 'Photo'}]}],
    'profiles': [{'id': 'graphics', 'name': 'Graphics & Design', 'apps': ['gimp', 'krita'], 'downloadBytes': 5}],
    'apps': [{'id': 'gimp', 'attribute': 'gimp', 'name': 'GIMP', 'category': 'create', 'subcategory': 'photo',
              'free': True, 'desktopIds': ['gimp.desktop'], 'downloadBytes': 1},
             {'id': 'firefox', 'attribute': 'firefox', 'name': 'Firefox', 'category': 'utilities',
              'subcategory': 'web', 'free': True, 'desktopIds': ['firefox.desktop'], 'downloadBytes': 0},
             {'id': 'okular', 'attribute': 'kdePackages.okular', 'name': 'Okular', 'category': 'work',
              'subcategory': 'office', 'free': True, 'desktopIds': ['org.kde.okular.desktop'], 'downloadBytes': 2},
             {'id': 'spotify', 'attribute': 'spotify', 'name': 'Spotify', 'category': 'media',
              'subcategory': 'audio', 'free': False, 'desktopIds': ['spotify.desktop'], 'downloadBytes': None},
             {'id': 'krita', 'attribute': 'krita', 'name': 'Krita', 'category': 'create', 'subcategory': 'photo',
              'free': True, 'desktopIds': ['org.kde.krita.desktop'], 'downloadBytes': 3},
             {'id': 'BAD', 'attribute': 'x; abort', 'name': 'Injected'}]}

METADATA = {'gimp': {'pname': 'gimp', 'version': '3.0.6', 'unfree': False, 'available': True, 'broken': False},
            'firefox': {'pname': 'firefox', 'version': '144.0', 'unfree': False, 'available': True, 'broken': False},
            'kdePackages.okular': {'pname': 'okular', 'version': '25.08.2', 'unfree': False, 'available': True, 'broken': False},
            'spotify': {'pname': 'spotify', 'version': '1.2.74', 'unfree': True, 'available': False, 'broken': False},
            'krita': {'pname': 'krita', 'version': '5.2.13', 'unfree': False, 'available': True, 'broken': False}}


class Nix:
    """`nix eval` of software-catalogue.nix, `nix build --dry-run` and `nix derivation show`."""
    def __init__(self, metadata=METADATA, allow_unfree=False, build='', graph=None, fail=None):
        self.metadata, self.allow_unfree, self.build, self.graph, self.fail = metadata, allow_unfree, build, graph or {}, fail
        self.calls = []

    def __call__(self, *args, **kwargs):
        args = tuple(map(str, args))
        self.calls.append((args, kwargs))
        if self.fail and self.fail(args):
            raise CommandFailure(args[0], 1, 'private diagnostics')
        if args[:2] == ('nix', 'eval'):
            expression = args[-1]
            names = re.search(r'attributes = \[ (.*) \];', expression)[1].split()
            derivations = 'derivations = true' in expression
            rows = []
            for name in map(json.loads, names):
                meta = self.metadata.get(name)
                row = {'attribute': name, 'exists': meta is not None} | (meta or {})
                if meta is not None and derivations:
                    row['drvPath'] = store('d', name + '.drv') if meta['available'] else None
                rows.append(row)
            return json.dumps({'allowUnfree': self.allow_unfree, 'packages': rows})
        if args[:3] == ('nix', 'build', '--dry-run'):
            self.assert_diagnostics = kwargs.get('diagnostics')
            return self.build
        if args[:3] == ('nix', 'derivation', 'show'):
            return json.dumps({path: self.graph[path] for path in args[3:] if path in self.graph})
        raise AssertionError('unexpected command ' + repr(args))

    def count(self, *prefix):
        return sum(call[0][:len(prefix)] == prefix for call in self.calls)


def compile_step(*inputs):
    # A package built from its own source (`prebuilt.kind`).
    return {'outputs': {'out': {'path': store('o', 'out')}}, 'env': {'src': store('s', 'source')},
            'inputDrvs': {path: {} for path in inputs}}


class CatalogueAndCheckTests(unittest.TestCase):
    setUp = lifecycle.EngineTests.setUp

    def machine(self, packages, selected=(), desired=()):
        atomic(self.config / 'local/software.json', {'schema': 1, 'packages': sorted(desired)})
        installed = self.base / 'inventory.json'
        atomic(installed, {'schema': 1, 'selected': sorted(selected), 'packages': packages})
        shipped = self.base / 'shipped'
        atomic(shipped / 'catalogue.json', SHIPPED)
        return dict(config=self.config, installed=installed, source=shipped, cache=self.base / 'cache')

    def test_catalogue_reports_installed_apps_by_owner_version_and_unfree_policy(self):
        apps = {store('a', 'gimp-3.0.6'): [{'id': 'gimp.desktop', 'name': 'GIMP', 'icon': 'gimp'}],
                store('b', 'firefox-144.0'): [{'id': 'firefox.desktop', 'name': 'Firefox', 'icon': 'firefox'}],
                store('c', 'okular-25.08.2'): [{'id': 'org.kde.okular.desktop', 'name': 'Okular', 'icon': 'okular'}]}
        packages = [
            {'path': store('a', 'gimp-3.0.6'), 'name': 'gimp', 'version': '3.0.6', 'attributes': ['gimp'],
             'origins': ['software'], 'managedElsewhere': False},
            {'path': store('b', 'firefox-144.0'), 'name': 'firefox', 'version': '144.0', 'attributes': [],
             'origins': ['cybexos'], 'managedElsewhere': True},
            {'path': store('c', 'okular-25.08.2'), 'name': 'okular', 'version': '25.08.2', 'attributes': [],
             'origins': ['personal'], 'managedElsewhere': True},
            # NixOS modules Cybex OS enables count as Cybex OS's own.
            {'path': store('e', 'coreutils-9.8'), 'name': 'coreutils', 'version': '9.8', 'attributes': [],
             'origins': ['nixos'], 'managedElsewhere': True}]
        run = Nix()
        with patch.object(software, 'desktop_entries', side_effect=lambda path, limit=24: apps.get(path, [])):
            result = software.catalogue(**self.machine(packages, selected=['gimp'], desired=['gimp', 'krita']), run=run)
        apps = {app['id']: app for app in result['apps']}
        self.assertNotIn('BAD', apps, 'catalogue entries with invalid attributes never reach Nix or the shell')
        self.assertEqual({key: apps['gimp'][key] for key in ('installed', 'owner', 'version', 'selected', 'unavailable')},
                         {'installed': True, 'owner': 'software', 'version': '3.0.6', 'selected': True, 'unavailable': ''})
        self.assertEqual((apps['firefox']['owner'], apps['okular']['owner']), ('cybexos', 'personal'))
        self.assertEqual(apps['okular']['installedVersion'], '25.08.2')
        self.assertEqual((apps['krita']['installed'], apps['krita']['desired']), (False, True))
        self.assertEqual(apps['spotify']['unavailable'], 'unfree', 'unfree apps are unavailable while proprietary apps are off')
        self.assertEqual({row['name']: row['owner'] for row in result['packages']},
                         {'gimp': 'software', 'firefox': 'cybexos', 'okular': 'personal', 'coreutils': 'cybexos'})
        self.assertEqual(result['packages'][0]['apps'][0]['id'], 'gimp.desktop')
        self.assertTrue(result['configurationChanged'])
        self.assertEqual(result['icons'], str(self.base / 'shipped/icons'))
        self.assertEqual(result['categories'][0]['id'], 'create')
        eval_args = run.calls[0][0]
        self.assertIn('--offline', eval_args); self.assertIn('--no-update-lock-file', eval_args)
        self.assertIn('software-catalogue.nix', eval_args[-1])
        self.assertIn('"kdePackages.okular"', eval_args[-1]); self.assertNotIn('abort', eval_args[-1])
        self.assertIn('derivations = false', eval_args[-1])

    def test_catalogue_metadata_is_cached_per_configuration_identity(self):
        args = self.machine([])
        run = Nix(allow_unfree=True, metadata=METADATA | {'spotify': METADATA['spotify'] | {'available': True}})
        first = software.catalogue(**args, run=run)
        self.assertEqual({app['id']: app['unavailable'] for app in first['apps']}['spotify'], '')
        self.assertTrue(first['allowUnfree'])
        software.catalogue(**args, run=run)
        self.assertEqual(run.count('nix', 'eval'), 1)
        (self.config / 'local/personal.nix').write_text('# personal overlay changed\n{}')
        software.catalogue(**args, run=run)
        self.assertEqual(run.count('nix', 'eval'), 2)
        (self.base / 'cache/apps.json').write_text('{"identity": 1, "packages": [')
        software.catalogue(**args, run=run)
        self.assertEqual(run.count('nix', 'eval'), 3, 'a damaged cache is rebuilt, not trusted')

    def test_catalogue_matches_apps_from_older_inventories_and_by_package_name(self):
        packages = [{'path': store('b', 'firefox-144.0'), 'name': 'firefox', 'version': '144.0', 'attributes': [],
                     'managedElsewhere': True},
                    {'path': store('a', 'krita-5.2.13'), 'name': 'krita', 'version': '5.2.13', 'attributes': ['krita'],
                     'managedElsewhere': False}]
        with patch.object(software, 'desktop_entries', return_value=[]):
            result = software.catalogue(**self.machine(packages, selected=['krita'], desired=['krita']), run=Nix())
        apps = {app['id']: app for app in result['apps']}
        self.assertEqual((apps['firefox']['installed'], apps['firefox']['owner']), (True, 'cybexos'))
        self.assertEqual(apps['krita']['owner'], 'software')
        self.assertFalse(result['configurationChanged'])

    def test_catalogue_refuses_unsupported_shipped_data(self):
        args = self.machine([])
        atomic(Path(args['source']) / 'catalogue.json', {'schema': 2, 'apps': []})
        with self.assertRaisesRegex(Failure, 'catalogue'):
            software.catalogue(**args, run=Nix())

    def test_desktop_entries_list_visible_applications_only(self):
        root = self.base / 'store'
        path = root / ('a' * 32 + '-gimp-3.0.6')
        applications = path / 'share/applications'
        applications.mkdir(parents=True)
        (applications / 'gimp.desktop').write_text('[Desktop Entry]\nType=Application\nName=GIMP\nIcon=gimp\n'
                                                   '[Desktop Action new]\nName=New window\n')
        (applications / 'hidden.desktop').write_text('[Desktop Entry]\nType=Application\nName=Hidden\nNoDisplay=true\n')
        (applications / 'link.desktop').write_text('[Desktop Entry]\nType=Link\nName=Website\n')
        with patch.object(software, 'STORE_PATH', re.compile(re.escape(str(root)) + r'/[a-z0-9]{32}-[^/]+')):
            self.assertEqual(software.desktop_entries(str(path)), [{'id': 'gimp.desktop', 'name': 'GIMP', 'icon': 'gimp'}])
        self.assertEqual(software.desktop_entries(str(path)), [], 'only store paths are read')
        self.assertEqual(software.desktop_entries('/etc/../nix/store/x'), [])

    def test_check_finds_compiles_but_allows_vendor_downloads_and_cached_packages(self):
        gimp, krita, spotify = (store('d', name + '.drv') for name in ('gimp', 'krita', 'spotify'))
        source = store('s', 'spotify-src.drv')
        wrapper = store('w', 'krita-wrapper.drv')
        krita_metadata = METADATA['krita']
        run = Nix(allow_unfree=True,
            metadata=METADATA | {'spotify': METADATA['spotify'] | {'available': True}},
            build=('these 4 derivations will be built:\n'
                   f'  {krita}\n  {wrapper}\n  {spotify}\n  {source}\n'
                   'these 12 paths will be fetched (40.00 MiB download, 160.00 MiB unpacked):\n'
                   f'  {store("f", "gtk")}\n'),
            graph={krita: {'outputs': {'out': {'path': store('k', 'krita')}}, 'env': {'preferLocalBuild': '1'},
                           'inputDrvs': {wrapper: {}}},
                   wrapper: compile_step(),
                   spotify: compile_step(source),
                   source: {'outputs': {'out': {'path': store('t', 'src'), 'hash': 'abc'}}, 'env': {}, 'inputDrvs': {}}})
        del krita_metadata
        result = software.check(['gimp', 'krita', 'spotify'], config=self.config, run=run)
        self.assertEqual(result['downloadBytes'], 40 * 1024 ** 2)
        self.assertFalse(result['prebuilt'])
        self.assertEqual(result['compiles'], ['krita-wrapper'])
        packages = result['packages']
        self.assertEqual((packages['gimp']['state'], packages['gimp']['compiles']), ('prebuilt', []))
        self.assertEqual(packages['krita']['state'], 'compiles')
        self.assertEqual((packages['spotify']['state'], packages['spotify']['vendor']), ('prebuilt', True),
                         'unpacking an unfree vendor download is expected')
        self.assertEqual(packages['gimp']['version'], '3.0.6')
        self.assertEqual(run.count('nix', 'derivation', 'show'), 1, 'one derivation query serves every root')
        build = next(call for call in run.calls if call[0][:3] == ('nix', 'build', '--dry-run'))
        self.assertTrue(build[1].get('diagnostics'))
        self.assertIn('--no-update-lock-file', build[0])
        self.assertNotIn('--offline', build[0], 'the dry run asks the configured caches')
        self.assertEqual([arg for arg in build[0] if '#' in arg],
                         ['path:' + str(self.config.resolve()) + '#nixosConfigurations.cybexos.pkgs.' + name
                          for name in ('gimp', 'krita', 'spotify')])
        self.assertIn('derivations = true', run.calls[0][0][-1])

    def test_check_reports_unavailable_packages_without_a_dry_run(self):
        run = Nix(build='')
        result = software.check(['spotify', 'nonexistent'], config=self.config, run=run)
        self.assertEqual({name: row['reason'] for name, row in result['packages'].items()},
                         {'spotify': 'unfree', 'nonexistent': 'missing'})
        self.assertFalse(result['prebuilt'])
        self.assertEqual(run.count('nix', 'build'), 0)
        everything = software.check(['gimp', 'firefox'], config=self.config, run=Nix(build=''))
        self.assertTrue(everything['prebuilt'])
        self.assertEqual((everything['downloadBytes'], everything['compiles']), (0, []))

    def test_check_validates_attributes_and_keeps_nix_diagnostics_private(self):
        for value in ([], ['hello; import /tmp/evil'], ['a..b'], ['../hello'], ['"x"'], ['a/${builtins.abort "x"}'],
                      ['hello', 'hello'], ['x' * 201], ['p%d' % index for index in range(65)], 'hello', [1]):
            with self.subTest(value=value), self.assertRaises(Failure):
                software.check(value, config=self.config, run=Nix())
        with self.assertRaises(Failure) as failure:
            software.check(['gimp'], config=self.config, run=Nix(fail=lambda args: args[:2] == ('nix', 'build')))
        self.assertIn('internet connection', str(failure.exception))
        self.assertNotIn('private diagnostics', str(failure.exception))
        with self.assertRaisesRegex(Failure, 'package set'):
            software.check(['gimp'], config=self.config, run=Nix(fail=lambda args: args[:2] == ('nix', 'eval')))

    def test_cli_serves_catalogue_and_check(self):
        import io, sys
        from contextlib import redirect_stdout
        from cybexos import cli
        for argv, function, expected in ((['cybex', 'software', 'catalogue'], 'catalogue', ()),
                                         (['cybex', 'software', 'check', 'gimp', 'kdePackages.okular'], 'check',
                                          (['gimp', 'kdePackages.okular'],))):
            output = io.StringIO()
            with self.subTest(argv=argv), patch.object(sys, 'argv', argv), patch.object(cli, 'require_installed'), \
                    patch.object(software, function, return_value={'ok': True}) as called, redirect_stdout(output):
                cli.main()
            called.assert_called_once_with(*expected)
            self.assertEqual(json.loads(output.getvalue()), {'ok': True})
