"""
LLM client layer — per-provider httpx connection pooling and rate-limit throttling.

Provides:
  _HTTPX_CLIENTS            — persistent AsyncClient pool (process-lifetime singletons)
  _get_httpx_client         — lazy factory
  _provider_rpm             — env-configurable requests-per-minute cap
  _parse_retry_after_seconds — safe parser for 429 Retry-After header
  _throttled_post_json      — rate-limited async POST with 429 backoff
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import Any, Dict, Optional

from api.services.trace_cag.provider_state import (
    _PROVIDER_QUEUE_LOCKS,
    _PROVIDER_NEXT_REQUEST_AT,
    _PROVIDER_LAST_WAIT_LOG_AT,
    _provider_is_disabled,
    _disable_provider,
)

logger = logging.getLogger(__name__)

# Persistent httpx clients per provider — reuses TCP/TLS connections across LLM calls.
# Created lazily on first use; not closed (process-lifetime singletons).
_HTTPX_CLIENTS: Dict[str, Any] = {}


def _get_httpx_client(provider: str) -> Any:
    """Return a long-lived httpx.AsyncClient for *provider*, creating it on first use."""
    if provider not in _HTTPX_CLIENTS:
        import httpx
        _HTTPX_CLIENTS[provider] = httpx.AsyncClient(
            limits=httpx.Limits(
                max_connections=20,
                max_keepalive_connections=10,
                keepalive_expiry=30,
            ),
        )
    return _HTTPX_CLIENTS[provider]


def _provider_rpm(provider: str) -> int:
    defaults = {
        "groq": 8,  # 1 active key × 8 safe RPM (TPM-bound)
        "gemini": 10,
        "ollama": 120,
    }
    raw = os.getenv(f"TRACECAG_{provider.upper()}_RPM", str(defaults.get(provider, 30)))
    try:
        return max(1, int(raw))
    except ValueError:
        return defaults.get(provider, 30)


def _parse_retry_after_seconds(raw_value: Optional[str]) -> float:
    if not raw_value:
        return 0.0
    try:
        return max(0.0, float(raw_value))
    except ValueError:
        return 0.0


async def _throttled_post_json(
    *,
    provider: str,
    url: str,
    payload: Dict[str, Any],
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 30.0,
    max_retries: int = 3,
) -> Any:
    """Queue provider requests and enforce a conservative per-minute cap.

    Rate-limit waits and 429 backoff sleeps happen OUTSIDE the lock so that a
    cooling key does not block other callers (e.g. a rotated key) from proceeding.
    The lock is held only during the actual HTTP round-trip + timestamp update.
    """
    # Allow benchmark mode to fast-fail immediately via TRACECAG_LLM_MAX_RETRIES=1
    env_retries = os.getenv("TRACECAG_LLM_MAX_RETRIES")
    if env_retries:
        try:
            max_retries = max(1, int(env_retries))
        except ValueError:
            pass

    lock = _PROVIDER_QUEUE_LOCKS.setdefault(provider, asyncio.Lock())
    response = None
    retry_after: float = 0.0

    for attempt in range(1, max_retries + 1):
        if _provider_is_disabled(provider):
            logger.warning(f"[llm_throttle] Skipping disabled provider={provider} (quota cooldown active)")
            return response

        rpm = _provider_rpm(provider)
        min_interval = 60.0 / max(rpm, 1)

        # --- Step 1: wait for rate-limit window OUTSIDE the lock ---
        # Poll in ≤1 s increments so env changes (key rotation clearing the
        # throttle state) are picked up quickly.
        while True:
            now = time.monotonic()
            wait = max(0.0, _PROVIDER_NEXT_REQUEST_AT.get(provider, now) - now)
            if wait <= 0:
                break
            last_log_at = _PROVIDER_LAST_WAIT_LOG_AT.get(provider, 0.0)
            # Log at most every 10s for long cooldowns to avoid flooding benchmark output.
            if (now - last_log_at) >= 10.0 or wait <= 3.0:
                logger.info(
                    f"[llm_throttle] Waiting {min(wait, 1.0):.2f}s before {provider} request "
                    f"to stay within {rpm} req/min (remaining {wait:.1f}s)"
                )
                _PROVIDER_LAST_WAIT_LOG_AT[provider] = now
            await asyncio.sleep(min(wait, 1.0))

        # --- Step 2: acquire lock only for HTTP request + timestamp update ---
        async with lock:
            # Re-check inside lock: another coroutine may have fired between our
            # pre-lock poll and now; if so, skip this attempt and let the outer
            # while loop wait again.
            now = time.monotonic()
            residual = max(0.0, _PROVIDER_NEXT_REQUEST_AT.get(provider, now) - now)
            if residual > 0:
                continue  # release lock immediately, re-enter wait loop

            client = _get_httpx_client(provider)
            response = await client.post(url, headers=headers, json=payload, timeout=timeout)

            _PROVIDER_NEXT_REQUEST_AT[provider] = time.monotonic() + min_interval

            if response.status_code != 429:
                return response

            retry_after = _parse_retry_after_seconds(response.headers.get("Retry-After"))
            error_text = str(getattr(response, "text", "") or "").lower()
            if any(marker in error_text for marker in ["tokens per day", "quota", "billing", "resource_exhausted"]):
                # Hard quota exhaustion should temporarily trip circuit breaker in benchmark runs.
                _disable_provider(provider, max(retry_after, 300.0))
            if retry_after <= 0:
                retry_after = max(min_interval * 2.0, 15.0)
            _PROVIDER_NEXT_REQUEST_AT[provider] = max(
                _PROVIDER_NEXT_REQUEST_AT.get(provider, time.monotonic()),
                time.monotonic() + retry_after,
            )

        # --- Step 3: 429 backoff sleep OUTSIDE the lock ---
        # Releasing the lock here lets a rotated key (which clears
        # _PROVIDER_NEXT_REQUEST_AT) proceed immediately without waiting.
        logger.warning(
            f"[llm_throttle] {provider} returned 429 on attempt {attempt}/{max_retries}; "
            f"backing off for {retry_after:.1f}s"
        )
        if attempt < max_retries:
            await asyncio.sleep(retry_after)

    return response
