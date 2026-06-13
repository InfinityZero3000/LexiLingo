# TRACE-CAG Unified Benchmark Design

## Objective

Refactor `model-development/benchmark` into a maintainable benchmark package
that evaluates the production `ai-service` TRACE-CAG implementation rather than
maintaining a separate routing/cache implementation.

The package must support two distinct protocols:

1. `public_qa`: generation, retrieval, cache, latency, and KG behavior on
   HotpotQA, 2WikiMultihopQA, MuSiQue, and query-cluster probes.
2. `drift_safety`: PCC and SCAR-L1 safety, coverage, patch validity, route
   accuracy, and routing latency on TRACE-DriftBench.

The default live provider is Groq with `GROQ_MODEL=qwen/qwen3-32b`. Runs must
record the actual provider/model observed from pipeline state and must not label
fallback output as Qwen output.

## Current Problems

`benchmark_public_qa.py` combines environment loading, provider setup, dataset
parsing, pipeline execution, metrics, validation, console output, and JSON
reporting in one 877-line file. Dataset and mode definitions are hard-coded.

The historical public QA runner also has measurement defects:

- It does not pass `context_docs`, so retrieval can collapse to a single oracle
  `benchmark_context` item.
- Its `Recall@K` and `MRR@5` helpers infer retrieval quality from answer EM/F1
  instead of `retrieval_trace`.
- The `fresh_run` argument is accepted but does not establish a documented,
  deterministic reset boundary for response cache, KG query cache, and online
  ranker state.
- KG readiness is not captured as a run precondition or report artifact.
- Provider fallback is permitted without making primary-provider validity a
  configurable run requirement.

The historical EM/F1, cache, and latency results remain useful as comparison
points. Historical retrieval numbers must be marked non-comparable.

## Architecture

Create a Python package at:

```text
model-development/benchmark/tracecag_bench/
```

The package owns benchmark concerns only. Production behavior remains in
`api.services.trace_cag`.

```text
tracecag_bench/
  __init__.py
  cli.py
  config.py
  catalog.py
  schemas.py
  environment.py
  datasets/
    __init__.py
    public_qa.py
    driftbench.py
  runtime/
    __init__.py
    ai_service.py
    reset.py
  protocols/
    __init__.py
    public_qa.py
    drift_safety.py
  metrics/
    __init__.py
    text.py
    retrieval.py
    cache.py
    safety.py
    latency.py
  kg/
    __init__.py
    preflight.py
  reporting/
    __init__.py
    json_report.py
    console.py
```

`model-development/benchmark/benchmark.py` is the thin executable entry point.
`benchmark_public_qa.py` and `run_benchmark_all_datasets.sh` remain as
compatibility wrappers and delegate to the new CLI.

## Configuration

`BenchmarkConfig` is an immutable dataclass built from CLI arguments and
`model-development/.env`.

Required defaults:

- provider: `groq`
- model: `qwen/qwen3-32b`
- seed: `42`
- primary provider required for live validation: `true`
- fallback enabled: `false` unless explicitly requested
- candidate mode: `candidate_pool`
- cache repeats: `2` for public QA
- drift split: `test`

Environment aliases are normalized in one place:

- `GROQ_KEYS` to `GROQ_API_KEYS`
- first `GEMINI_KEYS` entry to `GEMINI_API_KEY` only when fallback is enabled

The CLI may override model/provider controls without editing `.env`. Each report
contains the effective configuration with secrets removed.

## Catalog

`catalog.py` declares datasets and execution modes as typed dataclasses.

Public QA datasets:

- `hotpotqa`
- `2wikimultihopqa`
- `musique`
- `query_clusters`

Drift dataset:

- `trace_driftbench`, with train, calibration, and test splits

Modes:

- `cag_vanilla`
- `hipporag_proxy`
- `tracecag_rapid`
- `tracecag_adaptive`
- `l2_only`
- Drift ablations that can be expressed through production runtime controls

Proxy modes are labeled as proxies in every report. The benchmark must not claim
official GraphRAG, HippoRAG, LightRAG, or vCache reproduction.

## Dataset Contracts

### Public QA

`PublicQASample` contains:

- sample ID, dataset, question, accepted answers
- context documents with stable IDs/titles/text
- supporting title IDs
- optional cluster ID and expected cache route
- original metadata

The loader validates that context documents and supporting titles exist. It
deduplicates supporting titles for denominator calculations while preserving
the original metadata.

### TRACE-DriftBench

The independent DriftBench data is copied and normalized into:

```text
model-development/datasets/benchmarks/trace_driftbench/
  train.jsonl
  calibration.jsonl
  test.jsonl
  manifest.json
```

Each cluster has one base request and ordered variants. Each request records:

- query and expected output
- learner profile/level
- intent, concepts, graph neighborhood
- profile, policy, KG, relation, target, and evidence version fields
- expected route and safety label

The source data under `tracecag_benchmark` remains untouched during migration so
historical paper artifacts are reproducible.

## Runtime Adapter

`AIServiceRuntime` is the only benchmark component allowed to invoke
`TraceCAGPipeline.analyze`.

It accepts a typed benchmark request and returns a `RunObservation` containing:

- answer, error, and total latency
- cache hit, decision, layer, bucket, and risk
- PCC/SCAR decision reasons and routing timing
- retrieval trace and retrieval metadata
- KG seed/expanded concepts and KG snapshot metadata
- graph update metrics
- models/providers used and fallback classification
- raw state fields needed by metrics

Public QA passes `context_docs`, `supporting_titles`, source IDs, and protocol
mode through `benchmark_metadata`. It passes the flat context only for generation
after candidate ranking, not as a replacement for candidate documents.

Drift safety maps learner level/profile to `learner_profile` and maps explicit
state/version fields to benchmark metadata consumed by the production cache
gate. A base request populates the cache; variants then execute in declared
order within the same isolated cluster runtime.

## Production Instrumentation

The benchmark needs a small, backwards-compatible raw-state contract from
`api.services.trace_cag`:

- `cache_gate_meta.pcc_passed`
- `cache_gate_meta.reasons`
- `cache_gate_meta.risk`
- `cache_gate_meta.tau_reuse`
- `cache_gate_meta.tau_patch`
- `cache_gate_meta.routing_latency_ms`
- normalized request/candidate state hints used by the decision

This metadata is observational. It must not change routing behavior or public
API responses unless `return_raw_state=True`.

The production cache gate must accept benchmark-provided version/evidence hints
only under an explicit benchmark metadata namespace. Normal production requests
continue deriving these values from runtime state.

## Runtime Isolation

`runtime/reset.py` provides explicit reset operations for:

- in-process response cache
- L1 bucket and bucket-version state
- KG query cache
- provider cooldown/queue state when requested
- online retrieval ranker

Reset scopes:

- `run`: before an entire benchmark
- `mode`: between comparison modes
- `cluster`: between DriftBench clusters

The adapter reuses one compiled pipeline within a mode unless reset semantics
require reconstruction. Reset actions are recorded in the report.

## Public QA Protocol

Two evidence modes are separate:

### Candidate Pool

All modes rank the dataset-provided `context_docs`. This measures retrieval and
ranking under a controlled candidate set. Retrieval metrics use
`retrieval_trace` only:

- Recall@1, Recall@3, Recall@5
- MRR@5
- nDCG@5
- Precision@5

Generation metrics:

- exact match
- token F1
- answer coverage across accepted aliases

Cache metrics:

- overall, cold, and warm hit rate
- L0/L1 rates
- decision distribution
- warm speedup

Latency metrics:

- mean, median, P95
- cold and warm slices
- TTFT
- graph update and routing timing

### KG Only

Dataset candidates are not injected. The production Kuzu KG and retrieval stack
must retrieve evidence. Reports include KG entity coverage and cannot be merged
with candidate-pool retrieval results.

Generation may still use retrieved context. A missing or unhealthy KG causes a
failed preflight unless `--allow-degraded-kg` is supplied.

## Drift Safety Protocol

For each cluster:

1. Reset cluster-local cache state.
2. Run the base request through production TRACE-CAG to create the artifact.
3. Run variants in their declared order.
4. Compare actual route with expected route and accepted safety behavior.

Primary metrics:

- safe reuse precision
- admissible recall
- unsafe acceptance rate
- fallback rate
- patch recall/rate
- route accuracy
- accepted-case and overall routing latency
- quality preservation using exact match/token F1 where expected output exists

Uncertain labels are reported separately and excluded from safety precision and
unsafe-acceptance denominators.

Calibration selects thresholds on the calibration split under an unsafe budget.
The test split must use fixed selected thresholds and report the calibration
manifest. No test data may tune thresholds.

## KG Preflight

`kg/preflight.py` checks:

- effective `KUZU_DB_PATH`
- database readability
- concept and relation counts where supported
- dataset entity/title coverage
- expected benchmark seed metadata if present

The result is attached to every report. Candidate-pool runs may warn and
continue because their documents are controlled. KG-only runs fail by default
when the KG is unavailable.

Dataset preparation scripts that seed Kuzu remain separate from evaluation.
Evaluation never silently mutates the KG.

## Reporting

Each run writes:

- one canonical JSON report
- optional JSONL observations
- a human-readable console summary

The canonical report contains:

- protocol and evidence mode
- dataset path, split, count, seed, and content hash
- effective non-secret configuration
- requested and observed provider/model
- fallback and error rates
- KG preflight snapshot
- reset/isolation manifest
- per-mode metrics
- per-category DriftBench breakdown
- validation violations

Provider validity fails when the primary provider is required and an observation
uses fallback, extractive bypass, or no provider. A run can complete and write a
report while returning a non-zero validation exit code.

Historical results are included only as an explicitly labeled comparison block.
Historical public-QA retrieval metrics are marked `non_comparable`.

## Error Handling

- Invalid JSONL rows include path and line number.
- Missing required fields fail dataset loading before provider calls.
- Pipeline exceptions become observations with `error` populated.
- Empty answers and provider bypasses are counted, not dropped.
- Quota/429 responses are visible in provider validation and logs.
- Report writing occurs in a `finally` path when partial observations exist.
- Secrets are never logged or serialized.

## Testing

Unit tests cover:

- public and drift dataset validation
- exact match/token F1 and alias handling
- retrieval metrics from ranked traces
- safety metric denominators and uncertain exclusion
- cold/warm cache slicing
- provider/model observation classification
- KG preflight behavior
- report serialization and secret redaction
- runtime reset boundaries

Integration tests use a fake pipeline for deterministic protocol behavior.
Focused production integration tests exercise `TraceCAGPipeline` raw-state
instrumentation without live provider calls.

A live smoke command runs one or two samples with Groq Qwen 3 32B when
credentials and quota are available. Live tests are not part of the default
unit test suite.

## Compatibility and Migration

- Keep existing result files unchanged.
- Keep `benchmark_public_qa.py` as a deprecation wrapper for one release cycle.
- Update `run_benchmark_all_datasets.sh` to call the new CLI.
- Do not delete `model-development/tracecag_benchmark`.
- Add documentation that the independent harness is a paper-reference simulator,
  while new benchmark claims come from the production `ai-service` runtime.

## Acceptance Criteria

1. No new benchmark routing/cache implementation duplicates TRACE-CAG.
2. Both protocols run through `TraceCAGPipeline`.
3. Public QA retrieval metrics are derived from `retrieval_trace`.
4. Candidate-pool and KG-only results are clearly separated.
5. Drift safety evaluates production PCC/SCAR decisions with calibrated/test
   separation.
6. Default live configuration requests Groq `qwen/qwen3-32b`.
7. Reports identify the actual model/provider and invalidate unexpected fallback.
8. KG readiness and dataset hashes are reproducible report artifacts.
9. Existing CLI entry points continue working through wrappers.
10. Focused unit and integration tests pass without live network access.
