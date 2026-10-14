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
import hashlib
import logging
import os
import time
from typing import Any, Dict, Optional

from api.services.trace_cag.provider_state import (
    _PROVIDER_QUEUE_LOCKS,
    _PROVIDER_NEXT_REQUEST_AT,
    _PROVIDER_LAST_WAIT_LOG_AT,
    _PROVIDER_TOKEN_WINDOW,
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
            http2=True,
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


def _is_qwen_model(model: str) -> bool:
    return "qwen" in model.lower()


def _qwen_no_think_messages(model: str, messages: list) -> list:
    """Legacy qwen3 (e.g. qwen3-32b) prefix trick to suppress <think> reasoning.
    Kept for back-compat with older Qwen deployments; verified (2026-08-16) that
    it no longer suppresses thinking on qwen3.6 on Groq — see
    _qwen_reasoning_overrides for the control that does."""
    if not _is_qwen_model(model):
        return messages
    patched = list(messages)
    for i, msg in enumerate(patched):
        if msg.get("role") == "user":
            patched[i] = {**msg, "content": f"/no_think\n{msg['content']}"}
            break
    return patched


def _qwen_reasoning_overrides(model: str) -> Dict[str, Any]:
    """Groq-side reasoning control for current Qwen models. Verified directly
    against the Groq API (2026-08-16): qwen3.6-27b ignores the "/no_think"
    message-prefix trick and keeps emitting <think> blocks, but honors
    reasoning_effort="none" in the request body (finish_reason="stop", clean
    answer, no thinking tokens)."""
    return {"reasoning_effort": "none"} if _is_qwen_model(model) else {}


# Values that actually enable thinking, probed against Groq 2026-10-10 on
# qwen/qwen3.8-27b: "default" is a no-op indistinguishable from "none" (5
# completion tokens, empty reasoning), while low/medium/high each produce ~89
# completion tokens and a 351-386 char `message.reasoning`. On this model the
# trace arrives in that separate field and `content` stays clean, so the
# JSON-parsing hazard that `reasoning_effort="none"` exists for does not apply.
QWEN_THINKING_EFFORTS = frozenset({"low", "medium", "high"})


def _parse_retry_after_seconds(raw_value: Optional[str]) -> float:
    if not raw_value:
        return 0.0
    try:
        return max(0.0, float(raw_value))
    except ValueError:
        return 0.0


def _provider_tpm(provider: str) -> int:
    """Input tokens per minute per key; 0 (the default) means no in-process pacing.

    Opt-in, because pacing sleeps inside every caller of `_throttled_post_json`
    and production already paces through groq_key_pool. The benchmark switches it
    on (BenchmarkConfig.apply_environment): it runs without Redis, where the pool
    degrades to round-robin, and Groq's 429 names the limit it then hits:
    "input tokens per minute (ITPM): Limit 7000". Use 6000 for headroom.
    """
    try:
        return max(0, int(os.getenv(f"TRACECAG_{provider.upper()}_TPM", "0")))
    except ValueError:
        return 0


def _estimate_payload_tokens(payload: Dict[str, Any]) -> int:
    chars = sum(len(str(m.get("content") or "")) for m in payload.get("messages") or [])
    return (chars // 4) + int(payload.get("max_tokens") or 256)


def _token_window_wait(state_key: str, provider: str, tokens: int) -> float:
    """Seconds to wait so `tokens` fits inside this key's per-minute budget."""
    budget = _provider_tpm(provider)
    if budget <= 0:
        return 0.0
    now = time.monotonic()
    window = [(t, n) for t, n in _PROVIDER_TOKEN_WINDOW.get(state_key, []) if now - t < 60.0]
    _PROVIDER_TOKEN_WINDOW[state_key] = window
    spent = sum(n for _, n in window)
    if spent + tokens <= budget:
        return 0.0
    need = spent + tokens - budget
    freed = 0
    for timestamp, n in window:
        freed += n
        if freed >= need:
            return max(0.0, 60.0 - (now - timestamp))
    return 60.0


def _token_window_record(state_key: str, tokens: int) -> None:
    _PROVIDER_TOKEN_WINDOW.setdefault(state_key, []).append((time.monotonic(), tokens))


# Upper bound on a per-minute 429 backoff. Daily/quota 429s take the
# _disable_provider path instead, so capping here cannot mask an exhausted key.
_TPM_BACKOFF_CAP_SECONDS = float(os.getenv("TRACECAG_TPM_BACKOFF_CAP", "30"))


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

    # A qwen model without this override streams/returns <think> prose instead of
    # the answer, which every JSON caller here then fails to parse.
    if provider == "groq" and "reasoning_effort" not in payload:
        # Only when the caller has not asked for a specific effort. This used to
        # overwrite it unconditionally, so a caller could not turn reasoning on
        # even deliberately -- and the benchmark reader answers multi-hop
        # questions, which is the one task where thinking should earn its cost.
        payload = {**payload, **_qwen_reasoning_overrides(str(payload.get("model") or ""))}

    state_key = provider
    if provider == "groq" and headers and headers.get("Authorization"):
        fingerprint = hashlib.sha256(headers["Authorization"].encode()).hexdigest()[:16]
        state_key = f"groq:{fingerprint}"
    lock = _PROVIDER_QUEUE_LOCKS.setdefault(state_key, asyncio.Lock())
    response = None
    retry_after: float = 0.0

    for attempt in range(1, max_retries + 1):
        if _provider_is_disabled(state_key):
            logger.warning(f"[llm_throttle] Skipping disabled provider={provider} (quota cooldown active)")
            return response

        rpm = _provider_rpm(provider)
        min_interval = 60.0 / max(rpm, 1)
        est_tokens = _estimate_payload_tokens(payload)

        # Wait outside the lock, then retry admission without consuming an HTTP
        # retry when another coroutine reserved the next provider slot first.
        while True:
            now = time.monotonic()
            wait = max(0.0, _PROVIDER_NEXT_REQUEST_AT.get(state_key, now) - now)
            # Pace on tokens too: at 8 req/min a 700-token arm stays inside the
            # budget while a 3,900-token arm exceeds it on the second request.
            wait = max(wait, _token_window_wait(state_key, provider, est_tokens))
            if wait > 0:
                last_log_at = _PROVIDER_LAST_WAIT_LOG_AT.get(state_key, 0.0)
                if (now - last_log_at) >= 10.0 or wait <= 3.0:
                    logger.info(
                        f"[llm_throttle] Waiting {min(wait, 1.0):.2f}s before {provider} request "
                        f"to stay within {rpm} req/min (remaining {wait:.1f}s)"
                    )
                    _PROVIDER_LAST_WAIT_LOG_AT[state_key] = now
                await asyncio.sleep(min(wait, 1.0))
                continue

            async with lock:
                now = time.monotonic()
                if _PROVIDER_NEXT_REQUEST_AT.get(state_key, now) > now:
                    continue

                client = _get_httpx_client(provider)
                response = await client.post(url, headers=headers, json=payload, timeout=timeout)
                _token_window_record(state_key, est_tokens)
                _PROVIDER_NEXT_REQUEST_AT[state_key] = time.monotonic() + min_interval

                if response.status_code != 429:
                    return response

                retry_after = _parse_retry_after_seconds(response.headers.get("Retry-After"))
                error_text = str(getattr(response, "text", "") or "").lower()
                daily = any(marker in error_text for marker in ["tokens per day", "requests per day", "quota", "billing", "resource_exhausted"])
                if daily:
                    _disable_provider(state_key, max(retry_after, 300.0))
                if retry_after <= 0:
                    retry_after = max(min_interval * 2.0, 15.0)
                elif not daily:
                    # Groq's per-minute token bucket refills continuously --
                    # measured 10-21s to recover after a 1.4k-token request --
                    # but its Retry-After on a TPM breach can say 246s. Callers
                    # here are sequential, so one such header stalled an entire
                    # 500-question run: 2h36m of wall clock for 75s of CPU and
                    # no output. A per-minute limit cannot need more than the
                    # window itself; a daily limit is the branch above, which
                    # disables the key instead of sleeping on it.
                    retry_after = min(retry_after, _TPM_BACKOFF_CAP_SECONDS)
                _PROVIDER_NEXT_REQUEST_AT[state_key] = max(
                    _PROVIDER_NEXT_REQUEST_AT.get(state_key, time.monotonic()),
                    time.monotonic() + retry_after,
                )
                break

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
