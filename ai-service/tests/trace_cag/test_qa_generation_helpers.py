"""Pure helpers behind TRACE-CAG's extractive answers and token accounting.

`_generate_extractive_fallback_response` is what a learner reads when no LLM is reachable, and
`_usage_state_from_provider_usage` is where every token figure in the benchmark comes from. Neither had a test.
Expected values are worked out by hand.
"""

import asyncio
import json
import time
from datetime import timedelta
from types import SimpleNamespace

import networkx as nx
import pytest

from api.services.jit_graph_service import JITGraphService
from api.services.lexi_pipeline_helpers import sanitize_lexi_response
from api.services.trace_cag.benchmark import qa_generation as qa


def real_jit_payload() -> str:
    """Built by the production serializer: nested JSON, not a hand-written one-liner."""
    g = nx.DiGraph()
    g.add_node("a", t="Paris", l="entity", s=0.9)
    g.add_node("b", t="France", l="entity", s=0.8)
    g.add_edge("a", "b", r="capital_of", s=0.7)
    return JITGraphService._serialize_graph(g, 2000)


class TestSafeInt:
    @pytest.mark.parametrize("value,expected", [("5", 5), (7, 7), (3.9, 3), (None, 0), ("x", 0), ([], 0), ("", 0)])
    def test_coerces_or_zero(self, value, expected):
        assert qa._safe_int(value) == expected


class TestUsageState:
    def test_openai_shape_with_cache(self):
        out = qa._usage_state_from_provider_usage({
            "prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120,
            "prompt_tokens_details": {"cached_tokens": 40},
        })
        assert out["prompt_tokens"] == 100
        assert out["completion_tokens"] == 20
        assert out["total_tokens"] == 120
        assert out["cached_tokens"] == 40
        assert out["effective_prompt_tokens"] == pytest.approx(80.0)
        assert out["prompt_cache_token_rate"] == pytest.approx(0.4)
        assert out["prompt_discount_savings_rate"] == pytest.approx(0.2)
        assert out["usage_source"] == "provider"

    def test_gemini_key_names(self):
        out = qa._usage_state_from_provider_usage(
            {"promptTokenCount": 30, "candidatesTokenCount": 10, "totalTokenCount": 40}
        )
        assert (out["prompt_tokens"], out["completion_tokens"], out["total_tokens"]) == (30, 10, 40)

    def test_ollama_key_names_and_derived_total(self):
        out = qa._usage_state_from_provider_usage({"prompt_eval_count": 12, "eval_count": 8})
        assert out["total_tokens"] == 20

    def test_total_is_derived_when_missing(self):
        assert qa._usage_state_from_provider_usage({"prompt_tokens": 10, "completion_tokens": 5})["total_tokens"] == 15

    def test_top_level_cached_tokens(self):
        out = qa._usage_state_from_provider_usage({"prompt_tokens": 10, "cached_tokens": 4})
        assert out["cached_tokens"] == 4

    @pytest.mark.parametrize("details_key", ["prompt_tokens_details", "prompt_token_details", "input_token_details"])
    def test_every_cached_details_spelling(self, details_key):
        out = qa._usage_state_from_provider_usage({"prompt_tokens": 10, details_key: {"cached_tokens": 6}})
        assert out["cached_tokens"] == 6

    @pytest.mark.parametrize("usage", [{}, {"prompt_tokens": 0, "completion_tokens": 0}, {"prompt_tokens": "x"}])
    def test_no_usage_is_empty_dict(self, usage):
        assert qa._usage_state_from_provider_usage(usage) == {}

    def test_zero_prompt_does_not_divide_by_zero(self):
        out = qa._usage_state_from_provider_usage({"completion_tokens": 9})
        assert out["prompt_cache_token_rate"] == 0.0
        assert out["prompt_discount_savings_rate"] == 0.0

    def test_cached_larger_than_half_the_prompt_clamps_effective_tokens_at_zero(self):
        out = qa._usage_state_from_provider_usage({"prompt_tokens": 10, "cached_tokens": 100})
        assert out["effective_prompt_tokens"] == 0.0
        assert out["prompt_discount_savings_rate"] == pytest.approx(1.0)

    def test_effective_tokens_never_exceed_prompt_tokens(self):
        for prompt, cached in [(100, 0), (100, 50), (100, 100), (7, 3)]:
            out = qa._usage_state_from_provider_usage({"prompt_tokens": prompt, "cached_tokens": cached})
            assert 0.0 <= out["effective_prompt_tokens"] <= prompt
            assert 0.0 <= out["prompt_discount_savings_rate"] <= 1.0


class TestJitBlockStripping:
    def test_text_without_marker_is_untouched(self):
        assert qa._strip_jit_soft_graph_block("Plain context.") == "Plain context."

    @pytest.mark.parametrize("value", ["", None])
    def test_empty_is_empty(self, value):
        assert qa._strip_jit_soft_graph_block(value) == ""

    def test_flat_payload_is_removed(self):
        ctx = '[JIT_SOFT_GRAPH]\n{"v":1}\n\nParis is the capital of France.'
        assert qa._strip_jit_soft_graph_block(ctx) == "Paris is the capital of France."

    def test_marker_is_case_insensitive(self):
        assert qa._strip_jit_soft_graph_block('[jit_soft_graph]\n{"v":1}\nText.') == "Text."

    @pytest.mark.xfail(strict=True, reason="non-greedy \\{[\\s\\S]*?\\} stops at the first '}', so nested payloads leak")
    def test_real_nested_payload_is_removed_completely(self):
        ctx = f"[JIT_SOFT_GRAPH]\n{real_jit_payload()}\n\nParis is the capital of France."
        assert qa._strip_jit_soft_graph_block(ctx) == "Paris is the capital of France."

    @pytest.mark.xfail(strict=True, reason="same leak, reaches the learner through the extractive fallback")
    def test_extractive_answer_never_contains_payload_fragments(self):
        ctx = f"[JIT_SOFT_GRAPH]\n{real_jit_payload()}\n\nParis is the capital of France."
        out = qa._generate_extractive_fallback_response([], "scaffold", "What is Paris?", ctx)
        assert '"id"' not in out and "capital_of" not in out


class TestSanitizeLexiResponse:
    def test_standalone_payload_line_is_removed(self):
        assert sanitize_lexi_response(f"Paris is the capital.\n{real_jit_payload()}") == "Paris is the capital."

    @pytest.mark.xfail(strict=True, reason="marker-prefixed nested payload leaks into the user-facing reply")
    def test_marker_prefixed_real_payload_is_removed(self):
        out = sanitize_lexi_response(f"[JIT_SOFT_GRAPH]\n{real_jit_payload()}\n\nParis is the capital.")
        assert out == "Paris is the capital."

    @pytest.mark.xfail(strict=True, reason="inline marker + nested payload leaks")
    def test_inline_marker_real_payload_is_removed(self):
        out = sanitize_lexi_response(f"Paris is the capital. [JIT_SOFT_GRAPH] {real_jit_payload()}")
        assert '"id"' not in out

    def test_blank_reply_gets_the_apology(self):
        assert "Squawk" in sanitize_lexi_response("   ")


class TestFirstSentenceAndBestSentence:
    def test_first_sentence(self):
        assert qa._extract_first_sentence("Hello world. Next one.") == "Hello world"

    def test_no_punctuation_returns_whole_text_with_whitespace_collapsed(self):
        assert qa._extract_first_sentence("a   b\n c") == "a b c"

    def test_empty(self):
        assert qa._extract_first_sentence("") == ""

    def test_best_sentence_follows_overlap(self):
        ctx = "Paris is the capital of France. Berlin is in Germany."
        assert qa._best_matching_sentence("What is the capital of France?", ctx) == "Paris is the capital of France."
        assert qa._best_matching_sentence("Where is Berlin?", ctx) == "Berlin is in Germany."

    def test_digit_bonus_for_when_questions(self):
        ctx = "The firm opened. It opened in 1999."
        assert qa._best_matching_sentence("When did it open?", ctx) == "It opened in 1999."

    def test_empty_context(self):
        assert qa._best_matching_sentence("anything", "") == ""


class TestYesNo:
    def test_not_a_yes_no_question(self):
        assert qa._extract_yes_no_answer("Who is he?", "He is Bob.") is None

    def test_same_nationality_yes(self):
        assert qa._extract_yes_no_answer("Is Bob the same nationality as Amy?", "Bob is American. Amy is American.") == "yes"

    def test_same_nationality_no(self):
        assert qa._extract_yes_no_answer("Is Bob the same nationality as Amy?", "Bob is American. Amy is French.") == "no"

    def test_negation_in_best_sentence(self):
        assert qa._extract_yes_no_answer("Did Bob win?", "Bob did not win.") == "no"

    def test_affirmation_words(self):
        assert qa._extract_yes_no_answer("Did Bob win?", "Bob and Amy both won.") == "yes"

    def test_no_signal_is_none(self):
        assert qa._extract_yes_no_answer("Did Bob win?", "Bob won.") is None


class TestExtractiveQA:
    def test_who(self):
        assert qa._generate_extractive_qa_response("Who is the mayor of Paris?", "Alice Smith is the mayor of Paris. Other text.") == "Alice Smith"

    def test_where(self):
        assert qa._generate_extractive_qa_response("Where is the Louvre?", "The Louvre is located in Paris, France.") == "Paris"

    def test_when(self):
        assert qa._generate_extractive_qa_response("When did it open?", "It opened in 1999.") == "1999"

    def test_how_many(self):
        assert qa._generate_extractive_qa_response("How many does the stadium hold?", "The stadium holds 50,000 people.") == "50,000 people"

    def test_yes_no_wins_over_span_extraction(self):
        assert qa._generate_extractive_qa_response("Did Bob win?", "Bob did not win.") == "no"

    def test_empty_context_is_unknown(self):
        assert qa._generate_extractive_qa_response("Who is he?", "") == "unknown"

    def test_falls_back_to_the_whole_sentence_when_no_pattern_matches(self):
        assert qa._generate_extractive_qa_response("Who knows?", "Nobody tells.") == "Nobody tells."


ERR = [{"span": "go", "correction": "went", "explanation": "Past tense."}]
CTX = "Past tense describes finished actions. Another line."


class TestExtractiveFallback:
    def test_socratic_with_grounding_asks_a_question(self):
        out = qa._generate_extractive_fallback_response([], "socratic", "past tense", CTX)
        assert out == "Use this clue from context: Past tense describes finished actions. What conclusion can you draw from it?"

    def test_error_with_grounding(self):
        out = qa._generate_extractive_fallback_response(ERR, "feedback", "I go home past tense", CTX)
        assert out.startswith("You are close. Replace 'go' with 'went'. Past tense.")
        assert "Grounding: Past tense describes finished actions." in out

    def test_error_without_context_shows_the_corrected_sentence(self):
        out = qa._generate_extractive_fallback_response(ERR, "feedback", "I go home", "")
        assert out == "You are close. Replace 'go' with 'went'. Past tense. Try: \"I went home\""

    def test_error_with_missing_span_does_not_crash_and_keeps_the_input(self):
        out = qa._generate_extractive_fallback_response([{"explanation": "x"}], "feedback", "I go home", "")
        assert 'Try: "I go home"' in out

    def test_no_errors_returns_grounded_sentence(self):
        out = qa._generate_extractive_fallback_response([], "scaffold", "past tense", CTX)
        assert out == "Past tense describes finished actions."

    def test_praise_without_anything(self):
        assert qa._generate_extractive_fallback_response([], "praise", "hi", "") == "Great work. Your sentence is clear and grammatical."

    def test_last_resort_message_is_honest_about_the_outage(self):
        out = qa._generate_extractive_fallback_response([], "scaffold", "hi", "")
        assert "could not reach a language model" in out

    def test_socratic_without_context_falls_through(self):
        out = qa._generate_extractive_fallback_response([], "socratic", "hi", "")
        assert "could not reach a language model" in out

    def test_flat_jit_block_is_not_quoted_back(self):
        ctx = '[JIT_SOFT_GRAPH]\n{"v":1}\n\n' + CTX
        out = qa._generate_extractive_fallback_response([], "scaffold", "past tense", ctx)
        assert "JIT_SOFT_GRAPH" not in out and '"v"' not in out


class TestTruncateContext:
    def test_short_context_is_returned_as_is(self):
        assert qa._truncate_benchmark_context("short", "q", max_chars=100) == "short"

    def test_empty(self):
        assert qa._truncate_benchmark_context("", "q") == ""

    def test_items_keep_rank_order_and_drop_the_tail(self):
        items = [
            {"title": "A", "text": "x" * 20},
            {"title": "B", "text": "y" * 20},
            {"title": "C", "text": "z" * 20},
        ]
        out = qa._truncate_benchmark_context("q" * 500, "q", max_chars=50, items=items)
        assert out == f"[A] {'x' * 20}\n[B] {'y' * 20}"

    def test_an_item_one_char_over_budget_is_dropped(self):
        items = [{"title": "A", "text": "x" * 20}, {"title": "B", "text": "y" * 21}]
        out = qa._truncate_benchmark_context("q" * 500, "q", max_chars=50, items=items)
        assert out == f"[A] {'x' * 20}"

    def test_items_without_text_are_skipped(self):
        items = [{"title": "A", "text": ""}, {"title": "B", "text": "kept"}]
        assert qa._truncate_benchmark_context("q" * 500, "q", max_chars=50, items=items) == "[B] kept"

    def test_untitled_item_has_no_brackets(self):
        assert qa._truncate_benchmark_context("q" * 500, "q", max_chars=50, items=[{"text": "bare"}]) == "bare"

    def test_nothing_fits_falls_back_to_a_hard_cut(self):
        out = qa._truncate_benchmark_context("q" * 500, "q", max_chars=10, items=[{"title": "A", "text": "x" * 80}])
        assert out == "q" * 10

    def test_paragraph_mode_keeps_the_relevant_paragraph(self):
        ctx = "Alpha paragraph about cats.\n\nBeta paragraph about dogs and wolves.\n\nGamma about birds."
        assert qa._truncate_benchmark_context(ctx, "wolves dogs", max_chars=40) == "Beta paragraph about dogs and wolves."

    def test_paragraph_mode_restores_original_order(self):
        ctx = "Alpha wolves here.\n\nMiddle filler words go on.\n\nOmega wolves too."
        out = qa._truncate_benchmark_context(ctx, "wolves", max_chars=40)
        assert out == "Alpha wolves here.\n\nOmega wolves too."

    def test_never_exceeds_the_budget(self):
        ctx = "\n\n".join(f"Paragraph {i} about topic {i % 3}." for i in range(40))
        for budget in (30, 80, 200):
            assert len(qa._truncate_benchmark_context(ctx, "topic 1", max_chars=budget)) <= budget


class TestEstimateTokens:
    def test_chars_over_four_plus_budget(self):
        assert qa._estimate_message_tokens([{"content": "a" * 40}], max_tokens=100) == 110

    @pytest.mark.parametrize("messages", [[], None, [{"content": None}], [{}]])
    def test_empty_inputs_cost_only_the_output_budget(self, messages):
        assert qa._estimate_message_tokens(messages, max_tokens=64) == 64


class TestUsageLedger:
    def _add(self, role="tutor", usage=None, **kw):
        qa._ledger_add(role, {"usage": usage} if usage is not None else None, wall_started=time.monotonic(), **kw)

    def test_noop_outside_a_ledger(self):
        self._add(usage={"prompt_tokens": 5})
        assert qa._USAGE_LEDGER.get() is None

    def test_records_a_call(self):
        with qa.usage_ledger() as ledger:
            self._add(usage={"prompt_tokens": 100, "completion_tokens": 20, "prompt_tokens_details": {"cached_tokens": 30}})
        assert len(ledger) == 1
        e = ledger[0]
        assert (e["role"], e["prompt_tokens"], e["completion_tokens"], e["total_tokens"], e["cached_tokens"]) == ("tutor", 100, 20, 120, 30)
        assert e["wall_ms"] >= 0

    def test_http_ms_comes_from_response_elapsed(self):
        with qa.usage_ledger() as ledger:
            self._add(usage={"prompt_tokens": 1}, response=SimpleNamespace(elapsed=timedelta(milliseconds=250)))
        assert ledger[0]["http_ms"] == 250

    def test_missing_elapsed_is_zero(self):
        with qa.usage_ledger() as ledger:
            self._add(usage={"prompt_tokens": 1}, response=SimpleNamespace())
        assert ledger[0]["http_ms"] == 0

    def test_malformed_provider_data_never_raises(self):
        with qa.usage_ledger() as ledger:
            qa._ledger_add("tutor", "not-a-dict", wall_started=time.monotonic())
        assert ledger == []

    def test_missing_usage_records_zeros(self):
        with qa.usage_ledger() as ledger:
            self._add(usage=None)
        assert ledger[0]["total_tokens"] == 0

    def test_ledger_is_cleared_when_the_block_exits(self):
        with qa.usage_ledger():
            pass
        assert qa._USAGE_LEDGER.get() is None

    @pytest.mark.asyncio
    async def test_concurrent_requests_do_not_share_a_ledger(self):
        async def one(role, n):
            with qa.usage_ledger() as ledger:
                for _ in range(n):
                    self._add(role=role, usage={"prompt_tokens": 1})
                    await asyncio.sleep(0)
                return ledger

        a, b = await asyncio.gather(one("a", 3), one("b", 2))
        assert {e["role"] for e in a} == {"a"} and len(a) == 3
        assert {e["role"] for e in b} == {"b"} and len(b) == 2


class TestSummarizeLedger:
    @pytest.mark.parametrize("entries", [None, []])
    def test_none_when_nothing_was_recorded(self, entries):
        assert qa.summarize_usage_ledger(entries) is None

    def test_totals_and_per_role_breakdown(self):
        def e(role, p, c, cached, http, wall):
            return {"role": role, "prompt_tokens": p, "completion_tokens": c, "total_tokens": p + c,
                    "cached_tokens": cached, "http_ms": http, "wall_ms": wall}

        out = qa.summarize_usage_ledger([e("bridge", 10, 2, 0, 100, 150), e("answer", 30, 5, 10, 200, 250), e("answer", 20, 5, 0, 50, 60)])
        assert out["calls"] == 3
        assert out["prompt_tokens"] == 60 and out["completion_tokens"] == 12 and out["total_tokens"] == 72
        assert out["cached_tokens"] == 10 and out["http_ms"] == 350 and out["wall_ms"] == 460
        assert out["source"] == "provider"
        assert out["by_role"]["answer"] == {"calls": 2, "prompt_tokens": 50, "completion_tokens": 10, "total_tokens": 60, "http_ms": 250}
        assert out["by_role"]["bridge"]["calls"] == 1

    def test_role_totals_add_up_to_the_grand_total(self):
        with qa.usage_ledger() as ledger:
            for role, p in [("a", 3), ("b", 4), ("a", 5)]:
                qa._ledger_add(role, {"usage": {"prompt_tokens": p}}, wall_started=time.monotonic())
        out = qa.summarize_usage_ledger(ledger)
        assert sum(r["prompt_tokens"] for r in out["by_role"].values()) == out["prompt_tokens"]
        json.dumps(out)
