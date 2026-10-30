"""A one-path binary cache for nix/tests/pointer.nix, written without Nix.

usage: pointer-cache.py STORE_PATH OUT

Serialises STORE_PATH (which must have no references) as a NAR under
OUT/nar and writes its narinfo, unsigned, base64-encoded with its file name in
OUT/narinfo.b64. Encoded, the store path's hash appears nowhere in OUT, so
Nix's reference scan does not make the cache depend on the path: the test
machine gets the cache without the theme, and must download the theme from it
exactly as Settings does from cache.nixos.org. The test decodes the narinfo
into place before it starts.
"""
import base64
import hashlib
import json
import os
import struct
import sys

NIX32 = '0123456789abcdfghijklmnpqrsvwxyz'


def nix32(digest):
    """Nix's base-32 encoding of a hash, as in narinfo files."""
    out = []
    for n in range((len(digest) * 8 - 1) // 5, -1, -1):
        bit = n * 5
        index, shift = divmod(bit, 8)
        value = digest[index] >> shift
        if index + 1 < len(digest):
            value |= digest[index + 1] << (8 - shift)
        out.append(NIX32[value & 0x1F])
    return ''.join(out)


def string(data):
    data = data.encode() if isinstance(data, str) else data
    return struct.pack('<Q', len(data)) + data + b'\0' * (-len(data) % 8)


def serialise(path, write):
    write(string('('))
    if os.path.islink(path):
        write(string('type') + string('symlink') + string('target') + string(os.readlink(path)))
    elif os.path.isdir(path):
        write(string('type') + string('directory'))
        for name in sorted(os.listdir(path), key=os.fsencode):
            write(string('entry') + string('(') + string('name') + string(name) + string('node'))
            serialise(os.path.join(path, name), write)
            write(string(')'))
    else:
        write(string('type') + string('regular'))
        if os.access(path, os.X_OK):
            write(string('executable') + string(''))
        with open(path, 'rb') as handle:
            write(string('contents') + string(handle.read()))
    write(string(')'))


def main(store_path, out):
    os.makedirs(os.path.join(out, 'nar'))
    chunks = [string('nix-archive-1')]
    serialise(store_path, chunks.append)
    nar = b''.join(chunks)
    digest = nix32(hashlib.sha256(nar).digest())
    name = f'nar/{digest}.nar'
    with open(os.path.join(out, name), 'wb') as handle:
        handle.write(nar)
    narinfo = (f'StorePath: {store_path}\nURL: {name}\nCompression: none\n'
               f'FileHash: sha256:{digest}\nFileSize: {len(nar)}\n'
               f'NarHash: sha256:{digest}\nNarSize: {len(nar)}\nReferences: \n')
    entry = {'name': os.path.basename(store_path).split('-', 1)[0] + '.narinfo', 'text': narinfo}
    with open(os.path.join(out, 'narinfo.b64'), 'w') as handle:
        handle.write(base64.b64encode(json.dumps(entry).encode()).decode() + '\n')
    with open(os.path.join(out, 'nix-cache-info'), 'w') as handle:
        handle.write('StoreDir: /nix/store\nWantMassQuery: 0\nPriority: 10\n')


if __name__ == '__main__':
    main(*sys.argv[1:])
