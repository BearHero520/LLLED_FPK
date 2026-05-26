#!/usr/bin/env python3
"""生成占位图标 PNG（打包前运行一次）"""
import struct
import zlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def png_rgb(size, r, g, b):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    raw = b""
    row = b"\x00" + bytes([r, g, b]) * size
    for _ in range(size):
        raw += row
    compressed = zlib.compress(raw, 9)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def write(path, size):
    data = png_rgb(size, 0x23, 0x86, 0x36)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


if __name__ == "__main__":
    write(os.path.join(ROOT, "ICON.PNG"), 64)
    write(os.path.join(ROOT, "ICON_256.PNG"), 256)
    write(os.path.join(ROOT, "app", "ui", "images", "icon-64.png"), 64)
    write(os.path.join(ROOT, "app", "ui", "images", "icon-256.png"), 256)
    print("icons written")
