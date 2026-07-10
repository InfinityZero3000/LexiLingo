import pytest

from api.core.redis_client import RedisClient
from tracecag_bench.catalog import MODES
from tracecag_bench.config import BenchmarkConfig
from tracecag_bench.protocols.public_qa import ircot_summary, run_public_qa_protocol
from tracecag_bench.runtime.ai_service import AIServiceRuntime, classify_provider
from tracecag_bench.schemas import ContextDocument, PublicQASample, RunObservation


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


def test_redis_client_reads_benchmark_disabled_env(monkeypatch):
    monkeypatch.setenv("BENCHMARK_REDIS_DISABLED", "true")

    assert RedisClient._benchmark_redis_disabled() is True


def test_redis_client_disables_redis_when_benchmark_fail_fast(monkeypatch):
    monkeypatch.delenv("BENCHMARK_REDIS_DISABLED", raising=False)
    monkeypatch.setenv("BENCHMARK_REDIS_FAIL_FAST", "true")

    assert RedisClient._benchmark_redis_disabled() is True


def test_redis_client_disabled_env_overrides_fail_fast(monkeypatch):
    monkeypatch.setenv("BENCHMARK_REDIS_DISABLED", "false")
    monkeypatch.setenv("BENCHMARK_REDIS_FAIL_FAST", "true")

    assert RedisClient._benchmark_redis_disabled() is False


def test_ircot_summary_counts_gate_and_contract_outcomes():
    rows = [
        {
            "evaluated": True,
            "selected": False,
            "reason": "skip_yes_no",
        },
        {
            "evaluated": True,
            "selected": True,
            "reason": "augmented",
            "reason_latency_ms": 12,
            "contract": {"passes": True},
        },
        {
            "evaluated": True,
            "selected": True,
            "reason": "contract_rejected",
            "reason_latency_ms": 18,
            "contract": {"passes": False},
        },
    ]
    summary = ircot_summary([
        RunObservation(sample_id=f"s{i}", mode="tracecag_rapid", retrieval_meta={"ircot": row})
        for i, row in enumerate(rows)
    ])

    assert summary["evaluated"] == 3
    assert summary["selected"] == 2
    assert summary["selection_rate"] == pytest.approx(2 / 3)
    assert summary["reason_counts"] == {
        "augmented": 1,
        "contract_rejected": 1,
        "skip_yes_no": 1,
    }
    assert summary["contract_pass_rate"] == 0.5
    assert summary["avg_reason_latency_ms"] == 15
