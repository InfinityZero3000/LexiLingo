#!/usr/bin/env python3
"""Production-like AI-service smoke and latency checks with redacted reports."""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import ipaddress
import json
import math
import os
import platform
import re
import subprocess
import sys
import time
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import httpx
from jose import jwt


SAFE_FALLBACK = "I'm sorry, I'm temporarily unavailable right now. Please try again in a moment."
SENSITIVE_PATTERNS = (
    re.compile(r"authorization\s*:\s*bearer", re.I),
    re.compile(r"\beyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\b"),
    re.compile(r"\b(?:gsk|sk)-[a-zA-Z0-9_-]+\b"),
    re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s/@:]+:[^\s/@]+@", re.I),
)


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def required_config(env: dict[str, str]) -> dict[str, Any]:
    raw_keys = env.get("GROQ_API_KEYS", "")
    parts = raw_keys.split(",") if raw_keys else []
    if any(not item.strip() for item in parts):
        raise ValueError("GROQ_API_KEYS contains a blank entry")
    keys = [item.strip() for item in parts]
    if len(keys) != 7 or len(set(keys)) != 7:
        raise ValueError("GROQ_API_KEYS must contain exactly seven unique keys")
    secret = env.get("SECRET_KEY", "")
    if len(secret) < 32:
        raise ValueError("SECRET_KEY must contain at least 32 characters")
    return {"configured_key_count": len(keys), "keys": keys, "secret_key": secret}


def validate_base_url(value: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "http"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in ("", "/")
    ):
        raise ValueError("base URL must be plain HTTP on loopback")
    try:
        if not ipaddress.ip_address(parsed.hostname).is_loopback:
            raise ValueError
    except ValueError as exc:
        raise ValueError("base URL must use a literal loopback IP") from exc
    return value.rstrip("/")


def make_access_token(user_id: str, secret: str, *, now: datetime | None = None) -> str:
    issued = now or datetime.now(UTC)
    return jwt.encode(
        {
            "sub": user_id,
            "type": "access",
            "iss": "lexilingo-backend",
            "aud": "lexilingo-services",
            "iat": issued,
            "exp": issued + timedelta(minutes=5),
        },
        secret,
        algorithm="HS256",
    )


def nearest_rank(values: list[float], quantile: float) -> float:
    if not values:
        raise ValueError("latency samples are empty")
    ordered = sorted(values)
    return ordered[max(0, math.ceil(quantile * len(ordered)) - 1)]


def summarize_latencies(values: list[float]) -> dict[str, float | int]:
    return {
        "count": len(values),
        "method": "nearest_rank",
        "p50_ms": nearest_rank(values, 0.50),
        "p95_ms": nearest_rank(values, 0.95),
        "p99_ms": nearest_rank(values, 0.99),
    }


def _assert_redacted(serialized: str, secrets: list[str]) -> None:
    lowered = serialized.lower()
    if any(secret and secret in serialized for secret in secrets):
        raise ValueError("report contains a configured secret")
    if any(pattern.search(serialized) for pattern in SENSITIVE_PATTERNS):
        raise ValueError("report contains sensitive authentication data")
    if '"prompt"' in lowered or '"provider_body"' in lowered:
        raise ValueError("report contains sensitive request/provider content")


def write_report(report: dict[str, Any], directory: Path, *, secrets: list[str] | None = None) -> Path:
    serialized = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    _assert_redacted(serialized, secrets or [])
    directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    run_id = str(report.get("run_id") or datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ"))
    path = directory / f"{run_id}.json"
    pending = path.with_suffix(".json.tmp")
    pending.write_text(serialized + "\n", encoding="utf-8")
    pending.chmod(0o600)
    pending.replace(path)
    cutoff = time.time() - 30 * 86400
    for old in directory.glob("*.json"):
        if old != path and old.stat().st_mtime < cutoff:
            old.unlink()
    return path


def _docker_metadata() -> dict[str, Any]:
    try:
        output = subprocess.run(
            ["docker", "compose", "-p", "lexilingo-ai-e2e", "-f", "docker-compose.yml", "images", "--format", "json"],
            cwd=Path(__file__).resolve().parents[1],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
        config = subprocess.run(
            ["docker", "compose", "-p", "lexilingo-ai-e2e", "-f", "docker-compose.yml", "config", "--format", "json"],
            cwd=Path(__file__).resolve().parents[1], check=True, capture_output=True, text=True, timeout=10,
        ).stdout
        services = json.loads(config).get("services", {})
        limits = {name: {key: service.get(key) for key in ("mem_limit", "memswap_limit")} for name, service in services.items()}
        commit = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=Path(__file__).resolve().parents[2],
            check=True, capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        return {"images": json.loads(output) if output.strip() else [], "resource_limits": limits, "git_commit": commit}
    except Exception as exc:
        return {"images_error": type(exc).__name__}


def _groq_slot_ids(since: str) -> list[int]:
    try:
        output = subprocess.run(
            ["docker", "compose", "-p", "lexilingo-ai-e2e", "-f", "docker-compose.yml", "logs", "--since", since, "ai-service"],
            cwd=Path(__file__).resolve().parents[1], check=True, capture_output=True, text=True, timeout=10,
        ).stdout
        return [int(value) for value in re.findall(r"groq_slot_acquired slot_id=(\d+)", output)]
    except Exception:
        return []


async def _timed(client: httpx.AsyncClient, method: str, path: str, **kwargs: Any) -> tuple[httpx.Response, float]:
    started = time.perf_counter_ns()
    response = await client.request(method, path, **kwargs)
    return response, (time.perf_counter_ns() - started) / 1_000_000


async def wait_ready(client: httpx.AsyncClient, timeout: float = 180) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            response = await client.get("/health")
            if response.status_code == 200:
                return
        except httpx.HTTPError:
            pass
        await asyncio.sleep(2)
    raise TimeoutError("AI service did not become healthy within 180 seconds")


async def create_session(client: httpx.AsyncClient, headers: dict[str, str], user_id: str) -> str:
    response = await client.post("/api/v1/chat/sessions", headers=headers, json={"user_id": user_id, "title": "E2E"})
    response.raise_for_status()
    return str(response.json()["session_id"])


async def chat(client: httpx.AsyncClient, headers: dict[str, str], user_id: str, session_id: str, message: str, *, require_provider: bool = True) -> tuple[dict[str, Any], float]:
    response, elapsed = await _timed(
        client,
        "POST",
        "/api/v1/chat/messages",
        headers=headers,
        json={"user_id": user_id, "session_id": session_id, "message": message},
    )
    response.raise_for_status()
    body = response.json()
    if not str(body.get("response", "")).strip() or body.get("response") == SAFE_FALLBACK:
        raise RuntimeError("provider-backed response was not produced")
    model = str(body.get("metadata", {}).get("model_used", ""))
    if require_provider and "groq" not in model.lower():
        raise RuntimeError("response metadata does not identify Groq")
    return body, elapsed


async def analyze(client: httpx.AsyncClient, headers: dict[str, str], user_id: str, session_id: str, text: str) -> tuple[dict[str, Any], float]:
    response, elapsed = await _timed(
        client, "POST", "/api/v1/ai/trace-cag/analyze", headers=headers,
        json={"text": text, "user_id": user_id, "session_id": session_id, "input_type": "text"},
    )
    response.raise_for_status()
    body = response.json()
    if not str(body.get("tutor_response", "")).strip():
        raise RuntimeError("TraceCAG response was empty")
    return body, elapsed


async def cleanup_benchmark_sessions(
    client: httpx.AsyncClient,
    headers: dict[str, str],
    session_ids: set[str],
) -> None:
    for session_id in session_ids:
        response = await client.delete(f"/api/v1/chat/sessions/{session_id}", headers=headers)
        response.raise_for_status()


@asynccontextmanager
async def benchmark_session_cleanup(
    client: httpx.AsyncClient,
    headers: dict[str, str],
    session_ids: set[str],
    cleanup_failures: list[str],
):
    try:
        yield
    finally:
        try:
            await cleanup_benchmark_sessions(client, headers, session_ids)
        except Exception as exc:
            cleanup_failures.append(type(exc).__name__)


async def run_smoke(base_url: str, config: dict[str, Any]) -> dict[str, Any]:
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    user_id = f"e2e-{run_id}"
    headers = {"Authorization": f"Bearer {make_access_token(user_id, config['secret_key'])}"}
    async with httpx.AsyncClient(base_url=base_url, timeout=60) as client:
        await wait_ready(client)
        session_id = await create_session(client, headers, user_id)
        body, elapsed = await chat(client, headers, user_id, session_id, f"Give one short English study tip. Nonce {run_id}")
        persisted = await client.get(f"/api/v1/chat/sessions/{session_id}/messages", headers=headers)
        persisted.raise_for_status()
        if len(persisted.json()) < 2:
            raise RuntimeError("chat messages were not persisted")
    return {
        "run_id": run_id,
        "user_id": user_id,
        "session_id": session_id,
        "mode": "smoke",
        "configured_key_count": config["configured_key_count"],
        "provider": "groq",
        "model": body["metadata"]["model_used"],
        "trace_path": body["metadata"].get("trace-cag", {}).get("path"),
        "latency": summarize_latencies([round(elapsed, 3)]),
        "persisted_message_count": len(persisted.json()),
        "passed": True,
    }


async def verify_persistence(base_url: str, config: dict[str, Any], source_report: Path) -> dict[str, Any]:
    source = json.loads(source_report.read_text(encoding="utf-8"))
    user_id = str(source["user_id"])
    session_id = str(source["session_id"])
    headers = {"Authorization": f"Bearer {make_access_token(user_id, config['secret_key'])}"}
    async with httpx.AsyncClient(base_url=base_url, timeout=60) as client:
        await wait_ready(client)
        response = await client.get(f"/api/v1/chat/sessions/{session_id}/messages", headers=headers)
        response.raise_for_status()
        count = len(response.json())
    if count < 2:
        raise RuntimeError("smoke session did not survive restart")
    return {"run_id": datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-persistence", "mode": "verify-persistence", "source_run_id": source["run_id"], "persisted_message_count": count, "passed": True}


async def run_benchmark(base_url: str, config: dict[str, Any]) -> dict[str, Any]:
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    user_id = f"e2e-{run_id}"
    headers = {"Authorization": f"Bearer {make_access_token(user_id, config['secret_key'])}"}
    health: list[float] = []
    cold: list[float] = []
    warm: list[float] = []
    concurrent: list[float] = []
    ttft: list[float] = []
    failures = 0
    failures_by_phase = {name: 0 for name in ("warmup", "warm", "cold", "concurrent", "stream", "cleanup")}
    started = time.perf_counter()
    started_utc = datetime.now(UTC).isoformat()
    models: set[str] = set()
    cache_routes: set[str] = set()
    warm_hashes: set[str] = set()
    cache_hits = 0
    concurrent_batch_throughput: list[float] = []
    concurrent_batch_slots: list[list[int]] = []
    session_ids: set[str] = set()
    cleanup_failures: list[str] = []
    client = httpx.AsyncClient(base_url=base_url, timeout=60)
    async with client, benchmark_session_cleanup(client, headers, session_ids, cleanup_failures):
        await wait_ready(client)
        for _ in range(100):
            response, elapsed = await _timed(client, "GET", "/health")
            response.raise_for_status()
            health.append(round(elapsed, 3))
        warm_message = f"Give one concise vocabulary tip. Cache nonce {run_id}"
        warm_session_ids = (f"cache-{run_id}-a", f"cache-{run_id}-b")
        for _ in range(5):
            try:
                body, _ = await analyze(client, headers, user_id, warm_session_ids[0], warm_message)
                metadata = body.get("metadata", {})
                models.update(str(value) for value in metadata.get("models_used", []))
            except Exception:
                failures += 1
                failures_by_phase["warmup"] += 1
        for index in range(30):
            try:
                body, elapsed = await analyze(client, headers, user_id, warm_session_ids[index % 2], warm_message)
                metadata = body.get("metadata", {})
                models.update(str(value) for value in metadata.get("models_used", []))
                cache_routes.add(str(metadata.get("path", "")))
                cache_hits += int(bool(metadata.get("cache_hit")))
                warm_hashes.add(hashlib.sha256(" ".join(body["tutor_response"].split()).encode()).hexdigest())
                warm.append(round(elapsed, 3))
            except Exception:
                failures += 1
                failures_by_phase["warm"] += 1
        for index in range(14):
            session_id = await create_session(client, headers, user_id)
            session_ids.add(session_id)
            try:
                _, elapsed = await chat(client, headers, user_id, session_id, f"Give one concise vocabulary tip. Nonce {run_id}-{index}")
                cold.append(round(elapsed, 3))
            except Exception:
                failures += 1
                failures_by_phase["cold"] += 1
        slot_offset = len(_groq_slot_ids(started_utc))
        for batch in range(5):
            async def sample(slot: int):
                session_id = await create_session(client, headers, user_id)
                session_ids.add(session_id)
                return await chat(client, headers, user_id, session_id, f"Give one concise grammar tip. Nonce {run_id}-{batch}-{slot}")
            batch_started = time.perf_counter()
            jobs = [sample(slot) for slot in range(7)]
            results = await asyncio.gather(*jobs, return_exceptions=True)
            successful = 0
            for result in results:
                if isinstance(result, Exception):
                    failures += 1
                    failures_by_phase["concurrent"] += 1
                else:
                    concurrent.append(round(result[1], 3))
                    successful += 1
            concurrent_batch_throughput.append(round(successful / (time.perf_counter() - batch_started), 3))
            observed = _groq_slot_ids(started_utc)
            batch_slots = observed[slot_offset:]
            concurrent_batch_slots.append(batch_slots)
            slot_offset = len(observed)
        for index in range(14):
            tick = time.perf_counter_ns()
            try:
                session_id = await create_session(client, headers, user_id)
                session_ids.add(session_id)
                async with client.stream(
                    "POST",
                    "/api/v1/lexi/stream",
                    headers=headers,
                    json={"user_id": user_id, "session_id": session_id, "message": f"One short tip. Nonce {run_id}-sse-{index}", "enable_tts": False},
                ) as response:
                    response.raise_for_status()
                    event = ""
                    async for line in response.aiter_lines():
                        if line.startswith("event:"):
                            event = line[6:].strip()
                        elif event == "chunk" and line.startswith("data:") and line[5:].strip():
                            ttft.append(round((time.perf_counter_ns() - tick) / 1_000_000, 3))
                            break
            except Exception:
                failures += 1
                failures_by_phase["stream"] += 1
    failures += len(cleanup_failures)
    failures_by_phase["cleanup"] += len(cleanup_failures)
    elapsed_seconds = time.perf_counter() - started
    total_chat = len(warm) + len(cold) + len(concurrent)
    slot_ids = _groq_slot_ids(started_utc)
    concurrent_rotation_ok = all(
        len(slots) >= 14
        and set(slots[:7]) == set(range(7))
        and set(slots[7:14]) == set(range(7))
        for slots in concurrent_batch_slots
    )
    gates = {
        "health_p95_le_500ms": nearest_rank(health, 0.95) <= 500,
        "warm_p95_le_2000ms": bool(warm) and nearest_rank(warm, 0.95) <= 2_000,
        "warm_cache_hits_30": cache_hits == 30 and len(warm_hashes) == 1,
        "cold_p95_le_12000ms": bool(cold) and nearest_rank(cold, 0.95) <= 12_000,
        "concurrent_samples_35": len(concurrent) == 35,
        "concurrent_p95_le_20000ms": bool(concurrent) and nearest_rank(concurrent, 0.95) <= 20_000,
        "concurrent_batch_throughput_ge_0_2rps": bool(concurrent_batch_throughput) and min(concurrent_batch_throughput) >= 0.2,
        "ttft_samples_14": len(ttft) == 14,
        "deadline_le_1200s": elapsed_seconds <= 1_200,
        "concurrent_seven_slot_rotation": concurrent_rotation_ok,
        "zero_failures": failures == 0,
    }
    return {
        "run_id": run_id,
        "mode": "benchmark",
        "timestamp_utc": datetime.now(UTC).isoformat(),
        "base_url": base_url,
        "configured_key_count": config["configured_key_count"],
        "environment": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
            "memory_bytes": os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") if hasattr(os, "sysconf") else None,
            **_docker_metadata(),
        },
        "health": summarize_latencies(health),
        "warm_cache": summarize_latencies(warm) if warm else {"count": 0, "method": "nearest_rank"},
        "warm_cache_hit_count": cache_hits,
        "warm_answer_variant_count": len(warm_hashes),
        "cold_chat": summarize_latencies(cold) if cold else {"count": 0},
        "concurrent_chat": summarize_latencies(concurrent) if concurrent else {"count": 0},
        "streaming_ttft": summarize_latencies(ttft) if ttft else {"count": 0},
        "throughput_rps": round(total_chat / elapsed_seconds, 3),
        "concurrent_batch_throughput_rps": concurrent_batch_throughput,
        "concurrent_batch_slot_ids": concurrent_batch_slots,
        "elapsed_seconds": round(elapsed_seconds, 3),
        "provider": "groq",
        "models": sorted(value for value in models if value),
        "cache_routes": sorted(value for value in cache_routes if value),
        "groq_slot_ids": slot_ids,
        "error_count": failures,
        "error_rate": failures / 98,
        "errors_by_phase": failures_by_phase,
        "gates": gates,
        "passed": all(gates.values()),
    }


async def async_main(args: argparse.Namespace) -> int:
    env = {**os.environ, **load_env(Path(args.env_file))}
    config = required_config(env)
    if args.command == "preflight":
        print(json.dumps({"configured_key_count": 7, "passed": True}))
        return 0
    base_url = validate_base_url(args.base_url)
    if args.command == "verify-persistence" and not args.source_report:
        raise ValueError("--source-report is required for verify-persistence")
    try:
        async with asyncio.timeout(1_210):
            if args.command == "smoke":
                report = await run_smoke(base_url, config)
            elif args.command == "verify-persistence":
                report = await verify_persistence(base_url, config, Path(args.source_report))
            else:
                report = await run_benchmark(base_url, config)
    except TimeoutError:
        report = {"run_id": datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-timeout", "mode": args.command, "base_url": base_url, "error_category": "deadline_exceeded", "passed": False}
    path = write_report(report, Path(args.report_dir), secrets=config["keys"] + [config["secret_key"]])
    print(json.dumps({"passed": report["passed"], "report": str(path)}))
    return 0 if report["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("preflight", "smoke", "benchmark", "verify-persistence"))
    parser.add_argument("--env-file", default=".env")
    parser.add_argument("--base-url", default="http://127.0.0.1:18001")
    parser.add_argument("--report-dir", default="reports/e2e")
    parser.add_argument("--source-report")
    return asyncio.run(async_main(parser.parse_args()))


if __name__ == "__main__":
    sys.exit(main())
