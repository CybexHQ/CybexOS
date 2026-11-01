"""release/publish against a throwaway Git origin and a recording gh; no network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublishTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-publish-')
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        self.origin, self.work, self.log = base / 'origin.git', base / 'work', base / 'gh.log'
        self.git('init', '--quiet', '--bare', '--initial-branch=main', str(self.origin), cwd=base)
        self.git('init', '--quiet', '--initial-branch=main', str(self.work), cwd=base)
        for name, value in (('user.name', 'Release Test'), ('user.email', 'release@example.invalid')):
            self.git('config', name, value)
        (self.work / 'release').mkdir()
        shutil.copy2(ROOT / 'release/publish', self.work / 'release/publish')
        shutil.copy2(ROOT / 'release/compatibility.json', self.work / 'release/compatibility.json')
        (self.work / 'release/notes.md').write_text('# Cybex OS 1.0.1\n')
        (self.work / 'VERSION').write_text('1.0.1\n')
        (self.work / 'cybexos.iso').write_bytes(b'iso')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Release fixture')
        self.git('remote', 'add', 'origin', str(self.origin))
        self.git('push', '--quiet', 'origin', 'main')
        tools = base / 'bin'; tools.mkdir()
        (tools / 'gh').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$GH_LOG"\n')
        (tools / 'gh').chmod(0o755)
        self.environment = os.environ | {'PATH': f'{tools}:{os.environ["PATH"]}', 'GH_LOG': str(self.log),
                                         'CYBEXOS_RELEASE_REPO': 'CybexHQ/CybexOS'}

    def git(self, *arguments, cwd=None):
        return subprocess.run(['git', *arguments], cwd=cwd or self.work, check=True, capture_output=True, text=True).stdout

    def publish(self, *arguments):
        return subprocess.run([str(self.work / 'release/publish'), *arguments], cwd=self.work,
                              env=self.environment, capture_output=True, text=True)

    def assert_refused(self, pattern, *arguments):
        result = self.publish(*arguments)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(pattern, result.stderr)
        self.assertFalse(self.log.exists(), 'gh ran for a refused release')
        self.assertEqual(self.git('ls-remote', '--tags', 'origin'), '')

    def test_final_release_is_tagged_pushed_and_marked_latest(self):
        result = self.publish('1.0.1', 'cybexos.iso')
        self.assertEqual(result.returncode, 0, result.stderr)
        revision = self.git('rev-parse', 'HEAD').strip()
        self.assertEqual(self.git('rev-parse', 'v1.0.1^{commit}').strip(), revision)
        self.assertEqual(self.git('cat-file', '-t', 'v1.0.1').strip(), 'tag')
        self.assertIn('refs/tags/v1.0.1', self.git('ls-remote', '--tags', 'origin'))
        self.assertEqual(self.log.read_text().splitlines(), [
            'release create v1.0.1 --repo CybexHQ/CybexOS --verify-tag --title Cybex OS 1.0.1 '
            '--notes-file release/notes.md --latest cybexos.iso'])

    def test_prerelease_reaches_beta_only(self):
        (self.work / 'VERSION').write_text('1.0.2-beta.1\n')
        self.git('commit', '--quiet', '-am', 'Beta')
        self.git('push', '--quiet', 'origin', 'main')
        result = self.publish('1.0.2-beta.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--prerelease --latest=false', self.log.read_text())

    def test_dry_run_changes_nothing(self):
        result = self.publish('1.0.1', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Would publish v1.0.1', result.stdout)
        self.assertEqual(self.git('tag'), '')
        self.assertFalse(self.log.exists())

    def test_inconsistent_or_unpublished_sources_are_refused(self):
        self.assert_refused('not a semantic release version', '1.0')
        self.assert_refused('VERSION is 1.0.1, not 1.0.2', '1.0.2')
        self.assert_refused('asset missing.iso does not exist', '1.0.1', 'missing.iso')
        (self.work / 'untracked').write_text('local change')
        self.assert_refused('commit or stash local changes', '1.0.1')
        (self.work / 'untracked').unlink()
        (self.work / 'release/notes.md').write_text('# Cybex OS 1.0.1\n\nMore.\n')
        self.git('commit', '--quiet', '-am', 'Local only')
        self.assert_refused('main must equal origin/main', '1.0.1')
        self.git('reset', '--quiet', '--hard', 'origin/main')
        self.git('checkout', '--quiet', '-b', 'feature')
        self.assert_refused('publish from main', '1.0.1')
        self.git('checkout', '--quiet', 'main')
        (self.work / 'release/compatibility.json').write_text(json.dumps({'schema': 2}))
        self.git('commit', '--quiet', '-am', 'Broken declaration')
        self.git('push', '--quiet', 'origin', 'main')
        self.assert_refused('compatibility.json is missing or invalid', '1.0.1')

    def test_a_published_version_is_never_reused(self):
        self.git('tag', 'v1.0.1')
        self.assert_refused('v1.0.1 already exists', '1.0.1')
        self.git('push', '--quiet', 'origin', 'v1.0.1')
        self.git('tag', '--delete', 'v1.0.1')
        result = self.publish('1.0.1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('v1.0.1 already exists', result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
