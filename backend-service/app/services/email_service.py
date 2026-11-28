"""Email service for transactional emails (password reset, etc.)."""

from __future__ import annotations

import html
import logging
import re
import smtplib
from datetime import UTC, datetime
from email.message import EmailMessage
from email.utils import formataddr, parseaddr
from pathlib import Path
import uuid
from urllib.parse import quote

from fastapi.concurrency import run_in_threadpool

from app.core.config import settings
from app.services.email_copy import email_text, section_keys
from app.services.email_unsubscribe import unsubscribe_headers, unsubscribe_url
from app.services.push_copy import push_language

logger = logging.getLogger(__name__)

_TEMPLATE_DIR = Path(__file__).resolve().parents[1] / "templates"
_OTP_DIGIT_CELL = (
    '<td style="padding:0 3px;"><div class="ll-digit" style="width:44px;padding:12px 0;'
    "background:#F2F7FD;border:1px solid #E1EAF5;border-bottom:3px solid #C9D9EC;border-radius:10px;"
    "font-family:'SF Mono',Menlo,Consolas,monospace;font-size:28px;line-height:1.2;font-weight:700;"
    'color:#0D5FC4;text-align:center;">{digit}</div></td>'
)

# Addresses nobody can receive mail on: RFC 2606/6761 reserved names, plus the
# seed/demo domain, which has no DNS record (every send bounces to EMAIL_FROM).
_UNDELIVERABLE_DOMAINS = ("example.com", "example.net", "example.org", "lexilingo.dev")
_UNDELIVERABLE_SUFFIXES = (".test", ".invalid", ".localhost", ".local", ".example")


def is_undeliverable(address: str) -> bool:
    _, at, domain = parseaddr(address)[1].rpartition("@")
    domain = domain.lower()
    return (
        not at
        or not domain
        or domain in _UNDELIVERABLE_DOMAINS
        or domain.endswith(_UNDELIVERABLE_SUFFIXES)
    )


class _KeepMissing(dict):
    """A copy line may name a field this email does not have (the shared
    "manage" line has two links); leave it for the template check to catch."""

    def __missing__(self, key: str) -> str:
        return "{" + key + "}"


_BOLD = '<strong class="ll-h" style="color:#111418;">'
_LINK = '<a href="{{{field}}}" style="color:#0D5FC4;">'
_TOKEN = re.compile(r"\[a:([a-z_]+)\]")
# The section a template takes its words from, when it is not its own name.
_SECTION = {"_layout": "common", "_weekly_suggestion": "weekly_summary_email"}


def _markup(text: str, html_mode: bool) -> str:
    """Turn email_copy's [b]/[a:field]/[br] tokens into HTML, or drop them."""
    if not html_mode:
        return re.sub(r"\[/?(?:b|a)(?::[a-z_]+)?\]", "", text.replace("[br]", " "))
    text = html.escape(text, quote=False)
    text = text.replace("[b]", _BOLD).replace("[/b]", "</strong>").replace("[br]", "<br />")
    text = text.replace("[a:mailto]", _LINK.format(field="support_email").replace('href="{', 'href="mailto:{'))
    return _TOKEN.sub(lambda m: _LINK.format(field=m.group(1)), text).replace("[/a]", "</a>")


class EmailService:
    """SMTP-based email sender with lightweight HTML template rendering."""

    @staticmethod
    def _render_template(
        template_name: str,
        context: dict[str, str],
        *,
        lang: str | None = None,
        count: int | None = None,
        variant: str | None = None,
    ) -> str:
        template_path = _TEMPLATE_DIR / template_name
        if not template_path.exists():
            raise FileNotFoundError(f"Email template not found: {template_path}")
        content = template_path.read_text(encoding="utf-8")
        stem, _, suffix = template_name.rpartition(".")
        section = _SECTION.get(stem, stem)
        values = _KeepMissing(context)
        words = {
            f"t_{key}": _markup(
                email_text(lang, section, key, count=count, variant=variant), suffix == "html"
            ).format_map(values)
            for key in section_keys(section)
        }
        return content.format(**context, **words)

    @classmethod
    def _text(
        cls, lang: str | None, section: str, key: str, values: dict[str, object], **pick: object
    ) -> str:
        """A subject, title or preheader: plain text, no markup."""
        return _markup(email_text(lang, section, key, **pick), False).format_map(_KeepMissing(values))

    @classmethod
    def _render_html(
        cls,
        template_name: str,
        context: dict[str, str],
        *,
        title: str,
        preheader: str,
        lang: str | None = None,
        count: int | None = None,
        variant: str | None = None,
    ) -> str:
        """Render a body fragment inside the shared layout.

        The headline is HTML over a text-free background image, so it is in the
        learner's language; the old per-mail images had English baked in.
        """
        home_url = settings.APP_PUBLIC_URL.rstrip("/")
        assets = settings.EMAIL_ASSET_BASE_URL.rstrip("/")
        content = cls._render_template(
            template_name, context, lang=lang, count=count, variant=variant
        )
        return cls._render_template(
            "_layout.html",
            {
                "html_lang": push_language(lang),
                "title": html.escape(title),
                "preheader": html.escape(preheader),
                "content": content,
                "home_url": html.escape(home_url),
                "hero_url": html.escape(f"{assets}/hero.jpg"),
                "footer_url": html.escape(f"{assets}/footer.jpg"),
                "support_email": html.escape(cls._support_email()),
            },
            lang=lang,
        )

    @staticmethod
    def _support_email() -> str:
        return settings.EMAIL_REPLY_TO or settings.EMAIL_FROM

    @staticmethod
    def _set_sender(message: EmailMessage) -> None:
        message["From"] = formataddr((settings.EMAIL_FROM_NAME, settings.EMAIL_FROM))
        if settings.EMAIL_REPLY_TO:
            message["Reply-To"] = settings.EMAIL_REPLY_TO

    @staticmethod
    def _send_message_blocking(message: EmailMessage) -> None:
        if is_undeliverable(str(message["To"])):
            raise ValueError(f"refusing to send to undeliverable address {message['To']}")
        smtp_host = settings.SMTP_HOST
        if not smtp_host:
            raise ValueError("SMTP_HOST is not configured")
        if not settings.SMTP_USERNAME or not settings.SMTP_PASSWORD:
            raise ValueError("SMTP_USERNAME and SMTP_PASSWORD are required")

        timeout = settings.SMTP_TIMEOUT

        if settings.SMTP_USE_SSL:
            with smtplib.SMTP_SSL(smtp_host, settings.SMTP_PORT, timeout=timeout) as server:
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(message)
            return

        with smtplib.SMTP(smtp_host, settings.SMTP_PORT, timeout=timeout) as server:
            if settings.SMTP_USE_TLS:
                server.starttls()
            server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
            server.send_message(message)

    @classmethod
    async def _send_templated(
        cls,
        *,
        to_email: str,
        template: str,
        ctx: dict[str, object],
        lang: str | None = None,
        count: int | None = None,
        variant: str | None = None,
        headers: dict[str, str] | None = None,
        html_extra: dict[str, str] | None = None,
        text_extra: dict[str, str] | None = None,
    ) -> bool:
        """Render `<template>.html/.txt` inside the shared layout and send it; never raises.

        Subject, title and preheader come from email_copy's section of the same
        name, in `lang`; `count` picks a singular line, `variant` a named one.
        """
        if not settings.SMTP_HOST:
            logger.warning("SMTP_HOST not configured. %s email was not sent", template)
            return False
        if is_undeliverable(to_email):
            logger.info("Skipped %s email to an undeliverable address", template)
            return False

        raw = {k: str(v) for k, v in ctx.items() if v is not None}
        raw["display_name"] = raw.get("display_name") or "Learner"
        raw["support_email"] = cls._support_email()
        html_ctx = {**{k: html.escape(v) for k, v in raw.items()}, **(html_extra or {})}
        text_ctx = {**raw, **(text_extra or {})}
        pick = {"count": count, "variant": variant}

        message = EmailMessage()
        message["Subject"] = cls._text(lang, template, "subject", raw, **pick)
        for name, value in (headers or {}).items():
            message[name] = value
        cls._set_sender(message)
        message["To"] = to_email
        message.set_content(
            cls._render_template(f"{template}.txt", text_ctx, lang=lang, **pick)
        )
        message.add_alternative(
            cls._render_html(
                f"{template}.html",
                html_ctx,
                title=cls._text(lang, template, "title", raw, **pick),
                preheader=cls._text(lang, template, "preheader", raw, **pick),
                lang=lang,
                **pick,
            ),
            subtype="html",
        )
        try:
            await run_in_threadpool(cls._send_message_blocking, message)
            logger.info("%s email sent", template)
            return True
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send %s email: %s", template, exc)
            return False

    @classmethod
    async def send_password_reset_email(
        cls,
        *,
        to_email: str,
        reset_token: str,
        display_name: str | None,
        lang: str | None = None,
    ) -> bool:
        """Send password-reset email with a tokenized reset URL.

        If SMTP is not configured, returns False after logging the generated
        reset URL, which is how a local developer resets a password.
        """
        encoded_token = quote(reset_token, safe="")
        reset_link = f"{settings.effective_password_reset_url_base}?token={encoded_token}"
        if not settings.SMTP_HOST:
            logger.warning(
                "SMTP_HOST not configured. Password reset email was not sent. "
                "Generated reset URL for %s: %s",
                to_email,
                reset_link,
            )
            return False
        return await cls._send_templated(
            to_email=to_email,
            template="password_reset_email",
            ctx={"display_name": display_name, "reset_link": reset_link, "expiry_minutes": 60},
            lang=lang,
        )

    @classmethod
    async def send_verification_email(
        cls,
        to_email: str,
        token: str,
        display_name: str | None = None,
        lang: str | None = None,
    ) -> bool:
        """Send email verification link to a newly registered user.

        Never logs the token, even when SMTP is not configured.
        """
        verify_link = (
            f"{settings.effective_email_verification_url_base}?token={quote(token, safe='')}"
        )
        return await cls._send_templated(
            to_email=to_email,
            template="verification_email",
            ctx={"display_name": display_name, "verify_link": verify_link, "expiry_hours": 24},
            lang=lang,
        )

    @classmethod
    async def send_vocabulary_review_reminder_email(
        cls,
        *,
        to_email: str,
        display_name: str | None,
        due_count: int,
        lang: str | None = None,
    ) -> bool:
        """Send an occasional vocabulary review reminder email."""
        base = settings.APP_PUBLIC_URL.rstrip("/")
        review_link = f"{base}{settings.REMINDER_REVIEW_ROUTE}"
        settings_link = f"{base}/settings"
        if not settings.SMTP_HOST:
            logger.warning(
                "SMTP_HOST not configured. Vocabulary review reminder email was not sent. "
                "Generated review URL for %s: %s",
                to_email,
                review_link,
            )
            return False
        due = max(0, due_count)
        return await cls._send_templated(
            to_email=to_email,
            template="vocabulary_review_reminder",
            ctx={
                "display_name": display_name,
                "due_count": due,
                "review_link": review_link,
                "settings_link": settings_link,
            },
            lang=lang,
            count=due,
            headers={"List-Unsubscribe": f"<{settings_link}>"},
        )

    @classmethod
    async def send_welcome_email(
        cls, *, to_email: str, display_name: str | None, lang: str | None = None
    ) -> bool:
        """Sent once, right after the address is verified."""
        return await cls._send_templated(
            to_email=to_email,
            template="welcome_email",
            ctx={"display_name": display_name, "start_link": settings.APP_PUBLIC_URL.rstrip("/")},
            lang=lang,
        )

    @classmethod
    async def send_activation_nudge_email(
        cls,
        *,
        to_email: str,
        display_name: str | None,
        user_id: uuid.UUID,
        day: int,
        start_link: str,
        lang: str | None = None,
    ) -> bool:
        """Day-1 / day-3 nudge for a verified learner who has not finished a lesson."""
        return await cls._send_templated(
            to_email=to_email,
            template="activation_nudge_email",
            ctx={
                "display_name": display_name,
                "start_link": start_link,
                "settings_link": f"{settings.APP_PUBLIC_URL.rstrip('/')}/settings",
                "unsubscribe_link": unsubscribe_url(user_id),
            },
            lang=lang,
            variant="d1" if day <= 1 else "d3",
            headers=unsubscribe_headers(user_id),
        )

    @classmethod
    async def send_password_changed_email(
        cls, *, to_email: str, display_name: str | None, lang: str | None = None
    ) -> bool:
        """Security notice after a password change or reset."""
        # Numeric, so it reads the same in every language.
        changed_at = datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC")
        return await cls._send_templated(
            to_email=to_email,
            template="password_changed_email",
            ctx={"display_name": display_name, "changed_at": changed_at},
            lang=lang,
        )

    @classmethod
    async def send_weekly_summary_email(
        cls,
        *,
        to_email: str,
        display_name: str | None,
        user_id: uuid.UUID,
        xp: int,
        streak_days: int,
        words_learned: int,
        suggestion_title: str | None = None,
        suggestion_link: str | None = None,
        lang: str | None = None,
    ) -> bool:
        """Weekly recap; the caller must have checked the user's nurture opt-out."""
        settings_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}/settings"
        suggestion_html = suggestion_text = ""
        if suggestion_title and suggestion_link:
            suggestion_html = cls._render_template(
                "_weekly_suggestion.html",
                {
                    "suggestion_title": html.escape(suggestion_title),
                    "suggestion_link": html.escape(suggestion_link),
                },
                lang=lang,
            )
            up_next = email_text(lang, "weekly_summary_email", "up_next")
            suggestion_text = f"{up_next}: {suggestion_title}\n{suggestion_link}\n\n"
        return await cls._send_templated(
            to_email=to_email,
            template="weekly_summary_email",
            ctx={
                "display_name": display_name,
                "xp": f"{max(0, xp):,}",
                "streak_days": max(0, streak_days),
                "words_learned": max(0, words_learned),
                "settings_link": settings_link,
                "unsubscribe_link": unsubscribe_url(user_id),
            },
            lang=lang,
            headers=unsubscribe_headers(user_id),
            html_extra={"suggestion_block": suggestion_html},
            text_extra={"suggestion_block": suggestion_text},
        )

    @classmethod
    async def send_streak_at_risk_email(
        cls,
        *,
        to_email: str,
        display_name: str | None,
        user_id: uuid.UUID,
        streak_days: int,
        lang: str | None = None,
    ) -> bool:
        """Nudge for learners who have not practised today; the caller checks the nurture opt-out."""
        base = settings.APP_PUBLIC_URL.rstrip("/")
        days = max(0, streak_days)
        return await cls._send_templated(
            to_email=to_email,
            template="streak_at_risk_email",
            ctx={
                "display_name": display_name,
                "streak_days": days,
                "practice_link": f"{base}{settings.REMINDER_REVIEW_ROUTE}",
                "settings_link": f"{base}/settings",
                "unsubscribe_link": unsubscribe_url(user_id),
            },
            lang=lang,
            count=days,
            headers=unsubscribe_headers(user_id),
        )

    @staticmethod
    def _build_staff_message(to_email: str, subject: str, text: str, html_body: str) -> EmailMessage:
        """Plain English mail for the operations team; no layout, no per-language copy."""
        msg = EmailMessage()
        msg["Subject"] = subject
        EmailService._set_sender(msg)
        msg["To"] = to_email
        msg.set_content(text)
        msg.add_alternative(html_body, subtype="html")
        return msg

    @classmethod
    async def send_staff_message(cls, *, to_email: str, subject: str, text: str, html_body: str) -> bool:
        """Send an operations mail; never raises."""
        if not settings.SMTP_HOST:
            logger.warning("SMTP_HOST not configured. Staff email was not sent")
            return False
        if is_undeliverable(to_email):
            logger.info("Skipped staff email to an undeliverable address")
            return False
        try:
            await run_in_threadpool(
                cls._send_message_blocking, cls._build_staff_message(to_email, subject, text, html_body)
            )
            return True
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send staff email: %s", exc)
            return False

    @staticmethod
    def _build_otp_message(to_email: str, otp: str, display_name: str) -> EmailMessage:
        """Build an EmailMessage containing an admin login OTP."""
        from email.message import EmailMessage as _EM
        msg = _EM()
        msg["Subject"] = "LexiLingo Admin — Your login code"
        EmailService._set_sender(msg)
        msg["To"] = to_email
        text = (
            f"Hi {display_name},\n\n"
            f"Your LexiLingo Admin one-time passcode is:\n\n"
            f"  {otp}\n\n"
            f"This code expires in 5 minutes. Do not share it.\n\n"
            f"If you didn't request this, ignore this email.\n\n"
            f"— LexiLingo Team"
        )
        html_body = EmailService._render_html(
            "admin_otp_email.html",
            {
                "display_name": html.escape(display_name),
                "otp_cells": "".join(_OTP_DIGIT_CELL.format(digit=html.escape(d)) for d in otp),
            },
            title="Your admin sign-in code",
            preheader="Your one-time sign-in code. It works for 5 minutes.",
        )
        msg.set_content(text)
        msg.add_alternative(html_body, subtype="html")
        return msg
