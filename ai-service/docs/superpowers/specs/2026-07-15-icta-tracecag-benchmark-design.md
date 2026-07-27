# ICTA TRACE-CAG Benchmark and Paper Design

## Goal

Produce a reproducible TRACE-CAG evaluation, compare it fairly with historical runs, audit the implementation against the paper, and use only verified evidence in an eight-page ICTA DOCM submission.

## Frozen evaluation protocol

- Use the existing seven-stage daily benchmark runner and manifest.
- Use seed 42, Groq `qwen/qwen3-32b`, candidate-pool evidence, two cache repeats, no fallback, and no degraded provider.
- Keep the clean, read-only evaluation KG snapshot and verify its SHA-256 before every public-QA stage.
- Run `n=5` preflight before each paid public-QA stage; proceed only when validation passes.
- Keep cold generation quality separate from warm-cache efficiency.
- Do not tune thresholds on the held-out DriftBench test split.
- Compare runs only when dataset, split, seed, model, evidence mode, cache repeats, and implementation protocol are compatible.
- “Best” means the best valid run under a declared metric and compatible protocol, never a per-cell maximum assembled across incompatible runs.

The executable protocol is `model-development/benchmark/run_daily_benchmark.py` with `model-development/benchmark/daily_benchmark_manifest.json` schema version 2. The run records the Git commit or dirty-tree implementation SHA, Python/package versions, manifest SHA-256, input SHA-256 values, prompt/config hashes, provider/model actually observed, timestamps, request IDs when returned, retry counts, token usage, and host CPU/RAM/OS. The frozen KG is `model-development/benchmark/snapshots/eval-kuzu-clean-20260715.db`, expected SHA-256 `9cbd4f1cfa1edbfea0ab2553141fd7fc7d1d6bedf7c1ee18e79e7776328b2706`. Generated artifacts are indexed in an append-only JSON manifest containing paths, hashes, exclusions, and table/figure provenance.

Expected hashes are: manifest `7d370328c2c8ef67e5d3922c775e1fb181720d21a1b804da19953123158ace0c`; HotpotQA `6abaa163b80d897b3a0d63456c1345bcee20462e186c4b1dc6dfadc305585cd5`; 2Wiki `ab56b3beac30cc9da613e0e03815e3c1b7490b0cfadd4707c5e15ef8d447b669`; query-clusters `b12b8fea9f4f0c26944ec291d549b6f58847f5995a48261f327d728db8e27eb4`; MuSiQue `5ab2c6f7f648b6c58806f8ab2ad4f1bdca7a4fe8fe75b272265cbf6ba035f374`; DriftBench test `43887f662cfd4ce571fa2d4c0f1d962b850ddb59155e5b7964d6c3a42d0af089`. Before final execution, canonical sorted `protocol-lock.json` adds the clean Git commit (or an archived binary diff and its hash), dependency-lock hash, prompt hashes, and `max_tokens=96`; its SHA-256 is the protocol ID.

Public-QA final sizes are the complete frozen files: HotpotQA 64, 2WikiMultihopQA 64, query-clusters 32, and MuSiQue 500 validation items, preserving repository order after documented normalization/deduplication. The fixed preflight is the first five items and remains part of the final run; it gates only schema/artifact validity, exact provider/model match, no fallback, complete observation count, and KG isolation. DriftBench uses the complete frozen test file: 12 base clusters and 240 variants stratified by drift family; clusters, not variants, are the resampling unit. This is fixed-sample exploratory evidence, not a powered confirmatory trial. One temperature-zero cold generation per item does not estimate hosted-provider nondeterminism, so claims are narrowed accordingly. No parameter or code change is permitted after a final stage begins without a new protocol ID and complete stage invalidation.

Generation uses temperature 0, max_tokens 96, no top-p override, one serial process, and 30-second HTTP timeouts. A 401 tries the next configured key; only 503 is retried, at most five times with 2/4/8/16/32-second backoff; other statuses/exceptions fail. Cache is reset before each dataset/method, cold requests are timed end-to-end with a monotonic clock, and warm repeats replay the same request after a successful cold write. Resume appends only absent stable `(dataset,item,mode,repeat)` keys; prior attempts, IDs, statuses, and errors remain immutable, and duplicate keys invalidate the stage. Provider revision/region are recorded when exposed. Failed samples remain failures/abstentions; code/config/KG changes force a stage restart.

## Execution sequence

1. Check Docker daemon, disk/memory, Python environment, dependencies, datasets, KG hash, API-key presence, and provider/model preflight.
2. Start only Redis, because the benchmark calls the production Python pipeline directly and does not require the full API/Mongo stack.
3. Run focused TRACE-CAG and benchmark tests.
4. Run each daily stage with resumable artifacts: raw JSON/JSONL, logs, status, checksums, and summaries.
5. Stop on validation, provider, KG-isolation, or artifact-integrity failure; diagnose and resume rather than silently degrading.
6. Aggregate DriftBench tables and compare valid new results with compatible historical artifacts.
7. Generate ablation, per-drift-type, latency, error-analysis, and artifact-provenance tables before paper drafting.

Exact orchestration commands are `venv/bin/python model-development/benchmark/run_daily_benchmark.py --day N` for N=1..7, adding `--resume` only when hashes match. Baselines are `l2_only`, `exact_cache`, `lexical_overlap_cache`, `state_semantic_cache`, `version_aware_cache`, `trace_no_pcc`, `trace_no_graph_scope`, and `trace_no_scar`; optional `embedding_cache` is included only after its recorded preflight succeeds. All methods use the same DriftBench inputs and routing budget. `hipporag_proxy` is retained only as a same-pipeline ranker proxy in public QA and cannot support a claim against HippoRAG proper.

The common routing budget is the same candidate pool, top-k, cached artifact, L2 output, state transition, frozen thresholds, and one decision per variant. Exact cache matches canonical query text; lexical/state-semantic/version-aware methods use their checked-in frozen configs; each ablation changes only its named component. A method that cannot satisfy this budget is excluded and disclosed.

## Claim policy

- Primary safety claim: unsafe-serving rate under mandatory state drift, supported by the frozen DriftBench test split.
- Efficiency claims report cold and warm latency distributions separately and state the workload/repeat assumptions.
- Public-QA quality claims use evaluator-side labels only; supporting titles and answers are not exposed to runtime routing.
- Proxy baselines are labelled as proxies, not independent GraphRAG or HippoRAG implementations.
- Small or failed runs are reported as validation/smoke evidence, not final comparative evidence.
- Every numeric table in the paper must link back to a preserved artifact and protocol hash.

Primary metric is conservative unsafe service: mandatory-drift requests routed to L0/L1 reuse/patch plus indeterminate routing failures, divided by all mandatory-drift requests. Conventional unsafe acceptance among successfully routed oracle-unsafe requests is reported separately. Availability is completed/attempted; safe-service rate is completed-and-oracle-safe/attempted. Safe-reuse precision is accepted-safe/all accepted; admissible recall is accepted-safe/all oracle-safe; patch recall is correctly patched/all patchable-safe; route accuracy is exact route matches/all scored; macro-F1 is the unweighted mean of per-route F1. Warm hit rate is warm hits/all successful warm attempts. EM is any normalized exact gold match; token-F1 is the maximum over gold answers; R@k is relevant retrieved supports/all relevant supports; MRR@5 is reciprocal rank of the first relevant support. Provider failures score zero for quality and remain availability failures. Latency p50/p95/p99 covers completed monotonic-clock attempts, with failures counted separately. Binary proportions receive 95% Wilson intervals. Paired differences use cluster bootstrap for DriftBench and item bootstrap for public QA; effect sizes and 95% intervals are primary, with paired permutation/McNemar tests where defined and Holm correction across secondary comparisons. With 12 clusters, conclusions are precision-limited; no universal-safety claim is allowed.

Public QA is automatic, not LLM-judged: `model-development/benchmark/tracecag_bench/metrics/text.py` applies SQuAD/Hotpot normalization and maximizes over multiple gold answers; retrieval uses all gold support labels in the frozen row. A pre-run leakage test clears Redis and inspects serialized prompts/evidence, request metadata, routing features, cache keys, cache values, and pre-existing cache state for answers, support-title labels, and evaluator-only fields. Its command and JSON report are hashed into the artifact index. Malformed labels or evaluator failures invalidate the stage.

Historical runs are contextual unless their configuration tuple exactly matches `(dataset SHA, split, seed, provider, model, evidence mode, generation policy, cache repeats, prompt hash, implementation hash family)`. The May/June 2026 runs use different models or legacy runners and are contextual, not pooled comparative evidence. “Best” selection occurs only among repeated valid runs with the same tuple, using the predeclared primary metric first, then admissible recall, then warm p95 latency.

The artifact index is canonical sorted JSON Lines; every record stores the preceding-record hash and its own SHA-256. Final verification recomputes the chain, all referenced file hashes, unique observation keys, protocol ID, exclusions, and generated table/figure inputs. Any mismatch blocks paper generation.

## Paper-system audit

Trace the paper’s L0/L1/L2 routing, provenance certificate, SCAR-L1 patching, PCC validation, drift monitor, atomic snapshot recheck, and fail-closed behavior to production code and tests. Classify each claim as implemented, partially implemented, benchmark-only, or unsupported. Unsupported claims are removed or narrowed.

## ICTA paper

Create the paper from the official ICTA DOCM template while preserving macros, styles, page size, margins, and two-column layout. Target exactly eight pages including references. Include: motivation and novelty; related work; explicit L0/L1/L2 architecture; algorithms/pseudocode; experimental protocol; verified results with uncertainty; ablations/error analysis; deployment feasibility and limitations; references. Include one architecture figure and one routing/invalidation figure with readable captions and alt text.

## Verification gates

- Benchmark: tests pass, provider/model match, no fallback, KG hash/isolation pass, artifacts validate, and failed samples are disclosed.
- Scientific: no test-set tuning, no incompatible-run cherry-picking, no fabricated values, and claims match evidence.
- Document: DOCM opens, macros remain present, all citations resolve, exactly eight rendered pages, and every page passes visual inspection without clipping or overlap.

## Camera-ready mathematical strengthening

Keep the eight-page limit by replacing redundant prose rather than appending a new section. Add one conditional state-consistency proposition with three explicit assumptions: complete dependency capture, mutation-sensitive version tokens, and deterministic patch preservation of factual and provenance projections. Present the proposition and central formulas in compact bordered equation paragraphs; border the routing algorithm consistently.

Expand Selective IRCoT in one short paragraph covering its deterministic trigger, one bounded bridge-retrieval step, and a contract that admits the bridge only when entity/path and evidence-support checks pass. Clarify that the displayed SCAR equation belongs to the frozen benchmark router, while the production service uses intent, concept, entity, relation, and age features; both implementations apply the certificate hard gate before soft scoring. Keep numeric citations as ordinary submission-safe text without internal bookmarks.
