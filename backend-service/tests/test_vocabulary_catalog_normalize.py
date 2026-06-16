"""Regression tests for vocabulary_catalog.normalize_word.

These are pure unit tests — no DB required.
"""

from __future__ import annotations

import pytest

from app.services.vocabulary_catalog import normalize_word


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("HELLO", "hello"),
        ("Hello World", "hello world"),
        ("  apple  ", "apple"),
        ("go  to  sleep", "go to sleep"),
        ("ﬁle", "file"),       # fi ligature (U+FB01) via NFKC
        ("well–being", "well-being"),   # en dash U+2013
        ("caf\xe9—au—lait", "caf\xe9-au-lait"),  # em dash U+2014
        ("Caf\xe9", "caf\xe9"),
        ("A", "a"),
    ],
)
def test_normalize_word_ascii_and_common_unicode(raw: str, expected: str) -> None:
    assert normalize_word(raw) == expected


def test_normalize_word_right_single_quotation_mark_becomes_apostrophe() -> None:
    # U+2019 right single quotation mark -> U+0027 straight apostrophe
    raw = "it’s"
    assert normalize_word(raw) == "it's"


def test_normalize_word_left_single_quotation_mark_becomes_apostrophe() -> None:
    # U+2018 left single quotation mark -> U+0027 straight apostrophe
    raw = "‘hello’"
    assert normalize_word(raw) == "'hello'"


def test_normalize_word_preserves_ascii_hyphen() -> None:
    assert normalize_word("well-known") == "well-known"


def test_normalize_word_empty_string_is_stable() -> None:
    assert normalize_word("") == ""


def test_normalize_word_is_idempotent() -> None:
    word = "  Caf\xe9—World  "
    once = normalize_word(word)
    twice = normalize_word(once)
    assert once == twice


def test_normalize_word_em_dash_to_ascii_hyphen() -> None:
    assert normalize_word("Caf\xe9—Menu") == "caf\xe9-menu"
