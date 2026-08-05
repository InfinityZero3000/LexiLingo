import logging

from app.core.logging_config import (
    RedactSecretsLogFilter,
    RequestIDLogFilter,
    redact_secrets,
    set_request_id,
)


def test_redact_secrets_bearer_token():
    msg = "Auth failed for header Authorization: Bearer sk_live_abc123XYZ.token"
    assert "sk_live_abc123XYZ" not in redact_secrets(msg)
    assert "Bearer ***" in redact_secrets(msg)


def test_redact_secrets_url_credentials():
    msg = "Redis connected: redis://:Af07AAIncDFhYzU3NDk3@redis:6379/0"
    redacted = redact_secrets(msg)
    assert "Af07AAIncDFhYzU3NDk3" not in redacted
    assert "redis://:***@redis:6379/0" == redacted.split("Redis connected: ")[1]


def test_redact_secrets_key_value_pairs():
    msg = 'config loaded: api_key="sk_abcdef123456" password=hunter2'
    redacted = redact_secrets(msg)
    assert "sk_abcdef123456" not in redacted
    assert "hunter2" not in redacted


def test_redact_secrets_leaves_normal_messages_untouched():
    msg = "Request: GET /api/v1/courses from 127.0.0.1"
    assert redact_secrets(msg) == msg


def _make_record(msg: str) -> logging.LogRecord:
    return logging.LogRecord(
        name="test", level=logging.INFO, pathname=__file__, lineno=1,
        msg=msg, args=(), exc_info=None,
    )


def test_redact_secrets_log_filter_mutates_record():
    record = _make_record("token=abcd1234efgh5678")
    RedactSecretsLogFilter().filter(record)
    assert "abcd1234efgh5678" not in record.getMessage()


def test_request_id_log_filter_injects_current_id():
    set_request_id("req-123")
    record = _make_record("hello")
    RequestIDLogFilter().filter(record)
    assert record.request_id == "req-123"


if __name__ == "__main__":
    test_redact_secrets_bearer_token()
    test_redact_secrets_url_credentials()
    test_redact_secrets_key_value_pairs()
    test_redact_secrets_leaves_normal_messages_untouched()
    test_redact_secrets_log_filter_mutates_record()
    test_request_id_log_filter_injects_current_id()
    print("All logging_config self-checks passed.")
