"""Seamless tiles the libraries do not have (veined marble, paper, carbon
weave, frost), made from filtered noise, as grey detail tiles centred on 128."""
import sys
import numpy as np
from PIL import Image
rng = np.random.default_rng(7)

def noise(n, scale, seed, aniso=(1, 1)):
    """Seamless band-limited noise: white noise filtered in frequency."""
    r = np.random.default_rng(seed)
    w = r.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]; fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    f = np.sqrt(fx ** 2 + fy ** 2) * n
    g = np.exp(-(f / scale) ** 2)
    o = np.real(np.fft.ifft2(np.fft.fft2(w) * g))
    return o / o.std()

def fbm(n, base, octaves, seed, aniso=(1, 1)):
    o = 0; a = 1; t = 0
    for i in range(octaves):
        o = o + a * noise(n, base * 2 ** i, seed + i, aniso); t += a; a *= .5
    return o / t

def save(d, out, q=90):
    d = d - np.median(d)
    hi, lo = np.percentile(d, 99.7), np.percentile(d, .3)
    d = np.where(d > 0, d / hi, d / -lo)
    d = np.clip(d, -1, 1)
    Image.fromarray(np.round(128 + d * 127).astype(np.uint8), 'L').save(out, quality=q, optimize=True)

kind, out = sys.argv[1], sys.argv[2]
if kind == 'marble':
    n = 1024
    y, x = np.mgrid[0:n, 0:n] / n
    warp = fbm(n, 1, 3, 1) * .22 + fbm(n, 16, 3, 12) * .012
    t = (x * 3 + y * 1) + warp
    width = 40 + 50 * (fbm(n, 2, 2, 7) > .3)
    v = np.abs(np.sin(np.pi * t))
    veins = ((1 - v) ** width + .35 * (1 - v) ** 10) * (.55 + .45 * np.clip(fbm(n, 3, 3, 13), -1, 1))
    t2 = (x * 1 - y * 3) + fbm(n, 1, 3, 5) * .2
    v2 = (1 - np.abs(np.sin(np.pi * t2))) ** 120 * (fbm(n, 2, 2, 8) > 0)
    clouds = fbm(n, 2, 6, 21)
    d = clouds * .5 - veins * 1.5 - v2 * .7
    save(d, out)
elif kind == 'paper':
    from PIL import ImageDraw, ImageFilter
    n = 512
    tooth = noise(n, 230, 3) * .35 + fbm(n, 24, 3, 4) * .35 + fbm(n, 5, 2, 11) * .15
    im = Image.new('L', (n, n), 128); dr = ImageDraw.Draw(im)
    r = np.random.default_rng(5)
    for k in range(900):
        x0, y0 = r.uniform(0, n, 2); a = r.uniform(0, np.pi); L = r.uniform(6, 22); bend = r.uniform(-3, 3)
        val = int(128 + r.choice([-1, 1]) * r.uniform(20, 60))
        pts = []
        for s_ in np.linspace(0, 1, 6):
            px = x0 + np.cos(a) * L * s_ - np.sin(a) * bend * np.sin(np.pi * s_)
            py = y0 + np.sin(a) * L * s_ + np.cos(a) * bend * np.sin(np.pi * s_)
            pts.append((px, py))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                dr.line([(p_[0] + ox, p_[1] + oy) for p_ in pts], fill=val, width=1)
    im = im.filter(ImageFilter.GaussianBlur(.6))
    fib = (np.asarray(im).astype(float) - 128) / 40
    save(tooth + fib * .22, out)
elif kind == 'carbon':
    # A 2 x 2 twill of flat tows, each lit across its width with a soft
    # anisotropic sheen, in a 512 tile of 16 x 16 cells.
    n = 512; cells = 16; c = n // cells
    y, x = np.mgrid[0:n, 0:n]
    i, j = x // c, y // c
    u, v = (x % c) / c, (y % c) / c
    warp = ((i - j) % 4) < 2
    across = np.where(warp, u, v)           # position across the tow
    along = np.where(warp, v, u)
    tow = np.sin(np.pi * across) ** .6       # rounded tow
    sheen = np.where(warp, .55, -.35)       # warp and weft catch light differently
    fil = noise(n, 160, 3, aniso=(1, 8)) * .08
    fil2 = noise(n, 160, 4, aniso=(8, 1)) * .08
    gap = -(1 - np.sin(np.pi * across) ** .15) * 1.2
    d = tow * .6 + sheen + np.where(warp, fil, fil2) + gap + (along - .5) * np.where(warp, .2, -.2)
    save(d, out)
elif kind == 'frost':
    n = 256
    save(noise(n, 140, 8) * .8 + noise(n, 60, 9) * .35, out)
