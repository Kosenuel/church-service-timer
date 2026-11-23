#!/usr/bin/env python3
"""Draws the artwork for the Windows installer (windows/installer/art/).

Run from the repository root:

    python3 tool/make_installer_art.py

It needs Pillow and numpy, reads only files in this repository (the app's
fonts and icon, and screenshots from test/goldens) and writes PNG files.
It uses no network and no random numbers, so running it twice gives
byte-identical files. See windows/installer/README.md.

What it makes:

* welcome-<width>.png   the tall picture on the Welcome page (left side), in
                        several sizes so it stays sharp from 100% to 250%
                        Windows scaling (256-colour PNG, to stay small). Proportions match Inno Setup's
                        WizardImageFile area (551 x 1055 at 250%).
* ready-<width>.png     the same for the Finished page ("curtain call").
* header-<size>.png     the small square picture at the top right of the
                        inner pages, with transparent rounded corners.
* scene-1.png .. 6.png  the slideshow shown while files are copied, each
                        1000 x 333.

Colours are the app's Midnight Lime theme (lib/shared/app_theme.dart).
"""
from __future__ import annotations

import math
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "windows" / "installer" / "art"
GOLD = ROOT / "test" / "goldens"
FONTS = ROOT / "assets" / "fonts"

BG = (10, 18, 16)
SURFACE = (19, 29, 26)
ACCENT = (201, 249, 108)
MUTED = (156, 170, 165)
TEXT = (228, 231, 222)
RED = (229, 54, 60)

# Sizes of the wizard images, from 100% to 250% scaling. The tall picture
# keeps the 164 x 314 proportions of Inno Setup's own area (551 x 1055 at
# 250%); setup picks the smallest file that is at least as big as the area.
TALL_SIZES = [(220, 422), (331, 633), (441, 844), (551, 1055)]
SMALL_SIZES = [64, 80, 96, 128, 160]
SCENE_SIZE = (1000, 333)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"Roboto-{name}.ttf"), size)


# ---------------------------------------------------------------- helpers


def vertical_gradient(size, top, bottom):
    w, h = size
    t = np.linspace(0.0, 1.0, h)[:, None, None]
    a = np.array(top, dtype=np.float32)[None, None, :]
    b = np.array(bottom, dtype=np.float32)[None, None, :]
    arr = a + (b - a) * t
    arr = np.repeat(arr, w, axis=1)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB")


def screen(base: Image.Image, layer: Image.Image) -> Image.Image:
    """Adds light: `layer` (RGB) brightens `base`."""
    return ImageChops.screen(base, layer)


def tinted(mask: Image.Image, colour, strength=1.0) -> Image.Image:
    """A flat colour image whose brightness follows the L `mask`."""
    m = np.asarray(mask, dtype=np.float32) / 255.0 * strength
    c = np.array(colour, dtype=np.float32)[None, None, :]
    return Image.fromarray((m[:, :, None] * c).clip(0, 255).astype(np.uint8), "RGB")


def glow_text(base, xy, text, fnt, colour, anchor="mm", glow=1.0, tracking=0):
    """Draws `text` in `colour` with a soft glow of the same colour."""
    mask = Image.new("L", base.size, 0)
    draw_tracked(ImageDraw.Draw(mask), xy, text, fnt, 255, anchor, tracking)
    for radius, strength in ((38, 0.55), (18, 0.55), (7, 0.6)):
        blurred = mask.filter(ImageFilter.GaussianBlur(radius * base.size[0] / 1000 + 1))
        base = screen(base, tinted(blurred, colour, strength * glow))
    crisp = tinted(mask, colour, 1.0)
    return screen(base, crisp)


def draw_tracked(draw, xy, text, fnt, fill, anchor="mm", tracking=0):
    """Text with extra letter spacing. Only anchors 'mm', 'lm' and 'rm'."""
    if tracking == 0:
        draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)
        return
    widths = [fnt.getlength(ch) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor[0] == "m":
        x -= total / 2
    elif anchor[0] == "r":
        x -= total
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=fnt, fill=fill, anchor="l" + anchor[1])
        x += w + tracking


def beam(size, apex, spread_deg, angle_deg, length, softness, power=1.6):
    """A cone of stage light as an L image: bright at `apex`, fading away."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = xx - apex[0]
    dy = yy - apex[1]
    dist = np.sqrt(dx * dx + dy * dy) + 1e-3
    ang = np.degrees(np.arctan2(dx, dy))  # 0 = straight down
    off = np.abs(ang - angle_deg)
    edge = np.clip(1.0 - off / (spread_deg / 2.0), 0.0, 1.0)
    fade = np.clip(1.0 - dist / length, 0.0, 1.0) ** power
    arr = (edge ** 1.4) * fade
    img = Image.fromarray((arr * 255).clip(0, 255).astype(np.uint8), "L")
    return img.filter(ImageFilter.GaussianBlur(softness))


def vignette(img: Image.Image, strength=0.55) -> Image.Image:
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - w / 2) / (w / 2)
    ny = (yy - h / 2) / (h / 2)
    r = np.sqrt(nx * nx + ny * ny)
    k = 1.0 - strength * np.clip(r - 0.45, 0, 1) ** 1.4
    arr = np.asarray(img, dtype=np.float32) * k[:, :, None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB")


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def shadowed_paste(base, tile, xy, radius, shadow=0.7, blur=18, offset=(0, 10)):
    """Pastes `tile` with rounded corners and a soft drop shadow."""
    mask = rounded_mask(tile.size, radius)
    sh = Image.new("L", base.size, 0)
    sh.paste(mask, (xy[0] + offset[0], xy[1] + offset[1]))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    dark = Image.new("RGB", base.size, (0, 0, 0))
    base = Image.composite(dark, base, sh.point(lambda v: int(v * shadow)))
    base.paste(tile, xy, mask)
    return base


def golden(name, crop=None):
    img = Image.open(GOLD / name).convert("RGB")
    if crop:
        img = img.crop(crop)
    return img


def fit_height(img, h):
    w = round(img.width * h / img.height)
    return img.resize((w, h), Image.LANCZOS)


def icon_tile(px):
    """The app icon as a rounded tile with transparent corners."""
    src = Image.open(ROOT / "play" / "graphics" / "icon-512.png").convert("RGB")
    tile = src.resize((px, px), Image.LANCZOS).convert("RGBA")
    tile.putalpha(rounded_mask((px, px), round(px * 0.22)))
    return tile


# ------------------------------------------------------------ tall images


def draw_tall(width: int, height: int, ready: bool) -> Image.Image:
    """The Welcome (ready=False) or Finished (ready=True) picture, drawn at
    2x and reduced, so edges are smooth at every size."""
    k = 2
    W, H = 551 * k, 1055 * k
    base = vertical_gradient((W, H), (14, 26, 22), (6, 11, 10))

    # Stage light: cones from above that meet on the clock.
    beams = Image.new("RGB", (W, H), (0, 0, 0))
    cones = [
        ((W * 0.50, -260 * k), 46, 0, 1500 * k, 0.8, 0.17),
        ((W * 0.08, -200 * k), 30, 17, 1450 * k, 0.8, 0.15),
        ((W * 0.92, -200 * k), 30, -17, 1450 * k, 0.8, 0.15),
    ]
    if ready:
        cones += [
            ((W * 0.28, -240 * k), 24, 8, 1450 * k, 0.8, 0.13),
            ((W * 0.72, -240 * k), 24, -8, 1450 * k, 0.8, 0.13),
        ]
    for apex, spread, ang, length, power, strength in cones:
        mask = beam((W, H), apex, spread, ang, length, 30 * k, power=power)
        beams = screen(beams, tinted(mask, ACCENT, strength))
    base = screen(base, beams)

    # Floor: a soft pool of light under the clock.
    floor = Image.new("L", (W, H), 0)
    ImageDraw.Draw(floor).ellipse((W * 0.0, H * 0.74, W * 1.0, H * 1.0), fill=255)
    floor = floor.filter(ImageFilter.GaussianBlur(55 * k))
    base = screen(base, tinted(floor, ACCENT, 0.14 if not ready else 0.22))

    cx = W // 2
    cy = 520 * k
    rr = 218 * k

    # The ring from the app icon: most of the way round while counting,
    # closed once it is ready.
    ring = Image.new("L", (W, H), 0)
    rd = ImageDraw.Draw(ring)
    start, end = (-90 + 28, -90 + 300) if not ready else (-90, 270)
    rd.arc((cx - rr, cy - rr, cx + rr, cy + rr), start, end, fill=255, width=9 * k)
    for radius, s in ((34 * k, 0.45), (12 * k, 0.55)):
        base = screen(base, tinted(ring.filter(ImageFilter.GaussianBlur(radius)), ACCENT, s))
    base = screen(base, tinted(ring, ACCENT, 0.95))

    if not ready:
        digits = font("Light", 150 * k)
        base = glow_text(base, (cx, cy - 84 * k), "04", digits, TEXT, glow=0.3)
        base = glow_text(base, (cx, cy + 84 * k), "58", digits, ACCENT, glow=1.0)
        bar = Image.new("L", (W, H), 0)
        ImageDraw.Draw(bar).rounded_rectangle((cx - 50 * k, cy - 3 * k, cx + 50 * k, cy + 3 * k), 3 * k, fill=255)
        base = screen(base, tinted(bar.filter(ImageFilter.GaussianBlur(8 * k)), ACCENT, 0.7))
        base = screen(base, tinted(bar, ACCENT, 0.9))
    else:
        tick = Image.new("L", (W, H), 0)
        td = ImageDraw.Draw(tick)
        pts = [(cx - 96 * k, cy + 6 * k), (cx - 30 * k, cy + 74 * k), (cx + 100 * k, cy - 76 * k)]
        td.line(pts, fill=255, width=30 * k, joint="curve")
        for p in pts:
            td.ellipse((p[0] - 15 * k, p[1] - 15 * k, p[0] + 15 * k, p[1] + 15 * k), fill=255)
        for radius, s in ((36 * k, 0.5), (14 * k, 0.6)):
            base = screen(base, tinted(tick.filter(ImageFilter.GaussianBlur(radius)), ACCENT, s))
        base = screen(base, tinted(tick, (222, 252, 160), 1.0))

    # The icon at the top, the name and a line of words below.
    tile = icon_tile(124 * k)
    layer = base.convert("RGBA")
    layer.alpha_composite(tile, (cx - 62 * k, 64 * k))
    base = layer.convert("RGB")
    d = ImageDraw.Draw(base)
    draw_tracked(d, (cx, 820 * k), "CHURCH SERVICE", font("Bold", 29 * k), TEXT, "mm", 5 * k)
    draw_tracked(d, (cx, 868 * k), "TIMER", font("Bold", 29 * k), ACCENT, "mm", 16 * k)
    tag = "Ready for Sunday." if ready else "Everyone on time."
    draw_tracked(d, (cx, 948 * k), tag, font("Light", 30 * k), MUTED, "mm", 2 * k)
    d.line((cx - 36 * k, 990 * k, cx + 36 * k, 990 * k), fill=(70, 98, 44), width=2 * k)

    base = vignette(base, 0.5)
    return base.resize((width, height), Image.LANCZOS)


def header_image(px: int) -> Image.Image:
    return icon_tile(px)


# ----------------------------------------------------------------- scenes


def stage_backdrop(accent=ACCENT, strength=0.13, seed_shift=0.0):
    w, h = SCENE_SIZE
    k = 2
    W, H = w * k, h * k
    base = vertical_gradient((W, H), (12, 22, 19), (5, 9, 8))
    beams = Image.new("RGB", (W, H), (0, 0, 0))
    for x, ang in ((0.10, 14), (0.50, 0), (0.90, -14)):
        m = beam((W, H), (W * (x + seed_shift), -30), 30, ang, 900 * k, 22 * k, power=1.0)
        beams = screen(beams, tinted(m, accent, strength))
    base = screen(base, beams)
    pool = Image.new("L", (W, H), 0)
    ImageDraw.Draw(pool).ellipse((W * 0.10, H * 0.78, W * 0.90, H * 1.25), fill=255)
    base = screen(base, tinted(pool.filter(ImageFilter.GaussianBlur(45 * k)), accent, 0.13))
    return base


def finish_scene(base):
    base = vignette(base, 0.45)
    return base.resize(SCENE_SIZE, Image.LANCZOS)


def glow_behind(base, box, colour, strength=0.5, radius=50):
    m = Image.new("L", base.size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, 18, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(radius))
    return screen(base, tinted(m, colour, strength))


def screen_frame(base, shot, centre_x, height, colour, strength=0.5, radius=14):
    """A screenshot as a lit screen: glow, thin bezel, drop shadow."""
    k = 2
    shot = fit_height(shot, height)
    bezel = 6
    framed = Image.new("RGB", (shot.width + 2 * bezel, shot.height + 2 * bezel), (3, 5, 5))
    framed.paste(shot, (bezel, bezel))
    x = int(centre_x - framed.width / 2)
    y = (base.height - framed.height) // 2 - 6 * k
    base = glow_behind(base, (x, y, x + framed.width, y + framed.height), colour, strength, 38 * k)
    base = shadowed_paste(base, framed, (x, y), radius, shadow=0.75, blur=14 * k, offset=(0, 8 * k))
    d = ImageDraw.Draw(base)
    d.rounded_rectangle((x, y, x + framed.width - 1, y + framed.height - 1), radius, outline=(48, 64, 58), width=2)
    return base, (x, y, framed.width, framed.height)


def scene_countdown():
    base = stage_backdrop()
    k = 2
    shot = golden("countdown-current-wide.png")
    base, _ = screen_frame(base, shot, base.width / 2, 300 * k, ACCENT, 0.45)
    return finish_scene(base)


def scene_overtime():
    base = stage_backdrop(accent=RED, strength=0.12)
    k = 2
    shot = golden("countdown-overtime-strong-wide.png")
    base, _ = screen_frame(base, shot, base.width / 2, 300 * k, RED, 0.55)
    return finish_scene(base)


def scene_flip():
    base = stage_backdrop()
    k = 2
    shot = golden("flip-clock-wide-12h.png")
    base, _ = screen_frame(base, shot, base.width / 2, 300 * k, ACCENT, 0.40)
    return finish_scene(base)


def scene_slides():
    base = stage_backdrop(accent=(214, 190, 120), strength=0.10)
    k = 2
    song = golden("lyrics-slide-photo-northern-lights.png")
    verse = golden("lyrics-scripture.png")
    base, _ = screen_frame(base, song, base.width * 0.28, 214 * k, (120, 200, 150), 0.40)
    base, _ = screen_frame(base, verse, base.width * 0.72, 214 * k, (214, 190, 120), 0.45)
    return finish_scene(base)


def browser_chrome(shot, height, url):
    """A bare browser window around a web-screen screenshot. The address is a
    placeholder, not a real site."""
    shot = fit_height(shot, height)
    bar = 34
    win = Image.new("RGB", (shot.width, shot.height + bar), (32, 38, 36))
    d = ImageDraw.Draw(win)
    for i, c in enumerate(((229, 90, 80), (233, 190, 80), (110, 200, 110))):
        d.ellipse((12 + i * 18, 11, 24 + i * 18, 23), fill=c)
    d.rounded_rectangle((78, 6, win.width - 14, bar - 6), 9, fill=(14, 20, 18))
    d.text((92, bar // 2), url, font=font("Regular", 15), fill=MUTED, anchor="lm")
    win.paste(shot, (0, bar))
    return win


def phone_frame(shot, height):
    shot = fit_height(shot, height)
    bez = 9
    ph = Image.new("RGB", (shot.width + 2 * bez, shot.height + 2 * bez), (6, 8, 8))
    ph.paste(shot, (bez, bez))
    out = ph.convert("RGBA")
    out.putalpha(rounded_mask(ph.size, 26))
    return out


def scene_devices():
    base = stage_backdrop()
    k = 2
    web = browser_chrome(golden("paired-stage.png"), 206 * k, "your-church-screen.local")
    wx, wy = int(base.width * 0.31 - web.width / 2), (base.height - web.height) // 2
    base = glow_behind(base, (wx, wy, wx + web.width, wy + web.height), ACCENT, 0.35, 36 * k)
    base = shadowed_paste(base, web, (wx, wy), 12, 0.75, 14 * k, (0, 8 * k))
    phone = phone_frame(golden("countdown-warning-phone.png"), 276 * k)
    px, py = int(base.width * 0.70 - phone.width / 2), (base.height - phone.height) // 2
    base = glow_behind(base, (px, py, px + phone.width, py + phone.height), (244, 180, 90), 0.45, 34 * k)
    layer = base.convert("RGBA")
    shadow = Image.new("L", base.size, 0)
    shadow.paste(phone.getchannel("A"), (px, py + 8 * k))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * k)).point(lambda v: int(v * 0.7))
    layer = Image.composite(Image.new("RGBA", base.size, (0, 0, 0, 255)), layer, shadow)
    layer.alpha_composite(phone, (px, py))
    base = layer.convert("RGB")
    ImageDraw.Draw(base).rounded_rectangle((px, py, px + phone.width - 1, py + phone.height - 1), 26, outline=(52, 66, 60), width=2)
    return finish_scene(base)


def scene_finishes():
    base = stage_backdrop(accent=(210, 170, 110), strength=0.10)
    k = 2
    main = golden("desktop-three-panes-1366.png")
    base, box = screen_frame(base, main, base.width * 0.36, 266 * k, ACCENT, 0.30)
    names = ["live-brick-full-dark-1366.png", "live-denim-full-dark-1366.png", "live-leather-full-dark-1366.png"]
    th = 90 * k
    gx = int(base.width * 0.70)
    gy0 = (base.height - (3 * th + 2 * 12 * k)) // 2 - 4 * k
    for i, n in enumerate(names):
        t = fit_height(golden("finish/" + n), th)
        base = shadowed_paste(base, t, (gx, gy0 + i * (th + 12 * k)), 12, 0.75, 10 * k, (0, 6 * k))
    return finish_scene(base)


def save_png(img: Image.Image, path: Path, colours: int | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if colours:
        img = img.quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    img.save(path, "PNG", optimize=True)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()
    for w, h in TALL_SIZES:
        save_png(draw_tall(w, h, ready=False), OUT / f"welcome-{w}.png", 256)
        save_png(draw_tall(w, h, ready=True), OUT / f"ready-{w}.png", 256)
    for s in SMALL_SIZES:
        header_image(s).save(OUT / f"header-{s}.png", "PNG", optimize=True)
    scenes = [scene_countdown, scene_overtime, scene_flip, scene_slides, scene_devices, scene_finishes]
    for i, fn in enumerate(scenes, 1):
        save_png(fn(), OUT / f"scene-{i}.png", 256)
    total = 0
    for p in sorted(OUT.glob("*.png")):
        size = p.stat().st_size
        total += size
        print(f"{p.name:18s} {size / 1024:8.1f} KB")
    print(f"total {total / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
