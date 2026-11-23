#!/usr/bin/env python3
"""Draws mock-ups of the Windows installer's pages from its real assets.

    python3 tool/make_installer_preview.py <output folder>

These are PREVIEWS, not screenshots. Nobody has run the installer yet (it
needs Inno Setup on Windows). The mock-ups put the real pictures where Inno
Setup places them, in the real proportions, and use the words found in
windows/installer/church-service-timer.iss, but the window frame, fonts,
buttons and dark colours are an approximation of Inno Setup's "modern dark"
style, and how large the window is at a given Windows scale is a best
estimate. Treat the first test build on GitHub as the real proof.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ISS = (ROOT / "windows" / "installer" / "church-service-timer.iss").read_text(encoding="utf-8")
ART = ROOT / "windows" / "installer" / "art"
FONTS = ROOT / "assets" / "fonts"
VERSION = re.search(r"^version:\s*([0-9.]+)", (ROOT / "pubspec.yaml").read_text(), re.M).group(1)

# One design pixel of Inno Setup's wizard form (497 x 360) is S real pixels
# here; the picture area is 220 x 422 (the 100% size of the tall pictures).
S = 220 / 164
K = 2  # draw at twice the size for crisp text
WIN_BG = (32, 32, 32)
PANEL = (43, 43, 43)
TXT = (232, 232, 232)
DIM = (170, 170, 170)
LINE = (70, 70, 70)
BTN = (58, 58, 58)
ACCENT = (201, 249, 108)


def font(size_px, bold=False, light=False):
    name = "Bold" if bold else "Light" if light else "Regular"
    return ImageFont.truetype(str(FONTS / f"Roboto-{name}.ttf"), round(size_px * K))


def message(key: str) -> str:
    m = re.search(rf"^{key}=(.*)$", ISS, re.M)
    text = m.group(1) if m else key
    text = text.replace("[name/ver]", f"Church Service Timer version {VERSION}")
    text = text.replace("[name]", "Church Service Timer").replace("[ver]", VERSION)
    return text.replace("%n", "\n")


def captions() -> list[str]:
    return re.findall(r"^\s+\d: Result := '([^']*)';", ISS, re.M)


def wrap(draw, text, fnt, width):
    lines = []
    for para in text.split("\n"):
        if not para:
            lines.append("")
            continue
        cur = ""
        for word in para.split(" "):
            trial = (cur + " " + word).strip()
            if draw.textlength(trial, font=fnt) <= width:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines


def text_block(draw, x, y, text, fnt, width, fill=TXT, gap=1.45):
    for line in wrap(draw, text, fnt, width):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size * gap
    return y


class Page:
    CW, CH = round(497 * S), round(360 * S)  # client area
    TITLE = 34

    def __init__(self):
        self.w, self.h = self.CW * K, (self.CH + self.TITLE) * K
        self.img = Image.new("RGB", (self.w, self.h), WIN_BG)
        self.d = ImageDraw.Draw(self.img)
        self.oy = self.TITLE * K  # client area starts below the title bar
        self.title_bar()

    def title_bar(self):
        d = self.d
        d.rectangle((0, 0, self.w, self.TITLE * K), fill=(24, 24, 24))
        d.text((14 * K, self.TITLE * K / 2), "Set up Church Service Timer", font=font(12), fill=TXT, anchor="lm")
        for i, g in enumerate(("-", "x")):
            d.text((self.w - (30 + i * 0) * K - (1 - i) * 46 * K, self.TITLE * K / 2), g, font=font(14), fill=DIM, anchor="mm")

    def X(self, v):
        return round(v * S * K)

    def Y(self, v):
        return self.oy + round(v * S * K)

    def bottom_bar(self, buttons, bevel=True):
        d = self.d
        top = self.Y(314)
        d.rectangle((0, top, self.w, self.h), fill=WIN_BG)
        if bevel:
            d.line((0, top, self.w, top), fill=LINE, width=K)
        x = self.w - self.X(16)
        for label, primary in reversed(buttons):
            fnt = font(12)
            bw = max(round(d.textlength(label, font=fnt)) + 36 * K, 80 * K)
            bh = 28 * K
            by = top + 14 * K
            d.rounded_rectangle((x - bw, by, x, by + bh), 4 * K, fill=BTN, outline=(ACCENT if primary else LINE), width=K)
            d.text((x - bw / 2, by + bh / 2), label, font=fnt, fill=TXT, anchor="mm")
            x -= bw + 10 * K

    def picture(self, path, box):
        im = Image.open(path).convert("RGB").resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
        self.img.paste(im, box[:2])

    def header(self, title, sub):
        d = self.d
        top, bot = self.Y(0), self.Y(58)
        d.rectangle((0, top, self.w, bot), fill=PANEL)
        d.line((0, bot, self.w, bot), fill=LINE, width=K)
        d.text((self.X(16), top + 14 * K), title, font=font(13, bold=True), fill=TXT)
        d.text((self.X(24), top + 38 * K), sub, font=font(11), fill=DIM)
        side = bot - top
        icon = Image.open(ART / "header-128.png").convert("RGBA").resize((side - 16 * K, side - 16 * K), Image.LANCZOS)
        self.img.paste(icon, (self.w - side + 8 * K, top + 8 * K), icon)

    def finish(self, path):
        self.img.save(path)
        return self.img


def welcome_page():
    p = Page()
    p.picture(ART / "welcome-220.png", (0, p.Y(0), p.X(164), p.Y(314)))
    x = p.X(176)
    wide = p.X(301)
    text_block(p.d, x, p.Y(16), message("WelcomeLabel1"), font(19), wide, gap=1.3)
    text_block(p.d, x, p.Y(76), message("WelcomeLabel2"), font(12), wide)
    p.bottom_bar([("Next >", True), ("Cancel", False)])
    return p


def destination_page():
    p = Page()
    p.header("Select Destination Location", "Where should Church Service Timer be installed?")
    d = p.d
    x = p.X(40)
    y = p.Y(76)
    y = text_block(d, x, y, "Setup will install Church Service Timer into the following folder.", font(12), p.X(417))
    y += 8 * K
    text_block(d, x, y, "To continue, click Next. If you would like to select a different folder, click Browse.", font(12), p.X(417))
    by = p.Y(150)
    d.rounded_rectangle((x, by, x + p.X(330), by + 28 * K), 3 * K, fill=(30, 30, 30), outline=LINE, width=K)
    d.text((x + 8 * K, by + 14 * K), r"C:\Users\You\AppData\Local\Programs\Church Service Timer", font=font(11), fill=TXT, anchor="lm")
    d.rounded_rectangle((x + p.X(340), by, x + p.X(417), by + 28 * K), 4 * K, fill=BTN, outline=LINE, width=K)
    d.text((x + p.X(378), by + 14 * K), "Browse...", font=font(12), fill=TXT, anchor="mm")
    d.text((x, p.Y(290)), "At least 120 MB of free disk space is required.", font=font(11), fill=DIM)
    p.bottom_bar([("< Back", False), ("Next >", True), ("Cancel", False)])
    return p


def tasks_page():
    p = Page()
    p.header("Select Additional Tasks", "Which additional tasks should be performed?")
    d = p.d
    x = p.X(40)
    y = text_block(d, x, p.Y(76), "Select the additional tasks you would like Setup to perform while installing Church Service Timer, then click Next.", font(12), p.X(417))
    d.text((x, y + 10 * K), "Additional shortcuts:", font=font(12, bold=True), fill=TXT)
    cy = y + 40 * K
    d.rounded_rectangle((x, cy, x + 16 * K, cy + 16 * K), 3 * K, fill=(30, 30, 30), outline=DIM, width=K)
    d.text((x + 28 * K, cy + 8 * K), "Create a desktop shortcut", font=font(12), fill=TXT, anchor="lm")
    p.bottom_bar([("< Back", False), ("Next >", True), ("Cancel", False)])
    return p


def ready_page():
    p = Page()
    p.header("Ready to Install", "Setup is now ready to begin installing Church Service Timer on your computer.")
    d = p.d
    x = p.X(40)
    y = text_block(d, x, p.Y(76), "Click Install to continue with the installation, or click Back if you want to review or change any settings.", font(12), p.X(417))
    box = (x, y + 14 * K, x + p.X(417), p.Y(300))
    d.rectangle(box, fill=(30, 30, 30), outline=LINE, width=K)
    text_block(d, x + 10 * K, y + 24 * K, "Destination location:\n      C:\\Users\\You\\AppData\\Local\\Programs\\Church Service Timer", font(11), p.X(400))
    p.bottom_bar([("< Back", False), ("Install", True), ("Cancel", False)])
    return p


def installing_page(scene: int, progress: float, caps):
    p = Page()
    p.header("Installing", "Please wait while Setup installs Church Service Timer on your computer.")
    d = p.d
    x = p.X(40)
    w = p.X(417)
    img_h = round(w * 140 / 417)
    p.picture(ART / f"scene-{scene}.png", (x, p.Y(72), x + w, p.Y(72) + img_h))
    cap_y = p.Y(72) + round(img_h * 146 / 140)
    d.text((x, cap_y), caps[scene - 1], font=font(12), fill=TXT)
    d.text((x, p.Y(72) + round(img_h * 170 / 140)), "Extracting files...", font=font(12), fill=TXT)
    d.text((x, p.Y(72) + round(img_h * 186 / 140)), r"C:\Users\You\AppData\Local\Programs\Church Service Timer\data\flutter_assets\...", font=font(11), fill=DIM)
    gy = p.Y(72) + round(img_h * 208 / 140)
    d.rounded_rectangle((x, gy, x + w, gy + 14 * K), 3 * K, fill=(30, 30, 30), outline=LINE, width=K)
    d.rounded_rectangle((x, gy, x + round(w * progress), gy + 14 * K), 3 * K, fill=(0, 120, 212))
    p.bottom_bar([("Cancel", False)], bevel=True)
    return p


def finished_page():
    p = Page()
    p.picture(ART / "ready-220.png", (0, p.Y(0), p.X(164), p.Y(314)))
    x = p.X(176)
    wide = p.X(301)
    text_block(p.d, x, p.Y(16), message("FinishedHeadingLabel"), font(19), wide, gap=1.3)
    y = text_block(p.d, x, p.Y(76), message("FinishedLabel"), font(12), wide)
    cy = y + 24 * K
    p.d.rounded_rectangle((x, cy, x + 16 * K, cy + 16 * K), 3 * K, fill=(0, 120, 212), outline=(0, 120, 212), width=K)
    p.d.line((x + 3 * K, cy + 8 * K, x + 7 * K, cy + 12 * K, x + 13 * K, cy + 4 * K), fill=(255, 255, 255), width=2 * K)
    p.d.text((x + 28 * K, cy + 8 * K), "Launch Church Service Timer", font=font(12), fill=TXT, anchor="lm")
    p.bottom_bar([("Finish", True)])
    return p


def label(img: Image.Image, text: str) -> Image.Image:
    """Adds a strip under a mock-up saying what it is."""
    strip = 34 * K
    out = Image.new("RGB", (img.width, img.height + strip), (14, 14, 14))
    out.paste(img, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((12 * K, img.height + strip / 2), text + "   |   PREVIEW drawn from the installer's assets, not a screenshot", font=font(11), fill=(150, 150, 150), anchor="lm")
    return out


def main(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    caps = captions()
    pages = [
        ("01-welcome", "Welcome page", welcome_page()),
        ("02-destination", "Select Destination Location (inner page, header picture at the top right)", destination_page()),
        ("03-tasks", "Select Additional Tasks", tasks_page()),
        ("04-ready", "Ready to Install", ready_page()),
    ]
    marks = [0.08, 0.25, 0.42, 0.58, 0.75, 0.92]
    for i in range(6):
        pages.append((f"05-installing-{i + 1}", f"Installing, scene {i + 1} of 6", installing_page(i + 1, marks[i], caps)))
    pages.append(("06-finished", "Finished page", finished_page()))

    labelled = []
    for name, title, page in pages:
        img = label(page.finish(out_dir / f"{name}.png"), title)
        img.save(out_dir / f"{name}.png")
        labelled.append((title, img))

    # Contact sheet: three columns.
    cols = 3
    cell_w = 640
    thumbs = [im.resize((cell_w, round(im.height * cell_w / im.width)), Image.LANCZOS) for _, im in labelled]
    rows = (len(thumbs) + cols - 1) // cols
    row_h = max(t.height for t in thumbs) + 10
    sheet = Image.new("RGB", (cols * (cell_w + 10) + 10, rows * row_h + 56), (14, 14, 14))
    d = ImageDraw.Draw(sheet)
    d.text((14, 20), "Church Service Timer installer: PREVIEWS drawn from the installer's assets (not screenshots; window frame, fonts and dark colours approximate)", font=font(13), fill=(210, 210, 210), anchor="lm")
    for i, t in enumerate(thumbs):
        sheet.paste(t, (10 + (i % cols) * (cell_w + 10), 46 + (i // cols) * row_h))
    sheet.save(out_dir / "sheet.png")
    print(f"wrote {len(labelled)} previews and sheet.png to {out_dir}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    main(Path(sys.argv[1]))
