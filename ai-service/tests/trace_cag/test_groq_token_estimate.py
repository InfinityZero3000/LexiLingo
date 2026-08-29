"""The key pool must be told what the whole request costs, not just the reply.

It debits estimated_tokens against each key's per-minute budget. generate_node
passed a flat 512 while a grounded turn measures ~850 tokens before any history
is injected, so the pool kept handing out keys it had already spent and Groq
answered 429 with a several-minute Retry-After.
"""
from __future__ import annotations

from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.generate as generate_mod


@pytest.mark.asyncio
async def test_estimate_covers_prompt_and_history(monkeypatch):
    seen: list[int] = []

    async def _key(estimated_tokens=600):
        seen.append(estimated_tokens)
        return None  # no key: generate_node falls through, we only want the estimate

    monkeypatch.setattr("api.core.groq_key_pool.get_available_groq_key", _key)
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())
    monkeypatch.setattr(generate_mod, "_write_cache_entry", AsyncMock())

    long_turn = "I would like to practise reporting a bug in the app. " * 40
    await generate_mod.generate_node({
        "user_input": long_turn,
        "session_id": "s",
        "user_id": "u",
        "learner_profile": {"level": "B1"},
        "conversation_history": [{"role": "user", "content": long_turn}],
        "retrieved_context": "Concept (topic:x): Reporting an App Bug. " * 20,
        "diagnosis_errors": [],
        "diagnosis_root_causes": [],
        "cache_policy": "off",
        "generation_policy": "auto",
    })

    assert seen, "generate_node never asked the pool for a key"
    assert seen[0] > 512, "estimate still ignores the prompt it is about to send"
