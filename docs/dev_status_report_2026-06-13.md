# LexiLingo — Báo Cáo Tổng Hợp Phát Triển
**Ngày:** 2026-06-13  
**Branch:** `dev`  
**Người tổng hợp:** Auto-generated từ logs & git history

---

## 1. Tổng Quan Hệ Thống

| Service | Trạng thái | Ghi chú |
|---------|-----------|---------|
| Backend (FastAPI) | ⚠️ Lỗi khởi động | `DEBUG=True` khi `APP_ENV=production` |
| AI Service (FastAPI) | ⚠️ Lỗi khởi động | `DEBUG=True` khi `ENVIRONMENT=production` |
| Admin Dashboard (Vite) | ✅ Chạy bình thường | Port 5176 (2026-06-02) |
| PostgreSQL (Docker) | ✅ Đã fix | Docker socket issue đã được giải quyết |
| Redis | ✅ OK | Kéo image thành công |
| MongoDB | ✅ OK | Kéo image thành công |

---

## 2. Lỗi Tìm Thấy Trong Logs

### 2.1 Backend Service — `logs/backend.log`

**Lỗi:** `pydantic_core.ValidationError` khi khởi động

```
Value error, DEBUG must be false when APP_ENV=production
```

**Nguyên nhân:** File `.env` đặt `DEBUG=True` nhưng `APP_ENV=production`.  
**Fix:** Đặt `DEBUG=False` trong `.env` khi chạy production, hoặc dùng `.env.development` cho môi trường local.

### 2.2 AI Service — `logs/ai-service.log`

**Lỗi:** Tương tự backend service

```
Value error, DEBUG must be false when ENVIRONMENT=production
```

**Fix:** Tương tự — kiểm tra `ENVIRONMENT` và `DEBUG` trong `.env` của ai-service.

### 2.3 PostgreSQL — `logs/postgres.log`

**Lỗi ban đầu:** Docker daemon không chạy (socket `/Users/nguyenhuuthang/.docker/run/docker.sock` không tồn tại).  
**Trạng thái cuối:** Container `lexilingo-postgres` đã khởi động thành công sau khi Docker daemon được kích hoạt.

### 2.4 Admin Dashboard — `logs/admin.log`

**Trạng thái:** ✅ Khởi động thành công lúc 17:25 ngày 2026-06-02, port 5176, VITE v8.0.15.

---

## 3. TRACE-CAG Benchmark — Tóm Tắt Kết Quả

> **Chi tiết đầy đủ:** xem [tracecag_benchmark_report_2026-06-03.md](../ai-service/docs/tracecag_benchmark_report_2026-06-03.md)

### 3.1 Tổng quan 3 Lần Chạy

| Run | Ngày | Model | n | Datasets | Trạng thái |
|-----|------|-------|---|----------|-----------|
| Run 1 | 2026-05-30 | llama-3.1-8b-instant | 20 | 3 datasets | ⚠️ Quota exhaustion (hotpotqa, musique) |
| Run 2 | 2026-05-31 | llama-3.1-8b-instant | 20 | 3 datasets | ✅ Đầy đủ |
| Run 3 | 2026-06-03 | **llama-3.3-70b-versatile** | 5 | hotpotqa | ✅ Validation (n nhỏ) |

### 3.2 Kết Quả Tốt Nhất (Run 2, trung bình 3 datasets)

| Mode | EM avg | F1 avg | MRR@5 avg | Cache hit | Latency avg |
|------|--------|--------|-----------|-----------|-------------|
| cag_vanilla | 15.0% | 23.8% | 72.1% | 34.2% | 1960ms |
| hipporag_proxy | 18.3% | 27.1% | 69.7% | 0% | 3053ms |
| **tracecag_rapid** | **18.3%** | **27.3%** | **72.6%** | 30.8% | **2086ms** |

**Kết luận:** TRACE-CAG dẫn đầu MRR@5, cạnh tranh EM/F1 với hipporag, nhanh hơn 32%, có cache.

### 3.3 Thành Tựu Nổi Bật (Run 3)

- **Warm hit rate = 100%** sau khi fix threshold cache (was 65-85%)
- **P50 cached = 17–29ms** vs cold ~3200ms → speedup **~110–190x**
- **KG enrichment:** 4,280 → 5,173 concepts (+929 Wikipedia entities từ HotpotQA/2Wiki)
- Model **llama-3.3-70b-versatile** xác nhận hoạt động

### 3.4 Việc Cần Làm Tiếp

| Priority | Action |
|----------|--------|
| HIGH | n=20+ với 70b model, seed=42 (Run 3 n=5 quá nhỏ) |
| HIGH | Chạy `query_clusters` benchmark để đo L1 cache (hiện 0%) |
| MEDIUM | Test `tracecag_adaptive` profile |
| MEDIUM | Expand KG seeding (tăng `--max-samples 256`) |

---

## 4. Thay Đổi Code Trong Đợt Này

### 4.1 AI Service — Xóa modules lỗi thời

Các module sau đã bị xóa do refactor:

| Module | Lý do xóa |
|--------|-----------|
| `api/routes/user.py` | Chuyển sang backend-service |
| `api/routes/websocket_simple.py` | Thay bằng SSE |
| `api/routes/websocket_stream.py` | Thay bằng SSE |
| `api/services/dual_stream/` (toàn bộ) | Thay bằng SSE pipeline |
| `api/services/dl_model_service.py` | Deprecated |
| `api/services/fallback.py` | Hợp nhất vào model_gateway |
| `api/services/llama_vietnamese_service.py` | Deprecated |
| `api/services/qwen_engine.py` | Deprecated |
| `api/services/report_service.py` | Deprecated |
| `api/services/resource_manager.py` | Deprecated |
| `api/services/smart_router.py` | Hợp nhất vào model_gateway |
| `api/services/spaced_repetition_service.py` | Chuyển sang backend |

### 4.2 Flutter Admin — Toàn bộ bị xóa

`flutter-admin/` đã bị xóa hoàn toàn (đã chuyển sang Vite/React admin dashboard).

### 4.3 TRACE-CAG — Modules mới

| File | Mô tả |
|------|-------|
| `api/services/trace_cag/benchmark/` | Benchmark utilities (adaptive, qa_generation, quality, ranking) |
| `api/services/trace_cag/cache_utils.py` | Cache utilities |
| `api/services/trace_cag/env_helpers.py` | Environment helpers |
| `api/services/trace_cag/kg_utils.py` | KG utilities |
| `api/services/trace_cag/llm_client.py` | LLM client |
| `api/services/trace_cag/provider_state.py` | Provider state management |
| `tests/benchmark/` | Benchmark test suite |
| `tests/trace_cag/test_cache_gate_benchmark_metadata.py` | Cache gate metadata tests |

### 4.4 Backend Service — Cập nhật routes

Các routes đã được cập nhật: `ai_audit.py`, `learning.py`, `proficiency.py`, `progress.py`, `user_management.py`, `rbac.py`, `item_effects_service.py`.

---

## 5. Git Cleanup — Tóm Tắt

### Files đã được gitignore (mới thêm):

```
.claude/worktrees/       # Temporary Claude Code agent workspaces
.claire/                 # Local tool cache
ai-service/.crawl4ai/    # Web crawler cache
ai-service/data/kuzu_db  # KuzuDB runtime database (generated)
ai-service/data/kg_output/ # Generated KG artifacts (144MB)
ai-service/data/sample_stories.expanded.json
```

### Files cần xóa (chờ xác nhận):

- `ai-service/docs/tracecag_benchmark_report_2026-05-30.md` — superseded bởi report 2026-06-03
- `ai-service/docs/tracecag_benchmark_report_2026-05-31.md` — superseded bởi report 2026-06-03
- `.claude/worktrees/agent-a2e02f9977edbf924/` — old agent worktree (duplicate files)
- `ai-service/.crawl4ai/` — crawler cache (gitignored, có thể xóa local)

---

## 6. Vấn Đề Cấu Hình Cần Giải Quyết

1. **DEBUG mode:** Đảm bảo `.env` của backend và ai-service không set `DEBUG=True` khi `APP_ENV/ENVIRONMENT=production`.
2. **Docker daemon:** Cần bật Docker Desktop trước khi chạy `docker-compose`.
3. **L1 cache benchmark:** Dataset `query_clusters` đã sẵn sàng — cần chạy benchmark để đo L1 hit rate thực tế.
4. **Run 4 TRACE-CAG:** Cần chạy full benchmark n=20 với model 70b để xác nhận kết quả Run 3 (n=5).

---

*Báo cáo được tổng hợp từ: `logs/` (backend.log, ai-service.log, admin.log, postgres.log, databases.log) và `ai-service/docs/tracecag_benchmark_report_*.md`. Ngày tổng hợp: 2026-06-13.*
