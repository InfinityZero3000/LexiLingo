"""Durable, idempotent AI-to-backend handoff for learner observations."""

from __future__ import annotations

import asyncio
import hashlib
import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any, Awaitable, Callable

from pymongo import ReturnDocument, UpdateOne
from pymongo.write_concern import WriteConcern

logger = logging.getLogger(__name__)

# Kept in sync by hand with ALLOWED_OBSERVATION_PAYLOAD_KEYS in
# backend-service/app/schemas/learner_state.py — the backend rejects the whole
# batch on an unknown key, so add to both sides together.
_ALLOWED_PAYLOAD_KEYS = {
    "algorithm_version",
    "error_count",
    "migration_version",
    "source",
    # Skill evidence, carried on one anchor observation per turn (see
    # persist_trace_observations).
    "skill",
    "score",
    "difficulty_level",
}


def _telemetry_event(name: str, *, value: int = 1, gauge: bool = False) -> None:
    try:
        from api.services.telemetry import get_telemetry

        telemetry = get_telemetry()
        if gauge:
            telemetry.set_gauge(name, value)
        else:
            telemetry.increment_counter(name, value)
    except Exception:
        pass


@dataclass(frozen=True, slots=True)
class LearnerObservation:
    user_id: str
    session_id: str
    turn_id: str
    concept_id: str
    observation_kind: str
    outcome: str
    confidence: float
    observed_at: datetime
    payload: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class SpoolPersistResult:
    event_id: str
    durable: bool
    duplicate: bool = False
    reason: str | None = None


def deterministic_event_id(observation: LearnerObservation) -> str:
    """Return a stable identity; timestamps are deliberately excluded."""
    material = "|".join(
        (
            observation.user_id,
            observation.session_id,
            observation.turn_id,
            observation.concept_id,
            observation.observation_kind,
        )
    )
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def _sanitized_payload(payload: dict[str, Any]) -> dict[str, Any]:
    sanitized: dict[str, Any] = {}
    for key, value in payload.items():
        normalized = str(key).strip().lower()
        if normalized not in _ALLOWED_PAYLOAD_KEYS:
            continue
        if isinstance(value, (str, int, float, bool)) or value is None:
            sanitized[normalized] = value
    return sanitized


class LearnerObservationSpool:
    """Persists observations before terminal chat completion.

    PostgreSQL application happens asynchronously; this class only performs
    the bounded Mongo durability handoff.
    """

    def __init__(self, collection: Any, *, write_timeout_ms: int = 20) -> None:
        self._collection = collection
        self._write_timeout_seconds = max(1, write_timeout_ms) / 1000.0

    async def persist(self, observation: LearnerObservation) -> SpoolPersistResult:
        event_id = deterministic_event_id(observation)
        observed_at = observation.observed_at
        if observed_at.tzinfo is None:
            observed_at = observed_at.replace(tzinfo=UTC)
        now = datetime.now(UTC)
        document = {
            "event_id": event_id,
            "user_id": observation.user_id,
            "session_id": observation.session_id,
            "turn_id": observation.turn_id,
            "concept_id": observation.concept_id,
            "observation_kind": observation.observation_kind,
            "outcome": observation.outcome,
            "confidence": max(0.0, min(1.0, float(observation.confidence))),
            "observed_at": observed_at,
            "payload": _sanitized_payload(observation.payload),
            "status": "pending",
            "attempt_count": 0,
            "available_at": now,
            "created_at": now,
        }
        try:
            async with asyncio.timeout(self._write_timeout_seconds):
                result = await self._collection.update_one(
                    {"event_id": event_id},
                    {"$setOnInsert": document},
                    upsert=True,
                )
            return SpoolPersistResult(
                event_id=event_id,
                durable=True,
                duplicate=getattr(result, "upserted_id", None) is None,
            )
        except (TimeoutError, asyncio.TimeoutError):
            logger.error("learner_observation_spool_degraded reason=timeout")
            return SpoolPersistResult(event_id=event_id, durable=False, reason="timeout")
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("learner_observation_spool_degraded reason=storage_error")
            return SpoolPersistResult(
                event_id=event_id, durable=False, reason="storage_error"
            )

    async def persist_many(
        self, observations: list[LearnerObservation]
    ) -> list[SpoolPersistResult]:
        if not observations:
            return []
        now = datetime.now(UTC)
        operations = []
        event_ids = []
        for observation in observations[:60]:
            event_id = deterministic_event_id(observation)
            event_ids.append(event_id)
            observed_at = observation.observed_at
            if observed_at.tzinfo is None:
                observed_at = observed_at.replace(tzinfo=UTC)
            document = {
                "event_id": event_id,
                "user_id": observation.user_id,
                "session_id": observation.session_id,
                "turn_id": observation.turn_id,
                "concept_id": observation.concept_id,
                "observation_kind": observation.observation_kind,
                "outcome": observation.outcome,
                "confidence": max(0.0, min(1.0, float(observation.confidence))),
                "observed_at": observed_at,
                "payload": _sanitized_payload(observation.payload),
                "status": "pending",
                "attempt_count": 0,
                "available_at": now,
                "created_at": now,
            }
            operations.append(
                UpdateOne({"event_id": event_id}, {"$setOnInsert": document}, upsert=True)
            )
        try:
            async with asyncio.timeout(self._write_timeout_seconds):
                result = await self._collection.bulk_write(operations, ordered=False)
            duplicates = max(0, len(event_ids) - int(getattr(result, "upserted_count", 0)))
            if duplicates:
                _telemetry_event("learner_observation_duplicate_total", value=duplicates)
            return [SpoolPersistResult(event_id=item, durable=True) for item in event_ids]
        except (TimeoutError, asyncio.TimeoutError):
            reason = "timeout"
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("learner_observation_spool_degraded reason=storage_error")
            reason = "storage_error"
        _telemetry_event("learner_observation_dropped_total", value=len(event_ids))
        return [
            SpoolPersistResult(event_id=item, durable=False, reason=reason)
            for item in event_ids
        ]


# A delivery failure is one of three different things, and treating them alike is
# what let an undeliverable observation retry every 30 seconds forever.
#
# The receiver being switched off is the normal case, not an error: backend-service
# answers 404 for the whole route while `LEARNER_STATE_ENABLED` is false, and 401
# when the shared token is wrong. Neither is the observation's fault and neither
# improves by trying again soon — but the learner data is still good, so it waits
# instead of being discarded, and the wait does not count against the attempt cap.
_RECEIVER_OFF_STATUSES = frozenset({401, 403, 404})

# The backend looked at the payload and refused it. Its allowlist rejects an
# unknown key outright, so this will never succeed however often it is replayed.
_PERMANENT_REJECTION_STATUSES = frozenset({400, 422})

# Transient failures (5xx, 429, timeouts) get the exponential backoff below and
# are abandoned after this many tries, matching `reconcile_once`.
MAX_DELIVERY_ATTEMPTS = 10

# How long to wait while the receiver is switched off. Long enough that a feature
# left disabled for a week costs a handful of polls rather than 20,000.
RECEIVER_OFF_BACKOFF_SECONDS = 300.0


def _response_status(exc: BaseException) -> int | None:
    """HTTP status behind a failed send, if it was an HTTP error at all."""
    response = getattr(exc, "response", None)
    status = getattr(response, "status_code", None)
    return status if isinstance(status, int) else None


class SpoolForwarder:
    """Lease-based replay worker for pending Mongo spool documents."""

    def __init__(
        self,
        collection: Any,
        sender: Callable[[list[dict[str, Any]]], Awaitable[dict[str, Any]]],
        *,
        lease_seconds: float = 30.0,
        poll_seconds: float = 0.1,
        max_backoff_seconds: float = 30.0,
        audit_collection: Any | None = None,
    ) -> None:
        self._collection = collection
        self._sender = sender
        self._lease_seconds = max(1.0, lease_seconds)
        self._poll_seconds = max(0.01, poll_seconds)
        self._max_backoff_seconds = max(1.0, max_backoff_seconds)
        self._audit_collection = audit_collection
        self._stop = asyncio.Event()
        self._task: asyncio.Task[None] | None = None
        self._depth_emitted_at: datetime | None = None
        self._depth_interval_seconds = 60.0

    async def forward_once(self) -> bool:
        now = datetime.now(UTC)
        lease_expired = now - timedelta(seconds=self._lease_seconds)
        document = await self._collection.find_one_and_update(
            {
                "$or": [
                    {
                        "status": {"$in": ["pending", "retry"]},
                        "available_at": {"$lte": now},
                    },
                    {"status": "processing", "claimed_at": {"$lte": lease_expired}},
                ]
            },
            {
                "$set": {"status": "processing", "claimed_at": now},
                "$inc": {"attempt_count": 1},
            },
            sort=[("available_at", 1), ("created_at", 1)],
            return_document=ReturnDocument.AFTER,
        )
        if not document:
            return False

        event_id = str(document["event_id"])
        outbound = {
            key: document.get(key)
            for key in (
                "event_id",
                "user_id",
                "session_id",
                "concept_id",
                "outcome",
                "confidence",
                "observed_at",
                "payload",
            )
        }
        try:
            response = await self._sender([outbound])
            acknowledged = set(response.get("accepted_event_ids", [])) | set(
                response.get("duplicate_event_ids", [])
            )
            if event_id not in acknowledged:
                raise RuntimeError("backend_ack_missing_event")
            delivered_at = datetime.now(UTC)
            await self._collection.update_one(
                {"event_id": event_id, "status": "processing"},
                {
                    "$set": {
                        "status": "delivered",
                        "delivered_at": delivered_at,
                        "last_error_code": None,
                    },
                    "$unset": {"claimed_at": ""},
                },
            )
            return True
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            await self._reschedule_after_failure(document, event_id, exc)
            return False

    async def _reschedule_after_failure(
        self, document: dict[str, Any], event_id: str, exc: BaseException
    ) -> None:
        """Decide what a failed delivery means for this observation.

        Three outcomes, because the failures are not alike: park it until the
        receiver is back, abandon it because it will never be accepted, or back
        off and try again.
        """
        attempts = max(1, int(document.get("attempt_count", 1)))
        status_code = _response_status(exc)
        error_code = type(exc).__name__[:100]
        now = datetime.now(UTC)

        if status_code in _RECEIVER_OFF_STATUSES:
            # Hand the attempt back: the observation never got a real try, and a
            # long disabled spell must not exhaust its budget.
            await self._collection.update_one(
                {"event_id": event_id, "status": "processing"},
                {
                    "$set": {
                        "status": "retry",
                        "available_at": now
                        + timedelta(seconds=RECEIVER_OFF_BACKOFF_SECONDS),
                        "last_error_code": f"receiver_off_{status_code}",
                    },
                    "$inc": {"attempt_count": -1},
                    "$unset": {"claimed_at": ""},
                },
            )
            _telemetry_event("learner_state_degraded_total.receiver_off")
            return

        permanent = status_code in _PERMANENT_REJECTION_STATUSES
        exhausted = attempts >= MAX_DELIVERY_ATTEMPTS
        if permanent or exhausted:
            await self._collection.update_one(
                {"event_id": event_id, "status": "processing"},
                {
                    "$set": {
                        "status": "dead",
                        # Only `delivered_at` and `dead_at` carry a TTL, so a row
                        # that reaches neither would live in the collection
                        # forever. This is what makes the spool bounded.
                        "dead_at": now,
                        "last_error_code": (
                            f"rejected_{status_code}" if permanent else error_code
                        ),
                    },
                    "$unset": {"claimed_at": ""},
                },
            )
            logger.error(
                "learner observation %s abandoned after %d attempt(s): %s",
                event_id,
                attempts,
                error_code if not permanent else f"HTTP {status_code}",
            )
            _telemetry_event("learner_state_degraded_total.observation_dead")
            return

        delay = min(self._max_backoff_seconds, 2 ** min(attempts - 1, 8))
        await self._collection.update_one(
            {"event_id": event_id, "status": "processing"},
            {
                "$set": {
                    "status": "retry",
                    "available_at": now + timedelta(seconds=delay),
                    "last_error_code": error_code,
                },
                "$unset": {"claimed_at": ""},
            },
        )

    async def _emit_queue_depth(self) -> None:
        """Publish how much is still waiting.

        Driven by the loop rather than by a successful delivery: the depth
        matters most when nothing is being delivered, and emitting it on success
        meant it went stale exactly then. Once per interval regardless of
        traffic, so a parked backlog of ten thousand rows is one count, not ten
        thousand.
        """
        now = datetime.now(UTC)
        if (
            self._depth_emitted_at is not None
            and (now - self._depth_emitted_at).total_seconds()
            < self._depth_interval_seconds
        ):
            return
        self._depth_emitted_at = now
        try:
            depth = await self._collection.count_documents(
                {"status": {"$in": ["pending", "retry", "processing"]}}
            )
            _telemetry_event(
                "learner_observation_queue_depth", value=int(depth), gauge=True
            )
        except Exception:
            pass

    async def _run(self) -> None:
        while not self._stop.is_set():
            await self._emit_queue_depth()
            try:
                handled = await self.forward_once()
                if not handled:
                    handled = await self.reconcile_once()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("learner observation worker loop degraded")
                _telemetry_event("learner_state_degraded_total.worker_loop")
                handled = False
            if not handled:
                try:
                    await asyncio.wait_for(self._stop.wait(), timeout=self._poll_seconds)
                except TimeoutError:
                    pass

    async def reconcile_once(self) -> bool:
        """Last-resort replay for interactions whose bounded spool write failed."""
        if self._audit_collection is None:
            return False
        now = datetime.now(UTC)
        lease_expired = now - timedelta(seconds=self._lease_seconds)
        marker = await self._audit_collection.find_one_and_update(
            {
                "$or": [
                    {"observation_reconcile.status": {"$in": ["pending", "retry"]}},
                    {
                        "observation_reconcile.status": "processing",
                        "observation_reconcile.claimed_at": {"$lte": lease_expired},
                    },
                ]
            },
            {
                "$set": {
                    "observation_reconcile.status": "processing",
                    "observation_reconcile.claimed_at": now,
                },
                "$inc": {"observation_reconcile.attempt_count": 1},
            },
            return_document=ReturnDocument.AFTER,
        )
        if not marker:
            return False
        observations = list(marker.get("observation_reconcile", {}).get("observations") or [])
        try:
            response = await self._sender(observations[:60])
            acknowledged = set(response.get("accepted_event_ids", [])) | set(
                response.get("duplicate_event_ids", [])
            )
            expected = {str(item.get("event_id")) for item in observations}
            if not expected.issubset(acknowledged):
                raise RuntimeError("backend_ack_missing_event")
            await self._audit_collection.update_one(
                {"_id": marker["_id"]},
                {
                    "$set": {
                        "observation_reconcile.status": "delivered",
                        "observation_reconcile.delivered_at": datetime.now(UTC),
                    },
                    "$unset": {"observation_reconcile.observations": ""},
                },
            )
            return True
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            attempts = int(marker.get("observation_reconcile", {}).get("attempt_count") or 1)
            status = "dead" if attempts >= 10 else "retry"
            await self._audit_collection.update_one(
                {"_id": marker["_id"]},
                {
                    "$set": {
                        "observation_reconcile.status": status,
                        "observation_reconcile.last_error_code": type(exc).__name__[:100],
                    }
                },
            )
            return False

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._stop.clear()
            self._task = asyncio.create_task(self._run(), name="learner-observation-spool")

    async def stop(self, *, timeout_seconds: float = 5.0) -> None:
        self._stop.set()
        if self._task is None:
            return
        try:
            await asyncio.wait_for(self._task, timeout=max(0.1, timeout_seconds))
        except TimeoutError:
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
        finally:
            self._task = None


_SPOOL: LearnerObservationSpool | None = None
_FORWARDER: SpoolForwarder | None = None


def get_learner_observation_spool() -> LearnerObservationSpool:
    global _SPOOL
    if _SPOOL is None:
        from api.core.database import mongodb_manager

        collection = mongodb_manager.db["learner_observation_spool"].with_options(
            write_concern=WriteConcern(w="majority", wtimeout=20)
        )
        _SPOOL = LearnerObservationSpool(collection, write_timeout_ms=20)
    return _SPOOL


def start_learner_observation_forwarder() -> None:
    global _FORWARDER
    if _FORWARDER is None:
        from api.clients.learner_state_client import get_learner_state_client
        from api.core.database import mongodb_manager

        collection = mongodb_manager.db["learner_observation_spool"]
        client = get_learner_state_client()
        _FORWARDER = SpoolForwarder(
            collection,
            client.send_observations,
            audit_collection=mongodb_manager.db["ai_interactions"],
        )
    _FORWARDER.start()


async def stop_learner_observation_forwarder() -> None:
    global _FORWARDER, _SPOOL
    if _FORWARDER is not None:
        await _FORWARDER.stop(timeout_seconds=5.0)
    _FORWARDER = None
    _SPOOL = None


async def persist_trace_observations(
    *,
    user_id: str,
    session_id: str,
    turn_id: str,
    trace_result: dict[str, Any],
    skill: str | None = None,
    difficulty_level: str | None = None,
) -> dict[str, Any]:
    """Persist bounded concept evidence without retaining conversational text.

    When `skill` is given, the first observation of the turn also carries the
    skill/score payload the backend turns into a CEFR skill result — a
    conversation is speaking or writing practice, and until this existed an
    hour of talking to Lexi moved neither score.

    Only the first observation carries it, so one turn produces one skill
    result rather than one per linked concept. That also means a turn that
    linked no concepts at all records no skill evidence: the anchor rides on
    a real concept observation, which is what makes it idempotent (the
    backend dedupes on event_id) without a second dedup table.
    """
    from api.core.config import settings

    if settings.LEARNER_STATE_MODE == "off":
        return {"observation_count": 0, "observation_durability_degraded": False}
    if not user_id or not turn_id:
        return {"observation_count": 0, "observation_durability_degraded": False}
    concept_ids = list(
        dict.fromkeys(
            str(item)
            for item in (
                list(trace_result.get("linked_concepts") or [])
                + list(trace_result.get("kg_seed_concepts") or [])
                + list(trace_result.get("diagnosis_root_causes") or [])
            )
            if item
        )
    )[:60]
    errors = list(trace_result.get("diagnosis_errors") or [])
    outcome = "incorrect" if errors else "correct"
    confidence = 0.8 if errors else 0.6
    spool = get_learner_observation_spool()

    def _payload(is_anchor: bool) -> dict[str, Any]:
        payload: dict[str, Any] = {"error_count": len(errors)}
        if is_anchor and skill:
            payload["skill"] = skill
            # Fewer mistakes is a better turn. Capped at four so a long turn
            # with many corrections floors at 0 rather than going negative.
            payload["score"] = max(0.0, 100.0 - 25.0 * min(len(errors), 4))
            if difficulty_level:
                payload["difficulty_level"] = difficulty_level
        return payload

    observations = [
            LearnerObservation(
                user_id=str(user_id),
                session_id=str(session_id),
                turn_id=str(turn_id),
                concept_id=concept_id,
                observation_kind="tracecag_turn",
                outcome=outcome,
                confidence=confidence,
                observed_at=datetime.now(UTC),
                payload=_payload(index == 0),
            )
        for index, concept_id in enumerate(concept_ids)
    ]
    results = await spool.persist_many(observations)
    degraded = any(not result.durable for result in results)
    if degraded and observations:
        try:
            from api.core.database import mongodb_manager

            outbound = [
                {
                    "event_id": deterministic_event_id(item),
                    "user_id": item.user_id,
                    "session_id": item.session_id,
                    "concept_id": item.concept_id,
                    "outcome": item.outcome,
                    "confidence": item.confidence,
                    "observed_at": item.observed_at,
                    "payload": _sanitized_payload(item.payload),
                }
                for item in observations
            ]
            async with asyncio.timeout(0.020):
                await mongodb_manager.db["ai_interactions"].update_one(
                    {"observation_reconcile.turn_id": str(turn_id)},
                    {
                        "$setOnInsert": {
                            "created_at": datetime.now(UTC),
                            "indexed_at": datetime.now(UTC),
                            "observation_reconcile": {
                                "turn_id": str(turn_id),
                                "status": "pending",
                                "attempt_count": 0,
                                "observations": outbound,
                            },
                        }
                    },
                    upsert=True,
                )
        except Exception:
            logger.critical("learner observation audit reconciliation marker failed")
    return {
        "observation_count": len(concept_ids),
        "observation_durability_degraded": degraded,
    }
