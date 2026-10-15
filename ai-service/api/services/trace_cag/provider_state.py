"""
Per-provider rate-limit and health state.

These dicts are module-level singletons (process-scoped).  All provider helpers
that read or mutate state live here so benchmark and prod code can import them
without creating a circular dependency with nodes_v2.
"""

import asyncio
import time
from typing import Dict

_PROVIDER_QUEUE_LOCKS: Dict[str, asyncio.Lock] = {}
_PROVIDER_NEXT_REQUEST_AT: Dict[str, float] = {}
_PROVIDER_LAST_WAIT_LOG_AT: Dict[str, float] = {}
_PROVIDER_DISABLED_UNTIL: Dict[str, float] = {}


def _provider_cooldown_seconds(provider: str) -> float:
    now = time.monotonic()
    return max(0.0, _PROVIDER_NEXT_REQUEST_AT.get(provider, now) - now)


def _provider_is_disabled(provider: str) -> bool:
    now = time.monotonic()
    return _PROVIDER_DISABLED_UNTIL.get(provider, 0.0) > now


def _disable_provider(provider: str, duration_seconds: float) -> None:
    if duration_seconds <= 0:
        return
    now = time.monotonic()
    _PROVIDER_DISABLED_UNTIL[provider] = max(
        _PROVIDER_DISABLED_UNTIL.get(provider, 0.0),
        now + duration_seconds,
    )


# Rolling 60s record of (timestamp, estimated_tokens) per provider key.
#
# This duplicates what groq_key_pool does -- deliberately. The pool only
# enforces a token budget when its Redis backend is up; with Redis down it
# degrades to plain round-robin (`_fallback_cursor`) and ignores
# estimated_tokens entirely. The benchmark runs without Redis, so the pool
# cannot pace it: passing true token counts to the pool changed nothing, and
# 6 of 29 samples still failed on Groq's input-tokens-per-minute limit.
_PROVIDER_TOKEN_WINDOW: Dict[str, list] = {}
