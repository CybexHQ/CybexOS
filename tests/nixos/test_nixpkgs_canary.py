"""The Nixpkgs canary's verification record (scripts/nixpkgs-canary --verified)."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

import test_lifecycle  # noqa: F401  (puts lifecycle/ on the path)
from cybexos import verified

loader = importlib.machinery.SourceFileLoader('nixpkgs_canary', str(Path(__file__).resolve().parents[2] / 'scripts/nixpkgs-canary'))
canary = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(canary)

NAR = 'sha256-' + 'B' * 43 + '='
CHANNEL = {'ref': 'nixos-unstable', 'rev': 'c' * 40, 'date': 1793110635, 'narHash': NAR}
MASTER = {'ref': 'master', 'rev': 'm' * 40, 'date': 1793120000, 'narHash': NAR}


def evaluation(source, ok=True, nixpkgs=CHANNEL, target='product'):
    return {'source': source, 'target': target, 'nixpkgs': nixpkgs, 'ok': ok}


def built(source, revision, **change):
    return {'source': source, 'revision': revision, 'nixpkgs': CHANNEL, 'ok': True, 'expected': 28, 'built': 28,
            'held': [], 'heldNvidia': [], 'failed': []} | change


class Verifications(unittest.TestCase):
    def test_a_release_that_passes_completely_is_verified_with_its_aliases(self):
        results = [evaluation('beta'), evaluation('beta', target='system'), evaluation('beta', ok=False, nixpkgs=MASTER),
                   evaluation('main')]
        builds = [built('beta', 'v1.0.32'), built('main', 'f' * 40)]
        self.assertEqual(canary.verifications(results, builds, CHANNEL, {'beta': ['v1.0.25']}), ['1.0.25', '1.0.32'])

    def test_anything_short_of_that_verifies_nothing(self):
        failed = {'derivation': '/nix/store/x-tectonic.drv', 'name': 'tectonic-0.17.0', 'held': True, 'log': ''}
        for change in ({'held': ['codex-0.167.0']}, {'heldNvidia': ['egl-wayland-1.1.24']}, {'failed': [failed]},
                       {'built': 27}, {'expected': 0, 'built': 0}, {'skipped': True}, {'error': 'no lock'},
                       {'nixpkgs': MASTER}):
            with self.subTest(change=change):
                self.assertEqual(canary.verifications([evaluation('beta')], [built('beta', 'v1.0.32', **change)],
                                                      CHANNEL, {}), [])
        self.assertEqual(canary.verifications([evaluation('beta', ok=False)], [built('beta', 'v1.0.32')], CHANNEL, {}), [])
        self.assertEqual(canary.verifications([], [built('beta', 'v1.0.32')], CHANNEL, {}), [])


class Record(unittest.TestCase):
    def test_the_record_machines_read(self):
        record = canary.verify(None, CHANNEL, ['1.0.32'], '2026-11-11T04:17:00Z')
        found = verified.validate(record, 'nixos-unstable')
        self.assertEqual(found, [{'rev': CHANNEL['rev'], 'narHash': NAR, 'lastModified': CHANNEL['date'],
                                  'releases': ['1.0.32']}])
        # The same revision again adds releases; a newer one comes first.
        record = canary.verify(record, CHANNEL, ['1.0.25'], '2026-11-11T05:00:00Z')
        newer = CHANNEL | {'rev': 'd' * 40, 'date': CHANNEL['date'] + 100}
        record = canary.verify(record, newer, ['1.0.32'], '2026-11-12T04:17:00Z')
        found = verified.validate(record, 'nixos-unstable')
        self.assertEqual([(item['rev'], item['releases']) for item in found],
                         [('d' * 40, ['1.0.32']), (CHANNEL['rev'], ['1.0.25', '1.0.32'])])

    def test_nothing_verified_leaves_the_record_alone(self):
        record = canary.verify(None, CHANNEL, ['1.0.32'], 'now')
        self.assertIs(canary.verify(record, CHANNEL, [], 'later'), record)
        self.assertEqual(canary.verify(record, CHANNEL | {'narHash': None}, ['1.0.33'], 'later'), record)

    def test_old_revisions_are_dropped(self):
        record = None
        for day in range(70):
            record = canary.verify(record, CHANNEL | {'rev': f'{day:040x}', 'date': CHANNEL['date'] + day}, ['1.0.32'], 'now')
        entries = record['branches']['nixos-unstable']
        self.assertEqual((len(entries), entries[0]['rev']), (60, f'{69:040x}'))

    def test_release_versions(self):
        self.assertEqual([canary.release(r) for r in ('v1.0.32', 'v1.1.0-beta.2', 'main', 'f' * 40, 'v1.0')],
                         ['1.0.32', '1.1.0-beta.2', None, None, None])


if __name__ == '__main__':
    unittest.main()
