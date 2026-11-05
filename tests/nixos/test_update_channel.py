"""The release channel a machine follows: runtime choice, discovery and previews."""
from pathlib import Path
import unittest
from unittest.mock import patch

import test_lifecycle as lifecycle
from cybexos import channel as channels, cli, trust
from cybexos.common import Failure, atomic, locked, read


class ChannelChoice(unittest.TestCase):
    setUp = lifecycle.EngineTests.setUp

    def choose(self, name):
        return cli.choose_channel(self.engine.state, name, self.policy, self.engine)

    def test_runtime_choice_overrides_the_declared_channel_until_chosen_back(self):
        state, override = self.engine.state, self.engine.state / channels.POLICY
        self.assertEqual(channels.selected(state, self.policy),
                         {'selected': 'stable', 'declared': 'stable', 'override': False})
        self.assertEqual(self.choose('beta'), {'selected': 'beta', 'declared': 'stable', 'override': True})
        self.assertEqual(read(override), {'schema': 1, 'channel': 'beta'})
        # The signed-in desktop reads it, like the automatic update policy.
        self.assertEqual(override.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.engine.selected_channel(), 'beta')
        # Choosing the declared channel removes the override, so a later edit
        # of cybexos.updates.channel applies again.
        self.assertEqual(self.choose('stable'), {'selected': 'stable', 'declared': 'stable', 'override': False})
        self.assertFalse(override.exists())
        atomic(self.policy, {'channel': 'beta'})
        self.assertEqual(self.engine.selected_channel(), 'beta')
        with self.assertRaisesRegex(Failure, 'stable or beta'):
            self.choose('nightly')

    def test_an_unreadable_choice_follows_the_declared_channel(self):
        override = self.engine.state / channels.POLICY
        for body in ('not json', '{"channel": "nightly"}', '["beta"]'):
            with self.subTest(body=body):
                override.write_text(body)
                self.assertEqual(channels.selected(self.engine.state, self.policy)['selected'], 'stable')
        atomic(self.policy, {'channel': 'unknown'})
        with self.assertRaisesRegex(Failure, 'Unknown release channel'):
            channels.selected(self.engine.state, self.policy)

    def test_status_reports_the_channel_and_never_guesses_one(self):
        self.choose('beta')
        status = cli.update_status(self.engine.state, self.working, self.policy)
        self.assertEqual(status['channel'], {'selected': 'beta', 'declared': 'stable', 'override': True})
        missing = cli.update_status(self.engine.state, self.working, self.base / 'missing.json')
        self.assertEqual(missing['channel'], {'selected': '', 'declared': '', 'override': False})

    def test_discovery_follows_the_selected_channel(self):
        del self.engine.channel  # The fixture's fixed release.
        found = []
        def discover(fetch, name, installed):
            found.append(name)
            return lifecycle.release()
        with patch('cybexos.engine.discover', side_effect=discover):
            self.assertEqual(self.engine.channel()['channel'], 'stable')
            self.choose('beta')
            self.assertEqual(self.engine.channel()['channel'], 'beta')
            self.assertEqual(self.engine.check()['cybexos']['channel'], 'beta')
        self.assertEqual(found, ['stable', 'beta', 'beta'])

    def test_ahead_of_the_channel_is_a_neutral_state(self):
        self.engine.channel = lambda: (_ for _ in ()).throw(trust.AheadOfChannel('stable', '1.0.0', '0.9.0'))
        result = self.engine.check()
        self.assertEqual(result['cybexos'], {'state': 'ahead', 'installed': '1.0.0', 'available': '0.9.0',
                                             'channel': 'stable'})
        self.assertEqual(result['upstream']['state'], 'available')
        # NixOS package updates stay independent; a Cybex OS update is refused.
        self.engine.stage('upstream')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')
        self.engine.discard(read(self.engine.status_path)['transaction'])
        with self.assertRaisesRegex(Failure, 'next stable release after 1.0.0'):
            self.engine.stage('cybexos')

    def stage_beta(self):
        self.engine.channel = lambda: lifecycle.release() | {'channel': 'beta'}
        record = self.engine.stage('cybexos')
        self.assertEqual(record['channel'], 'beta')
        self.assertEqual(read(self.engine.tx(record['id']) / 'release.json')['channel'], 'beta')
        return record

    def test_moving_to_stable_invalidates_a_prepared_beta_release(self):
        self.choose('beta')
        record = self.stage_beta()
        self.choose('stable')
        status = read(self.engine.status_path)
        self.assertEqual(status['state'], 'stale')
        self.assertIn('changed to stable', status['error'])
        self.assertIsNone(status['reviewToken'])
        with self.assertRaisesRegex(Failure, 'not ready'):
            self.engine.apply(record['id'], record['reviewToken'])

    def test_moving_to_beta_keeps_a_prepared_release(self):
        self.engine.channel = lambda: lifecycle.release() | {'channel': 'stable'}
        self.engine.stage('cybexos')
        self.choose('beta')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')

    def test_installation_checks_the_channel_when_the_choice_could_not(self):
        self.choose('beta')
        record = self.stage_beta()
        # A running operation holds the lock; the choice never waits for it.
        with locked(self.engine.state / 'operation.lock'):
            self.choose('stable')
        self.assertEqual(read(self.engine.status_path)['state'], 'ready')
        with self.assertRaisesRegex(Failure, 'changed to stable'):
            self.engine.apply(record['id'], record['reviewToken'])
        self.assertEqual(read(self.engine.status_path)['state'], 'stale')
        self.assertFalse(self.engine.pending_path.exists())

    def test_request_boundary_accepts_only_a_channel_name(self):
        with patch('cybexos.cli.os.geteuid', return_value=0), \
                patch('cybexos.cli.require_installed'), \
                patch('cybexos.cli.Path', side_effect=lambda value: self.engine.state if value == '/var/lib/cybexos' else Path(value)), \
                patch('cybexos.cli.choose_channel', return_value={'selected': 'beta'}) as choose, \
                patch('sys.argv', ['cybexos-request', 'channel', 'beta']), \
                patch('builtins.print') as printed:
            cli.request()
        choose.assert_called_once_with(self.engine.state, 'beta')
        printed.assert_called_once_with('{"channel": {"selected": "beta"}}')
        with patch('cybexos.cli.os.geteuid', return_value=0), patch('cybexos.cli.require_installed'), \
                patch('sys.argv', ['cybexos-request', 'channel', 'nightly']), \
                patch('cybexos.cli.Path', side_effect=lambda value: self.engine.state if value == '/var/lib/cybexos' else Path(value)), \
                patch('cybexos.cli.channels.DECLARED', self.policy), \
                self.assertRaisesRegex(Failure, 'stable or beta'):
            cli.request()


if __name__ == '__main__':
    unittest.main()
