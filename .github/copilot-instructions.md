# GitHub Copilot Instructions for LexiLingo

## Project Overview
LexiLingo is an English learning app with 4 services:
- **flutter-app/** — Flutter frontend (Dart, Web + Mobile)
- **backend-service/** — FastAPI REST API (Python, PostgreSQL, Firebase Auth)
- **ai-service/** — AI tutoring engine (Python, Graph-CAG architecture)
- **admin-service/** — Admin dashboard (React + Vite)

## Architecture: What's RUNTIME vs CODING-TIME

### RUNTIME (in the app)
| Component | Location | What it does |
|-----------|----------|-------------|
| Graph-CAG Pipeline | `ai-service/api/services/graph_cag/` | LangGraph StateGraph: input → KG expand → diagnose → retrieve → generate → TTS |
| ModelGateway | `ai-service/api/services/model_gateway.py` | Lazy-loads AI models (Qwen, Whisper, Piper, HuBERT, Gemini) |
| KG Service V3 | `ai-service/api/services/kg_service_v3.py` | KuzuDB knowledge graph (grammar/vocab concepts) |
| MCP HTTP Server | `ai-service/api/mcp/` | JSON-RPC 2.0 tools exposed via FastAPI (analyze_text, assess_level, etc.) |
| Backend REST API | `backend-service/app/` | Users, books, lessons, progress, Firebase auth |
| Flutter App | `flutter-app/lib/` | UI screens, providers, API clients |

### CODING-TIME (for AI coding assistants)
| Component | Location | What it does |
|-----------|----------|-------------|
| MCP stdio Server | `mcp-server/` | IDE integration (Copilot/Cursor) — most handlers are placeholders |
| Agent Skills | `agent-skills/` | Best-practice rules compiled into AGENTS.md — zero runtime code |
| This file | `.github/copilot-instructions.md` | Instructions for Copilot agents |

## Coding Conventions

## App I18N Workflow
- For Flutter app UI work, use `flutter-app/assets/i18n/en.json` as the source of truth for key shape and wording.
- Keep all 7 locale files aligned with English: `en`, `vi`, `ja`, `ko`, `zh`, `fr`, `es`.
- Never add new user-facing strings as hardcoded literals when a reusable i18n key is appropriate.
- When translations are not ready for a locale, keep the English fallback string in that locale file instead of leaving the key missing.
- Follow the detailed operating guide in `docs/i18n-global-copilot-guide.md` when touching app text, auth flows, profile, settings, onboarding, and other user-facing Flutter screens.

### Python (backend-service, ai-service)
- Python 3.11+, FastAPI, Pydantic v2
- Use `async/await` everywhere — no blocking I/O
- Type hints on all functions, Pydantic models for request/response
- Logging: `logger = logging.getLogger(__name__)`, never `print()`
- Imports: stdlib → third-party → local, separated by blank lines
- Error handling: raise `HTTPException` in routes, custom exceptions in services

### Dart/Flutter (flutter-app)
- Dart 3.x, Flutter 3.x
- State management: Provider pattern
- API calls via `http` package, grouped in `services/` folder
- Follow `analysis_options.yaml` strictly
- Localization: use `l10n/` ARB files, never hardcode strings

### TypeScript (admin-service)
- React + Vite + TypeScript
- Component files in `src/components/`, pages in `src/pages/`
- **Animations (GSAP Best Practices)**:
  - **React Integration**: Import và sử dụng package `@gsap/react` với hook `useGSAP()`. Hook này tự động xử lý cleanup, tối quan trọng trong React Strict Mode. Luôn define `scope` (`{ scope: containerRef }`) để tránh conflict selector.
  - **Performance**: Ưu tiên animate các thuộc tính transform (`x`, `y`, `scale`, `rotation`) và `autoAlpha` thay vì can thiệp vào các layout props (như `top`, `left`, `width`, `height`).
  - **Sequencing**: Sử dụng `gsap.timeline()` để điều phối các chuỗi animation thay vì dùng thông số `delay` rời rạc.
  - **ScrollTrigger**: Nếu React state làm thay đổi layout/DOM rendering, gọi `ScrollTrigger.refresh()`.
  - **Accessibility**: Luôn kết hợp sử dụng `gsap.matchMedia()` bên trong context/hook để dọn dẹp (cleanup) và hỗ trợ thuộc tính `prefers-reduced-motion` của OS.
  - *Lưu ý*: Toàn bộ Plugins của GSAP (kể cả SplitText, MorphSVG...) hiện đã miễn phí 100% trên package npm public `gsap`, không cần yêu cầu membership hay token.

## Graph-CAG Pipeline Rules
When modifying the AI pipeline:
1. **State**: All data flows through `GraphCAGState` TypedDict in `state.py`
2. **Nodes**: Each node is a pure function `async def node(state) -> dict` in `nodes_v2.py`
3. **Edges**: Routing logic in `edges.py` — conditional edges decide next node
4. **Graph**: Compiled in `graph.py` — add nodes/edges there
5. **KNOWN ISSUE**: `check_cache_hit()` exists in edges.py but is NOT wired — cache fast-path not implemented
6. **KNOWN ISSUE**: `nodes.py` (v1) is dead code — only `nodes_v2.py` is used
7. **Models**: Always go through `ModelGateway`, never import model handlers directly

## MCP Tools Reference

### ai-service MCP (runtime, HTTP at :8001/mcp/)
- `analyze_text` → GraphCAG pipeline
- `get_user_profile` → learning_patterns_repo
- `expand_concepts` → kg_service_v3
- `assess_level` → assessment_service
- `get_due_reviews` → spaced_repetition_service

### mcp-server (coding-time, stdio)
- `chat_with_ai` → Qwen/Gemini handlers (Gemini placeholder)
- `transcribe_audio` → Whisper handler (placeholder)
- `evaluate_grammar` → rules + LLM fallback
- `analyze_pronunciation` → PLACEHOLDER
- `query_knowledge_graph` → PLACEHOLDER
- `generate_exercise` → PLACEHOLDER
- `generate_speech` → Piper handler (placeholder)

## Known Issues to Fix
1. KG database re-seeds on every restart (`kg_service_v3.py` line ~34 does `shutil.rmtree`)
2. `model_gateway` MCP tool exists but not registered in `mcp-server/server.py`
3. MCP resource URIs inconsistent: `learner://profile/` vs `learner_profile://`
4. Architecture doc mentions Qwen3-1.7B but code uses `Qwen3-1.7B`
5. DualStreamOrchestrator coded but WebSocket integration unclear
6. `cag_service.py` (content auto-gen) not connected to GraphCAG pipeline

## Testing
- Backend: `pytest` with fixtures in `tests/`
- AI service: `pytest` + manual Postman collection in `ai-service/postman/`
- Flutter: `flutter test`, coverage in `flutter-app/coverage/`

## Ports
| Service | Port |
|---------|------|
| Backend | 8000 |
| AI Service | 8001 |
| Flutter Web | 8080 |
| Admin | 5173 |
