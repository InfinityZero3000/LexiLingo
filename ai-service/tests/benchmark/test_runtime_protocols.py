import pytest

from api.core.redis_client import RedisClient
from tracecag_bench.catalog import MODES
from tracecag_bench.config import BenchmarkConfig
from tracecag_bench.protocols.public_qa import (
    ircot_summary,
    run_public_qa_protocol,
    summarize_public_qa,
)
from tracecag_bench.runtime.ai_service import AIServiceRuntime, _public_qa_state, classify_provider
from tracecag_bench.reporting.json_report import build_report, implementation_sha256, validate_run
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
                {"title": "A", "item_id": "a", "rank": 1},
                {"title": "B", "item_id": "b", "rank": 2},
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
    assert "supporting_titles" not in metadata
    assert "gold_answers" not in metadata
    state = metadata["_tracecag_state"]
    assert len(state["evidence_hash"]) == 64
    assert state["source_version"] == f"test:sha256:{state['evidence_hash']}"
    assert state["freshness_class"] == "static_benchmark_snapshot"
    assert pipeline.calls[1]["benchmark_metadata"]["_tracecag_state"] == state
    summary = result["summaries"]["tracecag_rapid"]
    assert summary["retrieval"]["recall_at_3"] == 1.0
    assert summary["cache"]["warm_hit_rate"] == 1.0


@pytest.mark.asyncio
async def test_public_protocol_does_not_repeat_cache_disabled_mode():
    pipeline = FakePipeline()
    sample = PublicQASample(
        sample_id="s1", dataset="test", question="Q?", answers=("yes",),
        context_docs=(), supporting_titles=(),
    )
    config = BenchmarkConfig(cache_repeats=2, generation_policy="extractive", require_primary_provider=False)

    result = await run_public_qa_protocol(
        [sample], [MODES["hipporag_proxy"]], config, runtime=AIServiceRuntime(pipeline),
    )

    assert len(pipeline.calls) == 1
    assert len(result["observations"]) == 1


def test_public_qa_summary_scores_quality_on_cold_observations_only():
    sample = PublicQASample(
        sample_id="s1", dataset="test", question="Q?", answers=("yes",),
        context_docs=(ContextDocument("a", "A", "one"),), supporting_titles=("A",),
    )
    observations = [
        RunObservation(sample_id="s1", mode="tracecag_rapid", answer="yes", gold_answers=("yes",)),
        RunObservation(
            sample_id="s1", mode="tracecag_rapid", answer="no", gold_answers=("yes",),
            is_warm=True, cache_hit=True,
        ),
    ]

    summary = summarize_public_qa([sample], observations)

    assert summary["quality_scope"] == "cold_only"
    assert summary["n_total"] == 1
    assert summary["n_observations"] == 2
    assert summary["exact_match"] == 1.0
    assert summary["token_f1"] == 1.0
    assert summary["cache"]["warm_hit_rate"] == 1.0


@pytest.mark.asyncio
async def test_runtime_fail_fast_reraises_pipeline_errors(monkeypatch):
    class BrokenPipeline:
        async def analyze(self, **kwargs):
            raise RuntimeError("provider unavailable")

    monkeypatch.setenv("TRACECAG_BENCHMARK_FAIL_FAST", "true")
    runtime = AIServiceRuntime(BrokenPipeline())
    sample = PublicQASample(
        sample_id="s1", dataset="test", question="Q?", answers=("yes",),
        context_docs=(), supporting_titles=(),
    )

    with pytest.raises(RuntimeError, match="provider unavailable"):
        await runtime.run_public_qa(
            sample, MODES["tracecag_rapid"], session_id="s", generation_policy="auto",
            evidence_mode="candidate_pool", is_warm=False,
        )


def test_public_qa_snapshot_state_is_deterministic_and_evidence_bound():
    sample = PublicQASample(
        sample_id="s1", dataset="test", question="Q?", answers=("yes",),
        context_docs=(ContextDocument("a", "A", "one"), ContextDocument("b", "B", "two")),
        supporting_titles=("A", "B"),
    )

    first = _public_qa_state(sample)
    second = _public_qa_state(sample)
    changed = _public_qa_state(PublicQASample(
        sample_id="s1", dataset="test", question="Q?", answers=("yes",),
        context_docs=(ContextDocument("a", "A", "changed"), ContextDocument("b", "B", "two")),
        supporting_titles=("A", "B"),
    ))

    assert first == second
    assert first["evidence_hash"] != changed["evidence_hash"]
    assert first["source_version"] == f"test:sha256:{first['evidence_hash']}"
    assert changed["source_version"] == f"test:sha256:{changed['evidence_hash']}"
    assert first["source_version"] != changed["source_version"]


def test_provider_classification_keeps_full_qwen_model_name():
    assert classify_provider(["groq/qwen/qwen3-32b"]) == ("groq", "qwen/qwen3-32b", "")


def test_primary_provider_config_enforces_and_records_fairness_policy(monkeypatch):
    for name in (
        "TRACECAG_USE_LEARNED_RANKER", "TRACECAG_BENCHMARK_FAIL_FAST",
        "TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR",
    ):
        monkeypatch.setenv(name, "false")
    config = BenchmarkConfig()

    config.apply_environment()

    policy = config.public_dict()["fairness_policy"]
    assert policy["learned_ranker"] is False
    assert policy["fail_fast"] is True
    assert policy["fail_on_provider_error"] is True
    for name in (
        "TRACECAG_USE_LEARNED_RANKER", "TRACECAG_BENCHMARK_FAIL_FAST",
        "TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR",
    ):
        monkeypatch.setenv(name, "false")


def test_public_report_emits_current_implementation_hash(tmp_path):
    dataset = tmp_path / "dataset.jsonl"
    dataset.write_text('{"sample_id":"s1"}\n')
    config = BenchmarkConfig(require_primary_provider=False)

    report = build_report(
        result={
            "run_id": "run", "stage_id": "preflight", "suite_id": "hotpotqa",
            "observations": [], "completed_count": 0, "target_count": 0,
            "kg_preflight": {"available": True, "sha256": "b" * 64},
        },
        config=config,
        dataset_path=dataset,
        dataset_name="hotpotqa",
    )

    emitted = report["configuration"]["implementation_sha256"]
    assert emitted == implementation_sha256()
    assert len(emitted) == 64
    assert set(emitted) <= set("0123456789abcdef")
    assert report["kg_preflight"]["sha256"] == "b" * 64


def test_report_validation_fails_closed_on_frozen_kg_hash_mismatch(monkeypatch):
    config = BenchmarkConfig(require_primary_provider=False)
    monkeypatch.setenv("TRACECAG_EXPECTED_KG_SHA256", "a" * 64)

    matching = validate_run(
        {"observations": [], "kg_preflight": {"available": True, "sha256": "a" * 64}},
        config,
    )
    mismatched = validate_run(
        {"observations": [], "kg_preflight": {"available": True, "sha256": "b" * 64}},
        config,
    )

    assert matching["passed"] is True
    assert mismatched["passed"] is False
    assert "KG snapshot hash mismatch" in mismatched["violations"][0]


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
