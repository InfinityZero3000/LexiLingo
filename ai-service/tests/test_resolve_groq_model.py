"""The one place that decides which Groq model gets called."""

import pytest

from api.core.groq_key_pool import DEFAULT_GROQ_MODEL, resolve_groq_model


def test_unset_falls_back_to_default(monkeypatch):
    monkeypatch.delenv("GROQ_MODEL", raising=False)
    assert resolve_groq_model() == DEFAULT_GROQ_MODEL


def test_blank_falls_back_to_default(monkeypatch):
    monkeypatch.setenv("GROQ_MODEL", "   ")
    assert resolve_groq_model() == DEFAULT_GROQ_MODEL


def test_live_model_is_honoured(monkeypatch):
    monkeypatch.setenv("GROQ_MODEL", "some/live-model")
    assert resolve_groq_model() == "some/live-model"


@pytest.mark.parametrize(
    "dead",
    ["llama-3.1-8b-instant", "llama-3.3-70b-versatile", "openai/gpt-oss-120b"],
)
def test_decommissioned_model_is_ignored(monkeypatch, dead):
    monkeypatch.setenv("GROQ_MODEL", dead)
    assert resolve_groq_model() == DEFAULT_GROQ_MODEL


def test_compound_model_is_ignored(monkeypatch):
    """Agentic; streams its reply as delta.reasoning, so callers receive nothing."""
    monkeypatch.setenv("GROQ_MODEL", "groq/compound-mini")
    assert resolve_groq_model() == DEFAULT_GROQ_MODEL


def test_first_set_env_var_wins(monkeypatch):
    monkeypatch.setenv("GROQ_MODEL_DIAGNOSE", "some/diagnose-model")
    monkeypatch.setenv("GROQ_MODEL", "some/general-model")
    assert (
        resolve_groq_model("GROQ_MODEL_DIAGNOSE", "GROQ_MODEL")
        == "some/diagnose-model"
    )


def test_unset_override_falls_through_to_next(monkeypatch):
    monkeypatch.delenv("GROQ_MODEL_DIAGNOSE", raising=False)
    monkeypatch.setenv("GROQ_MODEL", "some/general-model")
    assert (
        resolve_groq_model("GROQ_MODEL_DIAGNOSE", "GROQ_MODEL")
        == "some/general-model"
    )
