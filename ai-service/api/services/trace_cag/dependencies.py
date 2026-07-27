"""Pure dependency-trace primitives for state-certified cache artifacts."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from typing import Iterable


POLICY_VERSION_TOKEN = "policy_v1"
KG_VERSION_TOKEN = "kg_schema_v1"


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
    return {
        "key": key,
        "kind": kind,
        "version": version,
        "provenance": provenance,
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
