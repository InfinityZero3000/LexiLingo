import importlib.util
from pathlib import Path


PATH = Path(__file__).parents[2] / "model-development/scripts/probe_second_hop_expansion.py"
SPEC = importlib.util.spec_from_file_location("probe_second_hop_expansion", PATH)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


def test_expansion_adds_title_explicitly_named_by_seed_text():
    trace = [{"title": "Film A", "text": "Film A was directed by Person B"}]
    pool = [
        {"title": "Film A", "text": "Film A was directed by Person B"},
        {"title": "Person B", "text": "Person B was born in 1980"},
        {"title": "Noise", "text": "unrelated"},
    ]

    expanded = probe.expand("When was the director of Film A born?", trace, pool)

    assert [item["title"] for item in expanded] == ["Person B", "Film A"]


def test_parse_context_preserves_document_boundaries():
    assert probe.parse_context("[A] alpha\n[B] beta") == [
        {"title": "A", "item_id": "a", "text": "alpha"},
        {"title": "B", "item_id": "b", "text": "beta"},
    ]


def test_bootstrap_interval_is_deterministic_and_positive_for_all_wins():
    interval = probe.bootstrap_interval([0.5, 0.5, 0.0], rounds=200)
    assert interval == probe.bootstrap_interval([0.5, 0.5, 0.0], rounds=200)
    assert interval[0] >= 0.0


def test_interleave_preserves_original_top_one_and_deduplicates():
    trace = [
        {"title": "Film A", "text": "Film A was directed by Person B"},
        {"title": "Noise", "text": "unrelated"},
    ]
    pool = trace + [{"title": "Person B", "text": "Person B was born in 1980"}]

    ranked = probe.interleave("When was the director of Film A born?", trace, pool)

    assert [item["title"] for item in ranked] == ["Film A", "Person B", "Noise"]
