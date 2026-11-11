"""The dict a TRACE-CAG run hands back to its callers.

test_pipeline_integration only checks that keys exist. These tests pin the values,
the exact key sets, and the paths that bypass `_format_response`.
"""

import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from api.services.trace_cag.evaluation_agent import EvaluationAgent
from api.services.trace_cag.generate import generate_node
from api.services.trace_cag.graph import TraceCAGPipeline
from api.services.trace_cag.state import create_initial_state

TOP_KEYS = {
    "tutor_response", "corrections", "linked_concepts", "learner_facts_stated",
    "weak_concepts", "action_plan", "native_hint", "pronunciation_tip",
    "scores", "action", "metadata", "audio",
}
SCORE_KEYS = {
    "fluency", "grammar", "overall", "vocabulary_level", "diagnosis_confidence",
    "wer", "word_count", "correction_count", "error_density", "type_token_ratio",
    "retrieval",
}
METADATA_KEYS = {
    "latency_ms", "ttft_ms", "models_used", "path", "cache_hit", "cache_decision",
    "cache_layer", "cache_bucket", "reuse_risk", "adaptive_profile",
    "adaptive_features", "adaptive_controller", "tokens_saved", "diagnosis_intent",
    "kg_concepts_expanded", "retrieval_trace", "retrieval_meta", "graph_update",
}


def fmt(state: dict) -> dict:
    return TraceCAGPipeline._format_response(SimpleNamespace(), state)


def rel(rank, relevant):
    return {"rank": rank, "item_id": f"d{rank}", "is_relevant": relevant}


class TestKeyContract:
    def test_exact_top_level_keys(self):
        assert set(fmt({})) == TOP_KEYS

    def test_exact_score_and_metadata_keys(self):
        out = fmt({})
        assert set(out["scores"]) == SCORE_KEYS
        assert set(out["metadata"]) == METADATA_KEYS
        assert set(out["scores"]["retrieval"]) == {"precision_k", "recall_k", "ndcg_k", "mrr"}
        assert set(out["action"]) == {"strategy", "next"}

    def test_empty_state_defaults(self):
        out = fmt({})
        assert out["tutor_response"] == ""
        assert out["corrections"] == []
        assert out["learner_facts_stated"] == {}
        assert out["audio"] is None
        assert out["action"] == {"strategy": "scaffold", "next": "continue"}
        assert out["metadata"]["path"] == "slow"
        assert out["metadata"]["cache_decision"] == "full"
        assert out["metadata"]["cache_layer"] == "none"
        assert out["metadata"]["reuse_risk"] == 1.0
        assert out["metadata"]["cache_hit"] is False
        assert out["scores"]["word_count"] == 0
        assert out["scores"]["error_density"] == 0.0
        assert out["scores"]["wer"] == 0.0
        assert out["scores"]["retrieval"] == {
            "precision_k": None, "recall_k": None, "ndcg_k": None, "mrr": None,
        }

    def test_response_is_json_serialisable_without_audio_bytes(self):
        out = fmt({
            "user_input": "He go to school",
            "tutor_response": "Say 'goes'.",
            "diagnosis_errors": [{"span": "go", "correction": "goes", "type": "agreement", "explanation": "3rd person"}],
            "retrieval_trace": [rel(1, True), rel(2, False)],
            "kg_seed_concepts": ["c1"],
            "diagnosis_root_causes": ["c2"],
            "models_used": ["groq"],
            "graph_update": {"latency_ms": 1, "nodes_added": 0, "edges_added": 0},
        })
        json.dumps(out)


class TestScores:
    def test_overall_is_recomputed_not_copied_from_state(self):
        out = fmt({"overall_score": 0.99, "grammar_score": 0.5, "fluency_score": 0.5, "vocabulary_level": "B1"})
        assert out["scores"]["overall"] == pytest.approx(0.485)

    def test_overall_matches_evaluation_agent(self):
        out = fmt({"grammar_score": 0.9, "fluency_score": 0.7, "vocabulary_level": "C1"})
        assert out["scores"]["overall"] == EvaluationAgent.compute_overall_score(0.9, 0.7, "C1")

    def test_text_metrics_follow_input_and_errors(self):
        out = fmt({
            "user_input": "He go to school",
            "diagnosis_errors": [{"span": "go", "correction": "goes"}],
        })["scores"]
        assert out["word_count"] == 4
        assert out["correction_count"] == 1
        assert out["error_density"] == 25.0
        assert out["wer"] == pytest.approx(0.25)

    def test_wer_is_zero_without_errors(self):
        assert fmt({"user_input": "He go to school"})["scores"]["wer"] == 0.0

    def test_blank_input_has_zero_word_count(self):
        assert fmt({"user_input": "   "})["scores"]["word_count"] == 0

    def test_ttr_is_rounded_to_four_places(self):
        ttr = fmt({"user_input": "the cat the dog the end"})["scores"]["type_token_ratio"]
        assert ttr == 0.6667

    def test_diagnosis_confidence_defaults_to_zero(self):
        assert fmt({})["scores"]["diagnosis_confidence"] == 0.0


class TestRetrievalMetrics:
    def test_recall_uses_supporting_titles(self):
        out = fmt({
            "retrieval_trace": [rel(1, True), rel(2, False), rel(3, True)],
            "benchmark_metadata": {"supporting_titles": ["a", "b", "c", "d"]},
        })["scores"]["retrieval"]
        assert out["precision_k"] == pytest.approx(2 / 3)
        assert out["recall_k"] == pytest.approx(0.5)

    def test_recall_falls_back_to_relevant_passage_ids(self):
        out = fmt({
            "retrieval_trace": [rel(1, True)],
            "benchmark_metadata": {"relevant_passage_ids": ["x", "y"]},
        })["scores"]["retrieval"]
        assert out["recall_k"] == pytest.approx(0.5)

    def test_recall_is_none_without_gold_but_precision_is_not(self):
        out = fmt({"retrieval_trace": [rel(1, True)]})["scores"]["retrieval"]
        assert out["precision_k"] == 1.0
        assert out["recall_k"] is None

    def test_ndcg_and_mrr_are_rounded(self):
        out = fmt({"retrieval_trace": [rel(1, False), rel(2, False), rel(3, True)]})["scores"]["retrieval"]
        assert out["mrr"] == 0.3333
        assert out["ndcg_k"] == round(0.5, 4)

    def test_chat_traffic_has_no_retrieval_scores(self):
        trace = [{"rank": 1, "item_id": "d1"}, {"rank": 2, "item_id": "d2"}]
        out = fmt({"retrieval_trace": trace})
        assert out["scores"]["retrieval"] == {"precision_k": None, "recall_k": None, "ndcg_k": None, "mrr": None}
        assert out["metadata"]["retrieval_trace"] == trace

    def test_missing_benchmark_metadata_value_is_tolerated(self):
        fmt({"retrieval_trace": [rel(1, True)], "benchmark_metadata": None})


class TestFieldMapping:
    def test_corrections_rename_span_to_error(self):
        out = fmt({"diagnosis_errors": [
            {"span": "go", "correction": "goes", "type": "agreement", "explanation": "why"},
            {"span": "x"},
        ]})["corrections"]
        assert out[0] == {"error": "go", "correction": "goes", "type": "agreement", "explanation": "why"}
        assert out[1] == {"error": "x", "correction": "", "type": "", "explanation": ""}

    def test_linked_and_weak_concepts_come_from_different_fields(self):
        out = fmt({"kg_seed_concepts": ["seed"], "diagnosis_root_causes": ["root"]})
        assert out["linked_concepts"] == ["seed"]
        assert out["weak_concepts"] == ["root"]

    def test_none_facts_become_empty_dict(self):
        assert fmt({"diagnosis_facts": None})["learner_facts_stated"] == {}

    def test_expanded_node_count(self):
        assert fmt({"kg_expanded_nodes": [{}, {}, {}]})["metadata"]["kg_concepts_expanded"] == 3

    def test_action_mapping(self):
        out = fmt({"strategy": "praise", "next_action": "ask"})
        assert out["action"] == {"strategy": "praise", "next": "ask"}

    def test_cache_hit_metadata_passes_through(self):
        meta = fmt({
            "cache_hit": True, "cache_decision": "reuse", "cache_layer": "L1",
            "reuse_risk": 0.1, "tokens_saved": 120, "path": "fast",
        })["metadata"]
        assert (meta["cache_hit"], meta["cache_decision"], meta["cache_layer"]) == (True, "reuse", "L1")
        assert (meta["reuse_risk"], meta["tokens_saved"], meta["path"]) == (0.1, 120, "fast")


class TestAudio:
    def test_absent_when_neither_bytes_nor_url(self):
        assert fmt({"tts_audio_bytes": None, "tts_audio_url": None})["audio"] is None

    def test_present_with_url_only(self):
        assert fmt({"tts_audio_url": "u"})["audio"] == {"bytes": None, "url": "u"}

    def test_present_with_bytes_only(self):
        assert fmt({"tts_audio_bytes": b"\x00"})["audio"] == {"bytes": b"\x00", "url": None}


class TestAnalyzePaths:
    @pytest.fixture
    def pipeline(self):
        p = TraceCAGPipeline.__new__(TraceCAGPipeline)
        p.compiled = SimpleNamespace(ainvoke=AsyncMock(return_value={"tutor_response": "ok", "path": "slow"}))
        return p

    @pytest.mark.asyncio
    async def test_success_is_formatted_and_stamped_with_latency(self, pipeline):
        out = await pipeline.analyze("hi", "s1")
        assert set(out) == TOP_KEYS
        assert out["tutor_response"] == "ok"
        assert isinstance(out["metadata"]["latency_ms"], int)
        assert out["metadata"]["latency_ms"] >= 0

    @pytest.mark.asyncio
    async def test_raw_state_skips_formatting_but_keeps_latency(self, pipeline):
        out = await pipeline.analyze("hi", "s1", return_raw_state=True)
        assert out["tutor_response"] == "ok"
        assert "scores" not in out
        assert isinstance(out["latency_ms"], int)

    @pytest.mark.asyncio
    async def test_failure_returns_apology_error_and_error_path(self, pipeline):
        pipeline.compiled.ainvoke.side_effect = RuntimeError("boom")
        out = await pipeline.analyze("hi", "s1")
        assert out["tutor_response"]
        assert out["error"] == "boom"
        assert out["metadata"]["path"] == "error"
        assert out["metadata"]["models_used"] == []
        assert isinstance(out["metadata"]["latency_ms"], int)
        json.dumps(out)

    @pytest.mark.asyncio
    async def test_streaming_entry_point_skips_generation_and_returns_raw_state(self, pipeline):
        out = await pipeline.analyze_for_streaming("hi", "s1")
        initial = pipeline.compiled.ainvoke.await_args.args[0]
        assert initial["generation_policy"] == "skip"
        assert "scores" not in out

    @pytest.mark.asyncio
    async def test_policies_and_seeds_reach_the_initial_state(self, pipeline):
        await pipeline.analyze(
            "hi", "s1", cache_policy="off", retrieval_policy="rapid",
            diagnosis_policy="rules", kg_seed_concepts=["k1"],
        )
        initial = pipeline.compiled.ainvoke.await_args.args[0]
        assert (initial["cache_policy"], initial["retrieval_policy"], initial["diagnosis_policy"]) == ("off", "rapid", "rules")
        assert initial["kg_seed_concepts"] == ["k1"]


EXTRACTIVE = [
    # intent, fluency, n_errors, strategy, next_action
    ("correct", 0.8, 0, "praise", "continue"),
    ("correct", 0.8, 1, "feedback", "hint"),
    ("correct", 0.8, 2, "feedback", "hint"),
    ("correct", 0.8, 3, "scaffold", "correct"),
    ("correct", 0.8, 9, "scaffold", "correct"),
    ("explain", 0.8, 0, "socratic", "ask"),
    ("explain", 0.8, 3, "socratic", "ask"),
    ("explain", 0.7, 0, "praise", "continue"),
    ("explain", 0.7, 3, "scaffold", "correct"),
    ("practice", 0.95, 0, "praise", "continue"),
]


def _errors(n):
    return [{"span": f"w{i}", "type": "grammar", "correction": f"c{i}", "explanation": "e"} for i in range(n)]


class TestGenerateOutput:
    @pytest.fixture(autouse=True)
    def no_ranker_side_effects(self):
        with patch("api.services.trace_cag.generate._update_ranker_from_generation", autospec=True):
            yield

    def _state(self, intent, fluency, n, **over):
        s = create_initial_state(
            user_input="w0 w1 w2 w3 w4 w5 w6 w7 w8", session_id="s",
            cache_policy="off", generation_policy="extractive",
        )
        s.update(diagnosis_intent=intent, fluency_score=fluency, grammar_score=0.6,
                 vocabulary_level="B2", diagnosis_errors=_errors(n), **over)
        return s

    @pytest.mark.asyncio
    @pytest.mark.parametrize("intent,fluency,n,strategy,next_action", EXTRACTIVE)
    async def test_strategy_and_next_action_matrix(self, intent, fluency, n, strategy, next_action):
        out = await generate_node(self._state(intent, fluency, n))
        assert (out["strategy"], out["next_action"]) == (strategy, next_action)

    @pytest.mark.asyncio
    async def test_extractive_output_shape(self):
        out = await generate_node(self._state("correct", 0.8, 1))
        assert set(out) == {"tutor_response", "strategy", "next_action", "overall_score", "ttft_ms", "models_used"}
        assert isinstance(out["tutor_response"], str) and out["tutor_response"].strip()
        assert out["models_used"] == ["extractive_policy"]
        assert isinstance(out["ttft_ms"], int) and out["ttft_ms"] >= 0

    @pytest.mark.asyncio
    async def test_extractive_overall_score_matches_the_formula(self):
        out = await generate_node(self._state("correct", 0.8, 0))
        assert out["overall_score"] == pytest.approx(EvaluationAgent.compute_overall_score(0.6, 0.8, "B2"))

    @pytest.mark.asyncio
    async def test_template_is_a_deprecated_alias_for_extractive(self):
        state = self._state("correct", 0.8, 1)
        state["generation_policy"] = "template"
        out = await generate_node(state)
        assert out["models_used"] == ["extractive_policy"]

    @pytest.mark.asyncio
    async def test_skip_policy_returns_nothing(self):
        state = self._state("correct", 0.8, 1)
        state["generation_policy"] = "skip"
        assert await generate_node(state) == {}

    @pytest.mark.asyncio
    async def test_extractive_does_not_write_the_cache_when_cache_is_off(self):
        with patch("api.services.trace_cag.generate._write_cache_entry", autospec=True) as write:
            await generate_node(self._state("correct", 0.8, 1))
        write.assert_not_called()

    @pytest.mark.asyncio
    async def test_cache_write_failure_does_not_lose_the_answer(self):
        state = self._state("correct", 0.8, 1)
        state["cache_policy"] = "on"
        with patch("api.services.trace_cag.generate._write_cache_entry", autospec=True, side_effect=RuntimeError("redis down")):
            out = await generate_node(state)
        assert out["tutor_response"].strip()
