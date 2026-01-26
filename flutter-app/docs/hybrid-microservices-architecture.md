# Kiến Trúc Hybrid Microservices - LexiLingo

## Tổng Quan

Kiến trúc 2-service đơn giản, phù hợp với team nhỏ, tách biệt rõ ràng giữa Backend và AI Service.

```
┌─────────────────┐
│  Flutter App    │
│   (Mobile/Web)  │
└────────┬────────┘
         │
    ┌────┴────────────────┐
    │                     │
┌───▼──────────┐   ┌─────▼─────────┐
│   Backend    │   │  AI Service   │
│   Service    │   │               │
│  (FastAPI)   │   │   (FastAPI)   │
│              │   │               │
│  PostgreSQL  │   │   MongoDB     │
└──────────────┘   └───────────────┘
```

## 1. Tách Biệt Service

### Backend Service (PostgreSQL)
**Chức năng:**
- Quản lý User (đăng ký, đăng nhập, profile)
- Quản lý Course (danh sách khóa học, lessons, progress)
- Quản lý Vocabulary (từ vựng, flashcards)
- Theo dõi Progress (điểm số, streak, achievements)
- Authentication & Authorization (JWT)

**Lý do sử dụng PostgreSQL:**
- Dữ liệu có cấu trúc rõ ràng (users, courses, vocabulary)
- Quan hệ phức tạp (user → progress → course → lessons)
- ACID transactions (đảm bảo consistency)
- Query phức tạp (JOIN, aggregate functions)

### AI Service (MongoDB)
**Chức năng:**
- Chat với AI (lịch sử chat, context)
- Pronunciation Analysis (audio recordings, scores)
- Speech-to-Text / Text-to-Speech
- Error Analysis (lỗi phát âm, gợi ý cải thiện)
- Content Generation (câu hỏi, bài tập)

**Lý do sử dụng MongoDB:**
- Schema linh hoạt (AI responses, embeddings)
- Lưu trữ dữ liệu lớn (audio files, vectors)
- Document-based (phù hợp với chat sessions)
- Tốc độ cao với unstructured data
- Dễ scale horizontal

## 2. Technology Stack

### Backend Service
```yaml
Framework: FastAPI 0.115+
Database: PostgreSQL 16+
ORM: SQLAlchemy 2.0+
Migration: Alembic
Auth: python-jose[cryptography], passlib[bcrypt]
Validation: Pydantic 2.0+
Testing: pytest, pytest-asyncio
```

### AI Service
```yaml
Framework: FastAPI 0.115+
Database: MongoDB 7.0+
ODM: Motor (async), Beanie
AI Models:
  - Qwen2.5-1.5B (NLP)
  - LLaMA3-8B-VI (Vietnamese)
  - HuBERT (Pronunciation)
  - Faster-Whisper (STT)
  - Piper TTS (TTS)
Cache: Redis 7.0+
Vector DB: Qdrant (embeddings)
Testing: pytest, pytest-asyncio
```

## 3. Database Schema

### PostgreSQL Schema

```sql
-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    avatar_url TEXT,
    native_language VARCHAR(10) DEFAULT 'vi',
    target_language VARCHAR(10) DEFAULT 'en',
    level VARCHAR(20) DEFAULT 'beginner',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

-- Courses
CREATE TABLE courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    language VARCHAR(10) NOT NULL,
    level VARCHAR(20) NOT NULL,
    total_lessons INTEGER DEFAULT 0,
    thumbnail_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_published BOOLEAN DEFAULT false
);

-- Lessons
CREATE TABLE lessons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    order_index INTEGER NOT NULL,
    content JSONB,
    estimated_minutes INTEGER DEFAULT 10,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User Progress
CREATE TABLE user_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    lesson_id UUID REFERENCES lessons(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'not_started',
    score INTEGER DEFAULT 0,
    completed_at TIMESTAMP,
    time_spent_seconds INTEGER DEFAULT 0,
    attempts INTEGER DEFAULT 0,
    UNIQUE(user_id, lesson_id)
);

-- Vocabulary
CREATE TABLE vocabulary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    word VARCHAR(255) NOT NULL,
    translation VARCHAR(255),
    pronunciation VARCHAR(255),
    example_sentence TEXT,
    language VARCHAR(10) NOT NULL,
    difficulty VARCHAR(20),
    audio_url TEXT,
    image_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User Vocabulary (flashcards)
CREATE TABLE user_vocabulary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    vocabulary_id UUID REFERENCES vocabulary(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'learning',
    review_count INTEGER DEFAULT 0,
    next_review_at TIMESTAMP,
    ease_factor FLOAT DEFAULT 2.5,
    interval_days INTEGER DEFAULT 0,
    UNIQUE(user_id, vocabulary_id)
);

-- Streaks
CREATE TABLE streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_activity_date DATE,
    total_days_active INTEGER DEFAULT 0
);
```

### MongoDB Schema

```javascript
// Chat Sessions
{
  _id: ObjectId,
  userId: String,
  sessionTitle: String,
  language: String,
  createdAt: ISODate,
  updatedAt: ISODate,
  messages: [
    {
      messageId: String,
      role: "user" | "assistant" | "system",
      content: String,
      timestamp: ISODate,
      metadata: {
        model: String,
        tokens: Number
      }
    }
  ],
  context: {
    currentTopic: String,
    userLevel: String,
    learningGoals: [String]
  }
}

// Pronunciation Analysis
{
  _id: ObjectId,
  userId: String,
  audioUrl: String,
  transcript: String,
  targetText: String,
  analysis: {
    overallScore: Number,
    fluencyScore: Number,
    pronunciationScore: Number,
    phonemeScores: [
      {
        phoneme: String,
        expected: String,
        actual: String,
        score: Number,
        feedback: String
      }
    ],
    commonErrors: [String],
    improvements: [String]
  },
  createdAt: ISODate,
  processingTime: Number
}

// Audio Files
{
  _id: ObjectId,
  userId: String,
  fileType: "recording" | "synthesis",
  url: String,
  duration: Number,
  format: String,
  sampleRate: Number,
  metadata: {
    text: String,
    language: String,
    model: String
  },
  createdAt: ISODate,
  expiresAt: ISODate
}

// Error Analysis
{
  _id: ObjectId,
  userId: String,
  errorType: String,
  context: String,
  analysis: {
    errorDescription: String,
    severity: String,
    suggestions: [String],
    examples: [String]
  },
  createdAt: ISODate
}

// Content Generation Cache
{
  _id: ObjectId,
  contentType: "question" | "exercise" | "explanation",
  topic: String,
  level: String,
  language: String,
  content: Object,
  metadata: {
    model: String,
    generatedAt: ISODate,
    usageCount: Number
  },
  expiresAt: ISODate
}
```

## 4. API Endpoints

### Backend Service (Port 8000)

```
Authentication:
POST   /api/v1/auth/register       - Đăng ký user mới
POST   /api/v1/auth/login          - Đăng nhập
POST   /api/v1/auth/refresh        - Refresh token
POST   /api/v1/auth/logout         - Đăng xuất

Users:
GET    /api/v1/users/me            - Thông tin user hiện tại
PUT    /api/v1/users/me            - Cập nhật profile
GET    /api/v1/users/{id}          - Thông tin user (admin)

Courses:
GET    /api/v1/courses             - Danh sách courses
GET    /api/v1/courses/{id}        - Chi tiết course
GET    /api/v1/courses/{id}/lessons - Danh sách lessons

Progress:
GET    /api/v1/progress            - Progress của user
POST   /api/v1/progress/lessons/{id} - Cập nhật progress
GET    /api/v1/progress/stats      - Thống kê học tập

Vocabulary:
GET    /api/v1/vocabulary          - Danh sách từ vựng
POST   /api/v1/vocabulary          - Thêm từ vựng
GET    /api/v1/vocabulary/review   - Từ cần ôn tập
POST   /api/v1/vocabulary/{id}/review - Ghi nhận ôn tập

Streaks:
GET    /api/v1/streaks/me          - Streak hiện tại
POST   /api/v1/streaks/checkin     - Check-in hàng ngày
```

### AI Service (Port 8001)

```
Chat:
POST   /api/v1/ai/chat             - Gửi tin nhắn chat
GET    /api/v1/ai/chat/sessions    - Danh sách chat sessions
GET    /api/v1/ai/chat/sessions/{id} - Chi tiết session
DELETE /api/v1/ai/chat/sessions/{id} - Xóa session

Pronunciation:
POST   /api/v1/ai/pronunciation/analyze - Phân tích phát âm
GET    /api/v1/ai/pronunciation/history - Lịch sử phát âm
GET    /api/v1/ai/pronunciation/stats   - Thống kê phát âm

Speech:
POST   /api/v1/ai/stt              - Speech to Text
POST   /api/v1/ai/tts              - Text to Speech
GET    /api/v1/ai/audio/{id}       - Lấy file audio

Analysis:
POST   /api/v1/ai/analyze/error    - Phân tích lỗi
POST   /api/v1/ai/analyze/text     - Phân tích văn bản
GET    /api/v1/ai/analyze/suggestions - Gợi ý cải thiện

Content Generation:
POST   /api/v1/ai/generate/question - Tạo câu hỏi
POST   /api/v1/ai/generate/exercise - Tạo bài tập
POST   /api/v1/ai/generate/explanation - Tạo giải thích

Health:
GET    /api/v1/ai/health           - Trạng thái service
GET    /api/v1/ai/models/status    - Trạng thái AI models
```

## 5. Communication Pattern

### Không có giao tiếp trực tiếp giữa services

Services **KHÔNG gọi nhau**, chỉ Flutter app gọi services:

```
✅ Đúng:
Flutter → Backend Service (get user info)
Flutter → AI Service (chat)
Flutter → Backend Service (update progress)

❌ Sai:
Backend Service → AI Service
AI Service → Backend Service
```

### Chia sẻ dữ liệu qua Client

```typescript
// Flutter App làm cầu nối
async function startAIChat() {
  // 1. Lấy user info từ Backend
  const user = await backendApi.getUser();
  
  // 2. Gửi chat với user context
  const response = await aiApi.chat({
    userId: user.id,
    userLevel: user.level,
    targetLanguage: user.targetLanguage,
    message: "Hello"
  });
  
  // 3. Cập nhật progress nếu cần
  await backendApi.updateProgress({
    activityType: 'ai_chat',
    duration: response.duration
  });
}
```

## 6. Cấu Trúc Project

```
LexiLingo/
├── LexiLingo_app/              # Flutter App (hiện tại)
│   ├── lib/
│   ├── test/
│   └── pubspec.yaml
│
├── backend-service/             # Backend Service (NEW)
│   ├── alembic/                # Database migrations
│   ├── app/
│   │   ├── api/
│   │   │   └── v1/
│   │   │       ├── auth.py
│   │   │       ├── users.py
│   │   │       ├── courses.py
│   │   │       ├── progress.py
│   │   │       ├── vocabulary.py
│   │   │       └── streaks.py
│   │   ├── core/
│   │   │   ├── config.py
│   │   │   ├── security.py
│   │   │   └── database.py
│   │   ├── models/             # SQLAlchemy models
│   │   ├── schemas/            # Pydantic schemas
│   │   ├── services/           # Business logic
│   │   └── main.py
│   ├── tests/
│   ├── .env.example
│   ├── requirements.txt
│   ├── Dockerfile
│   └── README.md
│
├── ai-service/                  # AI Service (NEW)
│   ├── app/
│   │   ├── api/
│   │   │   └── v1/
│   │   │       ├── chat.py
│   │   │       ├── pronunciation.py
│   │   │       ├── speech.py
│   │   │       ├── analysis.py
│   │   │       └── generation.py
│   │   ├── core/
│   │   │   ├── config.py
│   │   │   ├── database.py
│   │   │   └── redis.py
│   │   ├── models/             # MongoDB models
│   │   ├── schemas/            # Pydantic schemas
│   │   ├── services/
│   │   │   ├── ai_orchestrator.py
│   │   │   ├── chat_service.py
│   │   │   ├── pronunciation_service.py
│   │   │   ├── stt_service.py
│   │   │   └── tts_service.py
│   │   ├── ml/
│   │   │   ├── model_loader.py
│   │   │   ├── inference.py
│   │   │   └── preprocessing.py
│   │   └── main.py
│   ├── models/                 # AI model files
│   ├── tests/
│   ├── .env.example
│   ├── requirements.txt
│   ├── Dockerfile
│   └── README.md
│
└── docker-compose.yml          # Orchestration
```

## 7. Environment Variables

### Backend Service (.env)
```bash
# Server
APP_NAME=LexiLingo Backend
APP_ENV=development
API_V1_PREFIX=/api/v1
DEBUG=True
PORT=8000

# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/lexilingo
DB_ECHO=False
DB_POOL_SIZE=20
DB_MAX_OVERFLOW=10

# Security
SECRET_KEY=your-secret-key-here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Logging
LOG_LEVEL=INFO
```

### AI Service (.env)
```bash
# Server
APP_NAME=LexiLingo AI Service
APP_ENV=development
API_V1_PREFIX=/api/v1
DEBUG=True
PORT=8001

# MongoDB
MONGODB_URL=mongodb://localhost:27017
MONGODB_DATABASE=lexilingo_ai

# Redis
REDIS_URL=redis://localhost:6379/0
REDIS_CACHE_TTL=3600

# AI Models
QWEN_MODEL_PATH=./models/qwen2.5-1.5b
LLAMA_MODEL_PATH=./models/llama3-8b-vi
HUBERT_MODEL_PATH=./models/hubert-base
WHISPER_MODEL_PATH=./models/faster-whisper-base
PIPER_MODEL_PATH=./models/piper-vi

# Model Config
DEVICE=cuda
MAX_TOKENS=2048
TEMPERATURE=0.7
BATCH_SIZE=8

# Vector Database
QDRANT_URL=http://localhost:6333
QDRANT_COLLECTION=embeddings

# File Storage
AUDIO_UPLOAD_DIR=./uploads/audio
MAX_AUDIO_SIZE_MB=10
AUDIO_RETENTION_DAYS=7

# Logging
LOG_LEVEL=INFO
```

## 8. Docker Compose

```yaml
version: '3.8'

services:
  # PostgreSQL
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: lexilingo
      POSTGRES_PASSWORD: lexilingo_pass
      POSTGRES_DB: lexilingo
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lexilingo"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MongoDB
  mongodb:
    image: mongo:7.0
    environment:
      MONGO_INITDB_ROOT_USERNAME: lexilingo
      MONGO_INITDB_ROOT_PASSWORD: lexilingo_pass
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Qdrant (Vector DB)
  qdrant:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage

  # Backend Service
  backend:
    build:
      context: ./backend-service
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://lexilingo:lexilingo_pass@postgres:5432/lexilingo
      SECRET_KEY: ${SECRET_KEY}
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./backend-service:/app
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  # AI Service
  ai-service:
    build:
      context: ./ai-service
      dockerfile: Dockerfile
    ports:
      - "8001:8001"
    environment:
      MONGODB_URL: mongodb://lexilingo:lexilingo_pass@mongodb:27017
      REDIS_URL: redis://redis:6379/0
      QDRANT_URL: http://qdrant:6333
      DEVICE: ${DEVICE:-cpu}
    depends_on:
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
      qdrant:
        condition: service_started
    volumes:
      - ./ai-service:/app
      - ai_models:/app/models
      - ai_uploads:/app/uploads
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    command: uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

volumes:
  postgres_data:
  mongodb_data:
  redis_data:
  qdrant_data:
  ai_models:
  ai_uploads:
```

## 9. Flutter Integration

### Cập nhật DI Container

```dart
// lib/core/di/injection_container.dart

Future<void> initializeDependencies() async {
  // API Clients
  sl.registerLazySingleton(() => BackendApiClient(
    baseUrl: const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://localhost:8000/api/v1',
    ),
  ));

  sl.registerLazySingleton(() => AiApiClient(
    baseUrl: const String.fromEnvironment(
      'AI_SERVICE_URL',
      defaultValue: 'http://localhost:8001/api/v1',
    ),
  ));

  // Services
  sl.registerLazySingleton<AuthService>(
    () => AuthServiceImpl(apiClient: sl<BackendApiClient>()),
  );

  sl.registerLazySingleton<ChatService>(
    () => ChatServiceImpl(apiClient: sl<AiApiClient>()),
  );

  sl.registerLazySingleton<PronunciationService>(
    () => PronunciationServiceImpl(apiClient: sl<AiApiClient>()),
  );

  // ... other services
}
```

### API Client Example

```dart
// lib/core/network/backend_api_client.dart

class BackendApiClient {
  final String baseUrl;
  final Dio _dio;

  BackendApiClient({required this.baseUrl}) 
    : _dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      )) {
    _dio.interceptors.add(AuthInterceptor());
    _dio.interceptors.add(LoggingInterceptor());
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  // ... other methods
}

// lib/core/network/ai_api_client.dart
// Tương tự BackendApiClient
```

## 10. Deployment Strategy

### Development
```bash
# Start all services
docker-compose up -d

# Run migrations
docker-compose exec backend alembic upgrade head

# Check logs
docker-compose logs -f backend
docker-compose logs -f ai-service
```

### Production (Cloud)

**Backend Service:**
- Deploy: Railway / Render / Fly.io
- Database: Supabase (PostgreSQL) / Neon
- Scaling: Auto-scale dựa trên CPU usage

**AI Service:**
- Deploy: RunPod / Vast.ai (GPU required)
- Database: MongoDB Atlas
- Cache: Redis Cloud / Upstash
- Scaling: Manual scale based on load

**Flutter App:**
- Mobile: Play Store / App Store
- Web: Vercel / Netlify / Firebase Hosting

## 11. Migration Plan

### Phase 1: Setup Infrastructure (1 tuần)
1. Tạo repositories cho backend-service và ai-service
2. Setup Docker Compose
3. Initialize databases
4. Setup CI/CD

### Phase 2: Backend Service (2 tuần)
1. Implement Authentication
2. Migrate User & Course management
3. Migrate Progress & Vocabulary
4. Testing & Documentation

### Phase 3: AI Service (3 tuần)
1. Setup MongoDB & Redis
2. Implement Chat service
3. Implement Pronunciation analysis
4. Implement STT/TTS
5. Model integration & optimization

### Phase 4: Flutter Integration (1 tuần)
1. Create API clients
2. Update DI container
3. Migrate existing features
4. Testing

### Phase 5: Testing & Deployment (1 tuần)
1. Integration testing
2. Load testing
3. Security audit
4. Production deployment

## 12. Ưu Điểm

✅ **Đơn giản**: Chỉ 2 services, dễ quản lý
✅ **Tách biệt rõ ràng**: Backend vs AI, PostgreSQL vs MongoDB
✅ **Không phụ thuộc**: Services không gọi nhau
✅ **Dễ scale**: Mỗi service scale độc lập
✅ **Dễ test**: Test riêng từng service
✅ **Team nhỏ**: 1-2 người/service
✅ **Lỗi cô lập**: AI crash không ảnh hưởng Backend
✅ **Deploy độc lập**: Update từng service mà không ảnh hưởng nhau

## 13. Lưu Ý

⚠️ **CORS**: Configure đúng CORS cho cả 2 services
⚠️ **Authentication**: JWT token shared giữa app và services
⚠️ **Error Handling**: Xử lý timeout và retry ở Flutter app
⚠️ **Monitoring**: Setup logging và monitoring cho cả 2 services
⚠️ **Database Backup**: Backup riêng PostgreSQL và MongoDB
⚠️ **API Versioning**: Sử dụng /api/v1, /api/v2 cho backward compatibility
⚠️ **Rate Limiting**: Implement rate limiting ở API Gateway hoặc mỗi service
⚠️ **Security**: HTTPS, API keys, JWT validation

## 14. Bước Tiếp Theo

Bạn muốn tôi tạo boilerplate code cho service nào trước?

1. **Backend Service** (PostgreSQL + FastAPI)
   - Auth, Users, Courses, Progress, Vocabulary
   
2. **AI Service** (MongoDB + FastAPI + AI models)
   - Chat, Pronunciation, STT/TTS, Analysis

3. **Flutter API Integration**
   - API clients, DI updates, error handling

---

Tài liệu này cung cấp đầy đủ thông tin về kiến trúc hybrid microservices cho LexiLingo, phù hợp với team nhỏ và dễ implement.
