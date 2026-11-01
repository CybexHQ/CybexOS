"""Passwordless sudo switch boundaries; real sudo behaviour is tested in NixOS."""
import importlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lifecycle'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'desktop/quickshell/scripts'))
from cybexos import passwordless_sudo
from cybexos.common import Failure, atomic
bridge = importlib.import_module('system_settings_sudo')
VISUDO = shutil.which('visudo') or next((path for path in ('/usr/sbin/visudo', '/run/current-system/sw/bin/visudo')
                                         if os.access(path, os.X_OK)), None)


class PasswordlessSudoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name) / 'state'
        self.state.mkdir()
        self.config = Path(self.temp.name) / 'config.json'
        self.settings = {'available': True, 'user': 'tester', 'passwordRequired': True,
                         'visudo': '/nix/store/0000-sudo/bin/visudo'}
        atomic(self.config, self.settings)
        self.rule = self.state / 'rule'
        self.checked = []

    def visudo(self, args, **kwargs):
        # The candidate is checked under a name sudo's @includedir skips.
        candidate = Path(args[-1])
        self.assertEqual(args[:4], [self.settings['visudo'], '-c', '-q', '-f'])
        self.assertIn('.', candidate.name)
        self.checked.append((candidate.read_text(), self.rule.exists()))
        return subprocess.CompletedProcess(args, 0, '')

    def test_off_by_default_and_enable_disable_round_trip(self):
        with patch.object(passwordless_sudo.subprocess, 'run', side_effect=self.visudo), \
                patch.object(os, 'geteuid', return_value=0):
            self.assertEqual(passwordless_sudo.status(self.state, self.config),
                             {'available': True, 'passwordRequired': True, 'enabled': False, 'user': 'tester'})
            self.assertTrue(passwordless_sudo.change('enable', self.state, self.config)['enabled'])
            self.assertEqual(self.rule.stat().st_mode & 0o777, 0o440)
            self.assertEqual(self.rule.read_text().splitlines()[-1], 'tester ALL=(ALL:ALL) NOPASSWD: SETENV: ALL')
            # Checked before it took effect, not after.
            self.assertEqual(self.checked, [(self.rule.read_text(), False)])
            # Only the rule, and the lock whose dot keeps it out of sudoers.
            self.assertEqual(sorted(path.name for path in self.state.iterdir()), ['operation.lock', 'rule'])
            self.assertTrue(passwordless_sudo.change('enable', self.state, self.config)['enabled'])
            self.assertFalse(passwordless_sudo.change('disable', self.state, self.config)['enabled'])
            self.assertFalse(self.rule.exists())

    @unittest.skipUnless(VISUDO, 'visudo is not installed')
    def test_the_rule_parses_with_real_visudo(self):
        real = subprocess.run
        with patch.object(os, 'geteuid', return_value=0), patch.object(
                passwordless_sudo.subprocess, 'run', side_effect=lambda args, **kwargs: real([VISUDO, *args[1:]], **kwargs)):
            passwordless_sudo.change('enable', self.state, self.config)
        self.assertEqual(real([VISUDO, '-c', '-q', '-f', str(self.rule)]).returncode, 0)

    def test_a_rejected_rule_never_takes_effect(self):
        def reject(args, **kwargs):
            raise subprocess.CalledProcessError(1, args)
        with patch.object(os, 'geteuid', return_value=0), \
                patch.object(passwordless_sudo.subprocess, 'run', side_effect=reject):
            with self.assertRaisesRegex(Failure, 'still required'):
                passwordless_sudo.change('enable', self.state, self.config)
        self.assertEqual([path.name for path in self.state.iterdir()], ['operation.lock'])

    def test_unprivileged_or_unknown_actions_never_change_state(self):
        with patch.object(os, 'geteuid', return_value=1000), patch.object(passwordless_sudo.subprocess, 'run') as run:
            for action in ('enable', 'disable', 'enable root'):
                with self.assertRaises(Failure):
                    passwordless_sudo.change(action, self.state, self.config)
            run.assert_not_called()
        self.assertFalse(self.rule.exists())

    def test_enable_needs_the_declared_contract_but_disable_always_works(self):
        for broken in ({'available': False}, {'user': 'tester ALL=(ALL) ALL\nroot'}, {'user': '../root'},
                       {'user': 1000}, {'visudo': 'visudo'}, {'visudo': None}):
            atomic(self.config, self.settings | broken)
            with patch.object(os, 'geteuid', return_value=0), \
                    patch.object(passwordless_sudo.subprocess, 'run') as run:
                with self.assertRaisesRegex(Failure, 'unavailable'):
                    passwordless_sudo.change('enable', self.state, self.config)
                run.assert_not_called()
            self.assertFalse(self.rule.exists(), broken)
        self.config.unlink()
        self.rule.write_text('tester ALL=(ALL:ALL) NOPASSWD: SETENV: ALL\n')
        with patch.object(os, 'geteuid', return_value=0):
            self.assertFalse(passwordless_sudo.change('disable', self.state, self.config)['enabled'])
        self.assertFalse(self.rule.exists())

    def test_status_reports_a_declared_passwordless_policy(self):
        atomic(self.config, self.settings | {'passwordRequired': False})
        self.assertFalse(passwordless_sudo.status(self.state, self.config)['passwordRequired'])
        self.config.unlink()
        self.assertEqual(passwordless_sudo.status(self.state, self.config),
                         {'available': False, 'passwordRequired': True, 'enabled': False, 'user': ''})

    def test_settings_requires_polkit_and_preserves_cancellation(self):
        service = bridge.SudoSettings()
        with patch.object(bridge.subprocess, 'run', return_value=subprocess.CompletedProcess([], 126, '')) as run:
            with self.assertRaisesRegex(ValueError, 'cancelled or denied'):
                service.dispatch({'action': 'set-enabled', 'enabled': True})
            self.assertEqual(run.call_args.args[0], ['/run/wrappers/bin/pkexec', os.path.realpath(bridge.HELPER), 'enable'])
        result = subprocess.CompletedProcess([], 1, json.dumps({'success': False, 'error': 'Helper said no'}))
        with patch.object(bridge.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'Helper said no'):
                service.dispatch({'action': 'set-enabled', 'enabled': False})
        with patch.object(bridge.subprocess, 'run') as run:
            for request in ({'action': 'set-enabled', 'enabled': 'true'},
                            {'action': 'set-enabled', 'enabled': True, 'user': 'root'},
                            {'action': 'snapshot', 'user': 'root'}):
                with self.assertRaises(ValueError):
                    service.dispatch(request)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
