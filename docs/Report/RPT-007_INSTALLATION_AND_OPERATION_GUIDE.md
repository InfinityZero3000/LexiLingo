# RPT-007 — Hướng Dẫn Cài Đặt và Vận Hành LexiLingo

> **Cập nhật:** 2026-04-24

---

## 1. Mục Tiêu

Tài liệu này hướng dẫn cài đặt và vận hành bộ Flutter app trong ngữ cảnh đầy đủ của dự án LexiLingo (backend + ai-service).

---

## 2. Điều Kiện Tiên Quyết

### 2.1 Công Cụ

| Công cụ | Phiên bản | Mục đích |
|---------|----------|---------|
| Flutter SDK | 3.24+ | Flutter app |
| Dart SDK | ^3.8.1 (đi kèm Flutter) | Dart runtime |
| Python | 3.11+ | Backend service và AI service |
| Git | Mới nhất | Quản lý code |
| Docker (tùy chọn) | 24+ | Chạy toàn bộ stack qua Docker Compose |
| Ollama (tùy chọn) | Mới nhất | Chạy LLM local |

### 2.2 Môi Trường Dự Án

Cần clone đầy đủ repository và đảm bảo có các thư mục:
- `flutter-app/`
- `backend-service/`
- `ai-service/`

Cấu hình file `.env` cho từng service (xem `.env.example` trong mỗi thư mục).

---

## 3. Cài Đặt Phần Flutter

Trong thư mục `flutter-app`:

```bash
# 1. Cài dependencies
flutter pub get

# 2. Kiểm tra cấu hình
cp .env.example .env         # Tạo .env nếu chưa có
# Sửa BACKEND_URL và AI_SERVICE_URL trong .env

# 3. Phân tích mã nguồn
flutter analyze

# 4. Chạy test
flutter test
```

**Chú ý cho web:** File `.env` và `.env.production` cần đặt đúng URL của backend và AI service.

---

## 4. Khởi Động Các Service Backend

### 4.1 Backend Service (Port 8000)

**Qua VS Code task:**
```
Run task: "Run Backend Service"
```

**Thủ công qua terminal:**
```bash
cd backend-service
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # Cấu hình DATABASE_URL, REDIS_URL, FIREBASE_PROJECT_ID

# Chạy migrations
alembic upgrade head

# Khởi động server
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Kiểm tra:** `curl http://localhost:8000/health`

### 4.2 AI Service (Port 8001)

**Qua VS Code task:**
```
Run task: "Run AI Service"
```

**Thủ công qua terminal:**
```bash
cd ai-service
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # Cấu hình GEMINI_API_KEY, MONGODB_URI, REDIS_URL

python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 --reload
```

**Kiểm tra:** `curl http://localhost:8001/health`

### 4.3 Chạy Toàn Bộ Stack (Docker Compose)

```bash
# Development (local)
docker-compose up -d

# AI local profile (với model gateway)
docker-compose -f docker-compose.local.yml up -d

# Production
docker-compose -f docker-compose.production.yml up -d
```

---

## 5. Khởi Động Flutter App

### 5.1 Flutter Web
```bash
cd flutter-app
flutter run -d chrome --web-port=8080
```
Hoặc qua VS Code task: **"Run Flutter Web"**

### 5.2 Flutter iOS Simulator
```
VS Code task: "Run Flutter iOS (iPhone 17 Pro)"
```

### 5.3 Flutter Android
```bash
cd flutter-app
flutter run -d android
```

---

## 6. Checklist Xác Minh Sau Khi Chạy

- [ ] App mở được màn welcome/login.
- [ ] Đăng nhập thành công và vào `MainScreen`.
- [ ] 5 tab chính hoạt động: Discovery, Learning, Lexi, Chat, Account.
- [ ] Truy cập được một route content (news/podcast/books/games).
- [ ] Profile mở được settings và progress.
- [ ] Backend API health check trả về `{"status": "ok"}`.
- [ ] AI service health check trả về `{"status": "ok"}`.

---

## 7. Quy Trình Test Cơ Bản

```bash
# Unit/widget test
cd flutter-app && flutter test

# Build web local
flutter build web --release

# Backend tests
cd backend-service && pytest tests/ -v

# AI service tests
cd ai-service && pytest tests/ -v
```

Nếu cần test tổng thể triển khai, kết hợp đọc:
- [RPT-008 — Deployment Checklist](RPT-008_DEPLOYMENT_CHECKLIST.md)
- [RPT-009 — Hybrid Deployment Guide](RPT-009_HYBRID_DEPLOYMENT_GUIDE.md)

---

## 8. Lỗi Thường Gặp và Hướng Xử Lý Nhanh

| Lỗi | Triệu Chứng | Cách Xử Lý |
|-----|------------|------------|
| Stale session web | App trắng, không load | Dừng Flutter/Chrome cũ, chạy `flutter clean && flutter pub get` |
| Lỗi env/API | `Connection refused` | Kiểm tra `BACKEND_URL` trong `.env` đang trỏ đúng backend |
| Lỗi kết nối AI | Chat không phản hồi | Xác nhận ai-service đang chạy ở port 8001, kiểm tra `GEMINI_API_KEY` |
| Lỗi database | `relation does not exist` | Chạy `alembic upgrade head` trong `backend-service/` |
| WebSocket voice | Không thu âm được | Kiểm tra quyền microphone trên browser/device |
| Lỗi Firebase | `invalid-token` | Kiểm tra `FIREBASE_PROJECT_ID` trong `.env` backend đúng project |

---

## 9. Kết Luận Vận Hành

Quy trình cài đặt của LexiLingo hiện tại tương đối trực tiếp nếu thực hiện đúng thứ tự: cài dependencies → chạy backend/ai → chạy Flutter. Việc tách rõ service giúp dễ debug từng lớp và giảm rủi ro khi triển khai.

---

*Tham khảo: [RPT-008](RPT-008_DEPLOYMENT_CHECKLIST.md) | [RPT-009](RPT-009_HYBRID_DEPLOYMENT_GUIDE.md) | [RPT-023](RPT-023_TECHNOLOGY_STACK_AND_TOOLS.md)*
