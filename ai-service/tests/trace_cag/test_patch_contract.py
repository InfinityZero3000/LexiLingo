from api.services.trace_cag import cache_utils


def _entry(response="Steve Jobs", *, factual_hash=True, provenance_hash=True):
    trace = [{"item_id": "apple", "title": "Apple Inc."}]
    certificate = {
        "factual_projection_hash": cache_utils._projection_hash(
            cache_utils._factual_projection(response)
        ) if factual_hash else "",
        "provenance_projection_hash": cache_utils._projection_hash(
            cache_utils._provenance_projection(trace)
        ) if provenance_hash else "",
    }
    return {
        "response": response,
        "retrieval_trace": trace,
        "admissibility_certificate": certificate,
    }


def test_unchanged_factual_and_provenance_projection_passes():
    entry = _entry()
    assert cache_utils._patch_postconditions_hold(entry, "Steve Jobs") is True


def test_factual_change_fails_patch_postcondition():
    entry = _entry()
    assert cache_utils._patch_postconditions_hold(entry, "Steve Wozniak") is False


def test_declared_cefr_marker_change_preserves_factual_projection():
    entry = _entry("Review this sentence (B1)")
    assert cache_utils._patch_postconditions_hold(entry, "Review this sentence (B2)") is True


def test_declared_related_concepts_append_preserves_factual_projection():
    entry = _entry("Review this sentence")
    patched = "Review this sentence\n\n(Also related: past tense)"
    assert cache_utils._patch_postconditions_hold(entry, patched) is True


def test_provenance_change_fails_patch_postcondition():
    entry = _entry()
    entry["retrieval_trace"] = [{"item_id": "other", "title": "Other"}]
    assert cache_utils._patch_postconditions_hold(entry, "Steve Jobs") is False


def test_missing_projection_hash_fails_closed():
    assert cache_utils._patch_postconditions_hold(_entry(factual_hash=False), "Steve Jobs") is False
