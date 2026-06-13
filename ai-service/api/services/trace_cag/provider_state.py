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
