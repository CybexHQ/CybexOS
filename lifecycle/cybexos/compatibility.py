"""Why a candidate Nixpkgs no longer evaluates, in terms safe to publish.

When Nixpkgs removes or renames something a configuration uses (Brave on
2026-11-03), the candidate system stops evaluating. The engine confirms the
cause by evaluating the same candidate with the installed Nixpkgs; these
helpers read Nix's error and name whose files used what disappeared:

  cybexos   a Cybex OS module: the update waits for a Cybex OS release.
  personal  a module in /etc/nixos or a personal input: the person fixes it.
  unknown   no module was named: the update waits and is retried.

Status files are world-readable. Only Nixpkgs' own message about a Cybex OS
module is published; errors from personal files stay in the private log.
"""
import json
import re

ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
# Fetch failures during evaluation say nothing about compatibility.
NETWORK = re.compile(r'unable to download|could(?: not|n.t) resolve|HTTP error|timed out|'
                     r'connection (?:refused|reset)|network is unreachable', re.I)


def evaluation_error(output):
    """(message, trace) of Nix's evaluation error in internal-json output, or None."""
    found = None
    for line in (output or '').splitlines():
        if not line.startswith('@nix '):
            continue
        try:
            event = json.loads(line[5:])
        except ValueError:
            continue
        if isinstance(event, dict) and event.get('action') == 'msg' and event.get('level') == 0:
            found = event
    if found is None:
        return None
    trace = ANSI.sub('', str(found.get('msg') or ''))
    message = ANSI.sub('', str(found.get('raw_msg') or '')).strip()
    if not re.search(r'while (?:evaluating|calling)', trace) or NETWORK.search(trace):
        return None
    return message, trace


def roots(archive):
    """Store path -> owner, from `nix flake archive --json` of the machine flake."""
    owners = {}
    def visit(node, owner, label):
        if isinstance(node, dict) and isinstance(node.get('path'), str):
            owners[node['path']] = (owner, label)
            for name, child in (node.get('inputs') or {}).items():
                visit(child, owner, name)
    if isinstance(archive, dict) and isinstance(archive.get('path'), str):
        owners[archive['path']] = ('personal', '')
        for name, child in (archive.get('inputs') or {}).items():
            visit(child, {'cybexos': 'cybexos', 'nixpkgs': 'nixpkgs'}.get(name, 'personal'), name)
    return owners


def origin(trace, archive):
    """The innermost module that used what failed, outside Nixpkgs itself."""
    owners = roots(archive)
    for path in reversed(re.findall(r"definitions from `(/nix/store/[^']+)'", trace)):
        for root, (owner, label) in owners.items():
            if not path.startswith(root + '/'):
                continue
            if owner == 'nixpkgs':
                break
            relative = path[len(root) + 1:]
            if owner == 'personal' and label:
                relative = f'{label}: {relative}'
            return {'origin': owner, 'file': relative[:200]}
    return {'origin': 'unknown', 'file': ''}


def public(message):
    """Nixpkgs' message, as one short line."""
    text = ' '.join(message.split())
    return text if len(text) <= 300 else text[:297] + '...'


def describe(details, version):
    """The status error for a diagnosis."""
    if details['origin'] == 'cybexos':
        text = f'The new Nixpkgs no longer works with Cybex OS {version}'
        text += f": {details['message']}" if details.get('message') else ''
        text += f" ({details['file']})." if details.get('file') else '.'
        return text + (' Nothing was changed. Cybex OS prepares the update again once a release'
                       ' supports this Nixpkgs.')
    if details['origin'] == 'personal':
        return (f"The new Nixpkgs no longer works with your configuration ({details['file']}): it uses"
                ' something Nixpkgs removed or changed. Nothing was changed. Update that file, then'
                ' prepare again; cybex update log shows the details.')
    return ('The new Nixpkgs no longer evaluates with this system. Nothing was changed. Cybex OS'
            ' tries again when a newer Cybex OS release or Nixpkgs arrives; cybex update log'
            ' shows the details.')
