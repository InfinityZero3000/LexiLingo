# TRACE-CAG end-to-end audit — 2026-07-17

## Outcome

The main request path is continuous and testable:

`input → L0/L1 discovery → certificate hard gate → canonical SCAR → optimistic recheck → reuse/patch or L2 retrieval → grounded generation → certificate/cache write → reverse-edge registration`.

Focused verification: `94 passed`; Ruff unused/import/name checks, `py_compile`, and `git diff --check` pass.

## Mechanism status

| Mechanism | Production path | Evidence | Status |
|---|---|---|---|
| L0 exact reuse | `cache_utils.cache_gate_node` | routing/certificate tests | Validated |
| L1 candidate discovery | graph buckets in `cache_utils` | L1 routing tests | Validated in tests; no frozen Day 1–2 hit |
| PCC | hard constraints inside canonical `decide_l1_reuse` | mismatch/fail-closed tests | Validated |
| SCAR | `l1_state_cache.py`; compatibility re-exports only | parity tests | Canonical and continuous |
| Typed patch | declared slots plus factual/provenance hashes | patch contract tests | Validated in tests; no frozen workload observation |
| Dependency capture | learner/KG/evidence/source/policy resolver events | resolver/certificate tests | Validated in tests |
| Optimistic recheck | immediately before L0/L1 service | race tests | Validated in tests |
| Reverse invalidation | dependency reverse sets and Redis sets | focused invalidation tests | Partial production coverage |
| Learner mutation hook | shared mastery writer | mutation test | Connected |
| KG mutation hook | no shared writer hook found | caller audit | Missing |
| Policy mutation hook | no shared writer hook found | caller audit | Missing |
| Multi-hop interleaving | benchmark candidate path, flag off by default | offline n=64 probes; end-to-end n=5 | Research validated, not production default |
| Drift route gate | benchmark protocol | deterministic metric tests | Code complete; frozen DriftBench pending |

## Dead/redundant code audit

- Removed the unused `httpx_module` argument from `_throttled_post_json` and all callers; the function already owns its pooled client.
- Removed four imports that existed only to satisfy that dead argument.
- Kept `AsyncGenerator`: it is used by streaming annotations.
- Kept legacy `tracecag_benchmark/tracecag/pcc.py`: the legacy router and benchmark runner still call it.
- Kept service SCAR re-export modules: active portable-service imports use them; they do not duplicate the formula.
- Kept research flags with one read site because they are active protocol inputs; single-use is not proof of dead code.

## Submission/production blockers

1. Connect KG and policy mutation boundaries to token increment plus targeted invalidation, or narrow the claim to learner-state mutations.
2. Run frozen DriftBench with observed L1 reuse, typed patch, unsafe rejection, and validate/serve mutation race.
3. Run multi-hop interleaving on a full locked split; n=5 shows no regression but does not prove answer-quality gain.
4. Keep `TRACECAG_SECOND_HOP_INTERLEAVE=false` until paired EM/F1 and latency gates pass.

## Defensible current claim

TRACE-CAG has a continuous certificate-gated routing implementation with canonical SCAR, dependency-aware cache artifacts, optimistic pre-serve recheck, learner-mutation invalidation, and provenance-preserving L2 reconstruction. General KG/policy mutation safety and full multi-hop superiority remain unverified.
