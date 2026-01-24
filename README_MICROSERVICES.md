# LexiLingo - Microservices Architecture

AI-powered language learning platform with microservices architecture.

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                          │
│              (Mobile + Web + Desktop)                   │
└────────────────┬────────────────────┬───────────────────┘
                 │                    │
      ┌──────────▼────────┐   ┌──────▼───────────┐
      │  Backend Service  │   │   AI Service     │
      │   (Port 8000)     │   │   (Port 8001)    │
      │                   │   │                  │
      │  FastAPI          │   │  FastAPI         │
      │  PostgreSQL       │   │  MongoDB         │
      │                   │   │  Redis           │
      └───────────────────┘   └──────────────────┘
```

## 📦 Project Structure

```
LexiLingo/
├── flutter-app/            # Flutter application (Mobile + Web + Desktop)
│   └── ...
│
├── backend-service/        # Backend Service (NEW)
│   ├── app/
│   │   ├── core/          # Config, Database, Security
│   │   ├── models/        # SQLAlchemy models (PostgreSQL)
│   │   ├── schemas/       # Pydantic schemas
│   │   └── routes/        # API endpoints
│   ├── alembic/           # Database migrations
│   ├── requirements.txt
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── ai-service/             # AI Service (RENAMED from LexiLingo_backend)
│   ├── api/
│   │   ├── core/          # Config, MongoDB, Redis
│   │   ├── models/        # MongoDB schemas
│   │   ├── routes/        # AI API endpoints
│   │   └── services/      # AI orchestrator, STT, TTS, etc.
│   ├── models/            # ML models (Qwen, LLaMA, HuBERT, Whisper)
│   ├── requirements.txt
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── docker-compose.yml      # Full stack orchestration (NEW)
└── .env.example           # Environment template (NEW)
```

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Clone repository
cd LexiLingo

# Create .env file
cp .env.example .env

# Edit .env with your credentials:
# - SECRET_KEY (generate with: openssl rand -hex 32)
# - GEMINI_API_KEY (get from https://aistudio.google.com/app/apikey)
nano .env
```

### 2. Start All Services

```bash
# Start all services (PostgreSQL, MongoDB, Redis, Backend, AI Service)
docker-compose up -d

# View logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f backend-service
docker-compose logs -f ai-service

# Stop all services
docker-compose down

# Stop and remove volumes (clean start)
docker-compose down -v
```

### 3. Access Services

Once running, services are available at:

| Service | URL | Documentation |
|---------|-----|---------------|
| **Backend Service** | http://localhost:8000 | http://localhost:8000/docs |
| **AI Service** | http://localhost:8001 | http://localhost:8001/docs |
| **PostgreSQL** | localhost:5432 | User: lexilingo, DB: lexilingo |
| **MongoDB** | localhost:27017 | DB: lexilingo |
| **Redis** | localhost:6379 | - |

### 4. Run Database Migrations

```bash
# Backend Service migrations
docker-compose exec backend-service alembic upgrade head

# Create new migration
docker-compose exec backend-service alembic revision --autogenerate -m "description"
```

## 📚 API Documentation

### Backend Service (Port 8000)

**User & Course Management**

```bash
# Register
POST http://localhost:8000/api/v1/auth/register
{
  "email": "user@example.com",
  "username": "john_doe",
  "password": "password123"
}

# Login
POST http://localhost:8000/api/v1/auth/login
{
  "email": "user@example.com",
  "password": "password123"
}

# Get courses
GET http://localhost:8000/api/v1/courses?language=en&level=A2
Authorization: Bearer <token>

# Get user profile
GET http://localhost:8000/api/v1/users/me
Authorization: Bearer <token>
```

### AI Service (Port 8001)

**AI Chat & Analysis**

```bash
# Create chat session
POST http://localhost:8001/api/v1/chat/sessions
{
  "user_id": "uuid",
  "title": "New Conversation"
}

# Send message
POST http://localhost:8001/api/v1/chat/messages
{
  "session_id": "uuid",
  "message": "Hello, teach me English!"
}

# Get AI interactions
GET http://localhost:8001/api/v1/ai/interactions/user/{user_id}
```

## 🔧 Development

### Individual Service Development

**Backend Service:**
```bash
cd backend-service

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run locally (need PostgreSQL running)
uvicorn app.main:app --reload --port 8000
```

**AI Service:**
```bash
cd ai-service

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run locally (need MongoDB + Redis)
uvicorn api.main:app --reload --port 8001
```

### Flutter App

```bash
cd flutter-app

# Get dependencies
flutter pub get

# Run on mobile/web
flutter run

# Run tests
flutter test
```

## 🧪 Testing

### Backend Service
```bash
cd backend-service
pytest

# With coverage
pytest --cov=app tests/
```

### AI Service
```bash
cd ai-service
pytest

# Test specific module
pytest tests/test_chat.py
```

### Flutter App
```bash
cd flutter-app
flutter test

# Integration tests
flutter test integration_test/
```

## 🔐 Security

### JWT Authentication
- Backend Service issues JWT tokens
- AI Service validates tokens using shared SECRET_KEY
- Access tokens expire in 30 minutes
- Refresh tokens expire in 7 days

### Environment Variables
```bash
# Required for Backend Service
SECRET_KEY=<generated-secret>

# Required for AI Service
GEMINI_API_KEY=<your-api-key>

# Optional
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000
```

## 📊 Technology Stack

### Backend Service
- **Framework**: FastAPI 0.109+
- **Database**: PostgreSQL 16+
- **ORM**: SQLAlchemy 2.0+ (Async)
- **Migrations**: Alembic
- **Auth**: JWT + bcrypt

### AI Service
- **Framework**: FastAPI 0.115+
- **Database**: MongoDB 7.0+
- **Cache**: Redis 7.0+
- **AI Models**: Qwen, LLaMA, HuBERT, Whisper, Piper
- **AI API**: Google Gemini

### Flutter App
- **Framework**: Flutter 3.24+
- **Language**: Dart 3.8+
- **State Management**: Provider
- **DI**: GetIt

## 🚢 Deployment

### Development (Docker Compose)
```bash
docker-compose up -d
```

### Production

**Backend Service:**
- Railway / Render / Fly.io
- Database: Supabase (PostgreSQL) / Neon

**AI Service:**
- RunPod / Vast.ai (GPU for ML models)
- Database: MongoDB Atlas
- Cache: Redis Cloud / Upstash

**Flutter App:**
- Mobile: Play Store / App Store
- Web: Vercel / Netlify / Firebase Hosting

## 📝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

## 🆘 Support

- **Documentation**: `/docs` endpoints
- **Issues**: GitHub Issues
- **Contact**: support@lexilingo.com
