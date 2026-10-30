"""What Nix would download, and what it would have to build on this computer.

Cybex OS installs prebuilt packages only. NixOS's cache supplies Nixpkgs
outputs; a missing output means NixOS has not built it (yet), or a personal
override changed it. Configuration files, and Cybex OS's own short builds,
are expected local builds. Nothing here runs a build: every check is a
`--dry-run` against the machine's own store and configured substituters.
"""
import json
import re

from .common import Failure, parse

STORE = re.compile(r'/nix/store/[a-z0-9]{32}-[^/\s]+')
SIZE = re.compile(r'\(([0-9.]+) (B|KiB|MiB|GiB|TiB) download')
UNITS = {'B': 1, 'KiB': 1024, 'MiB': 1024 ** 2, 'GiB': 1024 ** 3, 'TiB': 1024 ** 4}


def name(path):
    """`/nix/store/<hash>-gimp-3.0.6.drv` -> `gimp-3.0.6`."""
    base = path.rsplit('/', 1)[-1]
    base = base.split('-', 1)[1] if '-' in base else base
    return base[:-4] if base.endswith('.drv') else base


def parse_dry_run(text):
    """Parse `nix build --dry-run` diagnostics (singular and plural forms)."""
    result = {'build': [], 'fetch': [], 'downloadBytes': 0}
    section = None
    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r'(these \d+ derivations|this derivation) will be built', stripped):
            section = 'build'
        elif re.match(r'(these \d+ paths|this path) will be fetched', stripped):
            section = 'fetch'
            size = SIZE.search(stripped)
            if size:
                result['downloadBytes'] = int(float(size[1]) * UNITS[size[2]])
        elif line.startswith('  ') and section and STORE.fullmatch(stripped):
            result[section].append(stripped)
        elif stripped and not line.startswith('  '):
            section = None
    return result


def dry_run(run, *installables, options=(), timeout=900):
    """Build/fetch plan for flake installables without building anything."""
    output = run('nix', 'build', '--dry-run', '--no-link', *options, *installables,
                 timeout=timeout, sensitive=True, diagnostics=True)
    return parse_dry_run(output)


def attributes(env):
    """Derivation attributes, including structured ones (`__json`)."""
    if '__json' in env:
        try:
            value = json.loads(env['__json'])
        except ValueError:
            return {}
        return value if isinstance(value, dict) else {}
    return env


def kind(info):
    """How a derivation that is not in any cache gets built here.

    `fetch`: a fixed-output download. `trivial`: marked local-only by design.
    `configuration`: no source of its own (`src`/`srcs`); NixOS generates
    pam.d, the initrd, setuid wrappers, dconf and AppArmor rules this way
    without marking them local-only. `compile`: everything else, a package
    built from its source on this computer.
    """
    if any(isinstance(output, dict) and 'hash' in output for output in (info.get('outputs') or {}).values()):
        return 'fetch'
    attrs = attributes(info.get('env') or {})
    if attrs.get('preferLocalBuild') in (True, '1') or attrs.get('allowSubstitutes') in (False, ''):
        return 'trivial'
    if not any(attrs.get(key) for key in ('src', 'srcs')):
        return 'configuration'
    return 'compile'


def show(run, derivations):
    """`nix derivation show` for the given .drv paths, keyed by full path."""
    if not derivations:
        return {}
    data = parse(run('nix', 'derivation', 'show', *derivations, timeout=600, sensitive=True))
    if not isinstance(data, dict):
        raise Failure('Nix returned invalid derivation metadata.')
    return {key if key.startswith('/nix/store/') else '/nix/store/' + key: value
            for key, value in data.items() if isinstance(value, dict)}


def compiles(run, derivations, *, root=None, expected=()):
    """Names of real builds that are not expected local builds.

    Starting from `root` (when given), descend through trivial and
    configuration derivations only: anything needed solely to build an
    expected derivation (Cybex OS's own packages, unfree vendor downloads) or
    a compiled one is covered by it. Without a root every unexpected compile
    counts.
    """
    pending = set(derivations)
    graph = show(run, sorted(pending))
    expected = set(expected)
    found = []
    if root is None:
        return sorted({name(d) for d, info in graph.items() if d not in expected and kind(info) == 'compile'})
    seen, frontier = set(), [root]
    while frontier:
        current = frontier.pop()
        if current in seen or current not in graph:
            continue
        seen.add(current)
        if current in expected:
            continue
        sort = kind(graph[current])
        if sort == 'compile':
            found.append(name(current))
            continue
        if sort in ('trivial', 'configuration'):
            for child in graph[current].get('inputDrvs') or {}:
                child = child if child.startswith('/nix/store/') else '/nix/store/' + child
                if child in pending:
                    frontier.append(child)
    return sorted(set(found))
