# Kế Hoạch Phát Triển Hệ Thống LexiLingo (Giai đoạn Core - Non AI)

Tài liệu này chi tiết hóa các nhiệm vụ phát triển ứng dụng Mobile (Flutter) và Backend Service song song, tập trung vào các chức năng cốt lõi của một ứng dụng học tiếng Anh (định hướng Duolingo/Elsa style) trước khi tích hợp các tính năng AI nâng cao.

**Mục tiêu:** Hoàn thiện luồng người dùng cơ bản: Đăng nhập -> Chọn khóa học -> Học bài (Từ vựng/Ngữ pháp/Quiz) -> Theo dõi tiến độ.

---

## ✅ Đánh giá nhanh (độ chi tiết & tính khả thi)

Kế hoạch hiện tại đã tốt ở mức “feature list theo phase”, nhưng còn thiếu một số phần “thiết kế triển khai” để đội dev có thể bắt tay code mà không bị mơ hồ:

- **Thiếu chuẩn API/contract**: chưa định nghĩa format lỗi chuẩn, pagination, id/timestamp, versioning, retry policy.
- **Chưa chốt chiến lược Auth**: trong repo hiện tại Flutter đang dùng **Firebase Auth**, trong khi kế hoạch mô tả **JWT + refresh token rotation** (backend-service). Cần quyết định 1 trong 2 hoặc cách “kết hợp” để tránh làm 2 hệ thống song song.
- **Thiếu mô tả dữ liệu Progress/Learning**: “học bài” cần schema rõ cho attempt, score, answer history, mastery… để sau này AI/SRS lấy dữ liệu.
- **Thiếu seam tích hợp AI**: cần xác định rõ “điểm cắm” (AI Gateway/Client, message schema, session id, telemetry) ngay từ Core để sau này thêm AI không phải refactor.

Phần dưới đây bổ sung các mục đó và chỉnh lại cho khớp với cấu trúc codebase hiện tại.

---

## 🧩 Nguyên tắc kiến trúc để dễ tích hợp AI (khuyến nghị áp dụng ngay từ Core)

1) **Tách 3 lớp rõ ràng**
- Flutter: `presentation` (UI/state) → `domain` (usecase/entity) → `data` (datasource/api/local)
- Backend: `routes` (API) → `services` (business) → `models/schemas` (DB + contract)

2) **AI là 1 bounded context riêng**
- Core app KHÔNG phụ thuộc trực tiếp model/LLM.
- Chỉ giao tiếp qua 1 interface (Gateway/Client) + schema ổn định.

3) **Chuẩn hóa “Learning Event” ngay từ đầu**
- Mọi tương tác học (quiz/vocab/grammar/listening…) phát sinh `LearningEvent` và lưu lịch sử.
- AI sau này chỉ cần đọc event + profile để cá nhân hóa.

4) **Idempotency + Retry**
- Các API ghi dữ liệu (submit answer, update progress) có `idempotency_key` để tránh double-submit.

---

## 📦 Chuẩn hóa API Contract (áp dụng cho Backend Service)

### 1) Envelope thống nhất
- **Success**: `{ "data": ..., "meta": {"request_id": "..."} }`
- **Error**: `{ "error": {"code": "AUTH_INVALID", "message": "...", "details": {...}}, "meta": {"request_id": "..."} }`

### 2) Pagination chuẩn
- Query: `?page=1&page_size=20`
- Response meta: `{"page":1,"page_size":20,"total":123}`

### 3) Chuẩn timestamp
- Dùng ISO-8601 UTC: `2026-01-24T10:20:30Z`

### 4) Versioning
- Base path: `/api/v1/...`

## 🛠 Phase 1: Authentication & Secure User Foundation
*Trọng tâm: Bảo mật tối đa, trải nghiệm người dùng mượt mà, quản lý phiên làm việc chặt chẽ.*

### Backend Service (Python/FastAPI)
- [ ] **Infrastructure & Config**
    - [ ] Setup `Alembic` cho database migrations (quản lý version database).
    - [ ] Config `Pydantic Settings` để quản lý biến môi trường (Dev/Prod).
    - [ ] Setup `CORS`, `TrustedHost`, và `RateLimiting` middleware để chống spam.
- [ ] **Chốt chiến lược Auth (chọn 1)**
    - [ ] **Option A (khớp codebase hiện tại)**: Flutter dùng `Firebase Auth` → Backend verify `Firebase ID Token` và map sang `user_id` nội bộ.
    - [ ] **Option B (thuần backend)**: Flutter login/register qua Backend → Backend cấp `access_token`/`refresh_token`.
    - [ ] Nếu cần tích hợp AI-service về sau: thống nhất `Authorization` header và `user_id` xuyên suốt các service.
- [ ] **Database Schema (Advanced Users)**
    - Table `users`: Thêm `is_active`, `is_verified`, `provider` (local, google, facebook).
    - Table `user_devices`: Lưu `fcm_token` (cho Push Notification sau này), `device_id`, `last_login_ip`.
    - Table `refresh_tokens`: Quản lý token xoay vòng (Rotation) để chống trộm token.
- [ ] **API Implementation**
    - `POST /auth/register`: Validate password strong regex, email format. Gửi email xác thực (mockup hoặc tích hợp SendGrid).
    - `POST /auth/refresh-token`: Cơ chế cấp lại Access Token mới dùng Refresh Token cũ, đồng thời thu hồi Refresh Token cũ (Rotation) + phát hiện reuse.
    - `POST /auth/logout`: Blacklist token hiện tại.
    - `POST /auth/forgot-password` & `POST /auth/reset-password`.
- [ ] **Security Logic**
    - Password Hashing: Sử dụng `bcrypt` với `work_factor` tùy chỉnh.
    - Dependency Injection: `get_current_user`, `get_current_active_user`.
    - [ ] Chuẩn hoá error codes: `AUTH_INVALID`, `AUTH_EXPIRED`, `AUTH_FORBIDDEN`, `RATE_LIMITED`.

### Flutter App (Module: Features/Auth)
- [ ] **Core Architecture**
    - **Network layer (khớp repo hiện tại)**: dùng `ApiClient` + interceptors trong `lib/core/network/`.
    - **Auth token strategy (tùy chọn)**:
        - Nếu dùng Backend JWT: cần cơ chế attach Bearer + refresh-on-401 (có lock chống gọi refresh song song).
        - Nếu dùng Firebase: attach `Firebase ID Token` khi gọi backend (backend verify).
    - **Secure Storage**: nếu dùng JWT refresh token → ưu tiên `flutter_secure_storage` (Keychain/Keystore).
- [ ] **UI/UX Components**
    - **Input Validation**: Form có validation realtime (Email không hợp lệ, Password quá ngắn) trước khi bấm submit.
    - **UI State**: Button hiển thị loading spinner khi đang gọi API.
    - **Error Handling**: Hiển thị Toast/Snackbar thông báo lỗi cụ thể từ Server (VD: "Email đã tồn tại", "Sai mật khẩu").
- [ ] **Screens**
    - `LoginScreen`, `RegisterScreen` (support Social Login UI placeholder).
    - `OnboardingScreen`: Lưu state "isFirstTimeOpen" vào SharedPreferences để không hiện lại lần 2.

---

## 📚 Phase 2: Advanced Content Management System (CMS) & Structure
*Trọng tâm: Cấu trúc dữ liệu linh hoạt, hỗ trợ nhiều loại nội dung học tập phức tạp.*

### Backend Service
- [ ] **Database Design (Hierarchical Content)**
    - Table `courses`: Thêm `tags` (JSON), `total_xp`, `estimated_duration`. Index `level` và `is_published`.
    - Table `units` (Thay cho Topics): Nhóm bài học lớn. Column: `background_color` (cho UI sinh động).
    - Table `lessons`: Thêm `pass_score` (điểm tối thiểu để qua bài), `prerequisite_lesson_id` (bài học tiên quyết).
    - Table `media_resources`: Quản lý tập trung hình ảnh/âm thanh (tránh lặp lại URL trong nhiều bảng).
- [ ] **Nội dung học phải có version**
    - [ ] Thêm `content_version` ở course/unit/lesson để app có thể invalidate cache/offline.
    - [ ] Seed script/import (JSON/CSV) + checksum để đảm bảo nội dung nhất quán.
- [ ] **API Optimization**
    - `GET /courses`: Phân trang (Pagination) + Filter (theo Level/Tags).
    - `GET /course/{id}/roadmap`: Trả về dữ liệu dạng cây (Nested JSON) để render Map lộ trình học.
    - **Caching Strategy**: Dùng Redis cache `course_structure` với TTL 1 giờ. Invalidate cache khi Admin update bài học.
    - [ ] Thêm `ETag`/`If-None-Match` cho roadmap để giảm bandwidth.

### Flutter App (Module: Features/Course)
- [ ] **UI Components (High Interaction)**
    - **Lesson Map Widget**: Vẽ đường đi cong lượn sóng (giống Duolingo), dùng `CustomPainter`.
    - **Level Icon**: Có trạng thái (Locked - Xám, Active - Màu sáng + Animation nảy, Completed - Vàng/Gold).
    - **Course Progress Header**: Thanh progress tổng thể của khóa học.
- [ ] **Offline Capability (Preparations)**
    - Thiết kế Local DB (hiện repo đang có `sqflite`): `CoursesTable`, `UnitsTable`, `LessonsTable` + `content_version`.
    - Logic "Download Course": Tải assets (ảnh/mp3) về AppDirectory.
    - [ ] Chiến lược sync: last-updated + content_version để tránh merge phức tạp.

---

## 🧠 Phase 3: Smart Learning Engine & Spaced Repetition (SRS)
*Trọng tâm: Trải nghiệm học tập đa dạng, thuật toán lặp lại ngắt quãng để tối ưu ghi nhớ.*

### Backend Service
- [ ] **SRS Implementation (Algorithm)**
    - Table `user_vocab_knowledge`: `user_id`, `vocab_id`, `strength` (0-100%), `last_review_date`, `next_review_date` (tính theo SM-2/FSRS algorithm).
    - Job/Cron: Mỗi ngày quét DB để tìm các từ cần ôn tập -> Đẩy vào `Daily Review Session`.
- [ ] **Expanded Question Types**
    - `Pronunciation` (Placeholder): Chỉ định câu cần phát âm (sẽ nối AI Service sau).
    - `Sentence Arrange`: Sắp xếp các từ lộn xộn thành câu đúng (Lưu danh sách các từ rời rạc trong JSON).
    - `Listening Dictation`: Nghe audio và gõ lại nội dung.

- [ ] **Chuẩn hoá Progress/Attempt (cực quan trọng cho AI sau này)**
    - [ ] Table `lesson_attempts`: `user_id`, `lesson_id`, `started_at`, `finished_at`, `score`, `passed`, `xp_earned`.
    - [ ] Table `question_attempts`: `attempt_id`, `question_id`, `answer`, `is_correct`, `time_spent_ms`, `hint_used`.
    - [ ] API: `POST /lessons/{id}/start`, `POST /lessons/{id}/submit`, `GET /me/progress/summary`.

### Flutter App (Module: Features/Learning)
- [ ] **Interactive Widgets Workshop**
    - `DragAndDropWidget`: Kéo thả từ điền vào chỗ trống.
    - `PairMatchingWidget`: Game nối từ (Logic vẽ đường nối 2 item).
    - `SpeakingButton`: (Mockup) Nhấn giữ để ghi âm, hiển thị sóng âm (Waveform animation).
- [ ] **Session Manager Logic**
    - Quản lý State của một bài học: `List<Question>`, `currentQuestionIndex`, `UserAnswers`, `LifeHearts` (Tim - mạng sống).
    - Logic trừ tim khi làm sai. Hết tim -> Hiện popup "Hết mạng" -> Gợi ý nạp thêm hoặc xem quảng cáo (future).
- [ ] **Feedback System**
    - Bottom Sheet hiện lên ngay sau khi trả lời.
    - Sai: Hiện đáp án đúng + Giải thích (nếu có từ Backend).
    - Đúng: Hiệu ứng âm thanh "Ding" + Text khen ngợi ngẫu nhiên.

- [ ] **Sự kiện học (LearningEvent) để sau này AI đọc**
    - [ ] Emit event khi: start lesson, answer question, finish lesson, review vocab.
    - [ ] Queue offline → sync khi có mạng.

---

## 🏆 Phase 4: Integrated Gamification & Social Features
*Trọng tâm: Giữ chân người dùng bằng cơ chế thưởng và thi đua.*

### Backend Service
- [ ] **Gamification Engine**
    - Table `achievements`: `id`, `condition_type` (reach_streak_10, pass_level_a1), `badge_icon`.
    - Table `user_achievements`: Lưu các huy hiệu user đạt được.
    - Table `user_wallet`: `gems` (đơn vị tiền ảo), `history` (lịch sử cộng/trừ gem).
- [ ] **Leaderboard Logic**
    - Xây dựng Leaderboard "League" (Đồng, Bạc, Vàng).
    - Chủ Nhật hàng tuần: Job reset bảng xếp hạng, thăng hạng 10 người đầu, rớt hạng 10 người cuối.
- [ ] **Social API**
    - `POST /users/follow/{id}`: Theo dõi bạn bè.
    - `GET /users/friends/activity`: Newsfeed hiển thị "A vừa hoàn thành bài học", "B vừa đạt Streak 100".

### Flutter App (Module: Features/Profile & Social)
- [ ] **Profile Screen Pro**
    - Biểu đồ Heatmap (Giống Github) hiển thị cường độ học trong năm.
    - Show list Badges (Huy hiệu) dạng Grid. Icon bị khóa sẽ mờ đi.
- [ ] **Leaderboard Tab**
    - Tab riêng biệt. List view scroll vô tận.
    - Highlight highlignt vị trí của bản thân (Sticky bar ở dưới cùng nếu mình đang ở top dưới).
- [ ] **Shop System**
    - Màn hình đổi Gem lấy: "Freeze Streak" (Bảo hộ chuỗi), "Double XP" (Nhân đôi điểm).

---

## ⚙️ Phase 5: System Reliability & DevOps (Nền tảng vận hành)

### Backend Service
- [ ] **Observability**
    - Tích hợp `Logfire` hoặc `Prometheus` để monitor API latency.
    - Sentry connection để bắt Exception realtime.
- [ ] **Unit Testing**
    - Viết test cho Core Logic: `test_srs_algorithm.py`, `test_streak_calculation.py`.
    - API Test với `TestClient` của FastAPI.

- [ ] **Contract Tests (khuyến nghị)**
    - [ ] Snapshot test cho response schema quan trọng: auth, courses, roadmap, submit.

### Flutter App
- [ ] **CI/CD Pipeline**
    - Setup Github Actions: Auto run `flutter test`, `flutter analyze` khi Pull Request.
    - Auto build Android APK release khi merge vào branch `main`.
- [ ] **Performance Polish**
    - Sử dụng `RepaintBoundary` cho các Animation nặng.
    - Profile app để check Memory Leak (đặc biệt là AudioPlayer controllers).
    - Tối ưu kích thước ảnh (dùng format WebP thay vì PNG/JPG).

---

## 🔌 “AI-ready” Checklist (làm ngay từ Core để tích hợp AI nhẹ nhàng)

- [ ] **Stable identifiers**: mọi `lesson_id`, `question_id`, `vocab_id` là stable UUID/slug.
- [ ] **Conversation/Session id**: nếu có chat/tutor sau này, chuẩn hoá `chat_session_id` + mapping sang learning context.
- [ ] **AI Gateway interface**: Flutter & backend đều gọi qua 1 lớp client, không gọi thẳng AI-service ở UI.
- [ ] **Telemetry**: log p50/p95 latency, error rate, token usage (sau này) theo `request_id`.
- [ ] **Feature flags**: bật/tắt AI features theo user cohort (A/B testing).
