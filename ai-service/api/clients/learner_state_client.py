"""Deadline-bounded client for backend learner-state reads."""

from __future__ import annotations

import asyncio
import random
import time
from dataclasses import dataclass, field
from typing import Any

import httpx

from api.core.config import settings


@dataclass(frozen=True, slots=True)
class LearnerStateResult:
    state_epoch: int = 0
    states: dict[str, dict[str, Any]] = field(default_factory=dict)
    degraded: bool = False
    reason: str | None = None
    goal: str | None = None
    interest: str | None = None


class LearnerStateClient:
    """One pooled client protected by an absolute deadline and circuit breaker."""

    def __init__(
        self,
        *,
        base_url: str = "http://backend-service:8000/api/v1/internal",
        token: str,
        audience: str = "lexilingo-backend",
        http_client: httpx.AsyncClient | None = None,
        max_inflight: int = 100,
        circuit_failures: int = 5,
        circuit_reset_seconds: float = 30.0,
        connect_timeout_seconds: float = 0.010,
        pool_timeout_seconds: float = 0.005,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._token = token
        self._audience = audience
        self._owns_client = http_client is None
        self._http = http_client or httpx.AsyncClient(
            limits=httpx.Limits(max_connections=max_inflight, max_keepalive_connections=20),
            timeout=None,
        )
        self._bulkhead = asyncio.Semaphore(max_inflight)
        self._circuit_failures = max(1, circuit_failures)
        self._circuit_reset_seconds = max(0.1, circuit_reset_seconds)
        self._connect_timeout_seconds = max(0.001, connect_timeout_seconds)
        self._pool_timeout_seconds = max(0.001, pool_timeout_seconds)
        self._failure_count = 0
        self._circuit_open_until = 0.0
        self._half_open_probe = asyncio.Lock()

    def _degraded(self, reason: str) -> LearnerStateResult:
        return LearnerStateResult(degraded=True, reason=reason)

    def _record_failure(self) -> None:
        self._failure_count += 1
        if self._failure_count >= self._circuit_failures:
            self._circuit_open_until = time.monotonic() + self._circuit_reset_seconds

    async def batch_get(
        self,
        user_id: str,
        concept_ids: list[str],
        *,
        deadline: float,
    ) -> LearnerStateResult:
        started = time.perf_counter()
        candidate_count = min(len(set(concept_ids)), 100)

        def finish(result: LearnerStateResult) -> LearnerStateResult:
            try:
                from api.services.telemetry import get_telemetry

                telemetry = get_telemetry()
                telemetry.record_metric(
                    "learner_state_batch_read_seconds",
                    time.perf_counter() - started,
                    unit="seconds",
                    tags={"result": "degraded" if result.degraded else "ok"},
                )
                telemetry.record_metric(
                    "learner_state_batch_size", candidate_count, unit="count"
                )
                if result.degraded:
                    telemetry.increment_counter("learner_state_degraded_total")
                    telemetry.record_metric(
                        "learner_state_degraded_event",
                        1,
                        unit="count",
                        tags={"reason": result.reason or "unknown"},
                    )
            except Exception:
                pass
            return result

        now = time.monotonic()
        if now < self._circuit_open_until:
            return finish(self._degraded("circuit_open"))
        half_open = self._failure_count >= self._circuit_failures
        if half_open and self._half_open_probe.locked():
            return finish(self._degraded("circuit_half_open"))
        remaining = deadline - now
        if remaining <= 0:
            return finish(self._degraded("deadline_exceeded"))

        ids = list(dict.fromkeys(concept_ids))[:100]
        probe_acquired = False
        try:
            async with asyncio.timeout(remaining):
                if half_open:
                    await self._half_open_probe.acquire()
                    probe_acquired = True
                async with self._bulkhead:
                    response = None
                    last_reason = "transport_error"
                    for attempt in range(2):
                        try:
                            response = await self._http.post(
                                f"{self._base_url}/learner-state/batch-get",
                                headers={
                                    "X-LexiLingo-Service-Token": self._token,
                                    "X-LexiLingo-Audience": self._audience,
                                },
                                json={"user_id": user_id, "concept_ids": ids},
                                timeout=httpx.Timeout(
                                    max(0.001, deadline - time.monotonic()),
                                    connect=min(
                                        self._connect_timeout_seconds,
                                        max(0.001, deadline - time.monotonic()),
                                    ),
                                    pool=min(
                                        self._pool_timeout_seconds,
                                        max(0.001, deadline - time.monotonic()),
                                    ),
                                ),
                            )
                            if response.status_code < 400:
                                break
                            last_reason = f"http_{response.status_code}"
                            if response.status_code < 500 and response.status_code != 429:
                                return finish(self._degraded(last_reason))
                        except (httpx.TimeoutException, httpx.TransportError):
                            last_reason = "transport_error"
                        if attempt == 0 and deadline > time.monotonic():
                            await asyncio.sleep(
                                min(random.uniform(0.001, 0.005), max(0.0, deadline - time.monotonic()))
                            )
                    if response is None or response.status_code >= 400:
                        self._record_failure()
                        return finish(self._degraded(last_reason))
        except (TimeoutError, asyncio.TimeoutError, httpx.TimeoutException):
            self._record_failure()
            return finish(self._degraded("timeout"))
        except asyncio.CancelledError:
            raise
        except httpx.HTTPError:
            self._record_failure()
            return finish(self._degraded("transport_error"))
        finally:
            if probe_acquired:
                self._half_open_probe.release()

        try:
            payload = response.json()
            if not isinstance(payload, dict) or not isinstance(payload.get("states", []), list):
                raise ValueError("invalid learner-state response")
            states = {
                str(item["concept_id"]): dict(item)
                for item in payload.get("states", [])
                if isinstance(item, dict) and item.get("concept_id")
            }
            state_epoch = int(payload.get("state_epoch") or 0)
            goal = payload.get("goal")
            interest = payload.get("interest")
        except (TypeError, ValueError, KeyError):
            self._record_failure()
            return finish(self._degraded("invalid_response"))
        self._failure_count = 0
        self._circuit_open_until = 0.0
        return finish(LearnerStateResult(
            state_epoch=state_epoch,
            states=states,
            goal=goal if isinstance(goal, str) else None,
            interest=interest if isinstance(interest, str) else None,
        ))

    async def close(self) -> None:
        if self._owns_client:
            await self._http.aclose()

    async def send_observations(
        self,
        observations: list[dict[str, Any]],
        *,
        timeout_seconds: float = 5.0,
    ) -> dict[str, Any]:
        """Forward a durable spool batch; failures are replayed by the caller."""
        response = await self._http.post(
            f"{self._base_url}/learner-state/observations:batch",
            headers={
                "X-LexiLingo-Service-Token": self._token,
                "X-LexiLingo-Audience": self._audience,
            },
            json={"observations": observations[:100]},
            timeout=max(0.1, timeout_seconds),
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("invalid learner observation acknowledgement")
        accepted = payload.get("accepted_event_ids", [])
        duplicates = payload.get("duplicate_event_ids", [])
        if not isinstance(accepted, list) or not isinstance(duplicates, list):
            raise ValueError("invalid learner observation acknowledgement")
        return {
            "accepted_event_ids": [str(item) for item in accepted],
            "duplicate_event_ids": [str(item) for item in duplicates],
        }


_CLIENT: LearnerStateClient | None = None


def get_learner_state_client() -> LearnerStateClient:
    """Return the process-wide pooled learner-state client."""
    global _CLIENT
    if _CLIENT is None:
        _CLIENT = LearnerStateClient(
            base_url=settings.LEARNER_STATE_API_URL,
            token=settings.LEARNER_STATE_INTERNAL_TOKEN,
            audience=settings.LEARNER_STATE_INTERNAL_AUDIENCE,
            max_inflight=settings.LEARNER_STATE_MAX_INFLIGHT,
            circuit_failures=settings.LEARNER_STATE_CIRCUIT_FAILURES,
            circuit_reset_seconds=settings.LEARNER_STATE_CIRCUIT_RESET_SECONDS,
            connect_timeout_seconds=settings.LEARNER_STATE_CONNECT_TIMEOUT_MS / 1000.0,
            pool_timeout_seconds=settings.LEARNER_STATE_POOL_TIMEOUT_MS / 1000.0,
        )
    return _CLIENT


async def close_learner_state_client() -> None:
    """Close and reset the process-wide client during application shutdown."""
    global _CLIENT
    if _CLIENT is not None:
        await _CLIENT.close()
        _CLIENT = None
