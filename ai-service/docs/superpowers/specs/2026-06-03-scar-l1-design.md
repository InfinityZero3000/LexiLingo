# SCAR-L1 Design

## Goal

Build SCAR-L1, a state-certified adaptive reuse layer for TraceCAG. The layer turns the current L1 graph-bucket cache from a brittle near-hit lookup into a conservative, testable artifact-reuse controller that can accept safe paraphrase/surface drift, patch moderate drift, and reject unsafe learner/profile/answer-target/relation drift.

## Research Position

The novelty is not another semantic cache. SCAR-L1 treats reuse as an admissibility decision over state:

- Learner state: CEFR level, profile epoch, progress bucket, root-cause concepts.
- Task state: intent, answer target, relation path, requested output form.
- Evidence state: graph bucket, supporting titles, evidence dependency hash.
- Deployment state: graph version, policy version, TTL/freshness.

This complements existing CAG/semantic-cache/RAG work by adding a profile- and graph-state certificate before application-level artifacts are reused.

## Current Problem

TraceCAG already has:

- L0 exact cache.
- L1 graph bucket registration.
- Bucket version records.
- PCC risk scoring.
- L1 lookup inside `cache_gate_node`.

The current L1 does not activate in the public QA benchmark and misses all labeled patch cases in the drift pilot. The local implementation uses lightweight regex/token concepts and strict promotion rules, so it is safe but under-recovers admissible near hits.

## Proposed Architecture

Add `api/services/trace_cag/l1_state_cache.py` as a focused pure-Python module. It owns:

- Signature extraction from a request/cache entry.
- Certificate construction.
- Hard reject checks.
- Risk scoring.
- Candidate ranking.
- Patch eligibility.
- Decision output.

`nodes_v2.py` remains the orchestration layer:

- Keep L0 exact lookup first.
- Use SCAR-L1 for L1 candidate evaluation.
- Keep existing in-memory and Redis bucket storage initially.
- Keep `_patch_response` as the first patch function, then improve it later.

## Data Model

`L1RequestSignature`

- `query_norm`
- `intent`
- `level`
- `profile_epoch`
- `session_turn`
- `concepts`
- `entities`
- `answer_target`
- `relation_hints`
- `evidence_hash`

`L1CandidateSignature`

- Same fields as request signature, plus `created_at`, `ttl`, `graph_bucket`, and deployment versions.

`L1Decision`

- `decision`: `reuse`, `patch`, or `full`
- `risk`
- `rank_score`
- `reasons`
- `safe_to_reuse`

## Decision Rules

Hard reject when any of these are true:

- CEFR level differs unless explicitly allowed by metadata.
- Profile epoch differs.
- Graph/policy version is stale.
- Evidence dependency hash is present on both sides and differs.
- Answer target differs.
- Relation path differs.
- Concept overlap is below the floor.

Allow `reuse` when:

- No hard reject.
- Query is exact or normalized-equivalent.
- Risk is at or below `tau_reuse`.

Allow `patch` when:

- No hard reject.
- Intent, level, profile, answer target, relation hints, and evidence remain compatible.
- Surface/paraphrase drift is detected.
- Risk is at or below `tau_patch`.

Return `full` otherwise.

## Benchmark Target

On the existing `graphcag_drift_probes` n=48 pilot:

- Keep incorrect reuse rate at `0.0`.
- Keep PCC precision at `1.0` or at least `>= 0.98`.
- Raise PCC recall from `0.5` to at least `0.85`.
- Convert the six expected `patch` cases from `full` to `patch`.
- Produce non-zero L1 patch rate.

## Testing Strategy

Unit tests first:

- Exact repeat returns `reuse`.
- Punctuation near-hit returns `patch`.
- Paraphrase near-hit returns `patch`.
- Intent shift returns `full`.
- Relation shift returns `full`.
- Answer-target shift returns `full`.
- Level/profile mismatch returns `full`.
- Stale version returns `full`.

Integration tests:

- `cache_gate_node` uses SCAR-L1 to accept a near-hit candidate.
- Existing L0 tests still pass.
- Existing L1 regression remains valid.

## Non-Goals

- Do not add a new embedding model in the first implementation.
- Do not move Redis storage in the first implementation.
- Do not rewrite `nodes_v2.py`.
- Do not claim provider prompt-cache token savings from SCAR-L1.

## Approval

Approved by user on 2026-06-03 after reviewing the SCAR-L1 direction.
