#!/usr/bin/env python3
"""Render an MT5 realized-balance CSV as a dependency-free PNG."""

from __future__ import annotations

import argparse
import csv
import math
import pathlib
import struct
import zlib


WIDTH = 1200
HEIGHT = 620
PAD_X = 70
PAD_Y = 48


def load_balances(path: pathlib.Path) -> list[float]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        values = [float(row["balance"]) for row in csv.DictReader(handle)]
    if len(values) < 2 or not all(math.isfinite(value) for value in values):
        raise ValueError("invalid balance curve")
    return values


def set_pixel(pixels: bytearray, x: int, y: int, color: tuple[int, int, int]) -> None:
    if 0 <= x < WIDTH and 0 <= y < HEIGHT:
        offset = (y * WIDTH + x) * 3
        pixels[offset:offset + 3] = bytes(color)


def draw_line(
    pixels: bytearray,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    color: tuple[int, int, int],
    width: int = 1,
) -> None:
    dx = abs(x1 - x0)
    sx = 1 if x0 < x1 else -1
    dy = -abs(y1 - y0)
    sy = 1 if y0 < y1 else -1
    error = dx + dy
    while True:
        radius = max(0, width // 2)
        for ox in range(-radius, radius + 1):
            for oy in range(-radius, radius + 1):
                set_pixel(pixels, x0 + ox, y0 + oy, color)
        if x0 == x1 and y0 == y1:
            break
        twice = 2 * error
        if twice >= dy:
            error += dy
            x0 += sx
        if twice <= dx:
            error += dx
            y0 += sy


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def render(values: list[float], color: tuple[int, int, int]) -> bytes:
    pixels = bytearray(bytes((246, 247, 242)) * WIDTH * HEIGHT)
    left, right = PAD_X, WIDTH - PAD_X
    top, bottom = PAD_Y, HEIGHT - PAD_Y
    grid = (210, 216, 208)
    axis = (102, 115, 106)
    for step in range(6):
        y = top + (bottom - top) * step // 5
        draw_line(pixels, left, y, right, y, grid)
    for step in range(9):
        x = left + (right - left) * step // 8
        draw_line(pixels, x, top, x, bottom, grid)
    draw_line(pixels, left, top, left, bottom, axis, 2)
    draw_line(pixels, left, bottom, right, bottom, axis, 2)

    low, high = min(values), max(values)
    padding = max((high - low) * 0.08, 1.0)
    low -= padding
    high += padding
    span = high - low
    points: list[tuple[int, int]] = []
    for index, value in enumerate(values):
        x = left + round(index * (right - left) / (len(values) - 1))
        y = bottom - round((value - low) * (bottom - top) / span)
        points.append((x, y))
    for start, finish in zip(points, points[1:]):
        draw_line(pixels, *start, *finish, color, 5)
    for x, y in (points[0], points[-1]):
        for radius in range(7, 0, -1):
            shade = color if radius < 5 else (255, 255, 255)
            for ox in range(-radius, radius + 1):
                for oy in range(-radius, radius + 1):
                    if ox * ox + oy * oy <= radius * radius:
                        set_pixel(pixels, x + ox, y + oy, shade)

    rows = b"".join(b"\x00" + pixels[y * WIDTH * 3:(y + 1) * WIDTH * 3] for y in range(HEIGHT))
    signature = b"\x89PNG\r\n\x1a\n"
    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    return signature + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(rows, 9)) + png_chunk(b"IEND", b"")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curve", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--color", choices=("green", "blue"), default="green")
    args = parser.parse_args()
    colors = {"green": (8, 127, 91), "blue": (38, 91, 153)}
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(render(load_balances(pathlib.Path(args.curve)), colors[args.color]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
