# Backend Optimization Plan

> Audit Date: 2026-03-06  
> Target: Hỗ trợ 10,000 concurrent users  
> Current State: Functional nhưng chưa sẵn sàng cho production scale

---

## 1. Tổng Quan Kết Quả Audit

### Điểm Mạnh Hiện Tại
- **Async architecture**: Toàn bộ FastAPI + SQLAlchemy async + asyncpg
- **SQL Injection**: 100% ORM-based, zero raw SQL → Xuất sắc
- **Authentication**: JWT + Firebase dual-auth, bcrypt password hashing
- **RBAC**: Role-based access control (user/admin/super_admin)
- **Token lifecycle**: Access/refresh/verification tokens với type markers
- **Pagination**: Offset/limit có max page_size=100
- **Database indexes**: Composite indexes trên các bảng chính
- **Error handling**: Global middleware + standardized response envelopes
- **Logging**: Request ID, response time, per-request logging

### Vấn Đề Cần Giải Quyết

| Severity | Mã | Vấn đề | Impact |
|----------|-----|--------|--------|
| 🔴 Critical | C1 | Rate limiter in-memory, không distributed | Multi-instance bypass hoàn toàn |
| 🔴 Critical | C2 | Không response caching | Mỗi request đều hit DB |
| 🟠 High | H1 | N+1 query: courses list `is_enrolled` loop | 100 courses = 100 queries |
| 🟠 High | H2 | N+1 query: course detail `is_lesson_completed` loop | N lessons × M prereqs queries |
| 🟠 High | H3 | N+1 query: progress `get_course` loop | 10 progress = 10 queries |
| 🟠 High | H4 | Thiếu login brute-force protection | 60 password guesses/min/IP |
| 🟡 Medium | M1 | `datetime.utcnow()` deprecated Python 3.12+ | Future compatibility |
| 🟡 Medium | M2 | Rate limiter memory leak (no background cleanup) | RAM growth over time |
| 🟡 Medium | M3 | Thiếu request body size limit | Memory exhaustion risk |
| 🟡 Medium | M4 | Token blacklist fail-open khi Redis down | Security gap |

---

## 2. Capacity Analysis (Current vs Target)

```
Current Capacity:
  DB Pool: 20 + 10 overflow = 30 max connections
  Avg query: ~50ms
  Throughput: ~600 req/s (lý tưởng, không N+1)
  Actual: ~200-300 req/s (do N+1 hotspots)

Target (10k users, 10% concurrent):
  Peak concurrent: ~1,000 users
  Requests/sec: ~500-1000 req/s (assuming 1 req/sec/user)
  Required DB pool: 50-100 connections
  Required caching: Hot endpoints cached 30-60s
```

---

## 3. Kế Hoạch Thực Hiện (4 Phases)

### Phase 1: Security & Resilience (Critical) ✅ **HOÀN THÀNH**
> Mục tiêu: Production-ready security, chống DDoS

| Task | File | Mô tả | Status |
|------|------|--------|--------|
| 1.1 | `app/core/middleware.py` | Migrate rate limiter sang Redis-backed (distributed) | ✅ Done |
| 1.2 | `app/core/middleware.py` | Thêm login-specific rate limit (10 req/min cho `/auth/login`) | ✅ Done |
| 1.3 | `app/main.py` | Init/close Redis trong lifespan | ✅ Done |
| 1.4 | `app/core/middleware.py` | In-memory fallback khi Redis unavailable | ✅ Done |

### Phase 2: Query Optimization (High Impact) ✅ **HOÀN THÀNH**
> Mục tiêu: Eliminate N+1 queries, giảm DB load 5-10x

| Task | File | Mô tả | Status |
|------|------|--------|--------|
| 2.1 | `app/crud/course.py` | Thêm `get_enrolled_course_ids(user_id, course_ids)` batch query | ✅ Done |
| 2.2 | `app/routes/courses.py` | Dùng batch enrollment check thay vì loop | ✅ Done |
| 2.3 | `app/crud/course.py` | Thêm `get_completed_lesson_ids(user_id, lesson_ids)` batch query | ✅ Done |
| 2.4 | `app/routes/courses.py` | Pre-fetch all lesson completions for course detail | ✅ Done |
| 2.5 | `app/crud/progress.py` | Thêm `get_user_progress_with_courses()` JOIN query | ✅ Done |
| 2.6 | `app/routes/progress.py` | Dùng JOIN thay vì loop get_course | ✅ Done |

### Phase 3: Response Caching (Scale) ✅ **HOÀN THÀNH**
> Mục tiêu: Giảm DB hits 80% cho hot endpoints

| Task | File | Mô tả | Status |
|------|------|--------|--------|
| 3.1 | `app/core/cache.py` | Tạo Redis cache utilities (build_cache_key, get_cached, set_cached, invalidate_cache) | ✅ Done |
| 3.2 | `app/routes/courses.py` | Cache courses list public data (TTL 60s), overlay enrollment per-user | ✅ Done |
| 3.3 | `app/routes/vocabulary.py` | Cache vocabulary items with JSONResponse + Cache-Control (TTL 120s) | ✅ Done |
| 3.4 | `app/routes/vocabulary.py` | Cache-Control: public, max-age=120 header cho cached responses | ✅ Done |

### Phase 4: Infrastructure Tuning ✅ **HOÀN THÀNH**
> Mục tiêu: Fine-tune cho 10k users

| Task | File | Mô tả | Status |
|------|------|--------|--------|
| 4.1 | `app/core/config.py`, `database.py` | Prod config: effective_pool_size=50, effective_max_overflow=20 (property-based) | ✅ Done |
| 4.2 | `app/main.py` | Request body size limit middleware (10MB, Content-Length check) | ✅ Done |
| 4.3 | 22 files + 12 models + 1 schema | Migrate `datetime.utcnow()` → `datetime.now(timezone.utc)` (86 occurrences total) | ✅ Done |
| 4.4 | `app/main.py`, `Dockerfile` | Uvicorn workers = CPU cores × 2 + 1 (prod), UVICORN_WORKERS env override | ✅ Done |

---

## 4. Estimated Impact

| Phase | DB Load Reduction | Security Improvement | Effort |
|-------|-------------------|---------------------|--------|
| Phase 1 | - | Distributed rate limit + brute-force protection | 2-3h |
| Phase 2 | -70% query count | - | 3-4h |
| Phase 3 | -80% DB hits (hot paths) | - | 2-3h |
| Phase 4 | Connection scaling | Request size protection | 1-2h |

**Tổng effort: ~8-12h cho toàn bộ optimization.**

---

## 5. Metrics Cần Monitor Sau Optimization

- Response time P95 / P99 (target < 200ms)
- DB connection pool utilization (target < 70%)
- Redis memory usage
- Rate limit 429 responses/hour
- Cache hit ratio (target > 80%)
- Failed login attempts/IP/hour
