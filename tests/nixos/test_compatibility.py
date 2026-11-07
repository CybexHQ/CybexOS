"""A candidate Nixpkgs that no longer evaluates: diagnosis, hold and retry.

Fixture tests at the command boundary. The error text is the one Nix printed
when Nixpkgs removed Brave (2026-11-03) and Cybex OS 1.0.23 still used it.
"""
import json
from pathlib import Path
import unittest

import test_lifecycle as lifecycle
import test_update_automation as automation
from cybexos import automatic, compatibility, prebuilt
from cybexos.common import CommandFailure, atomic, read
from cybexos.engine import IncompatibleNixpkgs, config_digest

CONFIG = '/nix/store/' + 'c' * 32 + '-config'
CYBEXOS = '/nix/store/' + 'f' * 32 + '-source'
NIXPKGS = '/nix/store/' + 'd' * 32 + '-source'
HOME = '/nix/store/' + 'b' * 32 + '-source'
ARCHIVE = {'path': CONFIG, 'inputs': {
    'cybexos': {'path': CYBEXOS, 'inputs': {'lanzaboote': {'path': '/nix/store/' + 'l' * 32 + '-source', 'inputs': {}}}},
    'nixpkgs': {'path': NIXPKGS, 'inputs': {}},
    'home-manager': {'path': HOME, 'inputs': {}}}}
REMOVED = 'brave has been removed from nixpkgs, as there were no committers among its maintainers to unblock security issues'


def failure(module, message=REMOVED):
    trace = ('\x1b[31;1merror:\x1b[0m\n'
             f"       … while evaluating definitions from `{NIXPKGS}/nixos/modules/misc/man-db.nix':\n\n"
             "       … while evaluating the option `environment.systemPackages':\n\n"
             f"       … while evaluating definitions from `{module}':\n\n"
             f'       \x1b[31;1merror:\x1b[0m {message}')
    event = {'action': 'msg', 'level': 0, 'msg': trace, 'raw_msg': message}
    return ('@nix {"action":"start","id":1,"level":4,"text":"evaluating"}\n'
            '@nix ' + json.dumps(event) + '\n')


class Diagnosis(unittest.TestCase):
    def test_the_evaluation_error_and_its_message_are_read_from_nix_output(self):
        message, trace = compatibility.evaluation_error(failure(CYBEXOS + '/nix/modules/applications.nix'))
        self.assertEqual(message, REMOVED)
        self.assertNotIn('\x1b', trace)
        self.assertIn('while evaluating definitions from', trace)

    def test_fetch_failures_and_other_output_are_not_incompatibilities(self):
        self.assertIsNone(compatibility.evaluation_error(''))
        self.assertIsNone(compatibility.evaluation_error('error: plain text\n@nix not json\n'))
        network = failure(CYBEXOS + '/nix/modules/applications.nix',
                          'unable to download https://example.test: Couldn\'t resolve host name')
        self.assertIsNone(compatibility.evaluation_error(network))
        no_trace = '@nix ' + json.dumps({'action': 'msg', 'level': 0, 'msg': 'error: out of disk', 'raw_msg': 'x'})
        self.assertIsNone(compatibility.evaluation_error(no_trace))

    def test_the_innermost_module_outside_nixpkgs_names_the_owner(self):
        for module, expected in (
                (CYBEXOS + '/nix/modules/applications.nix', {'origin': 'cybexos', 'file': 'nix/modules/applications.nix'}),
                ('/nix/store/' + 'l' * 32 + '-source/nix/module.nix', {'origin': 'cybexos', 'file': 'nix/module.nix'}),
                (CONFIG + '/local/browser.nix', {'origin': 'personal', 'file': 'local/browser.nix'}),
                (HOME + '/modules/programs.nix', {'origin': 'personal', 'file': 'home-manager: modules/programs.nix'}),
                (NIXPKGS + '/nixos/modules/programs/chromium.nix', {'origin': 'unknown', 'file': ''}),
                ('/nix/store/' + 'z' * 32 + '-elsewhere/x.nix', {'origin': 'unknown', 'file': ''})):
            with self.subTest(module=module):
                trace = compatibility.evaluation_error(failure(module))[1]
                self.assertEqual(compatibility.origin(trace, ARCHIVE), expected)
        self.assertEqual(compatibility.origin('', {}), {'origin': 'unknown', 'file': ''})

    def test_only_a_cybexos_module_publishes_the_nixpkgs_message(self):
        vendor = compatibility.describe({'origin': 'cybexos', 'file': 'nix/modules/applications.nix',
                                         'message': REMOVED}, '1.0.23')
        self.assertIn('Cybex OS 1.0.23: brave has been removed', vendor)
        self.assertIn('Nothing was changed', vendor)
        personal = compatibility.describe({'origin': 'personal', 'file': 'local/browser.nix'}, '1.0.23')
        self.assertIn('local/browser.nix', personal)
        self.assertNotIn('brave', personal)
        self.assertEqual(len(compatibility.public('x ' * 400)), 300)


class EngineHold(unittest.TestCase):
    setUp = lifecycle.EngineTests.setUp

    def fail_with(self, module, probe_ok=True):
        """The candidate fails to evaluate unless it is the installed-Nixpkgs probe."""
        original = self.engine.run
        self.probes = []
        def run(*args, **kwargs):
            args = tuple(map(str, args))
            if args[:3] == ('nix', 'flake', 'archive'):
                return json.dumps(ARCHIVE)
            if args[:3] == ('nix', 'eval', '--raw') and any(a.endswith('.toplevel.drvPath') for a in args):
                flake = next(a for a in args if a.startswith('path:'))
                if 'nixpkgs-probe' in flake:
                    probe = Path(flake.removeprefix('path:').split('#')[0])
                    self.probes.append(read(probe / 'flake.lock'))
                    if probe_ok:
                        return original(*args, **kwargs)
                raise CommandFailure('nix', 1, failure(module))
            return original(*args, **kwargs)
        run.observer = None
        run.log = None
        self.engine.run = run

    def test_a_cybexos_module_using_a_removed_package_holds_the_update(self):
        self.fail_with(CYBEXOS + '/nix/modules/applications.nix')
        with self.assertRaises(IncompatibleNixpkgs) as raised:
            self.engine.stage('upstream')
        self.assertTrue(raised.exception.held)
        status = read(self.engine.status_path)
        self.assertEqual(status['incompatible'], {'origin': 'cybexos', 'file': 'nix/modules/applications.nix',
                                                  'message': REMOVED})
        self.assertEqual((status['state'], status['changeKind']), ('failed', 'update'))
        self.assertIn('brave has been removed', status['error'])
        self.assertIn('Waiting for a Cybex OS release', status['phase'])
        self.assertTrue(prebuilt.held(status))
        self.assertEqual(prebuilt.waiting_packages(status), [])
        # The probe kept the candidate and swapped only Nixpkgs back.
        [probe] = self.probes
        self.assertEqual(probe['nodes']['nixpkgs']['locked']['rev'], lifecycle.REV_OLD)
        tx = self.engine.tx(status['transaction'])
        self.assertFalse((tx / 'nixpkgs-probe').exists())
        self.assertEqual(config_digest(self.config), self.sentinel)
        builds = [c for c in self.runner.calls if c[:2] == ('nix', 'build') and '--dry-run' not in c]
        self.assertEqual(builds, [])

    def test_when_the_installed_nixpkgs_fails_too_it_is_an_ordinary_failure(self):
        self.fail_with(CYBEXOS + '/nix/modules/applications.nix', probe_ok=False)
        with self.assertRaises(CommandFailure):
            self.engine.stage('upstream')
        status = read(self.engine.status_path)
        self.assertIsNone(status['incompatible'])
        self.assertFalse(prebuilt.held(status))

    def test_a_personal_module_is_named_without_publishing_its_error(self):
        self.fail_with(CONFIG + '/local/browser.nix')
        with self.assertRaises(IncompatibleNixpkgs) as raised:
            self.engine.stage('upstream')
        self.assertFalse(raised.exception.held)
        status = read(self.engine.status_path)
        self.assertEqual(status['incompatible'], {'origin': 'personal', 'file': 'local/browser.nix'})
        self.assertNotIn('brave', status['error'])
        self.assertFalse(prebuilt.held(status))

    def test_a_prepared_update_stays_ready_beside_a_held_newer_set(self):
        first = self.engine.stage('upstream')
        self.fail_with(CYBEXOS + '/nix/modules/applications.nix')
        with self.assertRaises(IncompatibleNixpkgs):
            self.engine.stage('both')
        status = read(self.engine.status_path)
        self.assertEqual((status['state'], status['transaction']), ('ready', first['id']))
        self.assertEqual(status['replacement']['state'], 'waiting')
        self.assertEqual(status['replacement']['incompatible']['origin'], 'cybexos')

    def test_local_previews_are_never_diagnosed_as_nixpkgs_changes(self):
        self.fail_with(CYBEXOS + '/nix/modules/applications.nix')
        with self.assertRaises(CommandFailure):
            self.engine.stage('cybexos')
        self.assertEqual(self.probes, [])


class Retry(unittest.TestCase):
    setUp = automation.Automation.setUp
    discovery = automation.Automation.discovery
    enqueue = automation.Automation.enqueue
    status = automation.Automation.status
    prepare = automation.Automation.prepare
    finish = automation.Automation.finish

    def incompatible(self, **values):
        atomic(self.engine.status_path, {'state': 'failed', 'changeKind': 'update',
            'incompatible': {'origin': 'cybexos', 'file': 'nix/modules/applications.nix', 'message': REMOVED},
            'finishedAt': 1000.0, 'baseline': config_digest(self.working), 'inputs': {
                'nixpkgs': {'rev': '2' * 40}, 'cybexos': {'rev': 'c' * 40}}, **values})

    def test_a_held_update_waits_a_day_and_retries_a_new_release_at_once(self):
        self.incompatible()
        self.assertEqual(self.prepare(now=1001.0), {'skipped': 'waiting'})
        accepted = self.prepare(now=1000.0 + automatic.RETRY_SECONDS)
        self.assertEqual(accepted['scope'], 'upstream')
        self.finish(accepted, 'failed')
        self.incompatible()
        release = self.discovery(cybexos='available')
        release['cybexos']['revision'] = 'd' * 40
        self.assertEqual(self.prepare(release, now=1002.0)['scope'], 'both')

    def test_a_personal_module_is_not_a_hold(self):
        self.incompatible(incompatible={'origin': 'personal', 'file': 'local/browser.nix'})
        self.assertFalse(prebuilt.held(read(self.engine.status_path)))


if __name__ == '__main__':
    unittest.main()
