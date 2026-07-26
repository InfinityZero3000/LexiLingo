import json
from datetime import UTC, datetime

import pytest
from jose import jwt

from scripts import e2e_ai_service as e2e


def test_nearest_rank_percentiles():
    values = list(range(1, 101))
    assert e2e.nearest_rank(values, 0.50) == 50
    assert e2e.nearest_rank(values, 0.95) == 95
    assert e2e.nearest_rank(values, 0.99) == 99


def test_preflight_requires_exactly_seven_unique_keys():
    env = e2e.required_config({
        "GROQ_API_KEYS": ",".join(f"key-{i}" for i in range(7)),
        "SECRET_KEY": "s" * 32,
    })
    assert env["configured_key_count"] == 7
    with pytest.raises(ValueError, match="exactly seven"):
        e2e.required_config({"GROQ_API_KEYS": "a,b", "SECRET_KEY": "s" * 32})


def test_access_token_has_backend_contract():
    token = e2e.make_access_token("u1", "s" * 32, now=datetime(2026, 1, 1, tzinfo=UTC))
    claims = jwt.decode(
        token,
        "s" * 32,
        algorithms=["HS256"],
        audience="lexilingo-services",
        issuer="lexilingo-backend",
        options={"verify_exp": False},
    )
    assert claims["sub"] == "u1"
    assert claims["type"] == "access"
    assert claims["exp"] - claims["iat"] == 300


def test_report_redaction_rejects_secrets_and_auth_headers(tmp_path):
    safe = {"configured_key_count": 7, "slot_ids": list(range(7))}
    path = e2e.write_report(safe, tmp_path, secrets=["super-secret"])
    assert json.loads(path.read_text()) == safe

    with pytest.raises(ValueError, match="secret"):
        e2e.write_report({"error": "super-secret"}, tmp_path, secrets=["super-secret"])
    with pytest.raises(ValueError, match="sensitive"):
        e2e.write_report({"error": "Authorization: Bearer abc.def.ghi"}, tmp_path)


def test_latency_summary_includes_sample_count_and_percentiles():
    result = e2e.summarize_latencies([1, 2, 3, 4, 5])
    assert result == {"count": 5, "p50_ms": 3, "p95_ms": 5, "p99_ms": 5}
