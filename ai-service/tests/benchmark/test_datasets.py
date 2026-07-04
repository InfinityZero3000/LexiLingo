import json
from pathlib import Path

from tracecag_bench.datasets.driftbench import load_driftbench
from tracecag_bench.datasets.public_qa import load_public_qa


ROOT = Path(__file__).resolve().parents[2]


def test_public_loader_preserves_context_docs_and_deduplicates_titles():
    path = ROOT / "model-development/datasets/benchmarks/hotpotqa/validation.jsonl"
    sample = load_public_qa(path, dataset="hotpotqa", n=1, seed=42)[0]
    assert sample.context_docs
    assert len(sample.supporting_titles) == len(set(sample.supporting_titles))
    assert sample.answers


def test_public_loader_splits_bracketed_context_into_candidate_docs(tmp_path):
    path = tmp_path / "cluster.jsonl"
    row = {
        "id": "cluster-1",
        "text": "Which doc answers the bridge question?",
        "output": {"answer": "Final answer"},
        "metadata": {
            "context": "[Bridge Page] Bridge text.\n[Answer Page] Final answer text.",
            "supporting_titles": ["Bridge Page", "Answer Page"],
        },
    }
    path.write_text(json.dumps(row), encoding="utf-8")

    sample = load_public_qa(path, dataset="query_clusters", n=None, seed=0)[0]

    assert [doc.title for doc in sample.context_docs] == ["Bridge Page", "Answer Page"]
    assert [doc.text for doc in sample.context_docs] == ["Bridge text.", "Final answer text."]


def test_public_loader_keeps_single_context_fallback_for_unstructured_text(tmp_path):
    path = tmp_path / "fallback.jsonl"
    row = {
        "id": "fallback-1",
        "text": "Question?",
        "output": {"answer": "Answer"},
        "metadata": {"context": "Plain unstructured context."},
    }
    path.write_text(json.dumps(row), encoding="utf-8")

    sample = load_public_qa(path, dataset="custom", n=None, seed=0)[0]

    assert len(sample.context_docs) == 1
    assert sample.context_docs[0].title == "benchmark_context"
    assert sample.context_docs[0].text == "Plain unstructured context."


def test_query_clusters_supporting_titles_are_candidate_docs():
    path = ROOT / "model-development/datasets/benchmarks/query_clusters/validation.jsonl"
    samples = load_public_qa(path, dataset="query_clusters", n=None, seed=0)

    missing = []
    for sample in samples:
        titles = {doc.title.strip().lower() for doc in sample.context_docs}
        missing.extend(
            title for title in sample.supporting_titles
            if title.strip().lower() not in titles
        )

    assert not missing


def test_drift_loader_preserves_base_first_cluster_contract():
    path = ROOT / "model-development/datasets/benchmarks/trace_driftbench/test.jsonl"
    cluster = load_driftbench(path, n_clusters=1)[0]
    assert cluster.base.drift_type == "base"
    assert cluster.variants
    assert all(item.expected_route for item in cluster.variants)
