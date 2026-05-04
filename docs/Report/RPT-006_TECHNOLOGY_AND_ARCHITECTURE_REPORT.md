# RPT-006 — Báo Cáo Kiến Trúc và Công Nghệ

> **Cập nhật:** 2026-04-24 | Được thay thế chi tiết bởi [RPT-023](RPT-023_TECHNOLOGY_STACK_AND_TOOLS.md)

---

## 1. Tóm Tắt Kiến Trúc

LexiLingo sử dụng mô hình microservices kết hợp client Flutter. Flutter app đóng vai trò giao diện đa nền tảng, `backend-service` phụ trách nghiệp vụ người dùng/lộ trình/progress, `ai-service` phụ trách GraphCAG và các năng lực AI (chat, phát âm, voice).

```
Flutter App (iOS/Android/Web)
        │
        ├─── Backend Service (FastAPI + PostgreSQL + Redis)
        │     Auth, Users, Courses, Progress, Gamification, Content
        │
        └─── AI Service (FastAPI + MongoDB + Redis + KuzuDB)
              GraphCAG Pipeline, Model Gateway, STT/TTS, Pronunciation
```

---

## 2. Công Nghệ Phía Flutter

### 2.1 Nền Tảng
- Flutter 3.24+ / Dart SDK ^3.8.1
- Hỗ trợ iOS, Android, Web, macOS, Linux, Windows

### 2.2 Quản Lý State và Dependency
- **Provider** cho state management (28+ ChangeNotifier providers)
- **GetIt** cho dependency injection

### 2.3 Kết Nối và Lưu Trữ
- HTTP client (Dio-based custom `ApiClient`) cho REST
- Firebase Auth / Google Sign-In / Facebook Auth
- SharedPreferences + Flutter Secure Storage
- SQLite (`sqflite`) cho dữ liệu local, offline sync queue

### 2.4 Tương Tác Media và Nội Dung
- `google_generative_ai` cho Gemini integration
- `record`, `just_audio`, `audio_service` cho voice/audio
- `flutter_markdown`, `flutter_svg`, `cached_network_image` cho rendering nội dung
- WebSocket channel cho voice streaming real-time

---

## 3. Công Nghệ Backend Service

| Thành phần | Công nghệ |
|-----------|---------|
| Framework | FastAPI (async) + Uvicorn |
| Database | PostgreSQL 14+ + SQLAlchemy async |
| Schema migration | Alembic |
| Validation | Pydantic v2 |
| Cache | Redis (rate limiting, token blacklist, API cache) |
| Auth | JWT (python-jose) + Firebase Admin SDK |

---

## 4. Công Nghệ AI Service

| Thành phần | Công nghệ |
|-----------|---------|
| Orchestration | LangGraph StateGraph |
| Knowledge Graph | KuzuDB (embedded) |
| LLM | Gemini API (cloud) + Ollama/Qwen3 (local) |
| STT | Faster-Whisper |
| TTS | Piper TTS + gTTS |
| Pronunciation | HuBERT-large (Facebook) |
| Embeddings | Sentence-Transformers (MiniLM) |
| DB | MongoDB (chat sessions) + Redis (cache/CAG) |

---

## 5. Kiến Trúc Theo Lớp (Flutter)

Mô hình chính được tổ chức theo hướng **Clean Architecture** trong mỗi feature:

```
Domain Layer
  ├─ Entities (Pure Dart, no dependencies)
  ├─ Repository Interfaces
  └─ Use Cases (single responsibility)

Data Layer
  ├─ Repository Implementations
  ├─ Remote DataSources (Dio → API)
  └─ Local DataSources (SQLite/SharedPrefs)

Presentation Layer
  ├─ Pages / Screens
  ├─ Providers (ChangeNotifier)
  └─ Widgets
```

**Lợi ích:**
- Giảm phụ thuộc trực tiếp vào API implementation.
- Dễ viết test theo usecase.
- Dễ thay đổi backend mà không phá vỡ toàn bộ UI.

---

## 6. Data Flow Tương Tác

Từ góc nhìn runtime, luồng cơ bản:
1. User thao tác trên UI.
2. Provider nhận event và gọi usecase.
3. Usecase sử dụng repository interface.
4. Repository implementation điều phối datasource remote/local.
5. Kết quả trả về presentation để update UI.

---

## 7. Tích Hợp Backend và AI

- **Backend service**: xử lý user profile, course, progress, auth state.
- **AI service**: xử lý chat, phân tích ngôn ngữ, voice và các thành phần GraphCAG.
- Flutter app phối hợp 2 kênh này để tạo trải nghiệm học liền mạch.

---

## 8. Nhận Xét Kiến Trúc Hiện Tại

Kiến trúc đủ hiện đại, dễ mở rộng, và phù hợp bối cảnh MVP có nhiều tính năng. Điểm cần tiếp tục quan tâm là:
- Chuẩn hóa naming giữa các feature `chat`/`lexi_chat`.
- Duy trì route map cập nhật liên tục khi thêm màn hình mới.
- Tăng cường tài liệu liên kết giữa feature và endpoint backend/ai.

---

## 9. Khuyến Nghị

- Duy trì một "architecture decision log" ngắn cho các thay đổi lớn.
- Tạo bộ integration test theo luồng user quan trọng: Auth → Learning → Progress.
- Độc lập và version hóa environment config theo từng môi trường (dev/staging/prod).

---

*Tham khảo chi tiết: [RPT-023](RPT-023_TECHNOLOGY_STACK_AND_TOOLS.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md)*
