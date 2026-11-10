"""scripts/vendor-pins and release/automatic with recorded upstream answers, a
throwaway Git origin and a recording release/publish; no network."""
import base64
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('vendor_pins', str(ROOT / 'scripts/vendor-pins'))
spec = importlib.util.spec_from_loader(loader.name, loader)
pins = importlib.util.module_from_spec(spec)
loader.exec_module(pins)

CODEX_DIGEST = 'ab' * 32
CLAUDE_BINARY = 'cd' * 32
CLAUDE_PACKED = 'ef' * 32
CLAUDE = 'https://downloads.claude.ai/claude-code-releases'


def sri(digest):
    return 'sha256-' + base64.b64encode(bytes.fromhex(digest)).decode()


def codex_release(version, digest=CODEX_DIGEST, listed=None, **flags):
    tag = f'rust-v{version}'
    base = f'https://github.com/openai/codex/releases/download/{tag}/'
    asset = 'codex-package-x86_64-unknown-linux-musl.tar.gz'
    return dict({'tag_name': tag, 'prerelease': False, 'draft': False, 'published_at': '2026-11-06T01:40:00Z',
                 'assets': [{'name': asset, 'digest': 'sha256:' + digest, 'browser_download_url': base + asset},
                            {'name': 'codex-package_SHA256SUMS', 'digest': 'sha256:' + '0' * 64,
                             'browser_download_url': base + 'codex-package_SHA256SUMS'}]}, **flags)


def claude_manifest(version, binary, checksum, **overrides):
    return json.dumps(dict({'version': version, 'buildDate': '2026-11-10T00:53:25Z',
                            'platforms': {'linux-x64': {'binary': binary, 'checksum': checksum, 'size': 1},
                                          'darwin-arm64': {'binary': binary, 'checksum': '1' * 64}}},
                           **overrides)).encode()


class VendorPinTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-vendor-pins-')
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        for name, record in (('codex', {'version': '0.166.0', 'url': 'old', 'hash': 'old'}),
                             ('claude-code', {'version': '2.1.311', 'url': 'old', 'hash': 'old', 'binarySha256': 'old'}),
                             ('brave', {'version': '1.99.55', 'url': 'old', 'hash': 'old'})):
            (self.root / 'nix/packages' / name).mkdir(parents=True)
            (self.root / 'nix/packages' / name / 'release.json').write_text(json.dumps(record) + '\n')
        patch = mock.patch.object(pins, 'ROOT', self.root)
        patch.start()
        self.addCleanup(patch.stop)
        # Upstream as recorded: GitHub's release pages and plain downloads.
        self.pages = {}
        self.files = {}
        self.signatures = {}
        for target, function in (('github', self.github), ('fetch', self.fetch), ('signed', self.signed)):
            patch = mock.patch.object(pins, target, function)
            patch.start()
            self.addCleanup(patch.stop)
        self.serve_codex([codex_release('0.169.0-alpha.7', prerelease=True), codex_release('0.167.0'),
                          codex_release('0.166.0')])
        self.serve_claude('2.1.322')

    def github(self, path):
        return self.pages[path]

    def fetch(self, url, limit=1 << 20):
        if url not in self.files:
            raise pins.urllib.error.URLError(f'not recorded: {url}')
        return self.files[url]

    def signed(self, data, signature, key, fingerprint):
        self.assertEqual(key, b'anthropic key')
        self.assertEqual(fingerprint, '31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE')
        return self.signatures.get(signature) == data

    def serve_codex(self, releases, digest=CODEX_DIGEST):
        self.pages = {'/repos/openai/codex/releases?per_page=20&page=1': releases}
        for release in releases:
            sums = release['assets'][1]['browser_download_url']
            self.files[sums] = (f'{digest}  codex-package-x86_64-unknown-linux-musl.tar.gz\n'
                                f'{"9" * 64}  codex-package-aarch64-apple-darwin.tar.gz\n').encode()

    def serve_claude(self, version, binary=None, packed=None):
        binary = binary or claude_manifest(version, 'claude', CLAUDE_BINARY)
        packed = packed or claude_manifest(version, 'claude.zst', CLAUDE_PACKED)
        self.files.update({
            f'{CLAUDE}/latest': f'{version}\n'.encode(),
            'https://downloads.claude.ai/keys/claude-code.asc': b'anthropic key',
            f'{CLAUDE}/{version}/manifest.json': binary,
            f'{CLAUDE}/{version}/manifest.json.sig': b'sig:' + binary,
            f'{CLAUDE}/{version}/manifest.zst.json': packed,
            f'{CLAUDE}/{version}/manifest.zst.json.sig': b'sig:' + packed,
        })
        self.signatures = {b'sig:' + binary: binary, b'sig:' + packed: packed}

    def pin(self, name):
        return next(pin for pin in pins.PINS if pin.name == name)

    def record(self, name):
        return json.loads((self.root / 'nix/packages' / name / 'release.json').read_text())

    def test_the_agent_clis_are_automatic_pins_beside_brave(self):
        auto = {pin.name: pin for pin in pins.PINS if pin.mode == 'auto'}
        self.assertEqual(list(auto), ['brave-origin', 'codex', 'claude-code'])
        for name in ('codex', 'claude-code'):
            self.assertEqual(auto[name].checks, [f'packages.x86_64-linux.{name}', 'checks.x86_64-linux.agent-clis'])
            self.assertEqual(auto[name].file, f'nix/packages/{name}/release.json')
            self.assertTrue((ROOT / auto[name].file).is_file())

    def test_codex_follows_stable_releases_only(self):
        self.serve_codex([codex_release('0.169.0-alpha.7', prerelease=True), dict(codex_release('0.168.0'), draft=True),
                          dict(codex_release('0.167.0'), tag_name='libcap-v2.75'), codex_release('0.166.0'),
                          codex_release('0.165.0')])
        self.assertEqual(self.pin('codex').latest()['version'], '0.166.0')

    def test_codex_reads_further_pages_until_a_stable_release(self):
        alphas = [codex_release(f'0.169.0-alpha.{n}', prerelease=True) for n in range(20)]
        self.pages = {'/repos/openai/codex/releases?per_page=20&page=1': alphas,
                      '/repos/openai/codex/releases?per_page=20&page=2': [codex_release('0.167.0')]}
        self.assertEqual(self.pin('codex').latest()['version'], '0.167.0')
        self.pages = {'/repos/openai/codex/releases?per_page=20&page=1': alphas[:5]}
        with self.assertRaisesRegex(SystemExit, 'no Codex stable release'):
            self.pin('codex').latest()

    def test_codex_needs_matching_github_and_openai_checksums(self):
        pin = self.pin('codex')
        change = pin.update(pin.latest())
        self.assertEqual(change['record'], {
            'version': '0.167.0', 'hash': sri(CODEX_DIGEST),
            'url': 'https://github.com/openai/codex/releases/download/rust-v0.167.0/'
                   'codex-package-x86_64-unknown-linux-musl.tar.gz'})
        self.assertIn('Codex', change['notes'])
        self.assertIn('0.167.0', change['notes'])
        self.serve_codex([codex_release('0.167.0')], digest='12' * 32)
        with self.assertRaisesRegex(SystemExit, 'checksums disagree'):
            pin.update(pin.latest())
        release = codex_release('0.167.0')
        release['assets'] = release['assets'][:1]
        with self.assertRaisesRegex(SystemExit, 'with a checksum'):
            pin.update({'version': '0.167.0', 'release': release})
        self.serve_codex([codex_release('0.167.0')])
        release = codex_release('0.167.0')
        release['assets'][0]['browser_download_url'] = 'https://example.invalid/codex.tar.gz'
        with self.assertRaisesRegex(SystemExit, 'unexpected download location'):
            pin.update({'version': '0.167.0', 'release': release})

    def test_claude_code_follows_the_latest_channel_and_its_signed_manifests(self):
        pin = self.pin('claude-code')
        latest = pin.latest()
        self.assertEqual((latest['version'], latest['release']['published_at']), ('2.1.322', '2026-11-10T00:53:25Z'))
        change = pin.update(latest)
        self.assertEqual(change['record'], {
            'version': '2.1.322', 'url': f'{CLAUDE}/2.1.322/linux-x64/claude.zst',
            'hash': sri(CLAUDE_PACKED), 'binarySha256': CLAUDE_BINARY})
        self.assertIn('Claude Code', change['notes'])

    def test_claude_code_refuses_unsigned_or_inconsistent_manifests(self):
        pin = self.pin('claude-code')
        self.signatures.pop(next(iter(self.signatures)))
        with self.assertRaisesRegex(SystemExit, "not signed by Anthropic's release key"):
            pin.update({'version': '2.1.322'})
        self.serve_claude('2.1.322', binary=claude_manifest('2.1.321', 'claude', CLAUDE_BINARY))
        with self.assertRaisesRegex(SystemExit, 'no linux-x64 checksum'):
            pin.update({'version': '2.1.322'})
        self.serve_claude('2.1.322', packed=claude_manifest('2.1.322', 'claude.zst', 'not a digest'))
        with self.assertRaisesRegex(SystemExit, 'no linux-x64 checksum'):
            pin.update({'version': '2.1.322'})
        self.serve_claude('2.1.322', packed=claude_manifest('2.1.322', 'claude', CLAUDE_PACKED))
        with self.assertRaisesRegex(SystemExit, 'file names'):
            pin.update({'version': '2.1.322'})
        self.files[f'{CLAUDE}/latest'] = b'<html>unavailable</html>'
        with self.assertRaisesRegex(SystemExit, 'unexpected Claude Code version'):
            pin.latest()

    def test_status_reports_every_pin_behind_upstream(self):
        self.pages['/repos/brave/brave-browser/releases?per_page=100'] = []
        for name in ('t3-code', 'intel-lpmd', 'omawrite'):
            pin = self.pin(name)
            patch = mock.patch.object(pin, 'pinned', return_value='1.0.0')
            patch.start()
            self.addCleanup(patch.stop)
            self.pages[f'/repos/{pin.repository}/releases/latest'] = {'tag_name': 'v1.0.0', 'published_at': ''}
        with mock.patch.object(self.pin('brave-origin'), 'latest', return_value={'version': '1.99.55', 'release': {}}):
            rows = {row['name']: row for row in pins.status()}
        self.assertTrue(rows['codex']['behind'])
        self.assertTrue(rows['claude-code']['behind'])
        self.assertFalse(rows['brave-origin']['behind'])
        self.assertEqual(rows['claude-code']['published'], '2026-11-10')
        report = pins.markdown(list(rows.values()))
        self.assertIn('| Codex (`nix/packages/codex/release.json`) | 0.166.0 | 0.167.0 | 2026-11-06 | automatic, to beta |', report)
        self.assertIn('| Claude Code (`nix/packages/claude-code/release.json`) | 2.1.311 | 2.1.322 |', report)

    def test_update_rewrites_every_named_pin_and_lists_the_changes(self):
        changes = pins.update(['codex', 'claude-code'])
        self.assertEqual([(c['name'], c['title'], c['from'], c['to'], c['file']) for c in changes], [
            ('codex', 'Codex', '0.166.0', '0.167.0', 'nix/packages/codex/release.json'),
            ('claude-code', 'Claude Code', '2.1.311', '2.1.322', 'nix/packages/claude-code/release.json')])
        self.assertTrue(all(change['notes'] and change['checks'] for change in changes))
        self.assertEqual(self.record('codex')['version'], '0.167.0')
        self.assertEqual(self.record('claude-code')['binarySha256'], CLAUDE_BINARY)
        self.assertTrue((self.root / 'nix/packages/codex/release.json').read_text().endswith('}\n'))

    def test_update_changes_nothing_unless_every_pin_checks_out(self):
        self.signatures.clear()
        with self.assertRaisesRegex(SystemExit, 'not signed'):
            pins.update(['codex', 'claude-code'])
        self.assertEqual(self.record('codex')['version'], '0.166.0')
        self.assertEqual(self.record('claude-code')['version'], '2.1.311')
        with self.assertRaisesRegex(SystemExit, 'is not an automatically updated pin'):
            pins.update(['codex', 't3-code'])
        self.serve_claude('2.1.311')
        with self.assertRaisesRegex(SystemExit, 'Claude Code 2.1.311 is already current'):
            pins.update(['codex', 'claude-code'])
        self.assertEqual(self.record('codex')['version'], '0.166.0')

    def test_update_prints_a_json_list(self):
        with mock.patch('sys.stdout') as stdout:
            self.assertEqual(pins.main(['update', 'codex']), 0)
        printed = json.loads(''.join(call.args[0] for call in stdout.write.call_args_list))
        self.assertEqual([change['to'] for change in printed], ['0.167.0'])
        with self.assertRaises(SystemExit):
            pins.main(['update'])


# gpg as vendor-pins runs it: --dearmor copies the key; --verify answers with
# the status lines and exit status the test chooses.
FAKE_GPG = r"""#!/bin/sh
for argument in "$@"; do
  case $argument in
    --dearmor) cat; exit 0 ;;
    --verify) printf '%s\n' "$FAKE_GPG_STATUS"; exit "$FAKE_GPG_EXIT" ;;
  esac
done
exit 2
"""


class SignatureTests(unittest.TestCase):
    fingerprint = '31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE'

    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-vendor-gpg-')
        self.addCleanup(directory.cleanup)
        (Path(directory.name) / 'gpg').write_text(FAKE_GPG)
        (Path(directory.name) / 'gpg').chmod(0o755)
        self.path = f'{directory.name}:{os.environ["PATH"]}'

    def verify(self, status, exit_status=0):
        environment = {'PATH': self.path, 'FAKE_GPG_STATUS': status, 'FAKE_GPG_EXIT': str(exit_status)}
        with mock.patch.dict(os.environ, environment):
            return pins.signed(b'manifest', b'signature', b'key', self.fingerprint)

    def test_only_a_valid_signature_by_the_pinned_primary_key_counts(self):
        valid = f'[GNUPG:] GOODSIG BAA929FF1A7ECACE Anthropic\n[GNUPG:] VALIDSIG {"1" * 40} 2026-11-10 0 4 0 1 10 00 {self.fingerprint}'
        self.assertTrue(self.verify(valid))
        self.assertFalse(self.verify(valid, exit_status=1))
        self.assertFalse(self.verify(valid.replace(self.fingerprint, '2' * 40)))
        self.assertFalse(self.verify(f'[GNUPG:] GOODSIG {self.fingerprint}'))

    def test_missing_gpg_is_an_error(self):
        with mock.patch.dict(os.environ, {'PATH': '/nonexistent'}), self.assertRaisesRegex(SystemExit, 'gpg is needed'):
            pins.signed(b'manifest', b'signature', b'key', self.fingerprint)


# A recording release/publish: it succeeds unless PUBLISH_FAIL is set.
FAKE_PUBLISH = """#!/bin/sh
printf '%s\\n' "$*" >> "$PUBLISH_LOG"
"""


class AutomaticReleaseTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='cybexos-automatic-')
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        self.origin, self.work, self.log = base / 'origin.git', base / 'work', base / 'publish.log'
        self.other = base / 'other'
        self.git('init', '--quiet', '--bare', '--initial-branch=main', str(self.origin), cwd=base)
        self.git('init', '--quiet', '--initial-branch=main', str(self.work), cwd=base)
        self.configure(self.work)
        (self.work / 'release').mkdir()
        shutil.copy2(ROOT / 'release/automatic', self.work / 'release/automatic')
        (self.work / 'release/publish').write_text(FAKE_PUBLISH)
        (self.work / 'release/publish').chmod(0o755)
        (self.work / 'release/notes.md').write_text('# Cybex OS 1.0.27\n')
        (self.work / 'VERSION').write_text('1.0.27\n')
        for name, version in (('codex', '0.166.0'), ('claude-code', '2.1.311')):
            (self.work / 'nix/packages' / name).mkdir(parents=True)
            (self.work / 'nix/packages' / name / 'release.json').write_text(json.dumps({'version': version}) + '\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Release fixture')
        self.git('tag', 'v1.0.27')
        self.git('remote', 'add', 'origin', str(self.origin))
        self.git('push', '--quiet', 'origin', 'main', 'v1.0.27')
        self.changes = base / 'changes.json'
        self.environment = os.environ | {'PUBLISH_LOG': str(self.log)}

    def configure(self, path):
        for name, value in (('user.name', 'Release Test'), ('user.email', 'release@example.invalid')):
            self.git('config', name, value, cwd=path)

    def git(self, *arguments, cwd=None):
        return subprocess.run(['git', *arguments], cwd=cwd or self.work, check=True, capture_output=True, text=True).stdout

    def update(self, *pins_):
        changes = []
        for name, title, version, notes in pins_:
            file = f'nix/packages/{name}/release.json'
            before = json.loads((self.work / file).read_text())['version']
            (self.work / file).write_text(json.dumps({'version': version}) + '\n')
            changes.append({'name': name, 'title': title, 'from': before, 'to': version, 'file': file,
                            'checks': [], 'notes': notes})
        self.changes.write_text(json.dumps(changes))

    def automatic(self, *arguments):
        return subprocess.run([str(self.work / 'release/automatic'), str(self.changes), *arguments],
                              cwd=self.work, env=self.environment, capture_output=True, text=True)

    def both(self):
        self.update(('codex', 'Codex', '0.167.0', 'Codex moves to 0.167.0.'),
                    ('claude-code', 'Claude Code', '2.1.322', 'Claude Code moves to 2.1.322.'))

    def test_every_updated_pin_reaches_beta_in_one_release(self):
        self.both()
        result = self.automatic()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('log', '--format=%s', 'origin/main', '-4').splitlines(), [
            'Prepare Cybex OS 1.0.28 release', 'Update Claude Code to 2.1.322', 'Update Codex to 0.167.0',
            'Release fixture'])
        self.assertEqual(self.git('show', 'origin/main:VERSION'), '1.0.28\n')
        self.assertEqual(self.git('show', 'origin/main:release/notes.md'), (
            '# Cybex OS 1.0.28\n\nCodex moves to 0.167.0.\n\nClaude Code moves to 2.1.322.\n\n'
            'This is a source update with no new ISO. Installation, boot, physical hardware and '
            'staged-updater qualification are separate from source tests and package builds.\n'))
        self.assertEqual(self.git('show', '--stat', '--format=', 'origin/main~1').split()[0],
                         'nix/packages/claude-code/release.json')
        self.assertEqual(self.log.read_text(), '1.0.28\n')

    def test_a_single_pin_keeps_the_release_shape(self):
        self.update(('codex', 'Codex', '0.167.0', 'Codex moves to 0.167.0.'))
        result = self.automatic()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('show', 'origin/main:release/notes.md').split('\n\n')[1], 'Codex moves to 0.167.0.')

    def test_it_rebases_onto_main_and_takes_the_next_version(self):
        self.git('clone', '--quiet', str(self.origin), str(self.other), cwd=self.work.parent)
        self.configure(self.other)
        (self.other / 'VERSION').write_text('1.0.28\n')
        self.git('commit', '--quiet', '-am', 'Prepare Cybex OS 1.0.28 release', cwd=self.other)
        self.git('push', '--quiet', 'origin', 'main', cwd=self.other)
        self.both()
        result = self.automatic()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('show', 'origin/main:VERSION'), '1.0.29\n')
        self.assertEqual(self.git('log', '--format=%s', 'origin/main', '-4').splitlines()[1:], [
            'Update Claude Code to 2.1.322', 'Update Codex to 0.167.0', 'Prepare Cybex OS 1.0.28 release'])

    def test_dry_run_pushes_and_publishes_nothing(self):
        self.both()
        result = self.automatic('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('publish 1.0.28 to beta', result.stdout)
        self.assertIn('Claude Code moves to 2.1.322.', result.stdout)
        self.assertEqual(self.git('rev-parse', 'origin/main'), self.git('rev-parse', 'v1.0.27'))
        self.assertFalse(self.log.exists())

    def test_unexpected_input_or_changes_are_refused(self):
        self.both()
        (self.work / 'VERSION').write_text('9.9.9\n')
        result = self.automatic()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('may be changed', result.stderr)
        self.git('checkout', '--quiet', 'VERSION')
        for changes, message in (([], 'lists no changes'),
                                 ([{'file': 'VERSION', 'title': 'X', 'to': '1', 'notes': 'n'}], 'unexpected pin file'),
                                 ([{'file': 'nix/packages/codex/release.json', 'title': 'Codex', 'to': '1',
                                    'notes': ''}], 'incomplete change')):
            self.changes.write_text(json.dumps(changes))
            result = self.automatic()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)
        self.assertEqual(self.git('rev-parse', 'origin/main'), self.git('rev-parse', 'v1.0.27'))
        self.assertEqual(self.git('log', '--format=%s', '-1'), 'Release fixture\n')
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
