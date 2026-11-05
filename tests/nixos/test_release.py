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

    def test_a_release_goes_to_beta_first(self):
        result = self.publish('1.0.1', 'cybexos.iso')
        self.assertEqual(result.returncode, 0, result.stderr)
        revision = self.git('rev-parse', 'HEAD').strip()
        self.assertEqual(self.git('rev-parse', 'v1.0.1^{commit}').strip(), revision)
        self.assertEqual(self.git('cat-file', '-t', 'v1.0.1').strip(), 'tag')
        self.assertIn('refs/tags/v1.0.1', self.git('ls-remote', '--tags', 'origin'))
        self.assertEqual(self.log.read_text().splitlines(), [
            'release create v1.0.1 --repo CybexHQ/CybexOS --verify-tag --title Cybex OS 1.0.1 '
            '--notes-file release/notes.md --prerelease --latest=false cybexos.iso'])
        self.assertIn('for beta', result.stdout)
        self.assertIn('release/promote 1.0.1', result.stdout)

    def test_stable_release_is_tagged_pushed_and_marked_latest(self):
        result = self.publish('1.0.1', '--stable', 'cybexos.iso')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), [
            'release create v1.0.1 --repo CybexHQ/CybexOS --verify-tag --title Cybex OS 1.0.1 '
            '--notes-file release/notes.md --latest cybexos.iso'])
        self.assertIn('for stable and beta', result.stdout)
        self.assertNotIn('release/promote', result.stdout)

    def test_prerelease_reaches_beta_only(self):
        (self.work / 'VERSION').write_text('1.0.2-beta.1\n')
        self.git('commit', '--quiet', '-am', 'Beta')
        self.git('push', '--quiet', 'origin', 'main')
        self.assert_refused('can only reach the beta channel', '1.0.2-beta.1', '--stable')
        result = self.publish('1.0.2-beta.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--prerelease --latest=false', self.log.read_text())
        self.assertNotIn('release/promote', result.stdout)

    def test_dry_run_changes_nothing(self):
        result = self.publish('1.0.1', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Would publish v1.0.1', result.stdout)
        self.assertIn('for beta (--prerelease --latest=false)', result.stdout)
        result = self.publish('1.0.1', '--dry-run', '--stable')
        self.assertIn('for stable and beta (--latest)', result.stdout)
        self.assertEqual(self.git('tag'), '')
        self.assertFalse(self.log.exists())

    def test_inconsistent_or_unpublished_sources_are_refused(self):
        self.assert_refused('not a semantic release version', '1.0')
        self.assert_refused('VERSION is 1.0.1, not 1.0.2', '1.0.2')
        self.assert_refused('asset missing.iso does not exist', '1.0.1', 'missing.iso')
        self.assert_refused('unknown option --beta', '1.0.1', '--beta')
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



# A recording gh that serves the release listing as installed machines read it
# and applies `release edit` to it, as GitHub does.
FAKE_GH = r"""#!/usr/bin/env python3
import json, os, sys
state = os.environ['GH_STATE']
listing = json.load(open(state))
arguments = sys.argv[1:]
with open(os.environ['GH_LOG'], 'a') as log:
    log.write(' '.join(arguments) + '\n')
if arguments[0] == 'api':
    print(json.dumps(listing))
elif arguments[:2] == ['release', 'edit']:
    item = next(item for item in listing if item['tag_name'] == arguments[2])
    if os.environ.get('GH_IGNORE_EDIT'):
        sys.exit(0)
    if '--prerelease=false' in arguments:
        item['prerelease'] = False
    item['body'] = open(arguments[arguments.index('--notes-file') + 1]).read()
    json.dump(listing, open(state, 'w'))
else:
    sys.exit('unexpected gh ' + ' '.join(arguments))
"""


class PromoteTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-promote-')
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        self.origin, self.work = base / 'origin.git', base / 'work'
        self.log, self.state = base / 'gh.log', base / 'releases.json'
        subprocess.run(['git', 'init', '--quiet', '--bare', '--initial-branch=main', str(self.origin)], check=True)
        subprocess.run(['git', 'init', '--quiet', '--initial-branch=main', str(self.work)], check=True)
        for name, value in (('user.name', 'Release Test'), ('user.email', 'release@example.invalid')):
            self.git('config', name, value)
        (self.work / 'release').mkdir()
        shutil.copy2(ROOT / 'release/promote', self.work / 'release/promote')
        shutil.copytree(ROOT / 'lifecycle/cybexos', self.work / 'lifecycle/cybexos',
                        ignore=shutil.ignore_patterns('__pycache__'))
        self.git('remote', 'add', 'origin', str(self.origin))
        self.listing = []
        tools = base / 'bin'; tools.mkdir()
        (tools / 'gh').write_text(FAKE_GH)
        (tools / 'gh').chmod(0o755)
        self.environment = {key: value for key, value in os.environ.items() if key not in ('VISUAL', 'EDITOR')}
        self.environment |= {'PATH': f'{tools}:{os.environ["PATH"]}', 'GH_LOG': str(self.log),
                             'GH_STATE': str(self.state), 'CYBEXOS_RELEASE_REPO': 'CybexHQ/CybexOS',
                             'PYTHONDONTWRITEBYTECODE': '1'}
        # 1.0.1 is stable; 1.0.2 and 1.0.3 have been on beta for two days.
        self.release('1.0.1', prerelease=False, hours=96)
        self.release('1.0.2', hours=48)
        self.release('1.0.3', hours=47)

    def git(self, *arguments):
        return subprocess.run(['git', *arguments], cwd=self.work, check=True, capture_output=True, text=True).stdout

    def release(self, version, prerelease=True, hours=48, compatibility=None, draft=False):
        import datetime
        (self.work / 'VERSION').write_text(version + '\n')
        declared = json.loads((ROOT / 'release/compatibility.json').read_text()) | (compatibility or {})
        (self.work / 'release/compatibility.json').write_text(json.dumps(declared))
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', f'Cybex OS {version}')
        self.git('tag', '--annotate', 'v' + version, '--message', f'Cybex OS {version}')
        self.git('push', '--quiet', 'origin', 'main', 'v' + version)
        # The local tag is fetched from origin, as on a fresh checkout.
        self.git('tag', '--delete', 'v' + version)
        published = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
        self.listing.insert(0, {'tag_name': 'v' + version, 'prerelease': prerelease, 'draft': draft,
                                'published_at': published.strftime('%Y-%m-%dT%H:%M:%SZ'),
                                'body': f'# Cybex OS {version}\n\n- Change in {version}.\n'})
        self.state.write_text(json.dumps(self.listing))

    def promote(self, *arguments, **environment):
        return subprocess.run([str(self.work / 'release/promote'), *arguments], cwd=self.work,
                              env=self.environment | environment, capture_output=True, text=True,
                              stdin=subprocess.DEVNULL)

    def published(self, version):
        return next(item for item in json.loads(self.state.read_text()) if item['tag_name'] == 'v' + version)

    def edits(self):
        return [line for line in self.log.read_text().splitlines() if line.startswith('release edit')] \
            if self.log.exists() else []

    def assert_refused(self, pattern, *arguments):
        before, listing = self.edits(), self.state.read_text()
        result = self.promote(*arguments)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(pattern, result.stderr)
        self.assertEqual(self.edits(), before, 'a refused promotion changed a release')
        self.assertEqual(self.state.read_text(), listing)

    def test_promotion_moves_the_same_release_to_stable_with_combined_notes(self):
        revision = self.git('rev-parse', 'HEAD').strip()
        result = self.promote('1.0.3', '--yes')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.edits()), 1)
        self.assertTrue(self.edits()[0].startswith(
            'release edit v1.0.3 --repo CybexHQ/CybexOS --prerelease=false --latest --notes-file '))
        promoted = self.published('1.0.3')
        self.assertFalse(promoted['prerelease'])
        # Nothing about the release's source changes: same tag, same commit.
        self.assertEqual(self.git('rev-parse', 'v1.0.3^{commit}').strip(), revision)
        self.assertEqual(promoted['body'], '# Cybex OS 1.0.3\n\n'
                         'This stable release also includes 1.0.2, published on the beta channel since Cybex OS 1.0.1.\n\n'
                         '- Change in 1.0.3.\n\n## From Cybex OS 1.0.2\n\n- Change in 1.0.2.\n')
        # The skipped beta release stays beta-only.
        self.assertTrue(self.published('1.0.2')['prerelease'])
        self.assertIn('including 1.0.2', result.stdout)
        self.assert_refused('already on the stable channel', '1.0.3', '--yes')
        self.assert_refused('not newer than the current stable release v1.0.3', '1.0.2', '--yes')

    def test_a_single_release_keeps_its_own_notes(self):
        result = self.promote('1.0.2', '--yes')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.published('1.0.2')['body'], '# Cybex OS 1.0.2\n\n- Change in 1.0.2.\n')
        notes = self.work / 'notes.md'
        notes.write_text('# Cybex OS 1.0.3\n\nWritten for stable.\n')
        result = self.promote('1.0.3', '--yes', '--notes', str(notes))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.published('1.0.3')['body'], notes.read_text())

    def test_soak_time_on_beta(self):
        self.release('1.0.4', hours=2)
        self.assert_refused('on beta for 2.0 hours, less than 24', '1.0.4', '--yes')
        self.assert_refused('less than 3', '1.0.4', '--yes', '--soak', '3')
        result = self.promote('1.0.4', '--yes', '--soak', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.release('1.0.5', hours=0)
        result = self.promote('1.0.5', '--yes', '--now')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dry_run_and_confirmation(self):
        result = self.promote('1.0.3', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('## From Cybex OS 1.0.2', result.stdout)
        self.assertIn('Dry run: nothing was changed.', result.stdout)
        self.assertEqual(self.edits(), [])
        self.assert_refused('confirm with --yes', '1.0.3')

    def test_only_published_final_versions_reach_stable(self):
        self.assert_refused('not a semantic release version', '1.0')
        self.assert_refused('prerelease version', '1.0.4-beta.1')
        self.assert_refused('not a published release', '1.0.9')
        self.release('1.0.4', draft=True)
        self.assert_refused('not a published release', '1.0.4')
        self.assert_refused('v1.0.1 is already on the stable channel', '1.0.1')

    def test_every_stable_machine_must_be_able_to_install_it(self):
        self.release('1.0.4', compatibility={'minUpdater': 2})
        self.assert_refused('requires updater API 2, but v1.0.1 provides 1', '1.0.4', '--yes')
        self.release('1.0.5', compatibility={'nixos': ['26.11']})
        self.assert_refused('does not support NixOS unstable', '1.0.5', '--yes')
        self.release('1.0.6', compatibility={'configurationApi': 2})
        self.assert_refused('configurationApi 2 differs from 1', '1.0.6', '--yes')

    def test_github_must_confirm_the_promotion(self):
        result = self.promote('1.0.3', '--yes', GH_IGNORE_EDIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('still lists v1.0.3 as a prerelease', result.stderr)


if __name__ == '__main__':
    unittest.main()
