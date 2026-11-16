"""Signed one-click unsubscribe links for non-transactional mail."""

from __future__ import annotations

import base64
import hashlib
import hmac
import uuid
from urllib.parse import quote

from app.core.config import settings

NURTURE = "nurture"
CATEGORIES = frozenset({NURTURE})
_PURPOSE = b"lexilingo/email-unsubscribe/v1"


def _key() -> bytes:
    if settings.EMAIL_UNSUBSCRIBE_SECRET:
        return settings.EMAIL_UNSUBSCRIBE_SECRET.encode("utf-8")
    return hmac.new(settings.SECRET_KEY.encode("utf-8"), _PURPOSE + b"/key", hashlib.sha256).digest()


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _sign(body: bytes) -> bytes:
    return hmac.new(_key(), _PURPOSE + b"|" + body, hashlib.sha256).digest()[:16]


def make_token(user_id: uuid.UUID, category: str = NURTURE) -> str:
    """No expiry: a mail sits in an inbox for years. Rotating the secret revokes all of them."""
    body = f"{category}:{user_id}".encode("ascii")
    return f"{_b64(body)}.{_b64(_sign(body))}"


def read_token(token: str) -> tuple[uuid.UUID, str] | None:
    try:
        body_part, sig_part = token.split(".")
        body, sig = _unb64(body_part), _unb64(sig_part)
        if not hmac.compare_digest(sig, _sign(body)):
            return None
        category, _, raw_id = body.decode("ascii").partition(":")
        if category not in CATEGORIES:
            return None
        return uuid.UUID(raw_id), category
    except (ValueError, UnicodeError):
        return None


def unsubscribe_url(user_id: uuid.UUID, category: str = NURTURE) -> str:
    base = settings.API_PUBLIC_URL.rstrip("/")
    return f"{base}{settings.API_V1_PREFIX}/email/unsubscribe?token={quote(make_token(user_id, category), safe='')}"


def unsubscribe_headers(user_id: uuid.UUID, category: str = NURTURE) -> dict[str, str]:
    """RFC 2369 + RFC 8058 headers; the mailto target is offered only when a real inbox is configured."""
    targets = [f"<{unsubscribe_url(user_id, category)}>"]
    if settings.EMAIL_REPLY_TO:
        targets.append(f"<mailto:{settings.EMAIL_REPLY_TO}?subject=unsubscribe>")
    return {
        "List-Unsubscribe": ", ".join(targets),
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    }
