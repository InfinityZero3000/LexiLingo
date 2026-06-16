"""Source catalog resolution for licensed content ETL."""

from __future__ import annotations

import logging
from typing import Any

from pydantic import ValidationError

from app.schemas.content_agent import SourceSnapshotDescriptor
from app.services.content_agent_client import ContentAgentClient

logger = logging.getLogger(__name__)

# Admin uploads are job-local and never need AI-service snapshot pinning.
_VIRTUAL_SOURCES: frozenset[str] = frozenset({"admin_upload"})
_SOURCE_ALIASES: dict[str, str] = {"existing_cefr": "cefr_j"}


class SourceResolutionError(ValueError):
    """Raised when one or more sources cannot be pinned to an approved snapshot."""


async def get_source_catalog(client: ContentAgentClient) -> list[dict[str, Any]]:
    """Fetch approved source snapshots from the AI service.

    Returns the list of snapshot descriptors as returned by
    ``GET /api/v1/internal/content-agent/sources``.
    """
    return await client.list_sources()


def resolve_snapshots(
    sources: list[str],
    catalog: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Pin snapshot IDs for *sources* against the live *catalog*.

    Rules (all applied together; all errors collected before raising):

    * Every non-virtual source in *sources* must appear in *catalog*.
    * Every matched snapshot must have ``status == "active"``.
    * Every matched snapshot must carry a non-empty ``snapshot_id``.

    Returns the list of pinned descriptor dicts for non-virtual sources only.
    Virtual sources (``admin_upload``, ``existing_cefr``) are skipped — they
    are handled separately by the caller and never looked up in the catalog.

    Raises :class:`SourceResolutionError` with a collected message when any
    source cannot be resolved.
    """
    by_id: dict[str, SourceSnapshotDescriptor] = {}
    invalid_by_id: dict[str, str] = {}
    for entry in catalog:
        source_id = str(entry.get("source_id") or "")
        entry_status = str(entry.get("status") or "")
        if source_id and entry_status != "active":
            invalid_by_id[source_id] = (
                f"status {entry_status!r}, expected 'active'"
            )
            continue
        try:
            descriptor = SourceSnapshotDescriptor.model_validate(entry)
        except ValidationError as exc:
            if source_id:
                invalid_by_id[source_id] = "; ".join(
                    ".".join(str(part) for part in error["loc"])
                    for error in exc.errors()
                )
            logger.warning("Ignoring malformed content-agent source descriptor")
            continue
        if not descriptor.enabled:
            invalid_by_id[descriptor.source_id] = "enabled false, expected true"
            continue
        by_id[descriptor.source_id] = descriptor

    errors: list[str] = []
    resolved: list[dict[str, Any]] = []

    for source in sources:
        canonical_source = _SOURCE_ALIASES.get(source, source)
        if source in _VIRTUAL_SOURCES:
            continue

        descriptor = by_id.get(canonical_source)
        if descriptor is None:
            invalid_reason = invalid_by_id.get(canonical_source)
            if invalid_reason:
                errors.append(
                    f"source '{canonical_source}' has an invalid catalog "
                    f"descriptor: {invalid_reason}"
                )
            else:
                errors.append(
                    f"source '{canonical_source}' not found in catalog — "
                    "it may be unlicensed or not yet approved"
                )
            continue

        resolved.append(descriptor.model_dump(mode="json"))

    if errors:
        raise SourceResolutionError(
            "Source resolution failed:\n" + "\n".join(f"  • {e}" for e in errors)
        )

    return resolved


def canonicalize_sources(sources: list[str]) -> list[str]:
    return list(
        dict.fromkeys(
            _SOURCE_ALIASES.get(source, source)
            for source in sources
        )
    )
