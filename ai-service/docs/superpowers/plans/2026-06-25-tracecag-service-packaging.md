# TRACE-CAG Service Packaging Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a portable TRACE-CAG service package that can be imported by other projects without breaking the existing LexiLingo app.

**Architecture:** The new package defines stable request/response schemas and a runtime wrapper around a pluggable analyzer protocol. The existing app is integrated through a lazy LexiLingo adapter, while a dependency-free in-memory adapter proves portability.

**Tech Stack:** Python dataclasses, Protocol typing, asyncio, pytest.

---

## Chunk 1: Additive Package

**Files:**
- Create: `service/__init__.py`
- Create: `service/tracecag_service/__init__.py`
- Create: `service/tracecag_service/config.py`
- Create: `service/tracecag_service/schemas.py`
- Create: `service/tracecag_service/ports.py`
- Create: `service/tracecag_service/runtime.py`
- Create: `service/tracecag_service/core/fingerprint.py`
- Create: `service/tracecag_service/core/scar_l1.py`
- Create: `service/tracecag_service/adapters/lexilingo.py`
- Create: `service/tracecag_service/adapters/memory.py`
- Create: `service/tracecag_service/README.md`

- [x] Add portable dataclass schemas.
- [x] Add analyzer protocol and service runtime.
- [x] Add pure fingerprint and SCAR-L1 helpers.
- [x] Add lazy adapter to the existing LexiLingo pipeline.
- [x] Add in-memory adapter for dependency-free use.
- [x] Document usage.

## Chunk 2: Tests

**Files:**
- Create: `tests/service/test_tracecag_service_runtime.py`
- Create: `tests/service/test_tracecag_memory_adapter.py`
- Create: `tests/service/test_tracecag_lexilingo_adapter.py`

- [x] Test runtime accepts a pluggable analyzer and normalizes dict responses.
- [x] Test in-memory adapter cache miss, exact reuse, and L1 patch behavior.
- [x] Test LexiLingo adapter lazily calls the existing pipeline with mapped kwargs.
- [x] Run targeted pytest for `tests/service`.
