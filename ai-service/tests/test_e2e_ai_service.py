import json
from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import httpx
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
    assert result == {"count": 5, "method": "nearest_rank", "p50_ms": 3, "p95_ms": 5, "p99_ms": 5}


@pytest.mark.parametrize(
    "url",
    (
        "https://example.com",
        "http://localhost:8001",
        "http://localhost.example.com:8001",
        "http://user@127.0.0.1:8001",
        "http://127.0.0.1:8001?token=x",
        "http://127.0.0.1:8001/#fragment",
    ),
)
def test_base_url_rejects_token_exfiltration_targets(url):
    with pytest.raises(ValueError, match="loopback"):
        e2e.validate_base_url(url)


def test_base_url_accepts_only_plain_loopback_http():
    assert e2e.validate_base_url("http://127.0.0.1:8001") == "http://127.0.0.1:8001"


@pytest.mark.asyncio
async def test_benchmark_cleanup_runs_when_workload_is_cancelled(monkeypatch):
    cleanup = AsyncMock()
    monkeypatch.setattr(e2e, "cleanup_benchmark_sessions", cleanup)

    with pytest.raises(TimeoutError):
        async with e2e.benchmark_session_cleanup(AsyncMock(), {}, {"s1"}, []):
            raise TimeoutError

    cleanup.assert_awaited_once()


@pytest.mark.asyncio
async def test_wait_ready_uses_deep_readiness():
    client = AsyncMock()
    client.get.return_value = httpx.Response(200)

    await e2e.wait_ready(client)

    client.get.assert_awaited_once_with("/health")


@pytest.mark.asyncio
async def test_benchmark_fails_closed_on_slow_health_and_chat_errors(monkeypatch):
    client = AsyncMock()
    client.__aenter__.return_value = client
    monkeypatch.setattr(e2e.httpx, "AsyncClient", MagicMock(return_value=client))
    monkeypatch.setattr(e2e, "wait_ready", AsyncMock())
    monkeypatch.setattr(e2e, "create_session", AsyncMock(return_value="session"))
    monkeypatch.setattr(
        e2e,
        "_timed",
        AsyncMock(return_value=(httpx.Response(200, request=httpx.Request("GET", "http://127.0.0.1/live")), 600.0)),
    )
    monkeypatch.setattr(e2e, "chat", AsyncMock(side_effect=RuntimeError("provider failed")))
    analyze = AsyncMock(side_effect=RuntimeError("provider failed"))
    monkeypatch.setattr(e2e, "analyze", analyze)
    cleanup = AsyncMock()
    monkeypatch.setattr(e2e, "cleanup_benchmark_sessions", cleanup)
    monkeypatch.setattr(e2e, "_docker_metadata", lambda: {})
    monkeypatch.setattr(e2e, "_groq_slot_ids", lambda _: [])
    stream_response = MagicMock()
    stream_response.raise_for_status = MagicMock()
    async def lines():
        yield "data: {}"
    stream_response.aiter_lines = MagicMock(return_value=lines())
    stream_context = MagicMock()
    stream_context.__aenter__ = AsyncMock(return_value=stream_response)
    stream_context.__aexit__ = AsyncMock(return_value=False)
    client.stream = MagicMock(return_value=stream_context)

    report = await e2e.run_benchmark(
        "http://127.0.0.1:18001",
        {"configured_key_count": 7, "secret_key": "s" * 32},
    )

    assert report["passed"] is False
    assert report["error_count"] >= 14
    assert report["gates"]["health_p95_le_500ms"] is False
    assert report["gates"]["warm_p95_le_2000ms"] is False
    assert report["gates"]["cold_p95_le_12000ms"] is False
    assert report["gates"]["concurrent_samples_35"] is False
    assert report["gates"]["zero_failures"] is False
    measured_sessions = {call.args[3] for call in analyze.await_args_list[5:35]}
    assert len(measured_sessions) == 2
    cleanup.assert_awaited_once()


@pytest.mark.asyncio
async def test_async_main_writes_failed_report_and_returns_one(monkeypatch, tmp_path):
    monkeypatch.setattr(
        e2e,
        "load_env",
        lambda _: {"GROQ_API_KEYS": ",".join(f"key-{i}" for i in range(7)), "SECRET_KEY": "s" * 32},
    )
    monkeypatch.setattr(e2e, "run_benchmark", AsyncMock(return_value={"run_id": "failed", "passed": False}))
    write_report = MagicMock(return_value=tmp_path / "failed.json")
    monkeypatch.setattr(e2e, "write_report", write_report)

    result = await e2e.async_main(SimpleNamespace(
        command="benchmark",
        env_file="unused",
        base_url="http://127.0.0.1:18001",
        report_dir=str(tmp_path),
    ))

    assert result == 1
    write_report.assert_called_once()
