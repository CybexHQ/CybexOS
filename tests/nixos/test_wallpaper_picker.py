"""Wallpaper metering is conservative and offline."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'),
        ROOT / 'desktop/quickshell/scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WallpaperPickerTests(unittest.TestCase):
    def test_metering_includes_guesses_and_unknown_asks_first(self):
        parse = load('network-tool').parse_metered
        for state, expected in [('yes', True), ('yes (guessed)', True), ('no', False),
                                ('no (guessed)', False), ('unknown', True)]:
            result = parse(f'GENERAL.STATE:100 (connected)\nGENERAL.METERED:{state}\n')
            self.assertEqual(result['metered'], expected)
            self.assertEqual(result['known'], state != 'unknown')
        self.assertEqual(parse(''), {'known': False, 'metered': True})
        self.assertEqual(parse('GENERAL.STATE:30 (disconnected)\nGENERAL.METERED:yes\n'
                               'GENERAL.STATE:100 (connected)\nGENERAL.METERED:no\n'),
                         {'known': True, 'metered': False})
        self.assertEqual(parse('GENERAL.TYPE:loopback\nGENERAL.STATE:100 (connected externally)\n'
                               'GENERAL.METERED:unknown\nGENERAL.TYPE:ethernet\n'
                               'GENERAL.STATE:100 (connected)\nGENERAL.METERED:no\n'),
                         {'known': True, 'metered': False})
        self.assertTrue(parse('GENERAL.STATE:100 (connected)\nGENERAL.METERED:no\n'
                              'GENERAL.STATE:100 (connected)\nGENERAL.METERED:yes\n')['metered'])


if __name__ == '__main__':
    unittest.main()
