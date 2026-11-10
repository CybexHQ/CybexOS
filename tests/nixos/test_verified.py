"""The verified Nixpkgs record machines read (lifecycle/cybexos/verified.py)."""
import json
import unittest

import test_lifecycle  # noqa: F401  (puts lifecycle/ on the path)
from cybexos import verified
from cybexos.common import Failure
from cybexos.trust import EndpointNotFound

OLD, NEW, NEWER = '1' * 40, '2' * 40, '3' * 40
NAR = 'sha256-' + 'B' * 43 + '='


def entry(rev, when, *releases):
    return {'rev': rev, 'narHash': NAR, 'lastModified': when, 'releases': list(releases)}


class Fetch:
    def __init__(self, answer):
        self.answer, self.urls = answer, []

    def get(self, url, limit, accept):
        self.urls.append((url, accept))
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.answer


class Record(unittest.TestCase):
    def test_reads_one_branch_newest_first_from_the_repository(self):
        record = {'schema': 1, 'branches': {'nixos-unstable': [entry(NEW, 2, '1.0.32'), entry(NEWER, 3, '1.0.32')],
                                            'nixos-26.11': [entry(OLD, 1, '1.0.40')]}}
        fetch = Fetch(json.dumps(record).encode())
        self.assertEqual([item['rev'] for item in verified.entries(fetch, 'nixos-unstable')], [NEWER, NEW])
        self.assertEqual(fetch.urls, [('https://api.github.com/repos/CybexHQ/CybexOS/contents/nixpkgs/verified.json'
                                       '?ref=nixpkgs-verified', 'application/vnd.github.raw+json')])
        self.assertEqual(verified.entries(Fetch(json.dumps(record).encode()), 'nixos-25.05'), [])

    def test_nothing_verified_before_the_first_record(self):
        self.assertEqual(verified.entries(Fetch(EndpointNotFound('HTTP 404')), 'nixos-unstable'), [])

    def test_an_unreadable_record_is_a_failure(self):
        with self.assertRaises(Failure):
            verified.entries(Fetch(Failure('Release endpoint unreachable')), 'nixos-unstable')
        good = entry(NEW, 2, '1.0.32')
        for record in ([], {'schema': 2, 'branches': {}}, {'schema': 1, 'branches': []},
                       {'schema': 1, 'branches': {'nixos-unstable': {}}},
                       *({'schema': 1, 'branches': {'nixos-unstable': [good | change]}} for change in (
                           {'rev': 'main'}, {'narHash': 'sha256-x'}, {'lastModified': '2'}, {'lastModified': 0},
                           {'lastModified': True}, {'releases': []}, {'releases': ['latest']}))):
            with self.subTest(record=record), self.assertRaises(Failure):
                verified.validate(record, 'nixos-unstable')


class Newest(unittest.TestCase):
    FOUND = [entry(NEWER, 3, '1.0.33'), entry(NEW, 2, '1.0.32', '1.0.25')]

    def test_newest_revision_verified_for_the_release(self):
        installed = {'rev': OLD, 'lastModified': 1}
        self.assertEqual(verified.newest(self.FOUND, '1.0.33', installed)['rev'], NEWER)
        self.assertEqual(verified.newest(self.FOUND, '1.0.32', installed)['rev'], NEW)
        self.assertEqual(verified.newest(self.FOUND, '1.0.25', {'rev': OLD})['rev'], NEW)
        self.assertIsNone(verified.newest(self.FOUND, '1.0.31', installed))

    def test_never_the_installed_revision_or_an_older_one(self):
        self.assertIsNone(verified.newest(self.FOUND, '1.0.32', {'rev': NEW, 'lastModified': 2}))
        self.assertIsNone(verified.newest(self.FOUND, '1.0.32', {'rev': OLD, 'lastModified': 5}))

    def test_locks_exactly_the_verified_content(self):
        self.assertEqual(verified.locked(entry(NEW, 2, '1.0.32')),
                         {'type': 'github', 'owner': 'NixOS', 'repo': 'nixpkgs', 'rev': NEW, 'narHash': NAR,
                          'lastModified': 2})


if __name__ == '__main__':
    unittest.main()
