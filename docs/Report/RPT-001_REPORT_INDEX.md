# RPT-001 — Mục Lục Báo Cáo LexiLingo

> **Cập nhật lần cuối:** 2026-04-24

---

## Mục Tiêu Tài Liệu

Bộ tài liệu Report được đánh mã theo thứ tự để theo dõi rõ lượng thông tin từ tổng quan đến triển khai kỹ thuật. Toàn bộ file trong thư mục này sử dụng quy ước `RPT-XXX_TEN_BAO_CAO.md`.

---

## Luồng Đọc Đề Xuất (RPT-001 → RPT-017 — Bộ Cũ)

| # | File | Mô tả |
|---|------|--------|
| 1 | `RPT-001_REPORT_INDEX.md` | Bản đồ luồng đọc báo cáo |
| 2 | `RPT-002_PROJECT_FUNCTIONAL_OVERVIEW.md` | Tổng quan chức năng và giá trị sản phẩm |
| 3 | `RPT-003_FLUTTER_FEATURE_REPORT.md` | Báo cáo đầy đủ chức năng Flutter theo góc nhìn người dùng |
| 4 | `RPT-004_FLUTTER_USER_FLOW_AND_NAVIGATION.md` | Bản đồ điều hướng và page reachability |
| 5 | `RPT-005_FLUTTER_MODULE_CATALOG.md` | Catalog module theo feature và trách nhiệm |
| 6 | `RPT-006_TECHNOLOGY_AND_ARCHITECTURE_REPORT.md` | Công nghệ, kiến trúc, data flow |
| 7 | `RPT-007_INSTALLATION_AND_OPERATION_GUIDE.md` | Cài đặt, chạy dịch vụ, vận hành thủ công |
| 8 | `RPT-008_DEPLOYMENT_CHECKLIST.md` | Checklist triển khai |
| 9 | `RPT-009_HYBRID_DEPLOYMENT_GUIDE.md` | Hướng dẫn hybrid deployment |
| 10 | `RPT-010_HYBRID_DEPLOYMENT_SUMMARY.md` | Tổng kết triển khai hybrid |
| 11 | `RPT-011_GIT_WORKFLOW.md` | Quy trình git cho team |
| 12 | `RPT-012_GIT_QUICK_REFERENCE.md` | Tra cứu git nhanh |
| 13 | `RPT-013_GIT_EXAMPLES.md` | Ví dụ thao tác git |
| 14 | `RPT-014_VPS_NGINX_SSL_DEPLOYMENT.md` | Báo cáo VPS, NGINX, SSL |
| 15 | `RPT-015_MVP_ARCHITECTURE.md` | Báo cáo kiến trúc MVP |
| 16 | `RPT-016_GRAPHCAG_KG_REDIS_CACHE.md` | Báo cáo TRACECAG/KG/Redis cache |
| 17 | `RPT-017_PROJECT_MASTER_REPORT.md` | Báo cáo tổng thể toàn dự án |

---

## 🆕 Tài Liệu Mới — Cập Nhật 2026-04-24

> Bộ tài liệu mới được phân tích toàn diện từ source code thực tế của dự án.

| # | File | Mô tả |
|---|------|--------|
| 18 | `RPT-018_FEATURE_ANALYSIS.md` | **Phân tích tính năng toàn diện** — AI, Learning, Gamification, Content, Voice |
| 19 | `RPT-019_AI_SERVICE_DEEP_DIVE.md` | **AI Service chuyên sâu** — TRACECAG, Model Gateway, Smart Router, toàn bộ AI services |
| 20 | `RPT-020_BACKEND_SERVICE_REPORT.md` | **Backend Service** — 24 route modules, services, kiến trúc database |
| 21 | `RPT-021_GRAPHCAG_ALGORITHM_FLOW.md` | **TRACECAG algorithm flow** — từng node, thuật toán cache, scoring metrics |
| 22 | `RPT-022_FLUTTER_APP_ARCHITECTURE.md` | **Kiến trúc Flutter app** — 28 providers, 21 features, navigation, dependencies |
| 23 | `RPT-023_TECHNOLOGY_STACK_AND_TOOLS.md` | **Technology stack & tools** — toàn bộ tech stack và các tools đặc biệt |
| 24 | `RPT-024_GAMES_ENGINE.md` | **Games Engine** — 6 mini-games, CEFR config, XP rewards |
| 25 | `RPT-025_GAMIFICATION_XP_SYSTEM.md` | **Gamification System** — XP, Streak, Wallet, Shop, Leaderboards |
| 26 | `RPT-026_SPACED_REPETITION_VOCABULARY.md` | **Spaced Repetition & Vocab** — Thuật toán SM-2, Mastery Score tracking |
| 27 | `RPT-027_PROFICIENCY_CEFR_ASSESSMENT.md` | **Proficiency CEFR Assessment** — Đánh giá đa kỹ năng, weight system |
| 28 | `RPT-028_REALWORLD_CONTENT_INTEGRATION.md` | **Real-world Content Integration** — Tích hợp NewsAPI & YouTube với AI |
| 29 | `RPT-029_FLUTTER_UI_FILE_INVENTORY.md` | **Kiểm kê file giao diện Flutter** — 158 file UI (trừ admin), độ ưu tiên đổi icon, trạng thái redesign |
| 0 | `RPT-000_UPDATE_SUMMARY.md` | **Tổng hợp cập nhật** — danh sách thay đổi và số liệu thống kê |
---

## Quy Tắc Bảo Trì

- Khi thêm báo cáo mới, sử dụng mã tiếp theo: `RPT-029`, `RPT-030`, ...
- Không đổi số các báo cáo đã phát hành để tránh vỡ liên kết nội bộ.
- Mỗi báo cáo nên có: mục đích, phạm vi, nội dung văn bản mô tả, danh sách giải pháp/kiểm tra/chốt triển khai.

## Phạm Vi Hiện Tại

Bộ Report bao phủ toàn bộ hệ thống LexiLingo: Flutter app, Backend service, AI service, Gateway, và các công cụ đặc biệt.
