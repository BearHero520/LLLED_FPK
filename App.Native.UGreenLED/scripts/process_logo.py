#!/usr/bin/env python3
"""将可爱灯泡设计.png 转为飞牛应用所需图标尺寸"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(__file__).resolve().parent.parent.parent / "可爱灯泡设计.png"
OUTS = [
    (ROOT / "ICON.PNG", 64),
    (ROOT / "ICON_256.PNG", 256),
    (ROOT / "app" / "ui" / "images" / "icon_64.png", 64),
    (ROOT / "app" / "ui" / "images" / "icon_256.png", 256),
    (ROOT / "app" / "www" / "images" / "logo.png", 64),
]


def remove_green_bg(img: Image.Image, tolerance: int = 42) -> Image.Image:
    """去除近似纯绿背景，保留灯泡主体（透明底）"""
    img = img.convert("RGBA")
    # 四角采样背景色
    w, h = img.size
    corners = [img.getpixel((0, 0)), img.getpixel((w - 1, 0)), img.getpixel((0, h - 1)), img.getpixel((w - 1, h - 1))]
    bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if (
                abs(r - bg[0]) <= tolerance
                and abs(g - bg[1]) <= tolerance
                and abs(b - bg[2]) <= tolerance
                and g >= r - 15
                and g >= b - 15
            ):
                px[x, y] = (r, g, b, 0)

    # 轻微收缩边缘去绿晕
    alpha = img.split()[3]
    bbox = alpha.getbbox()
    if bbox:
        img = img.crop(bbox)

    return img


def square_fit(img: Image.Image, size: int) -> Image.Image:
    """等比缩放后居中铺到正方形画布（透明底）"""
    img = img.convert("RGBA")
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ox = (side - img.width) // 2
    oy = (side - img.height) // 2
    canvas.paste(img, (ox, oy), img)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def save_png(path: Path, img: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"源图不存在: {SRC}")

    raw = Image.open(SRC)
    cut = remove_green_bg(raw)
    base = square_fit(cut, 512)

    for out, size in OUTS:
        save_png(out, square_fit(base, size))
        print(f"  {out} ({size}x{size})")

    print(f"完成，源图: {SRC}")


if __name__ == "__main__":
    main()
