"""Exercise absent-only personal seeding and private SSH permissions."""
import importlib.machinery
import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('personal_init_checks', str(ROOT / 'lifecycle/bin/cybexos-personal-init'))
spec = importlib.util.spec_from_loader(loader.name, loader)
personal = importlib.util.module_from_spec(spec)
loader.exec_module(personal)


class PersonalInitTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cybexos-personal-init-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / 'home'
        self.home.mkdir()
        self.defaults = ROOT / 'desktop/defaults'
        # The runtime default is copied from this source asset during packaging.
        self.defaults_fixture = Path(temporary.name) / 'defaults'
        self.defaults_fixture.mkdir()
        for name in ('fastfetch.jsonc', 'voxtype.toml'):
            (self.defaults_fixture / name).write_bytes((self.defaults / name).read_bytes())
        (self.defaults_fixture / 'prompt.json').write_bytes((ROOT / 'assets/EDM115-newline2.omp.json').read_bytes())

    def seed(self, proprietary):
        personal.initialize(self.home, self.defaults_fixture, Path('/vendor-share'), proprietary)

    def test_private_ssh_include_and_generation_following_skills(self):
        self.seed(True)
        config = self.home / '.ssh/config'
        self.assertEqual(config.read_text(), f'Include {self.defaults_fixture}/ssh.conf\n')
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(config.parent.stat().st_mode), 0o700)
        for base in ('.agents', '.claude', '.codex'):
            self.assertEqual(str((self.home / base / 'skills/cybexos').readlink()),
                             '/run/current-system/sw/share/cybexos/skill')

    def test_preserves_personal_configuration_and_user_authored_skills(self):
        self.seed(True)
        config = self.home / '.ssh/config'
        config.write_text('Host personal\n  HostName example.invalid\n')
        preference = self.home / '.config/voxtype/config.toml'
        preference.write_text('personal preference\n')
        skill = self.home / '.claude/skills/cybexos'
        skill.unlink()
        skill.mkdir()
        (skill / 'SKILL.md').write_text('User-authored skill\n')
        self.seed(True)
        self.assertEqual(config.read_text(), 'Host personal\n  HostName example.invalid\n')
        self.assertEqual(preference.read_text(), 'personal preference\n')
        self.assertEqual((skill / 'SKILL.md').read_text(), 'User-authored skill\n')

    def test_terminals_follow_the_theme_and_personal_settings_win(self):
        self.seed(False)
        ghostty = (self.home / '.config/ghostty/config').read_text().splitlines()
        self.assertEqual([line for line in ghostty if not line.startswith('#')],
                         [f'config-file = {self.defaults_fixture}/ghostty.conf',
                          'config-file = ?~/.local/state/cybexos/theme/ghostty.conf',
                          'config-file = ?~/.config/ghostty/personal.conf'],
                         'Ghostty loads them in order: personal settings last')
        self.assertIn(f'import = ["{self.defaults_fixture}/alacritty.toml"]',
                      (self.home / '.config/alacritty/alacritty.toml').read_text())
        self.assertTrue((self.home / '.config/foot/foot.ini').read_text().startswith(f'include={self.defaults_fixture}/foot.ini\n'))
        theme = self.home / '.local/state/cybexos/theme/foot.ini'
        self.assertTrue(theme.read_text().startswith('#'), 'foot refuses a missing include')
        theme.write_text('[colors-dark]\nbackground=000000\n')
        self.seed(False)
        self.assertEqual(theme.read_text(), '[colors-dark]\nbackground=000000\n', 'the theme file is the shell\'s')

    def test_terminal_configurations_people_already_have_are_kept(self):
        own = self.home / '.config/ghostty/config.ghostty'
        own.parent.mkdir(parents=True)
        own.write_text('theme = personal\n')
        legacy = self.home / '.config/alacritty/alacritty.yml'
        legacy.parent.mkdir(parents=True)
        legacy.write_text('font: {}\n')
        self.seed(False)
        self.assertFalse((self.home / '.config/ghostty/config').exists())
        self.assertFalse((self.home / '.config/alacritty/alacritty.toml').exists())
        self.assertEqual(own.read_text(), 'theme = personal\n')

    def test_no_ssh_agent_integration_without_proprietary_choice(self):
        self.seed(False)
        self.assertFalse((self.home / '.ssh/config').exists())

    def test_developer_template_is_editable_and_preserves_personal_nvim(self):
        template = self.defaults_fixture / 'nvim'
        template.mkdir()
        (template / 'init.lua').write_text('require("config.lazy")\n')
        (template / 'init.lua').chmod(0o444)
        personal.initialize(self.home, self.defaults_fixture, Path('/vendor-share'), False, True)
        config = self.home / '.config/nvim/init.lua'
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o644)
        config.write_text('personal Neovim configuration\n')
        personal.initialize(self.home, self.defaults_fixture, Path('/vendor-share'), False, True)
        self.assertEqual(config.read_text(), 'personal Neovim configuration\n')


if __name__ == '__main__':
    unittest.main()


class FlathubRemoteTests(unittest.TestCase):
    """The account's Flathub remote is added once; a removal stays a removal."""
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cybexos-personal-flathub-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.calls = []

    def run_flatpak(self, argv, **kwargs):
        self.calls.append(argv)

    def test_added_once_from_the_shipped_repository_file(self):
        repository = ROOT / 'lifecycle/cybexos/flathub.flatpakrepo'
        personal.flathub(self.home, True, repository, run=self.run_flatpak)
        personal.flathub(self.home, True, repository, run=self.run_flatpak)
        self.assertEqual(self.calls, [['flatpak', 'remote-add', '--user', '--if-not-exists', 'flathub', str(repository)]])
        self.assertTrue((self.home / '.local/state/cybexos/flathub-remote').exists())

    def test_turned_off_or_failing_leaves_no_marker(self):
        personal.flathub(self.home, False, Path('/repo'), run=self.run_flatpak)
        self.assertEqual(self.calls, [])
        def fails(argv, **kwargs):
            raise OSError('flatpak is missing')
        personal.flathub(self.home, True, Path('/repo'), run=fails)
        self.assertFalse((self.home / '.local/state/cybexos/flathub-remote').exists(), 'a later login tries again')

    def test_shipped_repository_is_flathub_with_its_signing_key(self):
        text = (ROOT / 'lifecycle/cybexos/flathub.flatpakrepo').read_text()
        self.assertIn('\nUrl=https://dl.flathub.org/repo/\n', text)
        self.assertRegex(text, r'\nGPGKey=[A-Za-z0-9+/=]{2000,}\n')
