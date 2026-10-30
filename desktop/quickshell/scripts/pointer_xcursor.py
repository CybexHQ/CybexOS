"""XCursor themes for Settings -> Appearance -> Pointer: lookup and previews.

A theme is a directory with a `cursors/` folder of XCursor files, found on
XCURSOR_PATH like every toolkit finds it. Previews are PNGs of six shapes a
person meets every day, drawn from the theme's own files: the arrow, the link
hand, the text beam, the busy shape (every frame side by side, for the
gallery's animation), a resize arrow and "not allowed". Names differ between
themes, so each shape tries the freedesktop name first and then the older X11
ones.

The vendored previews for the catalogue (assets/pointers/previews) and the
previews of a person's own themes come from the same code, so both look
alike. Standard library only: it runs at build time and in the shell.
"""
import json
import os
import re
import struct
import zlib

# Freedesktop names first, then the X11 core and theme-specific aliases.
SHAPES = {
    'arrow': ('default', 'left_ptr', 'arrow', 'top_left_arrow'),
    'hand': ('pointer', 'hand2', 'hand1', 'pointing_hand', 'hand'),
    'text': ('text', 'xterm', 'ibeam'),
    'busy': ('wait', 'watch', 'progress', 'left_ptr_watch'),
    'resize': ('ew-resize', 'col-resize', 'sb_h_double_arrow', 'h_double_arrow', 'size_hor', 'e-resize'),
    'forbidden': ('not-allowed', 'crossed_circle', 'no-drop', 'circle', 'forbidden'),
}
# Large enough for a 2x display: the gallery draws a shape at about 26
# logical pixels.
PREVIEW_SIZE = 48
# The busy strip samples at most this many frames.
MAX_FRAMES = 12
# An animation longer than this is sampled from its first frames.
MAX_STORED_FRAMES = 240
MAX_DIMENSION = 512
IMAGE_TYPE = 0xFFFD0002
# Theme directory names reach Hyprland, gsettings and an environment file the
# session reads, so only names without spaces, quotes or shell syntax qualify.
NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$')
INHERIT_DEPTH = 4


class CursorError(Exception):
    pass


def valid_name(name):
    return isinstance(name, str) and bool(NAME.match(name))


def search_path(environ=None):
    """The directories toolkits search for cursor themes, in their order."""
    environ = os.environ if environ is None else environ
    home = environ.get('HOME') or os.path.expanduser('~')
    data = environ.get('XDG_DATA_HOME') or os.path.join(home, '.local/share')
    value = environ.get('XCURSOR_PATH')
    entries = value.split(':') if value else [
        '~/.icons', os.path.join(data, 'icons'), '/run/current-system/sw/share/icons', '/usr/share/icons']
    seen, out = set(), []
    # The user's own icons folder always counts: downloads are linked there.
    for entry in entries + [os.path.join(data, 'icons')]:
        if not entry:
            continue
        path = os.path.normpath(home + entry[1:] if entry.startswith('~') else entry)
        if path not in seen:
            seen.add(path)
            out.append(path)
    return out


def theme_dir(name, dirs):
    """The first directory named `name` on `dirs`; None when there is none."""
    if not valid_name(name):
        return None
    for base in dirs:
        candidate = os.path.join(base, name)
        if os.path.isdir(candidate):
            return candidate
    return None


def has_cursors(directory):
    cursors = os.path.join(directory, 'cursors')
    return os.path.isdir(cursors) and any(
        os.path.exists(os.path.join(cursors, name)) for name in SHAPES['arrow'])


def index_value(directory, key):
    """`key` from the [Icon Theme] section of directory/index.theme, or ''."""
    try:
        with open(os.path.join(directory, 'index.theme'), encoding='utf-8', errors='replace') as handle:
            text = handle.read(65536)
    except OSError:
        return ''
    section = ''
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1].strip()
        elif section == 'Icon Theme' and '=' in line:
            name, value = line.split('=', 1)
            if name.strip() == key:
                return value.strip()
    return ''


def shape_file(name, dirs, shape, depth=0):
    """The file drawing `shape` in theme `name`, following Inherits."""
    directory = theme_dir(name, dirs)
    if directory is None:
        return None
    for candidate in SHAPES[shape]:
        path = os.path.join(directory, 'cursors', candidate)
        if os.path.isfile(path):
            return path
    if depth >= INHERIT_DEPTH:
        return None
    for parent in index_value(directory, 'Inherits').split(','):
        parent = parent.strip()
        if parent and parent != name:
            found = shape_file(parent, dirs, shape, depth + 1)
            if found:
                return found
    return None


def read_frames(path, target):
    """The frames of an XCursor file at the nominal size nearest `target`
    (preferring larger), and every nominal size it has. A frame is a dict of
    width, height, xhot, yhot, delay and premultiplied BGRA pixels. Only the
    table of contents and the chosen frames are read: an animated theme's
    file holds every size and can run to megabytes."""
    with open(path, 'rb') as handle:
        head = handle.read(16)
        if len(head) < 16 or head[:4] != b'Xcur':
            raise CursorError(f'{path}: not an XCursor file')
        header, _version, count = struct.unpack_from('<III', head, 4)
        if header < 16 or count > 4096:
            raise CursorError(f'{path}: damaged table of contents')
        handle.seek(header)
        table = handle.read(count * 12)
        if len(table) < count * 12:
            raise CursorError(f'{path}: damaged table of contents')
        entries = [struct.unpack_from('<III', table, index * 12) for index in range(count)]
        images = [(subtype, position) for kind, subtype, position in entries if kind == IMAGE_TYPE]
        if not images:
            raise CursorError(f'{path}: no images')
        available = sorted({subtype for subtype, _position in images})
        larger = [size for size in available if size >= target]
        chosen = larger[0] if larger else available[-1]
        frames = []
        for subtype, position in images:
            if subtype != chosen:
                continue
            handle.seek(position)
            chunk = handle.read(36)
            if len(chunk) < 36:
                raise CursorError(f'{path}: damaged image header')
            size, kind, _nominal, _v, width, height, xhot, yhot, delay = struct.unpack('<9I', chunk)
            if kind != IMAGE_TYPE or size < 36 or not 0 < width <= MAX_DIMENSION or not 0 < height <= MAX_DIMENSION:
                raise CursorError(f'{path}: damaged image')
            handle.seek(position + size)
            pixels = handle.read(width * height * 4)
            if len(pixels) < width * height * 4:
                raise CursorError(f'{path}: damaged image')
            frames.append({'width': width, 'height': height, 'xhot': min(xhot, width),
                           'yhot': min(yhot, height), 'delay': delay, 'pixels': pixels})
            if len(frames) >= MAX_STORED_FRAMES:
                break
    return frames, available


def straight_rgba(pixels):
    """XCursor's premultiplied little-endian ARGB as straight RGBA."""
    out = bytearray(len(pixels))
    for offset in range(0, len(pixels), 4):
        b, g, r, a = pixels[offset:offset + 4]
        if 0 < a < 255:
            r, g, b = (min(255, (c * 255 + a // 2) // a) for c in (r, g, b))
        out[offset:offset + 4] = bytes((r, g, b, a))
    return out


def png(width, height, rgba):
    def chunk(kind, body):
        return (struct.pack('>I', len(body)) + kind + body
                + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF))
    stride = width * 4
    raw = b''.join(b'\x00' + bytes(rgba[row * stride:(row + 1) * stride]) for row in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def strip(frames):
    """Frames side by side on a shared canvas, hotspots aligned, as one PNG.
    Returns (png bytes, frame width, frame height)."""
    left = max(frame['xhot'] for frame in frames)
    top = max(frame['yhot'] for frame in frames)
    width = left + max(frame['width'] - frame['xhot'] for frame in frames)
    height = top + max(frame['height'] - frame['yhot'] for frame in frames)
    canvas = bytearray(width * len(frames) * height * 4)
    stride = width * len(frames) * 4
    for index, frame in enumerate(frames):
        rgba = straight_rgba(frame['pixels'])
        x0 = index * width + left - frame['xhot']
        y0 = top - frame['yhot']
        row = frame['width'] * 4
        for y in range(frame['height']):
            start = (y0 + y) * stride + x0 * 4
            canvas[start:start + row] = rgba[y * row:(y + 1) * row]
    return png(width * len(frames), height, canvas), width, height


def sample(frames):
    if len(frames) <= MAX_FRAMES:
        return frames
    step = len(frames) / MAX_FRAMES
    return [frames[int(index * step)] for index in range(MAX_FRAMES)]


def render(name, dirs, out_dir, size=PREVIEW_SIZE):
    """Writes out_dir/<shape>.png for each shape the theme draws and returns
    its index entry: the shapes drawn, the busy strip's frame count and
    duration, and the nominal sizes the arrow comes in."""
    os.makedirs(out_dir, exist_ok=True)
    entry = {'shapes': [], 'busyFrames': 1, 'busyDuration': 0, 'sizes': []}
    for shape in SHAPES:
        path = shape_file(name, dirs, shape)
        if path is None:
            continue
        frames, available = read_frames(path, size)
        if shape == 'arrow':
            entry['sizes'] = available
        if shape == 'busy' and len(frames) > 1:
            total = sum(frame['delay'] for frame in frames)
            frames = sample(frames)
            entry['busyFrames'] = len(frames)
            entry['busyDuration'] = max(200, min(4000, total or 50 * len(frames)))
        else:
            frames = frames[:1]
        data, _width, _height = strip(frames)
        target = os.path.join(out_dir, shape + '.png')
        with open(target + '.part', 'wb') as handle:
            handle.write(data)
        os.replace(target + '.part', target)
        entry['shapes'].append(shape)
    if 'arrow' not in entry['shapes']:
        raise CursorError(f'{name}: no arrow pointer')
    return entry


def write_index(path, entries):
    with open(path + '.part', 'w', encoding='utf-8') as handle:
        json.dump({'v': 1, 'themes': entries}, handle, indent=1, sort_keys=True)
        handle.write('\n')
    os.replace(path + '.part', path)
