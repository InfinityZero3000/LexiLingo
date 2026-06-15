"""Source catalog resolution for licensed content ETL."""

from __future__ import annotations

import logging
from typing import Any

from app.services.content_agent_client import ContentAgentClient

logger = logging.getLogger(__name__)

# Virtual sources that never need AI-service pinning.
_VIRTUAL_SOURCES: frozenset[str] = frozenset({"admin_upload", "existing_cefr"})


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

    Returns the list of pinned descriptor dicts (same order as *sources*).
    Virtual sources (``admin_upload``, ``existing_cefr``) are returned with a
    synthetic descriptor and are never looked up in the catalog.

    Raises :class:`SourceResolutionError` with a collected message when any
    source cannot be resolved.
    """
    by_id: dict[str, dict[str, Any]] = {}
    for entry in catalog:
        sid = str(entry.get("source_id") or entry.get("id") or "")
        if sid:
            by_id[sid] = entry

    errors: list[str] = []
    resolved: list[dict[str, Any]] = []

    for source in sources:
        if source in _VIRTUAL_SOURCES:
            resolved.append(
                {
                    "source_id": source,
                    "snapshot_id": source,
                    "status": "active",
                    "virtual": True,
                }
            )
            continue

        descriptor = by_id.get(source)
        if descriptor is None:
            errors.append(
                f"source '{source}' not found in catalog — "
                "it may be unlicensed or not yet approved"
            )
            continue

        status = str(descriptor.get("status", ""))
        if status != "active":
            errors.append(
                f"source '{source}' snapshot is '{status}', not active — "
                "choose an active snapshot or wait for approval"
            )
            continue

        snapshot_id = str(
            descriptor.get("snapshot_id") or descriptor.get("id") or ""
        )
        if not snapshot_id:
            errors.append(
                f"source '{source}' catalog entry has no snapshot_id — "
                "the AI service returned an incomplete descriptor"
            )
            continue

        resolved.append(
            {
                "source_id": source,
                "snapshot_id": snapshot_id,
                "status": "active",
                "virtual": False,
                "license_id": descriptor.get("license_id"),
                "license_url": descriptor.get("license_url"),
                "attribution_text": descriptor.get("attribution_text"),
                "content_usage": descriptor.get("content_usage", "full_text"),
            }
        )

    if errors:
        raise SourceResolutionError(
            "Source resolution failed:\n" + "\n".join(f"  • {e}" for e in errors)
        )

    return resolved
