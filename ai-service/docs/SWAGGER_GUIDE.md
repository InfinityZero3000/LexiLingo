#  Hướng dẫn Test API với Swagger UI

##  Khởi động nhanh

### Cách 1: Sử dụng script tự động
```bash
chmod +x test_swagger.sh
./test_swagger.sh
```

### Cách 2: Khởi động thủ công
```bash
# Cài đặt dependencies (nếu chưa cài)
pip install -r requirements.txt

# Khởi động server
python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

Sau đó truy cập: **http://localhost:8000/docs**

---

##  Các URL quan trọng

| URL | Mô tả |
|-----|-------|
| http://localhost:8000/docs | **Swagger UI** - Giao diện test API interactive |
| http://localhost:8000/redoc | **ReDoc** - Documentation đẹp hơn |
| http://localhost:8000/openapi.json | **OpenAPI Schema** - JSON schema của API |
| http://localhost:8000/ | **Root** - Thông tin cơ bản về API |
| http://localhost:8000/health | **Health Check** - Kiểm tra trạng thái hệ thống |

---

##  Test các endpoint trên Swagger UI

### 1. Health Check
1. Mở Swagger UI: http://localhost:8000/docs
2. Tìm section **" Health & Status"**
3. Click vào `GET /health`
4. Click nút **"Try it out"**
5. Click **"Execute"**
6. Xem kết quả trong phần **Response body**

**Kết quả mong đợi:**
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

---

### 2. Chat với Gemini AI

#### Tạo session mới
1. Tìm section **" Chat with Gemini AI"**
2. Click `POST /api/v1/chat/sessions`
3. Click **"Try it out"**
4. Nhập request body:
```json
{
  "user_id": "test_user_123",
  "title": "My First Chat"
}
```
5. Click **"Execute"**
6. **Lưu lại `session_id`** từ response

#### Gửi tin nhắn
1. Click `POST /api/v1/chat/messages`
2. Click **"Try it out"**
3. Nhập request body (thay `session_abc123` bằng session_id của bạn):
```json
{
  "session_id": "session_abc123",
  "user_id": "test_user_123",
  "message": "Hello! Can you help me with English grammar?"
}
```
4. Click **"Execute"**
5. Xem phản hồi từ AI trong response

#### Xem lịch sử chat
1. Click `GET /api/v1/chat/sessions/{session_id}/messages`
2. Click **"Try it out"**
3. Nhập `session_id` của bạn
4. Click **"Execute"**

---

### 3. AI Interactions & Analytics

#### Log một interaction
1. Tìm section **" AI Interactions & Analytics"**
2. Click `POST /api/v1/ai/interactions`
3. Click **"Try it out"**
4. Nhập request body:
```json
{
  "user_id": "test_user_123",
  "session_id": "test_session",
  "interaction_type": "grammar_check",
  "input_text": "I goes to school yesterday",
  "ai_response": {
    "fluency_score": 0.75,
    "vocabulary_level": "A2",
    "grammar_errors": [
      {
        "type": "verb_tense",
        "error": "goes",
        "correction": "went",
        "explanation": "Use past tense with 'yesterday'"
      }
    ],
    "tutor_response": "Good attempt! Remember past tense..."
  },
  "context": {
    "learner_level": "B1",
    "previous_errors": ["past_tense"]
  }
}
```
5. Click **"Execute"**

#### Xem lịch sử interactions
1. Click `GET /api/v1/ai/interactions/user/{user_id}`
2. Click **"Try it out"**
3. Nhập `user_id`: `test_user_123`
4. Click **"Execute"**

---

### 4. User Learning Pattern

#### Xem error statistics
1. Tìm section **" User Data & Learning Pattern"**
2. Click `GET /api/v1/users/{user_id}/stats`
3. Click **"Try it out"**
4. Nhập `user_id`: `test_user_123`
5. Click **"Execute"**

---

##  Tính năng Swagger UI

### Tìm kiếm endpoint
- Sử dụng ô **"Filter by tag"** ở trên cùng
- Hoặc gõ tên endpoint vào search box

### Export OpenAPI Schema
1. Click vào link `/openapi.json` ở top
2. Hoặc truy cập: http://localhost:8000/openapi.json
3. Copy JSON để import vào Postman/Insomnia

### Xem Response Schema
- Mỗi endpoint hiển thị schema của request/response
- Click vào "Schema" để xem chi tiết structure

### Test với nhiều parameters
- Swagger tự động generate form cho request body
- Có thể edit trực tiếp JSON hoặc dùng form

---

##  Troubleshooting

### Server không khởi động được
```bash
# Kiểm tra port 8000 có bị chiếm không
lsof -i :8000

# Nếu bị chiếm, kill process
kill -9 <PID>

# Hoặc dùng port khác
uvicorn api.main:app --reload --port 8001
```

### MongoDB connection failed
- Kiểm tra MongoDB đang chạy
- Kiểm tra file `.env` hoặc biến môi trường `MONGODB_URI`
- API vẫn chạy được với degraded mode (không có MongoDB)

### Gemini API không hoạt động
- Đảm bảo đã set `GEMINI_API_KEY` trong `.env`
- Lấy API key tại: https://makersuite.google.com/app/apikey

### Redis connection warning
- Redis là optional, API vẫn hoạt động bình thường
- Nếu muốn dùng Redis:
```bash
# macOS
brew install redis
brew services start redis
```

---

##  Tài liệu thêm

- **API Contract**: Xem file `docs/API_CONTRACT.md`
- **MongoDB Schema**: Xem file `docs/MONGODB_SCHEMA.md`
- **Postman Collection**: Import file `docs/postman/LexiLingo_API.postman_collection.json`

---

##  Tips

1. **Sử dụng "Try it out"**: Tất cả endpoints đều có thể test trực tiếp trên Swagger
2. **Copy curl command**: Mỗi request có thể export ra curl command
3. **Check Response Code**: Luôn kiểm tra HTTP status code (200, 400, 500...)
4. **Read Error Messages**: Error responses có detail message giúp debug
5. **Use different user_ids**: Test với nhiều user khác nhau để thấy sự khác biệt

---

**Happy Testing! **
