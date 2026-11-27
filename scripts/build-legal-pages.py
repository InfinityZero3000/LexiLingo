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

# Language code -> name shown in the switcher. English first: it is what a reviewer reads.
LANGS = {
    "en": "English",
    "vi": "Tiếng Việt",
    "es": "Español",
    "fr": "Français",
    "ja": "日本語",
    "ko": "한국어",
    "zh": "中文",
}

# Shown beside "Last updated", matching what the in-app pages print.
UPDATED = {
    "en": {"privacy": "November 2026", "terms": "June 2025", "deletion": "November 2026"},
    "vi": {"privacy": "Tháng 11, 2026", "terms": "Tháng 6, 2025", "deletion": "Tháng 11, 2026"},
    "es": {"privacy": "noviembre de 2026", "terms": "junio de 2025", "deletion": "noviembre de 2026"},
    "fr": {"privacy": "novembre 2026", "terms": "juin 2025", "deletion": "novembre 2026"},
    "ja": {"privacy": "2026年11月", "terms": "2025年6月", "deletion": "2026年11月"},
    "ko": {"privacy": "2026년 11월", "terms": "2025년 6월", "deletion": "2026년 11월"},
    "zh": {"privacy": "2026年11月", "terms": "2025年6月", "deletion": "2026年11月"},
}

PAGES = {
    "privacy": ("privacy.html", "privacy_title", 7, "privacy"),
    "terms": ("terms.html", "terms_title", 8, "terms"),
}
NAV = (
    ("privacy.html", "Privacy Policy"),
    ("terms.html", "Terms of Service"),
    ("data-deletion.html", "Delete your data"),
)

# The data-deletion page, authored here. {path} and {email} are filled in.
DELETION = {
    "en": {
        "title": "Delete your LexiLingo data",
        "intro": "You can delete your LexiLingo account and its data yourself, or ask us to do it.",
        "app_h": "Option 1: in the app (fastest)",
        "open": "Open LexiLingo and sign in.",
        "go": "Go to <strong>{path}</strong>.",
        "confirm": "Confirm. This cannot be undone.",
        "removed": "Your account and the learning data linked to it (profile, progress, vocabulary, achievements, wallet, devices and sessions) are removed from our main database immediately.",
        "mail_h": "Option 2: by email",
        "mail": "If you cannot open the app, email {email} from the address on your account, with the subject “Delete my LexiLingo data”. We verify the request and reply within 30 days.",
        "other_h": "What else we hold",
        "other": "Your conversations with Lexi and the notes Lexi keeps about you are stored in a separate service. Conversation transcripts expire automatically after up to 90 days. To have them, and the sign-in record kept by Firebase Authentication, removed sooner, use option 2 and say so.",
        "fb_h": "If you signed in with Facebook",
        "fb": "We receive your name, email address and profile picture from Meta when you sign in. Our servers never receive or store your Facebook access token. After deleting your account you can also remove LexiLingo from Facebook: <em>Settings &amp; privacy → Settings → Apps and websites → LexiLingo → Remove</em>.",
    },
    "vi": {
        "title": "Xoá dữ liệu LexiLingo của bạn",
        "intro": "Bạn có thể tự xoá tài khoản LexiLingo và dữ liệu của mình, hoặc nhờ chúng tôi xoá.",
        "app_h": "Cách 1: trong ứng dụng (nhanh nhất)",
        "open": "Mở LexiLingo và đăng nhập.",
        "go": "Vào <strong>{path}</strong>.",
        "confirm": "Xác nhận. Thao tác này không thể hoàn tác.",
        "removed": "Tài khoản và dữ liệu học tập gắn với nó (hồ sơ, tiến độ, từ vựng, thành tích, ví, thiết bị và phiên đăng nhập) được xoá khỏi cơ sở dữ liệu chính của chúng tôi ngay lập tức.",
        "mail_h": "Cách 2: qua email",
        "mail": "Nếu không mở được ứng dụng, hãy gửi email tới {email} từ địa chỉ gắn với tài khoản, tiêu đề “Xoá dữ liệu LexiLingo của tôi”. Chúng tôi xác minh yêu cầu và phản hồi trong vòng 30 ngày.",
        "other_h": "Những dữ liệu khác chúng tôi lưu",
        "other": "Các cuộc trò chuyện với Lexi và ghi chú Lexi lưu về bạn nằm ở một dịch vụ riêng. Nội dung hội thoại tự hết hạn sau tối đa 90 ngày. Muốn xoá chúng, cùng bản ghi đăng nhập do Firebase Authentication giữ, sớm hơn, hãy dùng cách 2 và nói rõ.",
        "fb_h": "Nếu bạn đăng nhập bằng Facebook",
        "fb": "Chúng tôi nhận tên, địa chỉ email và ảnh đại diện của bạn từ Meta khi bạn đăng nhập. Máy chủ của chúng tôi không nhận và không lưu mã truy cập Facebook của bạn. Sau khi xoá tài khoản, bạn cũng có thể gỡ LexiLingo khỏi Facebook: <em>Cài đặt và quyền riêng tư → Cài đặt → Ứng dụng và trang web → LexiLingo → Gỡ</em>.",
    },
    "es": {
        "title": "Elimina tus datos de LexiLingo",
        "intro": "Puedes eliminar tu cuenta de LexiLingo y sus datos tú mismo, o pedirnos que lo hagamos.",
        "app_h": "Opción 1: en la aplicación (la más rápida)",
        "open": "Abre LexiLingo e inicia sesión.",
        "go": "Ve a <strong>{path}</strong>.",
        "confirm": "Confirma. Esta acción no se puede deshacer.",
        "removed": "Tu cuenta y los datos de aprendizaje vinculados a ella (perfil, progreso, vocabulario, logros, monedero, dispositivos y sesiones) se eliminan de inmediato de nuestra base de datos principal.",
        "mail_h": "Opción 2: por correo electrónico",
        "mail": "Si no puedes abrir la aplicación, escribe a {email} desde la dirección de tu cuenta, con el asunto «Eliminar mis datos de LexiLingo». Verificamos la solicitud y respondemos en un plazo de 30 días.",
        "other_h": "Qué más conservamos",
        "other": "Tus conversaciones con Lexi y las notas que Lexi guarda sobre ti se almacenan en un servicio aparte. Las transcripciones caducan automáticamente tras un máximo de 90 días. Para eliminarlas antes, junto con el registro de inicio de sesión que conserva Firebase Authentication, usa la opción 2 e indícalo.",
        "fb_h": "Si iniciaste sesión con Facebook",
        "fb": "Cuando inicias sesión, recibimos de Meta tu nombre, correo electrónico y foto de perfil. Nuestros servidores nunca reciben ni almacenan tu token de acceso de Facebook. Después de eliminar tu cuenta, también puedes quitar LexiLingo de Facebook: <em>Configuración y privacidad → Configuración → Apps y sitios web → LexiLingo → Eliminar</em>.",
    },
    "fr": {
        "title": "Supprimer vos données LexiLingo",
        "intro": "Vous pouvez supprimer vous-même votre compte LexiLingo et ses données, ou nous demander de le faire.",
        "app_h": "Option 1 : dans l'application (la plus rapide)",
        "open": "Ouvrez LexiLingo et connectez-vous.",
        "go": "Accédez à <strong>{path}</strong>.",
        "confirm": "Confirmez. Cette action est irréversible.",
        "removed": "Votre compte et les données d'apprentissage qui y sont liées (profil, progression, vocabulaire, succès, portefeuille, appareils et sessions) sont immédiatement supprimés de notre base de données principale.",
        "mail_h": "Option 2 : par e-mail",
        "mail": "Si vous ne pouvez pas ouvrir l'application, écrivez à {email} depuis l'adresse de votre compte, avec l'objet « Supprimer mes données LexiLingo ». Nous vérifions la demande et répondons sous 30 jours.",
        "other_h": "Les autres données que nous conservons",
        "other": "Vos conversations avec Lexi et les notes que Lexi conserve à votre sujet sont stockées dans un service distinct. Les transcriptions expirent automatiquement après 90 jours au maximum. Pour les faire supprimer plus tôt, ainsi que l'enregistrement de connexion conservé par Firebase Authentication, utilisez l'option 2 et précisez-le.",
        "fb_h": "Si vous vous êtes connecté avec Facebook",
        "fb": "Lorsque vous vous connectez, nous recevons de Meta votre nom, votre adresse e-mail et votre photo de profil. Nos serveurs ne reçoivent ni ne conservent jamais votre jeton d'accès Facebook. Après avoir supprimé votre compte, vous pouvez aussi retirer LexiLingo de Facebook : <em>Paramètres et confidentialité → Paramètres → Applications et sites web → LexiLingo → Retirer</em>.",
    },
    "ja": {
        "title": "LexiLingo のデータを削除する",
        "intro": "LexiLingo のアカウントとデータは、ご自身で削除することも、当社に削除を依頼することもできます。",
        "app_h": "方法1：アプリ内で削除（最も早い方法）",
        "open": "LexiLingo を開いてログインします。",
        "go": "<strong>{path}</strong> に進みます。",
        "confirm": "確認して実行します。この操作は取り消せません。",
        "removed": "アカウントと、それに紐づく学習データ（プロフィール、進捗、単語、実績、ウォレット、端末、セッション）は、当社のメインデータベースから直ちに削除されます。",
        "mail_h": "方法2：メールで依頼",
        "mail": "アプリを開けない場合は、アカウントに登録されたアドレスから、件名を「LexiLingo のデータ削除」として {email} までメールを送ってください。依頼を確認のうえ、30日以内に返信します。",
        "other_h": "その他に保持しているデータ",
        "other": "Lexi との会話や、Lexi がお客様について保存するメモは、別のサービスに保管されています。会話の記録は最長90日で自動的に失効します。これらと Firebase Authentication が保持するログイン記録を早めに削除したい場合は、方法2でその旨をお知らせください。",
        "fb_h": "Facebook でログインした場合",
        "fb": "ログイン時に、お名前、メールアドレス、プロフィール写真を Meta から受け取ります。当社のサーバーが Facebook のアクセストークンを受け取ったり保存したりすることはありません。アカウント削除後、Facebook 側からも LexiLingo を削除できます：<em>設定とプライバシー → 設定 → アプリとウェブサイト → LexiLingo → 削除</em>。",
    },
    "ko": {
        "title": "LexiLingo 데이터 삭제",
        "intro": "LexiLingo 계정과 데이터는 직접 삭제하거나 당사에 삭제를 요청할 수 있습니다.",
        "app_h": "방법 1: 앱에서 삭제 (가장 빠름)",
        "open": "LexiLingo를 열고 로그인합니다.",
        "go": "<strong>{path}</strong>(으)로 이동합니다.",
        "confirm": "확인합니다. 이 작업은 되돌릴 수 없습니다.",
        "removed": "계정과 연결된 학습 데이터(프로필, 진행 상황, 어휘, 업적, 지갑, 기기 및 세션)는 당사의 기본 데이터베이스에서 즉시 삭제됩니다.",
        "mail_h": "방법 2: 이메일로 요청",
        "mail": "앱을 열 수 없는 경우, 계정에 등록된 주소에서 제목을 “LexiLingo 데이터 삭제”로 하여 {email}(으)로 이메일을 보내 주세요. 요청을 확인한 뒤 30일 이내에 답변드립니다.",
        "other_h": "그 밖에 보관하는 데이터",
        "other": "Lexi와의 대화와 Lexi가 사용자에 대해 보관하는 메모는 별도의 서비스에 저장됩니다. 대화 기록은 최대 90일 후 자동으로 만료됩니다. 이 데이터와 Firebase Authentication이 보관하는 로그인 기록을 더 빨리 삭제하려면 방법 2를 이용해 그 내용을 알려 주세요.",
        "fb_h": "Facebook으로 로그인한 경우",
        "fb": "로그인할 때 Meta로부터 이름, 이메일 주소, 프로필 사진을 받습니다. 당사 서버는 Facebook 액세스 토큰을 받거나 저장하지 않습니다. 계정을 삭제한 후 Facebook에서도 LexiLingo를 제거할 수 있습니다: <em>설정 및 개인정보 → 설정 → 앱 및 웹사이트 → LexiLingo → 삭제</em>.",
    },
    "zh": {
        "title": "删除你的 LexiLingo 数据",
        "intro": "你可以自行删除 LexiLingo 账户及其数据，也可以请我们代为删除。",
        "app_h": "方式一：在应用内删除（最快）",
        "open": "打开 LexiLingo 并登录。",
        "go": "进入 <strong>{path}</strong>。",
        "confirm": "确认删除。此操作无法撤销。",
        "removed": "你的账户及其关联的学习数据（个人资料、学习进度、词汇、成就、钱包、设备和登录会话）会立即从我们的主数据库中删除。",
        "mail_h": "方式二：通过电子邮件",
        "mail": "如果无法打开应用，请使用账户绑定的邮箱发送邮件至 {email}，主题写“删除我的 LexiLingo 数据”。我们会核实请求，并在 30 天内回复。",
        "other_h": "我们保存的其他数据",
        "other": "你与 Lexi 的对话，以及 Lexi 保存的关于你的笔记，存放在一个单独的服务中。对话记录最长在 90 天后自动过期。如需更早删除这些数据以及 Firebase Authentication 保存的登录记录，请使用方式二并说明。",
        "fb_h": "如果你使用 Facebook 登录",
        "fb": "当你登录时，我们会从 Meta 获取你的姓名、电子邮件地址和头像。我们的服务器绝不会接收或保存你的 Facebook 访问令牌。删除账户后，你还可以在 Facebook 中移除 LexiLingo：<em>设置与隐私 → 设置 → 应用和网站 → LexiLingo → 移除</em>。",
    },
}

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
.lang{display:flex;flex-wrap:wrap;gap:8px 16px;margin:16px 0 0;font-size:14px}
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
    link = f'<a href="mailto:{email}">{email}</a>'
    t = {k: v.replace("{path}", esc(path)).replace("{email}", link) for k, v in DELETION[lang].items()}
    return f"""<section class="doc" id="{lang}" lang="{lang}">
<h1>{t['title']}</h1>
<p class="meta">{esc(updated)}</p>
<p>{t['intro']}</p>
<h2>{t['app_h']}</h2>
<ol>
<li>{t['open']}</li>
<li>{t['go']}</li>
<li>{t['confirm']}</li>
</ol>
<p>{t['removed']}</p>
<h2>{t['mail_h']}</h2>
<p>{t['mail']}</p>
<h2>{t['other_h']}</h2>
<p>{t['other']}</p>
<h2>{t['fb_h']}</h2>
<p>{t['fb']}</p>
</section>"""


def page(filename: str, title: str, description: str, sections: list[str]) -> str:
    nav = " ".join(f'<a href="/{href}">{label}</a>' for href, label in NAV)
    switcher = "".join(f'<a href="#{lang}" lang="{lang}">{name}</a>' for lang, name in LANGS.items())
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<meta name="robots" content="index, follow">
<link rel="canonical" href="{SITE}/{filename}">
<meta property="og:image" content="{SITE}/og-image.png">
<meta property="og:image:width" content="1774">
<meta property="og:image:height" content="887">
<style>{CSS}</style>
</head>
<body>
<header>
<a class="brand" href="{SITE}/">LexiLingo</a>
<nav>{nav}</nav>
<div class="lang">{switcher}</div>
</header>
<main>
{chr(10).join(sections)}
</main>
<footer>© LexiLingo · <a href="{SITE}/">lexilingo.me</a></footer>
</body>
</html>
"""


def build() -> dict[str, str]:
    strings = {lang: load(lang) for lang in LANGS}
    en = strings["en"]
    email = contact_email(en)
    out: dict[str, str] = {}
    for kind, (filename, _, count, key) in PAGES.items():
        title = f"{en['legal'][f'{key}_title']} · LexiLingo"
        out[filename] = page(
            filename,
            title,
            f"{en['legal'][f'{key}_title']} of LexiLingo, the English learning app.",
            [policy_section(lang, strings[lang], kind, count, key) for lang in LANGS],
        )
    out["data-deletion.html"] = page(
        "data-deletion.html",
        "Delete your LexiLingo data · LexiLingo",
        "How to delete your LexiLingo account and data.",
        [deletion_section(lang, strings[lang], email) for lang in LANGS],
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
