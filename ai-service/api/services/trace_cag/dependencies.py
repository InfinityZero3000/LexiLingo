"""Pure dependency-trace primitives for state-certified cache artifacts."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from typing import Iterable


# Canonical schema/policy version integers — single source of truth shared by
# the L1 hard-gate mismatch check (cache_utils._GRAPH_SCHEMA_VERSION /
# _POLICY_VERSION) and the dependency/reverse-invalidation certificate system
# below. Bump these (not a duplicate literal elsewhere) when a KG
# contamination fix or policy/prompt change must invalidate every certified
# cache artifact. Previously these drifted independently (v1 here vs v2 in
# cache_utils.py), which silently defeated certificate-based invalidation.
GRAPH_SCHEMA_VERSION = 2
POLICY_SCHEMA_VERSION = 2

POLICY_VERSION_TOKEN = f"policy_v{POLICY_SCHEMA_VERSION}"
KG_VERSION_TOKEN = f"kg_schema_v{GRAPH_SCHEMA_VERSION}"


@dataclass(frozen=True, order=True)
class DependencyEvent:
    key: str
    kind: str
    version: str
    provenance: str
    required: bool = True


def stable_version_token(value: object, *, prefix: str) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)
    return f"{prefix}:{hashlib.sha256(payload.encode('utf-8')).hexdigest()}"


def dependency_record(
    key: str,
    kind: str,
    version: str,
    provenance: str,
    *,
    required: bool = True,
) -> dict[str, object]:
    # Coerce here, once, rather than trusting every caller: a non-str version
    # (e.g. a mock object in tests, or a future caller passing an int/enum)
    # would otherwise round-trip through dataclasses.asdict/json with an
    # inconsistent representation and silently break dependency-token
    # comparisons in invalidation.py's observe/recheck functions.
    return {
        "key": str(key),
        "kind": str(kind),
        "version": str(version),
        "provenance": str(provenance),
        "required": required,
    }


def compile_dependency_trace(events: Iterable[DependencyEvent]) -> tuple[DependencyEvent, ...]:
    """Return a deterministic trace or reject an incomplete/inconsistent read."""
    by_key: dict[str, DependencyEvent] = {}
    for event in events:
        if event.required and not event.version:
            raise ValueError(f"missing required dependency token: {event.key}")
        previous = by_key.get(event.key)
        if previous is not None and previous.version != event.version:
            raise ValueError(f"conflicting dependency versions: {event.key}")
        if previous is None or (event.required and not previous.required):
            by_key[event.key] = event
    return tuple(sorted(by_key.values(), key=lambda event: event.key))
