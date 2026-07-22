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


def build_report(results: dict[str, dict[int, list[float]]]) -> dict:
    required = {"piper_ttfa", "llm_ttft"}
    complete = set(results) == required and all(
        set(results[name]) == REQUIRED_CONCURRENCY
        and all(len(values) == REQUIRED_SAMPLES for values in results[name].values())
        for name in required
    )
    metrics = {
        name: {
            str(concurrency): {"samples": len(values), "p50_ms": statistics.median(values), "p95_ms": percentile(values)}
            for concurrency, values in sorted(groups.items())
        }
        for name, groups in results.items()
    }
    go = complete and all(
        item["p95_ms"] <= (PIPER_LIMIT_MS if name == "piper_ttfa" else LLM_LIMIT_MS)
        for name, groups in metrics.items()
        for item in groups.values()
    )
    return {"schema_version": "lexilingo.voice-gate0.v1", "go": go, "thresholds_ms": {"piper_ttfa_p95": PIPER_LIMIT_MS, "llm_ttft_p95": LLM_LIMIT_MS}, "metrics": metrics}


def validate_report(report: dict) -> None:
    if report.get("schema_version") != "lexilingo.voice-gate0.v1" or not isinstance(report.get("go"), bool):
        raise ValueError("invalid Gate 0 report")
    metrics = report.get("metrics", {})
    if set(metrics) != {"piper_ttfa", "llm_ttft"} or any(
        set(groups) != {str(value) for value in REQUIRED_CONCURRENCY}
        for groups in metrics.values()
    ):
        raise ValueError("incomplete Gate 0 metrics")
    for groups in metrics.values():
        for metric in groups.values():
            if metric["samples"] != REQUIRED_SAMPLES or metric["p50_ms"] < 0 or metric["p95_ms"] < 0:
                raise ValueError("invalid benchmark sample")


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
    async for token in stream_llm_tokens(system_prompt="Reply concisely in English.", messages=[{"role": "user", "content": text}], user_input=text):
        if token:
            return (time.perf_counter() - start) * 1000
    raise RuntimeError("configured Groq/Gemini provider returned no token")


async def _piper_ttfa(text: str) -> float:
    from api.services.tts_service import get_tts_service
    voice = get_tts_service()._load_voice()
    def synthesize_until_audio() -> float:
        start = time.perf_counter()
        for chunk in voice.synthesize(text):
            if first_non_silent_pcm(chunk.audio_int16_bytes) is not None:
                return (time.perf_counter() - start) * 1000
        raise RuntimeError("Piper returned no non-silent PCM")

    return await asyncio.to_thread(synthesize_until_audio)


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
    results = {"piper_ttfa": {}, "llm_ttft": {}}
    for level in levels:
        results["piper_ttfa"][level] = await run_samples(_piper_ttfa, args.samples, level)
        results["llm_ttft"][level] = await run_samples(_llm_ttft, args.samples, level)
    report = build_report(results)
    validate_report(report)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["go"] else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
