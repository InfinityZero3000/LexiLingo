"""Shared fixtures for tests/trace_cag."""

import pytest

import api.core.groq_key_pool as groq_key_pool_mod
from api.services.trace_cag.invalidation import clear_reverse_index


def _reset_groq_key_pool_state() -> None:
    """Reset api.core.groq_key_pool's module-level fallback pool.

    Root cause (found by bisecting the full tests/trace_cag directory down
    to a single file/test): `get_available_groq_key()` lazily caches
    `_fallback_keys` from `GROQ_API_KEY`/`GROQ_API_KEYS` on its *first ever*
    call in the process and never re-reads the environment after that.
    `test_diagnose_node.py::test_diagnose_handles_gateway_failure` makes the
    mocked gateway report failure, which sends `diagnose_node` down its real
    (unmocked) Groq-fallback branch — `get_available_groq_key()` runs for
    real, permanently caches `_fallback_keys` from whatever ambient env var
    happens to be set at that moment (no `GROQ_API_KEY` patch in that test),
    and `_fallback_cursor` keeps incrementing forever.

    Every later test that relies on `patch.dict("os.environ", {"GROQ_API_KEY":
    ...})` — e.g. test_system_tracecag.py's `_patched_pipeline` — has no
    effect, because the cache was already populated. `generate_node` and
    `diagnose_node` both call this function directly (generate.py:511,
    nodes_v2.py's fallback branch), so a poisoned pool makes `generate_node`
    silently degrade to `safe_tutor_fallback` instead of the mocked Groq
    response, which is what actually broke
    test_scenario_l1_writeback_pcc_stable and
    test_scenario_l1_invalidation_on_version_change — not a cache_utils or
    invalidation.py dict, despite both being plausible-looking suspects.
    """
    groq_key_pool_mod._pool_instance = None
    groq_key_pool_mod._fallback_keys = None
    groq_key_pool_mod._fallback_cursor = 0
    groq_key_pool_mod._fallback_in_flight = set()
    groq_key_pool_mod._fallback_next_at = []


@pytest.fixture(autouse=True)
def _reset_trace_cag_dependency_state():
    """Reset TRACE-CAG's in-process module-level singletons between tests.

    `invalidation.py`'s dependency/reverse-index dicts and
    `groq_key_pool.py`'s fallback pool are plain module globals with no
    per-test teardown, so they leak across test modules and produce
    order-dependent failures that pass in isolation but fail in the full
    suite.
    """
    clear_reverse_index()
    _reset_groq_key_pool_state()
    yield
    clear_reverse_index()
    _reset_groq_key_pool_state()
