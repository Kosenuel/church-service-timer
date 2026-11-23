"""Turns a seamless colour photo into the app's grey detail tile.

prep.py SRC OUT WIDTH [--hp FRACTION] [--gamma G] [--quality Q] [--rot]
The tile is luminance only, centred on 128: brighter than 128 lifts the
theme's base colour toward white, darker sinks it toward black, each side
scaled to the finish's budget at paint time. Lighting that varies across
the photo (a hotspot, a vignette) is removed with a wrap-around high pass,
so the tile repeats with no visible seam or bright patch.
"""
import sys, argparse
import numpy as np
from PIL import Image, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('out'); ap.add_argument('width', type=int)
ap.add_argument('--hp', type=float, default=.18, help='high-pass radius as a share of the width (0 = none)')
ap.add_argument('--clip', type=float, default=.5, help='percentile clipped at each end')
ap.add_argument('--soft', type=float, default=1.0, help='tanh softness of the extremes (0 = linear)')
ap.add_argument('--gamma', type=float, default=1.0)
ap.add_argument('--quality', type=int, default=88)
ap.add_argument('--rot', action='store_true', help='turn a quarter, so grain runs across')
ap.add_argument('--crop', type=float, default=1.0, help='keep this share of the photo (a seamless crop only at 1)')
ap.add_argument('--hblur', type=float, default=0, help='horizontal streak blur in px (brushed metal)')
a = ap.parse_args()

im = Image.open(a.src).convert('RGB')
if a.rot:
    im = im.transpose(Image.Transpose.ROTATE_90)
if a.crop < 1:
    w, h = im.size
    im = im.crop((0, 0, int(w * a.crop), int(h * a.crop)))
w, h = im.size
H = round(a.width * h / w)
im = im.resize((a.width, H), Image.Resampling.LANCZOS)
rgb = np.asarray(im).astype(np.float64) / 255
lum = (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]) ** (1 / max(a.gamma, .01))

def wrap_blur(x, radius, horizontal_only=False):
    """Gaussian blur that wraps round the edges (circular, by FFT), so the
    tile stays seamless."""
    hh, ww = x.shape
    fy = np.fft.fftfreq(hh)[:, None]
    fx = np.fft.fftfreq(ww)[None, :]
    sy = 0 if horizontal_only else radius
    g = np.exp(-2 * (np.pi ** 2) * ((fx * radius) ** 2 + (fy * sy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(x) * g))

if a.hblur > 0:
    lum = wrap_blur(lum, a.hblur, horizontal_only=True)
if a.hp > 0:
    lum = lum - wrap_blur(lum, a.width * a.hp)
else:
    lum = lum - lum.mean()
lum = lum - np.median(lum)
lo, hi = np.percentile(lum, a.clip), np.percentile(lum, 100 - a.clip)
pos = np.clip(lum / hi, 0, None) if hi > 0 else lum * 0
neg = np.clip(lum / -lo, None, 0) if lo < 0 else lum * 0
d = pos + neg
if a.soft > 0:
    d = np.tanh(d * a.soft * 1.3) / np.tanh(a.soft * 1.3)
d = np.clip(d, -1, 1)
out = np.clip(np.round(128 + d * 127), 0, 255).astype(np.uint8)
Image.fromarray(out, mode='L').save(a.out, quality=a.quality, optimize=True)
print(a.out, out.shape, 'mean', round(out.mean(), 1), 'std', round(out.std(), 1))
