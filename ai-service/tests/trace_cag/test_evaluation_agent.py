"""EvaluationAgent computes every number in the `scores` block of a TRACE-CAG response.

Expected values below are worked out by hand, not read back from the code.
"""

import math

import pytest

from api.services.trace_cag.evaluation_agent import EvaluationAgent as E


def _t(rank, rel):
    return {"rank": rank, "is_relevant": rel}


class TestOverallScore:
    def test_weights_sum_to_one(self):
        assert E._W_GRAMMAR + E._W_FLUENCY + E._W_VOCAB == pytest.approx(1.0)

    @pytest.mark.parametrize(
        "grammar,fluency,level,expected",
        [
            (1.0, 1.0, "C2", 1.0),
            (0.0, 0.0, "A1", 0.03),
            (0.8, 0.6, "B2", 0.695),
            (0.5, 0.5, "B1", 0.485),
        ],
    )
    def test_weighted_sum(self, grammar, fluency, level, expected):
        assert E.compute_overall_score(grammar, fluency, level) == pytest.approx(expected)

    def test_unknown_level_falls_back_to_b1(self):
        assert E.compute_overall_score(0, 0, "Z9") == E.compute_overall_score(0, 0, "B1")

    def test_stays_in_unit_interval_for_unit_inputs(self):
        for level in E._VOCAB_NUMERIC:
            assert 0.0 <= E.compute_overall_score(1.0, 1.0, level) <= 1.0


class TestVocabLevel:
    @pytest.mark.parametrize("text", ["", "   ", "\n\t"])
    def test_blank_is_a1(self, text):
        assert E.estimate_vocab_level(text) == "A1"

    @pytest.mark.parametrize(
        "text,level",
        [
            ("albeit", "C2"),
            ("ALBEIT it rained", "C2"),
            ("a rigorous study", "C1"),
            ("furthermore it works", "B2"),
            ("however it works", "B1"),
        ],
    )
    def test_marker_words_pick_the_tier(self, text, level):
        assert E.estimate_vocab_level(text) == level

    def test_highest_tier_wins_when_tiers_are_mixed(self):
        assert E.estimate_vocab_level("however albeit furthermore") == "C2"

    def test_word_in_two_tiers_gets_the_higher_one(self):
        assert E.estimate_vocab_level("ubiquitous") == "C2"
        assert E.estimate_vocab_level("hypothesis") == "C1"

    @pytest.mark.parametrize(
        "text,level",
        [("cat dog sun", "A1"), ("tree frog", "A2"), ("garden window", "B1")],
    )
    def test_average_word_length_fallback(self, text, level):
        assert E.estimate_vocab_level(text) == level

    def test_result_is_always_a_known_cefr_level(self):
        for text in ["", "hi", "x" * 40, "albeit", "I am 5", "😀"]:
            assert E.estimate_vocab_level(text) in E._VOCAB_NUMERIC


class TestRetrievalQuality:
    def test_none_without_trace(self):
        assert E.compute_retrieval_quality([]) is None

    def test_none_without_ground_truth(self):
        assert E.compute_retrieval_quality([{"rank": 1}, {"rank": 2}]) is None

    def test_fraction_relevant(self):
        trace = [_t(1, True), _t(2, False), _t(3, True)]
        assert E.compute_retrieval_quality(trace) == pytest.approx(2 / 3)

    def test_unlabelled_items_do_not_dilute_the_denominator(self):
        trace = [_t(1, True), {"rank": 2}, {"rank": 3}]
        assert E.compute_retrieval_quality(trace) == 1.0

    def test_all_irrelevant_is_zero_not_none(self):
        assert E.compute_retrieval_quality([_t(1, False)]) == 0.0


class TestApplyCorrections:
    def test_substitutes_span(self):
        errs = [{"span": "go", "correction": "goes"}]
        assert E.apply_corrections("He go home", errs) == "He goes home"

    def test_only_first_occurrence_per_error(self):
        errs = [{"span": "he go", "correction": "he goes"}]
        assert E.apply_corrections("he go he go", errs) == "he goes he go"

    def test_repeated_span_consumes_successive_occurrences(self):
        errs = [{"span": "go", "correction": "went"}] * 2
        assert E.apply_corrections("I go and go", errs) == "I went and went"

    @pytest.mark.parametrize(
        "err",
        [
            {"span": "", "correction": "x"},
            {"span": "go", "correction": ""},
            {"span": "go", "correction": "go"},
            {"span": "  ", "correction": "x"},
            {},
        ],
    )
    def test_unusable_errors_are_ignored(self, err):
        assert E.apply_corrections("I go", [err]) == "I go"

    def test_span_not_in_text_is_a_no_op(self):
        assert E.apply_corrections("I go", [{"span": "xyz", "correction": "abc"}]) == "I go"

    def test_whitespace_around_span_and_correction_is_stripped(self):
        errs = [{"span": " go ", "correction": " went "}]
        assert E.apply_corrections("I go home", errs) == "I went home"

    def test_no_errors_returns_input_unchanged(self):
        assert E.apply_corrections("same", []) == "same"


class TestWER:
    def test_identical_is_zero(self):
        assert E.compute_wer("the cat sat", "the cat sat") == 0.0

    def test_empty_reference_is_zero(self):
        assert E.compute_wer("anything", "") == 0.0

    def test_one_substitution_in_four(self):
        assert E.compute_wer("He go to school", "He goes to school") == pytest.approx(0.25)

    def test_insertion(self):
        assert E.compute_wer("a b c", "a b") == pytest.approx(0.5)

    def test_deletion(self):
        assert E.compute_wer("a b", "a b c d") == pytest.approx(0.5)

    def test_case_insensitive(self):
        assert E.compute_wer("HELLO World", "hello world") == 0.0

    def test_can_exceed_one_when_hypothesis_is_much_longer(self):
        assert E.compute_wer("a b c d", "a") == pytest.approx(3.0)

    def test_empty_hypothesis_is_total_error(self):
        assert E.compute_wer("", "a b c") == pytest.approx(1.0)

    def test_symmetric_for_equal_length_swaps(self):
        assert E.compute_wer("a b", "b a") == pytest.approx(1.0)


class TestTypeTokenRatio:
    def test_short_text_is_clamped_to_one(self):
        assert E.compute_type_token_ratio("hi hi hi hi") == 1.0

    def test_empty_is_one(self):
        assert E.compute_type_token_ratio("") == 1.0

    def test_all_repeats(self):
        assert E.compute_type_token_ratio("a a a a a") == pytest.approx(0.2)

    def test_case_is_folded(self):
        assert E.compute_type_token_ratio("The the THE the The") == pytest.approx(0.2)

    def test_digits_and_punctuation_are_not_tokens(self):
        assert E.compute_type_token_ratio("a 1 2 3 4 5 6 b") == 1.0

    def test_mixed(self):
        assert E.compute_type_token_ratio("the cat the dog the end") == pytest.approx(4 / 6)


class TestErrorDensity:
    @pytest.mark.parametrize(
        "errors,words,expected",
        [(2, 50, 4.0), (0, 10, 0.0), (1, 3, 33.33), (5, 5, 100.0)],
    )
    def test_per_hundred_words(self, errors, words, expected):
        assert E.compute_error_density(errors, words) == expected

    def test_zero_words_is_zero_not_a_crash(self):
        assert E.compute_error_density(3, 0) == 0.0


class TestRecall:
    def test_none_without_trace(self):
        assert E.compute_recall_k([], 2) is None

    @pytest.mark.parametrize("total", [0, -1])
    def test_none_without_gold_total(self, total):
        assert E.compute_recall_k([_t(1, True)], total) is None

    def test_none_without_labels(self):
        assert E.compute_recall_k([{"rank": 1}], 2) is None

    def test_fraction_of_gold_found(self):
        trace = [_t(1, True), _t(2, False), _t(3, False), _t(4, True)]
        assert E.compute_recall_k(trace, 4) == pytest.approx(0.5)

    def test_nothing_found_is_zero(self):
        assert E.compute_recall_k([_t(1, False)], 3) == 0.0

    @pytest.mark.xfail(
        strict=True,
        reason="recall is |found|/|gold| with no cap; more relevant hits than gold items gives >1",
    )
    def test_never_exceeds_one(self):
        trace = [_t(1, True), _t(2, True), _t(3, True)]
        assert E.compute_recall_k(trace, 2) <= 1.0


class TestNDCG:
    def test_none_without_labels(self):
        assert E.compute_ndcg_k([{"rank": 1}]) is None

    def test_none_for_empty(self):
        assert E.compute_ndcg_k([]) is None

    def test_perfect_ranking_is_one(self):
        assert E.compute_ndcg_k([_t(1, True), _t(2, True), _t(3, False)]) == pytest.approx(1.0)

    def test_relevant_at_rank_two(self):
        assert E.compute_ndcg_k([_t(1, False), _t(2, True)]) == pytest.approx(1 / math.log2(3))

    def test_nothing_relevant_is_zero(self):
        assert E.compute_ndcg_k([_t(1, False), _t(2, False)]) == 0.0

    def test_input_order_does_not_matter(self):
        shuffled = [_t(3, False), _t(1, True), _t(2, False)]
        assert E.compute_ndcg_k(shuffled) == pytest.approx(1.0)

    def test_pushing_a_hit_down_lowers_the_score(self):
        high = E.compute_ndcg_k([_t(1, True), _t(2, False), _t(3, True)])
        low = E.compute_ndcg_k([_t(1, False), _t(2, True), _t(3, True)])
        assert low < high <= 1.0

    def test_bounded_for_random_looking_traces(self):
        for pattern in ([1, 0, 1, 0, 1], [0, 0, 0, 1], [1, 1, 1, 1], [0, 1]):
            trace = [_t(i + 1, bool(r)) for i, r in enumerate(pattern)]
            assert 0.0 <= E.compute_ndcg_k(trace) <= 1.0


class TestMRR:
    def test_none_without_labels(self):
        assert E.compute_mrr([{"rank": 1}]) is None

    @pytest.mark.parametrize("first_hit", [1, 2, 3, 10])
    def test_reciprocal_of_first_hit(self, first_hit):
        trace = [_t(r, r == first_hit) for r in range(1, 11)]
        assert E.compute_mrr(trace) == pytest.approx(1 / first_hit)

    def test_only_first_hit_counts(self):
        assert E.compute_mrr([_t(1, False), _t(2, True), _t(3, True)]) == pytest.approx(0.5)

    def test_no_hit_is_zero(self):
        assert E.compute_mrr([_t(1, False), _t(2, False)]) == 0.0

    def test_input_order_does_not_matter(self):
        assert E.compute_mrr([_t(3, True), _t(1, False), _t(2, True)]) == pytest.approx(0.5)
