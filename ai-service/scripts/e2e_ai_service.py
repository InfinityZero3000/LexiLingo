#!/usr/bin/env python3
"""Production-like AI-service smoke and latency checks with redacted reports."""
from __future__ import annotations

import argparse
import asyncio
import json
import math
import os
import platform
import re
import subprocess
import sys
import time
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

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
    run_id = str(report.get("run_id") or datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ"))
    path = directory / f"{run_id}.json"
    pending = path.with_suffix(".json.tmp")
    pending.write_text(serialized + "\n", encoding="utf-8")
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
        return {"images": json.loads(output) if output.strip() else []}
    except Exception as exc:
        return {"images_error": type(exc).__name__}


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


async def chat(client: httpx.AsyncClient, headers: dict[str, str], user_id: str, session_id: str, message: str) -> tuple[dict[str, Any], float]:
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
    if "groq" not in model.lower():
        raise RuntimeError("response metadata does not identify Groq")
    return body, elapsed


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
        "mode": "smoke",
        "configured_key_count": config["configured_key_count"],
        "provider": "groq",
        "model": body["metadata"]["model_used"],
        "trace_path": body["metadata"].get("trace-cag", {}).get("path"),
        "latency": summarize_latencies([round(elapsed, 3)]),
        "persisted_message_count": len(persisted.json()),
        "passed": True,
    }


async def run_benchmark(base_url: str, config: dict[str, Any]) -> dict[str, Any]:
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    user_id = f"e2e-{run_id}"
    headers = {"Authorization": f"Bearer {make_access_token(user_id, config['secret_key'])}"}
    health: list[float] = []
    cold: list[float] = []
    failures = 0
    async with httpx.AsyncClient(base_url=base_url, timeout=60) as client:
        await wait_ready(client)
        for _ in range(100):
            response, elapsed = await _timed(client, "GET", "/health")
            response.raise_for_status()
            health.append(round(elapsed, 3))
        for index in range(14):
            session_id = await create_session(client, headers, user_id)
            try:
                _, elapsed = await chat(client, headers, user_id, session_id, f"Give one concise vocabulary tip. Nonce {run_id}-{index}")
                cold.append(round(elapsed, 3))
            except Exception:
                failures += 1
    gates = {
        "health_p95_le_500ms": nearest_rank(health, 0.95) <= 500,
        "cold_p95_le_12000ms": bool(cold) and nearest_rank(cold, 0.95) <= 12_000,
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
            **_docker_metadata(),
        },
        "health": summarize_latencies(health),
        "cold_chat": summarize_latencies(cold) if cold else {"count": 0},
        "error_count": failures,
        "error_rate": failures / 14,
        "gates": gates,
        "passed": all(gates.values()),
    }


async def async_main(args: argparse.Namespace) -> int:
    env = {**os.environ, **load_env(Path(args.env_file))}
    config = required_config(env)
    if args.command == "preflight":
        print(json.dumps({"configured_key_count": 7, "passed": True}))
        return 0
    report = await (run_smoke(args.base_url, config) if args.command == "smoke" else run_benchmark(args.base_url, config))
    path = write_report(report, Path(args.report_dir), secrets=config["keys"] + [config["secret_key"]])
    print(json.dumps({"passed": report["passed"], "report": str(path)}))
    return 0 if report["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("preflight", "smoke", "benchmark"))
    parser.add_argument("--env-file", default=".env")
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--report-dir", default="reports/e2e")
    return asyncio.run(async_main(parser.parse_args()))


if __name__ == "__main__":
    sys.exit(main())
