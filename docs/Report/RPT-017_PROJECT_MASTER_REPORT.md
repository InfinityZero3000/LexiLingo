# RPT-017 — Báo Cáo Tổng Thể Dự Án LexiLingo

> **Cập nhật:** 2026-04-24 | Xem bộ báo cáo mới RPT-018→RPT-023 để có phân tích chi tiết hơn.

---

## 1. Mục Tiêu Tài Liệu

Tài liệu này là báo cáo tổng thể toàn bộ hệ thống LexiLingo ở mức độ kiến trúc, vận hành, phát triển, kiểm thử và debt kỹ thuật. Phạm vi bao gồm toàn bộ các khối: Flutter, Backend, AI, Gateway, Admin, model-development (finetune/benchmark), deployment scripts và tài liệu support.

---

## 2. Toàn Cảnh Monorepo

Khối monorepo hiện tại gồm **4 dịch vụ runtime chính:**
- Flutter app: [flutter-app](../../flutter-app)
- Backend service: [backend-service](../../backend-service)
- AI service: [ai-service](../../ai-service)
- Admin service: [admin-service](../../admin-service)

**Khối hạ tầng và điều phối:**
- Gateway/API edge: [gateway](../../gateway)
- Docker stack: [docker-compose.yml](../../docker-compose.yml), [docker-compose.local.yml](../../docker-compose.local.yml), [docker-compose.production.yml](../../docker-compose.production.yml)
- DevOps scripts: [scripts](../../scripts)
- System testing: [system-testing](../../system-testing)

---

## 3. Kiến Trúc Runtime Tổng Quan

### 3.1 Luồng Chính

1. Flutter gửi request đến Backend (auth, profile, course, progress) và AI service (chat, voice, phân tích).
2. Backend xử lý nghiệp vụ học tập trên PostgreSQL, có Redis middleware cho rate limit/cache.
3. AI service xử lý TRACECAG pipeline, model routing và STT/TTS, liên kết KG (KuzuDB).
4. Gateway (Kong/Nginx) đóng vai trò edge routing, CORS, rate limit và observability.

### 3.2 Công Nghệ Từng Khối

| Khối | Stack |
|------|-------|
| Flutter | Dart/Flutter + Provider + GetIt + Firebase |
| Backend | FastAPI + SQLAlchemy + Alembic + Redis + Firebase Auth |
| AI | FastAPI + TRACECAG + KuzuDB + Whisper/Piper/HuBERT + Model Gateway |
| Admin | React + Vite + TypeScript |

---

## 4. Flutter App (Frontend Học Tập)

### 4.1 Entry và Wiring
- Entry app và route map: [flutter-app/lib/main.dart](../../flutter-app/lib/main.dart)
- DI container: [flutter-app/lib/core/di/injection_container.dart](../../flutter-app/lib/core/di/injection_container.dart)
- Theme: [flutter-app/lib/core/theme](../../flutter-app/lib/core/theme)

### 4.2 Feature Architecture
App tổ chức theo feature module trong [flutter-app/lib/features](../../flutter-app/lib/features), mỗi khối theo hướng domain/data/presentation. Các nhóm lớn:
- auth, user, profile
- course, learning, progress, level
- vocabulary, chat, lexi_chat, voice
- news, podcast, books, games, youtube
- gamification, achievements, social, notifications

### 4.3 State Management và API
- Provider được đăng ký loạt trong [flutter-app/lib/main.dart](../../flutter-app/lib/main.dart)
- API config/client ở [flutter-app/lib/core/network/api_config.dart](../../flutter-app/lib/core/network/api_config.dart) và [flutter-app/lib/core/network/api_client.dart](../../flutter-app/lib/core/network/api_client.dart)
- Named routes được khai báo tại [flutter-app/lib/main.dart](../../flutter-app/lib/main.dart)

### 4.4 Build và Release
- Cấu hình package: [flutter-app/pubspec.yaml](../../flutter-app/pubspec.yaml)
- Rule static analysis: [flutter-app/analysis_options.yaml](../../flutter-app/analysis_options.yaml)
- Deploy web: [flutter-app/vercel.json](../../flutter-app/vercel.json)

---

## 5. Backend Service (Nghiệp Vụ và Dữ Liệu)

### 5.1 Cấu Trúc App
- App entry + middleware + router include: [backend-service/app/main.py](../../backend-service/app/main.py)
- Core config/deps/middleware: [backend-service/app/core](../../backend-service/app/core)
- ORM models: [backend-service/app/models](../../backend-service/app/models)
- Schemas: [backend-service/app/schemas](../../backend-service/app/schemas)
- Routes: [backend-service/app/routes](../../backend-service/app/routes)
- Services nghiệp vụ: [backend-service/app/services](../../backend-service/app/services)

### 5.2 Domain Nghiệp Vụ Chính
- Auth + user management
- Course/learning/progress
- Vocabulary + spaced repetition (SM-2)
- Gamification/achievements/XP/leaderboard
- Content channels: books/news/podcasts/games/youtube
- Proficiency assessment (CEFR)

### 5.3 Database và Migration
- Alembic versions: [backend-service/alembic/versions](../../backend-service/alembic/versions)
- Config migration: [backend-service/alembic.ini](../../backend-service/alembic.ini)
- Dữ liệu chính trên PostgreSQL

---

## 6. AI Service (TRACECAG và Model Stack)

### 6.1 App và Routes
- AI app entry: [ai-service/api/main.py](../../ai-service/api/main.py)
- API routes: [ai-service/api/routes](../../ai-service/api/routes)

### 6.2 TRACECAG Pipeline
- State: [ai-service/api/services/graph_cag/state.py](../../ai-service/api/services/graph_cag/state.py)
- Nodes v2: [ai-service/api/services/graph_cag/nodes_v2.py](../../ai-service/api/services/graph_cag/nodes_v2.py)
- Edges/routing: [ai-service/api/services/graph_cag/edges.py](../../ai-service/api/services/graph_cag/edges.py)
- Graph compile: [ai-service/api/services/graph_cag/graph.py](../../ai-service/api/services/graph_cag/graph.py)

Pipeline logic theo flow: input → kg expand → diagnose → retrieve → generate (và các nhánh voice/pronunciation tùy route).

### 6.3 Model Gateway và Các Service AI
- Model router/lazy loading: [ai-service/api/services/model_gateway.py](../../ai-service/api/services/model_gateway.py)
- KG service V3 (KuzuDB): [ai-service/api/services/kg_service_v3.py](../../ai-service/api/services/kg_service_v3.py)
- STT: [ai-service/api/services/stt_service.py](../../ai-service/api/services/stt_service.py)
- TTS: [ai-service/api/services/tts_service.py](../../ai-service/api/services/tts_service.py)
- Pronunciation/HuBERT: [ai-service/api/services/hubert_service.py](../../ai-service/api/services/hubert_service.py)
- Retrieval: [ai-service/api/services/retrieval_service_v3.py](../../ai-service/api/services/retrieval_service_v3.py)

### 6.4 MCP Runtime
Tài liệu instruction xác nhận MCP runtime HTTP trong [ai-service/api/mcp](../../ai-service/api/mcp), sử dụng cho tool calls như `analyze_text`, `assess_level`, `expand_concepts`.

---

## 7. Finetune, Benchmark, Model-Development

Khối model-development nằm trong AI service tại [ai-service/model-development](../../ai-service/model-development), gồm:
- Benchmark public QA: [ai-service/model-development/benchmark](../../ai-service/model-development/benchmark)
- Datasets: [ai-service/model-development/datasets](../../ai-service/model-development/datasets)
- Export scripts: [ai-service/model-development/export](../../ai-service/model-development/export)
- Notebook huấn luyện LoRA: [ai-service/model-development/notebook](../../ai-service/model-development/notebook)
- Tool scripts crawl/download/merge/eval: [ai-service/model-development/scripts](../../ai-service/model-development/scripts)

**Định hướng hiện tại:** Benchmark và finetune đã tồn tại như một pipeline R&D bên trong AI service, chưa tách thành service runtime riêng.

---

## 8. Gateway và Edge Layer

### 8.1 Thành Phần
- Kong config: [gateway/kong](../../gateway/kong)
- Nginx config: [gateway/nginx](../../gateway/nginx)
- Cloudflare/APIM wrappers: [gateway/cloudflare](../../gateway/cloudflare), [gateway/apim](../../gateway/apim)
- Observability stack: [gateway/observability](../../gateway/observability)

### 8.2 Chức Năng
- Route backend/ai
- CORS/rate limit/plugin chain qua Kong
- SSL termination/proxy qua Nginx
- Metrics/traces dashboard qua observability stack (Prometheus + Grafana)

---

## 9. Admin Service

- Stack và source: [admin-service/src](../../admin-service/src)
- Build config: [admin-service/vite.config.ts](../../admin-service/vite.config.ts)
- Dependency manifest: [admin-service/package.json](../../admin-service/package.json)

Admin dashboard hiện là khối tách riêng, phụ trách công cụ vận hành/nội dung, và đồng bộ qua API backend.

---

## 10. DevOps và Deployment

### 10.1 Docker
- Full stack local: [docker-compose.yml](../../docker-compose.yml)
- AI local profile: [docker-compose.local.yml](../../docker-compose.local.yml)
- Production profile: [docker-compose.production.yml](../../docker-compose.production.yml)

### 10.2 Scripts Vận Hành
- Setup/start/stop/dev: [scripts/setup-all.sh](../../scripts/setup-all.sh), [scripts/start-all.sh](../../scripts/start-all.sh), [scripts/stop-all.sh](../../scripts/stop-all.sh), [scripts/dev.sh](../../scripts/dev.sh)
- Deploy: [scripts/deploy-hybrid.sh](../../scripts/deploy-hybrid.sh), [scripts/deploy-admin.sh](../../scripts/deploy-admin.sh), [scripts/deploy-admin-vercel.sh](../../scripts/deploy-admin-vercel.sh)
- Mac daemon support: [scripts/setup-launchd.sh](../../scripts/setup-launchd.sh)

### 10.3 Systemd/Deploy Support
- Service unit templates: [deploy/systemd](../../deploy/systemd)
- Security/hardening docs: [deploy/fail2ban](../../deploy/fail2ban)

---

## 11. Testing và Quality Strategy

### 11.1 Backend
- Pytest suite: [backend-service/tests](../../backend-service/tests)

### 11.2 AI
- AI tests: [ai-service/tests](../../ai-service/tests)
- Postman collection: [ai-service/postman](../../ai-service/postman)
- Benchmark reports: [ai-service/model-development/benchmark/reports](../../ai-service/model-development/benchmark/reports)

### 11.3 Flutter
- Tests: [flutter-app/test](../../flutter-app/test)
- Coverage output: [flutter-app/coverage](../../flutter-app/coverage)

### 11.4 System-Level
- End-to-end/load harness: [system-testing](../../system-testing)

---

## 12. Technical Debt và Rủi Ro Quan Trọng

### 12.1 Debt Đã Được Ghi Nhận Rõ Ràng

Theo instruction nội bộ [copilot-instructions.md](../../.github/copilot-instructions.md):
- Cache fast-path TRACECAG chưa wired (`check_cache_hit` có tồn tại nhưng chưa được nối flow)
- `nodes.py` (v1) là dead path, pipeline dùng `nodes_v2.py`
- KG service từng có issue re-seed database khi restart
- MCP URI naming chưa đồng nhất
- Tài liệu kiến trúc và tên model có điểm lệch version

### 12.2 Rủi Ro Bảo Mật/Hygiene

> ⚠️ **Cảnh báo bảo mật:** Có file Firebase service account JSON trong repo backend:
> - [backend-service/firebase-service-account.json](../../backend-service/firebase-service-account.json)
> - [backend-service/lexilingo-88492-firebase-adminsdk-fbsvc-733f43b698.json](../../backend-service/lexilingo-88492-firebase-adminsdk-fbsvc-733f43b698.json)

**Khuyến nghị:** Chuyển hoàn toàn sang secret manager/env injection, bỏ khỏi git history nếu có thể.

---

## 13. Đánh Giá Mức Độ Sẵn Sàng Hiện Tại

### 13.1 Điểm Mạnh
- Kiến trúc tách service rõ ràng, dễ scale theo khối
- Flutter feature-rich và có tổ chức module theo domain
- Backend routes/ORM/schemas có độ phủ cao
- AI service có pipeline TRACECAG rõ ràng và bộ model stack đầy đủ
- Đã có benchmark/system-testing scripts phục vụ đánh giá năng lực

### 13.2 Điểm Cần Ưu Tiên

| Ưu Tiên | Hành Động |
|---------|----------|
| 🔴 Cao | Chốt và cleanup debt trong TRACECAG (cache fast path, v1 dead code) |
| 🔴 Cao | Secret hygiene và quy trình rotation |
| 🟡 Trung | Chuẩn hóa MCP contracts và tài liệu runtime/coding-time |
| 🟢 Thấp | Chuẩn hóa tài liệu tổng thể theo một bộ report duy nhất |

---

## 14. Kế Hoạch Tài Liệu Đề Nghị (Bản Tối Ưu)

Để bộ tài liệu quy củ và bảo trì dễ, nên duy trì nhóm report sau:

1. Tổng quan kiến trúc hệ thống
2. Flutter architecture + user flow
3. Backend domains + API map
4. AI pipeline + model gateway + KG
5. Finetune/benchmark pipeline
6. Gateway + security edge
7. Deployment runbook
8. Testing strategy + SLO
9. Known issues + remediation roadmap
10. Security checklist + secrets policy

> Tài liệu RPT-017 này đóng vai trò master map; các tài liệu RPT-001 → RPT-016 là chi tiết theo chủ đề. **Bộ RPT-018 → RPT-023 là phân tích kỹ thuật cập nhật nhất.**

---

## 15. Kết Luận

LexiLingo đang ở trạng thái monorepo đã vượt ngưỡng MVP có cấu trúc: đã có hệ thống học tập đầy đủ, AI tutoring pipeline và deployment stack khá dày. Việc cần làm tiếp theo không phải là bổ sung tính năng bằng mọi giá, mà là chuẩn hóa vận hành, debt cleanup, bảo mật secret, và đồng bộ tài liệu kỹ thuật để team scale bền vững.

---

*Tham khảo: [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md) | [RPT-021](RPT-021_TRACECAG_ALGORITHM_FLOW.md)*
