#!/usr/bin/env python3
"""Preview the paper texture over the paper it is drawn on.

Reads Resources/PaperTexture@2x.png and composites it over the paper's
gradient, magnified, so the texture can be judged without a device.

Usage:
    python3 tools/paper_texture_preview.py
"""

import struct
import zlib
from pathlib import Path

PAPER_TOP = (0.984, 0.969, 0.925)
PAPER_BOTTOM = (0.945, 0.922, 0.855)
SCALE = 4


def read_gray_alpha(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, w, h = 8, b"", 0, 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    rows = []
    i = 0
    for _ in range(h):
        filter_type = raw[i]
        i += 1
        line = raw[i:i + w * 2]
        i += w * 2
        assert filter_type == 0, "expected filter 0"
        rows.append([(line[x * 2], line[x * 2 + 1]) for x in range(w)])
    return rows


def write_rgb(path, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b in row:
            raw += bytes((int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5)))

    def chunk(tag, d):
        return (struct.pack(">I", len(d)) + tag + d
                + struct.pack(">I", zlib.crc32(tag + d) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", len(pixels[0]), len(pixels), 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def main():
    here = Path(__file__).resolve().parent
    tile = read_gray_alpha(here.parent / "Resources" / "PaperTexture@2x.png")
    height = len(tile)
    width = len(tile[0])

    out = []
    for y in range(height):
        t = y / float(height - 1)
        base = [PAPER_TOP[i] + (PAPER_BOTTOM[i] - PAPER_TOP[i]) * t for i in range(3)]
        line = []
        for x in range(width):
            grey, alpha = tile[y][x]
            a = alpha / 255.0
            mixed = [base[i] * (1.0 - a) for i in range(3)]
            line += [tuple(mixed)] * SCALE
        for _ in range(SCALE):
            out.append(list(line))

    path = here / "paper-texture-preview.png"
    write_rgb(path, out)
    print(f"wrote {path} ({len(out[0])}x{len(out)})")


if __name__ == "__main__":
    main()
