#!/usr/bin/env python3
"""Gate 0 latency benchmark. Imports models/providers only when executed."""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import os
import statistics
import sys
import time
from pathlib import Path
from typing import Awaitable, Callable, Iterable

_INPUT_TEXT = (
    "Hello, how are you?",
    "Tell me about your day and help me practice conversational English today.",
    "Explain a useful English phrase, give two natural examples, and briefly correct one common learner mistake so I can use it confidently in conversation.",
)
INPUTS = tuple(text[:size].ljust(size) for text, size in zip(_INPUT_TEXT, (20, 80, 160)))
PIPER_LIMIT_MS = 150.0
LLM_LIMIT_MS = 300.0
REQUIRED_SAMPLES = 100
REQUIRED_CONCURRENCY = {1, 5, 10}
SERVICE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_ROOT))


def load_runtime_environment(env_path: Path | None = None) -> None:
    from dotenv import load_dotenv

    load_dotenv(env_path or SERVICE_ROOT / ".env")
    if not (os.getenv("GROQ_API_KEYS") or os.getenv("GROQ_API_KEY") or os.getenv("GEMINI_API_KEY")):
        raise RuntimeError("configure GROQ_API_KEYS/GROQ_API_KEY or GEMINI_API_KEY in ai-service/.env")


def percentile(values: Iterable[float], percent: float = 95) -> float:
    data = sorted(float(value) for value in values)
    if not data:
        raise ValueError("at least one sample is required")
    rank = max(0, math.ceil(percent / 100 * len(data)) - 1)
    return data[rank]


def first_non_silent_pcm(pcm16le: bytes, threshold: int = 64) -> int | None:
    if len(pcm16le) % 2:
        raise ValueError("PCM16LE must contain complete samples")
    for offset in range(0, len(pcm16le), 2):
        if abs(int.from_bytes(pcm16le[offset:offset + 2], "little", signed=True)) > threshold:
            return offset // 2
    return None


def build_report(results: dict[str, list[float]], saturation: dict[str, dict[int, dict]]) -> dict:
    complete = set(results) == {"piper_ttfa", "llm_ttft"} and all(
        len(values) == REQUIRED_SAMPLES for values in results.values()
    )
    metrics = {
        name: {"samples": len(values), "p50_ms": statistics.median(values), "p95_ms": percentile(values)}
        for name, values in results.items()
    }
    saturation_complete = set(saturation) == {"piper", "llm"} and all(
        set(groups) == REQUIRED_CONCURRENCY and all(
            item["unexpected_errors"] == 0
            and item["attempts"] == level
            and item["attempts"] == item["accepted"] + item["rejected_busy"]
            and item["accepted"] >= 1
            for level, item in groups.items()
        )
        for groups in saturation.values()
    )
    go = (
        complete
        and saturation_complete
        and metrics["piper_ttfa"]["p95_ms"] <= PIPER_LIMIT_MS
        and metrics["llm_ttft"]["p95_ms"] <= LLM_LIMIT_MS
    )
    return {
        "schema_version": "lexilingo.voice-gate0.v2",
        "go": go,
        "thresholds_ms": {"piper_ttfa_p95": PIPER_LIMIT_MS, "llm_ttft_p95": LLM_LIMIT_MS},
        "admitted_latency": metrics,
        "saturation": {
            name: {str(level): item for level, item in sorted(groups.items())}
            for name, groups in saturation.items()
        },
    }


def validate_report(report: dict) -> None:
    if report.get("schema_version") != "lexilingo.voice-gate0.v2" or not isinstance(report.get("go"), bool):
        raise ValueError("invalid Gate 0 report")
    metrics = report.get("admitted_latency", {})
    if set(metrics) != {"piper_ttfa", "llm_ttft"}:
        raise ValueError("incomplete Gate 0 metrics")
    for metric in metrics.values():
        if metric["samples"] != REQUIRED_SAMPLES or metric["p50_ms"] < 0 or metric["p95_ms"] < 0:
            raise ValueError("invalid benchmark sample")
    if report.get("thresholds_ms") != {
        "piper_ttfa_p95": PIPER_LIMIT_MS,
        "llm_ttft_p95": LLM_LIMIT_MS,
    }:
        raise ValueError("invalid Gate 0 thresholds")
    expected_levels = {str(value) for value in REQUIRED_CONCURRENCY}
    saturation = report.get("saturation", {})
    if set(saturation) != {"piper", "llm"} or any(set(groups) != expected_levels for groups in saturation.values()):
        raise ValueError("incomplete saturation metrics")
    valid_saturation = all(
        item.get("attempts") == int(level)
        and item.get("unexpected_errors") == 0
        and item.get("attempts") == item.get("accepted", -1) + item.get("rejected_busy", -1)
        and item.get("accepted", 0) >= 1
        for groups in saturation.values()
        for level, item in groups.items()
    )
    if not valid_saturation:
        raise ValueError("invalid saturation accounting")
    expected_go = (
        metrics["piper_ttfa"]["p95_ms"] <= PIPER_LIMIT_MS
        and metrics["llm_ttft"]["p95_ms"] <= LLM_LIMIT_MS
    )
    if report["go"] != expected_go:
        raise ValueError("Gate 0 GO status is inconsistent with measurements")


async def run_samples(runner: Callable[[str], Awaitable[float]], samples: int, concurrency: int) -> list[float]:
    semaphore = asyncio.Semaphore(concurrency)
    async def one(index: int) -> float:
        async with semaphore:
            value = await runner(INPUTS[index % len(INPUTS)])
            if not math.isfinite(value) or value < 0:
                raise ValueError("runner returned invalid latency")
            return value
    return await asyncio.gather(*(one(i) for i in range(samples)))


async def _llm_ttft(text: str) -> float:
    from api.services.trace_cag.generate import stream_llm_tokens
    start = time.perf_counter()
    async for token in stream_llm_tokens(system_prompt="Reply concisely in English.", messages=[{"role": "user", "content": text}], user_input=text, max_tokens=96, allow_gemini_fallback=False):
        if token:
            return (time.perf_counter() - start) * 1000
    raise RuntimeError("configured Groq/Gemini provider returned no token")


async def _piper_ttfa(text: str) -> float:
    from api.services.stt.streaming_tts import StreamingTTS
    global _TTS_RUNTIME
    if _TTS_RUNTIME is None:
        _TTS_RUNTIME = StreamingTTS(capacity=1)
    start = time.perf_counter()
    async for pcm in _TTS_RUNTIME.stream(text):
        if first_non_silent_pcm(pcm) is not None:
            return (time.perf_counter() - start) * 1000
    raise RuntimeError("Piper returned no non-silent PCM")


_TTS_RUNTIME = None


async def collect_admitted(runner: Callable[[str], Awaitable[float]], samples: int) -> list[float]:
    from api.services.stt.streaming_tts import TTSBusyError
    from api.services.trace_cag.generate import ProviderBusyError
    values: list[float] = []
    attempt = 0
    deadline = time.monotonic() + 120.0
    while len(values) < samples:
        if time.monotonic() >= deadline:
            raise TimeoutError("admission did not recover within 120 seconds")
        try:
            values.append(await runner(INPUTS[attempt % len(INPUTS)]))
        except (ProviderBusyError, TTSBusyError):
            await asyncio.sleep(0.02)
        attempt += 1
    return values


async def run_saturation(runner: Callable[[str], Awaitable[float]], concurrency: int) -> dict:
    from api.services.stt.streaming_tts import TTSBusyError
    from api.services.trace_cag.generate import ProviderBusyError
    accepted = rejected = unexpected = 0

    async def one(index: int) -> None:
        nonlocal accepted, rejected, unexpected
        try:
            await runner(INPUTS[index % len(INPUTS)])
            accepted += 1
        except (ProviderBusyError, TTSBusyError):
            rejected += 1
        except Exception:
            unexpected += 1

    await asyncio.gather(*(one(index) for index in range(concurrency)))
    return {"attempts": concurrency, "accepted": accepted, "rejected_busy": rejected, "unexpected_errors": unexpected}


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--concurrency", default="1,5,10")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.samples != REQUIRED_SAMPLES:
        parser.error(f"--samples must be exactly {REQUIRED_SAMPLES} for Gate 0")
    levels = [int(value) for value in args.concurrency.split(",")]
    if set(levels) != REQUIRED_CONCURRENCY or len(levels) != len(REQUIRED_CONCURRENCY):
        parser.error("--concurrency must contain exactly 1,5,10 for Gate 0")

    load_runtime_environment()
    # Warm models/providers before recording production-shaped latency.
    await _piper_ttfa(INPUTS[0])
    await _llm_ttft(INPUTS[0])
    results = {
        "piper_ttfa": await collect_admitted(_piper_ttfa, args.samples),
        "llm_ttft": await collect_admitted(_llm_ttft, args.samples),
    }
    saturation = {"piper": {}, "llm": {}}
    await asyncio.sleep(2.1)
    for level in levels:
        saturation["piper"][level] = await run_saturation(_piper_ttfa, level)
        saturation["llm"][level] = await run_saturation(_llm_ttft, level)
        await asyncio.sleep(2.1)
    report = build_report(results, saturation)
    validate_report(report)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["go"] else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
