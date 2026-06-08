# RPT-020 — Backend Service Report: API, Services & Database

> **Cập nhật:** 2026-04-24 | **Backend Version:** 1.0.1 | **FastAPI + PostgreSQL + Redis**

---

## 1. Tổng Quan Backend Service

Backend Service (`backend-service/`) là core API server xử lý:
- Authentication & Authorization
- User management & profiles
- Course & learning data
- Progress tracking & gamification
- Content management (news, podcasts, books, YouTube, games)
- Analytics & admin operations

**Tech Stack:**
- **Framework**: FastAPI (async)
- **Database**: PostgreSQL 14+ + SQLAlchemy (async ORM) + Alembic
- **Cache/Session**: Redis
- **Auth**: JWT + Firebase Admin SDK
- **Validation**: Pydantic v2

---

## 2. Middleware Stack

Middleware được thêm theo thứ tự (last added = outermost = chạy đầu tiên với request):

```
Request Flow:
PrivateNetworkAccess → CORS → RateLimit → RequestID → RequestLogging → App

Response Flow:
App → RequestLogging → RequestID → RateLimit → CORS → PrivateNetworkAccess
```

| Middleware | Chức năng |
|-----------|---------|
| `TrustedHostMiddleware` | Chặn requests từ host không được phép (production only) |
| `RequestLoggingMiddleware` | Log mọi request với latency |
| `RequestIDMiddleware` | Gán X-Request-ID duy nhất cho mỗi request |
| `RateLimitMiddleware` | Dev: 300 RPM / Prod: 120 RPM, max 5000/hour |
| `CORSMiddleware` | Cho phép cross-origin (lexilingo.me + configured origins) |
| `PrivateNetworkAccessMiddleware` | Chrome CORS-RFC1918 headers |
| `limit_request_body` | Reject body > MAX_REQUEST_BODY_BYTES |

---

## 3. Toàn Bộ API Routes

### 3.1 Authentication — `/api/v1/auth`

```
File: backend-service/app/routes/auth.py (27KB)
```

| Endpoint | Method | Chức năng |
|---------|--------|---------|
| `/register` | POST | Đăng ký email/password |
| `/login` | POST | Đăng nhập → JWT tokens |
| `/logout` | POST | Đăng xuất (blacklist token) |
| `/refresh` | POST | Làm mới access token |
| `/google` | POST | Đăng nhập Google (Firebase) |
| `/facebook` | POST | Đăng nhập Facebook (Firebase) |
| `/forgot-password` | POST | Yêu cầu reset password |
| `/reset-password` | POST | Reset password với token |
| `/verify-email` | POST | Xác minh email |
| `/change-password` | PUT | Đổi mật khẩu |
| `/me` | GET | Thông tin user hiện tại |

**Auth Flow:**
```
Register → Firebase token → Backend JWT
Google/Facebook → Firebase UID verify → Backend JWT
JWT → Access token (short) + Refresh token (long)
Logout → Token blacklist (Redis)
```

### 3.2 Users — `/api/v1/users`

```
File: backend-service/app/routes/users.py (15KB)
```

| Endpoint | Method | Chức năng |
|---------|--------|---------|
| `/me` | GET/PUT | Profile + settings |
| `/{user_id}` | GET | Xem profile người dùng |
| `/preferences` | GET/PUT | Preferences (language, theme) |
| `/avatar` | PUT | Upload avatar |

### 3.3 Courses — `/api/v1/courses`

```
File: backend-service/app/routes/courses.py (11KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/` (GET) | Danh sách courses |
| `/{id}` (GET) | Chi tiết course |
| `/{id}/lessons` | Danh sách lessons trong course |
| `/{id}/enroll` (POST) | Enroll vào course |

### 3.4 Learning Sessions — `/api/v1/learning`

```
File: backend-service/app/routes/learning.py (25KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/sessions` (POST) | Bắt đầu phiên học |
| `/sessions/{id}` (PUT) | Cập nhật phiên học |
| `/sessions/{id}/complete` | Hoàn thành phiên học |
| `/lessons/{id}/activities` | Log activity trong lesson |

### 3.5 Progress — `/api/v1`

```
File: backend-service/app/routes/progress.py (27KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/progress` (GET) | Tiến độ tổng hợp |
| `/progress/course/{id}` | Tiến độ theo course |
| `/streak` | Streak hiện tại |
| `/streak/update` (POST) | Cập nhật streak |
| `/daily-activity` | Activity hàng ngày |

### 3.6 Vocabulary — `/api/v1/vocabulary`

```
File: backend-service/app/routes/vocabulary.py (17KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/` (GET/POST) | Danh sách / thêm từ |
| `/{id}` (PUT/DELETE) | Sửa / xóa từ |
| `/review` (POST) | Ghi nhận kết quả ôn tập |
| `/due` | Từ cần ôn theo SM-2 |
| `/stats` | Thống kê từ vựng |

### 3.7 Gamification — `/api/v1`

```
File: backend-service/app/routes/gamification.py (31KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/leaderboard` | Bảng xếp hạng |
| `/achievements` | Thành tích của user |
| `/wallet` | Số dư gems/coins |
| `/shop` | Cửa hàng items |
| `/inventory` | Inventory user |
| `/daily-bonus` | Phần thưởng hàng ngày |

### 3.8 Challenges — `/api/v1`

```
File: backend-service/app/routes/challenges.py (22KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/challenges` | Danh sách challenges |
| `/challenges/daily` | Challenges hàng ngày |
| `/challenges/{id}/claim` | Nhận thưởng challenge |

### 3.9 Games — `/api/v1`

```
File: backend-service/app/routes/games.py (67KB — file lớn nhất)
```

| Endpoint | Chức năng |
|---------|---------|
| `/games/hub` | Danh sách mini-games |
| `/games/{type}/session` | Bắt đầu phiên game |
| `/games/{type}/result` | Gửi kết quả game |
| `/games/leaderboard` | Bảng xếp hạng games |

### 3.10 XP System — `/api/v1`

```
File: backend-service/app/routes/xp.py (16KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/xp/profile` | XP profile + level |
| `/xp/earn` (POST) | Earn XP |
| `/xp/history` | Lịch sử XP |
| `/xp/leaderboard` | XP leaderboard |

### 3.11 Proficiency Assessment — `/api/v1`

```
File: backend-service/app/routes/proficiency.py (28KB)
```

| Endpoint | Chức năng |
|---------|---------|
| `/proficiency` | Proficiency profile |
| `/proficiency/assess` (POST) | Đánh giá từ exercise results |
| `/proficiency/check-level` | Kiểm tra điều kiện lên level |
| `/proficiency/history` | Lịch sử level changes |
| `/proficiency/exam-gate` | Exam-gated promotion |
| `/proficiency/recommend` | Recommendations cải thiện |

### 3.12 Content Routes

| Route File | Prefix | Chức năng |
|-----------|--------|---------|
| `news.py` (21KB) | `/api/v1/news` | Tin tức + quiz |
| `podcasts.py` (25KB) | `/api/v1/podcasts` | Podcast catalog + RSS |
| `books.py` (18KB) | `/api/v1/books` | Thư viện sách |
| `youtube.py` (14KB) | `/api/v1/youtube` | YouTube videos |

### 3.13 Admin & Management Routes

| Route File | Prefix | Chức năng |
|-----------|--------|---------|
| `admin.py` (53KB — LỚN NHẤT) | `/api/v1/admin` | Full admin CMS |
| `user_management.py` (21KB) | `/api/v1/user-management` | Quản lý user nâng cao |
| `rbac.py` (12KB) | `/api/v1/rbac` | Role-based access control |
| `analytics.py` (16KB) | `/api/v1/analytics` | Analytics dashboard |
| `ai_audit.py` (3KB) | `/api/v1/ai-audit` | AI decision audit log |

### 3.14 Device & Notifications

| Route File | Prefix | Chức năng |
|-----------|--------|---------|
| `devices.py` (6KB) | `/api/v1/devices` | Đăng ký thiết bị FCM |

---

## 4. Business Services

### 4.1 Achievement Checker Service

```
File: backend-service/app/services/__init__.py (18KB)
```

**AchievementCheckerService** — đánh giá và mở khóa thành tích:

| Method | Chức năng |
|--------|---------|
| `check_all(user_id)` | Kiểm tra TẤT CẢ achievements (dùng khi cần) |
| `check_by_trigger(user_id, trigger)` | Kiểm tra chỉ achievements liên quan trigger |

**Triggers → Condition Types mapping:**
```python
"lesson_complete"  → lesson_complete, xp_earned, course_complete, speed_lesson
"streak_update"    → reach_streak, comeback
"vocab_review"     → vocab_mastered, vocab_reviewed
"quiz_complete"    → perfect_score, quiz_complete, first_perfect
"voice_practice"   → voice_practice
"daily_challenge"  → daily_challenge_complete
```

### 4.2 Proficiency Service

```
File: backend-service/app/services/proficiency_service.py (23KB)
```

#### CEFR Assessment Algorithm

**Skill Weights:**
```
Vocabulary:  25%  │  Grammar: 25%  │  Reading:  15%
Listening:   15%  │  Speaking: 10% │  Writing:  10%
```

**Difficulty Multipliers:**
```
A1: 0.5 │ A2: 0.7 │ B1: 1.0 │ B2: 1.3 │ C1: 1.6 │ C2: 2.0
```

**Skill Score Algorithm (EMA):**
```python
# Exponential Moving Average
final_score = (0.95 * current_score) + (0.05 * new_exercise_score)

# Weighted by difficulty_multiplier
new_exercise_score = Σ(score_contribution * difficulty_mult) / Σ(difficulty_mult)

# Confidence
confidence = min(1.0, len(exercises) / 50)  # 50+ = full confidence
```

**Level Requirements (chống XP grinding):**
- Phải đạt threshold mọi skill (vocabulary, grammar, reading, ...)
- Phải đủ exercises_completed và lessons_completed
- Phải đạt accuracy rate và streak_days tối thiểu

**Exam-Gated Promotion:**
- Chỉ lên tối đa 1 CEFR tier tại một thời điểm
- Phải pass exam và đạt passing_score (mặc định 70%)
- Exam level phải ≥ current level

### 4.3 API Cache Service

```
File: backend-service/app/services/api_cache_service.py (9KB)
```
- Redis-based API response caching
- TTL configuration per endpoint
- Cache invalidation by patterns

### 4.4 Email Service

```
File: backend-service/app/services/email_service.py (3KB)
```
- Email verification
- Password reset
- Notification emails

### 4.5 Level Service

```
File: backend-service/app/services/level_service.py (6KB)
```
- Numeric level calculation từ XP
- Level-up detection và rewards
- Level benefits

### 4.6 Rank Service

```
File: backend-service/app/services/rank_service.py (6KB)
```
- Leaderboard ranking computation
- Rank tiers (Bronze → Silver → Gold → Diamond)

### 4.7 Item Effects Service

```
File: backend-service/app/services/item_effects_service.py (10KB)
```
- Xử lý effect của shop items (XP boosts, streak freeze, etc.)
- Active item tracking

### 4.8 Quota Manager

```
File: backend-service/app/services/quota_manager.py (8KB)
```
- Quản lý quota API calls (rate limiting per user)
- Redis-based sliding window

---

## 5. Database Architecture

### 5.1 ORM Models

```
backend-service/app/models/
├── user.py          → User, UserSettings, UserPreferences
├── course.py        → Course, Lesson, Category
├── progress.py      → UserCourseProgress, LessonCompletion, Streak, DailyActivity
├── vocabulary.py    → UserVocabulary, VocabularyStatus
├── gamification.py  → Achievement, UserAchievement, Wallet, ShopItem,
│                       Challenge, ChallengeRewardClaim
└── (others)         → News, Podcast, Book, Game, XP, Device models
```

### 5.2 Database Startup

- **Development**: `init_db()` — tự động tạo tables
- **Production**: Alembic migrations qua `scripts/entrypoint.sh` trước khi Uvicorn start

### 5.3 Connection Strategy

```python
# Async SQLAlchemy
- PostgreSQL (prod): asyncpg driver
- SQLite (dev/test): aiosqlite driver
- Connection pool: SQLAlchemy async engine
```

### 5.4 Redis Usage

| Use Case | Key Pattern | TTL |
|---------|------------|-----|
| Token blacklist | `blacklist:{token}` | Token expiry |
| Rate limiting | `ratelimit:{ip}:{window}` | Rolling window |
| API cache | `cache:{endpoint}:{params}` | Configurable |
| Quota tracking | `quota:{user_id}:{period}` | Period |

---

## 6. CRUD Layer

```
backend-service/app/crud/
```

CRUD operations tách riêng khỏi routes, cung cấp:
- `gamification.py` — WalletCRUD (add/spend gems), AchievementCRUD
- Mỗi module có CRUD class hoặc standalone functions
- Sử dụng `AsyncSession` với `select()` + `execute()`

---

## 7. Schemas (Pydantic v2)

```
backend-service/app/schemas/
```

| Schema File | Mục đích |
|------------|---------|
| `common.py` | ErrorResponse, ErrorDetail, ErrorCodes |
| `auth.py` | LoginRequest, TokenResponse, RegisterRequest |
| `user.py` | UserProfile, UserUpdate |
| `proficiency.py` | SkillType, ProficiencyLevel, LEVEL_THRESHOLDS |
| `course.py` | CourseResponse, LessonResponse |
| (others) | Schemas cho mọi domain |

---

## 8. Exception Handling

```python
# 3 handlers đăng ký trong main.py:
HTTPException           → http_exception_handler
RequestValidationError  → validation_exception_handler
Exception               → unhandled_exception_handler

# Response format chuẩn:
{
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "...",
        "details": [...]
    }
}
```

---

## 9. Security Features

| Feature | Implementation |
|---------|---------------|
| **JWT Auth** | python-jose, RS256/HS256 |
| **Password Hashing** | passlib + bcrypt |
| **Firebase Auth** | firebase-admin SDK, ID token verification |
| **Rate Limiting** | Sliding window (Redis), fallback in-memory |
| **CORS** | Whitelist + regex pattern cho lexilingo.me |
| **Body Size Limit** | MAX_REQUEST_BODY_BYTES check |
| **Trusted Hosts** | Production-only |

---

## 10. Development Flow

```bash
# Setup
cd backend-service
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # Configure

# Database
alembic upgrade head   # Run migrations

# Run (development)
uvicorn app.main:app --reload --port 8000

# Run (production — via Docker)
docker-compose up -d backend

# Tests
pytest tests/ -v
```

---

## 11. Cấu Trúc Thư Mục

```
backend-service/
├── app/
│   ├── main.py          → App entry, middleware, router registration
│   ├── core/            → config, database, redis, middleware, exceptions
│   ├── models/          → SQLAlchemy ORM models
│   ├── schemas/         → Pydantic v2 schemas
│   ├── routes/          → API endpoints (24 route modules)
│   ├── services/        → Business logic services
│   ├── crud/            → Database CRUD operations
│   ├── clients/         → External service clients (AI service, etc.)
│   └── tasks/           → Celery/background tasks
├── alembic/             → Database migrations
├── tests/               → Pytest suite
├── requirements.txt
├── Dockerfile / Dockerfile.prod
└── render.yaml          → Render.com deployment config
```

---

*Tham khảo: [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-021](RPT-021_TRACECAG_ALGORITHM_FLOW.md) | [RPT-022](RPT-022_FLUTTER_APP_ARCHITECTURE.md)*
