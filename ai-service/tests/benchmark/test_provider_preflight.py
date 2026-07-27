import pytest
from argparse import Namespace

from tracecag_bench import provider_preflight
from tracecag_bench import cli


class _Response:
    def __init__(self, status_code, payload=None):
        self.status_code = status_code
        self._payload = payload or {}

    def json(self):
        return self._payload


class _Client:
    responses = []

    def __init__(self, **_kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return None

    async def get(self, *_args, **_kwargs):
        value = self.responses.pop(0)
        if isinstance(value, Exception):
            raise value
        return value


@pytest.mark.asyncio
async def test_provider_preflight_rejects_missing_credentials(monkeypatch):
    for name in ("GROQ_API_KEYS", "GROQ_KEYS", "GROQ_API_KEY"):
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(provider_preflight.ProviderPreflightError, match="no API credentials"):
        await provider_preflight.require_primary_provider("groq", "qwen/qwen3-32b")


@pytest.mark.asyncio
async def test_provider_preflight_accepts_available_model_after_bad_key(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEYS", "bad,good")
    monkeypatch.setattr(provider_preflight.httpx, "AsyncClient", _Client)
    _Client.responses = [_Response(401), _Response(200, {"data": [{"id": "qwen/qwen3-32b"}]})]
    result = await provider_preflight.require_primary_provider("groq", "qwen/qwen3-32b")
    assert result["status"] == "ready"


@pytest.mark.asyncio
async def test_provider_preflight_rejects_unavailable_model(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEYS", "configured")
    monkeypatch.setattr(provider_preflight.httpx, "AsyncClient", _Client)
    _Client.responses = [_Response(200, {"data": [{"id": "another-model"}]})]
    with pytest.raises(provider_preflight.ProviderPreflightError, match="unavailable"):
        await provider_preflight.require_primary_provider("groq", "qwen/qwen3-32b")


@pytest.mark.asyncio
async def test_provider_preflight_wraps_connection_failure(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEYS", "configured")
    monkeypatch.setattr(provider_preflight.httpx, "AsyncClient", _Client)
    _Client.responses = [provider_preflight.httpx.ConnectError("dns unavailable")]
    with pytest.raises(provider_preflight.ProviderPreflightError, match="connection failed: ConnectError"):
        await provider_preflight.require_primary_provider("groq", "qwen/qwen3-32b")


@pytest.mark.asyncio
async def test_cli_provider_failure_stops_before_dataset_or_protocol(monkeypatch):
    async def fail_provider(*_args):
        raise provider_preflight.ProviderPreflightError("offline")

    def should_not_run(*_args, **_kwargs):
        raise AssertionError("benchmark sampling started after provider preflight failure")

    monkeypatch.setattr(cli, "require_primary_provider", fail_provider)
    monkeypatch.setattr(cli, "load_public_qa", should_not_run)
    monkeypatch.setattr(cli, "run_public_qa_protocol", should_not_run)
    args = Namespace(
        command="public-qa", dataset="hotpotqa", n=1, seed=42,
        profile="public_cag_compare", modes=None, cache_repeats=2,
        generation_policy="auto", evidence_mode="candidate_pool",
        provider="groq", model="qwen/qwen3-32b", allow_fallback=False,
        allow_degraded_provider=False, allow_degraded_kg=False, report_json=None,
    )
    assert await cli.run_args(args) == 3
