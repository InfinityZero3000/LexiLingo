"""Reverse dependency index for targeted TRACE-CAG artifact invalidation."""

from __future__ import annotations

from collections import defaultdict
import hashlib
from typing import Iterable, Mapping, Any


_MEM_REVERSE_INDEX: dict[str, set[str]] = defaultdict(set)
_MEM_ARTIFACT_DEPENDENCIES: dict[str, set[str]] = {}
_MEM_DEPENDENCY_TOKENS: dict[str, str] = {}


def register_reverse_edges(artifact_key: str, dependencies: Iterable[Mapping[str, Any]]) -> None:
    remove_reverse_edges(artifact_key)
    keys = {str(item.get("key") or "") for item in dependencies}
    keys.discard("")
    _MEM_ARTIFACT_DEPENDENCIES[artifact_key] = keys
    for dependency_key in keys:
        _MEM_REVERSE_INDEX[dependency_key].add(artifact_key)


def remove_reverse_edges(artifact_key: str) -> None:
    for dependency_key in _MEM_ARTIFACT_DEPENDENCIES.pop(artifact_key, set()):
        artifacts = _MEM_REVERSE_INDEX.get(dependency_key)
        if artifacts is None:
            continue
        artifacts.discard(artifact_key)
        if not artifacts:
            _MEM_REVERSE_INDEX.pop(dependency_key, None)


def pop_dependent_artifacts(dependency_key: str) -> set[str]:
    artifacts = set(_MEM_REVERSE_INDEX.get(dependency_key, set()))
    for artifact_key in artifacts:
        remove_reverse_edges(artifact_key)
    return artifacts


def clear_reverse_index() -> None:
    _MEM_REVERSE_INDEX.clear()
    _MEM_ARTIFACT_DEPENDENCIES.clear()
    _MEM_DEPENDENCY_TOKENS.clear()


def observe_dependency_tokens(dependencies: Iterable[Mapping[str, Any]]) -> None:
    for item in dependencies:
        key = str(item.get("key") or "")
        version = str(item.get("version") or "")
        if key and version:
            # A stale artifact must never roll a token back after a mutation.
            _MEM_DEPENDENCY_TOKENS.setdefault(key, version)


def set_dependency_token(dependency_key: str, version: str) -> set[str]:
    """Publish a mutation token and detach every dependent artifact."""
    _MEM_DEPENDENCY_TOKENS[dependency_key] = version
    return pop_dependent_artifacts(dependency_key)


def recheck_dependency_snapshot(
    dependencies: Iterable[Mapping[str, Any]],
) -> tuple[bool, tuple[str, ...]]:
    reasons: list[str] = []
    for item in dependencies:
        if not bool(item.get("required", True)):
            continue
        key = str(item.get("key") or "")
        expected = str(item.get("version") or "")
        current = _MEM_DEPENDENCY_TOKENS.get(key)
        if not key or not expected:
            reasons.append("invalid_dependency_snapshot")
        elif current is None:
            reasons.append(f"dependency_token_unavailable:{key}")
        elif current != expected:
            reasons.append(f"snapshot_changed_before_serve:{key}")
    return not reasons, tuple(reasons)


def _redis_reverse_key(dependency_key: str) -> str:
    digest = hashlib.sha256(dependency_key.encode("utf-8")).hexdigest()
    return f"v1:tracecag:reverse:{digest}"


async def register_reverse_edges_redis(
    redis_client: Any,
    artifact_key: str,
    dependencies: Iterable[Mapping[str, Any]],
    ttl: int,
) -> None:
    for item in dependencies:
        dependency_key = str(item.get("key") or "")
        if not dependency_key:
            continue
        reverse_key = _redis_reverse_key(dependency_key)
        await redis_client.sadd(reverse_key, artifact_key)
        await redis_client.expire(reverse_key, ttl)


async def pop_dependent_artifacts_redis(redis_client: Any, dependency_key: str) -> set[str]:
    reverse_key = _redis_reverse_key(dependency_key)
    values = await redis_client.smembers(reverse_key)
    await redis_client.delete(reverse_key)
    return {
        value.decode("utf-8") if isinstance(value, bytes) else str(value)
        for value in values
    }
