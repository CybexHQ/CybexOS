"""The Cybex OS release channel a machine follows: stable or beta.

The machine's NixOS configuration declares a channel
(`cybexos.updates.channel`, in /etc/cybexos/update.json). An administrator may
choose the other one at runtime; that choice lives beside the other update
policies in /var/lib/cybexos, so switching needs no rebuild and a generation
rollback does not silently switch back. Choosing the declared channel removes
the override again. Only Cybex OS releases follow the channel: NixOS package
updates follow the Nixpkgs revisions verified for the installed release
(verified.py).
"""
from pathlib import Path

from .common import Failure, atomic, read

CHANNELS = ('stable', 'beta')
POLICY = 'update-channel.json'
DECLARED = Path('/etc/cybexos/update.json')


def declared(policy=DECLARED):
    value = read(Path(policy), {})
    channel = value.get('channel') if isinstance(value, dict) else None
    if channel not in CHANNELS:
        raise Failure('Unknown release channel')
    return channel


def selected(state, policy=DECLARED):
    """The channel in effect, and whether it overrides the declared one.

    An unreadable or invalid override is ignored: the machine follows the
    channel its configuration declares.
    """
    default = declared(policy)
    try:
        value = read(Path(state) / POLICY, {})
    except Failure:
        value = None
    chosen = value.get('channel') if isinstance(value, dict) else None
    channel = chosen if chosen in CHANNELS else default
    return {'selected': channel, 'declared': default, 'override': channel != default}


def choose(state, channel, policy=DECLARED):
    if channel not in CHANNELS:
        raise Failure('Choose the stable or beta channel')
    path = Path(state) / POLICY
    if channel == declared(policy):
        path.unlink(missing_ok=True)
    else:
        atomic(path, {'schema': 1, 'channel': channel}, 0o644)
    return selected(state, policy)
