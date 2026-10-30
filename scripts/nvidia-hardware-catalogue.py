#!/usr/bin/env python3
"""Extract supported PCI identities from the exact packaged NVIDIA drivers."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tarfile


def chips(source):
    # NVIDIA's makeself archive is not a tar file until after its shell stub.
    # Read metadata without executing vendor code or extracting executable files.
    with Path(source).open('rb', buffering=0) as stream:
        header = stream.read(65536)
        skip = re.search(rb'^skip=(\d+)$', header, re.M)
        if skip is None or not 1 <= int(skip[1]) <= 10000:
            raise ValueError('Unrecognized NVIDIA archive header')
        stream.seek(0)
        for _ in range(int(skip[1]) - 1):
            stream.readline()
        position = stream.tell()
        magic = stream.read(4)
        stream.seek(position)
        process = None
        try:
            payload = stream
            if magic == b'\x28\xb5\x2f\xfd':
                process = subprocess.Popen(['zstd', '-dq'], stdin=stream, stdout=subprocess.PIPE)
                payload = process.stdout
            with tarfile.open(fileobj=payload, mode='r|*') as archive:
                for member in archive:
                    if member.name.endswith('/supported-gpus.json'):
                        if not member.isfile() or member.size > 4 * 1024 * 1024:
                            raise ValueError('Invalid NVIDIA device metadata')
                        value = json.load(archive.extractfile(member))
                        if not isinstance(value.get('chips'), list) or not value['chips']:
                            raise ValueError('Empty NVIDIA device metadata')
                        return value['chips']
        finally:
            if process:
                process.stdout.close()
                if process.poll() is None:
                    process.terminate()
                process.wait()
    raise ValueError('NVIDIA archive has no supported device metadata')


def identity(chip):
    result = {}
    for source, target in [('devid', 'device'), ('subvendorid', 'subvendor'), ('subdevid', 'subdevice')]:
        if source in chip:
            value = chip[source]
            if not isinstance(value, str) or not re.fullmatch(r'0x[0-9a-fA-F]{4}', value):
                raise ValueError('Invalid NVIDIA PCI identity')
            result[target] = value[2:].lower()
    if 'device' not in result:
        raise ValueError('NVIDIA device has no PCI identity')
    return result


def catalogue(open_chips, closed_chips, open_version, closed_version):
    def supported(values, use_open):
        result = []
        for chip in values:
            # Lists also contain historical GPUs which this driver cannot load.
            if chip.get('legacybranch'):
                continue
            features = chip.get('features', [])
            if use_open and 'kernelopen' not in features:
                continue
            if not use_open and 'kernelopen' in features and 'gsp_proprietary_supported' not in features:
                continue
            item = identity(chip)
            if item not in result:
                result.append(item)
        if not result:
            raise ValueError('NVIDIA branch has no supported PCI identities')
        return result
    return {'schema': 1, 'nvidia': {
        'open': {'version': open_version, 'devices': supported(open_chips, True)},
        'closed': {'version': closed_version, 'devices': supported(closed_chips, False)},
    }}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('open-source', 'closed-source', 'open-version', 'closed-version'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = catalogue(chips(args.open_source), chips(args.closed_source), args.open_version, args.closed_version)
    args.output.write_text(json.dumps(result, sort_keys=True, separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
