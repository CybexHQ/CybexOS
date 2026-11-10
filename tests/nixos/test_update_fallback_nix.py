"""A new Nixpkgs that fails to build, with the real updater and real Nix.

The machine flake, its lock and a "release" are tiny stand-ins: the release's
system is a Nixpkgs `runCommand` that, with the new Nixpkgs revision, also
needs a package whose builder fails (as tectonic did on 2026-11-10). Its
Nixpkgs is this repository's locked Nixpkgs, under its real revision for the
installed system and under another, "verified" revision for the new one: the
same source, already in the store, so Nix resolves both offline. Only release
discovery, the verified record, the release's input update and device
firmware are stand-ins; evaluation, the prebuilt check, the build, its
failure and the fallback are the real ones.

Skipped where Nix can't build (the Nix build sandbox of checks.lifecycle).
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import test_lifecycle as lifecycle
from cybexos import cli
from cybexos.common import Runner, atomic, read
from cybexos.engine import Engine, NotBuilt, copy_config

ROOT = Path(__file__).resolve().parents[2]

RELEASE = r'''{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    lib.system = { broken }: let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      tectonic = pkgs.runCommand "tectonic-0.17.0" { } "echo compiling; exit 101";
      toplevel = pkgs.runCommand "nixos-system-test" { } ''
        mkdir -p $out/sw/bin $out/etc/cybexos
        printf '#!/bin/sh\nexit 0\n' > $out/sw/bin/cybexos-desktop-check
        chmod +x $out/sw/bin/cybexos-desktop-check
        echo '{"schema": 1, "packages": []}' > $out/etc/cybexos/software.json
        ${if broken then "cat ${tectonic}" else ""}
      '';
    in { config.system.build = { inherit toplevel; cybexosExpectedBuilds = [ ];
                                 cybexosVendorBuilds = [ ]; cybexosDeclaredBuilds = [ ]; }; };
  };
}
'''

MACHINE = '''{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.cybexos.url = "github:CybexHQ/CybexOS/%s";
  inputs.cybexos.inputs.nixpkgs.follows = "nixpkgs";
  outputs = { nixpkgs, cybexos, ... }: {
    # The new Nixpkgs carries a package that doesn't build.
    nixosConfigurations.cybexos = cybexos.lib.system { broken = nixpkgs.rev == "%s"; };
  };
}
'''


def revision(*parts):
    """A made-up revision for this exact content: Nix remembers which content a
    GitHub revision had, so different content must never reuse one."""
    return hashlib.sha1('/'.join(parts).encode()).hexdigest()


def nix(*args):
    return subprocess.run(['nix', '--extra-experimental-features', 'nix-command flakes', *args],
                          capture_output=True, text=True, timeout=600)


def usable():
    # A Nix build sandbox (checks.lifecycle) has no daemon to build with.
    if not shutil.which('nix') or not Path('/nix/var/nix/daemon-socket/socket').exists():
        return False
    try:
        return nix('store', 'info').returncode == 0 or nix('store', 'ping').returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


class Inputs(Runner):
    """The real Runner, except the release's input update: it would ask GitHub."""
    def __init__(self, release, revision):
        super().__init__()
        self.release, self.revision, self.builds = release, revision, 0

    def __call__(self, *args, **kwargs):
        args = tuple(map(str, args))
        if args[:4] == ('nix', 'flake', 'update', 'cybexos'):
            config = Path(args[args.index('--flake') + 1].removeprefix('path:'))
            lock = read(config / 'flake.lock')
            lock['nodes']['cybexos']['locked'] |= {'rev': self.revision, 'narHash': self.release}
            lock['nodes']['cybexos']['original']['rev'] = self.revision
            atomic(config / 'flake.lock', lock)
            return ''
        if args[:2] == ('nix', 'build') and '--dry-run' not in args:
            self.builds += 1
        return super().__call__(*args, **kwargs)


@unittest.skipUnless(usable(), 'needs a Nix that can build')
class FallbackWithNix(unittest.TestCase):
    def setUp(self):
        firmware = patch('cybexos.engine.firmware.discover', return_value={'state': 'current', 'devices': []})
        firmware.start()
        self.addCleanup(firmware.stop)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        upstream = read(ROOT / 'flake.lock')
        nixpkgs = upstream['nodes'][upstream['nodes'][upstream['root']]['inputs']['nixpkgs']]
        (base / 'release').mkdir()
        (base / 'release/flake.nix').write_text(RELEASE)
        added = nix('store', 'add', '--name', 'source', str(base / 'release'))
        if added.returncode:
            added = nix('store', 'add-path', '--name', 'source', str(base / 'release'))
        self.assertEqual(added.returncode, 0, added.stderr)
        info = json.loads(nix('path-info', '--json', added.stdout.strip()).stdout)
        release = (info[0] if isinstance(info, list) else next(iter(info.values())))['narHash']
        installed, self.released = revision('installed', release), revision('released', release)
        new = revision('nixpkgs', nixpkgs['locked']['narHash'])
        config = base / 'nixos'
        (config / 'local').mkdir(parents=True)
        (config / 'flake.nix').write_text(MACHINE % (installed, new))
        (config / 'local/personal.nix').write_text('{}\n')
        atomic(config / 'flake.lock', {'version': 7, 'root': 'root', 'nodes': {
            'root': {'inputs': {'nixpkgs': 'nixpkgs', 'cybexos': 'cybexos'}},
            'nixpkgs': {'locked': nixpkgs['locked'], 'original': {
                'type': 'github', 'owner': 'NixOS', 'repo': 'nixpkgs', 'ref': 'nixos-unstable'}},
            'cybexos': {'inputs': {'nixpkgs': ['nixpkgs']},
                        'locked': {'type': 'github', 'owner': 'CybexHQ', 'repo': 'CybexOS', 'rev': installed,
                                   'narHash': release, 'lastModified': 1},
                        'original': {'type': 'github', 'owner': 'CybexHQ', 'repo': 'CybexOS', 'rev': installed}}}})
        self.installed_nixpkgs = nixpkgs['locked']
        built = nix('build', '--no-link', '--print-out-paths', '--no-update-lock-file',
                    f'path:{config}#nixosConfigurations.cybexos.config.system.build.toplevel')
        self.assertEqual(built.returncode, 0, built.stderr)
        (base / 'current-system').symlink_to(built.stdout.strip())
        atomic(base / 'release.json', {'version': '1.0.0', 'architecture': 'x86_64-linux', 'nixos': 'unstable'})
        atomic(base / 'update.json', {'channel': 'beta'})
        self.runner = Inputs(release, self.released)
        self.engine = Engine(base / 'state', config, self.runner, base / 'release.json', base / 'update.json',
                             base / 'current-system', base / 'current-system')
        copy_config(config, base / 'deployed')
        (self.engine.state / 'deployed').symlink_to(base / 'deployed')
        candidate = lifecycle.release() | {'revision': self.released, 'channel': 'beta'}
        self.engine.channel = lambda: candidate
        self.engine.release_source = lambda found: found | {'narHash': release}
        # The new Nixpkgs, as Cybex OS's canary would have verified it.
        self.engine.verified_nixpkgs = lambda: [{'rev': new, 'narHash': nixpkgs['locked']['narHash'],
                                                 'lastModified': nixpkgs['locked']['lastModified'] + 1,
                                                 'releases': ['1.0.0', '1.1.0']}]

    def test_the_release_comes_alone_and_the_packages_wait_without_building_again(self):
        cli.stage_update(self.engine, 'both', 'a' * 32)
        status = read(self.engine.status_path)
        self.assertEqual((status['state'], status['scope'], status['availableVersion']), ('ready', 'cybexos', '1.1.0'))
        self.assertEqual(status['inputs']['nixpkgs'], self.installed_nixpkgs)
        self.assertEqual(status['inputs']['cybexos']['rev'], self.released)
        self.assertEqual(self.runner.builds, 2, 'the combined system, then the release alone')
        remembered = read(self.engine.state / 'failed-builds.json')
        self.assertEqual([Path(path).name.split('-', 1)[1] for path in remembered], ['tectonic-0.17.0.drv'])
        # The packages on their own: they wait, and tectonic isn't compiled again.
        with self.assertRaises(NotBuilt) as raised:
            self.engine.stage('upstream')
        self.assertEqual(raised.exception.names, ['tectonic-0.17.0'])
        self.assertEqual(self.runner.builds, 2)
        kept = read(self.engine.status_path)
        self.assertEqual((kept['state'], kept['scope'], kept['replacement']['state'],
                          kept['replacement']['notPrebuilt']), ('ready', 'cybexos', 'waiting', ['tectonic-0.17.0']))


if __name__ == '__main__':
    unittest.main()
