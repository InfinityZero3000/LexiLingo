"""What a learner-facing response looks like when the cache answers instead of the LLM.

test_system_tracecag only checks the negative case (a legacy entry without a certificate is refused). These run the
real graph twice on one input and compare the second response with the first.
"""

import json

import pytest
import pytest_asyncio

from tests.trace_cag.test_system_tracecag import _patched_pipeline

TEXT = "I go to school yesterday."
ANSWER = "Use 'went' for the past."
KW = dict(user_id="test_user", learner_profile={"level": "B1"})


@pytest_asyncio.fixture
async def twice():
    async with _patched_pipeline(groq_response=ANSWER) as pipeline:
        first = await pipeline.analyze(TEXT, "s1", **KW)
        second = await pipeline.analyze(TEXT, "s1", **KW)
        yield pipeline, first, second


@pytest.mark.asyncio
class TestHitOutput:
    async def test_first_run_is_a_slow_miss_and_the_second_a_fast_hit(self, twice):
        _, first, second = twice
        assert (first["metadata"]["path"], first["metadata"]["cache_hit"]) == ("slow", False)
        assert (second["metadata"]["path"], second["metadata"]["cache_hit"]) == ("fast", True)

    async def test_hit_reports_how_it_was_served(self, twice):
        _, _, second = twice
        meta = second["metadata"]
        assert meta["cache_decision"] == "reuse"
        assert meta["cache_layer"] == "L0"
        assert 0.0 <= meta["reuse_risk"] < 1.0

    async def test_hit_does_not_claim_an_llm_served_it(self, twice):
        _, first, second = twice
        assert "rapid_reuse_l0" in second["metadata"]["models_used"]
        assert not any(m.startswith(("groq", "gemini", "ollama")) for m in second["metadata"]["models_used"])
        assert any(m.startswith("groq") for m in first["metadata"]["models_used"])

    async def test_tokens_saved_is_zero_on_a_miss_and_follows_the_formula_on_a_hit(self, twice):
        _, first, second = twice
        assert first["metadata"]["tokens_saved"] == 0
        assert second["metadata"]["tokens_saved"] == 650 + len(second["tutor_response"]) // 4

    async def test_hit_returns_the_same_answer_and_corrections_as_the_original(self, twice):
        _, first, second = twice
        assert second["tutor_response"] == first["tutor_response"] == ANSWER
        assert second["corrections"] == first["corrections"]
        assert second["corrections"], "the cached diagnosis must survive the round trip"

    async def test_hit_keeps_scores_consistent_with_the_original(self, twice):
        _, first, second = twice
        for key in ("grammar", "fluency", "vocabulary_level", "overall", "correction_count", "wer", "word_count"):
            assert second["scores"][key] == first["scores"][key], key

    async def test_hit_has_the_same_shape_as_a_miss(self, twice):
        _, first, second = twice
        assert set(second) == set(first)
        assert set(second["metadata"]) == set(first["metadata"])
        assert set(second["scores"]) == set(first["scores"])

    async def test_hit_is_json_serialisable(self, twice):
        _, _, second = twice
        json.dumps(second)

    async def test_hit_is_not_slower_than_ten_seconds_of_wall_clock(self, twice):
        _, _, second = twice
        assert isinstance(second["metadata"]["latency_ms"], int)
        assert 0 <= second["metadata"]["latency_ms"] < 10_000


@pytest.mark.asyncio
class TestWhoMayReuse:
    async def test_another_user_does_not_get_the_cached_answer(self, twice):
        pipeline, _, _ = twice
        other = await pipeline.analyze(TEXT, "s2", user_id="someone_else", learner_profile={"level": "B1"})
        assert other["metadata"]["cache_hit"] is False
        assert other["metadata"]["path"] == "slow"

    async def test_another_level_does_not_get_the_cached_answer(self, twice):
        pipeline, _, _ = twice
        other = await pipeline.analyze(TEXT, "s1", user_id="test_user", learner_profile={"level": "C1"})
        assert other["metadata"]["cache_hit"] is False

    async def test_cache_policy_off_bypasses_a_warm_cache(self, twice):
        pipeline, _, _ = twice
        off = await pipeline.analyze(TEXT, "s1", cache_policy="off", **KW)
        assert off["metadata"]["cache_hit"] is False
        assert off["metadata"]["cache_decision"] == "full"
        assert off["metadata"]["path"] == "slow"

    async def test_a_miss_that_follows_a_hit_is_unaffected(self, twice):
        pipeline, _, _ = twice
        other = await pipeline.analyze("She dont like apples.", "s1", **KW)
        assert other["metadata"]["cache_hit"] is False
        assert other["tutor_response"]
