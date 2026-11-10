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


def waiting_packages(status):
    """An update waiting for cache outputs, not a failed personal change."""
    names = status.get('notPrebuilt')
    if (status.get('state') != 'failed' or status.get('changeKind') != 'update'
            or not isinstance(names, list) or not names
            or any(not isinstance(item, str) or not item.strip() for item in names)):
        return []
    return names


def incompatible(status):
    """An update waiting for a Cybex OS release that supports its Nixpkgs."""
    value = status.get('incompatible')
    if (status.get('state') != 'failed' or status.get('changeKind') != 'update' or not isinstance(value, dict)
            or value.get('origin') not in ('cybexos', 'unknown')):
        return None
    return value


def held(status):
    """Waiting for NixOS's cache or for a Cybex OS release, not for the person."""
    return bool(waiting_packages(status)) or incompatible(status) is not None


def hold_target(status, sources):
    """Whether discovery names the held candidate, a changed one, or is unknown.

    Only exact source identities can suppress a notification or permit an
    early automatic retry. Older status records without identities remain
    waiting, without guessing which revisions they checked.
    """
    if not held(status):
        return ''
    if (sources.get('firmware') or {}).get('state') == 'available':
        return 'changed'
    selected = status.get('inputs') or {}
    known, unknown = False, False
    for source, name, field in (('upstream', 'nixpkgs', 'available'), ('cybexos', 'cybexos', 'revision')):
        candidate = sources.get(source) or {}
        if candidate.get('state') != 'available':
            continue
        attempted = (selected.get(name) or {}).get('rev')
        revision = candidate.get(field)
        if not attempted or not revision:
            unknown = True
        elif attempted != revision:
            return 'changed'
        else:
            known = True
    return 'same' if known and not unknown else 'unknown'


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


def attributes(info):
    """Derivation attributes, including structured ones.

    Nix 2.34's derivation format (version 4) moves `__structuredAttrs`
    packages' attributes out of `env` into `structuredAttrs`, leaving only
    the output paths in `env`; older Nix keeps them as JSON in `env.__json`.
    Reading `env` alone makes such a package look source-less and lets an
    uncached build through as configuration.
    """
    if isinstance(info.get('structuredAttrs'), dict):
        return info['structuredAttrs']
    env = info.get('env') or {}
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
    attrs = attributes(info)
    # A Linux build is never configuration or an intentionally local helper,
    # even if an override adds those flags or removes its source attribute.
    if kernel_build(info):
        return 'compile'
    if attrs.get('preferLocalBuild') in (True, '1') or attrs.get('allowSubstitutes') in (False, ''):
        return 'trivial'
    if not any(attrs.get(key) for key in ('src', 'srcs')):
        return 'configuration'
    return 'compile'


def kernel_build(info):
    """Recognize Nixpkgs' kernel and image-rebuild recipes.

    External modules use the kernel as an input but do not install a kernel
    image and its in-tree modules. Keep their ordinary local-build allowance.
    """
    attrs = attributes(info)
    # rebuildImage runs kbuild again from the kernel's dev output. It has no
    # karch/modules_install attributes, but is still kernel compilation.
    return (attrs.get('pname') in ('linux', 'linux-image')
            or (bool(attrs.get('karch')) and 'modules_install' in (attrs.get('installTargets') or [])))


def derivation_graph(data):
    """Normalize Nix's derivation JSON, including its versioned wire format."""
    if not isinstance(data, dict):
        raise Failure('Nix returned invalid derivation metadata.')
    if 'derivations' in data:
        data = data['derivations']
    if not isinstance(data, dict):
        raise Failure('Nix returned invalid derivation metadata.')
    graph = {}
    for key, value in data.items():
        path = key if key.startswith('/nix/store/') else '/nix/store/' + key
        if not STORE.fullmatch(path) or not path.endswith('.drv') or not isinstance(value, dict):
            raise Failure('Nix returned invalid derivation metadata.')
        info = dict(value)
        wire_inputs = info.get('inputs', {})
        if not isinstance(wire_inputs, dict):
            raise Failure('Nix returned invalid derivation metadata.')
        inputs = info.get('inputDrvs', wire_inputs.get('drvs'))
        if (not isinstance(inputs, dict) or not isinstance(info.get('env'), dict) or not isinstance(info.get('outputs'), dict)
                or not isinstance(info.get('structuredAttrs', {}), dict)):
            raise Failure('Nix returned invalid derivation metadata.')
        info['inputDrvs'] = {key if key.startswith('/nix/store/') else '/nix/store/' + key: value
                             for key, value in inputs.items()}
        if any(not STORE.fullmatch(key) or not key.endswith('.drv') for key in info['inputDrvs']):
            raise Failure('Nix returned invalid derivation metadata.')
        if any(not isinstance(value, dict) or ('path' in value and not isinstance(value['path'], str))
               for value in info['outputs'].values()):
            raise Failure('Nix returned invalid derivation metadata.')
        info['outputs'] = {key: dict(value, path=value['path'] if value['path'].startswith('/nix/store/')
                                    else '/nix/store/' + value['path']) if value.get('path') else value
                           for key, value in info['outputs'].items()}
        graph[path] = info
    return graph


def show(run, derivations):
    """`nix derivation show` for the given .drv paths, keyed by full path."""
    if not derivations:
        return {}
    data = parse(run('nix', 'derivation', 'show', *derivations, timeout=600, sensitive=True))
    graph = derivation_graph(data)
    if set(derivations) - graph.keys():
        raise Failure('Nix omitted requested derivation metadata.')
    return graph


def compiles(run, derivations, *, root=None, expected=(), vendor=(), kernel_only=False):
    """Names of real builds that are not expected local builds.

    Starting from `root` (when given), descend through trivial and
    configuration derivations only: anything needed solely to build an
    expected derivation (Cybex OS's own packages, kernel modules) or a
    compiled one is covered by it. Without a root every unexpected compile
    counts.

    `vendor` names the expected builds that are unfree vendor downloads. They
    build here because NixOS never caches them, but their inputs are ordinary
    Nixpkgs packages that NixOS does build, so the walk continues into them.
    A vendor wrapper without a source of its own (a Wayland launcher, Steam's
    FHS environment) carries its vendor download: the first packages compiled
    below it are that download, and their inputs are checked in turn.

    `kernel_only` retains personal package build choices on local previews,
    while still refusing a kernel compile before any build starts.
    """
    pending = set(derivations)
    graph = show(run, sorted(pending))
    if root is not None:
        # A Software queue shares one plan across several package roots.
        # Retain all reachable inputs, even below expected or compiled nodes,
        # so kernel builds cannot hide there or be blamed on unrelated apps.
        reachable, frontier = set(), [root]
        while frontier:
            current = frontier.pop()
            if current in reachable or current not in graph:
                continue
            reachable.add(current)
            frontier.extend(graph[current]['inputDrvs'])
        graph = {path: graph[path] for path in reachable}
    expected = set(expected)
    # Inspect the relevant pending plan before pruning expected ancestors. A
    # kernel needed by e.g. an expected external module still must be cached.
    kernels = {d for d, info in graph.items() if kernel_build(info)}
    expected -= kernels
    found = [name(d) for d in kernels]
    if kernel_only:
        return sorted(set(found))
    if root is None:
        return sorted(set(found) | {name(d) for d, info in graph.items() if d not in expected and kind(info) == 'compile'})
    vendor = set(vendor) & expected
    # (derivation, below a vendor wrapper): a package reached both ways is
    # checked both ways.
    seen, frontier = set(), [(root, False)]
    while frontier:
        current, wrapped = frontier.pop()
        if (current, wrapped) in seen or current not in graph:
            continue
        seen.add((current, wrapped))
        sort = kind(graph[current])
        if current in vendor:
            wrapped = sort in ('trivial', 'configuration')
        elif current in expected:
            continue
        elif sort == 'compile' and wrapped:
            wrapped = False
        elif sort == 'compile':
            found.append(name(current))
            continue
        elif sort not in ('trivial', 'configuration'):
            continue
        for child in graph[current].get('inputDrvs') or {}:
            child = child if child.startswith('/nix/store/') else '/nix/store/' + child
            if child in pending:
                frontier.append((child, wrapped))
    return sorted(set(found))
