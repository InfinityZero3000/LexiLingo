"""Lexi must never open a reply with a reasoning tag.

Qwen3 answers a `/no_think` prompt by emitting an *empty* reasoning block, so
only the closing tag reaches the response. The paired `<think>…</think>` pattern
cannot match an unpaired closing tag — measured on `lexilingo-qwen3-1.7b`, the
model `OLLAMA_MODEL` names as the fallback provider when Groq is unavailable.
"""

from api.services.lexi_pipeline_helpers import sanitize_lexi_response


def test_unpaired_closing_tag_is_stripped():
    raw = '</think>\n\nThe correct sentence is: "She doesn\'t like coffee."'
    assert sanitize_lexi_response(raw).startswith("The correct sentence")


def test_paired_reasoning_block_is_still_removed():
    cleaned = sanitize_lexi_response("<think>long ramble</think>\n\nHello there friend.")
    assert "ramble" not in cleaned
    assert cleaned.startswith("Hello there")


def test_ordinary_reply_is_untouched():
    reply = 'Great job! Try "She doesn\'t like coffee." next time.'
    assert sanitize_lexi_response(reply).startswith("Great job")


def test_closing_tag_mid_reply_is_left_alone():
    """Only a leading orphan is an artifact; anything else is the model's text."""
    reply = "Use </think> as an example of an XML closing tag."
    assert "</think>" in sanitize_lexi_response(reply)
