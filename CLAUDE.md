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

<!-- ASTRYX:START -->
Astryx v0.1.3 · 90+ components
CLI: run every command as `npx astryx <cmd>` (shown below as `astryx ...`).

SETUP (once, in your app entry e.g. main.tsx) — without these, components render unstyled:
  import "@astryxdesign/core/reset.css";
  import "@astryxdesign/core/astryx.css";

WORKFLOW — discover, don't guess. Before writing UI:
1. `astryx build "<idea>"` — START HERE: returns a kit (closest [page] + [block]s + [component]s). No args = full playbook.
2. `astryx template <name> [--skeleton]` — scaffold the [page]/[block]s it named, or study their layout. Templates are reference code.
3. `astryx component <Name>` — props + examples for every component you use.

RULES:
- No <div> — components do all layout/spacing. Full page → AppShell; sidebar nav → SideNav.
- Frame first: pick the shell (AppShell / Layout+LayoutPanel) and budget regions in px BEFORE writing content (`astryx docs layout`).
- Dense data = rows (Table, List/Item) edge-to-edge — never Card-wrapped list items. Card = dashboard widgets, galleries, settings groups only.
- Status → StatusDot/Token; Badge only for counts and enumerated states, never decoration.
- Custom styling: component props first; else style/className with tokens — var(--color-*|--spacing-*|--radius-*). No raw hex/px. (No StyleX/Tailwind compiler here — don't use xstyle/utility classes.)
- Tokens for every value (`astryx docs tokens`). Brand/accent via `astryx theme` — never override --color-* in :root.

MORE CLI:
  search "<query>"   find any component / hook / doc / template / block
  component --list   90+ components by category
  template --list    page + block recipes
  docs <topic>       color, elevation, icons, illustrations, layout, migration, motion, principles, shape, spacing, styling, theme, tokens, typography
  swizzle <Name>     eject component source for deep customization
  upgrade --apply    run after any @astryxdesign/core bump
<!-- ASTRYX:END -->
