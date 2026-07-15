import asyncio
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest

from api.services.learner_observation_spool import (
    LearnerObservation,
    LearnerObservationSpool,
    SpoolForwarder,
    deterministic_event_id,
)
from api.services import learner_observation_spool as spool_module


def observation(**overrides):
    values = {
        "user_id": "11111111-1111-1111-1111-111111111111",
        "session_id": "session-1",
        "turn_id": "turn-4",
        "concept_id": "concept:past_tense",
        "observation_kind": "diagnosis",
        "outcome": "incorrect",
        "confidence": 0.8,
        "observed_at": datetime(2026, 7, 13, tzinfo=UTC),
        "payload": {"error_type": "past_tense"},
    }
    values.update(overrides)
    return LearnerObservation(**values)


def test_event_identity_is_deterministic_and_turn_scoped():
    first = deterministic_event_id(observation())
    assert first == deterministic_event_id(observation())
    assert first != deterministic_event_id(observation(turn_id="turn-5"))
    assert len(first) == 64


@pytest.mark.asyncio
async def test_spool_persists_pending_idempotently_without_prompt_or_token_data():
    collection = MagicMock()
    collection.update_one = AsyncMock(return_value=MagicMock(upserted_id="mongo-id"))
    spool = LearnerObservationSpool(collection, write_timeout_ms=20)

    item = observation(payload={"error_type": "past_tense"})
    result = await spool.persist(item)

    assert result.durable is True
    event_id = deterministic_event_id(item)
    query, update = collection.update_one.await_args.args[:2]
    kwargs = collection.update_one.await_args.kwargs
    assert query == {"event_id": event_id}
    assert kwargs["upsert"] is True
    document = update["$setOnInsert"]
    assert document["status"] == "pending"
    assert document["event_id"] == event_id
    assert "prompt" not in str(document).lower()
    assert "token" not in str(document).lower()
    assert "delivered_at" not in document


@pytest.mark.asyncio
async def test_spool_failure_degrades_chat_boundary_instead_of_raising():
    collection = MagicMock()
    collection.update_one = AsyncMock(side_effect=TimeoutError("mongo slow"))
    spool = LearnerObservationSpool(collection, write_timeout_ms=20)

    result = await spool.persist(observation())

    assert result.durable is False
    assert result.reason in {"timeout", "storage_error"}


@pytest.mark.asyncio
async def test_bulk_persist_uses_one_unordered_write_and_strict_payload_allowlist():
    collection = MagicMock()
    collection.bulk_write = AsyncMock(return_value=MagicMock(upserted_count=2))
    spool = LearnerObservationSpool(collection, write_timeout_ms=20)

    results = await spool.persist_many(
        [
            observation(concept_id="a", payload={"error_count": 1, "prompt": "secret"}),
            observation(
                concept_id="b",
                payload={"source": "trace", "raw_text": "private", "error_count": []},
            ),
        ]
    )

    assert all(result.durable for result in results)
    collection.bulk_write.assert_awaited_once()
    operations = collection.bulk_write.await_args.args[0]
    assert collection.bulk_write.await_args.kwargs == {"ordered": False}
    documents = [operation._doc["$setOnInsert"] for operation in operations]
    assert documents[0]["payload"] == {"error_count": 1}
    assert documents[1]["payload"] == {"source": "trace"}


@pytest.mark.asyncio
async def test_bulk_failure_returns_degraded_result_for_every_event():
    collection = MagicMock()
    collection.bulk_write = AsyncMock(side_effect=TimeoutError("slow"))
    spool = LearnerObservationSpool(collection, write_timeout_ms=20)

    results = await spool.persist_many(
        [observation(concept_id="a"), observation(concept_id="b")]
    )

    assert [result.durable for result in results] == [False, False]
    assert [result.reason for result in results] == ["timeout", "timeout"]


@pytest.mark.asyncio
async def test_forwarder_replays_same_event_after_lost_ack_and_marks_delivered():
    event_id = "a" * 64
    document = {
        "event_id": event_id,
        "user_id": "11111111-1111-1111-1111-111111111111",
        "session_id": "session-1",
        "concept_id": "concept:a",
        "outcome": "incorrect",
        "confidence": 0.8,
        "observed_at": datetime(2026, 7, 13, tzinfo=UTC),
        "payload": {},
    }
    collection = MagicMock()
    collection.find_one_and_update = AsyncMock(side_effect=[document, document])
    collection.update_one = AsyncMock()
    sender = AsyncMock(
        side_effect=[TimeoutError("ack lost"), {"duplicate_event_ids": [event_id]}]
    )
    worker = SpoolForwarder(collection, sender, lease_seconds=30)

    assert await worker.forward_once() is False
    assert await worker.forward_once() is True

    sent_ids = [call.args[0][0]["event_id"] for call in sender.await_args_list]
    assert sent_ids == [event_id, event_id]
    final_update = collection.update_one.await_args_list[-1].args[1]
    assert final_update["$set"]["status"] == "delivered"
    assert isinstance(final_update["$set"]["delivered_at"], datetime)


def test_spool_singleton_requests_majority_write_concern(monkeypatch):
    from api.core.database import mongodb_manager

    collection = MagicMock()
    durable_collection = MagicMock()
    collection.with_options.return_value = durable_collection
    database = MagicMock()
    database.__getitem__.return_value = collection
    monkeypatch.setattr(mongodb_manager, "_db", database)
    monkeypatch.setattr(spool_module, "_SPOOL", None)

    spool = spool_module.get_learner_observation_spool()

    concern = collection.with_options.call_args.kwargs["write_concern"]
    assert concern.document["w"] == "majority"
    assert concern.document["wtimeout"] == 20
    assert spool._collection is durable_collection


@pytest.mark.asyncio
async def test_forwarder_missing_event_ack_retries_instead_of_marking_delivered():
    event_id = "b" * 64
    document = {
        "event_id": event_id,
        "user_id": "11111111-1111-1111-1111-111111111111",
        "session_id": "session-1",
        "concept_id": "concept:a",
        "outcome": "correct",
        "confidence": 0.6,
        "observed_at": datetime(2026, 7, 13, tzinfo=UTC),
        "payload": {},
        "attempt_count": 3,
    }
    collection = MagicMock()
    collection.find_one_and_update = AsyncMock(return_value=document)
    collection.update_one = AsyncMock()
    worker = SpoolForwarder(collection, AsyncMock(return_value={}))

    assert await worker.forward_once() is False

    update = collection.update_one.await_args.args[1]
    assert update["$set"]["status"] == "retry"
    assert update["$set"]["last_error_code"] == "RuntimeError"
    assert "delivered_at" not in update["$set"]


@pytest.mark.asyncio
async def test_forwarder_lifecycle_start_and_stop_is_idempotent():
    collection = MagicMock()
    collection.find_one_and_update = AsyncMock(return_value=None)
    worker = SpoolForwarder(collection, AsyncMock(), poll_seconds=0.01)

    worker.start()
    first_task = worker._task
    worker.start()
    assert worker._task is first_task

    await worker.stop(timeout_seconds=0.2)
    await worker.stop(timeout_seconds=0.2)
    assert worker._task is None


@pytest.mark.asyncio
async def test_reconciler_requires_ack_for_every_observation_before_delivery():
    observations = [{"event_id": "a"}, {"event_id": "b"}]
    audit = MagicMock()
    audit.find_one_and_update = AsyncMock(
        return_value={
            "_id": "audit-1",
            "observation_reconcile": {"observations": observations},
        }
    )
    audit.update_one = AsyncMock()
    sender = AsyncMock(return_value={"accepted_event_ids": ["a"]})
    worker = SpoolForwarder(MagicMock(), sender, audit_collection=audit)

    assert await worker.reconcile_once() is False

    update = audit.update_one.await_args.args[1]
    assert update["$set"]["observation_reconcile.status"] == "retry"
    assert "delivered_at" not in str(update)


@pytest.mark.asyncio
async def test_worker_loop_survives_transient_claim_error():
    worker = SpoolForwarder(MagicMock(), AsyncMock(), poll_seconds=0.01)
    recovered = asyncio.Event()

    async def forward_once():
        if not recovered.is_set():
            recovered.set()
            raise RuntimeError("mongo transient")
        worker._stop.set()
        return False

    worker.forward_once = AsyncMock(side_effect=forward_once)
    worker.reconcile_once = AsyncMock(return_value=False)

    await asyncio.wait_for(worker._run(), timeout=0.2)

    assert worker.forward_once.await_count == 2


@pytest.mark.asyncio
async def test_reconciler_reclaims_expired_processing_lease_and_dead_letters():
    audit = MagicMock()
    audit.find_one_and_update = AsyncMock(
        return_value={
            "_id": "audit-1",
            "observation_reconcile": {
                "attempt_count": 10,
                "observations": [{"event_id": "a"}],
            },
        }
    )
    audit.update_one = AsyncMock()
    worker = SpoolForwarder(
        MagicMock(), AsyncMock(side_effect=RuntimeError("bad")), audit_collection=audit
    )

    assert await worker.reconcile_once() is False

    claim_filter = audit.find_one_and_update.await_args.args[0]
    assert claim_filter["$or"][1]["observation_reconcile.status"] == "processing"
    assert "$lte" in claim_filter["$or"][1]["observation_reconcile.claimed_at"]
    update = audit.update_one.await_args.args[1]
    assert update["$set"]["observation_reconcile.status"] == "dead"


@pytest.mark.asyncio
async def test_fallback_marker_write_is_bounded_by_timeout(monkeypatch):
    from api.core.database import mongodb_manager

    spool = MagicMock()
    spool.persist_many = AsyncMock(
        return_value=[spool_module.SpoolPersistResult(event_id="a", durable=False)]
    )
    monkeypatch.setattr(spool_module, "get_learner_observation_spool", lambda: spool)
    monkeypatch.setattr("api.core.config.settings.LEARNER_STATE_MODE", "read")
    database = MagicMock()
    audit = MagicMock()

    async def blocked_update(*_args, **_kwargs):
        await asyncio.Event().wait()

    audit.update_one = AsyncMock(side_effect=blocked_update)
    database.__getitem__.return_value = audit
    monkeypatch.setattr(mongodb_manager, "_db", database)

    started = asyncio.get_running_loop().time()
    result = await spool_module.persist_trace_observations(
        user_id="u", session_id="s", turn_id="t", trace_result={"linked_concepts": ["a"]}
    )

    assert asyncio.get_running_loop().time() - started < 0.1
    assert result["observation_durability_degraded"] is True


@pytest.mark.asyncio
async def test_trace_persistence_reports_count_and_any_durability_degradation(
    monkeypatch,
):
    monkeypatch.setattr("api.core.config.settings.LEARNER_STATE_MODE", "read")
    spool = MagicMock()
    spool.persist_many = AsyncMock(
        return_value=[
            spool_module.SpoolPersistResult(event_id="a", durable=True),
            spool_module.SpoolPersistResult(
                event_id="b", durable=False, reason="timeout"
            ),
        ]
    )
    monkeypatch.setattr(spool_module, "get_learner_observation_spool", lambda: spool)

    metadata = await spool_module.persist_trace_observations(
        user_id="user-1",
        session_id="session-1",
        turn_id="turn-1",
        trace_result={"linked_concepts": ["a", "b", "a"]},
    )

    assert metadata == {
        "observation_count": 2,
        "observation_durability_degraded": True,
    }
    persisted = spool.persist_many.await_args.args[0]
    assert [item.concept_id for item in persisted] == ["a", "b"]


def test_mongo_indexes_include_unique_claim_and_delivered_only_ttl():
    source = (Path(__file__).parents[1] / "api" / "main.py").read_text()

    assert "learner_observation_spool_event_id_uq" in source
    assert "learner_observation_spool_claim_idx" in source
    assert "learner_observation_spool_delivered_ttl" in source
    assert '[("status", ASCENDING), ("available_at", ASCENDING)]' in source
    assert '[("delivered_at", ASCENDING)]' in source
    assert "expireAfterSeconds=90 * 24 * 60 * 60" in source
