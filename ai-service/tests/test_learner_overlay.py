from datetime import UTC, datetime, timedelta

from api.services.learner_overlay import rank_with_learner_overlay


NOW = datetime(2026, 7, 13, tzinfo=UTC)


def test_two_users_can_rank_same_shared_candidates_differently():
    candidates = [
        {"concept_id": "a", "relevance": 0.8},
        {"concept_id": "b", "relevance": 0.8},
    ]
    user_a = {"a": {"mastery_probability": 0.95}, "b": {"mastery_probability": 0.1}}
    user_b = {"a": {"mastery_probability": 0.1}, "b": {"mastery_probability": 0.95}}

    assert rank_with_learner_overlay(candidates, user_a, now=NOW)[0]["concept_id"] == "b"
    assert rank_with_learner_overlay(candidates, user_b, now=NOW)[0]["concept_id"] == "a"


def test_missing_state_uses_prior_without_mutating_input_and_caps_top_k():
    candidates = [{"concept_id": str(i), "relevance": 0.5} for i in range(10)]
    original = [dict(item) for item in candidates]

    ranked = rank_with_learner_overlay(candidates, {}, now=NOW, top_k=3)

    assert len(ranked) == 3
    assert candidates == original
    assert all(item["learner_state_source"] == "prior" for item in ranked)


def test_forgetting_risk_increases_for_stale_state():
    candidates = [{"concept_id": "fresh", "relevance": 0.5}, {"concept_id": "stale", "relevance": 0.5}]
    states = {
        "fresh": {"mastery_probability": 0.5, "stability_days": 3, "last_interacted_at": NOW},
        "stale": {
            "mastery_probability": 0.5,
            "stability_days": 3,
            "last_interacted_at": NOW - timedelta(days=30),
        },
    }

    ranked = rank_with_learner_overlay(candidates, states, now=NOW)

    assert ranked[0]["concept_id"] == "stale"
    assert ranked[0]["forgetting_risk"] > ranked[1]["forgetting_risk"]


def test_equal_scores_preserve_input_order_stably():
    candidates = [
        {"concept_id": "z", "relevance": 0.5},
        {"concept_id": "a", "relevance": 0.5},
        {"concept_id": "m", "relevance": 0.5},
    ]

    ranked = rank_with_learner_overlay(candidates, {}, now=NOW)

    assert [item["concept_id"] for item in ranked] == ["z", "a", "m"]


def test_malformed_state_values_and_timestamps_fall_back_safely():
    candidates = [{"concept_id": "a", "relevance": "invalid"}]
    states = {
        "a": {
            "mastery_probability": "invalid",
            "stability_days": "invalid",
            "last_interacted_at": "not-a-timestamp",
        }
    }

    ranked = rank_with_learner_overlay(candidates, states, now=NOW)

    assert len(ranked) == 1
    assert ranked[0]["learner_mastery"] == 0.5
    assert ranked[0]["forgetting_risk"] == 0.0
    assert isinstance(ranked[0]["learner_score"], float)


def test_overlay_does_not_mutate_candidates_or_learner_states():
    candidates = [{"concept_id": "a", "metadata": {"shared": True}}]
    states = {
        "a": {
            "mastery_probability": 0.4,
            "last_interacted_at": NOW.isoformat(),
            "metadata": {"source": "test"},
        }
    }
    candidates_before = [{**candidates[0], "metadata": dict(candidates[0]["metadata"])}]
    states_before = {"a": {**states["a"], "metadata": dict(states["a"]["metadata"])}}

    ranked = rank_with_learner_overlay(candidates, states, now=NOW)
    ranked[0]["metadata"]["shared"] = False

    assert candidates == candidates_before
    assert states == states_before
