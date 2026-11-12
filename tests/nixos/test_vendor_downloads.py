"""scripts/vendor-downloads with a recorded `nix build --dry-run`, fixture .drv
files and a fake Nix store; no network, no Nix."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('vendor_downloads', str(ROOT / 'scripts/vendor-downloads'))
spec = importlib.util.spec_from_loader(loader.name, loader)
vd = importlib.util.module_from_spec(spec)
loader.exec_module(vd)

SNAP = '/nix/store/qdm7p7iy3avb52yg5b3am2c94h57x1y3-spotify-1.2.95.453.g0eeebbed-99.snap'
SOURCE = '/nix/store/74akpw2f6gl2lzb1p1xanhigzilvmwc2-source'
REAL_RUN = subprocess.run  # the fakes below replace subprocess.run itself


def done(code=0, stdout='', stderr=''):
    return subprocess.CompletedProcess([], code, stdout, stderr)


class Plan(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', str(self.dir)]))
        self.drvs = {
            'snap': ('Derive([("out","%s","sha512","2118c6")],[],[],"x86_64-linux","builtin:fetchurl",[],[])' % SNAP),
            'source': ('Derive([("out","%s","r:sha256","0a1b")],[],[],"x86_64-linux","/bin/sh",[],[])' % SOURCE),
            'app': 'Derive([("out","/nix/store/aaaa-chrome-156","","")],[],[],"x86_64-linux","/bin/sh",[],[])',
        }
        for name, text in self.drvs.items():
            (self.dir / (name + '.drv')).write_text(text)

    def dry_run(self, *order):
        built = ''.join(f'  {self.dir / (name + ".drv")}\n' for name in order)
        return done(stderr=f'these {len(order)} derivations will be built:\n{built}'
                           'these 2 paths will be fetched (1.0 MiB download, 4.0 MiB unpacked):\n'
                           f'  /nix/store/bbbb-bash.drv\n  /nix/store/cccc-glibc\n')

    def plan(self, *order):
        out = self.dir / 'plan.json'
        with mock.patch.object(vd.subprocess, 'run', return_value=self.dry_run(*order)), \
                mock.patch('builtins.print') as printed:
            vd.plan(types.SimpleNamespace(out=str(out), installables=['.#checks.x86_64-linux.browser-1password']))
        key = next(c.args[0] for c in printed.call_args_list if str(c.args[0]).startswith('key='))
        return json.loads(out.read_text()), key

    def test_only_fixed_output_derivations_that_will_be_built_are_downloads(self):
        downloads, _ = self.plan('snap', 'app', 'source')
        self.assertEqual([(d['path'], d['algo'], d['recursive']) for d in downloads],
                         [(SOURCE, 'sha256', True), (SNAP, 'sha512', False)])
        self.assertEqual([d['name'] for d in downloads], ['source', 'spotify-1.2.95.453.g0eeebbed-99.snap'])

    def test_the_cache_key_names_exactly_the_set_of_downloads(self):
        _, key = self.plan('snap', 'source')
        self.assertEqual(self.plan('source', 'app', 'snap')[1], key)
        self.assertNotEqual(self.plan('snap')[1], key)
        self.assertTrue(key.startswith('key=vendor-downloads-'))


class Fetch(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', str(self.dir)]))
        self.cache = self.dir / 'cache'
        self.store = set()
        self.snap = {'drv': '/nix/store/gq03-spotify.snap.drv', 'path': SNAP,
                     'name': 'spotify-1.2.95.453.g0eeebbed-99.snap', 'algo': 'sha512', 'recursive': False}
        self.plan = self.dir / 'plan.json'
        self.plan.write_text(json.dumps([self.snap]))
        self.calls = []
        self.builds = []

    def nix(self, cmd, **kw):
        self.calls.append(cmd)
        if cmd[:2] == ['nix-store', '--check-validity']:
            return done(0 if cmd[2] in self.store else 1)
        if cmd[:2] == ['nix-store', '--add-fixed']:
            good = Path(cmd[-1]).read_text() == 'snap'
            return done(stdout=(SNAP if good else '/nix/store/zzzz-other') + '\n')
        if cmd[0] == 'nix' and 'build' in cmd:
            outcome = self.builds.pop(0)
            if outcome == 'ok':
                self.store.add(SNAP)
                return done()
            return done(1, stderr=f'error: {outcome}\n')
        if cmd[0] == 'cp':
            Path(cmd[-1]).write_text('snap')
            return done()
        return REAL_RUN(cmd, **kw)

    def fetch(self):
        with mock.patch.object(vd.subprocess, 'run', side_effect=self.nix), \
                mock.patch.object(vd.time, 'sleep') as sleep, mock.patch('builtins.print'), \
                mock.patch.object(vd.sys.stderr, 'write'):
            code = vd.fetch(types.SimpleNamespace(plan=str(self.plan), cache=str(self.cache)))
        return code, [c.args[0] for c in sleep.call_args_list]

    def cached(self, text):
        entry = self.cache / Path(SNAP).name
        entry.mkdir(parents=True)
        (entry / self.snap['name']).write_text(text)

    def test_a_cached_copy_on_its_pinned_path_needs_no_download(self):
        self.cached('snap')
        self.assertEqual(self.fetch(), (0, []))
        self.assertFalse(any(c[0] == 'nix' for c in self.calls))

    def test_a_cached_copy_that_does_not_match_is_replaced_by_a_download(self):
        self.cached('tampered')
        self.builds = ['ok']
        self.assertEqual(self.fetch(), (0, []))
        self.assertEqual((self.cache / Path(SNAP).name / self.snap['name']).read_text(), 'snap')

    def test_an_unreachable_host_is_tried_again_minutes_later(self):
        self.builds = ['cannot download spotify.snap from any mirror', 'ok']
        code, waits = self.fetch()
        self.assertEqual(code, 0)
        self.assertEqual(waits, vd.WAITS[:1])
        self.assertTrue((self.cache / Path(SNAP).name).is_dir())

    def test_it_gives_up_after_three_attempts(self):
        self.builds = ['cannot download spotify.snap from any mirror'] * 3
        code, waits = self.fetch()
        self.assertEqual((code, len(waits)), (1, 2))

    def test_a_hash_mismatch_is_not_retried(self):
        self.builds = ['hash mismatch in fixed-output derivation']
        self.assertEqual(self.fetch(), (1, []))

    def test_the_cache_keeps_only_the_planned_downloads(self):
        (self.cache / 'old-download').mkdir(parents=True)
        self.store.add(SNAP)
        self.assertEqual(self.fetch(), (0, []))
        self.assertEqual(sorted(p.name for p in self.cache.iterdir()), [Path(SNAP).name])


if __name__ == '__main__':
    unittest.main()
