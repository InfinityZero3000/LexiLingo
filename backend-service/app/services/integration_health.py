"""Liveness probes for the third-party integrations features depend on.

Every guard in the codebase checks a key by truthiness, so a revoked key
passes configuration and fails only when a learner triggers the feature. That
is how the content agent — the sole path that generates course content — sat
broken while production served no real courses at all. A key can only be
proven alive by calling the provider, so this probes on demand.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import os
import time
from typing import Any, Callable

import httpx

logger = logging.getLogger(__name__)

TIMEOUT = 12.0


class IntegrationResult(dict):
    pass


def _result(name: str, env_var: str, feature: str, state: str, detail: str = "") -> dict:
    return {
        "integration": name,
        "env_var": env_var,
        "feature": feature,
        "state": state,          # ok | dead | not_configured | unreachable
        "detail": detail[:160],
    }


async def _probe(
    client: httpx.AsyncClient,
    name: str,
    env_var: str,
    feature: str,
    call: Callable[[httpx.AsyncClient, str], Any],
    *,
    required: bool = True,
) -> dict:
    key = (os.getenv(env_var) or "").strip()
    if not key:
        return _result(
            name, env_var, feature,
            "not_configured" if required else "disabled",
            "no value set",
        )
    try:
        resp = await call(client, key)
    except Exception as exc:  # noqa: BLE001
        return _result(name, env_var, feature, "unreachable", str(exc))

    status = getattr(resp, "status_code", 0)
    # 429 means the credential is valid and merely throttled.
    if status in (200, 429):
        return _result(name, env_var, feature, "ok")
    return _result(name, env_var, feature, "dead", f"HTTP {status}: {resp.text[:110]}")


async def _youtube(c, k):
    return await c.get(
        "https://www.googleapis.com/youtube/v3/search",
        params={"part": "snippet", "q": "english", "maxResults": 1, "key": k},
    )


async def _gemini(c, k):
    return await c.post(
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"gemini-2.5-flash:generateContent?key={k}",
        json={"contents": [{"parts": [{"text": "ping"}]}]},
    )


async def _newsapi(c, k):
    return await c.get(
        "https://newsapi.org/v2/top-headlines",
        params={"country": "us", "pageSize": 1}, headers={"X-Api-Key": k},
    )


async def _podcastindex(c, k):
    secret = (os.getenv("PODCASTINDEX_SECRET") or "").strip()
    stamp = str(int(time.time()))
    digest = hashlib.sha1((k + secret + stamp).encode()).hexdigest()
    return await c.get(
        "https://api.podcastindex.org/api/1.0/search/byterm",
        params={"q": "english"},
        headers={
            "X-Auth-Key": k, "X-Auth-Date": stamp, "Authorization": digest,
            "User-Agent": "LexiLingo/1.0",
        },
    )


async def _groq_pool(client: httpx.AsyncClient) -> dict:
    raw = (os.getenv("GROQ_API_KEYS") or os.getenv("GROQ_API_KEY") or "").strip()
    _GROQ_MODEL = os.getenv("GROQ_MODEL", "qwen/qwen3.6-27b")
    keys = [k.strip() for k in raw.split(",") if k.strip()]
    if not keys:
        return _result("groq", "GROQ_API_KEYS", "chat, dịch, TRACE-CAG",
                       "not_configured", "no value set")

    async def one(k: str) -> bool:
        try:
            r = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {k}"},
                json={"model": _GROQ_MODEL,
                      "messages": [{"role": "user", "content": "ping"}],
                      "max_tokens": 3,
                      # qwen spends the 3-token budget on reasoning and answers
                      # nothing without this, which reads as a dead key.
                      **({"reasoning_effort": "none"} if "qwen" in _GROQ_MODEL else {})},
            )
            return r.status_code in (200, 429)
        except Exception:  # noqa: BLE001
            return False

    alive = sum(await asyncio.gather(*(one(k) for k in keys)))
    # A partially dead pool still serves traffic but has lost its headroom,
    # so report it rather than letting it look healthy.
    state = "ok" if alive == len(keys) else ("degraded" if alive else "dead")
    return _result("groq", "GROQ_API_KEYS", "chat, dịch, TRACE-CAG", state,
                   f"{alive}/{len(keys)} keys alive")


async def check_all() -> dict:
    """Probe every integration concurrently. Never raises."""
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        results = await asyncio.gather(
            _probe(client, "youtube", "YOUTUBE_API_KEY",
                   "kênh / video / phụ đề", _youtube),
            _probe(client, "gemini", "GEMINI_API_KEY",
                   "content-agent sinh khoá học", _gemini),
            _probe(client, "newsapi", "NEWSAPI_KEY", "tin tức", _newsapi),
            _probe(client, "podcastindex", "PODCASTINDEX_KEY", "podcast",
                   _podcastindex),
            _groq_pool(client),
        )

    broken = [r for r in results if r["state"] in ("dead", "unreachable")]
    for r in broken:
        logger.error(
            "Integration %s (%s) is %s — feature '%s' is down: %s",
            r["integration"], r["env_var"], r["state"], r["feature"], r["detail"],
        )

    return {
        "healthy": not broken,
        "checked": len(results),
        "broken": len(broken),
        "integrations": results,
    }
