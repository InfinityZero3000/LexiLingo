"""Authenticated client for the AI service content-agent API."""

from __future__ import annotations

import uuid
from typing import Any

import httpx

from app.core.config import settings


class ContentAgentClient:
    def __init__(self) -> None:
        if not settings.CONTENT_AGENT_SERVICE_TOKEN.strip():
            raise RuntimeError("CONTENT_AGENT_SERVICE_TOKEN is not configured")
        self._base_url = settings.AI_SERVICE_URL.rstrip("/")
        self._headers = {
            "X-Content-Agent-Token": settings.CONTENT_AGENT_SERVICE_TOKEN
        }
        self._timeout = httpx.Timeout(settings.CONTENT_AGENT_AI_TIMEOUT_SECONDS)

    async def ingest_records(
        self, job_id: uuid.UUID, records: list[dict[str, Any]]
    ) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self._base_url}/internal/content-agent/jobs/{job_id}/records",
                headers=self._headers,
                json={"records": records},
            )
        response.raise_for_status()
        return response.json()

    async def generate(
        self, job_id: uuid.UUID, config: dict[str, Any]
    ) -> dict[str, Any]:
        generation_fields = {
            "levels",
            "sources",
            "title_focus",
            "topic_focus",
            "units_per_course",
            "lessons_per_unit",
            "words_per_lesson",
            "exercises_per_lesson",
            "exercise_mix",
            "confidence_threshold",
        }
        generation_config = {
            key: value for key, value in config.items() if key in generation_fields
        }
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self._base_url}/internal/content-agent/jobs/{job_id}/generate",
                headers=self._headers,
                json=generation_config,
            )
        response.raise_for_status()
        payload = response.json()
        if isinstance(payload, dict) and isinstance(payload.get("data"), dict):
            return payload["data"]
        return payload

    async def delete_context(self, job_id: uuid.UUID) -> None:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.delete(
                f"{self._base_url}/internal/content-agent/jobs/{job_id}",
                headers=self._headers,
            )
        if response.status_code != 404:
            response.raise_for_status()
