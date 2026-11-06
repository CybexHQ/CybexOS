"""Read-only, conservative model support metadata; never a qualification test.

The packaged JSON is also consumed by Nix. ``catalogue`` accepts a decoded
schema-1 dictionary or a JSON path for fixture callers. DMI strings are exact,
case-sensitive values after sysfs whitespace trimming, never substring matches.
"""
import copy
import json
import os
from pathlib import Path
import re

CATALOGUE = Path(__file__).with_name('hardware-profiles.json')
_DMI_FIELDS = {'sys_vendor', 'product_name', 'product_version', 'product_sku', 'board_name'}


def _text(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return ''


def _load(catalogue):
    if catalogue is None:
        catalogue = CATALOGUE
    if isinstance(catalogue, (str, Path)):
        try:
            catalogue = json.loads(Path(catalogue).read_text())
        except (OSError, ValueError, UnicodeError):
            return {}
    return catalogue if isinstance(catalogue, dict) and catalogue.get('schema') == 1 else {}


def _matches(rule, dmi):
    if not isinstance(rule, dict) or set(rule) - {'dmi', 'machineTypes'}:
        return False
    fields = rule.get('dmi')
    if not isinstance(fields, dict) or set(fields) - _DMI_FIELDS or 'sys_vendor' not in fields:
        return False
    # Machine types alone, board IDs alone and empty lists cannot name a model.
    if 'product_name' not in fields and not ('product_version' in fields and 'machineTypes' in rule):
        return False
    if not all(isinstance(values, list) and values and all(isinstance(v, str) and v for v in values)
               and dmi.get(key, '') in values for key, values in fields.items()):
        return False
    if 'machineTypes' in rule:
        types = rule['machineTypes']
        product = dmi['product_name']
        if not (isinstance(types, list) and types
                and all(isinstance(t, str) and re.fullmatch(r'[A-Z0-9]{4}', t) for t in types)
                and re.fullmatch(r'[A-Z0-9]{10}', product) and product[:4] in types):
            return False
    return True


def _version(value):
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r'(\d+)\.(\d+)(?:\.(\d+))?(?:[-+](?!rc\d)[0-9A-Za-z][0-9A-Za-z.+_-]*)?', value)
    return tuple(int(part or 0) for part in match.groups()) if match else None


def support_for(sysroot=Path('/sys'), *, kernel=None, catalogue=None):
    """Return JSON-safe support information without writes or privileged probes.

    An unknown or ambiguous model receives generic support, without a profile
    ID. An explicitly out-of-scope platform or too-old kernel receives an
    unsupported assessment. Neither is a verdict about individual components.
    The architecture is that of this process; injected sysfs is fixture data,
    not an emulator for a different CPU architecture.
    """
    sysroot = Path(sysroot)
    dmi = {key: _text(sysroot / 'class/dmi/id' / key) for key in _DMI_FIELDS}
    kernel = os.uname().release if kernel is None else kernel
    result = {'profileId': None, 'profileName': 'Generic Intel/AMD UEFI PC', 'status': 'generic',
              'summary': 'Generic Linux drivers; this exact model has no approved Cybex OS profile.',
              'limitations': ['Physical installation, devices, sleep and staged updates have not been qualified.'],
              'sources': [], 'kernel': kernel if isinstance(kernel, str) else '',
              'testStatus': {'physical': 'not-run'}, 'configurationSupported': False}
    alias = _text(sysroot / 'devices/system/cpu/modalias')
    vendor = re.search(r'(?:ven|vendor:)([0-9a-fA-F]{4})', alias)
    reason = None
    if os.uname().machine != 'x86_64':
        reason = 'Only Intel/AMD x86_64 UEFI PCs are supported.'
    elif 'apple' in dmi['sys_vendor'].lower() or 'apple' in _text(sysroot / 'class/dmi/id/board_vendor').lower():
        reason = 'Apple hardware is outside the supported PC scope.'
    elif vendor and vendor[1].lower() not in ('0000', '0002'):
        reason = 'Only Intel and AMD processors are supported.'
    elif not (sysroot / 'firmware/efi').is_dir():
        reason = 'UEFI firmware is required; legacy BIOS installation is unsupported.'
    if reason:
        return {**result, 'profileName': 'Unsupported platform', 'status': 'unsupported', 'summary': reason}

    data = _load(catalogue)
    profiles = data.get('profiles', [])
    if not isinstance(profiles, list):
        profiles = []
    matches = [p for p in profiles if isinstance(p, dict) and p.get('approved') is True
               and isinstance(p.get('id'), str) and re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', p['id'])
               and isinstance(p.get('name'), str) and isinstance(p.get('matches'), list)
               and any(_matches(rule, dmi) for rule in p['matches'])]
    if len(matches) != 1:
        if len(matches) > 1:
            result['limitations'].append('The catalogue has ambiguous model matches; no profile was selected.')
        elif not data:
            result['limitations'].append('Hardware profile metadata is unavailable or invalid.')
        return result
    profile = matches[0]
    limits = profile.get('limitations', [])
    sources = profile.get('sources', [])
    result.update(profileName=profile['name'],
                  limitations=copy.deepcopy(limits) if isinstance(limits, list) and all(isinstance(v, str) for v in limits) else [],
                  sources=copy.deepcopy(sources) if isinstance(sources, list) and all(isinstance(v, dict) for v in sources) else [])
    bounds = profile.get('kernel', {})
    bounds = bounds if isinstance(bounds, dict) else {}
    version, minimum, maximum = _version(kernel), _version(bounds.get('minimum')), _version(bounds.get('maximumExclusive'))
    if (version is None or minimum is None
            or (bounds.get('maximumExclusive') is not None and maximum is None)
            or version < minimum or (maximum and version >= maximum)):
        result.update(status='unsupported', matchedProfileId=profile['id'],
                      summary=f'{profile["name"]}: the running kernel is outside the reviewed profile range.')
        result['limitations'].append('Use the stock kernel supported by the selected Cybex OS release; no custom kernel is supplied.')
        return result
    # Catalogue inclusion and configuration checks never establish physical
    # qualification. Deliberate qualification support needs a reviewed record
    # and a future schema change, not an unchecked status string in JSON.
    result.update(profileId=profile['id'], status='experimental', configurationSupported=True,
                  summary=f'{profile["name"]}: experimental configuration; physical qualification is still required.')
    result['testStatus'] = {'source': 'reviewed', 'configuration': 'fixture-tested', 'physical': 'not-run'}
    return result
