"""Tests for the last-resort native-language fallback hint (nodes_v2._get_predefined_native_hint)."""

import api.services.trace_cag.nodes_v2 as nodes

_ERROR = {"type": "past_tense", "span": "go", "correction": "went", "explanation": "past tense"}


def test_predefined_native_hint_vietnamese_no_errors():
    assert "tốt" in nodes._get_predefined_native_hint([], "Vietnamese")


def test_predefined_native_hint_vietnamese_known_error_type():
    hint = nodes._get_predefined_native_hint([_ERROR], "Vietnamese")
    assert "quá khứ" in hint


def test_predefined_native_hint_japanese_does_not_fall_back_to_vietnamese():
    hint = nodes._get_predefined_native_hint([_ERROR], "Japanese")
    assert "quá khứ" not in hint
    assert hint == nodes._PREDEFINED_NATIVE_EXPLANATIONS["Japanese"]["past_tense"]


def test_predefined_native_hint_unsupported_language_falls_back_to_short_english():
    hint = nodes._get_predefined_native_hint([_ERROR], "Thai")
    assert hint == nodes._FALLBACK_NATIVE_DEFAULT


def test_predefined_native_hint_unsupported_language_no_errors():
    hint = nodes._get_predefined_native_hint([], "Thai")
    assert hint == nodes._FALLBACK_NATIVE_NO_ERRORS


def test_ask_clarify_hint_uses_learner_language():
    assert nodes._get_ask_clarify_hint("Japanese") == nodes._ASK_CLARIFY_HINTS["Japanese"]


def test_ask_clarify_hint_unsupported_language_falls_back_to_english():
    hint = nodes._get_ask_clarify_hint("Thai")
    assert hint == nodes._ASK_CLARIFY_HINT_DEFAULT
