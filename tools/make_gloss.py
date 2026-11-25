#!/usr/bin/env python3
"""Crop the gloss texture so its rounded shoulders are not visible.

The texture is a glossy rounded shape: a band of light across the top with
domed shoulders, and a fainter one along the bottom. Stretched over a drawer
that is full height, the domes show as curves - the gloss appears to arch
away from the drawer's corners, which is not what a panel wants.

The part of the shape that spans the full width is the straight-sided middle
of the top band, so that is what is kept. The very top of the crop is faded
out, so the band does not start with a hard edge, and the bottom of the crop
is the shape's own fade to nothing, so it ends softly.

Usage:
    python3 tools/make_gloss.py
"""

import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SOURCE = ROOT / "gloss.png"
TARGET = ROOT / "Resources" / "Gloss.png"

# The straight-sided part of the band: from where the shape reaches the full
# width to where it has faded out completely.
CROP_X = 2
CROP_Y = 96
CROP_W = 762
CROP_H = 224

# The top of the crop is faded in over this much of it, so the gloss does not
# begin with a hard line, and the bottom is faded out over this much, so the
# band ends softly rather than on the shape's curve.
FADE_IN = 0.18
FADE_OUT = 0.45


def read_rgba(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
            depth, colour = body[8], body[9]
            assert depth == 8 and colour == 6, "expected 8-bit RGBA"
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length

    raw = zlib.decompress(idat)
    stride = width * 4
    rows = []
    previous = bytearray(stride)
    i = 0
    for _ in range(height):
        filter_type = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        if filter_type == 1:
            for x in range(4, stride):
                line[x] = (line[x] + line[x - 4]) & 0xFF
        elif filter_type == 2:
            for x in range(stride):
                line[x] = (line[x] + previous[x]) & 0xFF
        elif filter_type == 3:
            for x in range(stride):
                left = line[x - 4] if x >= 4 else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 0xFF
        elif filter_type == 4:
            for x in range(stride):
                a = line[x - 4] if x >= 4 else 0
                b = previous[x]
                c = previous[x - 4] if x >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        rows.append(line)
        previous = line
    return width, height, rows


def write_rgba(path, rows, width, height):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw += row

    def chunk(tag, d):
        return (struct.pack(">I", len(d)) + tag + d
                + struct.pack(">I", zlib.crc32(tag + d) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def main():
    width, height, rows = read_rgba(SOURCE)
    print(f"source {width}x{height}")

    fade_in = max(1, int(CROP_H * FADE_IN))
    fade_out = max(1, int(CROP_H * FADE_OUT))
    out = []
    for y in range(CROP_H):
        source_row = rows[CROP_Y + y]
        # The fade in at the top of the crop, and the fade out at the bottom.
        if y < fade_in:
            factor = (y / float(fade_in)) ** 2
        elif y > CROP_H - fade_out:
            t = (CROP_H - y) / float(fade_out)
            factor = t ** 2
        else:
            factor = 1.0
        row = bytearray()
        for x in range(CROP_W):
            r, g, b, a = source_row[(CROP_X + x) * 4:(CROP_X + x) * 4 + 4]
            row += bytes((r, g, b, int(a * factor)))
        out.append(row)

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    write_rgba(TARGET, out, CROP_W, CROP_H)
    print(f"wrote {TARGET} ({CROP_W}x{CROP_H}, {TARGET.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
