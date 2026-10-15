"""The L1 write gate must open for an ordinary turn, not only a grammar error.

Regression: `_is_pcc_stable` used to accept only `diagnosis_root_causes`, which
`diagnose_node` populates from five mapped grammar mistakes. A correct sentence,
a plain question, and every benchmark request therefore wrote no bucket at all,
so the L1 read path had nothing to find and `l1_rate` measured 0.0 in every run.
"""

from api.services.trace_cag.cache_utils import _is_pcc_stable, _patch_response

BENCH_STATE = {
    "evidence_hash": "a" * 64,
    "source_version": "hotpotqa:sha256:" + "a" * 64,
    "freshness_class": "static_benchmark_snapshot",
}


def _state(**over):
    base = {
        "user_input": "Who directed the film Kansas Song?",
        "diagnosis_confidence": 1.0,
        "diagnosis_root_causes": [],
        "kg_seed_concepts": [],
    }
    base.update(over)
    return base


def test_kg_concepts_anchor_the_bucket():
    """The concepts kg_expand_node produced are a valid anchor on their own."""
    assert _is_pcc_stable(_state(kg_seed_concepts=["concept:qa.film_director"])) is True


def test_benchmark_turn_writes_l1():
    """A benchmark request carries no root causes and no oracle concepts, but
    kg_expand_node still resolves concepts for it."""
    state = _state(
        benchmark_metadata={"_tracecag_state": BENCH_STATE},
        kg_seed_concepts=["concept:qa.person_nationality"],
    )
    assert _is_pcc_stable(state) is True


def test_no_anchor_still_refuses():
    """Nothing resolved: no concepts, no root causes. The bucket would be
    anchored to one phrasing, so it must stay unwritten."""
    assert _is_pcc_stable(_state()) is False


def test_grammar_root_cause_still_works():
    """The original path must keep working."""
    state = _state(diagnosis_root_causes=["concept:grammar.past_tense"])
    assert _is_pcc_stable(state) is True


def test_low_confidence_without_concepts_refuses():
    state = _state(diagnosis_confidence=0.5, diagnosis_root_causes=["concept:grammar.past_tense"])
    assert _is_pcc_stable(state) is False


def test_low_confidence_with_kg_concepts_refuses():
    state = _state(diagnosis_confidence=0.5, kg_seed_concepts=["concept:qa.film_director"])
    assert _is_pcc_stable(state) is False


def test_short_input_refuses_even_with_concepts():
    """Two-word queries are too instance-specific to be useful L1 artifacts."""
    state = _state(user_input="hello there", kg_seed_concepts=["concept:conversation.small_talk"])
    assert _is_pcc_stable(state) is False


def test_oracle_concepts_still_accepted():
    state = _state(benchmark_metadata={"_tracecag_state": dict(BENCH_STATE, concepts=["c1"])})
    assert _is_pcc_stable(state) is True


# ── patch payload ────────────────────────────────────────────────────────────
def _entry(response, concepts):
    return {"response": response, "fingerprint": {"level": "B1", "root_concepts": concepts}}


def test_patch_never_leaks_bucket_tokens():
    """`token:*` shingles exist to bucket near-miss queries, not to be read."""
    entry = _entry("Pedro Rodríguez", [])
    fp = {"level": "B1", "root_concepts": ["token:ab", "token:that", "token:true"]}
    assert _patch_response(entry, fp) == "Pedro Rodríguez"


def test_patch_still_surfaces_real_concepts():
    entry = _entry("You use the past tense here.", [])
    fp = {"level": "B1", "root_concepts": ["concept:grammar.past_tense", "token:went"]}
    patched = _patch_response(entry, fp)
    assert patched.endswith("(Also related: past tense)")


def test_patch_retargets_level():
    entry = _entry("Try this (B1) drill.", [])
    fp = {"level": "B2", "root_concepts": []}
    assert _patch_response(entry, fp) == "Try this (B2) drill."
