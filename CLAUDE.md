# LexiLingo — Claude Code Project Instructions

## Project Overview

Language learning app (Duolingo-style). Stack:
- `flutter-app/` — Flutter mobile, Provider state management, Clean Architecture
- `backend-service/` — FastAPI + SQLAlchemy async (PostgreSQL)
- `ai-service/` — Python AI/ML (sentence-transformers, Whisper STT, TRACE-CAG pipeline)
- `admin-service/` — React admin dashboard
- `gateway/` — API gateway (Kong or Traefik)
- `mcp-server/` — Custom MCP server for LexiLingo tools

## Architecture Rules

- Flutter: Clean Architecture — `data/` → `domain/` → `presentation/`. Never import presentation from domain.
- Backend: async-first — all DB calls use `await`, never sync SQLAlchemy.
- AI service: FastAPI routes → services → handlers. No business logic in routes.
- Do not cross service boundaries directly — go through the gateway.

## Key Files

| File | Purpose |
|------|---------|
| `backend-service/scripts/seed_courses.py` | Production seed (idempotent, one-shot) |
| `backend-service/scripts/seed_data.py` | Master seed entry point |
| `flutter-app/lib/features/learning/presentation/screens/learning_roadmap_screen.dart` | Duolingo-style zigzag roadmap |
| `ai-service/api/services/trace_cag/` | TRACE-CAG multi-hop reasoning pipeline |

## DB Models — Non-obvious Constraints

- `VocabularyItem.part_of_speech` → `PartOfSpeech` enum (lowercase: `noun`, `verb`, …)
- `VocabularyItem.difficulty_level` → `DifficultyLevel` enum (uppercase: `A1`, `A2`, …)
- `GrammarItem.content` → Text (not JSON); `examples` → JSON list
- `GameWord.cefr_level` → plain String (`A1`–`C2`)
- `TestExam.question_ids` → JSON list (populated at runtime)
- bcrypt: use `import bcrypt; bcrypt.hashpw(...)` directly — passlib has a 4.x bug

## Python Environment

```bash
# backend-service
cd backend-service && source venv/bin/activate

# ai-service
cd ai-service && source venv/bin/activate   # python3.12
```

## Seed Run Order

```
seed_data.py → seed_courses.py → seed_analytics.py → seed_demo_data.py → seed_questions.py
```

Expected DB state after full seed: 109 users, 1614 daily activities, 98 questions.

## Testing

- Backend: `pytest` from `backend-service/`
- Flutter: `flutter test` from `flutter-app/`
- AI service integration tests: `pytest tests/trace_cag/`

## MCP Tools (use BEFORE grep/read)

This project has a code-review-graph knowledge graph. Prefer:
- `semantic_search_nodes` over grep for finding functions
- `get_impact_radius` over manual import tracing
- `detect_changes` + `get_review_context` for code review
- `query_graph` for caller/callee/test relationships

## Code Style

- No comments unless the WHY is non-obvious
- No docstrings beyond a single short line
- Flutter: `Theme.of(context)` tokens only — never hardcode colors or sizes
- Python: type hints on all function signatures
- Async Python: `async def` + `await` everywhere in service/handler layer
