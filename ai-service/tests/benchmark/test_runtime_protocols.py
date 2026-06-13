import pytest

from tracecag_bench.catalog import MODES
from tracecag_bench.config import BenchmarkConfig
from tracecag_bench.protocols.public_qa import run_public_qa_protocol
from tracecag_bench.runtime.ai_service import AIServiceRuntime, classify_provider
from tracecag_bench.schemas import ContextDocument, PublicQASample


class FakePipeline:
    def __init__(self):
        self.calls = []

    async def analyze(self, **kwargs):
        self.calls.append(kwargs)
        warm = len(self.calls) > 1
        return {
            "tutor_response": "yes",
            "latency_ms": 5 if warm else 50,
            "cache_hit": warm,
            "cache_decision": "reuse" if warm else "full",
            "cache_layer": "L0" if warm else "none",
            "reuse_risk": 0.0 if warm else 1.0,
            "retrieval_trace": [
                {"title": "A", "item_id": "a", "rank": 1, "is_relevant": True},
                {"title": "B", "item_id": "b", "rank": 2, "is_relevant": True},
            ],
            "models_used": ["rapid_reuse_l0"] if warm else ["groq/qwen/qwen3-32b"],
        }


@pytest.mark.asyncio
async def test_public_protocol_passes_context_docs_and_measures_trace():
    pipeline = FakePipeline()
    runtime = AIServiceRuntime(pipeline)
    sample = PublicQASample(
        sample_id="s1", dataset="test", question="Q?", answers=("yes",),
        context_docs=(ContextDocument("a", "A", "one"), ContextDocument("b", "B", "two")),
        supporting_titles=("A", "B"),
    )
    config = BenchmarkConfig(cache_repeats=2, generation_policy="extractive", require_primary_provider=False)
    result = await run_public_qa_protocol([sample], [MODES["tracecag_rapid"]], config, runtime=runtime)
    metadata = pipeline.calls[0]["benchmark_metadata"]
    assert len(metadata["context_docs"]) == 2
    summary = result["summaries"]["tracecag_rapid"]
    assert summary["retrieval"]["recall_at_3"] == 1.0
    assert summary["cache"]["warm_hit_rate"] == 1.0


def test_provider_classification_keeps_full_qwen_model_name():
    assert classify_provider(["groq/qwen/qwen3-32b"]) == ("groq", "qwen/qwen3-32b", "")
