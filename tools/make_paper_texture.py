#!/usr/bin/env python3
"""Generate the paper texture the lyrics sheet is drawn with.

The texture has to be three things at once, which is why it is generated
rather than painted by hand:

  seamless   the sheet is much larger than the tile, and the tile is drawn as
             a pattern, so any feature crossing an edge would show as a line
             where the pattern repeats.

  unscaled   the grain has to be the same size on every device, so the tile is
             generated separately at each scale rather than one image scaled
             up. Scaling noise up just makes bigger noise.

  uncorrelated
             the first version drew the fibre as alternating one-pixel rows,
             which read as hard horizontal banding. This one is uncorrelated
             per-pixel grain plus short strokes at random angles, so there is
             nothing to band.

Writes Resources/PaperTexture.png, @2x and @3x.

Usage:
    python3 tools/make_paper_texture.py
"""

import math
import struct
import zlib
from pathlib import Path

# The tile, in points. The texture is drawn as a pattern, so this is how big
# the repeat is on screen.
TILE_POINTS = 64

# How much the grain varies. Enough to be felt, not enough to be seen.
GRAIN_ALPHA = 0.030

# The strokes that give the paper its fibre: many short ones rather than a
# few long ones, or they read as cracks.
STROKES_PER_TILE = 700
STROKE_MIN_LENGTH = 0.8
STROKE_MAX_LENGTH = 3.5
STROKE_ALPHA = 0.016
STROKE_WIDTH = 0.45


def write_png_gray_alpha(path, pixels, width, height):
    """pixels: rows of (grey 0..255, alpha 0..255)."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for grey, alpha in row:
            raw += bytes((grey, alpha))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 4, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


class Rng:
    """A small deterministic generator, so the texture is the same every time."""

    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFF

    def next(self):
        self.state = (self.state * 1103515245 + 12345) & 0xFFFFFFFF
        return (self.state >> 8) & 0xFFFFFF

    def unit(self):
        return self.next() / float(0xFFFFFF)

    def between(self, low, high):
        return low + (high - low) * self.unit()

    def pick(self, seq):
        return seq[self.next() % len(seq)]


def build_tile(scale):
    """The tile at a given scale: rows of (grey, alpha)."""
    pixels = TILE_POINTS * scale
    rng = Rng(0x5EED0000 + scale * 977)

    # The grain: one uncorrelated value per pixel, so nothing lines up into
    # bands. Half of it lightens, half darkens.
    buffer = [[0.0] * pixels for _ in range(pixels)]

    for y in range(pixels):
        row = buffer[y]
        for x in range(pixels):
            row[x] = -rng.unit() * GRAIN_ALPHA

    # The strokes: short, at random angles, so the paper has a direction
    # without any of them lining up.
    count = int(STROKES_PER_TILE * scale * scale)
    for _ in range(count):
        angle = rng.between(0.0, math.pi * 2.0)
        length = rng.between(STROKE_MIN_LENGTH, STROKE_MAX_LENGTH) * scale
        start_x = rng.between(0.0, pixels)
        start_y = rng.between(0.0, pixels)
        dx = math.cos(angle) * length
        dy = math.sin(angle) * length
        strength = STROKE_ALPHA * rng.between(0.4, 1.0)
        width = STROKE_WIDTH * scale

        steps = max(2, int(length * 4))
        for step in range(steps + 1):
            t = step / float(steps)
            px = start_x + dx * t
            py = start_y + dy * t
            # Splat a small round dab. Wrapped, so a stroke that runs off
            # the edge carries on at the other side and the tile still joins
            # up.
            reach = max(1, int(width) + 1)
            for oy in range(-reach, reach + 1):
                for ox in range(-reach, reach + 1):
                    x = int(px) + ox
                    y = int(py) + oy
                    fx = x - px
                    fy = y - py
                    distance = math.sqrt(fx * fx + fy * fy)
                    if distance > width:
                        continue
                    weight = 1.0 - (distance / width)
                    buffer[y % pixels][x % pixels] -= strength * weight * 0.5

    # The PNG carries a grey and an alpha: the noise darkens or lightens
    # whatever is underneath, so it can sit over the paper's gradient.
    out = []
    for y in range(pixels):
        row = []
        for x in range(pixels):
            value = buffer[y][x]
            # The texture only ever darkens, so it can be drawn over the
            # paper with plain alpha and the preview is what the device shows.
            grey = 0
            alpha = int(min(255, -value * 255.0))
            row.append((grey, alpha))
        out.append(row)
    return out


def main():
    out = Path(__file__).resolve().parent.parent / "Resources"
    for scale, name in ((1, "PaperTexture.png"),
                        (2, "PaperTexture@2x.png"),
                        (3, "PaperTexture@3x.png")):
        tile = build_tile(scale)
        path = out / name
        write_png_gray_alpha(path, tile, len(tile), len(tile))
        print(f"wrote {path}  ({len(tile)}x{len(tile)}px, {path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
