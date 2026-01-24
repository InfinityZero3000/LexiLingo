#  Troubleshooting Guide

##  Lỗi thường gặp và cách khắc phục

### 1. MongoDB Connection Refused

**Lỗi:**
```
 Failed to connect to MongoDB: localhost:27017: [Errno 61] Connection refused
```

**Nguyên nhân:** MongoDB chưa được khởi động

**Giải pháp:**

#### Cách 1: Sử dụng Docker (Khuyến nghị)
```bash
# Khởi động MongoDB và Redis qua Docker
docker-compose up -d

# Kiểm tra trạng thái
docker-compose ps
```

#### Cách 2: Cài đặt MongoDB local (macOS)
```bash
# Cài đặt MongoDB
brew install mongodb-community

# Khởi động MongoDB
brew services start mongodb-community

# Kiểm tra MongoDB đang chạy
brew services list | grep mongodb
```

#### Cách 3: Sử dụng MongoDB Atlas (Cloud)
1. Tạo cluster miễn phí tại https://www.mongodb.com/atlas
2. Lấy connection string
3. Cập nhật file `.env`:
```bash
MONGODB_URI=***REMOVED***
```

**Lưu ý:** API vẫn hoạt động ngay cả khi MongoDB down nhờ graceful degradation, nhưng các endpoints liên quan đến database sẽ trả về lỗi.

---

### 2. Port 8000 Already in Use

**Lỗi:**
```
ERROR: [Errno 48] Address already in use
```

**Giải pháp:**
```bash
# Kill process đang chiếm port 8000
lsof -ti:8000 | xargs kill -9

# Hoặc dùng port khác
uvicorn api.main:app --port 8001
```

---

### 3. Redis Connection Warning

**Warning:**
```
 Redis connection failed. Continuing without cache...
```

**Giải pháp:**

#### Sử dụng Docker:
```bash
docker-compose up -d redis
```

#### Cài đặt Redis local (macOS):
```bash
# Cài đặt Redis
brew install redis

# Khởi động Redis
brew services start redis

# Kiểm tra Redis
redis-cli ping
# Phản hồi: PONG
```

**Lưu ý:** Redis là optional. API sẽ hoạt động bình thường không có Redis, chỉ không có caching.

---

### 4. Module Not Found Error

**Lỗi:**
```
ModuleNotFoundError: No module named 'fastapi'
```

**Giải pháp:**
```bash
# Kích hoạt virtual environment
source .venv/bin/activate  # macOS/Linux
# hoặc
.venv\Scripts\activate  # Windows

# Cài đặt dependencies
pip install -r requirements.txt
```

---

### 5. Pydantic Settings Error

**Lỗi:**
```
SettingsError: error parsing value for field "ALLOWED_ORIGINS"
```

**Giải pháp:**
Kiểm tra file `.env` không có field không hợp lệ. File `.env` mẫu:
```bash
# Environment
ENVIRONMENT=development
DEBUG=true

# MongoDB
MONGODB_URI=mongodb://localhost:27017
MONGODB_DATABASE=lexilingo

# Gemini AI
GEMINI_API_KEY=your_api_key_here

# Rate Limiting
RATE_LIMIT_PER_MINUTE=60
```

---

### 6. Google Generative AI Warning

**Warning:**
```
FutureWarning: All support for the `google.generativeai` package has ended
```

**Giải pháp:** 
Đây chỉ là warning, không ảnh hưởng hoạt động hiện tại. Sẽ được cập nhật sang `google.genai` trong phiên bản tương lai.

---

##  Kiểm tra hệ thống hoạt động đúng

### 1. Kiểm tra API đang chạy
```bash
curl http://localhost:8000/
```
Kết quả mong đợi:
```json
{
  "name": "LexiLingo API",
  "version": "1.0.0",
  "status": "running",
  ...
}
```

### 2. Kiểm tra Health
```bash
curl http://localhost:8000/health
```
Kết quả mong đợi (khi tất cả services đều OK):
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "environment": "development",
  "services": {
    "mongodb": true,
    "redis": true,
    "ai_model": false
  }
}
```

### 3. Test Swagger UI
Mở browser: http://localhost:8000/docs

---

##  Docker Commands Hữu Ích

```bash
# Khởi động tất cả services
docker-compose up -d

# Xem logs
docker-compose logs -f

# Dừng services
docker-compose down

# Xóa volumes và restart từ đầu
docker-compose down -v
docker-compose up -d

# Kiểm tra containers đang chạy
docker ps
```

---

##  Debug Tips

### Bật Debug Mode
Trong file `.env`:
```bash
DEBUG=true
LOG_LEVEL=DEBUG
```

### Xem Logs Chi Tiết
Server logs được in ra terminal tự động khi chạy với `--reload`

### Test Endpoints với curl
```bash
# Health check
curl http://localhost:8000/health

# Ping
curl http://localhost:8000/ping

# Root
curl http://localhost:8000/
```

---

##  Cần Thêm Trợ Giúp?

1. Kiểm tra file logs trong terminal
2. Xem API Contract: `docs/API_CONTRACT.md`
3. Xem MongoDB Schema: `docs/MONGODB_SCHEMA.md`
4. Đọc Swagger Guide: `SWAGGER_GUIDE.md`

---

**Cập nhật:** 16/01/2026
