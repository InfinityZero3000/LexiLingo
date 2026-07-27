# Production KG Isolation Design

## Goal

Rebuild a clean production knowledge graph and make it impossible for benchmark
entities or raw retrieval context to reach Lexi chat again.

## Architecture

Production and benchmark knowledge use separate source directories and separate
Kuzu paths. Production startup validates that its graph contains no
`concept:benchmark.*` nodes and fails readiness when the invariant is violated.
The benchmark seeder requires explicit benchmark-only destinations and refuses
the runtime DB/source paths.

The existing runtime database is rebuilt from the allowlisted production JSON
sources. The rebuild is performed into a new path, validated, then promoted;
the contaminated database is retained as a quarantine backup rather than
modified in place. Per the approved clean rebuild, existing `Mastery` data is
discarded and is not migrated from the contaminated database.

## Generation safety

Extractive QA remains available only for explicit benchmark tasks and policies.
Normal Lexi chat uses a fixed, user-safe degraded response when all LLM providers
are unavailable. Degraded responses are not written to TraceCAG response cache,
including the separate Lexi streaming path. The cache policy version in
`cache_utils.py` changes so previously poisoned entries cannot be served after
rollout.

## Reliability boundaries

Kuzu auto-recovery runs only for recognized corruption errors. Configuration,
schema, permission, lock, and programming errors fail startup without deleting
the database. Production source ingestion is allowlisted and rejects benchmark
namespaces before merging.

## Verification

- Seeder refuses runtime paths and writes only to benchmark storage.
- Production KG initialization rejects benchmark namespaces.
- A clean rebuild contains zero benchmark concepts and expected runtime concepts.
- Provider outage never returns retrieved context or concept IDs and is not cached.
- Existing benchmark QA extractive behavior remains intact.

## Deliberate exclusions

This incident does not split the large retrieval or generation modules and does
not introduce a repository/factory abstraction. Those changes do not improve the
runtime/benchmark isolation invariant.
