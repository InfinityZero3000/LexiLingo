"""Licence ids a content record may carry, and the rules for IELTS passage provenance."""

from __future__ import annotations

from typing import Any

# Mirror of AllowedLicenseId in ai-service/api/services/content_etl/contracts.py,
# which is the source of truth. Services do not share code; a test fails on drift.
AI_SERVICE_LICENSE_IDS: frozenset[str] = frozenset(
    {
        "CC0-1.0",
        "CC-BY-2.0-FR",
        "CC-BY-4.0",
        "LicenseRef-CMUdict",
        "LicenseRef-CEFR-J-Commercial",
        "LicenseRef-Admin-Owned",
        "LicenseRef-Generated",
    }
)

# Passage sources the ETL list has no slot for: encyclopedic text, public domain books and
# US-government works.
PASSAGE_ONLY_LICENSE_IDS: frozenset[str] = frozenset(
    {
        "CC-BY-SA-4.0",
        "CC-BY-SA-3.0",
        "LicenseRef-Public-Domain",
        "LicenseRef-US-Gov-Public-Domain",
    }
)

ALLOWED_LICENSE_IDS: frozenset[str] = AI_SERVICE_LICENSE_IDS | PASSAGE_ONLY_LICENSE_IDS

# The commercial CEFR-J licence covers a word list, never a reading passage.
PASSAGE_FORBIDDEN_LICENSE_IDS: frozenset[str] = frozenset({"LicenseRef-CEFR-J-Commercial", "LicenseRef-CMUdict"})

ATTRIBUTION_REQUIRED_PREFIXES: tuple[str, ...] = ("CC-BY",)


def requires_attribution(license_id: str) -> bool:
    return license_id.startswith(ATTRIBUTION_REQUIRED_PREFIXES)


def passage_license_problem(entry: Any) -> str | None:
    """Why a provenance entry cannot back a published passage, or None."""
    if not isinstance(entry, dict):
        return "has no provenance entry"
    license_id = entry.get("license_id")
    if not isinstance(license_id, str) or license_id not in ALLOWED_LICENSE_IDS:
        return f"has no valid license_id (got {license_id!r})"
    if license_id in PASSAGE_FORBIDDEN_LICENSE_IDS:
        return f"license_id {license_id} does not cover passage text"
    if requires_attribution(license_id):
        for field in ("attribution", "source_url"):
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                return f"is {license_id} and needs a non-empty {field}"
    return None
