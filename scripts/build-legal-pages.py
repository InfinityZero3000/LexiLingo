#!/usr/bin/env python3
"""Write the public legal pages (privacy, terms, data deletion) into flutter-app/web.

Meta, Google and app stores need a public URL for each, and the web app is a single-page app: any path
returns the app shell, and a crawler runs no JavaScript. So these are static files, served ahead of the
SPA rewrite.

The policy and terms text is not written here. It is read from the same strings the in-app pages show
(`legal.*` in assets/i18n), so the two cannot drift. Only the data-deletion page is authored here.

    python3 scripts/build-legal-pages.py            # write the files
    python3 scripts/build-legal-pages.py --check    # exit 1 if they are out of date
"""

from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
I18N = ROOT / "flutter-app" / "assets" / "i18n"
OUT = ROOT / "flutter-app" / "web"
SITE = "https://lexilingo.me"

# Shown beside "Last updated", matching what the in-app pages print.
UPDATED = {
    "en": {"privacy": "November 2026", "terms": "June 2025", "deletion": "November 2026"},
    "vi": {"privacy": "Tháng 11, 2026", "terms": "Tháng 6, 2025", "deletion": "Tháng 11, 2026"},
}

PAGES = {
    "privacy": ("privacy.html", "privacy_title", 7, "privacy"),
    "terms": ("terms.html", "terms_title", 8, "terms"),
}
NAV = (
    ("privacy.html", {"en": "Privacy Policy", "vi": "Chính sách quyền riêng tư"}),
    ("terms.html", {"en": "Terms of Service", "vi": "Điều khoản dịch vụ"}),
    ("data-deletion.html", {"en": "Delete your data", "vi": "Xoá dữ liệu của bạn"}),
)

CSS = """
:root{--bg:#fff;--fg:#1c2433;--muted:#5b6475;--line:#e3e7ee;--brand:#1d5fd1;--card:#f6f8fb}
@media (prefers-color-scheme:dark){:root{--bg:#0f1520;--fg:#e8ecf3;--muted:#a3adbf;--line:#273041;--brand:#7fb0ff;--card:#161e2c}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header,main,footer{max-width:720px;margin:0 auto;padding:0 20px}
header{padding-top:24px;padding-bottom:16px;border-bottom:1px solid var(--line)}
.brand{font-weight:700;font-size:20px;color:var(--fg);text-decoration:none}
nav{display:flex;flex-wrap:wrap;gap:8px 20px;margin-top:8px;font-size:14px}
a{color:var(--brand)}
h1{font-size:28px;line-height:1.25;margin:32px 0 4px}
h2{font-size:18px;margin:28px 0 4px}
p{margin:4px 0 8px}
.meta{color:var(--muted);font-size:14px;margin:0 0 16px}
.lang{display:flex;gap:16px;margin:16px 0 0;font-size:14px}
section.doc{padding-bottom:16px}
section.doc+section.doc{border-top:1px solid var(--line);margin-top:24px;padding-top:8px}
ol{padding-left:22px}li{margin:6px 0}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 16px;margin:12px 0}
footer{padding-top:24px;padding-bottom:40px;color:var(--muted);font-size:14px;border-top:1px solid var(--line);margin-top:32px}
"""


def load(lang: str) -> dict:
    return json.loads((I18N / f"{lang}.json").read_text(encoding="utf-8"))


def esc(text: str) -> str:
    """Escape, then turn email addresses into links."""
    safe = html.escape(text, quote=False)
    return re.sub(r"([\w.+-]+@[\w-]+\.[\w.-]+\w)", r'<a href="mailto:\1">\1</a>', safe)


def contact_email(en: dict) -> str:
    found = re.search(r"[\w.+-]+@[\w-]+\.[\w.-]+\w", en["legal"]["privacy7Body"])
    if not found:
        raise SystemExit("privacy7Body no longer names a contact email")
    return found.group(0)


def policy_section(lang: str, strings: dict, kind: str, count: int, key: str) -> str:
    legal = strings["legal"]
    updated = legal["last_updated"].replace("{date}", UPDATED[lang][kind])
    parts = [
        f'<section class="doc" id="{lang}" lang="{lang}">',
        f"<h1>{esc(legal[f'{key}_title' if key == 'terms' else 'privacy_title'])}</h1>",
        f'<p class="meta">{esc(updated)}</p>',
    ]
    for n in range(1, count + 1):
        parts.append(f"<h2>{esc(legal[f'{key}{n}Title'])}</h2>")
        parts.append(f"<p>{esc(legal[f'{key}{n}Body'])}</p>")
    parts.append("</section>")
    return "\n".join(parts)


def deletion_section(lang: str, strings: dict, email: str) -> str:
    settings = strings["settings"]
    path = f"{settings['title']} → {settings['account']} → {settings['delete_account']}"
    updated = strings["legal"]["last_updated"].replace("{date}", UPDATED[lang]["deletion"])
    if lang == "en":
        body = f"""<h1>Delete your LexiLingo data</h1>
<p class="meta">{esc(updated)}</p>
<p>You can delete your LexiLingo account and its data yourself, or ask us to do it.</p>
<h2>Option 1: in the app (fastest)</h2>
<ol>
<li>Open LexiLingo and sign in.</li>
<li>Go to <strong>{esc(path)}</strong>.</li>
<li>Confirm. This cannot be undone.</li>
</ol>
<p>Your account and the learning data linked to it (profile, progress, vocabulary, achievements, wallet, devices and sessions) are removed from our main database immediately.</p>
<h2>Option 2: by email</h2>
<p>If you cannot open the app, email <a href="mailto:{email}">{email}</a> from the address on your account, with the subject “Delete my LexiLingo data”. We verify the request and reply within 30 days.</p>
<h2>What else we hold</h2>
<p>Your conversations with Lexi and the notes Lexi keeps about you are stored in a separate service. Conversation transcripts expire automatically after up to 90 days. To have them, and the sign-in record kept by Firebase Authentication, removed sooner, use option 2 and say so.</p>
<h2>If you signed in with Facebook</h2>
<p>We receive your name, email address and profile picture from Meta when you sign in. Our servers never receive or store your Facebook access token. After deleting your account you can also remove LexiLingo from Facebook: <em>Settings &amp; privacy → Settings → Apps and websites → LexiLingo → Remove</em>.</p>"""
    else:
        body = f"""<h1>Xoá dữ liệu LexiLingo của bạn</h1>
<p class="meta">{esc(updated)}</p>
<p>Bạn có thể tự xoá tài khoản LexiLingo và dữ liệu của mình, hoặc nhờ chúng tôi xoá.</p>
<h2>Cách 1: trong ứng dụng (nhanh nhất)</h2>
<ol>
<li>Mở LexiLingo và đăng nhập.</li>
<li>Vào <strong>{esc(path)}</strong>.</li>
<li>Xác nhận. Thao tác này không thể hoàn tác.</li>
</ol>
<p>Tài khoản và dữ liệu học tập gắn với nó (hồ sơ, tiến độ, từ vựng, thành tích, ví, thiết bị và phiên đăng nhập) được xoá khỏi cơ sở dữ liệu chính của chúng tôi ngay lập tức.</p>
<h2>Cách 2: qua email</h2>
<p>Nếu không mở được ứng dụng, hãy gửi email tới <a href="mailto:{email}">{email}</a> từ địa chỉ gắn với tài khoản, tiêu đề “Xoá dữ liệu LexiLingo của tôi”. Chúng tôi xác minh yêu cầu và phản hồi trong vòng 30 ngày.</p>
<h2>Những dữ liệu khác chúng tôi lưu</h2>
<p>Các cuộc trò chuyện với Lexi và ghi chú Lexi lưu về bạn nằm ở một dịch vụ riêng. Nội dung hội thoại tự hết hạn sau tối đa 90 ngày. Muốn xoá chúng, cùng bản ghi đăng nhập do Firebase Authentication giữ, sớm hơn, hãy dùng cách 2 và nói rõ.</p>
<h2>Nếu bạn đăng nhập bằng Facebook</h2>
<p>Chúng tôi nhận tên, địa chỉ email và ảnh đại diện của bạn từ Meta khi bạn đăng nhập. Máy chủ của chúng tôi không nhận và không lưu mã truy cập Facebook của bạn. Sau khi xoá tài khoản, bạn cũng có thể gỡ LexiLingo khỏi Facebook: <em>Cài đặt và quyền riêng tư → Cài đặt → Ứng dụng và trang web → LexiLingo → Gỡ</em>.</p>"""
    return f'<section class="doc" id="{lang}" lang="{lang}">\n{body}\n</section>'


def page(filename: str, title: str, description: str, sections: list[str]) -> str:
    nav = " ".join(
        f'<a href="/{href}">{labels["en"]} / {labels["vi"]}</a>' for href, labels in NAV
    )
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<meta name="robots" content="index, follow">
<link rel="canonical" href="{SITE}/{filename}">
<style>{CSS}</style>
</head>
<body>
<header>
<a class="brand" href="{SITE}/">LexiLingo</a>
<nav>{nav}</nav>
<div class="lang"><a href="#en">English</a><a href="#vi">Tiếng Việt</a></div>
</header>
<main>
{chr(10).join(sections)}
</main>
<footer>© LexiLingo · <a href="{SITE}/">lexilingo.me</a></footer>
</body>
</html>
"""


def build() -> dict[str, str]:
    en, vi = load("en"), load("vi")
    email = contact_email(en)
    out: dict[str, str] = {}
    for kind, (filename, _, count, key) in PAGES.items():
        title = f"{en['legal'][f'{key}_title']} · LexiLingo"
        out[filename] = page(
            filename,
            title,
            f"{en['legal'][f'{key}_title']} of LexiLingo, the English learning app.",
            [policy_section("en", en, kind, count, key), policy_section("vi", vi, kind, count, key)],
        )
    out["data-deletion.html"] = page(
        "data-deletion.html",
        "Delete your LexiLingo data · LexiLingo",
        "How to delete your LexiLingo account and data.",
        [deletion_section("en", en, email), deletion_section("vi", vi, email)],
    )
    return out


def main() -> int:
    pages = build()
    stale = [name for name, text in pages.items() if not (OUT / name).exists() or (OUT / name).read_text(encoding="utf-8") != text]
    if "--check" in sys.argv:
        if stale:
            print("Out of date, run scripts/build-legal-pages.py:", ", ".join(stale))
            return 1
        print("Legal pages are up to date.")
        return 0
    for name, text in pages.items():
        (OUT / name).write_text(text, encoding="utf-8")
        print("wrote", (OUT / name).relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
