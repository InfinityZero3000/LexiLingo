"""Unit tests for content_agent_sources: snapshot resolution logic."""

from __future__ import annotations

import pytest

from app.services.content_agent_sources import (
    SourceResolutionError,
    canonicalize_sources,
    resolve_snapshots,
)


def _catalog(*entries: dict) -> list[dict]:
    return list(entries)


def _source(
    source_id: str,
    *,
    snapshot_id: str | None = None,
    status: str = "active",
    license_id: str = "CC-BY-4.0",
    license_url: str = "https://creativecommons.org/licenses/by/4.0/",
    attribution_text: str = "Test attribution",
    content_usage: str = "full_text",
    enabled: bool = True,
) -> dict:
    return {
        "source_id": source_id,
        "source_name": source_id,
        "source_version": "2025",
        "snapshot_id": snapshot_id or f"{source_id}-snap-001",
        "official_url": "https://example.com/source",
        "status": status,
        "license_id": license_id,
        "license_url": license_url,
        "attribution_text": attribution_text,
        "retrieved_at": "2026-06-15T00:00:00Z",
        "raw_checksum": "a" * 64,
        "normalized_sha256": "b" * 64,
        "normalized_bytes": 100,
        "record_checksum_root": "c" * 64,
        "adapter_version": 1,
        "record_count": 10,
        "enabled": enabled,
    }


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


def test_admin_upload_is_the_only_virtual_source() -> None:
    assert resolve_snapshots(["admin_upload"], catalog=[]) == []
    with pytest.raises(SourceResolutionError, match="cefr_j"):
        resolve_snapshots(["existing_cefr"], catalog=[])


def test_existing_cefr_alias_resolves_to_canonical_cefr_j_snapshot() -> None:
    catalog = _catalog(
        _source(
            "cefr_j",
            snapshot_id="cefr-j-snap",
            license_id="LicenseRef-CEFR-J-Commercial",
        )
    )
    resolved = resolve_snapshots(["existing_cefr"], catalog)

    assert resolved[0]["source_id"] == "cefr_j"
    assert canonicalize_sources(["existing_cefr", "admin_upload"]) == [
        "cefr_j",
        "admin_upload",
    ]


def test_exact_snapshot_pinning_captures_descriptor_fields() -> None:
    catalog = _catalog(_source("oewn", snapshot_id="oewn-20240601"))
    resolved = resolve_snapshots(["oewn"], catalog=catalog)
    assert len(resolved) == 1
    r = resolved[0]
    assert r["snapshot_id"] == "oewn-20240601"
    assert r["license_id"] == "CC-BY-4.0"


def test_mixed_virtual_and_real_sources_resolved_in_order() -> None:
    catalog = _catalog(
        _source(
            "cefr_j",
            license_id="LicenseRef-CEFR-J-Commercial",
        ),
        _source("oewn"),
        _source("tatoeba"),
    )
    resolved = resolve_snapshots(
        ["existing_cefr", "oewn", "tatoeba"], catalog=catalog
    )
    assert [r["source_id"] for r in resolved] == ["cefr_j", "oewn", "tatoeba"]


# ---------------------------------------------------------------------------
# Blocking error cases
# ---------------------------------------------------------------------------


def test_unavailable_source_raises_resolution_error() -> None:
    with pytest.raises(SourceResolutionError, match="not found in catalog"):
        resolve_snapshots(["oewn"], catalog=[])


def test_inactive_snapshot_raises_resolution_error() -> None:
    catalog = _catalog(_source("oewn", status="archived"))
    with pytest.raises(SourceResolutionError, match="archived"):
        resolve_snapshots(["oewn"], catalog=catalog)


def test_pending_snapshot_also_rejected() -> None:
    catalog = _catalog(_source("cmudict", status="pending"))
    with pytest.raises(SourceResolutionError, match="pending"):
        resolve_snapshots(["cmudict"], catalog=catalog)


def test_disabled_active_snapshot_is_rejected() -> None:
    catalog = _catalog(_source("oewn", enabled=False))
    with pytest.raises(SourceResolutionError, match="enabled false"):
        resolve_snapshots(["oewn"], catalog=catalog)


def test_missing_snapshot_id_raises_resolution_error() -> None:
    entry = {
        "source_id": "cefr_j",
        "snapshot_id": "",
        "status": "active",
    }
    with pytest.raises(SourceResolutionError, match="snapshot_id"):
        resolve_snapshots(["cefr_j"], catalog=[entry])


def test_multiple_errors_collected_in_single_raise() -> None:
    with pytest.raises(SourceResolutionError) as exc_info:
        resolve_snapshots(["oewn", "cmudict", "tatoeba"], catalog=[])
    msg = str(exc_info.value)
    assert "oewn" in msg
    assert "cmudict" in msg
    assert "tatoeba" in msg


def test_stale_catalog_missing_requested_source_rejected() -> None:
    # Catalog has wikidata but request asks for librispeech
    catalog = _catalog(_source("wikidata"))
    with pytest.raises(SourceResolutionError, match="librispeech"):
        resolve_snapshots(["librispeech"], catalog=catalog)


def test_license_mismatch_not_in_catalog_raises_error() -> None:
    # Source exists but with no license_id and inactive status
    catalog = _catalog(
        {"source_id": "common_voice", "snapshot_id": "cv-001", "status": "inactive"}
    )
    with pytest.raises(SourceResolutionError):
        resolve_snapshots(["common_voice"], catalog=catalog)


# ---------------------------------------------------------------------------
# AI-service failure sanitization
# ---------------------------------------------------------------------------


def test_catalog_entry_missing_source_id_is_skipped() -> None:
    # A malformed entry with no source_id should not cause KeyError
    catalog = [{"snapshot_id": "bad-entry", "status": "active"}]
    with pytest.raises(SourceResolutionError, match="oewn"):
        resolve_snapshots(["oewn"], catalog=catalog)


def test_catalog_with_none_values_does_not_crash() -> None:
    catalog = [
        {
            "source_id": "oewn",
            "snapshot_id": "oewn-snap",
            "status": "active",
            "license_id": None,
            "license_url": None,
            "attribution_text": None,
        }
    ]
    with pytest.raises(SourceResolutionError, match="oewn"):
        resolve_snapshots(["oewn"], catalog=catalog)


def test_virtual_sources_not_blocked_by_empty_catalog() -> None:
    # Even when AI service is unavailable, virtual sources should resolve
    resolved = resolve_snapshots(["admin_upload"], catalog=[])
    assert resolved == []
