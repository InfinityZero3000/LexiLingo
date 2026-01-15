# LexiLingo Backend API

FastAPI backend cho ứng dụng LexiLingo - AI-powered language learning platform.

## 🏗️ Kiến trúc

Backend được thiết kế theo **Clean Architecture** tương tự Flutter app:

```
backend/
├── api/
│   ├── main.py              # FastAPI application entry
│   ├── core/                # Core configuration
│   │   ├── config.py        # Settings management
│   │   └── database.py      # MongoDB connection
│   ├── models/              # Domain models
│   │   ├── schemas.py       # Pydantic models
│   │   └── ai_repository.py # Data access layer
│   ├── routes/              # API endpoints
│   │   ├── health.py        # Health check
│   │   ├── ai.py            # AI interactions
│   │   ├── chat.py          # Chat with Gemini
│   │   └── user.py          # User data
│   └── services/            # Business logic (TODO)
├── scripts/
│   └── mongo-init.js        # MongoDB initialization
├── requirements.txt         # Python dependencies
├── docker-compose.yml       # Local development
├── Dockerfile              # Container image
└── vercel.json             # Vercel deployment
```

## 🚀 Quick Start

### Local Development

1. **Clone và setup:**
```bash
cd LexiLingo_backend
cp .env.example .env
# Chỉnh sửa .env với API keys của bạn
```

2. **Chạy với Docker Compose:**
```bash
docker-compose up -d
```

Services sẽ chạy tại:
- API: http://localhost:8000
- MongoDB: localhost:27017
- Mongo Express: http://localhost:8081 (admin/admin123)
- Redis: localhost:6379

3. **Hoặc chạy local không Docker:**
```bash
# Cài đặt dependencies
pip install -r requirements.txt

# Chạy MongoDB riêng hoặc dùng Atlas

# Start server
uvicorn api.main:app --reload
```

### API Documentation

Truy cập API docs:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## 📋 API Endpoints

### Health Check
- `GET /health` - Kiểm tra trạng thái hệ thống
- `GET /ping` - Simple ping

### AI Interactions
- `POST /api/v1/ai/interactions` - Log AI interaction
- `GET /api/v1/ai/interactions/user/{user_id}` - Lấy lịch sử user
- `GET /api/v1/ai/interactions/session/{session_id}` - Lấy interactions của session
- `POST /api/v1/ai/interactions/{id}/feedback` - Cập nhật feedback
- `GET /api/v1/ai/analytics/user/{user_id}/errors` - Thống kê lỗi

### Chat (Gemini)
- `POST /api/v1/chat/sessions` - Tạo chat session mới
- `POST /api/v1/chat/messages` - Gửi message và nhận AI response
- `GET /api/v1/chat/sessions/{session_id}/messages` - Lấy lịch sử chat
- `GET /api/v1/chat/sessions/user/{user_id}` - Lấy tất cả sessions

### User
- `GET /api/v1/users/{user_id}/learning-pattern` - Lấy learning pattern
- `GET /api/v1/users/{user_id}/stats` - Lấy thống kê học tập

## 🔧 Configuration

### Environment Variables

File `.env` cần có:

```env
# Environment
ENVIRONMENT=development

# MongoDB
MONGODB_URI=mongodb://localhost:27017
MONGODB_DB_NAME=lexilingo

# Gemini AI
GEMINI_API_KEY=your_api_key

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Rate Limiting
RATE_LIMIT_PER_MINUTE=60
```

### MongoDB Atlas (Production)

Để dùng MongoDB Atlas thay vì local:

1. Tạo FREE cluster tại [MongoDB Atlas](https://www.mongodb.com/cloud/atlas)
2. Whitelist IP hoặc allow all (0.0.0.0/0)
3. Lấy connection string
4. Update `.env`:
```env
MONGODB_URI=***REMOVED***
```

Chi tiết xem: [docs/MONGODB_ATLAS_SETUP.md](docs/MONGODB_ATLAS_SETUP.md)

### MongoDB Configuration File

File `config/mongodb_config.yaml` chứa cấu hình cho cả development và production:
- Development: Local Docker MongoDB
- Production: MongoDB Atlas connection

Xem schema details: [docs/MONGODB_SCHEMA.md](docs/MONGODB_SCHEMA.md)

## 🚢 Deployment

### Vercel (Recommended)

1. **Install Vercel CLI:**
```bash
npm i -g vercel
```

2. **Login và deploy:**
```bash
cd LexiLingo_backend
vercel
```

3. **Setup environment variables trong Vercel:**
   - `MONGODB_URI` - Atlas connection string
   - `GEMINI_API_KEY` - Google API key
   - `ALLOWED_ORIGINS` - Frontend URLs
   - `ENVIRONMENT=production`

4. **Deploy:**
```bash
vercel --prod
```

Backend sẽ có URL: `https://your-project.vercel.app`

### Docker (Self-hosted)

```bash
# Build image
docker build -t lexilingo-backend .

# Run
docker run -p 8000:8000 \
  -e MONGODB_URI=your_uri \
  -e GEMINI_API_KEY=your_key \
  lexilingo-backend
```

## 🔗 Integration với Flutter

### Setup HTTP Client trong Flutter

```dart
// lib/core/api/api_client.dart
class ApiClient {
  static const baseUrl = 'https://your-backend.vercel.app/api/v1';
  final http.Client client;
  
  Future<Response> logInteraction(AIInteraction interaction) async {
    return await client.post(
      Uri.parse('$baseUrl/ai/interactions'),
      body: jsonEncode(interaction.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  }
  
  Future<List<ChatMessage>> getChatHistory(String sessionId) async {
    final response = await client.get(
      Uri.parse('$baseUrl/chat/sessions/$sessionId/messages'),
    );
    return (jsonDecode(response.body) as List)
      .map((e) => ChatMessage.fromJson(e))
      .toList();
  }
}
```

### Update Repository trong Flutter

```dart
// lib/features/chat/data/repositories/chat_repository_impl.dart
class ChatRepositoryImpl implements ChatRepository {
  final ApiClient apiClient;
  final LocalDataSource localDataSource; // SQLite cache
  
  @override
  Future<Either<Failure, String>> sendMessage(String message) async {
    try {
      // Call backend API
      final response = await apiClient.sendMessage(message);
      
      // Cache locally
      await localDataSource.saveMessage(response);
      
      return Right(response.aiResponse);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
```

## 📊 Database Schema

### ai_interactions
```javascript
{
  user_id: String,
  session_id: String,
  interaction_type: Enum['grammar_check', 'chat', 'vocabulary'],
  timestamp: Date,
  input_text: String,
  ai_response: Object,
  feedback: Object
}
```

### chat_sessions & chat_messages
```javascript
// Session
{
  session_id: String (unique),
  user_id: String,
  title: String,
  created_at: Date,
  last_activity: Date,
  message_count: Int
}

// Message
{
  message_id: String (unique),
  session_id: String,
  content: String,
  role: Enum['user', 'ai', 'system'],
  timestamp: Date
}
```

### learning_patterns
```javascript
{
  user_id: String,
  analyzed_at: Date,
  common_errors: Array,
  strengths: Array,
  recommendations: Array,
  stats: {
    total_interactions: Int,
    avg_fluency_score: Float,
    improvement_rate: Object
  }
}
```

## 🧪 Testing

```bash
# Install test dependencies
pip install pytest pytest-asyncio httpx

# Run tests
pytest tests/

# With coverage
pytest --cov=api tests/
```

## 📝 Development Notes

### Sync với DL-Model-Support

Backend này sẽ gọi DL-Model-Support API để:
- Phân tích văn bản (grammar check)
- Fine-tune model với feedback data
- Inference với custom model

Setup connection:
```python
# api/services/dl_model_service.py
class DLModelService:
    base_url = "http://localhost:8000"  # DL-Model-Support API
    
    async def analyze_text(self, text: str):
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/analyze",
                json={"text": text}
            )
            return response.json()
```

### Architecture Decisions

1. **FastAPI thay vì Spring Boot:** 
   - Vercel chỉ support Node.js, Python, Go, Ruby (không support Java)
   - Python ecosystem tốt cho AI/ML
   - Async support tốt với Motor (MongoDB)

2. **MongoDB thay vì PostgreSQL:**
   - Schema linh hoạt cho AI data
   - Dễ lưu JSON responses từ Gemini
   - FREE tier generous (512MB)
   - Aggregate pipeline mạnh cho analytics

3. **Clean Architecture:**
   - Consistency với Flutter app
   - Easy testing
   - Clear separation of concerns

## 🤝 Contributing

Xem [CONTRIBUTING.md](../../CONTRIBUTING.md)

## 📄 License

Private - LexiLingo Team
