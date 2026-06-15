"""Strict CSV/JSON ingestion for content-agent admin uploads."""

from __future__ import annotations

import csv
import hashlib
import io
import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from pydantic import ValidationError

from app.schemas.content_agent import NormalizedVocabularyRecord

MAX_UPLOAD_BYTES = 5 * 1024 * 1024
MAX_UPLOAD_ROWS = 20_000
MAX_REPORTED_ERRORS = 100


@dataclass(frozen=True)
class ParsedContentUpload:
    filename: str
    checksum: str
    records: list[dict]
    errors: list[str]
    schema_version: int = 1
    rights_confirmed: bool = False
    rights_confirmed_at: datetime | None = None


def _normalized_payload(row: dict, row_number: int) -> dict:
    lowered = {str(key).strip().lower(): value for key, value in row.items()}
    word = str(lowered.get("word") or "").strip()
    level = str(
        lowered.get("declared_cefr") or lowered.get("cefr_level") or ""
    ).strip().upper()
    pos = str(lowered.get("part_of_speech") or "noun").strip().lower()
    topic = str(
        lowered.get("declared_topic") or lowered.get("topic") or "general"
    ).strip().lower()
    return {
        "record_id": f"admin_upload:{row_number}:{word.casefold()}",
        "source_name": "admin_upload",
        "source_url": None,
        "license_mode": "admin_owned",
        "content_usage": "full_text",
        "title": lowered.get("title") or None,
        "word": word,
        "part_of_speech": pos,
        "definition": lowered.get("definition") or None,
        "translation_vi": lowered.get("translation_vi") or None,
        "example": lowered.get("example") or None,
        "declared_cefr": level,
        "declared_topic": topic or "general",
        "published_at": lowered.get("published_at") or None,
        "checksum": None,
        "metadata": {},
    }


def parse_content_upload(
    filename: str,
    content: bytes,
    *,
    rights_confirmed: bool = False,
) -> ParsedContentUpload:
    """Parse and validate an admin content upload.

    Parameters
    ----------
    filename:
        Original filename (used to detect format from extension).
    content:
        Raw file bytes (max 5 MB).
    rights_confirmed:
        Must be ``True`` for uploads that will be used in ETL jobs.
        When ``False`` the parsed result has ``rights_confirmed=False``
        which will cause the route to reject the upload with HTTP 422.
    """
    if len(content) > MAX_UPLOAD_BYTES:
        raise ValueError("Upload exceeds the 5 MB limit")

    suffix = Path(filename).suffix.lower()
    if suffix not in {".csv", ".json"}:
        raise ValueError("Only UTF-8 CSV and JSON uploads are supported")

    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("Upload must be valid UTF-8") from exc

    checksum = hashlib.sha256(content).hexdigest()
    if suffix == ".csv":
        rows = list(csv.DictReader(io.StringIO(text)))
    else:
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON at line {exc.lineno}") from exc
        if isinstance(payload, dict):
            rows = payload.get("records")
        else:
            rows = payload
        if not isinstance(rows, list):
            raise ValueError("JSON must be an array or an object with a records array")

    if len(rows) > MAX_UPLOAD_ROWS:
        raise ValueError("Upload exceeds the 20,000 row limit")
    if not rows:
        raise ValueError("Upload contains no records")

    records: list[dict] = []
    errors: list[str] = []
    for index, row in enumerate(rows, start=2 if suffix == ".csv" else 1):
        if not isinstance(row, dict):
            errors.append(f"Row {index}: expected an object")
            continue
        try:
            record = NormalizedVocabularyRecord.model_validate(
                _normalized_payload(row, index)
            )
            records.append(record.model_dump(mode="json"))
        except ValidationError as exc:
            message = "; ".join(error["msg"] for error in exc.errors())
            errors.append(f"Row {index}: {message}")
        if len(errors) >= MAX_REPORTED_ERRORS:
            errors.append("Additional validation errors were omitted")
            break

    confirmed_at = datetime.now(UTC) if rights_confirmed else None
    return ParsedContentUpload(
        filename=Path(filename).name,
        checksum=checksum,
        records=records,
        errors=errors,
        schema_version=1,
        rights_confirmed=rights_confirmed,
        rights_confirmed_at=confirmed_at,
    )
