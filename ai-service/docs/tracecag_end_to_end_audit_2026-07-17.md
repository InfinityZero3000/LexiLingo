# TRACE-CAG end-to-end audit — 2026-07-17

> **Superseded in part (2026-08-26, revised 2026-08-29).** Blockers 3–4 below are
> resolved and the
> multi-hop claim is now measured: see `tracecag_benchmark_report_2026-08-26.md`
> for n=64 results against the real HippoRAG package, the new
> `all_support_at_k` / `answer_in_context_at_k` metrics, and the four ranking
> and evidence-budget fixes. The mechanism table and the KG/policy mutation
> blockers in this document still stand.
>
> **Per-metric comparison (2026-08-30):** see
> `tracecag_metrics_comparison_2026-08-30.md`. It settles one row of the
> mechanism table with measurement: **L1 has never fired** — `l1_rate` is 0.0
> in every mode of every run since 2026-05-30. The 48.4% cache hit rate is
> entirely L0 exact-repeat on the protocol's warm pass, so "L1 validated in
> tests; no frozen Day 1-2 hit" now reads: no hit anywhere, on any workload
> measured to date. HotpotQA cannot produce one — 64 unrelated questions never
> share a graph bucket. Measuring L1 needs a clustered question set.

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
| Optimistic recheck | immediately before L0/L1 service | race tests | Validated; **inert for KG until 2026-08-31** (nothing published the token) |
| Reverse invalidation | dependency reverse sets and Redis sets | focused invalidation tests | Partial production coverage |
| Learner mutation hook | shared mastery writer | mutation test | Connected |
| KG mutation hook | `kg_service_v3.sync_knowledge_files` publishes the new content token | mutation/recheck tests | **Connected 2026-08-31** |
| Policy mutation hook | not needed — `POLICY_VERSION_TOKEN` is a deploy-time constant the certificate compares | `mismatch:policy_version` test | **Covered by certificate** |
| Multi-hop interleaving | ~~benchmark candidate path~~ | — | **Removed 2026-08-29**: the flag was off *and* the reordering was discarded by the score-sort in `_select_diverse_multihop_evidence`, so it could not affect output even when enabled |
| Coverage-first evidence selection | `retrieve.py`, benchmark multi-hop only | n=64 `all_support_at_5` | Replaces the above; reserves one slot per question anchor |
| Drift route gate | benchmark protocol | deterministic metric tests | Code complete; frozen DriftBench pending |

## Dead/redundant code audit

- Removed the unused `httpx_module` argument from `_throttled_post_json` and all callers; the function already owns its pooled client.
- Removed four imports that existed only to satisfy that dead argument.
- Kept `AsyncGenerator`: it is used by streaming annotations.
- Kept legacy `tracecag_benchmark/tracecag/pcc.py`: the legacy router and benchmark runner still call it.
- Kept service SCAR re-export modules: active portable-service imports use them; they do not duplicate the formula.
- Kept research flags with one read site because they are active protocol inputs; single-use is not proof of dead code.

## Submission/production blockers

1. ~~Connect KG and policy mutation boundaries~~ — **done 2026-08-31**, and the
   audit understated it. This was not merely a missing hook: it was a live
   staleness hole. `get_kg_content_version()` produces a real content hash and
   `kg_expand_node` emits it, but the only consumer was
   `observe_dependency_tokens`, which is `setdefault` by design so a stale
   artifact cannot roll a token back. Nothing ever called the publisher, so the
   store kept the first version forever, `recheck_dependency_snapshot` compared a
   stale entry against its own token, matched, and **L0 served the pre-change
   answer**. The certificate could not catch it either — its `kg_version` is the
   hardcoded schema constant `kg_schema_v2`, not the content hash. Proven
   end-to-end, then fixed by publishing the token from the sync path.
   Policy needed no hook: `POLICY_VERSION_TOKEN` is a deploy-time constant and
   `decide_l1_reuse` rejects on `mismatch:policy_version` (verified).
2. Run frozen DriftBench with observed L1 reuse, typed patch, unsafe rejection, and validate/serve mutation race.
3. ~~Run multi-hop interleaving on a full locked split~~ — done 2026-08-26 at n=64; see the new report.
4. ~~Keep `TRACECAG_SECOND_HOP_INTERLEAVE=false`~~ — the flag and its code were
   deleted on 2026-08-29 as provably inert (see the mechanism table).
5. **The architectural gap is no longer measurable at n=64.** The 2026-08-28
   ranker and IRCoT fixes are generic, so they lifted the vanilla-CAG baseline
   more than the graph path: `tracecag_rapid` minus `cag_vanilla` fell from
   +3.1 EM / +3.4 F1 to **0.0 EM / +0.4 F1**. TRACE-CAG still retrieves better
   (`all_support@5` 59.4% vs 50.0%), but that advantage no longer converts into
   answer quality — the reader is now the binding constraint.

## Defensible current claim

TRACE-CAG has a continuous certificate-gated routing implementation with canonical SCAR, dependency-aware cache artifacts, optimistic pre-serve recheck, learner-mutation invalidation, and provenance-preserving L2 reconstruction. General KG/policy mutation safety remains unverified.

Multi-hop quality is no longer unverified, but the honest reading is narrower
than the one first written here. At n=64 on HotpotQA (validated run, 0 provider
fallbacks):

| System | EM | F1 | R@5 | latency/question |
|---|---|---|---|---|
| `tracecag_rapid` | 62.5% | 74.7% | 78.9% | 2.2s (cold) |
| `cag_vanilla` | 62.5% | 74.5% | 74.2% | 2.1s (cold) |
| HippoRAG 2 (real package) | 53.1–56.2% | 69.7–73.0% | **85.9%** | 66–81s |

HippoRAG's EM/F1 are given as a range over two runs of the *same* configuration
(53.1/69.7 and 56.2/73.0): 4 of 64 answers differ between them, which is
ordinary LLM nondeterminism, not a config effect. Quote the range.

TRACE-CAG beats the real HippoRAG package on both headline metrics at ~30–37x
lower latency. It does **not** currently beat vanilla CAG on EM: the two are
tied, and the F1 margin of 0.4pp is inside run-to-run noise. Any claim that the
graph architecture drives the answer-quality win is unsupported at this n.
HippoRAG still retrieves better than either (85.9% vs 78.9%) and still converts
that advantage into a worse answer — the same reachability-vs-conversion split
seen inside TRACE-CAG.

**The R@5 figure was corrected on 2026-08-29 and the old one must not be
quoted.** HippoRAG's adapter scored recall by searching the *joined body text*
of the retrieved passages for the gold title, and on HotpotQA bridge questions
one passage names the other's title by construction. The adapter now matches on
document identity, and a full n=64 re-run measured the damage directly:

| | R@5 |
|---|---|
| old (joined-text match) | 93.8% |
| new (document identity) | **85.9%** |

so the old rule inflated by **7.8pp**, disagreeing on 13 of 64 questions. Note
it was noisy in *both* directions, not merely generous: on 2 questions the gold
passage was retrieved but its title never appears in the body text, so the old
rule scored a miss on a hit.
