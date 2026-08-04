"""Request correlation and secret redaction for application logs.

Two logging.Filter subclasses, wired into the root logger in app/main.py:
- RequestIDLogFilter: injects the current request's correlation ID (set by
  RequestIDMiddleware) into every log record, including ones emitted from
  services/background code that never see the Request object directly.
- RedactSecretsLogFilter: best-effort scrub of common secret shapes
  (Authorization bearer tokens, connection-string passwords, api_key=/
  password=/token= style fields) so an accidental log call elsewhere doesn't
  leak a credential — see app/core/redis.py's connection-string log for a
  concrete example this would have caught.
"""

from __future__ import annotations

import contextvars
import logging
import re

_request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar(
    "request_id", default="-"
)


def set_request_id(request_id: str) -> None:
    _request_id_var.set(request_id)


def get_request_id() -> str:
    return _request_id_var.get()


class RequestIDLogFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = _request_id_var.get()
        return True


_BEARER_TOKEN = re.compile(r"(Bearer\s+)[A-Za-z0-9\-_.=]+", re.IGNORECASE)
_URL_CREDENTIALS = re.compile(r"(://[^:@/\s]*:)[^@/\s]+(@)")
_KEY_VALUE_SECRET = re.compile(
    r"((?:api[_-]?key|password|token|secret)[\"']?\s*[:=]\s*[\"']?)"
    r"[^\"'\s,}]+",
    re.IGNORECASE,
)


def redact_secrets(message: str) -> str:
    message = _BEARER_TOKEN.sub(r"\1***", message)
    message = _URL_CREDENTIALS.sub(r"\1***\2", message)
    message = _KEY_VALUE_SECRET.sub(r"\1***", message)
    return message


class RedactSecretsLogFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        try:
            message = record.getMessage()
        except Exception:  # noqa: BLE001 - never let redaction break logging
            return True
        redacted = redact_secrets(message)
        if redacted != message:
            record.msg = redacted
            record.args = ()
        return True
