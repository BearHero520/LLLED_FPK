#!/usr/bin/env python3
"""将可爱灯泡设计.png 转为飞牛应用所需图标尺寸（保留原图背景，不抠图）"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(__file__).resolve().parent.parent.parent / "可爱灯泡设计.png"
OUTS = [
    (ROOT / "ICON.PNG", 64),
    (ROOT / "ICON_256.PNG", 256),
    (ROOT / "app" / "ui" / "images" / "icon-64.png", 64),
    (ROOT / "app" / "ui" / "images" / "icon-256.png", 256),
    (ROOT / "app" / "www" / "images" / "logo.png", 64),
]


def sample_bg(img: Image.Image) -> tuple[int, int, int]:
    """四角取平均色，用于非正方形时补边"""
    w, h = img.size
    corners = [
        img.getpixel((0, 0)),
        img.getpixel((w - 1, 0)),
        img.getpixel((0, h - 1)),
        img.getpixel((w - 1, h - 1)),
    ]
    return tuple(sum(c[i] for c in corners) // 4 for i in range(3))


def square_fit(img: Image.Image, size: int) -> Image.Image:
    """等比内容居中，用原图背景色补成正方形后缩放"""
    img = img.convert("RGB")
    w, h = img.size
    bg = sample_bg(img)
    side = max(w, h)
    canvas = Image.new("RGB", (side, side), bg)
    canvas.paste(img, ((side - w) // 2, (side - h) // 2))
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def save_png(path: Path, img: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"源图不存在: {SRC}")

    raw = Image.open(SRC)
    base = square_fit(raw, 512)

    for out, size in OUTS:
        save_png(out, square_fit(base, size))
        print(f"  {out} ({size}x{size})")

    print(f"完成，源图: {SRC}")


if __name__ == "__main__":
    main()
