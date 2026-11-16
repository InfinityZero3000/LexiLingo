"""One-click unsubscribe for nurture mail; reached from a mail client, so no login and no cookies."""

import html

from fastapi import APIRouter, Depends, Query
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.models.user import User
from app.routes.reminders import _get_or_create_preferences
from app.services.email_unsubscribe import NURTURE, read_token

router = APIRouter(prefix="/email", tags=["Email"])

# The global policy is default-src 'self', which blocks the inline style this page needs.
_CSP = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'"

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>{title} - LexiLingo</title>
<style>
body{{margin:0;background:#F2F7FD;color:#111418;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6}}
main{{max-width:440px;margin:48px auto;padding:32px 24px;background:#fff;border:1px solid #E1EAF5;border-radius:16px}}
h1{{margin:0 0 12px;font-size:22px}}p{{margin:0 0 20px;color:#3D4A5C;font-size:16px}}
button,a.btn{{display:inline-block;min-height:48px;padding:0 32px;border:0;border-bottom:4px solid #0A4A9C;border-radius:14px;background:#0D5FC4;color:#fff;font-size:16px;font-weight:700;line-height:48px;text-decoration:none;cursor:pointer}}
button:hover,a.btn:hover{{background:#0A4A9C}}
.m{{font-size:13px;color:#5B6B7F;margin:20px 0 0}}
</style></head><body><main>
<h1>{title}</h1>
{body}
</main></body></html>"""


def _page(status: int, title: str, body: str) -> HTMLResponse:
    return HTMLResponse(
        _PAGE.format(title=html.escape(title), body=body),
        status_code=status,
        headers={"Content-Security-Policy": _CSP, "Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


def _invalid() -> HTMLResponse:
    return _page(
        400,
        "This link does not work",
        "<p>This unsubscribe link is not valid. You can turn these emails off in the LexiLingo app, under Settings.</p>",
    )


@router.get("/unsubscribe", response_class=HTMLResponse, include_in_schema=False)
async def unsubscribe_confirm(token: str = Query("", max_length=512)):
    """Asks first: mail scanners and link previews fetch every URL in a message, so GET changes nothing."""
    if read_token(token) is None:
        return _invalid()
    action = html.escape(f"{settings.API_V1_PREFIX}/email/unsubscribe?token=" + token, quote=True)
    return _page(
        200,
        "Stop these emails?",
        "<p>You will no longer get reminders, streak alerts or weekly summaries by email. "
        "Emails about your account, like password resets, still arrive.</p>"
        f'<form method="post" action="{action}"><button type="submit">Unsubscribe</button></form>',
    )


@router.post("/unsubscribe", response_class=HTMLResponse, include_in_schema=False)
async def unsubscribe_perform(token: str = Query("", max_length=512), db: AsyncSession = Depends(get_db)):
    """RFC 8058 target: the mail client posts here with no cookies; repeating it changes nothing."""
    claims = read_token(token)
    if claims is None:
        return _invalid()
    user_id, category = claims
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    # A signed link for an account that no longer exists reads the same as success.
    if user is not None and category == NURTURE:
        preference = await _get_or_create_preferences(db, user)
        if preference.nurture_emails_enabled:
            preference.nurture_emails_enabled = False
            await db.commit()
    return _page(
        200,
        "You are unsubscribed",
        "<p>We will not send you reminders, streak alerts or weekly summaries by email. "
        "You can turn them back on any time in the LexiLingo app, under Settings.</p>"
        f'<a class="btn" href="{html.escape(settings.APP_PUBLIC_URL, quote=True)}">Open LexiLingo</a>',
    )
