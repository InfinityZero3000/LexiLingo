from api.services.trace_cag.cache_utils import _benchmark_cache_scope, _build_cache_key


def test_two_benchmark_modes_do_not_share_a_cache_entry():
    """cag_vanilla and tracecag_rapid answer the SAME question from different
    evidence. The harness clearing the in-process cache between modes hid this,
    but a Redis entry survives that clear — and the identical omission in the
    dependency-token key already poisoned a run (cache hit 46.9%->6.2%)."""
    flat = _build_cache_key(None, "Who wrote it?", "B1", "cag_vanilla")
    graph = _build_cache_key(None, "Who wrote it?", "B1", "tracecag_rapid")
    assert flat != graph


def test_production_keys_are_unchanged_by_the_scope():
    """Production has no benchmark mode, so its keys must be byte-identical to
    what they were before scoping — otherwise every live entry is invalidated."""
    import hashlib

    legacy = hashlib.md5("who wrote it?||B1".encode()).hexdigest()
    assert _build_cache_key(None, "Who wrote it?", "B1", "") == legacy
    assert _build_cache_key(None, "Who wrote it?", "B1") == legacy


def test_user_scope_still_separates_learners():
    assert _build_cache_key("u1", "hello", "B1") != _build_cache_key("u2", "hello", "B1")


def test_scope_reads_the_benchmark_mode_off_the_state():
    assert _benchmark_cache_scope({}) == ""
    assert _benchmark_cache_scope({"benchmark_metadata": {"_benchmark_mode": "TraceCAG_Rapid"}}) == "tracecag_rapid"
