# Topic Knowledge Crawl Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a script that crawls topic data, enriches topic KG data with Groq, and renders a topic knowledge prefix.

**Architecture:** Add one focused script under `ai-service/scripts` with pure helper functions for testable parsing, quota rotation, validation, merge, and prefix rendering. Runtime network work stays behind CLI execution, while unit tests use local fixtures and mocked Groq/crawl results.

**Tech Stack:** Python 3.12, `crawl4ai`, `httpx`, `pytest`, existing LexiLingo JSON data files.

---

## Chunk 1: Script And Test Scaffolding

### Task 1: Add Topic Crawl Script

**Files:**
- Create: `ai-service/scripts/crawl_topic_knowledge.py`

- [ ] Add dataclasses for `GroqKeyPool`, crawl results, extraction results, and report entries.
- [ ] Add constants for default paths and curated topic source URLs.
- [ ] Add helpers for slugifying IDs, loading JSON, atomic JSON writes, and compacting markdown.

### Task 2: Add Unit Tests

**Files:**
- Create: `ai-service/tests/test_crawl_topic_knowledge.py`

- [ ] Test quota state loads Groq keys and persists count changes without exposing keys.
- [ ] Test Groq JSON extraction strips code fences and rejects invalid shapes.
- [ ] Test merge deduplicates concepts and edges.
- [ ] Test prefix renderer emits `[LEXILINGO KNOWLEDGE BASE]` lines compatible with the current sample.

## Chunk 2: Extraction Pipeline

### Task 3: Implement Crawl And Groq Calls

**Files:**
- Modify: `ai-service/scripts/crawl_topic_knowledge.py`

- [ ] Add async crawl with `AsyncWebCrawler`.
- [ ] Add Groq chat completions call via `httpx.AsyncClient`.
- [ ] Add retry-on-malformed-JSON repair prompt.
- [ ] Add local fallback generation behind `--allow-local-fallback`.

### Task 4: Implement CLI

**Files:**
- Modify: `ai-service/scripts/crawl_topic_knowledge.py`

- [ ] Add CLI flags: `--topics`, `--limit`, `--merge`, `--update-prefix`, `--allow-local-fallback`, `--dry-run`, `--model`.
- [ ] Default to non-destructive output files.
- [ ] Print concise report counts without printing API keys.

## Chunk 3: Verification And Crawl Run

### Task 5: Run Tests

**Files:**
- Test: `ai-service/tests/test_crawl_topic_knowledge.py`

- [ ] Run `PYTHONPATH=. pytest tests/test_crawl_topic_knowledge.py -q` from `ai-service`.
- [ ] Fix any failures.

### Task 6: Run Data Generation

**Files:**
- Output: `ai-service/data/topic_graphs.enriched.json`
- Output: `ai-service/data/kg_output/topic_knowledge_prefix.txt`
- Output: `ai-service/data/kg_output/topic_crawl_report.json`

- [ ] Run the script for the 8 bundled topics.
- [ ] If sandbox network blocks crawl or Groq, rerun the same command with escalation.
- [ ] Validate output JSON and summarize counts.
