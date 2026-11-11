"""generate_node's real provider chain: Groq / Gemini race, Ollama last resort, safe fallback.

test_generate_node covers prompt building and a couple of failure cases through one shared mock. These tests
drive each provider branch separately and look at what comes out and what gets sent.
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

import api.services.trace_cag.generate as gen
from api.services.trace_cag.evaluation_agent import EvaluationAgent
from api.services.trace_cag.state import create_initial_state

OUT_KEYS = {"tutor_response", "strategy", "next_action", "overall_score", "action_plan", "ttft_ms", "models_used"}


def _resp(status=200, **body):
    r = MagicMock()
    r.status_code = status
    r.json.return_value = body
    return r


GROQ_OK = lambda text="groq says hi": _resp(choices=[{"message": {"content": text}}], usage={"total_tokens": 321})
GEMINI_OK = lambda text="gemini says hi": _resp(candidates=[{"content": {"parts": [{"text": text}]}}])
OLLAMA_OK = lambda text="ollama says hi": _resp(message={"content": text})


class Rig:
    def __init__(self):
        self.calls: list[dict] = []
        self.by_provider: dict = {}
        self.groq_key = "gk"
        self.record = AsyncMock()
        self.write_cache = AsyncMock()

    async def post(self, **kw):
        self.calls.append(kw)
        out = self.by_provider.get(kw["provider"])
        if isinstance(out, Exception):
            raise out
        return out

    def payload(self, provider):
        return next(c["payload"] for c in self.calls if c["provider"] == provider)

    def providers(self):
        return [c["provider"] for c in self.calls]


@pytest.fixture
def rig(monkeypatch):
    r = Rig()
    monkeypatch.setenv("GROQ_MODEL", "qwen/qwen3.8-27b")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    monkeypatch.setenv("OLLAMA_MODEL", "tiny")
    monkeypatch.delenv("TRACECAG_ENABLE_LOCAL_LLAMA_KV", raising=False)
    with patch.object(gen, "_throttled_post_json", r.post), \
         patch("api.core.groq_key_pool.get_available_groq_key", AsyncMock(side_effect=lambda **_: r.groq_key)), \
         patch("api.core.groq_key_pool.record_groq_key_usage", r.record), \
         patch.object(gen, "_write_cache_entry", r.write_cache), \
         patch.object(gen, "_update_ranker_from_generation", MagicMock()), \
         patch.object(gen, "get_doc_intel_service", MagicMock(return_value=MagicMock(should_promote_to_cache=MagicMock(return_value=False)))):
        yield r


def state(n_errors=0, intent="correct", **over):
    s = create_initial_state(user_input="I go home yesterday", session_id="s", user_id="u", cache_policy="off")
    s.update(
        diagnosis_intent=intent, fluency_score=0.8, grammar_score=0.6, vocabulary_level="B2",
        diagnosis_errors=[{"span": f"w{i}", "type": "grammar", "correction": f"c{i}", "explanation": "why"} for i in range(n_errors)],
        learner_profile={"level": "B1"}, retrieved_context="",
    )
    s.update(over)
    return s


class TestWinners:
    @pytest.mark.asyncio
    async def test_groq_answer_is_returned_with_its_model_label(self, rig):
        rig.by_provider["groq"] = GROQ_OK("Use 'went'.")
        out = await gen.generate_node(state(1))
        assert out["tutor_response"] == "Use 'went'."
        assert out["models_used"] == ["groq/qwen/qwen3.8-27b"]
        assert set(out) == OUT_KEYS

    @pytest.mark.asyncio
    async def test_groq_usage_is_reported_to_the_key_pool(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1))
        rig.record.assert_awaited_once_with("gk", 321)

    @pytest.mark.asyncio
    async def test_groq_usage_defaults_when_provider_omits_it(self, rig):
        rig.by_provider["groq"] = _resp(choices=[{"message": {"content": "x"}}])
        await gen.generate_node(state(1))
        rig.record.assert_awaited_once_with("gk", 500)

    @pytest.mark.asyncio
    async def test_gemini_answers_when_there_is_no_groq_key(self, rig, monkeypatch):
        rig.groq_key = None
        monkeypatch.setenv("GEMINI_API_KEY", "gem")
        rig.by_provider["gemini"] = GEMINI_OK("Hello from Gemini")
        out = await gen.generate_node(state(1))
        assert out["tutor_response"] == "Hello from Gemini"
        assert out["models_used"] == ["gemini-2.0-flash"]
        assert "groq" not in rig.providers()

    @pytest.mark.asyncio
    async def test_gemini_answers_when_groq_returns_500(self, rig, monkeypatch):
        monkeypatch.setenv("GEMINI_API_KEY", "gem")
        rig.by_provider["groq"] = _resp(500)
        rig.by_provider["gemini"] = GEMINI_OK()
        out = await gen.generate_node(state(1))
        assert out["models_used"] == ["gemini-2.0-flash"]

    @pytest.mark.asyncio
    async def test_gemini_empty_candidates_is_treated_as_failure(self, rig, monkeypatch):
        rig.groq_key = None
        monkeypatch.setenv("GEMINI_API_KEY", "gem")
        rig.by_provider["gemini"] = _resp(candidates=[])
        rig.by_provider["ollama"] = OLLAMA_OK()
        out = await gen.generate_node(state(1))
        assert out["models_used"] == ["ollama/tiny"]

    @pytest.mark.asyncio
    async def test_ollama_is_the_last_resort(self, rig):
        rig.groq_key = None
        rig.by_provider["ollama"] = OLLAMA_OK("local answer")
        out = await gen.generate_node(state(1))
        assert out["tutor_response"] == "local answer"
        assert out["models_used"] == ["ollama/tiny"]
        assert rig.payload("ollama")["stream"] is False

    @pytest.mark.asyncio
    async def test_provider_exception_falls_through_to_the_next(self, rig):
        rig.by_provider["groq"] = RuntimeError("boom")
        rig.by_provider["ollama"] = OLLAMA_OK()
        out = await gen.generate_node(state(1))
        assert out["models_used"] == ["ollama/tiny"]


class TestSafeFallback:
    @pytest.mark.asyncio
    async def test_every_provider_down_returns_the_apology_and_labels_it(self, rig):
        out = await gen.generate_node(state(1))
        assert out["tutor_response"] == gen.SAFE_TUTOR_FALLBACK
        assert out["models_used"] == ["safe_tutor_fallback"]

    @pytest.mark.asyncio
    async def test_the_apology_is_never_cached(self, rig):
        s = state(1)
        s["cache_policy"] = "on"
        await gen.generate_node(s)
        rig.write_cache.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_fallback_still_carries_strategy_and_scores(self, rig):
        out = await gen.generate_node(state(3))
        assert (out["strategy"], out["next_action"]) == ("scaffold", "correct")
        assert out["overall_score"] == pytest.approx(EvaluationAgent.compute_overall_score(0.6, 0.8, "B2"))

    @pytest.mark.asyncio
    async def test_empty_provider_text_counts_as_no_answer(self, rig):
        rig.by_provider["groq"] = GROQ_OK("")
        out = await gen.generate_node(state(1))
        assert out["models_used"] == ["safe_tutor_fallback"]


class TestStrategyAndPlan:
    @pytest.mark.asyncio
    @pytest.mark.parametrize("n,strategy,next_action", [(0, "praise", "continue"), (1, "feedback", "hint"), (2, "feedback", "hint"), (3, "scaffold", "correct")])
    async def test_strategy_matrix_on_the_llm_path(self, rig, n, strategy, next_action):
        rig.by_provider["groq"] = GROQ_OK()
        out = await gen.generate_node(state(n))
        assert (out["strategy"], out["next_action"]) == (strategy, next_action)

    @pytest.mark.asyncio
    async def test_explain_intent_with_fluent_learner_is_socratic(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        out = await gen.generate_node(state(0, intent="explain"))
        assert (out["strategy"], out["next_action"]) == ("socratic", "ask")
        assert "Strategy: SOCRATIC" in rig.payload("groq")["messages"][0]["content"]

    @pytest.mark.asyncio
    async def test_no_errors_means_no_practice_plan(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        assert (await gen.generate_node(state(0)))["action_plan"] == []

    @pytest.mark.asyncio
    async def test_errors_produce_one_practice_item(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        plan = (await gen.generate_node(state(1)))["action_plan"]
        assert len(plan) == 1
        assert plan[0]["action"] == "practice"
        assert plan[0]["type"] in {"grammar", "vocabulary"}
        assert plan[0]["exercise"]
        json.dumps(plan)

    @pytest.mark.asyncio
    async def test_practice_intent_asks_for_vocabulary(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        plan = (await gen.generate_node(state(0, intent="practice")))["action_plan"]
        assert [p["type"] for p in plan] == ["vocabulary"]

    @pytest.mark.asyncio
    async def test_a_broken_exercise_generator_does_not_lose_the_answer(self, rig):
        rig.by_provider["groq"] = GROQ_OK("still here")
        with patch("api.services.cag_service.ContentAutoGenerator", side_effect=RuntimeError("no data")):
            out = await gen.generate_node(state(1))
        assert out["tutor_response"] == "still here"
        assert out["action_plan"] == []


class TestRequestSent:
    @pytest.fixture(autouse=True)
    def non_qwen_model(self, rig, monkeypatch):
        monkeypatch.setenv("GROQ_MODEL", "llama-test-8b")

    @pytest.mark.asyncio
    async def test_context_and_errors_reach_the_system_prompt(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1, retrieved_context="PAST TENSE NOTES"))
        system = rig.payload("groq")["messages"][0]
        assert system["role"] == "system"
        assert "PAST TENSE NOTES" in system["content"]
        assert "Knowledge Graph Context" in system["content"]

    @pytest.mark.asyncio
    async def test_user_input_is_the_last_message(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1))
        assert rig.payload("groq")["messages"][-1] == {"role": "user", "content": "I go home yesterday"}

    @pytest.mark.asyncio
    async def test_both_history_shapes_are_replayed_in_order(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        s = state(1)
        s["conversation_history"] = [
            {"role": "user", "content": "hi"},
            {"role": "assistant", "content": "hello"},
            {"user": "legacy q", "ai": "legacy a"},
            {"role": "user", "content": ""},
            {"role": None, "content": "orphan"},
        ]
        await gen.generate_node(s)
        roles = [(m["role"], m["content"]) for m in rig.payload("groq")["messages"][1:-1]]
        assert roles == [("user", "hi"), ("assistant", "hello"), ("user", "legacy q"), ("assistant", "legacy a")]

    @pytest.mark.asyncio
    async def test_only_the_last_twelve_history_entries_are_sent(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        s = state(1)
        s["conversation_history"] = [{"role": "user", "content": f"m{i}"} for i in range(30)]
        await gen.generate_node(s)
        sent = [m["content"] for m in rig.payload("groq")["messages"][1:-1]]
        assert sent == [f"m{i}" for i in range(18, 30)]

    @pytest.mark.asyncio
    async def test_non_qwen_payload_has_no_reasoning_override(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1))
        p = rig.payload("groq")
        assert p["model"] == "llama-test-8b"
        assert p["max_tokens"] == 512
        assert "reasoning_effort" not in p

    @pytest.mark.asyncio
    async def test_temperature_comes_from_env_and_survives_garbage(self, rig, monkeypatch):
        rig.by_provider["groq"] = GROQ_OK()
        monkeypatch.setenv("TRACECAG_TUTOR_TEMPERATURE", "0.2")
        await gen.generate_node(state(1))
        assert rig.payload("groq")["temperature"] == 0.2
        rig.calls.clear()
        monkeypatch.setenv("TRACECAG_TUTOR_TEMPERATURE", "warm")
        await gen.generate_node(state(1))
        assert rig.payload("groq")["temperature"] == 0.7

    @pytest.mark.asyncio
    async def test_native_hint_reaches_the_prompt(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1, native_hint="mẹo tiếng Việt"))
        assert "mẹo tiếng Việt" in rig.payload("groq")["messages"][0]["content"]


class TestQwenPayload:
    @pytest.mark.asyncio
    async def test_reasoning_is_switched_off_in_the_request_body(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1))
        p = rig.payload("groq")
        assert p["model"] == "qwen/qwen3.8-27b"
        assert p["reasoning_effort"] == "none"
        assert p["max_tokens"] == 512

    @pytest.mark.asyncio
    async def test_only_the_first_user_turn_gets_the_no_think_prefix(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        s = state(1)
        s["conversation_history"] = [{"role": "user", "content": "earlier"}]
        await gen.generate_node(s)
        users = [m["content"] for m in rig.payload("groq")["messages"] if m["role"] == "user"]
        assert users == ["/no_think\nearlier", "I go home yesterday"]


class TestCacheWrite:
    @pytest.mark.asyncio
    async def test_success_with_cache_on_writes_once_with_the_answer(self, rig):
        rig.by_provider["groq"] = GROQ_OK("cache me")
        s = state(1)
        s["cache_policy"] = "on"
        await gen.generate_node(s)
        rig.write_cache.assert_awaited_once()
        assert rig.write_cache.await_args.args[1] == "cache me"

    @pytest.mark.asyncio
    async def test_cache_off_never_writes(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        await gen.generate_node(state(1))
        rig.write_cache.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_a_cache_failure_does_not_lose_the_answer(self, rig):
        rig.by_provider["groq"] = GROQ_OK("kept")
        rig.write_cache.side_effect = RuntimeError("redis down")
        s = state(1)
        s["cache_policy"] = "on"
        assert (await gen.generate_node(s))["tutor_response"] == "kept"

    @pytest.mark.asyncio
    async def test_l2_answer_is_cached_only_after_the_chunk_earns_promotion(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        s = state(1)
        s["cache_policy"] = "on"
        s["retrieval_trace"] = [{"item_id": "ext_abc123"}]
        await gen.generate_node(s)
        rig.write_cache.assert_not_awaited()

        with patch.object(gen, "get_doc_intel_service", MagicMock(return_value=MagicMock(should_promote_to_cache=MagicMock(return_value=True)))):
            await gen.generate_node(s)
        rig.write_cache.assert_awaited_once()


class TestRouting:
    @pytest.mark.asyncio
    @pytest.mark.parametrize("task", ["multihop_qa", "retrieval_qa"])
    async def test_benchmark_tasks_bypass_the_tutor_chain(self, rig, task):
        sentinel = {"tutor_response": "span"}
        with patch.object(gen, "_generate_benchmark_qa_response", AsyncMock(return_value=sentinel)) as bench:
            out = await gen.generate_node(state(1, benchmark_task=task))
        assert out is sentinel
        bench.assert_awaited_once()
        assert rig.calls == []

    @pytest.mark.asyncio
    async def test_other_benchmark_task_values_use_the_tutor_chain(self, rig):
        rig.by_provider["groq"] = GROQ_OK()
        out = await gen.generate_node(state(1, benchmark_task="something_else"))
        assert out["models_used"] == ["groq/qwen/qwen3.8-27b"]
