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


def _int_or_zero(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def usage_counts(usage: Dict[str, Any]) -> Dict[str, int]:
    """Token counts from an OpenAI, Groq, Gemini or Ollama usage object; {} when it reports none."""
    prompt = _int_or_zero(usage.get("prompt_tokens") or usage.get("promptTokenCount") or usage.get("prompt_eval_count"))
    completion = _int_or_zero(usage.get("completion_tokens") or usage.get("candidatesTokenCount") or usage.get("eval_count"))
    total = _int_or_zero(usage.get("total_tokens") or usage.get("totalTokenCount"))
    details = usage.get("prompt_tokens_details") or usage.get("prompt_token_details") or usage.get("input_token_details") or {}
    cached = _int_or_zero(usage.get("cached_tokens") or details.get("cached_tokens"))
    if not total and (prompt or completion):
        total = prompt + completion
    if not (prompt or completion or total or cached):
        return {}
    return {"prompt_tokens": prompt, "completion_tokens": completion, "total_tokens": total, "cached_tokens": cached}


def provider_usage(payload: Dict[str, Any]) -> Optional[Dict[str, int]]:
    """Usage a body or stream chunk reports: `usage`, Groq's `x_groq.usage` or Gemini's `usageMetadata`."""
    usage = payload.get("usage") or (payload.get("x_groq") or {}).get("usage")
    if not usage and isinstance(payload.get("usageMetadata"), dict):
        meta = payload["usageMetadata"]
        usage = {**meta, "cached_tokens": meta.get("cachedContentTokenCount")}
    counts = usage_counts(usage) if isinstance(usage, dict) else {}
    return {key: counts[key] for key in ("prompt_tokens", "completion_tokens", "cached_tokens")} if counts else None


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


def _is_daily_limit(error_text: str) -> bool:
    """A 429 that will not clear within the minute, so the provider is disabled rather than retried.

    Groq's per-minute 429s end with "Need more tokens? Upgrade to Dev Tier today at
    https://console.groq.com/settings/billing". Matching "billing" against the whole body took every
    OTPM/ITPM hit for a daily limit and switched the provider off for 5+ minutes, so one burst turned
    every later request into "no response". Only the text before that sentence describes the limit.
    """
    described = error_text.lower().split("need more tokens")[0]
    return any(marker in described for marker in ["tokens per day", "requests per day", "quota", "billing", "resource_exhausted"])


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


def _token_window_record(state_key: str, provider: str, tokens: int) -> None:
    if _provider_tpm(provider) <= 0:
        return  # nothing prunes the window while pacing is off, so it would grow for the life of the process
    _PROVIDER_TOKEN_WINDOW.setdefault(state_key, []).append((time.monotonic(), tokens))


# Upper bound on a per-minute 429 backoff. Daily/quota 429s take the
# _disable_provider path instead, so capping here cannot mask an exhausted key.
_TPM_BACKOFF_CAP_SECONDS = float(os.getenv("TRACECAG_TPM_BACKOFF_CAP", "30"))


def groq_refusal_seconds(status_code: int, retry_after: Optional[str], body: str) -> float:
    """How long to leave a Groq key alone after this answer; 0 when the key is not the problem."""
    if status_code == 401:
        return 3600.0
    if status_code == 403:
        return 60.0  # may be the network or the account, not this key: never sideline the pool for long
    if status_code != 429:
        return 0.0
    asked = _parse_retry_after_seconds(retry_after)
    if _is_daily_limit(body):
        return max(asked, 300.0)
    return min(asked or 15.0, _TPM_BACKOFF_CAP_SECONDS)


def estimate_chat_tokens(messages: list, max_tokens: int) -> int:
    """Prompt plus reply: the pool debits it against a per-minute budget that counts both."""
    return max_tokens + sum(len(str(m.get("content") or "")) for m in messages) // 4


async def groq_chat(
    messages: list,
    *,
    max_tokens: int,
    temperature: float = 0.3,
    timeout: float = 6.0,
    model: Optional[str] = None,
) -> Optional[str]:
    """One short Groq completion, or None. Never raises: callers own a fallback."""
    from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage, resolve_groq_model

    model = model or resolve_groq_model()
    estimate = estimate_chat_tokens(messages, max_tokens)
    try:
        async with asyncio.timeout(timeout):
            key = await get_available_groq_key(estimated_tokens=estimate)
            if not key:
                return None
            response = await _throttled_post_json(
                provider="groq",
                url="https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                payload={
                    "model": model,
                    "messages": messages,
                    "max_tokens": max_tokens,
                    "temperature": temperature,
                    **_qwen_reasoning_overrides(model),
                },
                timeout=timeout,
            )
            if response is None or response.status_code != 200:
                return None
            data = response.json()
            await record_groq_key_usage(
                groq_key_used(response, key), int((data.get("usage") or {}).get("total_tokens") or estimate)
            )
            return str(data["choices"][0]["message"]["content"] or "").strip() or None
    except Exception as exc:
        logger.warning("[groq_chat] %s: %s", type(exc).__name__, exc)
        return None


def groq_key_used(response: Any, default: str) -> str:
    """The key that answered, which is not the caller's when a 429 rotated it."""
    extensions = getattr(response, "extensions", None)
    return extensions.get("groq_key", default) if isinstance(extensions, dict) else default


async def _another_groq_key(provider: str, tokens: int) -> Optional[str]:
    """A free key to retry on. Only with the Redis pool: benchmarks run without it and pace one key on purpose."""
    from api.core.groq_key_pool import get_available_groq_key, get_groq_key_pool

    if provider != "groq" or get_groq_key_pool() is None:
        return None
    return await get_available_groq_key(estimated_tokens=tokens)


def _bearer_key(headers: Optional[Dict[str, str]]) -> str:
    return str((headers or {}).get("Authorization") or "").removeprefix("Bearer ").strip()


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

    def _state_key() -> str:
        if provider == "groq" and headers and headers.get("Authorization"):
            return f"groq:{hashlib.sha256(headers['Authorization'].encode()).hexdigest()[:16]}"
        return provider

    state_key = _state_key()
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
                _token_window_record(state_key, provider, est_tokens)
                _PROVIDER_NEXT_REQUEST_AT[state_key] = time.monotonic() + min_interval

                refused = (
                    groq_refusal_seconds(
                        response.status_code, response.headers.get("Retry-After"),
                        str(getattr(response, "text", "") or ""),
                    )
                    if provider == "groq" and response.status_code in (401, 403, 429) else 0.0
                )
                if refused:
                    from api.core.groq_key_pool import park_groq_key

                    park_groq_key(_bearer_key(headers), refused)

                if response.status_code != 429:
                    if response.status_code == 200 and provider == "groq" and isinstance(
                        getattr(response, "extensions", None), dict
                    ):
                        response.extensions["groq_key"] = _bearer_key(headers)
                    return response

                retry_after = _parse_retry_after_seconds(response.headers.get("Retry-After"))
                daily = _is_daily_limit(str(getattr(response, "text", "") or ""))
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
            rotated = await _another_groq_key(provider, est_tokens)
            if rotated:
                # Waiting out one key's window while others are free cost the turn its whole deadline.
                headers = {**(headers or {}), "Authorization": f"Bearer {rotated}"}
                state_key = _state_key()
                lock = _PROVIDER_QUEUE_LOCKS.setdefault(state_key, asyncio.Lock())
                continue
            await asyncio.sleep(retry_after)

    return response
