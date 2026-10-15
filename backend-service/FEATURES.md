# Backend Service — Danh sách chức năng

FastAPI + SQLAlchemy async (PostgreSQL) + Celery + Redis. Tất cả route dưới `{API_V1_PREFIX}` (mặc định `/api/v1`) trừ health & well-known.

## 1. Xác thực & Tài khoản

| Nhóm | Endpoint | Chức năng |
|------|----------|-----------|
| `/auth` | `register`, `login`, `refresh`, `logout`, `me` | Đăng ký/đăng nhập JWT, refresh token, blacklist khi logout |
| `/auth` | `google`, `facebook` | Đăng nhập social (Firebase) |
| `/auth` | `verify-email`, `resend-verification` | Xác thực email |
| `/auth` | `forgot-password`, `reset-password`, `change-password` | Khôi phục / đổi mật khẩu |
| `/auth` | `admin/login`, `admin/request-otp`, `admin/verify-otp` | Đăng nhập admin 2 bước qua OTP |
| `/users` | `me` (GET/PUT/DELETE), `me/permanent` | Hồ sơ cá nhân, xoá mềm & xoá vĩnh viễn |
| `/users` | `search`, `{user_id}` | Tìm & xem hồ sơ người dùng khác |
| `/users` | `me/level`, `me/stats`, `me/weekly-activity`, `me/xp` | Level, thống kê, hoạt động tuần |
| `/devices` | CRUD | Đăng ký thiết bị + push token |

## 2. Nội dung khoá học

| Nhóm | Chức năng |
|------|-----------|
| `/courses` | Danh sách khoá học, chi tiết, khoá đã ghi danh, ghi danh |
| `/categories` | Danh mục khoá học (CRUD + đếm lại số khoá) |
| `/learning` | Bắt đầu bài học, lấy nội dung/ngữ cảnh, nộp câu trả lời, hoàn thành lượt, roadmap khoá học |
| `/progress` | Tiến độ tổng / theo khoá, hoàn thành bài học, XP, tiến độ tuần |
| `/progress/streak` | Xem, cập nhật, đóng băng, khôi phục streak, nhận thưởng hằng ngày |

> Ràng buộc: bài học chỉ "học được" khi `content.exercises` khác rỗng; endpoint learner ẩn/trả 409 với bài học rỗng.

## 3. Từ vựng & Ôn tập (FSRS)

| Endpoint | Chức năng |
|----------|-----------|
| `/vocabulary/word-of-day` | Từ trong ngày |
| `/vocabulary/items` | Tra cứu kho từ vựng |
| `/vocabulary/collection` (+ `quick-save`, `bulk`) | Sổ tay từ cá nhân |
| `/vocabulary/due`, `/review/{id}` | Lịch ôn theo FSRS |
| `/vocabulary/decks` | Bộ thẻ tự tạo (CRUD + thêm/xoá thẻ) |
| `/vocabulary/pronunciation/evaluate` | Chấm phát âm (proxy AI service) |
| `/vocabulary/stats` | Thống kê học từ |
| `/concepts/due` | Concept (ngữ pháp/kỹ năng) đến hạn ôn |
| `/mistakes` | Sổ lỗi sai: xem & xoá |

## 4. Game hoá & Xã hội

| Endpoint | Chức năng |
|----------|-----------|
| `/games/*` | 6 minigame: word-scramble, matching, spelling-bee, hangman, fill-blank, grammar-quiz + danh mục |
| `/gamification/achievements` | Danh sách, của tôi, gần đây, kiểm tra thành tựu |
| `/gamification/wallet` | Số dư xu + lịch sử giao dịch |
| `/gamification/shop`, `/inventory` | Cửa hàng, mua, sử dụng vật phẩm |
| `/gamification/boosts` | Boost đang hiệu lực, hệ số nhân XP |
| `/gamification/leaderboard` | Bảng xếp hạng + hạng của tôi |
| `/gamification/users/*` | Follow/unfollow, followers, following, gợi ý bạn, feed |
| `/gamification/users/location`, `/nearby` | Vị trí & người học gần đây |
| `/challenges/daily` | Thử thách ngày + nhận thưởng / thưởng bonus |
| `/xp` | Cộng XP, hồ sơ XP, bảng xếp hạng XP |
| `/referral` | Mã giới thiệu của tôi, nhận thưởng theo mã |

## 5. Đánh giá trình độ

`/proficiency` — hồ sơ trình độ, ghi nhận kết quả bài tập, kiểm tra level, ngưỡng level, lịch sử, bài test xếp lớp (lấy + nộp), nộp bài thi có kiểm soát (`exam-gated/submit`).

`/recommendations` — gợi ý nội dung cá nhân hoá (RecGraph/EASE/SKNN, xem [[project_recsys_phases]]).

## 5b. IELTS

| Nhóm | Endpoint | Chức năng |
|------|----------|-----------|
| `/ielts` | `tests`, `tests/{id}` | Danh sách & chi tiết đề thi IELTS |
| `/ielts` | `tests/{id}/start` | Bắt đầu lượt làm bài |
| `/ielts` | `attempts/{id}/answers` (PATCH) | Lưu câu trả lời theo lượt |
| `/ielts` | `attempts/{id}/submit`, `attempts/{id}/result` | Nộp bài & xem kết quả |
| `/ielts` | `attempts` | Lịch sử lượt làm bài của tôi |
| `/admin/ielts` | `tests` (CRUD), `tests/{id}/validate` | Quản trị đề thi + kiểm tra hợp lệ (40 câu/đề) |
| `/admin/ielts` | `attempts`, `upload-audio` | Xem lượt làm bài, upload audio nghe |

## 6. Nội dung ngoài (content hub)

| Endpoint | Chức năng |
|----------|-----------|
| `/news` | Tin tức, danh mục, nội dung đầy đủ, quiz theo bài, proxy ảnh |
| `/youtube` | Kênh, tìm video, video theo kênh, phụ đề, dịch |
| `/podcasts` | Tìm, curated, tập, transcript, proxy ảnh |
| `/books` | Gợi ý, tìm, duyệt, quiz theo sách, proxy ảnh/text |

Có cache (`api_cache`) + quota manager cho API bên thứ ba, và Celery prefetch định kỳ.

## 7. Thông báo & Nhắc học

| Endpoint | Chức năng |
|----------|-----------|
| `/notifications` | Danh sách, đánh dấu đã đọc (từng cái / tất cả), xoá |
| `/users/me/reminder-preferences` | Cấu hình giờ nhắc, kênh nhắc |
| Celery | Quét nhắc FSRS, cảnh báo streak (20:00), word-of-day (08:00) |

## 8. Thanh toán & Quyền lợi

`/entitlements` — `sync` (đồng bộ RevenueCat) và `me` (quyền lợi hiện tại: premium, giới hạn tính năng). Kèm `starter_reward_service`, `item_effects_service`.

## 9. Admin

| Nhóm | Chức năng |
|------|-----------|
| `/admin/courses|units|lessons` | CRUD khoá/unit/bài học + sửa content + bulk import |
| `/admin/vocabulary|grammar|questions|test-exams` | CRUD + bulk import từng loại nội dung |
| `/admin/import/extract-pdf-text`, `/upload/badge` | Trích text từ PDF, upload huy hiệu |
| `/admin/achievements`, `/admin/shop` | CRUD thành tựu & vật phẩm shop |
| `/admin/seed`, `/system-info`, `/quota-usage`, `/quota-reset` | Seed dữ liệu, cấu hình hệ thống, hạn mức API |
| `/admin/users` | Danh sách/chi tiết/sửa, đổi vai trò & trạng thái, xoá vĩnh viễn, lịch sử hoạt động, thao tác hàng loạt, tặng quà |
| `/admin/rbac` | Vai trò, quyền, gán vai trò, kích hoạt/vô hiệu user, audit log, dashboard |
| `/admin/analytics` | KPI, tăng trưởng user, engagement, độ phổ biến khoá, phễu hoàn thành, cohort retention, hiệu quả nội dung & từ vựng |
| `/admin/monitoring` | Tình trạng hệ thống, services, DB stats, request stats |
| `/admin/ai-proxy` | Quản lý chủ đề & cấu hình proxy sang AI service |
| `/admin/content-agent` | Job sinh nội dung bằng AI: xem, preview, apply |
| `/admin/ranking-agent` | Job xếp hạng/league: xem, preview, apply, cancel, retry |
| `/admin/notification-campaign` | Tạo & chạy chiến dịch thông báo |

## 10. Tích hợp & Nội bộ

| Nhóm | Chức năng |
|------|-----------|
| `/integrations/*` | API cho đối tác (auth bằng partner API key): courses, categories, lessons, vocabulary, games, news, podcasts, books |
| `/internal/learner-state` | `batch-get`, `observations:batch` — đồng bộ trạng thái người học với AI service (có outbox) |
| `/analytics/events` | Ghi nhận product event từ client |
| `/ai-audit` | Ghi & xem sự kiện AI, tổng hợp chất lượng |
| `/health`, `/health/ready`, `/ping` | Health check / readiness |
| `/.well-known/*` | assetlinks.json (Android), apple-app-site-association (iOS) |

## 11. Tác vụ nền (Celery beat)

| Task | Lịch |
|------|------|
| `reminders.scan_fsrs_reminders` | Theo `REMINDER_SCAN_INTERVAL_SECONDS` |
| `event_worker.drain_content_interaction_stream` | Theo `EVENT_WORKER_DRAIN_INTERVAL_SECONDS` |
| `streak_reminders.send_streak_alerts` | 20:00 hằng ngày |
| `word_of_day.send_word_of_day` | 08:00 hằng ngày |
| `content_agent.cleanup_expired_content_agent_uploads` | 03:15 hằng ngày |
| `learner_state.cleanup_learner_observations` | 02:30 hằng ngày |
| `auth_tokens.prune_refresh_tokens` | 02:15 hằng ngày |
| `skill_history.prune_exercise_attempts` | 02:45 hằng ngày |
| `event_worker.prune_product_events` | 03:45 hằng ngày |
| `skill_history.snapshot_skill_scores` | 03:00 thứ Hai |
| `ranking_agent.auto_league_reset` | 00:05 thứ Hai |
| `content_prefetch_schedule.prefetch_news` | Mỗi 6 giờ |
| `content_prefetch_schedule.prefetch_youtube` | Mỗi 12 giờ |
| `content_prefetch_schedule.prefetch_podcasts` | 00:00 hằng ngày |

## 12. Hạ tầng chung

- **Middleware**: RequestID, RequestLogging, CORS, SecurityHeaders, PrivateNetworkAccess, rate limit.
- **Auth**: JWT + Firebase, token blacklist (Redis), partner API key, RBAC theo role/permission.
- **Cache**: Redis (`core/cache.py`, `core/redis.py`) + `api_cache` cho nội dung ngoài.
- **Services đáng chú ý**: FSRS scheduler, XP/level/rank, streak, quota manager, entitlement, email, push notification, user deletion, achievement checker.
- **Migration**: Alembic (`alembic/versions/`).
