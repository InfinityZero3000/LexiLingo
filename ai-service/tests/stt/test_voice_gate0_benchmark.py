from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

PATH = Path(__file__).parents[2] / "scripts" / "benchmark_voice_gate0.py"
SPEC = importlib.util.spec_from_file_location("benchmark_voice_gate0", PATH)
assert SPEC and SPEC.loader
gate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gate
SPEC.loader.exec_module(gate)


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
    report = gate.build_report({
        "piper_ttfa": {level: piper for level in gate.REQUIRED_CONCURRENCY},
        "llm_ttft": {level: llm for level in gate.REQUIRED_CONCURRENCY},
    })
    gate.validate_report(report)
    assert report["go"] is True
    assert report["metrics"]["piper_ttfa"]["1"]["samples"] == gate.REQUIRED_SAMPLES
    slow_piper = [151.0] * gate.REQUIRED_SAMPLES
    assert gate.build_report({
        "piper_ttfa": {level: slow_piper for level in gate.REQUIRED_CONCURRENCY},
        "llm_ttft": {level: llm for level in gate.REQUIRED_CONCURRENCY},
    })["go"] is False


def test_report_rejects_missing_gate_metric():
    report = gate.build_report({"piper_ttfa": {1: [100]}})
    assert report["go"] is False
    with pytest.raises(ValueError):
        gate.validate_report(report)


def test_report_rejects_incomplete_sample_or_concurrency_matrix():
    incomplete = gate.build_report({
        "piper_ttfa": {1: [100.0]},
        "llm_ttft": {1: [200.0]},
    })
    assert incomplete["go"] is False
    with pytest.raises(ValueError):
        gate.validate_report(incomplete)


@pytest.mark.asyncio
async def test_runner_is_deterministic_and_rejects_invalid_samples():
    async def fake(text):
        return float(len(text))
    assert await gate.run_samples(fake, 4, 2) == [float(len(gate.INPUTS[i % 3])) for i in range(4)]
    async def invalid(_text):
        return -1
    with pytest.raises(ValueError):
        await gate.run_samples(invalid, 1, 1)
