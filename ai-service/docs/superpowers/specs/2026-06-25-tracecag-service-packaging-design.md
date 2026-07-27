# TRACE-CAG Service Packaging Design

## Goal

Package the reusable TRACE-CAG runtime behind a stable service contract without changing the existing FastAPI routes, pipeline graph, Redis, KG, or model gateway behavior.

## Boundary

The new code lives under `service/tracecag_service/`. It is importable as a Python package and has no import-time dependency on `api.*`. The current LexiLingo pipeline remains the production implementation and is reached only through a lazy adapter.

## Design

The package exposes:

- `TraceCAGRequest` and `TraceCAGResponse` dataclasses for a stable cross-project contract.
- `TraceCAGService`, a small lifecycle wrapper with validation, timeouts, batch concurrency, and response normalization.
- `TraceCAGAnalyzer`, a protocol that any project can implement.
- `LexiLingoTraceCAGAnalyzer`, a lazy adapter to the existing `api.services.trace_cag.graph.get_trace_cag()` pipeline.
- `InMemoryTraceCAGAnalyzer`, a dependency-free adapter for local tests, demos, and new projects before they wire real KG/LLM backends.
- Portable core helpers for fingerprinting and SCAR-L1 reuse decisions.

## Non-Breaking Rules

- Do not move or rename existing `api/services/trace_cag` modules in this pass.
- Do not edit FastAPI routes.
- Do not change existing singleton lifecycle.
- Do not import `api.*` from package top-level modules.
- Keep the current app path intact; the new service is additive.

## Follow-Up

After this additive package is stable, pure logic can be moved gradually from `api/services/trace_cag` into `service/tracecag_service/core` with compatibility re-exports.
