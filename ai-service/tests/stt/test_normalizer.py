import pytest

from api.services.stt.transcript_normalizer import normalize_transcript


def test_trim_removes_extra_whitespace():
    text, rules = normalize_transcript("  hello world  ")
    assert text == "hello world."
    assert "trim" in rules


def test_adds_period_when_missing():
    text, rules = normalize_transcript("hello world")
    assert text == "hello world."
    assert "punctuation" in rules


def test_no_change_when_punctuated():
    text, rules = normalize_transcript("Hello world.")
    assert text == "Hello world."
    assert "punctuation" not in rules


def test_question_mark_preserved():
    text, rules = normalize_transcript("What time is it?")
    assert text == "What time is it?"
    assert "punctuation" not in rules


def test_filler_um_removed():
    text, rules = normalize_transcript("um")
    assert text == ""
    assert rules == ["filler_removed"]


def test_filler_uh_removed():
    text, rules = normalize_transcript("uh")
    assert text == ""
    assert rules == ["filler_removed"]


def test_filler_hmm_removed():
    text, rules = normalize_transcript("hmm")
    assert text == ""
    assert rules == ["filler_removed"]


def test_filler_with_trailing_period_removed():
    text, rules = normalize_transcript("um.")
    assert text == ""
    assert rules == ["filler_removed"]


def test_filler_mixed_case_removed():
    text, rules = normalize_transcript("Uh")
    assert text == ""
    assert rules == ["filler_removed"]


def test_bigram_repeat_deduplicated():
    text, rules = normalize_transcript("hello world hello world hello world")
    assert text == "hello world."
    assert "deduplication" in rules


def test_trigram_repeat_deduplicated():
    text, rules = normalize_transcript("I want to I want to I want to")
    assert text == "I want to."
    assert "deduplication" in rules


def test_unigram_repeat_with_tail_deduplicated():
    text, rules = normalize_transcript("can can can you help me")
    assert text == "can you help me."
    assert "deduplication" in rules


def test_unigram_repeat_only_collapsed():
    text, rules = normalize_transcript("the the the")
    assert text == "the."
    assert "deduplication" in rules


def test_two_repetitions_not_deduplicated():
    text, rules = normalize_transcript("hello world hello world")
    assert text == "hello world hello world."
    assert "deduplication" not in rules


def test_normal_sentence_unchanged():
    text, rules = normalize_transcript("I want to improve my English.")
    assert text == "I want to improve my English."
    assert "deduplication" not in rules


def test_preserve_exact_skips_filler_removal():
    text, rules = normalize_transcript("um", preserve_exact=True)
    assert text == "um"
    assert "filler_removed" not in rules


def test_preserve_exact_skips_punctuation():
    text, rules = normalize_transcript("hello world", preserve_exact=True)
    assert text == "hello world"
    assert "punctuation" not in rules


def test_preserve_exact_skips_deduplication():
    text, rules = normalize_transcript(
        "hello world hello world hello world", preserve_exact=True
    )
    assert text == "hello world hello world hello world"
    assert "deduplication" not in rules


def test_empty_input_returns_empty():
    text, rules = normalize_transcript("")
    assert text == ""
    assert rules == []


def test_preserve_exact_still_trims_whitespace():
    text, rules = normalize_transcript("  hello  ", preserve_exact=True)
    assert text == "hello"
    assert "trim" in rules
