from __future__ import annotations

import importlib.util
import sys
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace

import pytest

PATH = Path(__file__).parents[2] / "scripts" / "benchmark_voice_gate0.py"
SPEC = importlib.util.spec_from_file_location("benchmark_voice_gate0", PATH)
assert SPEC and SPEC.loader
gate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gate
SPEC.loader.exec_module(gate)


def _saturation(unexpected_errors=0):
    return {
        name: {
            level: {
                "attempts": level,
                "accepted": 1,
                "rejected_busy": level - 1,
                "unexpected_errors": unexpected_errors,
            }
            for level in gate.REQUIRED_CONCURRENCY
        }
        for name in ("piper", "llm")
    }


def test_percentile_is_nearest_rank_and_validates_samples():
    assert [len(text) for text in gate.INPUTS] == [20, 80, 160]
    assert gate.percentile(range(1, 101)) == 95
    assert gate.percentile([3, 1, 2], 50) == 2
    with pytest.raises(ValueError):
        gate.percentile([])


def test_first_non_silent_pcm_validates_and_finds_sample():
    pcm = (0).to_bytes(2, "little", signed=True) + (65).to_bytes(2, "little", signed=True)
    assert gate.first_non_silent_pcm(pcm) == 1
    assert gate.first_non_silent_pcm(b"\0\0") is None
    with pytest.raises(ValueError):
        gate.first_non_silent_pcm(b"\0")


def test_report_schema_and_threshold_status():
    piper = [100.0] * gate.REQUIRED_SAMPLES
    llm = [200.0] * gate.REQUIRED_SAMPLES
    report = gate.build_report(
        {"piper_ttfa": piper, "llm_ttft": llm}, _saturation()
    )
    gate.validate_report(report)
    assert report["go"] is True
    assert report["schema_version"] == "lexilingo.voice-gate0.v2"
    assert report["admitted_latency"]["piper_ttfa"]["samples"] == gate.REQUIRED_SAMPLES
    slow_piper = [151.0] * gate.REQUIRED_SAMPLES
    assert gate.build_report(
        {"piper_ttfa": slow_piper, "llm_ttft": llm}, _saturation()
    )["go"] is False
    slow_llm = [301.0] * gate.REQUIRED_SAMPLES
    assert gate.build_report(
        {"piper_ttfa": piper, "llm_ttft": slow_llm}, _saturation()
    )["go"] is False
    assert gate.build_report(
        {"piper_ttfa": piper, "llm_ttft": llm}, _saturation(unexpected_errors=1)
    )["go"] is False
    bad_accounting = _saturation()
    bad_accounting["llm"][5]["rejected_busy"] = 5
    assert gate.build_report(
        {"piper_ttfa": piper, "llm_ttft": llm}, bad_accounting
    )["go"] is False
    wrong_attempts = _saturation()
    wrong_attempts["llm"][5].update(attempts=4, rejected_busy=3)
    assert gate.build_report(
        {"piper_ttfa": piper, "llm_ttft": llm}, wrong_attempts
    )["go"] is False


def test_report_validation_rejects_stale_thresholds_accounting_and_tampered_go():
    results = {
        "piper_ttfa": [100.0] * gate.REQUIRED_SAMPLES,
        "llm_ttft": [200.0] * gate.REQUIRED_SAMPLES,
    }
    report = gate.build_report(results, _saturation())

    stale = deepcopy(report)
    stale["thresholds_ms"]["llm_ttft_p95"] = 999
    bad_attempts = deepcopy(report)
    bad_attempts["saturation"]["llm"]["5"].update(attempts=4, rejected_busy=3)
    tampered = deepcopy(report)
    tampered["go"] = False

    for invalid in (stale, bad_attempts, tampered):
        with pytest.raises(ValueError):
            gate.validate_report(invalid)


def test_report_rejects_missing_gate_metric():
    report = gate.build_report({"piper_ttfa": [100]}, _saturation())
    assert report["go"] is False
    with pytest.raises(ValueError):
        gate.validate_report(report)


def test_report_rejects_incomplete_sample_or_concurrency_matrix():
    incomplete = gate.build_report(
        {"piper_ttfa": [100.0], "llm_ttft": [200.0]}, _saturation()
    )
    assert incomplete["go"] is False
    with pytest.raises(ValueError):
        gate.validate_report(incomplete)


def test_runtime_environment_requires_a_provider_key(monkeypatch, tmp_path):
    for name in ("GROQ_API_KEYS", "GROQ_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(RuntimeError, match="configure GROQ"):
        gate.load_runtime_environment(tmp_path / "missing.env")


def test_runtime_environment_loads_dotenv_without_overriding_exported_key(monkeypatch, tmp_path):
    env_path = tmp_path / ".env"
    env_path.write_text("GROQ_API_KEY=from-file\n")
    monkeypatch.setenv("GROQ_API_KEY", "exported")
    gate.load_runtime_environment(env_path)
    assert gate.os.environ["GROQ_API_KEY"] == "exported"


@pytest.mark.asyncio
async def test_runner_is_deterministic_and_rejects_invalid_samples():
    async def fake(text):
        return float(len(text))
    assert await gate.run_samples(fake, 4, 2) == [float(len(gate.INPUTS[i % 3])) for i in range(4)]
    async def invalid(_text):
        return -1
    with pytest.raises(ValueError):
        await gate.run_samples(invalid, 1, 1)


@pytest.mark.asyncio
async def test_collect_admitted_times_out_when_capacity_never_recovers(monkeypatch):
    from api.services.trace_cag.generate import ProviderBusyError

    clock = iter((0.0, 0.0, 121.0))

    async def busy(_text):
        raise ProviderBusyError("busy")

    async def no_sleep(_seconds):
        return None

    monkeypatch.setattr(gate, "time", SimpleNamespace(monotonic=lambda: next(clock)))
    monkeypatch.setattr(gate, "asyncio", SimpleNamespace(sleep=no_sleep))

    with pytest.raises(TimeoutError, match="admission did not recover"):
        await gate.collect_admitted(busy, 1)
