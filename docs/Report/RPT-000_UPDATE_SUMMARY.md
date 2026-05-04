# RPT-000 — Tổng Hợp: Cập Nhật Bộ Tài Liệu LexiLingo

> **Cập nhật:** 2026-04-24 | Cập nhật toàn diện dựa trên phân tích source code thực tế

---

## Danh Sách Tài Liệu Đã Tồn Tại (RPT-001 → RPT-017)

| File | Tiêu Đề | Trạng Thái |
|------|---------|-----------  |
| RPT-001 | Report Index | Đã cập nhật dấu và bổ sung bảng |
| RPT-002 | Project Functional Overview | Đã cập nhật dấu và bổ sung luồng người dùng |
| RPT-003 | Flutter Feature Report | Đã cập nhật dấu và bổ sung bảng phases |
| RPT-004 | Flutter User Flow & Navigation | Đã cập nhật dấu và bổ sung bảng routes |
| RPT-005 | Flutter Module Catalog | Đã cập nhật dấu và bổ sung phân biệt chat/lexi |
| RPT-006 | Technology & Architecture Report | Đã cập nhật dấu và bổ sung bảng tech stack |
| RPT-007 | Installation & Operation Guide | Còn hiệu lực |
| RPT-008 | Deployment Checklist | Còn hiệu lực |
| RPT-009 | Hybrid Deployment Guide | Còn hiệu lực |
| RPT-010 | Hybrid Deployment Summary | Còn hiệu lực |
| RPT-011 | Git Workflow | Còn hiệu lực |
| RPT-012 | Git Quick Reference | Còn hiệu lực |
| RPT-013 | Git Examples | Còn hiệu lực |
| RPT-014 | VPS Nginx SSL Deployment | Còn hiệu lực |
| RPT-015 | MVP Architecture | Còn hiệu lực |
| RPT-016 | GraphCAG KG Redis Cache | Được thay thế chi tiết bởi RPT-021 |
| RPT-017 | Project Master Report | Đã cập nhật dấu và bổ sung bảng ưu tiên |

---

## Tài Liệu Mới (RPT-018 → RPT-028)

| File | Tiêu Đề | Nội Dung Chính |
|------|---------|----------------|
| **RPT-018** | Feature Analysis | Tất cả tính năng theo 7 nhóm category |
| **RPT-019** | AI Service Deep Dive | GraphCAG, Model Gateway, Smart Router, toàn bộ AI services |
| **RPT-020** | Backend Service Report | 24 route modules, services, kiến trúc database |
| **RPT-021** | GraphCAG Algorithm Flow | Node-by-node algorithm, RAPID cache, scoring metrics |
| **RPT-022** | Flutter App Architecture | 28 providers, 21 features, navigation, dependencies |
| **RPT-023** | Technology Stack & Tools | Toàn bộ tech stack và 7 special tools tự phát triển |
| **RPT-024** | Games Engine | 6 mini-games liên hoàn, bộ seed CEFR embedded trong DB |
| **RPT-025** | Gamification System | XP tracking, Streak bonus, Wallet system, Shop, Achievements |
| **RPT-026** | Spaced Repetition (SM-2) | Lịch học thông minh, chất lượng trả lời 0-5, Mastery Score |
| **RPT-027** | Proficiency Assessment | Logic tính điểm level CEFR theo trend, độ khó bài, 6 kỹ năng |
| **RPT-028** | Real-world Content (News/YT)| Fetch proxy, Web Scraping (trafilatura), subtitle parser (JSON3) |
---

## Tóm Tắt Phát Hiện Từ Phân Tích

### Tính Năng Nổi Bật
1. **GraphCAG Pipeline** — 11 nodes LangGraph với RAPID 2-level cache (L0/L1)
2. **Model Gateway** — Lazy loading, auto-unload theo idle timeout, smart routing
3. **Dual-Stream Voice** — STT/Thinking/TTS đồng thời, interruption handling
4. **CEFR Assessment** — 6 chiều đánh giá, chống XP grinding, exam-gated promotion
5. **SM-2 Spaced Repetition** — Lịch ôn tập tối ưu theo thuật toán SuperMemo 2
6. **HuBERT Pronunciation** — Phoneme-level analysis, Vietnamese error patterns

### Tools Đặc Biệt Được Phát Hiện
1. `jit_graph_service.py` — Just-In-Time graph construction
2. `evaluation_agent.py` — WER/NDCG/MRR metrics tự động
3. `retrieval_ranker.py` — Advanced retrieval ranking
4. `subgraph_hot_cache.py` — Pre-cached subgraphs phổ biến
5. `document_intelligence.py` — Phân tích nội dung thông minh
6. `topic_preloader.py` — Background topic warming
7. **GraphCAG Node Visualizer** — Debug tool tại `/visualizer`

### Số Liệu Thống Kê Dự Án

| Metric | Giá Trị |
|--------|---------|
| Backend route modules | 24 |
| AI service modules | 40+ |
| Flutter feature modules | 21 |
| Flutter providers (ChangeNotifier) | 28+ |
| LangGraph nodes | 11 |
| LangGraph edges | 6 conditional + direct |
| Flutter dependencies | 30+ packages |
| Backend dependencies | 20+ packages |
| AI dependencies | 30+ packages |
| Supported platforms | iOS, Android, Web, macOS, Linux, Windows |
