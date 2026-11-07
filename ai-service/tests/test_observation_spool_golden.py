import asyncio
import copy
import hashlib
import json
import logging
import subprocess
from contextlib import ExitStack
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, create_autospec, patch

import pytest

from api.core.config import settings
from api.services import learner_observation_spool as spool_module
from api.services.learner_observation_spool import (
    LearnerObservation,
    LearnerObservationSpool,
    SpoolPersistResult,
    deterministic_event_id,
    persist_trace_observations,
)
from api.services.trace_cag.graph import TraceCAGPipeline

CAPTURED_FROM_SPOOL_SHA256 = "1dc0dbf6f0a593a617a00726e1d24eab8cf4417208fc1cc489de30bd5955b76a"
CAPTURED_FROM_COMMIT = "15663a3c46ed11e18c0a3d0c8756aaf30b75c490"
BASELINE_SPOOL_SHA256 = "67802adb452b55a1a54f478327fb9b93d3c968316b47ef546e83fde309dd5b86"

FIXED = datetime(2026, 11, 6, 12, 0, 0, tzinfo=UTC)
USER, SESSION, TURN = "user-1", "session-1", "turn-1"


class _Frozen(datetime):
    @classmethod
    def now(cls, tz=None):
        return FIXED


def _ids(prefix: str, n: int) -> list[str]:
    return [f"concept:{prefix}{i:02d}" for i in range(1, n + 1)]


def _errors(n: int) -> list[dict]:
    return [
        {"span": f"w{i}", "correction": f"c{i}", "type": "grammar", "explanation": f"e{i}"}
        for i in range(n)
    ]


def _state(seeds=(), root=(), errors=0, linked=None) -> dict:
    state = {
        "user_input": "w0 w1 w2 w3 w4 w5",
        "kg_seed_concepts": list(seeds),
        "diagnosis_root_causes": list(root),
        "diagnosis_errors": _errors(errors),
    }
    if linked is not None:
        state["linked_concepts"] = list(linked)
    return state


STATES = {
    "err17_rc": (_state(_ids("t", 17), ["concept:g01", "concept:t03"], 2), "writing", "B1"),
    "err17_norc": (_state(_ids("t", 17), [], 2), "writing", "B1"),
    "err17_noskill": (_state(_ids("t", 17), ["concept:g01"], 2), None, None),
    "clean": (_state(_ids("t", 5), [], 0), "writing", "B1"),
    "clean_noskill": (_state(_ids("t", 5), [], 0), None, None),
    "noconcept_skill": (_state([], [], 0), "speaking", "A2"),
    "noconcept_skill_err": (_state([], [], 3), "speaking", "A2"),
    "skill_no_difficulty": (_state(_ids("t", 3), ["concept:g01"], 1), "writing", None),
    "skill_err1": (_state(_ids("t", 3), ["concept:g01"], 1), "writing", "C1"),
    "skill_err4": (_state(_ids("t", 3), ["concept:g01"], 4), "writing", "C1"),
    "skill_err6": (_state(_ids("t", 3), ["concept:g01"], 6), "writing", "C1"),
    "cap_70": (_state(_ids("t", 70), _ids("g", 3), 1), "writing", "B2"),
    "cap_59_plus_2": (_state(_ids("t", 59), _ids("g", 2), 1), "writing", "B2"),
    "dedupe_all_lists": (
        _state(
            ["concept:a", "concept:b", "concept:c", "concept:a", "", "concept:d"],
            ["concept:c", "concept:e", None, "concept:a", "concept:f"],
            1,
            linked=["concept:z", "concept:a"],
        ),
        "writing",
        "B1",
    ),
}

AS_IS = {
    "pipeline_error": (
        {"tutor_response": "", "error": "boom", "metadata": {"path": "error"}},
        "writing",
        "B1",
    ),
    "empty_dict": ({}, "writing", "B1"),
}

DEGRADED_CASES = ("err17_rc", "clean", "noconcept_skill_err", "cap_70")


def _build_specs() -> dict[str, dict]:
    specs: dict[str, dict] = {}

    def add(case, shape, mode="read", user=USER, turn=TURN, durable=True, tag=None):
        key = "|".join(
            [case, shape, mode, "u" if user else "nouser", "t" if turn else "noturn",
             "durable" if durable else "degraded"]
        )
        specs[key] = dict(case=case, shape=shape, mode=mode, user=user, turn=turn, durable=durable)

    for case in STATES:
        for shape in ("raw", "formatted"):
            add(case, shape)
    for case in AS_IS:
        add(case, "as_is")
    for case in DEGRADED_CASES:
        for shape in ("raw", "formatted"):
            add(case, shape, durable=False)
    for shape in ("raw", "formatted"):
        add("err17_rc", shape, mode="off")
        add("err17_rc", shape, mode="shadow")
        add("err17_rc", shape, mode="primary")
        add("err17_rc", shape, user="")
        add("err17_rc", shape, user=None)
        add("err17_rc", shape, turn="")
        add("err17_rc", shape, turn=None)
    return specs


SPECS = _build_specs()


def _input(spec: dict) -> tuple[dict, str | None, str | None]:
    pool = AS_IS if spec["case"] in AS_IS else STATES
    raw, skill, difficulty = pool[spec["case"]]
    raw = copy.deepcopy(raw)
    if spec["shape"] == "formatted":
        return TraceCAGPipeline._format_response(SimpleNamespace(), raw), skill, difficulty
    return raw, skill, difficulty


def _dump(item: LearnerObservation) -> dict:
    return {
        "user_id": item.user_id,
        "session_id": item.session_id,
        "turn_id": item.turn_id,
        "concept_id": item.concept_id,
        "observation_kind": item.observation_kind,
        "outcome": item.outcome,
        "confidence": item.confidence,
        "observed_at": item.observed_at.isoformat(),
        "payload": item.payload,
        "event_id": deterministic_event_id(item),
    }


def _sha(obj) -> str:
    return hashlib.sha256(json.dumps(obj, sort_keys=True, default=str).encode()).hexdigest()


async def capture(spec: dict) -> dict:
    trace_result, skill, difficulty = _input(spec)
    before = copy.deepcopy(trace_result)
    seen: list[list[LearnerObservation]] = []
    calls = {"n": 0, "positional_only": True}

    async def persist_many(observations, *args, **kwargs):
        calls["n"] += 1
        calls["positional_only"] = calls["positional_only"] and not args and not kwargs
        seen.append(list(observations))
        return [
            SpoolPersistResult(event_id=deterministic_event_id(o), durable=spec["durable"])
            for o in observations
        ]

    fake = create_autospec(LearnerObservationSpool, instance=True)
    fake.persist_many.side_effect = persist_many
    collections = {}

    def _collection(name):
        collections.setdefault(name, MagicMock(update_one=AsyncMock()))
        return collections[name]

    manager = MagicMock()
    manager.db.__getitem__.side_effect = _collection

    with ExitStack() as stack:
        stack.enter_context(patch.object(settings, "LEARNER_STATE_MODE", spec["mode"]))
        stack.enter_context(patch.object(settings, "LEARNER_OBSERVATION_DIAGNOSED_ONLY", False))
        stack.enter_context(patch.object(spool_module, "datetime", _Frozen))
        stack.enter_context(
            patch.object(
                spool_module, "get_learner_observation_spool", autospec=True, return_value=fake
            )
        )
        stack.enter_context(patch("api.core.database.mongodb_manager", manager))
        returned = await persist_trace_observations(
            user_id=spec["user"],
            session_id=SESSION,
            turn_id=spec["turn"],
            trace_result=trace_result,
            skill=skill,
            difficulty_level=difficulty,
        )

    assert trace_result == before
    observations = seen[0] if seen else []
    dumped = [_dump(o) for o in observations]
    marker = None
    if "ai_interactions" in collections:
        update_one = collections["ai_interactions"].update_one
        assert update_one.await_count == 1
        args, kwargs = update_one.await_args
        marker = {
            "filter": args[0],
            "kwargs": kwargs,
            "sha256": _sha(args[1]),
            "n_observations": len(args[1]["$setOnInsert"]["observation_reconcile"]["observations"]),
            "status": args[1]["$setOnInsert"]["observation_reconcile"]["status"],
            "attempt_count": args[1]["$setOnInsert"]["observation_reconcile"]["attempt_count"],
            "turn_id": args[1]["$setOnInsert"]["observation_reconcile"]["turn_id"],
            "created_at": args[1]["$setOnInsert"]["created_at"].isoformat(),
            "indexed_at": args[1]["$setOnInsert"]["indexed_at"].isoformat(),
        }
    return {
        "returned": returned,
        "persist_many_calls": calls["n"],
        "positional_only": calls["positional_only"],
        "collections_touched": sorted(collections),
        "n": len(dumped),
        "obs": [
            [d["concept_id"], d["outcome"], d["confidence"], d["payload"]] for d in dumped
        ],
        "event_ids": [dumped[0]["event_id"], dumped[-1]["event_id"]] if dumped else [],
        "sha256": _sha(dumped),
        "marker": marker,
    }


# GOLDEN-BEGIN
EXPECTED = {
    "cap_59_plus_2|formatted|read|u|t|durable": {
        "returned": {"observation_count": 59, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 59,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B2"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
            ["concept:t18", "correct", 0.6, {"error_count": 0}],
            ["concept:t19", "correct", 0.6, {"error_count": 0}],
            ["concept:t20", "correct", 0.6, {"error_count": 0}],
            ["concept:t21", "correct", 0.6, {"error_count": 0}],
            ["concept:t22", "correct", 0.6, {"error_count": 0}],
            ["concept:t23", "correct", 0.6, {"error_count": 0}],
            ["concept:t24", "correct", 0.6, {"error_count": 0}],
            ["concept:t25", "correct", 0.6, {"error_count": 0}],
            ["concept:t26", "correct", 0.6, {"error_count": 0}],
            ["concept:t27", "correct", 0.6, {"error_count": 0}],
            ["concept:t28", "correct", 0.6, {"error_count": 0}],
            ["concept:t29", "correct", 0.6, {"error_count": 0}],
            ["concept:t30", "correct", 0.6, {"error_count": 0}],
            ["concept:t31", "correct", 0.6, {"error_count": 0}],
            ["concept:t32", "correct", 0.6, {"error_count": 0}],
            ["concept:t33", "correct", 0.6, {"error_count": 0}],
            ["concept:t34", "correct", 0.6, {"error_count": 0}],
            ["concept:t35", "correct", 0.6, {"error_count": 0}],
            ["concept:t36", "correct", 0.6, {"error_count": 0}],
            ["concept:t37", "correct", 0.6, {"error_count": 0}],
            ["concept:t38", "correct", 0.6, {"error_count": 0}],
            ["concept:t39", "correct", 0.6, {"error_count": 0}],
            ["concept:t40", "correct", 0.6, {"error_count": 0}],
            ["concept:t41", "correct", 0.6, {"error_count": 0}],
            ["concept:t42", "correct", 0.6, {"error_count": 0}],
            ["concept:t43", "correct", 0.6, {"error_count": 0}],
            ["concept:t44", "correct", 0.6, {"error_count": 0}],
            ["concept:t45", "correct", 0.6, {"error_count": 0}],
            ["concept:t46", "correct", 0.6, {"error_count": 0}],
            ["concept:t47", "correct", 0.6, {"error_count": 0}],
            ["concept:t48", "correct", 0.6, {"error_count": 0}],
            ["concept:t49", "correct", 0.6, {"error_count": 0}],
            ["concept:t50", "correct", 0.6, {"error_count": 0}],
            ["concept:t51", "correct", 0.6, {"error_count": 0}],
            ["concept:t52", "correct", 0.6, {"error_count": 0}],
            ["concept:t53", "correct", 0.6, {"error_count": 0}],
            ["concept:t54", "correct", 0.6, {"error_count": 0}],
            ["concept:t55", "correct", 0.6, {"error_count": 0}],
            ["concept:t56", "correct", 0.6, {"error_count": 0}],
            ["concept:t57", "correct", 0.6, {"error_count": 0}],
            ["concept:t58", "correct", 0.6, {"error_count": 0}],
            ["concept:t59", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e0dbffc12597c0e20b93fd861b9f1746e8754091828301036e944eb6fde62409"],
        "sha256": "04f1317b5b4d917951debce5abf10ff4c861e4caac3f6fff3efb40ac71f81dea",
        "marker": None,
    },
    "cap_59_plus_2|raw|read|u|t|durable": {
        "returned": {"observation_count": 60, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 60,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 1, "skill": "writing", "score": 75.0, "difficulty_level": "B2"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t18", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t19", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t20", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t21", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t22", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t23", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t24", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t25", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t26", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t27", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t28", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t29", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t30", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t31", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t32", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t33", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t34", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t35", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t36", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t37", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t38", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t39", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t40", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t41", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t42", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t43", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t44", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t45", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t46", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t47", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t48", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t49", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t50", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t51", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t52", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t53", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t54", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t55", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t56", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t57", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t58", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t59", "incorrect", 0.8, {"error_count": 1}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 1}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "afb96bb3967886f25df6930b0eb3328b1ae9214df7f4a9b181abf781c9e36eb6",
        "marker": None,
    },
    "cap_70|formatted|read|u|t|degraded": {
        "returned": {"observation_count": 60, "observation_durability_degraded": True},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": ["ai_interactions"],
        "n": 60,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B2"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
            ["concept:t18", "correct", 0.6, {"error_count": 0}],
            ["concept:t19", "correct", 0.6, {"error_count": 0}],
            ["concept:t20", "correct", 0.6, {"error_count": 0}],
            ["concept:t21", "correct", 0.6, {"error_count": 0}],
            ["concept:t22", "correct", 0.6, {"error_count": 0}],
            ["concept:t23", "correct", 0.6, {"error_count": 0}],
            ["concept:t24", "correct", 0.6, {"error_count": 0}],
            ["concept:t25", "correct", 0.6, {"error_count": 0}],
            ["concept:t26", "correct", 0.6, {"error_count": 0}],
            ["concept:t27", "correct", 0.6, {"error_count": 0}],
            ["concept:t28", "correct", 0.6, {"error_count": 0}],
            ["concept:t29", "correct", 0.6, {"error_count": 0}],
            ["concept:t30", "correct", 0.6, {"error_count": 0}],
            ["concept:t31", "correct", 0.6, {"error_count": 0}],
            ["concept:t32", "correct", 0.6, {"error_count": 0}],
            ["concept:t33", "correct", 0.6, {"error_count": 0}],
            ["concept:t34", "correct", 0.6, {"error_count": 0}],
            ["concept:t35", "correct", 0.6, {"error_count": 0}],
            ["concept:t36", "correct", 0.6, {"error_count": 0}],
            ["concept:t37", "correct", 0.6, {"error_count": 0}],
            ["concept:t38", "correct", 0.6, {"error_count": 0}],
            ["concept:t39", "correct", 0.6, {"error_count": 0}],
            ["concept:t40", "correct", 0.6, {"error_count": 0}],
            ["concept:t41", "correct", 0.6, {"error_count": 0}],
            ["concept:t42", "correct", 0.6, {"error_count": 0}],
            ["concept:t43", "correct", 0.6, {"error_count": 0}],
            ["concept:t44", "correct", 0.6, {"error_count": 0}],
            ["concept:t45", "correct", 0.6, {"error_count": 0}],
            ["concept:t46", "correct", 0.6, {"error_count": 0}],
            ["concept:t47", "correct", 0.6, {"error_count": 0}],
            ["concept:t48", "correct", 0.6, {"error_count": 0}],
            ["concept:t49", "correct", 0.6, {"error_count": 0}],
            ["concept:t50", "correct", 0.6, {"error_count": 0}],
            ["concept:t51", "correct", 0.6, {"error_count": 0}],
            ["concept:t52", "correct", 0.6, {"error_count": 0}],
            ["concept:t53", "correct", 0.6, {"error_count": 0}],
            ["concept:t54", "correct", 0.6, {"error_count": 0}],
            ["concept:t55", "correct", 0.6, {"error_count": 0}],
            ["concept:t56", "correct", 0.6, {"error_count": 0}],
            ["concept:t57", "correct", 0.6, {"error_count": 0}],
            ["concept:t58", "correct", 0.6, {"error_count": 0}],
            ["concept:t59", "correct", 0.6, {"error_count": 0}],
            ["concept:t60", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e8d6817b9cdffbf0d7912453c284abeef9a5eb2ed963687a3098ccae4c1d62b2"],
        "sha256": "10978ecf0458acbd38c4a94562e1664707ef45bdd686c4712963edec6e4ed3b5",
        "marker": {"filter": {"observation_reconcile.turn_id": "turn-1"}, "kwargs": {"upsert": True}, "sha256": "b16b3150ae055b0563c1b3981b3ffaf1e66a152a3d2c4c27ac8c990dcfe9f12b", "n_observations": 60, "status": "pending", "attempt_count": 0, "turn_id": "turn-1", "created_at": "2026-11-06T12:00:00+00:00", "indexed_at": "2026-11-06T12:00:00+00:00"},
    },
    "cap_70|formatted|read|u|t|durable": {
        "returned": {"observation_count": 60, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 60,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B2"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
            ["concept:t18", "correct", 0.6, {"error_count": 0}],
            ["concept:t19", "correct", 0.6, {"error_count": 0}],
            ["concept:t20", "correct", 0.6, {"error_count": 0}],
            ["concept:t21", "correct", 0.6, {"error_count": 0}],
            ["concept:t22", "correct", 0.6, {"error_count": 0}],
            ["concept:t23", "correct", 0.6, {"error_count": 0}],
            ["concept:t24", "correct", 0.6, {"error_count": 0}],
            ["concept:t25", "correct", 0.6, {"error_count": 0}],
            ["concept:t26", "correct", 0.6, {"error_count": 0}],
            ["concept:t27", "correct", 0.6, {"error_count": 0}],
            ["concept:t28", "correct", 0.6, {"error_count": 0}],
            ["concept:t29", "correct", 0.6, {"error_count": 0}],
            ["concept:t30", "correct", 0.6, {"error_count": 0}],
            ["concept:t31", "correct", 0.6, {"error_count": 0}],
            ["concept:t32", "correct", 0.6, {"error_count": 0}],
            ["concept:t33", "correct", 0.6, {"error_count": 0}],
            ["concept:t34", "correct", 0.6, {"error_count": 0}],
            ["concept:t35", "correct", 0.6, {"error_count": 0}],
            ["concept:t36", "correct", 0.6, {"error_count": 0}],
            ["concept:t37", "correct", 0.6, {"error_count": 0}],
            ["concept:t38", "correct", 0.6, {"error_count": 0}],
            ["concept:t39", "correct", 0.6, {"error_count": 0}],
            ["concept:t40", "correct", 0.6, {"error_count": 0}],
            ["concept:t41", "correct", 0.6, {"error_count": 0}],
            ["concept:t42", "correct", 0.6, {"error_count": 0}],
            ["concept:t43", "correct", 0.6, {"error_count": 0}],
            ["concept:t44", "correct", 0.6, {"error_count": 0}],
            ["concept:t45", "correct", 0.6, {"error_count": 0}],
            ["concept:t46", "correct", 0.6, {"error_count": 0}],
            ["concept:t47", "correct", 0.6, {"error_count": 0}],
            ["concept:t48", "correct", 0.6, {"error_count": 0}],
            ["concept:t49", "correct", 0.6, {"error_count": 0}],
            ["concept:t50", "correct", 0.6, {"error_count": 0}],
            ["concept:t51", "correct", 0.6, {"error_count": 0}],
            ["concept:t52", "correct", 0.6, {"error_count": 0}],
            ["concept:t53", "correct", 0.6, {"error_count": 0}],
            ["concept:t54", "correct", 0.6, {"error_count": 0}],
            ["concept:t55", "correct", 0.6, {"error_count": 0}],
            ["concept:t56", "correct", 0.6, {"error_count": 0}],
            ["concept:t57", "correct", 0.6, {"error_count": 0}],
            ["concept:t58", "correct", 0.6, {"error_count": 0}],
            ["concept:t59", "correct", 0.6, {"error_count": 0}],
            ["concept:t60", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e8d6817b9cdffbf0d7912453c284abeef9a5eb2ed963687a3098ccae4c1d62b2"],
        "sha256": "10978ecf0458acbd38c4a94562e1664707ef45bdd686c4712963edec6e4ed3b5",
        "marker": None,
    },
    "cap_70|raw|read|u|t|degraded": {
        "returned": {"observation_count": 60, "observation_durability_degraded": True},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": ["ai_interactions"],
        "n": 60,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 1, "skill": "writing", "score": 75.0, "difficulty_level": "B2"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t18", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t19", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t20", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t21", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t22", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t23", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t24", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t25", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t26", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t27", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t28", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t29", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t30", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t31", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t32", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t33", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t34", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t35", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t36", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t37", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t38", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t39", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t40", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t41", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t42", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t43", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t44", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t45", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t46", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t47", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t48", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t49", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t50", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t51", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t52", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t53", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t54", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t55", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t56", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t57", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t58", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t59", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t60", "incorrect", 0.8, {"error_count": 1}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e8d6817b9cdffbf0d7912453c284abeef9a5eb2ed963687a3098ccae4c1d62b2"],
        "sha256": "1ff373831080a5c213a6087f8e820d41862e881878568c44a00b00bf42bda0ce",
        "marker": {"filter": {"observation_reconcile.turn_id": "turn-1"}, "kwargs": {"upsert": True}, "sha256": "981e7379642e3dbe7c84807b54b65263981100287e1a207e4d038761f8b37ac3", "n_observations": 60, "status": "pending", "attempt_count": 0, "turn_id": "turn-1", "created_at": "2026-11-06T12:00:00+00:00", "indexed_at": "2026-11-06T12:00:00+00:00"},
    },
    "cap_70|raw|read|u|t|durable": {
        "returned": {"observation_count": 60, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 60,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 1, "skill": "writing", "score": 75.0, "difficulty_level": "B2"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t18", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t19", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t20", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t21", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t22", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t23", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t24", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t25", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t26", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t27", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t28", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t29", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t30", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t31", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t32", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t33", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t34", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t35", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t36", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t37", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t38", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t39", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t40", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t41", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t42", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t43", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t44", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t45", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t46", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t47", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t48", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t49", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t50", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t51", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t52", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t53", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t54", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t55", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t56", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t57", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t58", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t59", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t60", "incorrect", 0.8, {"error_count": 1}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e8d6817b9cdffbf0d7912453c284abeef9a5eb2ed963687a3098ccae4c1d62b2"],
        "sha256": "1ff373831080a5c213a6087f8e820d41862e881878568c44a00b00bf42bda0ce",
        "marker": None,
    },
    "clean_noskill|formatted|read|u|t|durable": {
        "returned": {"observation_count": 5, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 5,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "3c084e57a6c273261a69c3093ab9f88be4c5e2efa75c4bb3a544589abcb860e5"],
        "sha256": "838fd3b6f8b0a7101a14559a5a0b2de1fff0dd27eba450802cc5c24aa6996220",
        "marker": None,
    },
    "clean_noskill|raw|read|u|t|durable": {
        "returned": {"observation_count": 5, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 5,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "3c084e57a6c273261a69c3093ab9f88be4c5e2efa75c4bb3a544589abcb860e5"],
        "sha256": "838fd3b6f8b0a7101a14559a5a0b2de1fff0dd27eba450802cc5c24aa6996220",
        "marker": None,
    },
    "clean|formatted|read|u|t|degraded": {
        "returned": {"observation_count": 5, "observation_durability_degraded": True},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": ["ai_interactions"],
        "n": 5,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "3c084e57a6c273261a69c3093ab9f88be4c5e2efa75c4bb3a544589abcb860e5"],
        "sha256": "74b930c658b01abc27e1b4603e3b125dad94ec5e9195296fd6abca0a424b2bfc",
        "marker": {"filter": {"observation_reconcile.turn_id": "turn-1"}, "kwargs": {"upsert": True}, "sha256": "44c49ba185ea2e2aa4edd1af9cee5afe06faa0ceeeafeb6cb008475ddaa83d4b", "n_observations": 5, "status": "pending", "attempt_count": 0, "turn_id": "turn-1", "created_at": "2026-11-06T12:00:00+00:00", "indexed_at": "2026-11-06T12:00:00+00:00"},
    },
    "clean|formatted|read|u|t|durable": {
        "returned": {"observation_count": 5, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 5,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "3c084e57a6c273261a69c3093ab9f88be4c5e2efa75c4bb3a544589abcb860e5"],
        "sha256": "74b930c658b01abc27e1b4603e3b125dad94ec5e9195296fd6abca0a424b2bfc",
        "marker": None,
    },
    "clean|raw|read|u|t|degraded": {
        "returned": {"observation_count": 5, "observation_durability_degraded": True},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": ["ai_interactions"],
        "n": 5,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "3c084e57a6c273261a69c3093ab9f88be4c5e2efa75c4bb3a544589abcb860e5"],
        "sha256": "74b930c658b01abc27e1b4603e3b125dad94ec5e9195296fd6abca0a424b2bfc",
        "marker": {"filter": {"observation_reconcile.turn_id": "turn-1"}, "kwargs": {"upsert": True}, "sha256": "44c49ba185ea2e2aa4edd1af9cee5afe06faa0ceeeafeb6cb008475ddaa83d4b", "n_observations": 5, "status": "pending", "attempt_count": 0, "turn_id": "turn-1", "created_at": "2026-11-06T12:00:00+00:00", "indexed_at": "2026-11-06T12:00:00+00:00"},
    },
    "clean|raw|read|u|t|durable": {
        "returned": {"observation_count": 5, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 5,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "3c084e57a6c273261a69c3093ab9f88be4c5e2efa75c4bb3a544589abcb860e5"],
        "sha256": "74b930c658b01abc27e1b4603e3b125dad94ec5e9195296fd6abca0a424b2bfc",
        "marker": None,
    },
    "dedupe_all_lists|formatted|read|u|t|durable": {
        "returned": {"observation_count": 4, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 4,
        "obs": [
            ["concept:a", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:b", "correct", 0.6, {"error_count": 0}],
            ["concept:c", "correct", 0.6, {"error_count": 0}],
            ["concept:d", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["19386edc1cd2bc0cdc8e08d48f37779a638713e2aa210b1395e9b443eadcf550", "55b742fde674400156ce144065848d232728d43f88b21925e56b67020fb6f74d"],
        "sha256": "78237e8e4113663229a488f5cb04367159d22dc61fb568f4973a5f2fa6e7f244",
        "marker": None,
    },
    "dedupe_all_lists|raw|read|u|t|durable": {
        "returned": {"observation_count": 7, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 7,
        "obs": [
            ["concept:z", "incorrect", 0.8, {"error_count": 1, "skill": "writing", "score": 75.0, "difficulty_level": "B1"}],
            ["concept:a", "incorrect", 0.8, {"error_count": 1}],
            ["concept:b", "incorrect", 0.8, {"error_count": 1}],
            ["concept:c", "incorrect", 0.8, {"error_count": 1}],
            ["concept:d", "incorrect", 0.8, {"error_count": 1}],
            ["concept:e", "incorrect", 0.8, {"error_count": 1}],
            ["concept:f", "incorrect", 0.8, {"error_count": 1}],
        ],
        "event_ids": ["46c899d20393ff8fbe3884fa7f723a51a561da94765ecbea500adba2ea5d8c65", "9766893b6f54c95998f9086cfd256d7b5698e630e5ca3c10e85633cd598d74bb"],
        "sha256": "6949bb5a8f55bceda3722577e28b3d8c98f74aecac838479c36d32e24cfc8420",
        "marker": None,
    },
    "empty_dict|as_is|read|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_norc|formatted|read|u|t|durable": {
        "returned": {"observation_count": 17, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 17,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "603ebd71b9d69c52df6759004b80942e5fe4f4ffa0cb8cf50b3853e0dc39a99e",
        "marker": None,
    },
    "err17_norc|raw|read|u|t|durable": {
        "returned": {"observation_count": 17, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 17,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 2, "skill": "writing", "score": 50.0, "difficulty_level": "B1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 2}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "73a9c6165602bbf32430b42a544e8429f724aeb5fd73d5a374c37f5103ad1767",
        "marker": None,
    },
    "err17_noskill|formatted|read|u|t|durable": {
        "returned": {"observation_count": 17, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 17,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "9c3258ae63c99bd9b562a60ff71b9977aded9b97ec5167813b10534d95d810cb",
        "marker": None,
    },
    "err17_noskill|raw|read|u|t|durable": {
        "returned": {"observation_count": 18, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 18,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 2}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 2}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "090e141c3670af78f315e4beab3b64539f1a90f952c685638b6cd31cc07d22a2",
        "marker": None,
    },
    "err17_rc|formatted|off|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 0,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_rc|formatted|primary|u|t|durable": {
        "returned": {"observation_count": 17, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 17,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "603ebd71b9d69c52df6759004b80942e5fe4f4ffa0cb8cf50b3853e0dc39a99e",
        "marker": None,
    },
    "err17_rc|formatted|read|nouser|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 0,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_rc|formatted|read|u|noturn|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 0,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_rc|formatted|read|u|t|degraded": {
        "returned": {"observation_count": 17, "observation_durability_degraded": True},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": ["ai_interactions"],
        "n": 17,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "603ebd71b9d69c52df6759004b80942e5fe4f4ffa0cb8cf50b3853e0dc39a99e",
        "marker": {"filter": {"observation_reconcile.turn_id": "turn-1"}, "kwargs": {"upsert": True}, "sha256": "7b2c0960f8dcfe58bd1336009463a48a72deaff081306b1ad3f9b51c060eee87", "n_observations": 17, "status": "pending", "attempt_count": 0, "turn_id": "turn-1", "created_at": "2026-11-06T12:00:00+00:00", "indexed_at": "2026-11-06T12:00:00+00:00"},
    },
    "err17_rc|formatted|read|u|t|durable": {
        "returned": {"observation_count": 17, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 17,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "603ebd71b9d69c52df6759004b80942e5fe4f4ffa0cb8cf50b3853e0dc39a99e",
        "marker": None,
    },
    "err17_rc|formatted|shadow|u|t|durable": {
        "returned": {"observation_count": 17, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 17,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "B1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
            ["concept:t04", "correct", 0.6, {"error_count": 0}],
            ["concept:t05", "correct", 0.6, {"error_count": 0}],
            ["concept:t06", "correct", 0.6, {"error_count": 0}],
            ["concept:t07", "correct", 0.6, {"error_count": 0}],
            ["concept:t08", "correct", 0.6, {"error_count": 0}],
            ["concept:t09", "correct", 0.6, {"error_count": 0}],
            ["concept:t10", "correct", 0.6, {"error_count": 0}],
            ["concept:t11", "correct", 0.6, {"error_count": 0}],
            ["concept:t12", "correct", 0.6, {"error_count": 0}],
            ["concept:t13", "correct", 0.6, {"error_count": 0}],
            ["concept:t14", "correct", 0.6, {"error_count": 0}],
            ["concept:t15", "correct", 0.6, {"error_count": 0}],
            ["concept:t16", "correct", 0.6, {"error_count": 0}],
            ["concept:t17", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "e6cc93fa7301e4aed82b4260fcac1b79fc0aa1f2e6e84ba2b8bfcb5cccb80938"],
        "sha256": "603ebd71b9d69c52df6759004b80942e5fe4f4ffa0cb8cf50b3853e0dc39a99e",
        "marker": None,
    },
    "err17_rc|raw|off|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 0,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_rc|raw|primary|u|t|durable": {
        "returned": {"observation_count": 18, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 18,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 2, "skill": "writing", "score": 50.0, "difficulty_level": "B1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 2}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 2}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "dff63451080741334ced8c5db699f193e5139f26fa410e301a01569cfe79948e",
        "marker": None,
    },
    "err17_rc|raw|read|nouser|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 0,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_rc|raw|read|u|noturn|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 0,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "err17_rc|raw|read|u|t|degraded": {
        "returned": {"observation_count": 18, "observation_durability_degraded": True},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": ["ai_interactions"],
        "n": 18,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 2, "skill": "writing", "score": 50.0, "difficulty_level": "B1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 2}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 2}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "dff63451080741334ced8c5db699f193e5139f26fa410e301a01569cfe79948e",
        "marker": {"filter": {"observation_reconcile.turn_id": "turn-1"}, "kwargs": {"upsert": True}, "sha256": "b69ee40a80e4096cd6745067830f3f8938f2d34ddef61c6a94833c451c41a748", "n_observations": 18, "status": "pending", "attempt_count": 0, "turn_id": "turn-1", "created_at": "2026-11-06T12:00:00+00:00", "indexed_at": "2026-11-06T12:00:00+00:00"},
    },
    "err17_rc|raw|read|u|t|durable": {
        "returned": {"observation_count": 18, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 18,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 2, "skill": "writing", "score": 50.0, "difficulty_level": "B1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 2}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 2}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "dff63451080741334ced8c5db699f193e5139f26fa410e301a01569cfe79948e",
        "marker": None,
    },
    "err17_rc|raw|shadow|u|t|durable": {
        "returned": {"observation_count": 18, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 18,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 2, "skill": "writing", "score": 50.0, "difficulty_level": "B1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t04", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t05", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t06", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t07", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t08", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t09", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t10", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t11", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t12", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t13", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t14", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t15", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t16", "incorrect", 0.8, {"error_count": 2}],
            ["concept:t17", "incorrect", 0.8, {"error_count": 2}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 2}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "dff63451080741334ced8c5db699f193e5139f26fa410e301a01569cfe79948e",
        "marker": None,
    },
    "noconcept_skill_err|formatted|read|u|t|degraded": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "noconcept_skill_err|formatted|read|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "noconcept_skill_err|raw|read|u|t|degraded": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "noconcept_skill_err|raw|read|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "noconcept_skill|formatted|read|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "noconcept_skill|raw|read|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "pipeline_error|as_is|read|u|t|durable": {
        "returned": {"observation_count": 0, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 0,
        "obs": [
        ],
        "event_ids": [],
        "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "marker": None,
    },
    "skill_err1|formatted|read|u|t|durable": {
        "returned": {"observation_count": 3, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 3,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "C1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "2f10c99094f3510b9024921bd3b416f84e2f4dc51840a790b18f7f1f85414ed3"],
        "sha256": "08ebdf66899bfe23431c6af28d7d0870e599a84c34bf049347a217a0089f8766",
        "marker": None,
    },
    "skill_err1|raw|read|u|t|durable": {
        "returned": {"observation_count": 4, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 4,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 1, "skill": "writing", "score": 75.0, "difficulty_level": "C1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 1}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 1}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "7cba2d833036775f6156f8786ef9a5e2a8a671084bf9fa462f68740904c02527",
        "marker": None,
    },
    "skill_err4|formatted|read|u|t|durable": {
        "returned": {"observation_count": 3, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 3,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "C1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "2f10c99094f3510b9024921bd3b416f84e2f4dc51840a790b18f7f1f85414ed3"],
        "sha256": "08ebdf66899bfe23431c6af28d7d0870e599a84c34bf049347a217a0089f8766",
        "marker": None,
    },
    "skill_err4|raw|read|u|t|durable": {
        "returned": {"observation_count": 4, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 4,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 4, "skill": "writing", "score": 0.0, "difficulty_level": "C1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 4}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 4}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 4}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "a8b04381b064f2b4b4863dbf39651be3a8fd9a3a800ced7611906ce5108113de",
        "marker": None,
    },
    "skill_err6|formatted|read|u|t|durable": {
        "returned": {"observation_count": 3, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 3,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0, "difficulty_level": "C1"}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "2f10c99094f3510b9024921bd3b416f84e2f4dc51840a790b18f7f1f85414ed3"],
        "sha256": "08ebdf66899bfe23431c6af28d7d0870e599a84c34bf049347a217a0089f8766",
        "marker": None,
    },
    "skill_err6|raw|read|u|t|durable": {
        "returned": {"observation_count": 4, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 4,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 6, "skill": "writing", "score": 0.0, "difficulty_level": "C1"}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 6}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 6}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 6}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "b3c3e925e304bf65f3cc424a743ef9848f0fa93944d7f13ffee84511dbdcac51",
        "marker": None,
    },
    "skill_no_difficulty|formatted|read|u|t|durable": {
        "returned": {"observation_count": 3, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 3,
        "obs": [
            ["concept:t01", "correct", 0.6, {"error_count": 0, "skill": "writing", "score": 100.0}],
            ["concept:t02", "correct", 0.6, {"error_count": 0}],
            ["concept:t03", "correct", 0.6, {"error_count": 0}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "2f10c99094f3510b9024921bd3b416f84e2f4dc51840a790b18f7f1f85414ed3"],
        "sha256": "fd4b40735302ea1e6e4452653d2e2d2d1033fa3f0171a68f773b34ed0911aa82",
        "marker": None,
    },
    "skill_no_difficulty|raw|read|u|t|durable": {
        "returned": {"observation_count": 4, "observation_durability_degraded": False},
        "persist_many_calls": 1,
        "positional_only": True,
        "collections_touched": [],
        "n": 4,
        "obs": [
            ["concept:t01", "incorrect", 0.8, {"error_count": 1, "skill": "writing", "score": 75.0}],
            ["concept:t02", "incorrect", 0.8, {"error_count": 1}],
            ["concept:t03", "incorrect", 0.8, {"error_count": 1}],
            ["concept:g01", "incorrect", 0.8, {"error_count": 1}],
        ],
        "event_ids": ["49864843dc8c526cbb5425372f30cc8f879f85fdec554f3f6d596a1d19ad481d", "441127e47c928f276c236a104e1d37a367a936047bd07e9ed354e6017295199a"],
        "sha256": "1fb5c5251a0319c4ced092116c78338065beb6eb0abca1afc94902e7f8e87554",
        "marker": None,
    },
}
# GOLDEN-END


def test_spool_module_sha_is_the_post_flag_module():
    source = Path(spool_module.__file__).read_bytes()
    assert hashlib.sha256(source).hexdigest() == BASELINE_SPOOL_SHA256


def test_golden_values_were_captured_from_the_committed_module():
    try:
        committed = subprocess.run(
            ["git", "show", f"{CAPTURED_FROM_COMMIT}:ai-service/api/services/learner_observation_spool.py"],
            cwd=Path(spool_module.__file__).parent,
            capture_output=True,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        pytest.skip(f"git history unavailable: {exc}")
    assert hashlib.sha256(committed).hexdigest() == CAPTURED_FROM_SPOOL_SHA256


def test_specs_and_expected_cover_each_other():
    assert set(EXPECTED) == set(SPECS)


def test_formatted_shape_really_is_the_other_shape():
    raw, _, _ = _input(dict(case="err17_rc", shape="raw"))
    formatted, _, _ = _input(dict(case="err17_rc", shape="formatted"))
    assert "diagnosis_errors" in raw and "diagnosis_errors" not in formatted
    assert "corrections" in formatted and len(formatted["corrections"]) == 2
    assert formatted["linked_concepts"] == raw["kg_seed_concepts"]
    assert formatted["weak_concepts"] == raw["diagnosis_root_causes"]


@pytest.mark.parametrize("key", sorted(SPECS))
def test_flag_off_observation_lists_match_golden(key):
    actual = asyncio.run(capture(SPECS[key]))
    expected = EXPECTED[key]
    assert actual["returned"] == expected["returned"]
    assert actual["obs"] == expected["obs"]
    assert actual["event_ids"] == expected["event_ids"]
    assert actual["sha256"] == expected["sha256"]
    assert actual["persist_many_calls"] == expected["persist_many_calls"]
    assert actual["positional_only"] == expected["positional_only"]
    assert actual["collections_touched"] == expected["collections_touched"]
    assert actual["marker"] == expected["marker"]
    assert actual == expected


def test_marker_write_failure_is_logged_and_does_not_change_the_return(caplog):
    spec = SPECS["err17_rc|raw|read|u|t|degraded"]
    trace_result, skill, difficulty = _input(spec)
    fake = create_autospec(LearnerObservationSpool, instance=True)

    async def persist_many(observations):
        return [SpoolPersistResult(event_id="x", durable=False) for _ in observations]

    fake.persist_many.side_effect = persist_many
    manager = MagicMock()
    manager.db.__getitem__.return_value = MagicMock(
        update_one=AsyncMock(side_effect=RuntimeError("down"))
    )
    with ExitStack() as stack:
        stack.enter_context(patch.object(settings, "LEARNER_STATE_MODE", "read"))
        stack.enter_context(patch.object(settings, "LEARNER_OBSERVATION_DIAGNOSED_ONLY", False))
        stack.enter_context(patch.object(spool_module, "datetime", _Frozen))
        stack.enter_context(
            patch.object(
                spool_module, "get_learner_observation_spool", autospec=True, return_value=fake
            )
        )
        stack.enter_context(patch("api.core.database.mongodb_manager", manager))
        with caplog.at_level(logging.CRITICAL, logger=spool_module.logger.name):
            returned = asyncio.run(
                persist_trace_observations(
                    user_id=USER,
                    session_id=SESSION,
                    turn_id=TURN,
                    trace_result=trace_result,
                    skill=skill,
                    difficulty_level=difficulty,
                )
            )
    assert returned == EXPECTED["err17_rc|raw|read|u|t|degraded"]["returned"]
    assert "reconciliation marker failed" in caplog.text
