"""Email service for transactional emails (password reset, etc.)."""

from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage
from pathlib import Path
from urllib.parse import quote

from fastapi.concurrency import run_in_threadpool

from app.core.config import settings

logger = logging.getLogger(__name__)

_TEMPLATE_DIR = Path(__file__).resolve().parents[1] / "templates"


class EmailService:
    """SMTP-based email sender with lightweight HTML template rendering."""

    @staticmethod
    def _render_template(template_name: str, context: dict[str, str]) -> str:
        template_path = _TEMPLATE_DIR / template_name
        if not template_path.exists():
            raise FileNotFoundError(f"Email template not found: {template_path}")
        content = template_path.read_text(encoding="utf-8")
        return content.format(**context)

    @staticmethod
    def _send_message_blocking(message: EmailMessage) -> None:
        smtp_host = settings.SMTP_HOST
        if not smtp_host:
            raise ValueError("SMTP_HOST is not configured")

        if settings.SMTP_USE_SSL:
            with smtplib.SMTP_SSL(smtp_host, settings.SMTP_PORT) as server:
                if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
                    server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(message)
            return

        with smtplib.SMTP(smtp_host, settings.SMTP_PORT) as server:
            if settings.SMTP_USE_TLS:
                server.starttls()
            if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
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

        context = {
            "display_name": display_name or "Learner",
            "reset_link": reset_link,
            "expiry_minutes": "60",
            "support_email": settings.EMAIL_FROM,
        }

        html_body = cls._render_template("password_reset_email.html", context)
        text_body = cls._render_template("password_reset_email.txt", context)

        message = EmailMessage()
        message["Subject"] = "LexiLingo - Reset your password"
        message["From"] = settings.EMAIL_FROM
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
        False after logging a warning and the generated verification URL for local dev.
        """
        from urllib.parse import quote
        encoded_token = quote(token, safe="")
        verify_link = f"{settings.effective_email_verification_url_base}?token={encoded_token}"
        if not settings.SMTP_HOST:
            logger.warning(
                "SMTP_HOST not configured. Verification email was not sent. "
                "Generated verification URL for %s: %s",
                to_email,
                verify_link,
            )
            return False

        context = {
            "display_name": display_name or "Learner",
            "verify_link": verify_link,
            "expiry_hours": "24",
            "support_email": settings.EMAIL_FROM,
        }

        html_body = cls._render_template("verification_email.html", context)
        text_body = cls._render_template("verification_email.txt", context)

        message = EmailMessage()
        message["Subject"] = "LexiLingo - Verify your email address"
        message["From"] = settings.EMAIL_FROM
        message["To"] = to_email
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        try:
            await run_in_threadpool(cls._send_message_blocking, message)
            logger.info("Verification email sent to %s", to_email)
            return True
        except Exception as exc:  # pragma: no cover - external IO
            logger.exception("Failed to send verification email to %s: %s", to_email, exc)
            return False

    @staticmethod
    def _build_otp_message(to_email: str, otp: str, display_name: str) -> "EmailMessage":
        """Build an EmailMessage containing an admin login OTP."""
        from email.message import EmailMessage as _EM
        msg = _EM()
        msg["Subject"] = "LexiLingo Admin — Your login code"
        msg["From"] = settings.EMAIL_FROM or "noreply@lexilingo.me"
        msg["To"] = to_email
        text = (
            f"Hi {display_name},\n\n"
            f"Your LexiLingo Admin one-time passcode is:\n\n"
            f"  {otp}\n\n"
            f"This code expires in 5 minutes. Do not share it.\n\n"
            f"If you didn't request this, ignore this email.\n\n"
            f"— LexiLingo Team"
        )
        html = f"""
<html><body style="font-family:sans-serif;background:#f8f9ff;padding:32px">
  <div style="max-width:480px;margin:auto;background:#fff;border-radius:16px;padding:32px">
    <h2 style="color:#AD3200;margin:0 0 8px">LingoAdmin Login</h2>
    <p>Hi <strong>{display_name}</strong>,</p>
    <p>Your one-time passcode is:</p>
    <div style="background:#FFF3EE;border-radius:12px;padding:24px;text-align:center;margin:24px 0">
      <span style="font-size:36px;font-weight:700;letter-spacing:8px;color:#AD3200">{otp}</span>
    </div>
    <p style="color:#666;font-size:13px">Expires in <strong>5 minutes</strong>. Do not share this code.</p>
  </div>
</body></html>"""
        msg.set_content(text)
        msg.add_alternative(html, subtype="html")
        return msg
