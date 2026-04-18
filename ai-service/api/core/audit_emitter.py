"""Emit AI interaction audit events to backend-service."""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx

logger = logging.getLogger(__name__)


def _audit_endpoint() -> str:
    return os.getenv("BACKEND_AUDIT_INGEST_URL", "").strip()


def _audit_secret() -> str:
    return os.getenv("AI_AUDIT_INGEST_SECRET", "").strip()


async def emit_ai_audit_event(payload: dict[str, Any]) -> None:
    """Best-effort async delivery to backend audit ingestion endpoint."""
    url = _audit_endpoint()
    if not url:
        return

    headers = {"Content-Type": "application/json"}
    secret = _audit_secret()
    if secret:
        headers["X-AI-Service-Secret"] = secret

    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            response = await client.post(url, json=payload, headers=headers)
            if response.status_code >= 400:
                logger.warning(
                    "Audit ingest rejected with status=%s body=%s",
                    response.status_code,
                    response.text[:500],
                )
    except Exception as exc:  # noqa: BLE001 - best-effort telemetry path
        logger.warning("Failed to emit AI audit event: %s", exc)
