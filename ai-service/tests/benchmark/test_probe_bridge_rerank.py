import importlib.util
from pathlib import Path


PATH = Path(__file__).parents[2] / "model-development/scripts/probe_bridge_rerank.py"
SPEC = importlib.util.spec_from_file_location("probe_bridge_rerank", PATH)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


def test_bridge_link_promotes_candidate_connected_to_another_title():
    items = [
        {"title": "Distractor", "text": "unrelated words"},
        {"title": "Film A", "text": "Film A was directed by Person B"},
        {"title": "Person B", "text": "Person B was born in 1980"},
    ]

    ranked = probe.rerank("Who directed Film A?", items, "bridge_link")

    assert ranked[0]["title"] == "Film A"
    assert probe.metrics(ranked, {"film a"})["recall_at_5"] == 1.0
