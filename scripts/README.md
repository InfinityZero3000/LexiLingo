# LexiLingo Scripts

Scripts để quản lý và chạy toàn bộ hệ thống LexiLingo.

## 📋 Danh sách Scripts

### 1. `setup-all.sh` - Cài đặt toàn bộ hệ thống
Cài đặt dependencies và cấu hình cho tất cả các services.

```bash
./scripts/setup-all.sh
```

**Thực hiện:**
- ✅ Tạo Python virtual environments cho Backend & AI Service
- ✅ Cài đặt tất cả Python dependencies
- ✅ Thiết lập PostgreSQL database
- ✅ Chạy database migrations
- ✅ Cài đặt Flutter dependencies
- ✅ Tạo file `.env` từ templates

### 2. `start-all.sh` - Khởi động tất cả services
Khởi động Backend, AI Service, và Flutter Web cùng lúc.

```bash
./scripts/start-all.sh
```

**Services được khởi động:**
- 🔧 **Backend Service** - `http://localhost:8000`
  - API Docs: `http://localhost:8000/docs`
  - Health Check: `http://localhost:8000/health`
  
- 🤖 **AI Service** - `http://localhost:8001`
  - Health Check: `http://localhost:8001/health`
  
- 📱 **Flutter Web** - `http://localhost:8080`

**Logs được lưu tại:** `logs/`
- `backend.log`
- `ai-service.log`
- `flutter-web.log`

**Dừng tất cả services:** Nhấn `Ctrl+C`

### 3. `stop-all.sh` - Dừng tất cả services
Dừng tất cả services đang chạy.

```bash
./scripts/stop-all.sh
```

### 4. `status.sh` - Kiểm tra trạng thái services
Kiểm tra trạng thái của tất cả services.

```bash
./scripts/status.sh
```

**Hiển thị:**
- ✅ Services đang chạy (với PID)
- Services đã dừng
- 🗄️ Trạng thái PostgreSQL database

## 🚀 Quick Start

### Lần đầu sử dụng:

```bash
# 1. Cài đặt toàn bộ hệ thống
./scripts/setup-all.sh

# 2. Chỉnh sửa các file cấu hình .env (nếu cần)
# - backend-service/.env
# - ai-service/.env
# - flutter-app/.env

# 3. Khởi động tất cả services
./scripts/start-all.sh
```

### Sử dụng hàng ngày:

```bash
# Khởi động
./scripts/start-all.sh

# Kiểm tra trạng thái
./scripts/status.sh

# Dừng
./scripts/stop-all.sh
```

## 📝 Yêu cầu hệ thống

- ✅ Python 3.11+
- ✅ Flutter 3.24.0+
- ✅ PostgreSQL 14+
- ✅ pip/venv

## 🔧 Cấu trúc Logs & PIDs

```
LexiLingo/
├── logs/                    # Log files
│   ├── backend.log
│   ├── ai-service.log
│   └── flutter-web.log
├── .pids/                   # Process ID files
│   ├── backend.pid
│   ├── ai-service.pid
│   └── flutter-web.pid
└── scripts/
    ├── setup-all.sh        # Setup script
    ├── start-all.sh        # Start script
    ├── stop-all.sh         # Stop script
    └── status.sh           # Status check script
```

## 🐛 Troubleshooting

### Port đã được sử dụng

```bash
# Kiểm tra process đang dùng port
lsof -ti:8000  # Backend
lsof -ti:8001  # AI Service
lsof -ti:8080  # Flutter Web

# Kill process
kill -9 $(lsof -ti:8000)
```

### Service không khởi động

```bash
# Kiểm tra logs
tail -f logs/backend.log
tail -f logs/ai-service.log
tail -f logs/flutter-web.log
```

### Database connection error

```bash
# Kiểm tra PostgreSQL
pg_isready

# Kiểm tra database exists
psql -l | grep lexilingo

# Tạo database nếu chưa có
createdb lexilingo
```

### Virtual environment không tìm thấy

```bash
# Chạy lại setup
./scripts/setup-all.sh
```

## 📚 Tài liệu chi tiết

- Backend Service: [backend-service/README.md](../backend-service/README.md)
- AI Service: [ai-service/README.md](../ai-service/README.md)
- Flutter App: [flutter-app/README.md](../flutter-app/README.md)

## ⚡ Advanced Usage

### Chạy từng service riêng lẻ

**Backend:**
```bash
cd backend-service
source venv/bin/activate
uvicorn app.main:app --reload --port 8000
```

**AI Service:**
```bash
cd ai-service
source venv/bin/activate
uvicorn api.main:app --reload --port 8001
```

**Flutter Web:**
```bash
cd flutter-app
flutter run -d web-server --web-port 8080
```

### Xem logs real-time

```bash
# Tất cả logs
tail -f logs/*.log

# Chỉ Backend
tail -f logs/backend.log

# Chỉ AI Service
tail -f logs/ai-service.log

# Chỉ Flutter
tail -f logs/flutter-web.log
```

### Clean restart

```bash
# Dừng tất cả
./scripts/stop-all.sh

# Xóa logs cũ
rm -rf logs/*.log

# Khởi động lại
./scripts/start-all.sh
```

## 🤝 Contributing

Khi thêm scripts mới:
1. Đặt tên rõ ràng với extension `.sh`
2. Thêm shebang `#!/bin/bash`
3. Thêm description và usage instructions
4. Cập nhật file README này
5. Make executable: `chmod +x scripts/your-script.sh`
