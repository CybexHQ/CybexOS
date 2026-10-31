"""Real GIO associations and argv-safe launches in disposable XDG directories."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'assets/scripts/cybexos-apps'
loader = importlib.machinery.SourceFileLoader('default_applications', str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
apps = importlib.util.module_from_spec(spec); loader.exec_module(apps)
try:
    apps.libraries()
    HAS_GIO = True
except ImportError:
    HAS_GIO = False


class EffectiveDefaultsTests(unittest.TestCase):
    def test_effective_defaults_resolves_only_the_docks_roles_without_catalog(self):
        browser = Mock(); browser.get_id.return_value = 'browser.desktop'
        terminal = Mock(); terminal.get_id.return_value = 'terminal.desktop'
        files = Mock(); files.get_id.return_value = 'files.desktop'
        gio = Mock()
        gio.AppInfo.get_default_for_type.side_effect = lambda mime, _: {'x-scheme-handler/http': browser,
                                                                         'inode/directory': files}[mime]
        gio.AppInfo.get_all.side_effect = AssertionError('effective defaults must not enumerate applications')
        desktop = Mock(); desktop.new.return_value = terminal
        process = Mock(returncode=0, stdout='terminal.desktop:desktop-action\n')
        with patch.object(apps, 'libraries', return_value=(gio, None, desktop)), \
                patch.object(apps, 'load_choices', return_value={}), \
                patch.object(apps.subprocess, 'run', return_value=process):
            self.assertEqual(apps.effective_defaults(), {'browser':'browser.desktop', 'terminal':'terminal.desktop',
                                                         'files':'files.desktop'})
        self.assertEqual([call.args for call in gio.AppInfo.get_default_for_type.call_args_list],
                         [('x-scheme-handler/http', False), ('inode/directory', False)])
        gio.AppInfo.get_all.assert_not_called()
        desktop.new.assert_called_once_with('terminal.desktop')

    def test_missing_defaults_remain_empty_and_resolution_errors_propagate(self):
        with patch.object(apps, 'load_choices', return_value={}), \
                patch.object(apps, 'current', return_value=None):
            self.assertEqual(apps.effective_defaults(), {'browser':'', 'terminal':'', 'files':''})
        with patch.object(apps, 'load_choices', side_effect=ValueError('Preserve preferences')):
            with self.assertRaisesRegex(ValueError, 'Preserve preferences'):
                apps.effective_defaults()
        with patch.object(apps, 'load_choices', return_value={}), \
                patch.object(apps, 'current', side_effect=TimeoutError('terminal lookup')):
            with self.assertRaises(TimeoutError):
                apps.effective_defaults()


class MailtoTests(unittest.TestCase):
    def test_web_mail_compose_pages_keep_every_field_and_literal_plus(self):
        address = 'mailto:a@example.org,b%40example.org?Subject=Two%20words+plus&body=Line%201%0ALine%202&cc=c@example.org&bcc='
        self.assertEqual(apps.compose_url('gmail', address),
                         'https://mail.google.com/mail/?view=cm&fs=1&to=a%40example.org%2Cb%40example.org'
                         '&cc=c%40example.org&su=Two%20words%2Bplus&body=Line%201%0ALine%202')
        self.assertEqual(apps.compose_url('outlook', 'mailto:?to=x@example.org&subject=Hi'),
                         'https://outlook.live.com/mail/0/deeplink/compose?to=x%40example.org&subject=Hi')
        self.assertEqual(apps.compose_url('outlook', ''), 'https://outlook.live.com/mail/0/deeplink/compose')
        for bad in ('https://example.org/', 'javascript:alert(1)', 'mailto:' + 'a' * 9000):
            with self.assertRaises(ValueError):
                apps.compose_url('gmail', bad)
        with self.assertRaises(ValueError):
            apps.compose_url('yahoo', 'mailto:a@example.org')


class PendingTests(unittest.TestCase):
    def test_waiting_choices_expire_after_a_day_and_ignore_malformed_entries(self):
        now = 1_000_000
        value = {'pending': {'browser': {'id': 'a.desktop', 'since': now - 60},
                             'terminal': {'id': 'b.desktop', 'since': now - apps.PENDING_SECONDS - 1},
                             'editor': {'id': 3, 'since': now}, 'unknown': {'id': 'c.desktop', 'since': now},
                             'video': 'd.desktop'}}
        self.assertEqual(apps.pending_choices(value, now), {'browser': 'a.desktop'})


@unittest.skipUnless(HAS_GIO and shutil.which('xdg-terminal-exec'), 'GIO and xdg-terminal-exec are provided by nix develop')
class DefaultApplicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.data = self.base / 'data'; (self.data / 'applications').mkdir(parents=True)
        self.log = self.base / 'launch.json'
        self.capture = self.base / 'capture'
        self.capture.write_text('#!' + sys.executable + '\nimport os,sys,json\nfrom pathlib import Path\nPath(os.environ["APPLICATION_LOG"]).write_text(json.dumps(sys.argv[1:]))\n')
        self.capture.chmod(0o755)
        self.env = os.environ | {'HOME':str(self.base), 'XDG_CONFIG_HOME':str(self.base / 'config'),
             'XDG_DATA_HOME':str(self.data), 'XDG_DATA_DIRS':str(self.base / 'empty'),
             'XDG_CONFIG_DIRS':str(self.base / 'empty-config'), 'XDG_CURRENT_DESKTOP':'Hyprland',
             'XDG_CACHE_HOME':str(self.base / 'cache'), 'APPLICATION_LOG':str(self.log),
             'DBUS_SESSION_BUS_ADDRESS':'unix:path=/nonexistent-cybexos-test-bus', 'VISUAL':'', 'EDITOR':''}
        self.desktop('browser.desktop', 'Browser', 'MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;\nActions=new-private-window;\n\n[Desktop Action new-private-window]\nName=Private\nExec=' + str(self.capture) + ' --private\n')
        self.desktop('editor.desktop', 'Editor', 'MimeType=text/plain;text/html;\n')
        self.desktop('terminal.desktop', 'Terminal', 'Categories=System;TerminalEmulator;\nX-TerminalArgExec=-e\nX-TerminalArgTitle=--title=\n')
        subprocess.run(['update-desktop-database', str(self.data / 'applications')], check=True, capture_output=True, env=self.env)

    def desktop(self, identifier, name, extra):
        (self.data / 'applications' / identifier).write_text('[Desktop Entry]\nType=Application\nName=' + name + '\nExec=' + str(self.capture) + (' %U\n' if name == 'Browser' else ' %F\n') + extra)

    def run_apps(self, *arguments):
        result = subprocess.run([sys.executable, str(SCRIPT), *arguments], env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def captured(self):
        for _ in range(100):
            if self.log.exists(): return json.loads(self.log.read_text())
            time.sleep(.02)
        self.fail('Application did not launch')

    def test_associations_preserve_other_mime_choices_and_update_browser_launches(self):
        config = self.base / 'config'; config.mkdir()
        (config / 'mimeapps.list').write_text('[Default Applications]\napplication/x-personal=personal.desktop;\n')
        result = self.run_apps('set', 'browser', 'browser.desktop')
        self.assertEqual(result['roles']['browser']['selected'], 'browser.desktop')
        self.assertNotIn('editor.desktop', [row['value'] for row in result['roles']['browser']['choices']])
        self.assertIn('application/x-personal=personal.desktop;', (config / 'mimeapps.list').read_text())
        self.run_apps('browser', 'https://example.invalid/a?x=two%20words')
        self.assertEqual(self.captured(), ['https://example.invalid/a?x=two%20words'])
        self.log.unlink()
        self.run_apps('browser', '--private')
        self.assertEqual(self.captured(), ['--private'])

    def test_terminal_preferences_and_arguments_with_spaces(self):
        self.run_apps('set', 'terminal', 'terminal.desktop')
        self.run_apps('terminal', '--title=Two words', '--', 'printf', 'literal $(touch no-file)')
        self.assertEqual(self.captured(), ['--title=Two words', '-e', 'printf', 'literal $(touch no-file)'])
        self.assertFalse((self.base / 'no-file').exists())

    def test_effective_defaults_matches_full_status_and_follows_external_changes(self):
        self.run_apps('set', 'browser', 'browser.desktop')
        self.run_apps('set', 'terminal', 'terminal.desktop')
        before = (self.base / 'config/cybexos/default-applications.json').read_bytes()
        status = self.run_apps('status')['roles']
        self.assertEqual(self.run_apps('effective-defaults'),
                         {role:status[role]['effective'] for role in ('browser', 'terminal', 'files')})
        self.desktop('other-browser.desktop', 'Browser', 'MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;\n')
        path = self.base / 'config/mimeapps.list'
        path.write_text(path.read_text().replace('browser.desktop', 'other-browser.desktop'))
        status = self.run_apps('status')['roles']
        effective = self.run_apps('effective-defaults')
        self.assertEqual(effective, {role:status[role]['effective'] for role in ('browser', 'terminal', 'files')})
        self.assertEqual(effective['browser'], 'other-browser.desktop')
        self.assertEqual((self.base / 'config/cybexos/default-applications.json').read_bytes(), before)

    def test_explicit_editor_override_and_removed_application_choice_survive(self):
        self.run_apps('set', 'editor', 'editor.desktop')
        self.env['EDITOR'] = str(self.capture) + ' --personal'
        self.run_apps('edit', 'a file.txt')
        self.assertEqual(self.captured(), ['--personal', 'a file.txt'])
        (self.data / 'applications/editor.desktop').unlink()
        state = self.run_apps('status')
        self.assertTrue(state['roles']['editor']['unavailable'])
        self.assertEqual(state['roles']['editor']['selected'], 'editor.desktop')
        saved = json.loads((self.base / 'config/cybexos/default-applications.json').read_text())
        self.assertEqual(saved['choices']['editor'], 'editor.desktop')

    def test_external_mime_selection_takes_precedence_over_missing_saved_choice(self):
        self.run_apps('set', 'editor', 'editor.desktop')
        self.desktop('other.desktop', 'Other', 'MimeType=text/plain;\n')
        (self.data / 'applications/editor.desktop').unlink()
        path = self.base / 'config/mimeapps.list'
        path.write_text(path.read_text().replace('editor.desktop', 'other.desktop'))
        role = self.run_apps('status')['roles']['editor']
        self.assertFalse(role['unavailable'])
        self.assertEqual(role['selected'], 'other.desktop')

    def test_selected_browser_handles_webapps_and_terminal_editor_gets_file_uris(self):
        self.run_apps('set', 'browser', 'browser.desktop')
        self.run_apps('webapp', 'https://example.invalid/app')
        self.assertEqual(self.captured(), ['https://example.invalid/app'])
        self.log.unlink()
        self.run_apps('set', 'terminal', 'terminal.desktop')
        self.desktop('console-editor.desktop', 'Console editor', 'MimeType=text/plain;\nTerminal=true\n')
        path = self.data / 'applications/console-editor.desktop'
        path.write_text(path.read_text().replace(' %F', ' %U'))
        self.run_apps('set', 'editor', 'console-editor.desktop')
        target = self.base / 'a file.txt'
        self.run_apps('edit', str(target))
        self.assertEqual(self.captured(), ['-e', str(self.capture), target.as_uri()])

    def test_new_roles_list_only_real_handlers_and_web_mail(self):
        self.desktop('files.desktop', 'Files', 'MimeType=inode/directory;\nCategories=Utility;FileManager;\n')
        self.desktop('code.desktop', 'Code', 'MimeType=text/plain;inode/directory;\nCategories=Development;\n')
        self.desktop('music.desktop', 'Music', 'MimeType=audio/flac;audio/mpeg;\n')
        self.desktop('mail.desktop', 'Mail', 'MimeType=x-scheme-handler/mailto;\n')
        self.desktop('cybexos-mail-gmail.desktop', 'Gmail', 'NoDisplay=true\n')
        self.desktop('hidden-mail.desktop', 'Hidden', 'MimeType=x-scheme-handler/mailto;\nNoDisplay=true\n')
        roles = self.run_apps('status')['roles']
        self.assertNotEqual(roles['mail']['effective'], 'cybexos-mail-gmail.desktop', 'web mail is never an implicit default')
        self.assertEqual([c['value'] for c in roles['files']['choices']], ['files.desktop'])
        self.assertEqual([c['value'] for c in roles['music']['choices']], ['music.desktop'])
        self.assertEqual(sorted(c['value'] for c in roles['mail']['choices']), ['cybexos-mail-gmail.desktop', 'mail.desktop'])
        result = self.run_apps('set', 'mail', 'cybexos-mail-gmail.desktop')
        self.assertEqual(result['roles']['mail']['effective'], 'cybexos-mail-gmail.desktop')
        self.assertTrue(result['roles']['mail']['personal'])

    def test_reset_returns_to_the_system_default_and_keeps_other_associations(self):
        system = self.base / 'system'; system.mkdir()
        self.env['XDG_CONFIG_DIRS'] = str(system)
        self.desktop('other-editor.desktop', 'Other', 'MimeType=text/plain;\n')
        (system / 'mimeapps.list').write_text('[Default Applications]\ntext/plain=editor.desktop;\n')
        config = self.base / 'config'; config.mkdir()
        (config / 'mimeapps.list').write_text('[Default Applications]\napplication/x-personal=personal.desktop;\n')
        before = self.run_apps('status')['roles']['editor']
        self.assertEqual((before['effective'], before['system'], before['personal']), ('editor.desktop', 'editor.desktop', False))
        chosen = self.run_apps('set', 'editor', 'other-editor.desktop')['roles']['editor']
        self.assertEqual((chosen['effective'], chosen['system'], chosen['personal']), ('other-editor.desktop', 'editor.desktop', True))
        after = self.run_apps('reset', 'editor')['roles']['editor']
        self.assertEqual((after['effective'], after['personal']), ('editor.desktop', False))
        self.assertIn('application/x-personal=personal.desktop;', (config / 'mimeapps.list').read_text())
        self.assertNotIn('other-editor.desktop', (config / 'mimeapps.list').read_text().split('[Added Associations]')[0])

    def test_terminal_reset_removes_only_the_chosen_entry(self):
        system = self.base / 'system'; system.mkdir()
        self.env['XDG_CONFIG_DIRS'] = str(system)
        (system / 'xdg-terminals.list').write_text('terminal.desktop\n')
        self.desktop('other-terminal.desktop', 'Other terminal', 'Categories=System;TerminalEmulator;\n')
        config = self.base / 'config'; config.mkdir()
        (config / 'xdg-terminals.list').write_text('personal.desktop\n')
        self.run_apps('set', 'terminal', 'other-terminal.desktop')
        self.assertEqual((config / 'xdg-terminals.list').read_text(), 'other-terminal.desktop\npersonal.desktop\n')
        role = self.run_apps('reset', 'terminal')['roles']['terminal']
        self.assertEqual((config / 'xdg-terminals.list').read_text(), 'personal.desktop\n')
        self.assertEqual((role['system'], role['personal']), ('terminal.desktop', False))
        (config / 'xdg-terminals.list').write_text('other-terminal.desktop\n')
        self.run_apps('set', 'terminal', 'other-terminal.desktop')
        self.run_apps('reset', 'terminal')
        self.assertFalse((config / 'xdg-terminals.list').exists())

    def test_a_choice_waits_for_its_app_then_applies_once_installed(self):
        waiting = self.run_apps('set', 'browser', 'later.desktop', '--when-installed')['roles']['browser']
        self.assertEqual((waiting['pending'], waiting['personal']), ('later.desktop', False))
        result = subprocess.run([sys.executable, str(SCRIPT), 'set', 'browser', 'later.desktop'], env=self.env,
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.desktop('later.desktop', 'Browser', 'MimeType=x-scheme-handler/http;x-scheme-handler/https;\n')
        state = self.run_apps('status')
        self.assertEqual(state['settled'], ['browser'])
        self.assertEqual((state['roles']['browser']['effective'], state['roles']['browser']['pending']), ('later.desktop', ''))
        self.assertEqual(self.run_apps('status')['settled'], [])
        self.run_apps('set', 'editor', 'missing.desktop', '--when-installed')
        self.assertEqual(self.run_apps('cancel', 'editor')['roles']['editor']['pending'], '')
        saved = json.loads((self.base / 'config/cybexos/default-applications.json').read_text())
        self.assertNotIn('pending', saved)

    def test_files_open_in_the_selected_file_manager(self):
        self.desktop('files.desktop', 'Files', 'MimeType=inode/directory;\nCategories=Utility;FileManager;\n')
        self.run_apps('set', 'files', 'files.desktop')
        self.run_apps('files', str(self.base / 'a folder'))
        self.assertEqual(self.captured(), [str(self.base / 'a folder')])

    def test_terminals_without_argument_keys_get_their_own_options(self):
        self.desktop('Alacritty.desktop', 'Alacritty', 'Categories=System;TerminalEmulator;\n')
        self.run_apps('set', 'terminal', 'Alacritty.desktop')
        self.run_apps('terminal', '--hold', '--app-id=cybexos-agent', '--title=Two words', '--', 'printf', '$(x)')
        self.assertEqual(self.captured(), ['--hold', '--class', 'cybexos-agent', '--title', 'Two words', '-e', 'printf', '$(x)'])
        self.log.unlink()
        self.run_apps('terminal')
        self.assertEqual(self.captured(), [])

