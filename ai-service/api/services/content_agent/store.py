"""TTL-backed temporary job storage with Redis and local fallback."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import Callable
from typing import Any

from api.models.content_agent import NormalizedSourceRecord


logger = logging.getLogger(__name__)


class RecordLimitExceeded(ValueError):
    """Raised when a job would exceed its configured record cap."""


class ContentAgentStore:
    def __init__(
        self,
        *,
        ttl_seconds: int,
        max_records: int,
        redis_client: Any | None = None,
        allow_local_fallback: bool = True,
        clock: Callable[[], float] | None = None,
    ) -> None:
        self.ttl_seconds = max(1, ttl_seconds)
        self.max_records = max(1, max_records)
        self.redis = redis_client
        self.allow_local_fallback = allow_local_fallback
        self._clock = clock or time.monotonic
        self._local: dict[str, tuple[float, list[NormalizedSourceRecord]]] = {}
        self._lock = asyncio.Lock()

    def set_redis_client(self, redis_client: Any | None) -> None:
        self.redis = redis_client

    @staticmethod
    def _key(job_id: str) -> str:
        return f"content-agent:job:{job_id}:records"

    async def _read_redis(
        self,
        job_id: str,
    ) -> list[NormalizedSourceRecord] | None:
        if self.redis is None:
            return None
        raw = await self.redis.get(self._key(job_id))
        if not raw:
            return None
        payload = json.loads(raw)
        return [
            NormalizedSourceRecord.model_validate(item)
            for item in payload
        ]

    async def _write_redis(
        self,
        job_id: str,
        records: list[NormalizedSourceRecord],
    ) -> None:
        if self.redis is None:
            return
        payload = [
            record.model_dump(mode="json")
            for record in records
        ]
        await self.redis.set(
            self._key(job_id),
            json.dumps(payload, ensure_ascii=False),
            ex=self.ttl_seconds,
        )

    def _read_local(
        self,
        job_id: str,
    ) -> list[NormalizedSourceRecord] | None:
        entry = self._local.get(job_id)
        if entry is None:
            return None
        expires_at, records = entry
        if self._clock() >= expires_at:
            self._local.pop(job_id, None)
            return None
        return list(records)

    def _write_local(
        self,
        job_id: str,
        records: list[NormalizedSourceRecord],
    ) -> None:
        self._local[job_id] = (
            self._clock() + self.ttl_seconds,
            list(records),
        )

    async def append(
        self,
        job_id: str,
        records: list[NormalizedSourceRecord],
    ) -> int:
        async with self._lock:
            if self.redis is None and not self.allow_local_fallback:
                raise RuntimeError("Redis is required for content-agent storage")
            current: list[NormalizedSourceRecord] | None = None
            if self.redis is not None:
                try:
                    current = await self._read_redis(job_id)
                except Exception as exc:
                    if not self.allow_local_fallback:
                        raise RuntimeError(
                            "Content-agent Redis read failed"
                        ) from exc
                    logger.warning(
                        "Content-agent Redis read failed; using local store: %s",
                        exc,
                    )
            if current is None:
                current = self._read_local(job_id) or []

            updated = [*current, *records]
            if len(updated) > self.max_records:
                raise RecordLimitExceeded(
                    f"Job record limit exceeded ({self.max_records})"
                )

            if self.redis is not None:
                try:
                    await self._write_redis(job_id, updated)
                except Exception as exc:
                    if not self.allow_local_fallback:
                        raise RuntimeError(
                            "Content-agent Redis write failed"
                        ) from exc
                    logger.warning(
                        "Content-agent Redis write failed; using local store: %s",
                        exc,
                    )
            self._write_local(job_id, updated)
            return len(updated)

    async def get(self, job_id: str) -> list[NormalizedSourceRecord] | None:
        async with self._lock:
            if self.redis is None and not self.allow_local_fallback:
                raise RuntimeError("Redis is required for content-agent storage")
            if self.redis is not None:
                try:
                    records = await self._read_redis(job_id)
                    if records is not None:
                        return records
                except Exception as exc:
                    if not self.allow_local_fallback:
                        raise RuntimeError(
                            "Content-agent Redis read failed"
                        ) from exc
                    logger.warning(
                        "Content-agent Redis read failed; using local store: %s",
                        exc,
                    )
            return self._read_local(job_id)

    async def delete(self, job_id: str) -> None:
        async with self._lock:
            if self.redis is None and not self.allow_local_fallback:
                raise RuntimeError("Redis is required for content-agent storage")
            if self.redis is not None:
                try:
                    await self.redis.delete(self._key(job_id))
                except Exception as exc:
                    if not self.allow_local_fallback:
                        raise RuntimeError(
                            "Content-agent Redis delete failed"
                        ) from exc
                    logger.warning(
                        "Content-agent Redis delete failed; clearing local store: %s",
                        exc,
                    )
            self._local.pop(job_id, None)
