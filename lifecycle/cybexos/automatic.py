"""Background preparation and post-restart confirmation of system updates.

Both run as root from fixed system units the signed-in desktop may start.
They take no input: each reads the machine policy and the updater's own state,
then submits an ordinary supervised request or does nothing. Preparation
downloads and builds; installing a prepared update still needs authorization.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

from .common import Failure, atomic, read
from . import prebuilt
from .trust import version

POLICY = 'update-automatic.json'
LAST_RUN = 'update-automatic-run.json'
DEFAULTS = {'prepare': True, 'confirm': True}
# A failed automatic preparation of the same target is retried at most daily.
RETRY_SECONDS = 24 * 3600
# A prepared update is prepared again for newer NixOS packages alone only
# once it is this old: nixos-unstable moves every day or two, and a review
# that is rebuilt for each snapshot never settles. A new Cybex OS release
# replaces it straight away.
OUTDATED_SECONDS = 3 * 24 * 3600
# The requests background preparation submitted, newest last; their previews
# may take in every available source, the person's own keep their sources.
REMEMBERED = 8
SOURCES = {'upstream': ('upstream',), 'cybexos': ('cybexos',), 'both': ('upstream', 'cybexos')}


def policy(state=Path('/var/lib/cybexos')):
    """Defaults apply when no choice was made; an unreadable choice disables."""
    try:
        value = read(Path(state) / POLICY, {})
    except Failure:
        value = None
    if not isinstance(value, dict) or any(not isinstance(value.get(key, True), bool) for key in DEFAULTS):
        return {key: False for key in DEFAULTS}
    return {key: value.get(key, default) for key, default in DEFAULTS.items()}


def choose(state, name, enabled):
    if name not in DEFAULTS or not isinstance(enabled, bool):
        raise Failure('Invalid automatic update choice')
    value = policy(state) | {name: enabled}
    atomic(Path(state) / POLICY, value, 0o644)
    return value


def metered(run=subprocess.run):
    """NetworkManager's metered guess; unknown or unavailable is not metered."""
    try:
        result = run(['busctl', 'get-property', 'org.freedesktop.NetworkManager',
                      '/org/freedesktop/NetworkManager', 'org.freedesktop.NetworkManager', 'Metered'],
                     capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return False
    match = re.fullmatch(r'u ([0-9]+)\s*', result.stdout or '') if result.returncode == 0 else None
    # NM_METERED_YES and NM_METERED_GUESS_YES.
    return bool(match) and int(match[1]) in (1, 3)


def target(config, discovery):
    sources = {name: discovery[name].get('available') if discovery[name].get('state') == 'available' else None
               for name in ('upstream', 'cybexos')}
    scope = 'both' if all(sources.values()) else 'upstream' if sources['upstream'] else 'cybexos' if sources['cybexos'] else ''
    devices = (discovery.get('firmware') or {}).get('devices', [])
    if not scope and devices:
        scope = 'firmware'
    identity = hashlib.sha256(json.dumps({'config': config, **sources, 'firmware': devices}, sort_keys=True).encode()).hexdigest()
    return scope, identity


def later(available, prepared):
    try:
        return version(available) > version(prepared)
    except Failure:
        return False


def refresh(current, discovery, automatic, now):
    """The discovery a prepared update is prepared again for, or None.

    A newer Cybex OS release replaces the prepared update; newer NixOS
    packages alone do once it is OUTDATED_SECONDS old. A preview the person
    prepared keeps its sources (they may have left one out); one background
    preparation made takes in every available source.
    """
    wanted = (('upstream', 'cybexos') if current.get('requestId') in automatic
              else SOURCES.get(current.get('scope'), ()))
    vendor, upstream = discovery.get('cybexos') or {}, discovery.get('upstream') or {}
    release = ('cybexos' in wanted and vendor.get('state') == 'available'
               and later(vendor.get('available'), current.get('availableVersion')))
    prepared_at = current.get('finishedAt') or current.get('updatedAt') or now
    packages = ('upstream' in wanted and upstream.get('state') == 'available'
                and upstream.get('available') != ((current.get('inputs') or {}).get('nixpkgs') or {}).get('rev')
                and now - prepared_at >= OUTDATED_SECONDS)
    if not (release or packages):
        return None
    return discovery | {name: (discovery.get(name) or {}) | {'state': 'left-out'}
                        for name in ('upstream', 'cybexos') if name not in wanted}


def prepare(engine, enqueue, status, config_digest, discover=None, is_metered=metered, now=time.time):
    """Submit one preparation per available target; never repeat a reviewed one.

    A prepared update is prepared again when a newer release (or, after a
    while, newer packages) would supersede it, so updates arrive together
    instead of one restart each. It stays installable until the new one is.
    """
    state = engine.state
    if not policy(state)['prepare']:
        return {'skipped': 'disabled'}
    current = status()
    if (current.get('firmware') or {}).get('needsReboot'):
        return {'skipped': 'restart'}
    last = read(state / LAST_RUN, {}) or {}
    own_failure = (current.get('state') in ('failed', 'interrupted') and last.get('requestId')
                   and current.get('requestId') == last.get('requestId'))
    held = prebuilt.held(current) and current.get('changeKind') == 'update'
    prepared = (current.get('state') == 'ready' and current.get('changeKind') == 'update'
                and current.get('scope') in SOURCES)
    # Anything else in progress, awaiting review/restart or needing attention
    # belongs to the person. Their own failures are dismissed in the app.
    if current.get('state', 'idle') not in ('idle', 'done') and not own_failure and not held and not prepared:
        return {'skipped': current.get('state')}
    if (current.get('request') or {}).get('state') in ('queued', 'running', 'unknown'):
        return {'skipped': 'request'}
    if is_metered():
        return {'skipped': 'metered'}
    discovery = (discover or engine.check)()
    configuration = config_digest(engine.working)
    if prepared:
        discovery = refresh(current, discovery, submitted(last), now())
        if discovery is None:
            return {'skipped': 'ready'}
    scope, identity = target(configuration, discovery)
    if not scope:
        return {'skipped': 'current'}
    if prepared:
        # Preparing again failed and left the prepared update in place:
        # the same newer set is tried again at most daily.
        if last.get('target') == identity and now() - last.get('at', 0) < RETRY_SECONDS:
            return {'skipped': 'prepared'}
        return submit(state, enqueue, last, scope, identity, now)
    # An unavailable package is safe to check again without dismissing the
    # result. Retry changed sources/configuration promptly, the same candidate
    # at most daily, including a hold first encountered by a manual request.
    if held and prebuilt.hold_target(current, discovery) != 'changed':
        changed_config = current.get('baseline') and current['baseline'] != configuration
        if not changed_config and now() - current.get('finishedAt', now()) < RETRY_SECONDS:
            return {'skipped': 'waiting'}
    if last.get('target') == identity and not ((own_failure or held) and now() - last.get('at', 0) >= RETRY_SECONDS):
        return {'skipped': 'prepared'}
    return submit(state, enqueue, last, scope, identity, now)


def submitted(last):
    """Requests background preparation submitted; a record from before the list names one."""
    values = last.get('requests') if isinstance(last.get('requests'), list) else [last.get('requestId')]
    return [value for value in values if isinstance(value, str) and value]


def submit(state, enqueue, last, scope, identity, now):
    accepted = enqueue(state, 'stage', [scope])
    requests = submitted(last)[-(REMEMBERED - 1):]
    atomic(state / LAST_RUN, {'target': identity, 'scope': scope, 'requestId': accepted['requestId'],
                              'requests': requests + [accepted['requestId']], 'at': now()}, 0o644)
    return accepted | {'scope': scope}


def confirm(engine, enqueue, status):
    """Confirm a trial boot from the signed-in desktop; health still decides."""
    if not policy(engine.state)['confirm']:
        return {'skipped': 'disabled'}
    current = status()
    if current.get('state') != 'awaiting-login':
        return {'skipped': current.get('state')}
    if (current.get('request') or {}).get('state') in ('queued', 'running', 'unknown'):
        return {'skipped': 'request'}
    return enqueue(engine.state, 'confirm', [])
