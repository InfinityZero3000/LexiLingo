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


def test_drift_loader_preserves_base_first_cluster_contract():
    path = ROOT / "model-development/datasets/benchmarks/trace_driftbench/test.jsonl"
    cluster = load_driftbench(path, n_clusters=1)[0]
    assert cluster.base.drift_type == "base"
    assert cluster.variants
    assert all(item.expected_route for item in cluster.variants)
