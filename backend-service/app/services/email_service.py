"""Email service for transactional emails (password reset, etc.)."""

from __future__ import annotations

import html
import logging
import smtplib
from datetime import UTC, datetime
from email.message import EmailMessage
from email.utils import formataddr, parseaddr
from pathlib import Path
import uuid
from urllib.parse import quote

from fastapi.concurrency import run_in_threadpool

from app.core.config import settings
from app.services.email_unsubscribe import unsubscribe_headers, unsubscribe_url

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


class EmailService:
    """SMTP-based email sender with lightweight HTML template rendering."""

    @staticmethod
    def _render_template(template_name: str, context: dict[str, str]) -> str:
        template_path = _TEMPLATE_DIR / template_name
        if not template_path.exists():
            raise FileNotFoundError(f"Email template not found: {template_path}")
        content = template_path.read_text(encoding="utf-8")
        return content.format(**context)

    @classmethod
    def _render_html(
        cls,
        template_name: str,
        context: dict[str, str],
        *,
        title: str,
        preheader: str,
        hero: str | None = None,
    ) -> str:
        """Render a body fragment inside the shared layout."""
        home_url = settings.APP_PUBLIC_URL.rstrip("/")
        assets = settings.EMAIL_ASSET_BASE_URL.rstrip("/")
        hero = hero or template_name.removesuffix(".html")
        return cls._render_template(
            "_layout.html",
            {
                "title": html.escape(title),
                "preheader": html.escape(preheader),
                "content": cls._render_template(template_name, context),
                "home_url": html.escape(home_url),
                "hero_url": html.escape(f"{assets}/hero_{hero}.jpg"),
                "footer_url": html.escape(f"{assets}/footer.jpg"),
                "support_email": html.escape(cls._support_email()),
            },
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
    async def send_password_reset_email(
        cls,
        *,
        to_email: str,
        reset_token: str,
        display_name: str | None,
    ) -> bool:
        """Send password-reset email with a tokenized reset URL.

        Returns True when sent successfully. If SMTP is not configured, returns
        False after logging a warning and the generated reset URL for local dev.
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

        html_context = {
            "display_name": html.escape(display_name or "Learner"),
            "reset_link": html.escape(reset_link),
            "expiry_minutes": "60",
            "support_email": html.escape(cls._support_email()),
        }
        text_context = {
            "display_name": display_name or "Learner",
            "reset_link": reset_link,
            "expiry_minutes": "60",
            "support_email": cls._support_email(),
        }

        html_body = cls._render_html(
            "password_reset_email.html",
            html_context,
            title="Choose a new password",
            preheader="Use this link to choose a new password. It works for 60 minutes.",
        )
        text_body = cls._render_template("password_reset_email.txt", text_context)

        message = EmailMessage()
        message["Subject"] = "LexiLingo - Reset your password"
        cls._set_sender(message)
        message["To"] = to_email
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        try:
            await run_in_threadpool(cls._send_message_blocking, message)
            logger.info("Password reset email sent to %s", to_email)
            return True
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send password reset email to %s: %s", to_email, exc)
            return False

    @classmethod
    async def send_verification_email(
        cls,
        to_email: str,
        token: str,
        display_name: str | None = None,
    ) -> bool:
        """Send email verification link to a newly registered user.

        Returns True when sent successfully. If SMTP is not configured, returns
        False without exposing the verification token in logs.
        """
        from urllib.parse import quote
        encoded_token = quote(token, safe="")
        verify_link = f"{settings.effective_email_verification_url_base}?token={encoded_token}"
        if not settings.SMTP_HOST:
            logger.warning(
                "SMTP_HOST not configured. Verification email was not sent"
            )
            return False

        html_context = {
            "display_name": html.escape(display_name or "Learner"),
            "verify_link": html.escape(verify_link),
            "expiry_hours": "24",
            "support_email": html.escape(cls._support_email()),
        }
        text_context = {
            "display_name": display_name or "Learner",
            "verify_link": verify_link,
            "expiry_hours": "24",
            "support_email": cls._support_email(),
        }

        html_body = cls._render_html(
            "verification_email.html",
            html_context,
            title="Confirm your email",
            preheader="Confirm your email to activate your LexiLingo account.",
        )
        text_body = cls._render_template("verification_email.txt", text_context)

        message = EmailMessage()
        message["Subject"] = "LexiLingo - Verify your email address"
        cls._set_sender(message)
        message["To"] = to_email
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        try:
            await run_in_threadpool(cls._send_message_blocking, message)
            logger.info("Verification email sent")
            return True
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception(
                "Failed to send verification email: %s",
                exc,
            )
            return False

    @classmethod
    async def send_vocabulary_review_reminder_email(
        cls,
        *,
        to_email: str,
        display_name: str | None,
        due_count: int,
    ) -> bool:
        """Send an occasional vocabulary review reminder email."""
        review_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}{settings.REMINDER_REVIEW_ROUTE}"
        settings_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}/settings"

        if not settings.SMTP_HOST:
            logger.warning(
                "SMTP_HOST not configured. Vocabulary review reminder email was not sent. "
                "Generated review URL for %s: %s",
                to_email,
                review_link,
            )
            return False

        due = max(0, due_count)
        due_noun = "word" if due == 1 else "words"
        html_context = {
            "display_name": html.escape(display_name or "Learner"),
            "due_count": str(due),
            "due_noun": due_noun,
            "review_link": html.escape(review_link),
            "settings_link": html.escape(settings_link),
            "support_email": html.escape(cls._support_email()),
        }
        text_context = {
            "display_name": display_name or "Learner",
            "due_count": str(due),
            "due_noun": due_noun,
            "review_link": review_link,
            "settings_link": settings_link,
            "support_email": cls._support_email(),
        }

        html_body = cls._render_html(
            "vocabulary_review_reminder.html",
            html_context,
            title="Time to review",
            preheader=f"{due} {due_noun} waiting for review.",
        )
        text_body = cls._render_template("vocabulary_review_reminder.txt", text_context)

        message = EmailMessage()
        message["Subject"] = "LexiLingo - Time to review your vocabulary"
        message["List-Unsubscribe"] = f"<{settings_link}>"
        cls._set_sender(message)
        message["To"] = to_email
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        try:
            await run_in_threadpool(cls._send_message_blocking, message)
            logger.info("Vocabulary review reminder email sent to %s", to_email)
            return True
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception(
                "Failed to send vocabulary review reminder email to %s: %s",
                to_email,
                exc,
            )
            return False

    @classmethod
    async def _send_templated(
        cls,
        *,
        to_email: str,
        subject: str,
        template: str,
        ctx: dict[str, object],
        title: str,
        preheader: str,
        headers: dict[str, str] | None = None,
        html_extra: dict[str, str] | None = None,
        text_extra: dict[str, str] | None = None,
        hero: str | None = None,
    ) -> bool:
        """Render `<template>.html/.txt` inside the shared layout and send it; never raises."""
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

        message = EmailMessage()
        message["Subject"] = subject
        for name, value in (headers or {}).items():
            message[name] = value
        cls._set_sender(message)
        message["To"] = to_email
        message.set_content(cls._render_template(f"{template}.txt", text_ctx))
        message.add_alternative(
            cls._render_html(
                f"{template}.html", html_ctx, title=title, preheader=preheader, hero=hero
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
    async def send_welcome_email(cls, *, to_email: str, display_name: str | None) -> bool:
        """Sent once, right after the address is verified."""
        return await cls._send_templated(
            to_email=to_email,
            subject="Welcome to LexiLingo",
            template="welcome_email",
            ctx={"display_name": display_name, "start_link": settings.APP_PUBLIC_URL.rstrip("/")},
            title="Welcome to LexiLingo",
            preheader="Your account is ready. Start your first lesson.",
        )

    @classmethod
    async def send_activation_nudge_email(
        cls, *, to_email: str, display_name: str | None, user_id: uuid.UUID, day: int, start_link: str
    ) -> bool:
        """Day-1 / day-3 nudge for a verified learner who has not finished a lesson."""
        settings_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}/settings"
        if day <= 1:
            subject = "Your first LexiLingo lesson takes five minutes"
            lead = "your account is ready, and your first lesson is ready when you are."
        else:
            subject = "Still want to start with LexiLingo?"
            lead = "your first lesson is still waiting. One short lesson is enough to begin."
        return await cls._send_templated(
            to_email=to_email,
            subject=subject,
            template="activation_nudge_email",
            ctx={
                "display_name": display_name,
                "lead": lead,
                "start_link": start_link,
                "settings_link": settings_link,
                "unsubscribe_link": unsubscribe_url(user_id),
            },
            title=subject,
            preheader="One tap opens your first lesson.",
            headers=unsubscribe_headers(user_id),
            hero="welcome_email",
        )

    @classmethod
    async def send_password_changed_email(cls, *, to_email: str, display_name: str | None) -> bool:
        """Security notice after a password change or reset."""
        changed_at = datetime.now(UTC).strftime("%d %b %Y, %H:%M UTC")
        return await cls._send_templated(
            to_email=to_email,
            subject="Your LexiLingo password was changed",
            template="password_changed_email",
            ctx={"display_name": display_name, "changed_at": changed_at},
            title="Your password was changed",
            preheader="If this was not you, act now.",
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
            )
            suggestion_text = f"Up next for you: {suggestion_title}\n{suggestion_link}\n\n"
        return await cls._send_templated(
            to_email=to_email,
            subject="Your week in LexiLingo",
            template="weekly_summary_email",
            ctx={
                "display_name": display_name,
                "xp": f"{max(0, xp):,}",
                "streak_days": max(0, streak_days),
                "words_learned": max(0, words_learned),
                "settings_link": settings_link,
                "unsubscribe_link": unsubscribe_url(user_id),
            },
            title="Your week in LexiLingo",
            preheader=f"{max(0, xp):,} XP and a {max(0, streak_days)}-day streak this week.",
            headers=unsubscribe_headers(user_id),
            html_extra={"suggestion_block": suggestion_html},
            text_extra={"suggestion_block": suggestion_text},
        )

    @classmethod
    async def send_streak_at_risk_email(
        cls, *, to_email: str, display_name: str | None, user_id: uuid.UUID, streak_days: int
    ) -> bool:
        """Nudge for learners who have not practised today; the caller checks the nurture opt-out."""
        settings_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}/settings"
        days = max(0, streak_days)
        return await cls._send_templated(
            to_email=to_email,
            subject=f"Your {days}-day streak ends tonight",
            template="streak_at_risk_email",
            ctx={
                "display_name": display_name,
                "streak_days": days,
                "day_noun": "day" if days == 1 else "days",
                "practice_link": f"{settings.APP_PUBLIC_URL.rstrip('/')}{settings.REMINDER_REVIEW_ROUTE}",
                "settings_link": settings_link,
                "unsubscribe_link": unsubscribe_url(user_id),
            },
            title="Keep your streak alive",
            preheader=f"{days} {'day' if days == 1 else 'days'} in a row. A few minutes is enough.",
            headers=unsubscribe_headers(user_id),
        )

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
