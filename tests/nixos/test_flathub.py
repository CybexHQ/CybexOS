"""Flathub apps for one account, with Flatpak, systemd and Flathub's API as fixtures."""
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lifecycle'))
from cybexos import flathub  # noqa: E402
from cybexos.common import CommandFailure, Failure, atomic, read  # noqa: E402

ICON = 'https://dl.flathub.org/media//org/mozilla/thunderbird/x/icons/128x128/org.mozilla.thunderbird.png'
SHOT = 'https://dl.flathub.org/media/org/mozilla/thunderbird/x/screenshots/image-1_752x470@1.png'
HITS = [
    {'app_id': 'org.mozilla.thunderbird', 'type': 'desktop-application', 'name': 'Thunderbird',
     'summary': 'Email &amp; chat', 'developer_name': 'MZLA', 'icon': ICON, 'project_license': 'MPL-2.0',
     'is_free_license': True, 'verification_verified': True, 'installs_last_month': 29077, 'arches': ['x86_64', 'aarch64']},
    {'app_id': 'com.spotify.Client', 'type': 'desktop-application', 'name': 'Spotify', 'summary': 'Music',
     'icon': 'https://tracker.example.com/spotify.png', 'is_free_license': False, 'arches': ['x86_64']},
    {'app_id': 'org.example.ArmOnly', 'type': 'desktop-application', 'name': 'Arm', 'arches': ['aarch64']},
    {'app_id': 'org.freedesktop.Platform', 'type': 'runtime', 'name': 'Runtime'},
    {'app_id': 'bad id; rm -rf', 'type': 'desktop-application', 'name': 'Evil'},
]
APPSTREAM = {
    'id': 'org.mozilla.thunderbird', 'name': 'Thunderbird', 'summary': 'Email', 'developer_name': 'MZLA',
    'project_license': 'MPL-2.0', 'is_free_license': True, 'icon': ICON,
    'description': '<p>Thunderbird is a mail client.</p><ul><li>Calendars</li><li>Chat <b>and</b> news</li></ul>'
                   '<p>Packaged on Flathub by its developers.</p>',
    'releases': [{'version': '159.0', 'type': 'stable'}], 'urls': {'homepage': 'https://www.thunderbird.net/'},
    'screenshots': [{'sizes': [{'src': SHOT, 'width': '752'}, {'src': 'http://insecure.example/a.png', 'width': '1248'}]}],
    'branding': [{'type': 'primary', 'value': '#0a84ff', 'scheme_preference': 'light'},
                 {'type': 'primary', 'value': 'red', 'scheme_preference': 'dark'}],
}
SUMMARY = {'download_size': 126212325, 'installed_size': 343719424, 'arches': ['x86_64'],
           'metadata': {'runtimeName': 'Freedesktop Platform version 25.08',
                        'permissions': {'shared': ['network', 'ipc'], 'devices': ['all'],
                                        'filesystems': ['xdg-download', 'home'], 'sockets': ['wayland', 'x11']}}}


class Flatpak:
    """`flatpak` and its installations, as the commands report them."""
    def __init__(self):
        self.calls = []
        self.apps = []          # (id, name, version, installation)
        self.remotes = []
        self.updates = []
        self.fail = {}

    def __call__(self, *args, **kwargs):
        self.calls.append(args)
        if args[0] != 'flatpak':
            raise AssertionError(args)
        verb = args[1]
        if verb in self.fail:
            raise CommandFailure('flatpak', 1, self.fail[verb])
        if verb == 'list':
            return ''.join(f'{i}\t{n}\t{v}\tstable\tflathub\t{where}\n' for i, n, v, where in self.apps)
        if verb == 'remotes':
            return ''.join(name + '\n' for name in self.remotes)
        if verb == 'remote-add':
            if 'flathub' not in self.remotes:
                self.remotes.append('flathub')
            return ''
        if verb == 'remote-ls':
            return ''.join(f'{i}\t{v}\n' for i, v in self.updates)
        if verb == 'install':
            for app in args[args.index('flathub') + 1:]:
                self.apps.append((app, app.rsplit('.', 1)[-1], '1.0', 'user'))
            return 'Installing app/' + args[-1]
        if verb == 'uninstall':
            if '--unused' in args:
                return ''
            gone = [app for app in self.apps if app[0] in args and app[3] == 'user']
            if not gone:
                raise CommandFailure('flatpak', 1, 'error: No installed refs found for ‘x’')
            self.apps = [app for app in self.apps if app not in gone]
            return ''
        if verb == 'update':
            return ''
        raise AssertionError(args)


def api(routes):
    calls = []
    def get(url, body=None):
        calls.append((url, body))
        key = url.removeprefix(flathub.API)
        if key not in routes:
            return None
        value = routes[key]
        if isinstance(value, Exception):
            raise value
        return value
    get.calls = calls
    return get


class FlathubTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cybexos-flathub-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.state = self.base / 'state'
        self.flatpak = Flatpak()
        self.machine = mock.patch.object(flathub, 'architecture', return_value='x86_64')
        self.machine.start()
        self.addCleanup(self.machine.stop)

    def test_search_keeps_installable_apps_and_type_checks_flathub_answers(self):
        self.flatpak.apps.append(('org.mozilla.thunderbird', 'Thunderbird', '158.0', 'user'))
        get = api({'search': {'hits': HITS, 'totalHits': 5}})
        result = flathub.search('  thunderbird ', run=self.flatpak, get=get, allowed=False)
        self.assertEqual(get.calls, [(flathub.API + 'search', {'query': 'thunderbird', 'hits_per_page': 48, 'page': 1})])
        self.assertEqual([row['id'] for row in result['results']], ['org.mozilla.thunderbird', 'com.spotify.Client'])
        bird, spotify = result['results']
        self.assertEqual((bird['summary'], bird['verified'], bird['installed'], bird['unavailable']), ('Email & chat', True, True, ''))
        self.assertEqual((spotify['icon'], spotify['unavailable'], spotify['installed']), ('', 'unfree', False),
                         'media only from dl.flathub.org; proprietary follows the machine')
        self.assertEqual(flathub.search('spotify', run=self.flatpak, get=api({'search': {'hits': HITS}}),
                                        allowed=True)['results'][1]['unavailable'], '')
        self.assertEqual(flathub.search('', run=self.flatpak, get=get, allowed=True)['results'], [])
        self.assertEqual(len(get.calls), 1, 'an empty query asks nobody')
        with self.assertRaises(Failure):
            flathub.search('x' * 201, run=self.flatpak, get=get)
        with self.assertRaises(Failure):
            flathub.search('mail', run=self.flatpak, get=api({'search': {'hits': 'nope'}}))

    def test_details_reduce_markup_and_summarize_the_sandbox(self):
        get = api({'appstream/org.mozilla.thunderbird': APPSTREAM, 'summary/org.mozilla.thunderbird': SUMMARY,
                   'verification/org.mozilla.thunderbird/status': {'verified': True}})
        value = flathub.details('org.mozilla.thunderbird', run=self.flatpak, get=get, allowed=True)
        self.assertEqual(value['description'], ['Thunderbird is a mail client.', '• Calendars', '• Chat and news',
                                                'Packaged on Flathub by its developers.'])
        self.assertEqual(value['screenshots'], [SHOT])
        self.assertEqual(value['brand'], {'light': '#0a84ff'})
        self.assertEqual((value['version'], value['homepage'], value['verified'], value['downloadBytes']),
                         ('159.0', 'https://www.thunderbird.net/', True, 126212325))
        self.assertEqual(value['permissions'], ['files-home', 'network', 'devices'])
        self.assertEqual((value['supported'], value['installed'], value['unavailable']), (True, None, ''))
        missing = api({})
        with self.assertRaises(Failure):
            flathub.details('org.example.Missing', run=self.flatpak, get=missing)
        for bad in ('org.gimp', '--user.x.y', 'a.b.c/../d'):
            with self.subTest(bad=bad), self.assertRaises(Failure):
                flathub.details(bad, run=self.flatpak, get=get)
        # Verification is optional; an unreachable status endpoint is not a failure.
        get = api({'appstream/org.mozilla.thunderbird': APPSTREAM | {'is_free_license': False},
                   'verification/org.mozilla.thunderbird/status': Failure(flathub.UNREACHABLE)})
        value = flathub.details('org.mozilla.thunderbird', run=self.flatpak, get=get, allowed=False)
        self.assertEqual((value['verified'], value['unavailable'], value['downloadBytes']), (False, 'unfree', 0))

    def test_permissions_name_the_significant_holes(self):
        self.assertEqual(flathub.permissions({'permissions': {'filesystems': ['host:ro'], 'sockets': ['x11'],
                                                              'session-bus': {'talk': ['org.freedesktop.Flatpak']}}}),
                         ['files-all', 'x11', 'host-commands'])
        self.assertEqual(flathub.permissions({'permissions': {'filesystems': ['xdg-music'], 'sockets': ['wayland', 'fallback-x11']}}),
                         ['files-some'])
        self.assertEqual(flathub.permissions({'permissions': 'all'}), [])
        self.assertEqual(flathub.permissions(None), [])

    def test_status_lists_both_installations_without_contacting_flathub(self):
        self.flatpak.apps += [('org.vim.Vim', 'Vim', '9.2', 'user'), ('org.gimp.GIMP', 'GIMP', '3.0', 'system'),
                              ('not an id', 'x', '1', 'user'), ('org.example.Odd', 'Odd', '1', 'elsewhere')]
        value = flathub.status(run=self.flatpak, state=self.state, allowed=True, present=True, on=True)
        self.assertEqual([(row['id'], row['installation']) for row in value['installed']],
                         [('org.gimp.GIMP', 'system'), ('org.vim.Vim', 'user')])
        self.assertEqual((value['enabled'], value['remote'], value['task']), (True, False, None))
        self.assertFalse(any(call[1] in ('remote-ls', 'install') for call in self.flatpak.calls))
        absent = flathub.status(run=self.flatpak, state=self.state, allowed=True, present=False, on=True)
        self.assertEqual((absent['available'], absent['installed']), (False, []))

    def spawned(self):
        spawned = []
        def spawn(argv, **kwargs):
            spawned.append(argv)
        spawn.calls = spawned
        return spawn

    def test_changes_start_a_transient_user_service_and_record_its_result(self):
        spawn = self.spawned()
        started = flathub.start('install', ['org.mozilla.thunderbird'], names={'org.mozilla.thunderbird': 'Thunderbird', 'x': 'y'},
                                run=self.flatpak, state=self.state, allowed=True, spawn=spawn, active=lambda unit: True, on=True)
        task = read(self.state / 'flathub-task.json')
        self.assertEqual((task['state'], task['ids'], task['names']), ('queued', ['org.mozilla.thunderbird'],
                                                                     {'org.mozilla.thunderbird': 'Thunderbird'}))
        argv = spawn.calls[0]
        self.assertEqual(argv[:5], ['systemd-run', '--user', '--collect', '--quiet', '--unit'])
        self.assertEqual(argv[5], f'cybexos-flathub-{started["task"]}.service')
        self.assertEqual(argv[-4:], ['software', 'flathub', 'run', started['task']])
        with self.assertRaisesRegex(Failure, 'already changing'):
            flathub.start('remove', ['org.vim.Vim'], run=self.flatpak, state=self.state, spawn=spawn,
                          active=lambda unit: True, on=True)

        result = flathub.work(started['task'], run=self.flatpak, state=self.state)
        self.assertEqual(result, {'state': 'done', 'error': ''})
        self.assertIn(('flatpak', 'remote-add', '--user', '--if-not-exists', 'flathub', str(flathub.REPOSITORY)),
                      self.flatpak.calls, 'the shipped repository file, never a download')
        self.assertIn(('flatpak', 'install', '--user', '--noninteractive', '-y', '--or-update', 'flathub',
                       'org.mozilla.thunderbird'), self.flatpak.calls)
        self.assertEqual(flathub.current_task(self.state)['state'], 'done')
        with self.assertRaises(Failure):
            flathub.work(started['task'], run=self.flatpak, state=self.state)  # it ran already

        removal = flathub.start('remove', ['org.mozilla.thunderbird'], run=self.flatpak, state=self.state,
                                spawn=spawn, active=lambda unit: True, on=False)
        self.assertEqual(flathub.work(removal['task'], run=self.flatpak, state=self.state)['state'], 'done',
                         'removal stays possible with Flathub turned off')
        self.assertIn(('flatpak', 'uninstall', '--user', '--unused', '--noninteractive', '-y'), self.flatpak.calls)
        again = flathub.start('remove', ['org.mozilla.thunderbird'], run=self.flatpak, state=self.state,
                              spawn=spawn, active=lambda unit: True, on=True)
        self.assertEqual(flathub.work(again['task'], run=self.flatpak, state=self.state)['state'], 'done',
                         'an app that is already gone is removed')

    def test_policy_and_validation_refuse_before_anything_runs(self):
        spawn = self.spawned()
        common = dict(run=self.flatpak, state=self.state, spawn=spawn, active=lambda unit: True)
        with self.assertRaisesRegex(Failure, 'turned off'):
            flathub.start('install', ['org.mozilla.thunderbird'], allowed=True, on=False, **common)
        unfree = api({'appstream/com.spotify.Client': {'id': 'com.spotify.Client', 'is_free_license': False}})
        with self.assertRaisesRegex(Failure, 'Proprietary'):
            flathub.start('install', ['com.spotify.Client'], allowed=False, on=True, get=unfree, **common)
        for action, ids in (('install', []), ('install', ['--system.evil.App']), ('install', ['org.a.B', 'org.a.B']),
                            ('downgrade', ['org.a.B']), ('remove', ['org.gimp'])):
            with self.subTest(action=action, ids=ids), self.assertRaises(Failure):
                flathub.start(action, ids, allowed=True, on=True, **common)
        self.assertEqual(spawn.calls, [])
        self.assertIsNone(read(self.state / 'flathub-task.json'))
        updates = flathub.start('update', [], allowed=True, on=True, **common)
        self.assertTrue(updates['accepted'], 'update with no IDs updates everything')
        with self.assertRaises(Failure):
            flathub.work('not-a-task', run=self.flatpak, state=self.state)

    def test_failures_are_explained_and_diagnostics_stay_private(self):
        spawn = self.spawned()
        self.flatpak.fail['install'] = 'error: While pulling app/x: Could not resolve hostname dl.flathub.org secret-token'
        started = flathub.start('install', ['org.mozilla.thunderbird'], run=self.flatpak, state=self.state,
                                allowed=True, spawn=spawn, active=lambda unit: True, on=True)
        result = flathub.work(started['task'], run=self.flatpak, state=self.state)
        self.assertEqual(result, {'state': 'failed', 'error': flathub.UNREACHABLE})
        self.assertNotIn('secret-token', json.dumps(read(self.state / 'flathub-task.json')))
        self.assertIn('space', flathub.explain('install', 'No space left on device'))
        self.assertIn("doesn't offer", flathub.explain('install', 'error: Nothing matches org.x.Y in remote flathub'))
        self.assertEqual(flathub.explain('update', 'weird'), "Flathub couldn't update your apps. Try again.")

    def test_a_worker_that_died_reads_as_failed_and_frees_the_next_change(self):
        now = time.time()
        atomic(self.state / 'flathub-task.json', {'schema': 1, 'id': 'a' * 32, 'action': 'install', 'ids': ['org.vim.Vim'],
                                                  'names': {}, 'state': 'running', 'error': '', 'unit': 'u.service',
                                                  'createdAt': now - 60, 'updatedAt': now - 60})
        self.assertEqual(flathub.current_task(self.state, active=lambda unit: True)['state'], 'running')
        self.assertEqual(flathub.current_task(self.state, active=lambda unit: None)['state'], 'running',
                         'an unknown unit state is not a failure')
        self.assertEqual(flathub.current_task(self.state, active=lambda unit: False)['state'], 'failed')
        spawn = self.spawned()
        flathub.start('install', ['org.vim.Vim'], run=self.flatpak, state=self.state, allowed=True, spawn=spawn,
                      active=lambda unit: False, on=True)
        self.assertEqual(len(spawn.calls), 1)

    def test_a_service_that_cannot_start_is_recorded(self):
        def spawn(argv, **kwargs):
            raise OSError('no user manager')
        with self.assertRaises(Failure):
            flathub.start('install', ['org.vim.Vim'], run=self.flatpak, state=self.state, allowed=True, spawn=spawn,
                          active=lambda unit: True, on=True)
        self.assertEqual(read(self.state / 'flathub-task.json')['state'], 'failed')

    def test_updates_compare_this_accounts_apps_with_flathub(self):
        self.flatpak.apps += [('org.vim.Vim', 'Vim', '9.1', 'user'), ('org.gimp.GIMP', 'GIMP', '3.0', 'system')]
        self.flatpak.updates = [('org.vim.Vim', '9.2'), ('org.gimp.GIMP', '3.1'), ('org.freedesktop.Platform', '25.08')]
        self.assertEqual(flathub.updates(run=self.flatpak)['updates'],
                         [{'id': 'org.vim.Vim', 'name': 'Vim', 'icon': '', 'before': '9.1', 'after': '9.2'}])
        self.flatpak.fail['remote-ls'] = 'Could not resolve host'
        with self.assertRaisesRegex(Failure, 'reached'):
            flathub.updates(run=self.flatpak)
        self.flatpak.apps = []
        self.assertEqual(flathub.updates(run=self.flatpak), {'updates': []}, 'nothing installed asks nobody')


if __name__ == '__main__':
    unittest.main()
