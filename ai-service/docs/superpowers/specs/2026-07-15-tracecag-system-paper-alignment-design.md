# TRACE-CAG System–Paper Alignment Design

## Goal

Implement the state-certified reuse architecture claimed by TRACE-CAG, validate it with deterministic and frozen benchmarks, and update the ICTA paper only from verified artifacts.

## Decisions

- Use a system-first delivery order: implementation, tests, benchmark, then paper.
- Keep `api/services/trace_cag/` as the canonical production implementation; benchmark code imports it instead of maintaining independent routing logic.
- Unify SCAR around intent, concept, relation, evidence, and profile/version staleness features.
- Treat SCAR as an expert-weighted risk score until a separate calibration experiment exists.
- Capture dependencies through explicit resolver events rather than automatic instrumentation.
- Use optimistic token recheck immediately before reuse or patch; do not claim transactional linearizability.
- Deliver vertical slices so every stage remains runnable and independently testable.

## Canonical data flow

Resolvers emit immutable dependency events containing a canonical key, dependency kind, version token, provenance, and required flag. A compiler rejects conflicting or incomplete traces, deduplicates valid events, and writes their snapshot into the cache certificate. Cache writes register reverse edges from dependency keys to artifact keys.

L0 and L1 only discover candidates. The certificate validator performs fail-closed hard checks. Unified SCAR ranks only compatible candidates. Immediately before a reuse or patch response is returned, the gate rereads all required dependency tokens. A missing or changed token sends the request to L2 and records `snapshot_changed_before_serve`.

Mutations increment their version token before consulting the reverse index. Directly dependent artifacts are removed, and the existing bucket-version mechanism remains as coarse fail-safe invalidation.

## Components

### Dependency events and compiler

`DependencyEvent` contains `key`, `kind`, `version`, `provenance`, and `required`. The compiler:

- deduplicates identical `(key, version)` reads;
- rejects one key observed at multiple versions;
- rejects required events without a token;
- does not infer undeclared dependencies.

### Certificate

The next certificate schema stores the request/output contract, dependency snapshot, profile/policy/KG/source versions, factual and provenance projection hashes, patchable slots, schema version, and creation time. An incomplete required trace prevents cache admission.

### Unified SCAR

After the hard gate passes, risk is:

\[
\rho=w_I\delta_I+w_C\delta_C+w_R\delta_R+w_E\delta_E+w_S\delta_S.
\]

Weights and thresholds are frozen protocol inputs. Production and benchmark use the same pure implementation. Similarity or a low score can never override a certificate failure.

### Reverse invalidation

Redis sets map each dependency key to its artifact keys. Artifact deletion or expiry removes reverse edges. Mutation increments the dependency token, invalidates indexed artifacts, and also bumps the existing bucket version when the affected scope cannot be resolved precisely.

### Optimistic recheck

The cache gate validates a candidate against the first snapshot, then rereads required tokens immediately before service. Any read failure or mismatch fails closed to L2. This provides mutation-sensitive optimistic consistency, not a lock-based or linearizable transaction.

### Typed patch

Only declared presentation slots may change. A patch is admitted only if factual and provenance projections remain equal before and after transformation. Otherwise the gate reconstructs through L2.

## Verification design

Unit and integration tests must cover complete and incomplete dependency traces, related and unrelated mutations, reverse-index cleanup, the validate/serve race, L1 reuse, typed patch acceptance and rejection, empty candidates, L2 response behavior after a failed quality gate, and production/benchmark SCAR parity.

Evaluation proceeds through three gates:

1. Provider-free deterministic route tests.
2. A small frozen DriftBench preflight that must exercise L1 and patch routes.
3. Final frozen evaluation and ablations only after the first two gates pass.

The final comparison includes L2-only, exact/L0, L0+L1 without certificate, L0+L1 with certificate, and full TRACE-CAG. Primary measures are unsafe-serving rate, safe-reuse precision, admissible recall, patch precision/recall, route accuracy, latency, and answer quality with paired uncertainty.

## Paper policy

The paper is updated only after implementation SHA and protocol ID are frozen. Every claim is labeled as validated, observed, implemented-but-unexercised, or design-only. Algorithm 1 must match production control flow; dependency compiler, reverse invalidation, optimistic recheck, SCAR, and typed-patch claims require corresponding tests and artifacts. Related work must position TRACE-CAG narrowly against GroundedCache, FreshCache, Krites, RAGCache, and TurboRAG. The final DOCM/PDF must remain within eight pages and comply with the target conference's anonymity policy.

## Out of scope

- Distributed locks or transactional linearizability.
- Automatic interception of every state/KG read.
- Learned or statistically calibrated SCAR weights in this implementation cycle.
- A new cache backend; Redis and the existing in-process fallback remain.
