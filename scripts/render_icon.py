#!/usr/bin/env python3
"""Renders the XM Connect app icon (all macOS iconset sizes) with Pillow + NumPy.

    python3 scripts/render_icon.py

The PNGs are committed in Resources/AppIcon.iconset, so building the app does not need Python;
`make` only runs `iconutil` on them.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 2048  # working resolution (2× the largest icon, for clean anti-aliasing)


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def superellipse_mask(size, box, n=5.0):
    """Apple-style squircle as an L-mode mask."""
    x0, y0, x1, y1 = box
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rx, ry = (x1 - x0) / 2, (y1 - y0) / 2
    v = np.abs((xx - cx) / rx) ** n + np.abs((yy - cy) / ry) ** n
    # Soft edge over ~1.5 px for anti-aliasing.
    edge = np.clip((1.0 - v) * max(rx, ry) / (n * 1.5), 0, 1)
    return Image.fromarray((edge * 255).astype(np.uint8), "L")


def radial(size, cx, cy, radius, color, alpha):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** 2 * alpha
    layer = np.zeros((size, size, 4), np.float32)
    layer[..., :3] = color
    layer[..., 3] = a * 255
    return Image.fromarray(layer.astype(np.uint8), "RGBA")


def vertical_gradient(size, top, bottom):
    t = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    top, bottom = np.array(top, np.float32), np.array(bottom, np.float32)
    rgb = top + (bottom - top) * t[..., None]
    rgb = np.broadcast_to(rgb, (size, size, 3))
    alpha = np.full((size, size, 1), 255, np.float32)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2).astype(np.uint8), "RGBA")


def gradient_fill(mask, top, bottom, y0, y1):
    """Fills `mask` with a vertical gradient running from y0 to y1."""
    size = mask.size[0]
    t = np.clip((np.arange(size, dtype=np.float32) - y0) / max(1, y1 - y0), 0, 1)[:, None]
    top, bottom = np.array(top, np.float32), np.array(bottom, np.float32)
    rgb = np.broadcast_to(top + (bottom - top) * t[..., None], (size, size, 3))
    a = np.array(mask, np.float32)[..., None]
    return Image.fromarray(np.concatenate([rgb, a], axis=2).astype(np.uint8), "RGBA")


def arc_band(draw, cx, cy, r_out, r_in, a0, a1, fill, steps=240):
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
    for i in range(steps, -1, -1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + r_in * math.cos(a), cy + r_in * math.sin(a)))
    draw.polygon(pts, fill=fill)


def render_master():
    margin = 200  # Apple's grid: 824/1024 body
    box = (margin, margin, S - margin, S - margin)
    body = superellipse_mask(S, box)
    W = box[2] - box[0]
    cx = S / 2

    # Background inside the squircle.
    bg = vertical_gradient(S, hex_rgb("#1D1546"), hex_rgb("#05060F"))
    for glow in (
        radial(S, cx, S * 0.63, W * 0.62, hex_rgb("#6C63FF"), 0.85),
        radial(S, cx, S * 0.86, W * 0.42, hex_rgb("#2FD2FF"), 0.55),
        radial(S, S * 0.74, S * 0.24, W * 0.36, hex_rgb("#FF5E9C"), 0.30),
    ):
        bg = Image.alpha_composite(bg, glow)

    # "Connect" rings behind the headphones.
    rings = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    rcx, rcy = cx, S * 0.565
    for i, (r, a) in enumerate(((0.34, 70), (0.42, 46), (0.50, 26))):
        rr = W * r
        rd.ellipse((rcx - rr, rcy - rr, rcx + rr, rcy + rr), outline=(255, 255, 255, a), width=10)
    rings = rings.filter(ImageFilter.GaussianBlur(2))
    bg = Image.alpha_composite(bg, rings)

    # Headphones silhouette (band + sliders + cups), built as masks.
    hp_cx, hp_cy = cx, S * 0.60
    r_out, r_in = W * 0.33, W * 0.282
    band = Image.new("L", (S, S), 0)
    bd = ImageDraw.Draw(band)
    arc_band(bd, hp_cx, hp_cy, r_out, r_in, 192, 348, 255)
    # Sliders
    sl_w = W * 0.022
    for side in (-1, 1):
        x = hp_cx + side * (r_out + r_in) / 2 * math.cos(math.radians(12))
        y_top = hp_cy - (r_out + r_in) / 2 * math.sin(math.radians(12))
        bd.rounded_rectangle((x - sl_w, y_top - 10, x + sl_w, hp_cy + W * 0.03), radius=sl_w, fill=255)

    cups = Image.new("L", (S, S), 0)
    cd = ImageDraw.Draw(cups)
    cup_w, cup_h = W * 0.19, W * 0.305
    cup_cy = hp_cy + W * 0.07
    cup_x = (r_out + r_in) / 2 * math.cos(math.radians(12))
    cup_boxes = []
    for side in (-1, 1):
        x = hp_cx + side * cup_x
        b = (x - cup_w / 2, cup_cy - cup_h / 2, x + cup_w / 2, cup_cy + cup_h / 2)
        cup_boxes.append((side, b))
        cd.ellipse(b, fill=255)

    silhouette = Image.fromarray(np.maximum(np.array(band), np.array(cups)), "L")

    # Shadow under the headphones.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(silhouette.point(lambda v: int(v * 0.65)))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -28)).filter(ImageFilter.GaussianBlur(36))
    bg = Image.alpha_composite(bg, shadow)

    # Glow around the cups (mode light).
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for side, b in cup_boxes:
        pad = 30
        color = hex_rgb("#2FD2FF") if side > 0 else hex_rgb("#8A7DFF")
        gd.ellipse((b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad), outline=color + (255,), width=34)
    glow = glow.filter(ImageFilter.GaussianBlur(30))
    bg = Image.alpha_composite(bg, glow)

    # Metallic body: bright top to cool grey bottom.
    metal = gradient_fill(silhouette, hex_rgb("#FFFFFF"), hex_rgb("#AEB4C8"),
                          hp_cy - r_out, cup_cy + cup_h / 2)
    bg = Image.alpha_composite(bg, metal)

    # Cup details: inner shading, light strip and highlight.
    detail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    for side, (x0, y0, x1, y1) in cup_boxes:
        w, h = x1 - x0, y1 - y0
        # Soft shade on the inner side of each cup.
        inner = (x0 + w * (0.42 if side < 0 else 0.0), y0 + h * 0.08,
                 x1 - w * (0.0 if side < 0 else 0.42), y1 - h * 0.08)
        dd.ellipse(inner, fill=(40, 46, 70, 38))
        # Light strip
        inset = w * 0.16
        strip = (x0 + inset, y0 + inset * 1.4, x1 - inset, y1 - inset * 1.4)
        color = hex_rgb("#2FD2FF") if side > 0 else hex_rgb("#8A7DFF")
        dd.ellipse(strip, outline=color + (255,), width=12)
        # Specular highlight
        hl = (x0 + w * 0.24, y0 + h * 0.12, x0 + w * 0.44, y0 + h * 0.30)
        dd.ellipse(hl, fill=(255, 255, 255, 80))
    detail = detail.filter(ImageFilter.GaussianBlur(6))
    # Keep details inside the cups.
    detail.putalpha(Image.fromarray(np.minimum(np.array(detail.getchannel("A")), np.array(cups)), "L"))
    bg = Image.alpha_composite(bg, detail)

    # Band highlight line.
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    arc_band(hd, hp_cx, hp_cy, r_out - 12, r_out - 26, 215, 325, (255, 255, 255, 170))
    hl = hl.filter(ImageFilter.GaussianBlur(4))
    bg = Image.alpha_composite(bg, hl)

    # Top sheen on the squircle.
    sheen = radial(S, cx, box[1] - W * 0.15, W * 0.75, (255, 255, 255), 0.16)
    bg = Image.alpha_composite(bg, sheen)

    # Clip to the squircle.
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), body)

    # Rim light.
    rim = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    inner_body = superellipse_mask(S, (box[0] + 5, box[1] + 5, box[2] - 5, box[3] - 5))
    rim_alpha = np.clip(np.array(body, np.int16) - np.array(inner_body, np.int16), 0, 255).astype(np.uint8)
    rim.putalpha(Image.fromarray((rim_alpha * 0.35).astype(np.uint8), "L"))
    icon = Image.alpha_composite(icon, rim)

    # Drop shadow beneath the whole icon (part of the macOS icon grid).
    drop = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    drop.putalpha(body.point(lambda v: int(v * 0.45)))
    drop = drop.transform(drop.size, Image.AFFINE, (1, 0, 0, 0, 1, -24)).filter(ImageFilter.GaussianBlur(28))
    final = Image.alpha_composite(drop, icon)
    return final


def render_installer_background(master):
    """Faded icon in the bottom-left corner of the Installer window (transparent elsewhere)."""
    w, h = 620, 418
    bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    icon = master.resize((150, 150), Image.LANCZOS)
    faded = icon.copy()
    faded.putalpha(icon.getchannel("A").point(lambda v: int(v * 0.9)))
    bg.alpha_composite(faded, (24, h - 150 - 18))
    return bg


def render_dmg_background(master):
    """Light window background (Finder labels stay readable) with an arrow to Applications."""
    w, h = 660, 400
    size = max(w, h)
    bg = vertical_gradient(size, hex_rgb("#FAF9FF"), hex_rgb("#E7E4F5")).crop((0, 0, w, h))
    for glow in (radial(size, w * 0.5, h * 1.05, 380, hex_rgb("#8A7DFF"), 0.28),
                 radial(size, w * 0.88, h * 0.05, 260, hex_rgb("#2FD2FF"), 0.18)):
        bg = Image.alpha_composite(bg, glow.crop((0, 0, w, h)))
    d = ImageDraw.Draw(bg)
    # Arrow between the two icon slots (app at x=170, Applications at x=490, y=190).
    y = 190
    violet = hex_rgb("#6C63FF")
    for i in range(8):
        x0 = 262 + i * 18
        d.ellipse((x0 - 3, y - 3, x0 + 3, y + 3), fill=violet + (60 + i * 22,))
    d.polygon([(410, y - 14), (432, y), (410, y + 14)], fill=violet + (240,))
    try:
        from PIL import ImageFont
        font = ImageFont.truetype("DejaVuSans.ttf", 15)
        small = ImageFont.truetype("DejaVuSans.ttf", 12)
    except OSError:
        font = small = None
    d.text((w / 2, 320), "Drag XM Connect into Applications", fill=(40, 36, 70, 230), font=font, anchor="mm")
    d.text((w / 2, 344), "Glisse XM Connect dans Applications", fill=(40, 36, 70, 150), font=small, anchor="mm")
    return bg


def main():
    master = render_master()
    out = os.path.join(ROOT, "Resources", "AppIcon.iconset")
    os.makedirs(out, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}.png" if scale == 1 else f"icon_{base}x{base}@2x.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(docs, "icon.png"))
    render_installer_background(master).save(os.path.join(ROOT, "installer", "resources", "background.png"))
    dmg = render_dmg_background(master)
    dmg.save(os.path.join(ROOT, "installer", "dmg-background.png"))
    dmg.resize((1320, 800), Image.LANCZOS).save(os.path.join(ROOT, "installer", "dmg-background@2x.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
