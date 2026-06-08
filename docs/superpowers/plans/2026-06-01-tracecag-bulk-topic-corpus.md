# TraceCAG Bulk Topic Corpus Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate 60 new UI topics and more than 10,000 TraceCAG quadruple/edge lines.

**Architecture:** Add one deterministic generator script that owns topic blueprints, story construction, quadruple/edge expansion, KG concept conversion, validation, and file writes. Update Flutter topic defaults so all topics can be loaded and use the `tracecag` preferred LLM label.

**Tech Stack:** Python 3.12, JSON/JSONL, Pydantic story schema, Flutter/Dart provider/data-source defaults.

---

## Chunk 1: Generator

### Task 1: Create Generator Script

**Files:**
- Create: `ai-service/scripts/generate_tracecag_topic_corpus.py`

- [ ] Define 60 topic blueprints across travel, work, health, food, shopping, housing, education, finance, technology, culture, media, services, emergency, environment, and leisure.
- [ ] Generate valid story objects for each blueprint.
- [ ] Generate dense TraceCAG quadruples and edges.
- [ ] Write JSONL outputs and KG import JSON.
- [ ] Add validation summary report.

### Task 2: Add Tests

**Files:**
- Create: `ai-service/tests/test_generate_tracecag_topic_corpus.py`

- [ ] Assert generated story IDs are unique.
- [ ] Assert generated stories parse through `Story`.
- [ ] Assert generated quadruple/edge counts exceed target.
- [ ] Assert generated KG edges are not dangling.

## Chunk 2: UI And Naming

### Task 3: Load More Topics In Flutter

**Files:**
- Modify: `flutter-app/lib/features/chat/data/datasources/story_api_data_source.dart`
- Modify: `flutter-app/lib/features/chat/data/repositories/story_repository_impl.dart`
- Modify: `flutter-app/lib/features/chat/domain/repositories/story_repository.dart`
- Modify: `flutter-app/lib/features/chat/presentation/providers/story_provider.dart`
- Modify: `flutter-app/lib/features/chat/data/models/topic_session_model.dart`

- [ ] Raise default story fetch limit from 20 to at least 100.
- [ ] Change topic preferred LLM default from `TRACECAG` to `tracecag`.

### Task 4: Category Icons

**Files:**
- Modify: `flutter-app/lib/features/chat/presentation/pages/story_selection_page.dart`
- Modify: `flutter-app/lib/features/chat/presentation/widgets/topic_card.dart`

- [ ] Add icons for expanded topic categories.

## Chunk 3: Generate And Verify Data

### Task 5: Run Generator

**Files:**
- Modify: `ai-service/data/sample_stories.json`
- Create: `ai-service/data/sample_stories.expanded.json`
- Create: `ai-service/data/kg/06_tracecag_topic_expansion.json`
- Create: `ai-service/data/kg_output/tracecag_topic_quadruples.jsonl`
- Create: `ai-service/data/kg_output/tracecag_topic_edges.jsonl`
- Create: `ai-service/data/kg_output/tracecag_knowledge_prefix.full.txt`
- Create: `ai-service/data/kg_output/tracecag_topic_corpus_report.json`

- [ ] Run generator with `--merge-stories`.
- [ ] Confirm counts and validation results.

### Task 6: Tests

**Files:**
- Test: `ai-service/tests/test_generate_tracecag_topic_corpus.py`

- [ ] Run `PYTHONPATH=. pytest tests/test_generate_tracecag_topic_corpus.py tests/test_topic_prompt_builder.py -q`.
- [ ] Run `flutter analyze` if Flutter changes need validation.
