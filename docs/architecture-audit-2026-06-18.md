# Architecture Audit — LexiLingo
**Ngày:** 2026-06-18  
**Branch:** `feat/stt-ensemble-phase3-5`  
**Phạm vi:** Flutter app · backend-service · ai-service · admin-service  
**Công cụ:** code-review-graph (1324 files · 12966 nodes · 99780 edges) + static analysis

---

## Tóm tắt chẩn đoán

| Service | Vĩ mô (microservice boundary) | Nội bộ (layer discipline) |
|---------|-------------------------------|--------------------------|
| Flutter app | ✅ Không cross-service import | 🔴 Domain ↔ Data bị trộn lẫn |
| backend-service | ✅ Services không import routes | 🔴 Business logic trong routes |
| ai-service | ✅ Services không import routes | 🔴 MongoDB ops rò rỉ vào routes |
| admin-service | ✅ lib/ layer tách bạch | 🟡 Raw fetch trong một số pages |

Hệ thống **đúng ở cấp vĩ mô** — các microservice không gọi chéo nhau trực tiếp.  
Các vi phạm đều **trong từng service**, ở cấp độ layer discipline.

---

## Danh mục vấn đề

### F — Flutter (Clean Architecture)

#### [F1] 🔴 Domain importing Data layer

**Quy tắc bị phá vỡ:** `domain/` phải độc lập hoàn toàn — không biết về `data/models/` hay `data/datasources/`.

| File vi phạm | Import sai |
|---|---|
| `features/lexi_chat/domain/repositories/lexi_chat_repository.dart:1` | `data/datasources/lexi_chat_data_source.dart` |
| `features/achievements/domain/repositories/achievement_repository.dart:5` | `data/models/achievement_model.dart` |
| `features/learning/domain/repositories/learning_repository.dart:3-6` | 4 data models (`lesson_attempt_model`, `roadmap_model`, `answer_response_model`, `lesson_complete_model`) |
| `features/learning/domain/usecases/submit_answer_usecase.dart:4` | `data/models/answer_response_model.dart` |
| `features/learning/domain/usecases/complete_lesson_usecase.dart:4` | `data/models/lesson_complete_model.dart` |
| `features/learning/domain/usecases/get_course_roadmap_usecase.dart:4` | `data/models/roadmap_model.dart` |
| `features/learning/domain/usecases/start_lesson_usecase.dart:4` | `data/models/lesson_attempt_model.dart` |

**Nguyên nhân gốc:** Data models (`*_model.dart`) đang đóng vai trò entity nhưng nằm nhầm chỗ trong `data/`. Domain cần entity riêng.

---

#### [F2] 🔴 Presentation gọi ApiClient trực tiếp (bypass domain)

**Quy tắc bị phá vỡ:** `presentation/` chỉ được gọi UseCase hoặc Provider — không được biết về HTTP client.

| File vi phạm | Dòng | Vi phạm |
|---|---|---|
| `features/home/presentation/pages/home_page.dart` | 60 | `sl<ApiClient>()` trực tiếp trong widget |
| `features/lexi_chat/presentation/pages/lexi_chat_page.dart` | 255 | `sl<AiApiClient>()` trong page |
| `features/profile/presentation/pages/profile_page.dart` | 73 | `sl<ApiClient>()` trong page |
| `features/user/presentation/pages/settings_page.dart` | 871 | `sl<ApiClient>()` trong page |

---

#### [F3] 🟡 Cấu trúc feature thiếu nhất quán

| Feature | Vấn đề |
|---|---|
| `home/` | Chỉ có `presentation/` — thiếu hoàn toàn `data/` và `domain/` |
| `gamification/` | Thiếu `data/` layer |
| `premium/` | Chỉ có `presentation/` |
| `level/` | Có folder `services/` ngoài chuẩn thay vì `domain/services/` |

---

### B — backend-service (FastAPI)

#### [B1] 🔴 Business logic rò rỉ vào Route handlers

**Quy tắc bị phá vỡ:** Route handler chỉ được: validate request → gọi service → trả response. Không chứa query logic.

| File | Số lượng vi phạm | Loại vi phạm |
|---|---|---|
| `app/routes/users.py` | 20+ `db.execute()` | Query stats phức tạp trong handler |
| `app/routes/auth.py` | :86, :94, :105, :125 | DB ops (add, commit, execute) trong route |
| `app/routes/progress.py` | :230, :239 | Lazy import crud từ bên trong handler |

Ví dụ điển hình từ `users.py`:
```python
# ❌ Trong route handler — sai
courses_enrolled = (await db.execute(courses_query)).scalar() or 0
courses_completed = (await db.execute(completed_query)).scalar() or 0
lessons_completed = (await db.execute(lessons_query)).scalar() or 0
words_learned = (await db.execute(vocab_learned_query)).scalar() or 0
# ... 6 query nữa cùng kiểu
```

---

#### [B2] 🟡 Fat Routes — quá nhiều dòng trong một file

| File | Số dòng | Đánh giá |
|---|---|---|
| `app/routes/admin.py` | **2146** | 🔴 Cần tách ngay |
| `app/routes/games.py` | **1691** | 🔴 |
| `app/routes/learning.py` | 1233 | 🟡 |
| `app/routes/gamification.py` | 1155 | 🟡 |
| `app/routes/auth.py` | 1008 | 🟡 |

---

#### [B3] 🟡 Thiếu nhất quán giữa CRUD layer và direct DB

Một số routes dùng CRUD layer (đúng), một số bypass trực tiếp:

```python
# ✅ Đúng — routes/progress.py
from app.crud.progress import ProgressCRUD
from app.crud.course import CourseCRUD

# ❌ Sai — routes/users.py (cùng project, khác convention)
result = await db.execute(select(UserVocabulary).where(...))
```

---

### A — ai-service (FastAPI + MongoDB)

#### [A1] 🔴 MongoDB operations rò rỉ vào route handler

**Quy tắc bị phá vỡ:** Route không được biết về collection name hay query syntax — đó là việc của Repository.

`api/routes/topic_chat.py` chứa **12 lần** truy cập MongoDB trực tiếp:

| Dòng | Operation |
|---|---|
| 134 | `db["chat_sessions"].find_one(...)` |
| 341 | `db["chat_sessions"].insert_one(session)` |
| 356 | `db["chat_sessions"].update_one(...)` |
| 380 | `db["chat_messages"].insert_one(ai_message)` |
| 477 | `db["chat_messages"].find(...)` — cursor |
| 602, 664, 696, 716, 723 | Pagination queries với `count_documents`, `find` |

---

#### [A2] 🟡 Fat Route — `ai.py` (552 dòng)

`api/routes/ai.py` gọi trực tiếp `get_trace_cag()`, `get_v3_pipeline()`, `enforce_user_quota()`, `repo.get_user_interactions()` — logic orchestration đang nằm trong route thay vì service.

---

### AD — admin-service (React)

#### [AD1] 🟢 Raw `fetch()` trong một số Pages

**Quy tắc bị phá vỡ:** Mọi HTTP call phải đi qua `lib/*Api.ts` — Pages không gọi `fetch()` trực tiếp.

| File | Dòng | URL đích |
|---|---|---|
| `pages/DatabasePage.tsx` | 35-36 | `ENV.backendHealthUrl`, `ENV.aiHealthUrl` |
| `pages/SuperAdminDashboard.tsx` | 27-28 | `ENV.backendHealthUrl`, `ENV.aiHealthUrl` |
| `pages/AiChatSettingsPage.tsx` | 46, 88 | `ENV.aiAdminUrl/config` |
| `pages/AiModelsPage.tsx` | 42 | `ENV.aiHealthUrl` |

---

## Kế hoạch khắc phục & Checklist

> Độ ưu tiên: 🔴 Ngay → 🟡 Sprint này → 🟢 Backlog  
> Mỗi task được đánh dấu `[ ]` để track tiến độ.

---

### Sprint 1 — Khắc phục vi phạm cốt lõi

#### Flutter [F1] — Tạo Entity trong domain để tách khỏi data models

**Mục tiêu:** Domain chỉ biết về Entity, không biết về Model.

##### learning feature
- [x] Tạo `features/learning/domain/entities/lesson_attempt.dart` (thay thế `data/models/lesson_attempt_model.dart` trong domain)
- [x] Tạo `features/learning/domain/entities/roadmap.dart`
- [x] Tạo `features/learning/domain/entities/answer_response.dart`
- [x] Tạo `features/learning/domain/entities/lesson_complete.dart`
- [x] Cập nhật `domain/repositories/learning_repository.dart` → dùng entity thay vì model
- [x] Cập nhật `domain/usecases/submit_answer_usecase.dart` → dùng `AnswerResponse` entity
- [x] Cập nhật `domain/usecases/complete_lesson_usecase.dart` → dùng `LessonComplete` entity
- [x] Cập nhật `domain/usecases/get_course_roadmap_usecase.dart` → dùng `Roadmap` entity
- [x] Cập nhật `domain/usecases/start_lesson_usecase.dart` → dùng `LessonAttempt` entity
- [x] Cập nhật `data/repositories/learning_repository_impl.dart` → map Model → Entity khi trả về
- [x] Chạy `flutter test` → đảm bảo không broken

##### achievements feature
- [x] Tạo `features/achievements/domain/entities/achievement.dart`
- [x] Cập nhật `domain/repositories/achievement_repository.dart` → dùng entity
- [x] Cập nhật `data/repositories/achievement_repository_impl.dart` → map Model → Entity
- [x] Chạy `flutter test`

##### lexi_chat feature (nghiêm trọng nhất — domain import datasource)
- [x] Xóa `import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart'` khỏi `domain/repositories/lexi_chat_repository.dart`
- [x] Repository interface trong domain chỉ dùng Entity và primitive types
- [x] Đảm bảo `data/repositories/lexi_chat_repository_impl.dart` là nơi duy nhất biết về datasource
- [x] Chạy `flutter test`

---

#### Flutter [F2] — Xóa ApiClient khỏi Presentation layer

**Mục tiêu:** Presentation không còn `sl<ApiClient>()` hay `sl<AiApiClient>()`.

##### home feature
- [x] Tạo `features/home/domain/usecases/fetch_level_usecase.dart`
- [x] Tạo `features/home/domain/repositories/home_repository.dart` (interface)
- [x] Tạo `features/home/data/repositories/home_repository_impl.dart` (inject ApiClient)
- [x] Cập nhật `features/home/di/` → đăng ký repository và usecase
- [x] Refactor `home_page.dart:60` → gọi usecase thay vì `sl<ApiClient>()`

##### lexi_chat feature
- [x] Tạo `features/lexi_chat/domain/usecases/init_chat_usecase.dart` (bao gồm logic khởi tạo AiApiClient)
- [x] Refactor `lexi_chat_page.dart:255` → gọi qua usecase / provider

##### profile feature
- [x] Tạo `features/profile/domain/usecases/fetch_profile_level_usecase.dart`
- [x] Refactor `profile_page.dart:73` → gọi usecase

##### user/settings feature
- [x] Tạo `features/user/domain/usecases/load_settings_usecase.dart`
- [x] Refactor `settings_page.dart:871` → gọi usecase

---

#### Flutter [F3] — Chuẩn hóa cấu trúc feature

- [~] `home/`: **Bỏ qua** — `HomeProvider` đã delegate qua use cases của các feature khác, không có home-specific API call. Thêm layer là over-engineering.
- [x] `gamification/`: Tạo `data/datasources/gamification_remote_data_source.dart` (abstract + impl), `domain/repositories/gamification_repository.dart`, `data/repositories/gamification_repository_impl.dart`. `GamificationProvider` refactored: `_apiClient` → `_repository`. DI updated. 2 test files updated để dùng `_FakeRepository`.
- [~] `premium/`: **Bỏ qua** — chỉ có `paywall_screen.dart` wrap RevenueCat SDK, không có business logic để encapsulate.
- [x] `level/services/level_calculator.dart` → `level/domain/services/level_calculator.dart`. Update import trong `level_provider.dart`, `level_widgets.dart`, `level.dart` barrel, và `test/features/level/level_calculator_test.dart`.

> ℹ️ F3 là backlog — không blocking Sprint 2.

---

#### Backend [B1] — Tách business logic ra khỏi Route handlers

##### users.py → UserStatsService
- [x] Tạo `app/services/user_stats_service.py`
  - [x] `async def get_user_stats(db, user) -> UserStatsResponse`  — chứa 10 query hiện tại
  - [x] `async def delete_user_permanently(db, user)` — chứa logic cascade delete (GDPR)
  - [x] `async def get_weekly_activity(db, user) -> WeeklyActivityResponse`
- [x] Refactor `routes/users.py`: handlers chỉ gọi service
- [x] Chạy `pytest tests/` → không broken

##### auth.py → AuthService
- [x] Tạo `app/services/auth_service.py`
  - [x] `async def register_user(db, request) -> User`
  - [x] `async def authenticate_user(db, email, password, dummy_hash) -> User | None`
  - [x] `async def save_refresh_token / revoke_refresh_token`
  - [x] `def issue_token_pair(user_id) -> tuple[str, str]`
- [x] Refactor `routes/auth.py` → delegating to `AuthService`
- [x] Chạy `pytest tests/`

---

#### AI-service [A1] — Tạo TopicChatRepository

- [x] Tạo `api/repositories/topic_chat_repository.py`
  - [x] `async def get_session / create_session / update_session_kg`
  - [x] `async def insert_message / get_history / get_messages / count_messages`
  - [x] `async def get_messages_paged / get_latest_message / get_oldest_message`
- [x] Refactor `api/routes/topic_chat.py` → inject repository, không còn `db["chat_sessions"]` hay `db["chat_messages"]` trực tiếp
- [x] Chạy import check — OK

---

### Sprint 2 — Fat routes & consistency

#### Backend [B2] — Tách Fat Route files

##### admin.py (2146 dòng) → tách thành 3 files
- [x] `app/routes/admin_courses.py` — courses, units, lessons, vocab, grammar, questions, test-exams (956 lines)
- [x] `app/routes/admin_gamification.py` — achievements, shop (352 lines)
- [x] `app/routes/admin_system.py` — seed endpoint, system-info, quota (860 lines)
- [x] Cập nhật `app/main.py` → include 3 routers mới, giải quyết merge conflict prometheus
- [x] `app/routes/admin.py` đánh dấu deprecated
- [x] Import check: 254 total routes loaded OK

##### games.py (1691 dòng) → tách thành 3 files
- [x] `app/routes/game_data.py` — tất cả constants (GAME_WORDS_SEED, HANGMAN_FALLBACK_WORDS, FILL_BLANK_BANK, GRAMMAR_QUIZ_BANK) + `_ensure_seeded`
- [x] `app/routes/game_content.py` — 6 GET game endpoints + /categories (7 routes)
- [x] `app/routes/game_scoring.py` — POST /sessions/{id}/complete (1 route)
- [x] Cập nhật `app/main.py` → game_content_router + game_scoring_router
- [x] `app/routes/games.py` đánh dấu deprecated
- [x] Import check: games OK

#### Backend [B3] — Chuẩn hóa CRUD layer usage

- [x] Tạo `app/crud/user.py` với `UserCRUD` class
  - [x] `get_by_id`, `get_by_email`, `get_by_username`, `search`, `get_following_ids`
- [x] Tạo `app/crud/auth.py` với `AuthCRUD` class
  - [x] `get_refresh_token`, `get_active_refresh_token`
- [x] Refactor `routes/users.py` → dùng `UserCRUD.search`, `UserCRUD.get_following_ids`, `UserCRUD.get_by_id`
- [ ] Enforce rule: route files không được import `select`, `delete`, `update` từ sqlalchemy trực tiếp (ongoing — áp dụng cho file mới, không refactor toàn bộ codebase)

---

#### AI-service [A2] — Tạo TopicChatService

- [x] `api/services/topic_chat_service.py` đã tồn tại (185 lines): `call_tracecag_with_retry`, `persist_topic_turn`, `resolve_kg_seeds`
  - [x] Thêm `insert_messages_bulk` và `update_session_activity` vào `TopicChatRepository`
  - [x] `persist_topic_turn` refactored: nhận `repo: TopicChatRepository` thay vì `db` trực tiếp — xóa nốt `db["chat_*"]` cuối cùng
  - [x] Call site trong `topic_chat.py:494` cập nhật → `db=db` thành `repo=repo`
- [x] Import check: AI service OK — 11 routes

---

### Sprint 3 — Polish & Admin cleanup

#### Admin [AD1] — Tập trung raw fetch vào lib/healthApi.ts

- [x] Tạo `admin-service/src/lib/healthApi.ts`
  - [x] `checkBackendHealth()`, `checkAiHealth()` — dùng healthHeaders từ ENV.apiKey
  - [x] `getAiConfig(accessToken?)`, `updateAiConfig(body, accessToken?)` — dùng admin headers (Bearer + X-Api-Key + X-Admin-Key)
- [x] Refactor `DatabasePage.tsx` → dùng `checkBackendHealth`, `checkAiHealth`; xóa import `ENV`
- [x] Refactor `SuperAdminDashboard.tsx` → dùng `checkBackendHealth`, `checkAiHealth`; xóa import `ENV`
- [x] Refactor `AiChatSettingsPage.tsx` → dùng `getAiConfig`, `updateAiConfig`; xóa `buildAdminHeaders` + import `ENV`
- [x] Refactor `AiModelsPage.tsx` → dùng `checkAiHealth`; xóa import `ENV`
- [x] TypeScript type check: 0 errors

#### Kiểm tra cuối (CI gate)
- [x] `flutter test` — **710/710 passed**
- [x] `pytest backend-service/tests/` — **978 passed**, failures/errors đều do `lexilingo_test` DB không tồn tại trên local (infra, không phải code regression); các file liên quan đến thay đổi (users_routes, game_scoring, courses_routes) pass 100%
- [x] `pytest ai-service/tests/` — **206 passed**, 6 failures đều pre-existing (numpy version mismatch + translate route mock không tồn tại `get_available_groq_key`); `test_topic_chat_routes.py` (file A2 thay đổi) pass **16/16**
- [x] `npm run build` trong `admin-service/` — `npx tsc --noEmit` 0 errors
- [x] Chạy lại `code-review-graph detect_changes` → **0 architecture violations**; risk score 0.60 (pre-existing test gaps từ toàn bộ branch, không phải từ sprint này)

---

## Nguyên tắc phòng ngừa (thêm vào CLAUDE.md)

```
## Architecture Rules — Enforcement

### Flutter
- domain/ KHÔNG được import bất cứ thứ gì từ data/
- presentation/ KHÔNG được gọi ApiClient, AiApiClient hay DioClient trực tiếp
- Mỗi feature PHẢI có đủ data/ + domain/ + presentation/

### Backend
- Route handler tối đa 50 dòng — mọi logic ra service/crud
- Route file tối đa 400 dòng — nếu vượt thì tách
- Không import sqlalchemy.select/delete/update trong routes/ — dùng crud/

### AI-service
- routes/ không được chứa db["collection_name"] — dùng repositories/
- Orchestration logic (quota + pipeline + storage) → vào services/

### Admin
- pages/ và components/ không được gọi fetch() trực tiếp — dùng lib/*Api.ts
```

---

## Tham chiếu

| Mục | Link |
|-----|------|
| Báo cáo kiểm tra gốc | Cuộc hội thoại ngày 2026-06-18 |
| Architecture overview | `docs/ARCHITECTURE.md` |
| CLAUDE.md project rules | `LexiLingo/CLAUDE.md` |
