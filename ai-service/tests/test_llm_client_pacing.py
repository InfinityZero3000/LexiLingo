"""Token pacing must stay opt-in.

`_provider_tpm` once defaulted to 6000 for Groq, and the pacing it drives
sleeps inside every caller of `_throttled_post_json` — so a limit meant for
benchmark runs was slowing live chat, translate and TRACE-CAG traffic.
Production paces through `groq_key_pool` instead.

The benchmark harness has its own test for the opt-in side, but it lives under
`model-development/`, which is gitignored (4.3GB of datasets and checkpoints)
and therefore never reaches CI. That is why the regression sat on `dev`
unnoticed. This file is tracked, so the default is pinned where CI can see it.
"""

import pytest

from api.services.trace_cag.llm_client import _provider_tpm


@pytest.mark.parametrize("provider", ["groq", "gemini"])
def test_pacing_is_off_unless_asked_for(monkeypatch, provider):
    monkeypatch.delenv(f"TRACECAG_{provider.upper()}_TPM", raising=False)
    assert _provider_tpm(provider) == 0


def test_an_explicit_budget_is_honoured(monkeypatch):
    monkeypatch.setenv("TRACECAG_GROQ_TPM", "6000")
    assert _provider_tpm("groq") == 6000


def test_a_malformed_budget_disables_pacing_rather_than_crashing(monkeypatch):
    """A typo in an env var must not take the service down at import time."""
    monkeypatch.setenv("TRACECAG_GROQ_TPM", "six thousand")
    assert _provider_tpm("groq") == 0


def test_a_negative_budget_cannot_invert_the_pacing(monkeypatch):
    monkeypatch.setenv("TRACECAG_GROQ_TPM", "-1")
    assert _provider_tpm("groq") == 0


def test_an_unknown_provider_is_unpaced(monkeypatch):
    monkeypatch.delenv("TRACECAG_OPENAI_TPM", raising=False)
    assert _provider_tpm("openai") == 0
