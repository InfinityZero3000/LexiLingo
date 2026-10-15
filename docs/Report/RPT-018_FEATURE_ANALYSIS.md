# RPT-018 — Phân Tích Tính Năng Toàn Diện LexiLingo

> **Cập nhật:** 2026-09-30 (đối chiếu lại với code) | **Phiên bản dự án:** v0.4.0 (Flutter), v1.0.1 (Backend), v2.1.0 (AI Service)

---

## 1. Tổng Quan Hệ Thống

LexiLingo là nền tảng học tiếng Anh enterprise-grade, tích hợp AI và machine learning để cung cấp **trải nghiệm học cá nhân hóa và thích ứng**. Hệ thống sử dụng kiến trúc microservices với 3 service chính: Backend, AI Service và Flutter App.

---

## Trạng Thái Triển Khai — Bảng Tra Nhanh

> Đối chiếu trực tiếp với source code ngày **2026-10-01**. Các mục ⚠️/❌ nêu rõ
> thiếu gì, không chỉ gắn nhãn.
>
> ✅ **Đủ** — backend + client + wiring hoàn chỉnh, có đường dùng thật
> ⚠️ **Một phần** — chạy được nhưng thiếu một mảnh, hoặc đang tắt bằng feature flag
> ❌ **Chưa** — không có, hoặc có code nhưng không ai gọi

### A. Learning Core

| Hệ thống | TT | Chức năng | Code / Endpoint |
|---|---|---|---|
| Authentication | ✅ | Email, Google, Facebook, reset password, verify email, logout, admin OTP | `routes/auth.py` (15 endpoint) |
| Course → Unit → Lesson | ✅ | CRUD, publish gate, enrol, roadmap | `routes/courses.py`, `routes/admin_courses.py` (37 endpoint) |
| Learning session | ✅ | Start/content/submit answer/complete, chấm từng câu, 20+ ui_type bài tập | `routes/learning.py` |
| Vocabulary + flashcard | ✅ | Thư viện cá nhân, due queue, quiz 2 chiều, word-of-day, quick-save | `routes/vocabulary.py` (17 endpoint) |
| Lịch ôn tập (delta-rule + FSRS) | ⚠️ | Mastery + ngày ôn kế tiếp. **Kênh observation từ chat đang tắt** (`LEARNER_STATE_ENABLED=false`) | `services/learner_state.py`, `routes/learner_state.py` |
| Proficiency CEFR | ✅ | 6 kỹ năng, EMA từng bài, confidence, promotion gate, exam-gated | `routes/proficiency.py`, `services/proficiency_service.py` |
| Placement test | ✅ | Đề xếp trình, submit → gán level | `/proficiency/placement-test` |
| Mistake notebook | ✅ | Ghi lỗi từ lesson/quiz/chat, ôn lại | `routes/mistakes.py`, `features/mistakes/` |
| IELTS | ✅ | Tests → sitting → result, AI chấm Writing/Speaking, admin quản đề | `routes/ielts.py`, `routes/admin_ielts.py`, ai-service `/internal/ielts` |
| Practice Lab | ⚠️ | Hub luyện theo kỹ năng yếu. Thẻ Writing khoá sau `PremiumGate` | `features/practice/` |

### B. Gamification

| Hệ thống | TT | Chức năng | Code / Endpoint |
|---|---|---|---|
| XP | ✅ | **Một endpoint duy nhất** `POST /xp/award`: cap theo source, cap 500/ngày, dedup `source_id`, ghi `XPTransaction` | `routes/xp.py`, `services/xp_service.py` |
| Kế toán XP | ✅ | `record_daily_activity` cập nhật *cả* `DailyActivity` hôm nay và `LeaderboardEntry` tuần | `services/streak_service.py` |
| Daily quest | ✅ | 16 template, rút 4–5/ngày, **đúng 1 quest nội dung**, claim có dedup, bonus hoàn thành hết | `routes/challenges.py` |
| Quest nội dung | ✅ | 5 quest: xem video, nghe podcast, **đọc** (gộp sách + tin tức) theo **phút**; quiz tin tức, quiz chương sách theo **lượt** | `CONTENT_QUEST_SOURCES` |
| Theo dõi giải trí | ✅ | Tab **Content** trong Progress: sessions/phút/XP/lần cuối từng nguồn. Cả 4 nguồn đều đo phút | `GET /xp/content-activity`, `content_activity_tab.dart` |
| Streak | ✅ | Chuỗi ngày, freeze item, previous_streak khi mất | `services/streak_service.py` |
| Wallet / Shop / Inventory | ✅ | Gem, mua, dùng item, boost XP đang hoạt động | `routes/gamification.py` |
| Leaderboard + league | ✅ | Xếp hạng tuần theo league, vị trí của tôi | `routes/gamification.py`, `crud/leaderboard.py` |
| Achievements | ✅ | Badge theo điều kiện, auto-check sau mỗi hoạt động | `services/achievement_checker_service.py` |
| Social | ✅ | Follow/unfollow, feed, gợi ý bạn, người quanh đây | `routes/gamification.py` (prefix `/gamification`, **không có** `/social`) |
| Referral | ✅ | Sinh mã, claim qua deep link | `routes/referral.py` |
| Premium / Entitlements | ⚠️ | Server tự xác thực qua RevenueCat, có `require_premium`. **Chưa gate route nào** — xem §2.9 | `routes/entitlements.py`, `core/dependencies.py` |

### C. Nội dung & giải trí

| Hệ thống | TT | Chức năng | Code / Endpoint |
|---|---|---|---|
| News | ✅ | Danh sách theo CEFR/chủ đề, full content, quiz có chấm → XP + skill + mistake, **thời gian đọc** (chunk 5 phút) | `routes/news.py`, `features/news/` |
| Books | ✅ | Curated theo CEFR, search Gutendex/OpenLibrary, reader, quiz chương, milestone đọc, **thời gian đọc** (chunk 5 phút) | `routes/books.py`, `features/books/` |
| Podcast | ✅ | Explore, player background, XP + **phút đã nghe** ở mốc 80% | `routes/podcasts.py`, `features/podcast/` |
| YouTube | ✅ | Explore, player, caption, dịch, quick-save từ vựng, XP + **phút xem theo chunk 5 phút** | `routes/youtube.py`, `features/youtube/` |
| Games | ✅ | 6 mini-game, session server-side, chống gian lận thời lượng, feed cả 2 engine | `routes/games.py` |
| Content agent | ⚠️ | Sinh course→unit→lesson có bài tập bằng LLM. `CONTENT_AGENT_ENABLED=false` | `services/content_agent_apply.py` |
| Content ETL | ⚠️ | OEWN/CMUdict/Tatoeba… chỉ sinh **từ vựng/phát âm**, không sinh bài học. `CONTENT_ETL_ENABLED=false` | ai-service `services/content_etl/` |

### D. AI & Voice

| Hệ thống | TT | Chức năng | Code / Endpoint |
|---|---|---|---|
| Lexi Chat (TRACE-CAG) | ✅ | KuzuDB KG + Redis CAG + LangGraph, multi-hop, learner card cá nhân hoá | ai-service `services/trace_cag/`, `routes/lexi_chat.py` |
| Topic Chat | ✅ | Hội thoại theo chủ đề, 12 endpoint | ai-service `routes/topic_chat.py` |
| STT | ✅ | Whisper, WebSocket streaming | ai-service `routes/stt.py` |
| TTS | ✅ | Piper/gTTS | ai-service `routes/tts.py` |
| Pronunciation | ✅ | HuBERT cấp phoneme, feed skill `speaking` | ai-service `routes/pronunciation.py` |
| Duplex voice | ⚠️ | Ticket + readiness + quota đầy đủ. `VOICE_DUPLEX_ENABLED=false` | ai-service `routes/voice.py` |
| Translate | ✅ | Dịch từ/câu, cache | ai-service `routes/translate.py` |
| Recommendations / Ranking agent | ✅ | Gợi ý nội dung, insight xếp hạng | `routes/recommendations.py`, `routes/ranking_agent.py` |
| Notification agent | ✅ | Sinh nội dung thông báo bằng LLM | ai-service `routes/notification_agent.py` |

### E. Người dùng & vận hành

| Hệ thống | TT | Chức năng | Code / Endpoint |
|---|---|---|---|
| Profile / Settings | ✅ | Hồ sơ, đổi mật khẩu, ngôn ngữ, theme, daily goal | `routes/users.py`, `features/user/` |
| Notifications (FCM) | ✅ | Device token, danh sách, đánh dấu đã đọc | `routes/notifications.py`, `routes/devices.py` |
| Reminders | ❌ | Có API + Celery worker/beat, nhưng `REMINDERS_ENABLED=false` → **2 container chạy không làm gì** | `routes/reminders.py`, `tasks/reminders.py` |
| Offline sync | ✅ | Xem cache, queue chờ gửi, xoá cache hết hạn | `features/offline/` |
| Admin dashboard | ✅ | 29 trang: course/lesson/unit, vocab, IELTS, shop, user, RBAC, monitoring, AI quality… | `admin-service/` |
| Analytics / RBAC / User mgmt | ✅ | Số liệu học tập, phân quyền, quản lý người dùng nâng cao | `routes/analytics.py`, `routes/rbac.py`, `routes/user_management.py` |
| AI audit | ✅ | Log quyết định AI, trang AI Quality | `routes/ai_audit.py` |
| Banner / quảng cáo | ❌ | Đã gỡ trang WIP khỏi admin nav (2026-10-01). Không có backend | — |

### Feature flag mặc định **TẮT** — kiểm tra `.env.production` trước khi tin là đang chạy

`LEARNER_STATE_ENABLED` · `CONTENT_AGENT_ENABLED` · `REMINDERS_ENABLED` ·
`VOICE_DUPLEX_ENABLED` · `CONTENT_ETL_ENABLED` · `TRACE_CAG_EXTERNAL_ENABLED` ·
`OLLAMA_ENABLED`

**File `.env.production.example` không phải bằng chứng** — nó từng có giá trị
đúng trong khi `.env.production` thật thiếu hẳn dòng đó, khiến kênh chat→skill
trả 404 trong production mà không log gì.

---

## 2. Danh Sách Tính Năng Chính

### 2.1 🤖 AI & Machine Learning Features

| Feature | Mô tả | Vị trí |
|---------|--------|--------|
| **TRACECAG Pipeline** | Graph + Cache-Augmented Generation qua LangGraph StateGraph | `ai-service/api/services/trace_cag/` |
| **Model Gateway** | Quản lý vòng đời tất cả AI models với lazy loading | `ai-service/api/services/model_gateway.py` |
| **CEFR Assessment** | Đánh giá trình độ tự động từ A1 đến C2 | `backend-service/app/services/proficiency_service.py` |
| **Delta-rule + FSRS** | Mastery theo delta rule, lịch ôn theo FSRS (`ALGORITHM_VERSION = delta-fsrs-v3`). **Không phải SM-2, không phải BKT** — cột SM-2 trên `UserVocabulary` đã đóng băng | `backend-service/app/services/learner_state.py` |
| **HuBERT Pronunciation** | Phân tích phát âm cấp phoneme với Facebook HuBERT-large | `ai-service/api/services/hubert_service.py` |
| **Knowledge Graph (KuzuDB)** | Đồ thị tri thức curriculum với mastery tracking | `ai-service/api/services/kg_service_v3.py` |
| **Dual-Stream Voice** | STT → Thinking → TTS đồng thời với interruption handling. **Gated sau `VOICE_DUPLEX_ENABLED` (mặc định false)** | `ai-service/api/routes/stt.py` + `voice.py` |
| **Content Auto-Generation** | AI tự tạo bài tập thích ứng với profil người học | `ai-service/api/services/trace_cag/nodes_v2.py` |

### 2.2 📚 Learning Features

| Feature | Mô tả | Backend Route |
|---------|--------|--------------|
| **Course System** | Khóa học có phân cấp (category → course → lesson) | `/api/v1/courses/` |
| **Learning Sessions** | Phiên học với tracking thời gian và kết quả | `/api/v1/learning/` |
| **Progress Tracking** | Theo dõi tiến độ học, streak, daily activity | `/api/v1/progress/` |
| **Vocabulary Library** | Thư viện từ vựng cá nhân với flashcard | `/api/v1/vocabulary/` |
| **Daily Challenges** | Thử thách hàng ngày với phần thưởng | `/api/v1/challenges/` |
| **Proficiency Assessment** | Kiểm tra trình độ CEFR multi-dimensional | `/api/v1/proficiency/` |

### 2.3 🎮 Gamification Features

| Feature | Mô tả | Backend Route |
|---------|--------|--------------|
| **XP System** | Hệ thống điểm kinh nghiệm phân cấp | `/api/v1/xp/` |
| **Streak System** | Chuỗi ngày học liên tiếp | `progress` module |
| **Achievement Badges** | Huy hiệu thành tích với điều kiện đa dạng | `backend/services/__init__.py` |
| **Leaderboard** | Bảng xếp hạng người dùng | `gamification` module |
| **English Games** | Mini-game học tiếng Anh (word puzzles, etc.) | `/api/v1/games/` |
| **Gems & Rewards** | Hệ thống gem và phần thưởng | `gamification` module |
| **Items/Power-ups** | Vật phẩm tăng sức mạnh học tập | `backend/services/item_effects_service.py` |
| **Daily Quest** | 16 template, rút 4–5/ngày theo seed `(ngày, user)`; **đúng 1 quest nội dung** mỗi ngày | `/api/v1/challenges/daily` |
| **Content Quest** | Xem video / nghe podcast / **đọc** tính theo **phút**; quiz tin tức / quiz chương sách tính theo **lượt** | `CONTENT_QUEST_SOURCES` trong `routes/challenges.py` |
| **Theo dõi giải trí** | sessions / phút / XP / lần cuối hoạt động theo từng nguồn | `/api/v1/xp/content-activity` |

### 2.4 📰 Content Features

| Feature | Mô tả | Backend Route | Flutter Screen |
|---------|--------|--------------|----------------|
| **YouTube Videos** | Xem video + caption/translate + quick-save từ vựng. **Không có quiz**, nhưng từ 2026-10-01 ghi nhận **phút xem** (chunk 5 phút) → XP + quest | `/api/v1/youtube/` | `youtube_explore_screen.dart`, `youtube_player_screen.dart` |
| **News Reading** | Đọc tin tức với quiz kiểm tra hiểu bài | `/api/v1/news/` | `news_list_screen.dart`, `news_quiz_screen.dart` |
| **Podcast Player** | Nghe podcast background playback; XP + **phút đã nghe** ở mốc 80% | `/api/v1/podcasts/` | `podcast_player_screen.dart` |
| **Book Library** | Thư viện sách điện tử | `/api/v1/books/` | `book_library_screen.dart` |

### 2.5 🗣️ Voice & Communication Features

| Feature | Mô tả | Route |
|---------|--------|-------|
| **AI Tutor Chat** | Trò chuyện với gia sư AI cơ bản | `/api/v1/chat/` |
| **Lexi Chat (Advanced)** | Chat nâng cao với TRACECAG pipeline, voice support | `/api/v1/lexi/` |
| **Topic Chat** | Chat theo chủ đề với context đặc biệt | `/api/v1/topics/` |
| **Speech-to-Text** | Chuyển giọng nói thành văn bản (Whisper) | `/api/v1/stt/` |
| **Text-to-Speech** | Tạo âm thanh từ văn bản (Piper/gTTS) | `/api/v1/tts/` |
| **Voice WebSocket** | Luồng voice thời gian thực (`/api/v1/voice/stream`, cần ticket) | `voice.py` → `stt.py:stream_audio` |

### 2.6 👥 Social & User Features

| Feature | Mô tả | Route |
|---------|--------|-------|
| **Authentication** | JWT + Firebase (Google, Facebook, Email) | `/api/v1/auth/` |
| **User Profile** | Quản lý hồ sơ cá nhân | `/api/v1/users/` |
| **Social Features** | Follow, feed, gợi ý bạn, tìm người quanh đây | `/api/v1/gamification/` (không có route `/social`) |
| **Notifications** | Push notification qua Firebase FCM | `devices/notifications` |
| **Multi-language UI** | Giao diện đa ngôn ngữ (easy_localization) | `core/l10n/` |

### 2.7 🔧 Admin & Analytics Features

| Feature | Mô tả |
|---------|--------|
| **Admin Dashboard** | React/Vite dashboard quản lý nội dung | `admin-service/` |
| **Analytics API** | Số liệu học tập và hành vi người dùng | `/api/v1/analytics/` |
| **RBAC System** | Phân quyền dựa trên vai trò | `/api/v1/rbac/` |
| **User Management** | Quản lý người dùng nâng cao | `/api/v1/user-management/` |
| **AI Audit** | Kiểm tra và log AI decisions | `/api/v1/ai-audit/` |

---

### 2.8 ⚠️ Feature có trong code nhưng thiếu ở bản báo cáo này

Bảng trên viết 2026-04-24 và đã trôi so với code. Các feature sau đã tồn tại:

| Feature | Backend Route | Ghi chú |
|---------|--------------|---------|
| **IELTS** (test → sitting → result, AI grading Writing/Speaking) | `/api/v1/ielts/`, `/api/v1/admin/ielts/` | ai-service: `/api/v1/internal/ielts` |
| **Mistake Notebook** | `/api/v1/mistakes/` | |
| **Referral** | `/api/v1/referral/` | |
| **Entitlements / Premium** | `/api/v1/entitlements/` | RevenueCat; enforce bằng `require_premium` |
| **Recommendations** | `/api/v1/recommendations/` | |
| **Ranking Agent** | `/api/v1/ranking-agent/` | `RANKING_AGENT_ENABLED` mặc định true |
| **Notification Campaign** | `/api/v1/notification-campaign/` | |
| **Reminders** | `/api/v1/reminders/` | `REMINDERS_ENABLED` mặc định **false** |
| **Learner State** (delta-rule + FSRS) | `/api/v1/internal/learner-state/` | `LEARNER_STATE_ENABLED` mặc định **false** |
| **Concepts** | `/api/v1/concepts/` | |
| **Learner Card** | `/api/v1/internal/learner-card/` | Lexi trả lời câu hỏi cá nhân |
| **Product Events** | `/api/v1/product-events/` | |
| **Content Agent** | `/api/v1/content-agent/` | `CONTENT_AGENT_ENABLED` mặc định **false** |

Flutter-only: Practice Lab, Offline Sync Center, Paywall, Level.

**Feature flag mặc định OFF** — kiểm tra `.env.production` trước khi tin là feature đang chạy:
`LEARNER_STATE_ENABLED`, `CONTENT_AGENT_ENABLED`, `REMINDERS_ENABLED`,
`VOICE_DUPLEX_ENABLED`, `CONTENT_ETL_ENABLED`, `TRACE_CAG_EXTERNAL_ENABLED`, `OLLAMA_ENABLED`.

### 2.9 Premium — phạm vi thực tế

Entitlement do server xác thực (`EntitlementService`, nguồn sự thật là RevenueCat).
`require_premium` (`app/core/dependencies.py`) là boundary để gate route; `PremiumGate`
phía Flutter đọc `/entitlements/me`, không đọc SDK local.

**Hiện chưa có route nào được gate**: surface premium duy nhất trong app là thẻ
"Writing" ở Practice Lab, mà nó điều hướng sang Lexi chat — vốn miễn phí ở tab khác.
Gate route Lexi sẽ lấy mất tính năng của người dùng free. Cần chốt nghiệp vụ
"premium bán cái gì" trước khi gắn `require_premium` vào đâu đó.

## 3. Phân Tích Theo Provider Feature Phases

Flutter app được phát triển theo 6 phases rõ ràng:

```
Phase 1: YouTube Video Integration    → YouTubeProvider
Phase 2: News Reading                 → NewsProvider
Phase 3: English Games + XP System   → GamesProvider
Phase 4: Podcast (Background Audio)  → PodcastProvider
Phase 5: Book Reading                 → BookProvider
Phase 6: Lexi Chat (Story Adventure) → LexiChatProvider
```

---

## 4. Key Highlights — Tính Năng Liên Biệt

### 4.1 TRACECAG Pipeline (Đặc sắc nhất)
Không giống RAG truyền thống, TRACECAG kết hợp:
- **KuzuDB Knowledge Graph**: Đồ thị curriculum với quan hệ prerequisite
- **Redis Cache-Augmented Generation (CAG)**: Cache context người học, không cần re-retrieve
- **LangGraph StateGraph**: Orchestration đa bước stateful với conditional routing

### 4.2 CEFR Assessment (6 chiều đánh giá)
Thuật toán đánh giá trình độ tích hợp:
- Listening, Speaking, Reading, Writing mỗi kỹ năng 20%; Vocabulary 10%, Grammar 10% (`SKILL_WEIGHTS` trong `proficiency_service.py`) — vocabulary và grammar là *resource* của CEFR, không phải trụ cột
- Chống "XP grinding" – không thể lên cấp chỉ bằng số lượng bài
- EMA (Exponential Moving Average) cho điểm kỹ năng

### 4.3 Delta-rule + FSRS (không phải SM-2)
`ALGORITHM_VERSION = "delta-fsrs-v3"`:
- Retrievability, interval và spacing bonus theo FSRS
- Mastery đổi theo **delta rule** — không có transition probability, không slip/guess, **không phải Bayesian**
- Nhiễu đoán mò xử lý bằng `FORMAT_CONFIDENCE` (đáp án 4 lựa chọn đúng có trọng số thấp hơn đáp án tự gõ)
- Cột SM-2 cũ trên `UserVocabulary` (`ease_factor`, `interval`, `fsrs_*`) đã đóng băng, chỉ còn giá trị lịch sử

---

### 4.4 Daily Quest & ghi nhận nội dung giải trí

Bốn mục giải trí (sách, podcast, video, tin tức) trước đây **kiếm XP nhưng không
tính vào bất cứ đâu** — một ngày đọc sách trông "rảnh" cạnh một bài học. Hệ thống
quest giải quyết việc đó mà **không thêm bảng mới**:

- Nguồn dữ liệu là `XPTransaction` — dòng ghi immutable mà mỗi lần award đã tạo,
  vốn có `source` / `source_id` / `created_at` và **dedup theo `source_id`**.
  Thay đổi schema duy nhất là cột `duration_seconds` (migration `b6c1d9e4f207`).
- **Đúng 1 quest nội dung mỗi ngày.** `claim_daily_bonus` yêu cầu hoàn thành
  *tất cả* quest, nên nếu rút ngẫu nhiên từ một pool thì có ngày phần lớn là quest
  nội dung và người chỉ muốn học sẽ mất bonus oan.
- **Tin tức và sách được tính theo *cả hai*:** lượt quiz (hiểu bài) và thời gian
  đọc (`source_detail = "reading_time"`). Chính `source_detail` giữ cho hai quest
  đọc cùng một nguồn mà không ăn award của nhau — một quyển sách sinh award cho
  thời gian đọc, cho milestone *và* cho quiz chương.
- **"Màn hình mở" không phải "đang đọc".** `ContentTimeTracker`
  (`core/services/`) chỉ cộng giây khi app ở foreground **và** vừa có thao tác
  (cuộn / lật trang) trong `idleAfter`. Mặc định 2 phút: đây là **núm hiệu chỉnh
  theo tốc độ đọc**, không phải giới hạn kỹ thuật — người học A2 có thể ở một
  trang hơn một phút mà không cuộn, nên cửa sổ quá ngắn sẽ âm thầm tính thiếu
  đúng những người đọc chậm nhất; quá dài thì điện thoại để ngửa cũng ra XP.
- **Chunk dở dang bị bỏ, không làm tròn lên** — người học sẽ không được trả cho
  một chunk họ chưa bỏ ra, và lần đọc sau tự đếm lại từ đầu.
- **Cả ba surface báo theo chunk 5 phút** qua cùng `ContentTimeTracker`
  (`source_id = "<prefix>:<chunk>"`). Một award cho cả video/bài thì không thể
  cộng dồn vì `/xp/award` dedup theo `source_id` và từ chối lần gọi thứ hai.
  Video khác hai cái kia ở chỗ *đo bằng gì*: nó nạp **mức tăng của position được
  clamp trong một tick** thay vì nhịp đồng hồ, nên kéo scrubber về sau không
  được tính.

**`duration_seconds` là lời khai của client, không phải phép đo.** Mọi tổng suy ra
từ nó cap mỗi award ở `MAX_STUDY_MINUTES_PER_AWARD` (60 phút) qua
`capped_duration_seconds()` — dùng `CASE` chứ không dùng `least()`, vì SQLite
(môi trường test) không có `least` còn production là PostgreSQL. Cộng thêm
`XP_SOURCE_CAPS` theo từng nguồn và cap 500 XP/ngày.

---

## 5. Bản Đồ Tính Năng → Service

```
Flutter App
├── Auth (Google/Facebook/Email) → Backend /auth
├── Courses/Learning           → Backend /courses, /learning
├── Vocabulary + Flashcard     → Backend /vocabulary
├── Progress/Streak            → Backend /progress
├── Gamification/Achievements  → Backend /gamification, /xp
├── AI Chat (Basic)            → AI Service /chat
├── Lexi Chat (Advanced)       → AI Service /lexi
├── Voice (STT/TTS/Realtime)   → AI Service /stt, /tts, /ws
├── YouTube/News/Podcast/Books → Backend content APIs
└── Social/Notifications       → Backend /social, /devices
```

---

*Tham khảo: [RPT-001](RPT-001_REPORT_INDEX.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md)*
