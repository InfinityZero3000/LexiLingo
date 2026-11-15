"""Build the email hero/footer JPEGs in app/templates/assets from the two source illustrations."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ASSETS = Path(__file__).resolve().parents[1] / "app" / "templates" / "assets"
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
PAGE_BG = (242, 247, 253)
HEROES = {
    "verification_email": "Confirm your email",
    "password_reset_email": "Choose a new password",
    "vocabulary_review_reminder": "Time to review",
    "admin_otp_email": "Your admin sign-in code",
    "welcome_email": "Welcome to LexiLingo",
    "password_changed_email": "Your password was changed",
    "weekly_summary_email": "Your week in LexiLingo",
    "streak_at_risk_email": "Keep your streak alive",
}
W, H = 1040, 360
TEXT_LEFT, TEXT_MAX = 64, 590  # the art starts at ~64% of the width


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> list[str]:
    lines: list[str] = []
    for word in text.split():
        trial = f"{lines[-1]} {word}" if lines else word
        if lines and draw.textlength(trial, font=font) <= TEXT_MAX:
            lines[-1] = trial
        else:
            lines.append(word)
    return lines


def build_hero(src: Image.Image, stem: str, title: str) -> None:
    img = src.resize((W, H), Image.LANCZOS).convert("RGB")
    draw = ImageDraw.Draw(img)
    label, big = ImageFont.truetype(FONT, 26), ImageFont.truetype(FONT, 60)
    lines = wrap(draw, title, big)
    block = 26 + 18 + len(lines) * 70
    y = (H - block) // 2
    draw.text((TEXT_LEFT, y), "LexiLingo", font=label, fill=(255, 255, 255))
    y += 26 + 18
    for line in lines:
        draw.text((TEXT_LEFT, y), line, font=big, fill=(255, 255, 255))
        y += 70
    img.save(ASSETS / f"hero_{stem}.jpg", quality=84, optimize=True, progressive=True)


def build_footer(src: Image.Image) -> None:
    w, h = src.size
    crop = src.convert("RGB").crop((0, int(h * 0.40), w, h)).resize((W, round(W * (h * 0.60) / w)), Image.LANCZOS)
    fade = int(crop.height * 0.45)
    for y in range(fade):
        t = y / fade
        for x in range(0, crop.width):
            r, g, b = crop.getpixel((x, y))
            crop.putpixel((x, y), tuple(round(p * t + q * (1 - t)) for p, q in zip((r, g, b), PAGE_BG, strict=True)))
    crop.save(ASSETS / "footer.jpg", quality=84, optimize=True, progressive=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--header-src", required=True, type=Path)
    parser.add_argument("--footer-src", required=True, type=Path)
    args = parser.parse_args()
    header = Image.open(args.header_src)
    for stem, title in HEROES.items():
        build_hero(header, stem, title)
    build_footer(Image.open(args.footer_src))


if __name__ == "__main__":
    main()
