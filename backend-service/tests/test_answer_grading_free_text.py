"""Typed and assembled answers compare on words, whatever the client calls the type."""

import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.routes.learning import _answers_match  # noqa: E402


def test_arrange_answer_ignores_punctuation_the_word_bank_never_had():
    # arrange_tiles() strips ".,?!;:", so the learner can only ever build this.
    assert _answers_match(
        "I would like a cup of coffee please",
        "I would like a cup of coffee, please.",
        "reorder",
        "arrange_the_sentence",
    )


def test_client_type_translation_is_graded_like_translate():
    assert _answers_match("Nice to meet you", "Nice to meet you.", "translation")


def test_extra_whitespace_is_not_a_mistake():
    assert _answers_match("nice  to meet you ", "Nice to meet you", "fill_blank", "dictation")


def test_colon_and_comma_in_a_sentence_are_not_read_as_pairs():
    correct = "Note: I like it, a lot"
    assert _answers_match("note i like it a lot", correct, "fill_blank", "grammar_correction")
    assert not _answers_match("Note: I like it, banana", correct, "fill_blank", "grammar_correction")


def test_wrong_words_are_still_wrong():
    assert not _answers_match("I like tea", "I like coffee.", "reorder", "arrange_the_sentence")


def test_pair_answers_must_be_complete_but_not_ordered():
    correct = "happy:vui vẻ, sad:buồn bã"
    assert _answers_match("sad:buồn bã, happy:vui vẻ", correct, "matching", "match_word_to_meaning")
    assert not _answers_match("happy:vui vẻ", correct, "matching", "match_word_to_meaning")
