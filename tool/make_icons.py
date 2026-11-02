#!/usr/bin/env python3
"""Generates the Fyleon launcher icon PNGs (needs Pillow). Run: python3 tool/make_icons.py"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
SIZE = 1024
SS = 2  # supersampling
GS = 1.2  # glyph scale around center

STOPS = [(0.0, (79, 70, 229)), (0.55, (124, 58, 237)), (1.0, (6, 182, 212))]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    n = 256
    img = Image.new("RGB", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            for i in range(len(STOPS) - 1):
                t0, c0 = STOPS[i]
                t1, c1 = STOPS[i + 1]
                if t0 <= t <= t1:
                    px[x, y] = lerp(c0, c1, (t - t0) / (t1 - t0))
                    break
    return img.resize((size, size), Image.BICUBIC).convert("RGBA")


def glyph(size, mono=False):
    k = size / 1024.0

    def S(v):
        return (512 + (v - 512) * GS) * k

    main = (0, 0, 0, 255) if mono else (255, 255, 255, 255)
    flap = (0, 0, 0, 255) if mono else (147, 220, 255, 255)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = 30 * GS * k
    d.rounded_rectangle([S(330), S(270), S(435), S(760)], radius=r, fill=main)
    d.rounded_rectangle([S(330), S(480), S(615), S(575)], radius=r, fill=main)

    bar = Image.new("L", (size, size), 0)
    bd = ImageDraw.Draw(bar)
    bd.rounded_rectangle([S(330), S(270), S(700), S(375)], radius=r, fill=255)
    bd.polygon([(S(605), S(260)), (S(710), S(365)), (S(710), S(260))], fill=0)
    layer.paste(Image.new("RGBA", (size, size), main), (0, 0), bar)

    fm = Image.new("L", (size, size), 0)
    ImageDraw.Draw(fm).polygon([(S(615), S(270)), (S(700), S(355)), (S(615), S(355))], fill=255)
    fm = ImageChops.multiply(fm, bar)
    layer.paste(Image.new("RGBA", (size, size), flap), (0, 0), fm)

    # four point spark
    cx, cy, ro, ri = 668, 668, 64, 17
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = ro if i % 2 == 0 else ri
        pts.append((S(cx + rad * math.cos(ang) / GS * GS), S(cy + rad * math.sin(ang))))
    ImageDraw.Draw(layer).polygon(pts, fill=main)
    return layer


def with_shadow(layer):
    alpha = layer.split()[3]
    sh = Image.new("RGBA", layer.size, (30, 20, 90, 0))
    sh.putalpha(alpha.point(lambda v: int(v * 0.35)))
    off = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    off.paste(sh, (0, int(14 * layer.size[0] / 1024)))
    off = off.filter(ImageFilter.GaussianBlur(14 * layer.size[0] / 1024))
    return Image.alpha_composite(off, layer)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    big = SIZE * SS
    bg = gradient(big)
    g = with_shadow(glyph(big))
    icon = Image.alpha_composite(bg, g).resize((SIZE, SIZE), Image.LANCZOS)
    icon.convert("RGB").save(OUT / "icon.png")
    gradient(SIZE).convert("RGB").save(OUT / "icon_background.png")
    g.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon_foreground.png")
    glyph(big, mono=True).resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon_mono.png")
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
