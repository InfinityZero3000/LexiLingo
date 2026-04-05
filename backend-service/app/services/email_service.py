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
        if settings.SMTP_USE_SSL:
            with smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT) as server:
                if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
                    server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(message)
            return

        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
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
        reset_link = f"{settings.PASSWORD_RESET_URL_BASE}?token={encoded_token}"

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
