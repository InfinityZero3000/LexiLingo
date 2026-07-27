# Tài liệu API LexiLingo

> Cập nhật theo các router đang được đăng ký trong
> `backend-service/app/main.py` và `ai-service/api/main.py`.

LexiLingo gồm hai FastAPI service:

- **Backend Service**: tài khoản, nội dung học, tiến độ, từ vựng, game và quản trị.
- **AI Service**: chat, TraceCAG, dịch, STT, TTS và hội thoại theo chủ đề.

Các URL bên dưới là path của service tương ứng. Host và port phụ thuộc môi
trường triển khai.

## Sử dụng API từ hệ thống bên ngoài

Base URL production:

```text
https://api.lexilingo.me
```

Các endpoint nghiệp vụ dùng tiền tố `/api/v1`. Ví dụ:

```bash
curl https://api.lexilingo.me/backend-health  → backend-service
curl https://api.lexilingo.me/ai-health       → ai-service
```

### Đăng nhập và gọi API người dùng

1. Đăng nhập qua `POST /api/v1/auth/login`.
2. Lấy `access_token` từ response.
3. Gửi token ở header `Authorization` cho các request tiếp theo:

```bash
curl https://api.lexilingo.me/api/v1/users/me \
  -H "Authorization: Bearer <access_token>"
```

Access token mặc định hết hạn sau 30 phút. Dùng
`POST /api/v1/auth/refresh` để lấy token mới.

### Phân loại quyền truy cập

- **Public/health**: có thể gọi trực tiếp, ví dụ `/health`, `/ping`,
  `/api/v1/auth/login`.
- **User API**: yêu cầu `Authorization: Bearer <access_token>`.
- **Admin API**: yêu cầu quyền admin và khóa quản trị theo cấu hình triển khai.
- **Internal API**: chỉ dành cho giao tiếp giữa các service; không cung cấp
  secret nội bộ cho hệ thống bên ngoài.

### Cấu hình phía client tích hợp

Hệ thống tích hợp có thể tự đặt tên biến cấu hình, ví dụ:

```env
LEXILINGO_BACKEND_URL=https://api.lexilingo.me/api/v1
LEXILINGO_AI_URL=https://api.lexilingo.me/api/v1
```

Đây là biến của client tích hợp, không phải biến mà LexiLingo backend đọc.

### CORS

Ứng dụng browser chỉ gọi được từ các origin đã được gateway cho phép. Tích
hợp server-to-server không bị giới hạn bởi CORS.

## Biến môi trường nội bộ (không dành cho bên tích hợp)

Các tên `LEXILINGO_IMPORT_KEY`, `LEXILINGO_AI_SERVICE_SECRET` hiện không được
codebase đọc. Các biến nội bộ đang dùng là:

| Mục đích | Biến nội bộ |
| --- | --- |
| Backend gọi AI Service | `AI_SERVICE_URL` |
| AI Service gọi Backend | `BACKEND_SERVICE_URL` |
| AI Service gửi sự kiện audit về Backend | `BACKEND_AUDIT_INGEST_URL` |
| Secret cho audit ingest, gửi qua `X-AI-Service-Secret` | `AI_AUDIT_INGEST_SECRET` |
| Khóa import dùng chung | Chưa có |

## Xác thực

- API người dùng dùng `Authorization: Bearer <access_token>`.
- Access token mặc định hết hạn sau 30 phút; refresh token sau 7 ngày.
- API quản trị AI dùng `X-Admin-Key`.
- API gọi nội bộ dùng secret riêng, ví dụ `X-AI-Service-Secret`.
- Yêu cầu xác thực cụ thể của từng route được thể hiện đầy đủ tại `/docs`.

## Tích hợp server-to-server

Có cơ chế service authentication, nhưng các credential này chỉ dành cho
service được cấp quyền, không dành cho ứng dụng bên thứ ba tự đăng ký:

| Phạm vi | Header | Giá trị kiểm tra | Route |
| --- | --- | --- | --- |
| Learner state nội bộ | `X-Lexilingo-Service-Token` và `X-Lexilingo-Audience` | `LEARNER_STATE_INTERNAL_TOKEN` và `LEARNER_STATE_INTERNAL_AUDIENCE` | `/api/v1/internal/learner-state/*` |
| Content agent nội bộ | `X-Content-Agent-Token` | `CONTENT_AGENT_SERVICE_TOKEN` | `/api/v1/internal/content-agent/*` |
| AI audit ingest | `X-AI-Service-Secret` | `AI_AUDIT_INGEST_SECRET` | `/api/v1/ai-audit/events` |
| AI admin | `X-Admin-Key` | `AI_ADMIN_API_KEY` | Các route admin của AI |

Các secret trên phải được cấp qua secret manager/env production và không được
đưa vào frontend, mobile app hoặc tài liệu công khai.

API đối tác read-only dùng namespace `/api/v1/integrations` và header
`X-LexiLingo-API-Key`. Key chỉ dùng server-to-server, không đại diện cho người
dùng và không truy cập được user, progress, admin hoặc internal API.

### API đối tác: Courses

```http
GET /api/v1/integrations/courses?page=1&page_size=20&language=en&level=A1
X-LexiLingo-API-Key: <partner-key>
```

| Query | Kiểu | Mặc định | Ràng buộc |
| --- | --- | --- | --- |
| `page` | integer | `1` | `>= 1` |
| `page_size` | integer | `20` | `1..100` |
| `language` | string/null | null | Ví dụ `en` |
| `level` | string/null | null | CEFR `A1` đến `C2` |

Response `200`:

```json
{
  "data": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "title": "English A1",
      "description": "Beginner English",
      "language": "en",
      "level": "A1",
      "tags": [],
      "thumbnail_url": null,
      "total_lessons": 10,
      "total_xp": 100,
      "estimated_duration": 120,
      "is_enrolled": null
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 20,
    "total": 1,
    "total_pages": 1
  }
}
```

| Status lỗi | Khi nào |
| --- | --- |
| `401` | Thiếu hoặc sai `X-LexiLingo-API-Key` |
| `422` | Query parameter không hợp lệ |

Lát cắt đầu tiên dùng allowlist hash dùng chung trong env; chưa có key ID,
owner, hạn dùng, revoke hoặc rotate riêng từng đối tác. Server chỉ lưu SHA-256
của các key trong `LEXILINGO_PARTNER_API_KEY_HASHES`; plaintext key phải được
trao đổi qua secret manager. Không dùng key này trong browser.

### Allowlist API read-only hiện có

Tất cả route dưới đây dùng `GET` và bắt buộc cùng API key:

```text
/api/v1/integrations/courses
/api/v1/integrations/courses/{course_id}
/api/v1/integrations/categories
/api/v1/integrations/categories/{category_id}
/api/v1/integrations/categories/slug/{slug}
/api/v1/integrations/categories/{category_id}/courses
/api/v1/integrations/lessons/{lesson_id}/content
/api/v1/integrations/lessons/{lesson_id}/context
/api/v1/integrations/vocabulary/word-of-day
/api/v1/integrations/vocabulary/items
/api/v1/integrations/vocabulary/items/{vocabulary_id}
/api/v1/integrations/games/categories
/api/v1/integrations/news
/api/v1/integrations/news/categories
/api/v1/integrations/news/{article_id}/quiz
/api/v1/integrations/podcasts/search
/api/v1/integrations/podcasts/curated
/api/v1/integrations/podcasts/episodes
/api/v1/integrations/books/recommended
/api/v1/integrations/books/search
/api/v1/integrations/books/browse
/api/v1/integrations/books/{book_id}/quiz
/api/v1/integrations/youtube/channels
/api/v1/integrations/youtube/search
/api/v1/integrations/youtube/captions/{video_id}
/api/v1/integrations/youtube/channels/{channel_id}/videos
```

Không expose trong namespace này: user/authentication, profile, enrollment,
collection/deck cá nhân, progress, XP, streak, achievements, các game session
cần user JWT, admin/RBAC, internal agent, audit, monitoring và mọi method
ghi/xóa.

## Request/response schema

Schema chi tiết của từng endpoint được phát hành tự động bởi FastAPI:

| Tài liệu | URL |
| --- | --- |
| Swagger UI (thử request trực tiếp) | `https://api.lexilingo.me/docs` |
| ReDoc (xem schema) | `https://api.lexilingo.me/redoc` |
| OpenAPI JSON (dùng cho code generation) | `https://api.lexilingo.me/openapi.json` |

Trong OpenAPI, `requestBody` mô tả JSON/form-data gửi lên; `responses` mô tả
status code, content type và response schema; phần `security`/`parameters` mô
tả JWT và các header xác thực của route. Ví dụ request tối thiểu cho đăng nhập:

```json
{
  "email": "user@example.com",
  "password": "your-password"
}
```

Response thành công trả về `access_token`, `refresh_token` và thông tin token
theo schema được định nghĩa trong `POST /api/v1/auth/login` trên OpenAPI.

## Backend Service

Phần lớn endpoint nghiệp vụ có tiền tố `/api/v1`. Các endpoint health và
well-known không có tiền tố này.

### Health và App Links

| Method | Endpoint |
| --- | --- |
| `GET` | `/health` |
| `GET` | `/health/ready` |
| `GET` | `/ping` |
| `GET` | `/.well-known/assetlinks.json` |
| `GET` | `/.well-known/apple-app-site-association` |

### Authentication

| Method | Endpoint |
| --- | --- |
| `POST` | `/api/v1/auth/register` |
| `POST` | `/api/v1/auth/resend-verification` |
| `POST` | `/api/v1/auth/login` |
| `POST` | `/api/v1/auth/refresh` |
| `GET` | `/api/v1/auth/me` |
| `POST` | `/api/v1/auth/logout` |
| `POST` | `/api/v1/auth/google` |
| `POST` | `/api/v1/auth/facebook` |
| `POST` | `/api/v1/auth/change-password` |
| `POST` | `/api/v1/auth/forgot-password` |
| `POST` | `/api/v1/auth/reset-password` |
| `POST` | `/api/v1/auth/verify-email` |
| `POST` | `/api/v1/auth/admin/login` |
| `POST` | `/api/v1/auth/admin/request-otp` |
| `POST` | `/api/v1/auth/admin/verify-otp` |

### Users, Devices, Reminders và Referral

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/users/me` |
| `PUT` | `/api/v1/users/me` |
| `DELETE` | `/api/v1/users/me` |
| `DELETE` | `/api/v1/users/me/permanent` |
| `GET` | `/api/v1/users/search` |
| `GET` | `/api/v1/users/{user_id}` |
| `GET` | `/api/v1/users/me/level` |
| `GET` | `/api/v1/users/me/level-full` |
| `GET` | `/api/v1/users/me/stats` |
| `GET` | `/api/v1/users/me/weekly-activity` |
| `POST` | `/api/v1/users/me/xp` |
| `POST` | `/api/v1/devices` |
| `GET` | `/api/v1/devices` |
| `PUT` | `/api/v1/devices/{device_id}` |
| `DELETE` | `/api/v1/devices/{device_id}` |
| `GET` | `/api/v1/users/me/reminder-preferences` |
| `PUT` | `/api/v1/users/me/reminder-preferences` |
| `GET` | `/api/v1/referral/my-code` |
| `POST` | `/api/v1/referral/claim/{code}` |

### Courses, Categories và Learning

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/courses` |
| `GET` | `/api/v1/courses/enrolled` |
| `GET` | `/api/v1/courses/{course_id}` |
| `GET` | `/api/v1/integrations/courses` |
| `POST` | `/api/v1/courses/{course_id}/enroll` |
| `GET` | `/api/v1/categories` |
| `GET` | `/api/v1/categories/{category_id}` |
| `GET` | `/api/v1/categories/slug/{slug}` |
| `GET` | `/api/v1/categories/{category_id}/courses` |
| `POST` | `/api/v1/categories` |
| `PUT` | `/api/v1/categories/{category_id}` |
| `DELETE` | `/api/v1/categories/{category_id}` |
| `POST` | `/api/v1/categories/update-counts` |
| `POST` | `/api/v1/learning/lessons/{lesson_id}/start` |
| `GET` | `/api/v1/learning/lessons/{lesson_id}/content` |
| `GET` | `/api/v1/learning/lessons/{lesson_id}/context` |
| `POST` | `/api/v1/learning/attempts/{attempt_id}/answer` |
| `POST` | `/api/v1/learning/attempts/{attempt_id}/complete` |
| `GET` | `/api/v1/learning/courses/{course_id}/roadmap` |

### Progress và Proficiency

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/progress/me` |
| `GET` | `/api/v1/progress/courses/{course_id}` |
| `POST` | `/api/v1/progress/lessons/{lesson_id}/complete` |
| `GET` | `/api/v1/progress/xp` |
| `GET` | `/api/v1/progress/weekly` |
| `GET` | `/api/v1/progress/streak` |
| `POST` | `/api/v1/progress/streak/update` |
| `POST` | `/api/v1/progress/streak/freeze` |
| `POST` | `/api/v1/progress/streak/restore` |
| `POST` | `/api/v1/progress/streak/claim-daily-reward` |
| `GET` | `/api/v1/proficiency/profile` |
| `POST` | `/api/v1/proficiency/record-exercises` |
| `GET` | `/api/v1/proficiency/level-check` |
| `GET` | `/api/v1/proficiency/level-thresholds` |
| `GET` | `/api/v1/proficiency/history` |
| `GET` | `/api/v1/proficiency/placement-test` |
| `POST` | `/api/v1/proficiency/placement-test/submit` |
| `POST` | `/api/v1/proficiency/exam-gated/submit` |

### Vocabulary và Mistake Notebook

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/vocabulary/word-of-day` |
| `GET` | `/api/v1/vocabulary/items` |
| `GET` | `/api/v1/vocabulary/items/{vocabulary_id}` |
| `GET` | `/api/v1/vocabulary/collection` |
| `POST` | `/api/v1/vocabulary/collection` |
| `POST` | `/api/v1/vocabulary/collection/quick-save` |
| `POST` | `/api/v1/vocabulary/collection/bulk` |
| `POST` | `/api/v1/vocabulary/pronunciation/evaluate` |
| `GET` | `/api/v1/vocabulary/due` |
| `POST` | `/api/v1/vocabulary/review/{user_vocabulary_id}` |
| `GET` | `/api/v1/vocabulary/stats` |
| `POST` | `/api/v1/vocabulary/decks` |
| `GET` | `/api/v1/vocabulary/decks` |
| `GET` | `/api/v1/vocabulary/decks/{deck_id}/items` |
| `POST` | `/api/v1/vocabulary/decks/{deck_id}/items` |
| `DELETE` | `/api/v1/vocabulary/decks/{deck_id}` |
| `DELETE` | `/api/v1/vocabulary/decks/{deck_id}/items/{user_vocabulary_id}` |
| `GET` | `/api/v1/mistakes` |
| `POST` | `/api/v1/mistakes` |
| `PATCH` | `/api/v1/mistakes/{mistake_id}/review` |
| `PATCH` | `/api/v1/mistakes/{mistake_id}/reopen` |
| `DELETE` | `/api/v1/mistakes/{mistake_id}` |

### Gamification, XP và Challenges

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/gamification/achievements` |
| `GET` | `/api/v1/gamification/achievements/me` |
| `GET` | `/api/v1/gamification/achievements/recent` |
| `POST` | `/api/v1/gamification/achievements/check` |
| `GET` | `/api/v1/gamification/rewards/starter/pending` |
| `POST` | `/api/v1/gamification/rewards/starter/seen` |
| `GET` | `/api/v1/gamification/wallet` |
| `GET` | `/api/v1/gamification/wallet/history` |
| `GET` | `/api/v1/gamification/leaderboard` |
| `GET` | `/api/v1/gamification/leaderboard/me` |
| `GET` | `/api/v1/gamification/shop` |
| `POST` | `/api/v1/gamification/shop/purchase` |
| `GET` | `/api/v1/gamification/inventory` |
| `POST` | `/api/v1/gamification/inventory/avatar/equip` |
| `POST` | `/api/v1/gamification/inventory/use` |
| `GET` | `/api/v1/gamification/boosts/active` |
| `GET` | `/api/v1/gamification/boosts/xp-multiplier` |
| `POST` | `/api/v1/gamification/users/{user_id}/follow` |
| `DELETE` | `/api/v1/gamification/users/{user_id}/follow` |
| `POST` | `/api/v1/gamification/users/{user_id}/unfollow` |
| `GET` | `/api/v1/gamification/users/{user_id}/followers` |
| `GET` | `/api/v1/gamification/users/{user_id}/following` |
| `GET` | `/api/v1/gamification/feed` |
| `GET` | `/api/v1/gamification/users/suggestions` |
| `POST` | `/api/v1/gamification/users/location` |
| `GET` | `/api/v1/gamification/users/nearby` |
| `POST` | `/api/v1/xp/award` |
| `GET` | `/api/v1/xp/profile` |
| `GET` | `/api/v1/xp/leaderboard` |
| `GET` | `/api/v1/challenges/daily` |
| `POST` | `/api/v1/challenges/daily/bonus/claim` |
| `POST` | `/api/v1/challenges/daily/{challenge_id}/claim` |

### Games

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/games/word-scramble` |
| `GET` | `/api/v1/games/matching` |
| `GET` | `/api/v1/games/spelling-bee` |
| `GET` | `/api/v1/games/hangman` |
| `GET` | `/api/v1/games/fill-blank` |
| `GET` | `/api/v1/games/grammar-quiz` |
| `POST` | `/api/v1/games/sessions/{session_id}/complete` |
| `GET` | `/api/v1/games/categories` |

### Content: YouTube, News, Podcasts và Books

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/youtube/channels` |
| `GET` | `/api/v1/youtube/search` |
| `GET` | `/api/v1/youtube/captions/{video_id}` |
| `GET` | `/api/v1/youtube/channels/{channel_id}/videos` |
| `GET` | `/api/v1/youtube/translate` |
| `GET` | `/api/v1/news` |
| `GET` | `/api/v1/news/proxy/image` |
| `GET` | `/api/v1/news/categories` |
| `POST` | `/api/v1/news/full-content` |
| `GET` | `/api/v1/news/{article_id}/quiz` |
| `GET` | `/api/v1/podcasts/proxy/image` |
| `GET` | `/api/v1/podcasts/search` |
| `GET` | `/api/v1/podcasts/curated` |
| `GET` | `/api/v1/podcasts/episodes` |
| `POST` | `/api/v1/podcasts/transcript` |
| `GET` | `/api/v1/books/proxy/image` |
| `GET` | `/api/v1/books/proxy/text` |
| `GET` | `/api/v1/books/recommended` |
| `GET` | `/api/v1/books/search` |
| `GET` | `/api/v1/books/browse` |
| `GET` | `/api/v1/books/{book_id}/quiz` |

### Notifications

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/notifications` |
| `PATCH` | `/api/v1/notifications/{notification_id}/read` |
| `PATCH` | `/api/v1/notifications/read-all` |
| `DELETE` | `/api/v1/notifications` |
| `DELETE` | `/api/v1/notifications/{notification_id}` |

### Admin: Content

| Method | Endpoint |
| --- | --- |
| `GET`, `POST` | `/api/v1/admin/courses` |
| `PUT`, `DELETE` | `/api/v1/admin/courses/{course_id}` |
| `GET`, `POST` | `/api/v1/admin/units` |
| `PUT`, `DELETE` | `/api/v1/admin/units/{unit_id}` |
| `GET`, `PUT`, `DELETE` | `/api/v1/admin/lessons/{lesson_id}` |
| `GET`, `POST` | `/api/v1/admin/lessons` |
| `PUT` | `/api/v1/admin/lessons/{lesson_id}/content` |
| `GET`, `POST` | `/api/v1/admin/vocabulary` |
| `PUT`, `DELETE` | `/api/v1/admin/vocabulary/{vocab_id}` |
| `POST` | `/api/v1/admin/vocabulary/bulk-import` |
| `POST` | `/api/v1/admin/upload/badge` |
| `GET`, `POST` | `/api/v1/admin/grammar` |
| `PUT`, `DELETE` | `/api/v1/admin/grammar/{grammar_id}` |
| `GET`, `POST` | `/api/v1/admin/questions` |
| `PUT`, `DELETE` | `/api/v1/admin/questions/{question_id}` |
| `GET`, `POST` | `/api/v1/admin/test-exams` |
| `PUT`, `DELETE` | `/api/v1/admin/test-exams/{test_exam_id}` |

### Admin: Gamification, Users, RBAC và System

| Method | Endpoint |
| --- | --- |
| `GET`, `POST` | `/api/v1/admin/achievements` |
| `PUT`, `DELETE` | `/api/v1/admin/achievements/{achievement_id}` |
| `GET`, `POST` | `/api/v1/admin/shop` |
| `PUT`, `DELETE` | `/api/v1/admin/shop/{item_id}` |
| `GET` | `/api/v1/admin/users` |
| `GET`, `PUT` | `/api/v1/admin/users/{user_id}` |
| `PUT` | `/api/v1/admin/users/{user_id}/role` |
| `PUT` | `/api/v1/admin/users/{user_id}/status` |
| `DELETE` | `/api/v1/admin/users/{user_id}/permanent` |
| `GET` | `/api/v1/admin/users/{user_id}/activity` |
| `POST` | `/api/v1/admin/users/bulk-action` |
| `POST` | `/api/v1/admin/users/{user_id}/gift` |
| `GET` | `/api/v1/admin/rbac/roles` |
| `GET` | `/api/v1/admin/rbac/roles/{role_slug}` |
| `GET` | `/api/v1/admin/rbac/permissions` |
| `GET` | `/api/v1/admin/rbac/users` |
| `POST` | `/api/v1/admin/rbac/users/assign-role` |
| `POST` | `/api/v1/admin/rbac/users/{user_id}/deactivate` |
| `POST` | `/api/v1/admin/rbac/users/{user_id}/activate` |
| `GET` | `/api/v1/admin/rbac/audit-logs` |
| `GET` | `/api/v1/admin/rbac/dashboard` |
| `POST` | `/api/v1/admin/seed` |
| `GET`, `PUT` | `/api/v1/admin/system-info` |
| `GET` | `/api/v1/admin/quota-usage` |
| `POST` | `/api/v1/admin/quota-reset/{api_name}` |
| `GET` | `/api/v1/admin/monitoring/system` |
| `GET` | `/api/v1/admin/monitoring/services` |
| `GET` | `/api/v1/admin/monitoring/db-stats` |
| `GET` | `/api/v1/admin/monitoring/request-stats` |

### Admin: Analytics và Agents

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/admin/analytics/dashboard/kpis` |
| `GET` | `/api/v1/admin/analytics/dashboard/user-growth` |
| `GET` | `/api/v1/admin/analytics/dashboard/engagement` |
| `GET` | `/api/v1/admin/analytics/dashboard/course-popularity` |
| `GET` | `/api/v1/admin/analytics/dashboard/completion-funnel` |
| `GET` | `/api/v1/admin/analytics/user-metrics` |
| `GET` | `/api/v1/admin/analytics/retention-cohorts` |
| `GET` | `/api/v1/admin/analytics/content-performance` |
| `GET` | `/api/v1/admin/analytics/vocabulary-effectiveness` |
| `POST` | `/api/v1/admin/content-agent/uploads` |
| `GET` | `/api/v1/admin/content-agent/sources` |
| `POST`, `GET` | `/api/v1/admin/content-agent/jobs` |
| `GET` | `/api/v1/admin/content-agent/jobs/{job_id}` |
| `GET` | `/api/v1/admin/content-agent/jobs/{job_id}/preview` |
| `POST` | `/api/v1/admin/content-agent/jobs/{job_id}/apply` |
| `POST` | `/api/v1/admin/content-agent/jobs/{job_id}/retry` |
| `POST` | `/api/v1/admin/content-agent/jobs/{job_id}/cancel` |
| `POST`, `GET` | `/api/v1/admin/notification-campaign/jobs` |
| `GET` | `/api/v1/admin/notification-campaign/jobs/{job_id}` |
| `POST` | `/api/v1/admin/notification-campaign/jobs/{job_id}/apply` |
| `POST` | `/api/v1/admin/notification-campaign/jobs/{job_id}/cancel` |
| `POST` | `/api/v1/admin/notification-campaign/jobs/{job_id}/retry` |
| `POST`, `GET` | `/api/v1/admin/ranking-agent/jobs` |
| `GET` | `/api/v1/admin/ranking-agent/jobs/{job_id}` |
| `GET` | `/api/v1/admin/ranking-agent/jobs/{job_id}/preview` |
| `POST` | `/api/v1/admin/ranking-agent/jobs/{job_id}/apply` |
| `POST` | `/api/v1/admin/ranking-agent/jobs/{job_id}/cancel` |
| `POST` | `/api/v1/admin/ranking-agent/jobs/{job_id}/retry` |

### Backend Internal và AI Audit

| Method | Endpoint |
| --- | --- |
| `POST` | `/api/v1/internal/learner-state/batch-get` |
| `POST` | `/api/v1/internal/learner-state/observations:batch` |
| `POST` | `/api/v1/ai-audit/events` |
| `GET` | `/api/v1/ai-audit/events/me` |
| `GET` | `/api/v1/ai-audit/quality-summary` |

## AI Service

### Service, Chat và Lexi Chat

| Method | Endpoint |
| --- | --- |
| `GET` | `/` |
| `GET` | `/health` |
| `GET`, `POST` | `/warmup` |
| `GET`, `POST` | `/api/v1/warmup` |
| `POST` | `/api/v1/chat/sessions` |
| `POST` | `/api/v1/chat/messages` |
| `GET` | `/api/v1/chat/sessions/{session_id}/messages` |
| `GET` | `/api/v1/chat/sessions/{session_id}/messages/paged` |
| `GET` | `/api/v1/chat/sessions/{session_id}/messages/metadata` |
| `GET` | `/api/v1/chat/sessions/user/{user_id}` |
| `POST` | `/api/v1/lexi/sessions` |
| `POST` | `/api/v1/lexi/chat` |
| `POST` | `/api/v1/lexi/stream` |
| `GET` | `/api/v1/lexi/sessions/{session_id}/messages` |
| `GET` | `/api/v1/lexi/sessions/{session_id}/messages/paged` |
| `GET` | `/api/v1/lexi/sessions/{session_id}/messages/metadata` |
| `GET` | `/api/v1/lexi/sessions/user/{user_id}` |
| `POST` | `/api/v1/lexi/sessions/{session_id}/rename` |
| `POST` | `/api/v1/lexi/sessions/{session_id}/delete` |
| `GET` | `/api/v1/lexi/health` |

### Topic Chat

| Method | Endpoint |
| --- | --- |
| `GET` | `/api/v1/topics/stories` |
| `GET` | `/api/v1/topics/categories` |
| `POST` | `/api/v1/topics/stories/warm` |
| `GET` | `/api/v1/topics/stories/{story_id}` |
| `POST` | `/api/v1/topics/topic-sessions` |
| `POST` | `/api/v1/topics/topic-sessions/{session_id}/messages` |
| `GET` | `/api/v1/topics/topic-sessions/{session_id}` |
| `GET` | `/api/v1/topics/topic-sessions/{session_id}/messages` |
| `GET` | `/api/v1/topics/topic-sessions/{session_id}/messages/paged` |
| `GET` | `/api/v1/topics/topic-sessions/{session_id}/messages/metadata` |
| `GET` | `/api/v1/topics/llm/health` |

### Speech và Voice

| Method | Endpoint |
| --- | --- |
| `WEBSOCKET` | `/api/v1/stt/stream` |
| `POST` | `/api/v1/stt/transcribe` |
| `POST` | `/api/v1/stt/assess-pronunciation` |
| `POST` | `/api/v1/tts/synthesize` |
| `GET` | `/api/v1/voice/ready` |
| `POST` | `/api/v1/voice/ticket` |

### AI, TraceCAG, Analytics và Translate

| Method | Endpoint |
| --- | --- |
| `POST` | `/api/v1/ai/trace-cag/analyze` |
| `POST` | `/api/v1/ai/analyze` |
| `GET` | `/api/v1/ai/trace-cag/health` |
| `GET`, `POST` | `/api/v1/ai/warmup` |
| `GET` | `/api/v1/ai/graph-analytics` |
| `GET` | `/api/v1/ai/graph-analytics/communities/{community_id}` |
| `GET` | `/api/v1/ai/monitoring/dashboard` |
| `GET` | `/api/v1/ai/monitoring/metrics/{metric_name}` |
| `GET` | `/api/v1/ai/monitoring/system` |
| `GET` | `/api/v1/ai/monitoring/health` |
| `POST` | `/api/v1/ai/interactions` |
| `GET` | `/api/v1/ai/interactions/user/{user_id}` |
| `GET` | `/api/v1/ai/interactions/session/{session_id}` |
| `POST` | `/api/v1/ai/interactions/{interaction_id}/feedback` |
| `GET` | `/api/v1/ai/analytics/user/{user_id}/errors` |
| `GET` | `/api/v1/ai/translate` |

### AI Admin và Ollama

| Method | Endpoint |
| --- | --- |
| `GET`, `PUT` | `/api/v1/admin/config` |
| `GET`, `POST` | `/api/v1/admin/topics` |
| `GET` | `/api/v1/ollama/health` |
| `POST` | `/api/v1/ollama/chat` |
| `POST` | `/api/v1/ollama/analyze` |
| `GET` | `/api/v1/ollama/models` |

### AI Internal Agents

| Method | Endpoint |
| --- | --- |
| `POST` | `/api/v1/internal/content-agent/jobs/{job_id}/records` |
| `POST` | `/api/v1/internal/content-agent/jobs/{job_id}/generate` |
| `DELETE` | `/api/v1/internal/content-agent/jobs/{job_id}` |
| `GET` | `/api/v1/internal/content-agent/sources` |
| `POST` | `/api/v1/internal/content-agent/jobs/{job_id}/snapshots` |
| `POST` | `/api/v1/internal/ranking-agent/insights` |
| `POST` | `/api/notification-agent/generate-content` |

## Tài liệu tương tác

Mỗi FastAPI service tự cung cấp:

- Swagger UI: `/docs`
- ReDoc: `/redoc`
- OpenAPI schema: `/openapi.json`

Swagger/OpenAPI là nguồn chi tiết cho request body, query parameter, response
schema, mã lỗi và yêu cầu xác thực của từng endpoint.
