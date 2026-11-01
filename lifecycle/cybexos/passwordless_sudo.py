"""A narrow, authenticated switch for the primary user's passwordless sudo rule."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from .common import Failure, atomic, locked, read, syncdir

STATE = Path('/var/lib/cybexos/passwordless-sudo')
CONFIG = Path('/etc/cybexos/passwordless-sudo.json')
# /etc/sudoers includes every file in STATE whose name has no dot, so the lock
# and atomic()'s temporary files beside the rule never become policy.
RULE = 'rule'
USER = re.compile(r'[a-z_][a-z0-9_-]{0,31}')


def status(state=STATE, config=CONFIG):
    settings = read(config, {})
    return {'available': settings.get('available') is True,
            'passwordRequired': settings.get('passwordRequired') is not False,
            'enabled': (state / RULE).is_file(), 'user': settings.get('user', '')}


def change(action, state=STATE, config=CONFIG):
    if action not in ('enable', 'disable'):
        raise Failure('Choose enable or disable')
    if os.geteuid() != 0:
        raise Failure('Administrator authentication is required')
    settings = read(config, {})
    user, visudo = settings.get('user'), settings.get('visudo')
    # Turning it off always works, even after a personal module removed the
    # account from wheel; turning it on needs the declared contract.
    if action == 'enable' and (settings.get('available') is not True or not isinstance(user, str)
                               or not USER.fullmatch(user) or not isinstance(visudo, str)
                               or not visudo.startswith('/nix/store/')):
        raise Failure('Sudo without password is unavailable in this system configuration')
    rule = state / RULE
    with locked(state / 'operation.lock'):
        if action == 'disable':
            rule.unlink(missing_ok=True)
            syncdir(state)
            return status(state, config)
        # sudo stops working for everyone if an included file does not parse,
        # so the rule is checked under a skipped name before it takes effect.
        candidate = state / '.rule.new'
        try:
            atomic(candidate, b'# Managed by Settings > Security > Sudo without password.\n'
                   + f'{user} ALL=(ALL:ALL) NOPASSWD: SETENV: ALL\n'.encode(), 0o440)
            subprocess.run([visudo, '-c', '-q', '-f', str(candidate)], capture_output=True, timeout=30, check=True)
            os.replace(candidate, rule)
            syncdir(state)
        except (OSError, subprocess.SubprocessError) as error:
            raise Failure('Could not turn on sudo without password. Your password is still required.') from error
        finally:
            candidate.unlink(missing_ok=True)
    return status(state, config)


def main():
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in ('status', 'enable', 'disable'):
            raise Failure('Choose status, enable or disable')
        value = status() if sys.argv[1] == 'status' else change(sys.argv[1])
        print(json.dumps({'success': True, **value}))
    except (Failure, OSError, ValueError) as error:
        message = str(error) if isinstance(error, Failure) else 'Could not read the sudo setting. Retry, then check /var/lib/cybexos/passwordless-sudo.'
        print(json.dumps({'success': False, 'error': message}))
        return 1
    return 0
