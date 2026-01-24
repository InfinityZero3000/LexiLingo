# LexiLingo Backend Service

FastAPI backend service for user management, courses, vocabulary, and progress tracking.

## 🏗 Architecture

```
backend-service/
├── app/
│   ├── core/              # Core configuration
│   │   ├── config.py      # Settings
│   │   ├── database.py    # PostgreSQL connection
│   │   ├── security.py    # JWT & password hashing
│   │   └── dependencies.py # FastAPI dependencies
│   ├── models/            # SQLAlchemy models
│   │   ├── user.py
│   │   ├── course.py
│   │   ├── vocabulary.py
│   │   └── progress.py
│   ├── schemas/           # Pydantic schemas
│   │   ├── user.py
│   │   ├── auth.py
│   │   ├── course.py
│   │   └── common.py
│   ├── routes/            # API endpoints
│   │   ├── auth.py        # Authentication
│   │   ├── users.py       # User management
│   │   └── courses.py     # Course management
│   └── main.py            # FastAPI application
├── alembic/               # Database migrations
├── tests/                 # Unit tests
├── .env                   # Environment variables
├── requirements.txt       # Python dependencies
├── Dockerfile
└── docker-compose.yml
```

## 🚀 Quick Start

### 1. Local Development (Docker Compose)

```bash
# Create .env file
cp .env.example .env

# Edit .env with your settings (especially SECRET_KEY)

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f backend-app

# Stop services
docker-compose down
```

Services will be available at:
- **API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **PostgreSQL**: localhost:5432

### 2. Local Development (Without Docker)

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Setup PostgreSQL (install locally or use Docker)
docker run -d \
  --name lexilingo-postgres \
  -e POSTGRES_USER=lexilingo \
  -e POSTGRES_PASSWORD=lexilingo_pass \
  -e POSTGRES_DB=lexilingo \
  -p 5432:5432 \
  postgres:16-alpine

# Create .env file
cp .env.example .env

# Run database migrations
alembic upgrade head

# Start development server
uvicorn app.main:app --reload --port 8000
```

## 📚 API Documentation

### Interactive Docs
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Key Endpoints

#### Authentication
```bash
# Register
POST /api/v1/auth/register
{
  "email": "user@example.com",
  "username": "john_doe",
  "password": "securePassword123"
}

# Login
POST /api/v1/auth/login
{
  "email": "user@example.com",
  "password": "securePassword123"
}

# Response
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "user_id": "uuid",
  "username": "john_doe",
  "email": "user@example.com"
}

# Refresh token
POST /api/v1/auth/refresh
{
  "refresh_token": "eyJ..."
}
```

#### Users
```bash
# Get current user profile
GET /api/v1/users/me
Authorization: Bearer <token>

# Update profile
PUT /api/v1/users/me
Authorization: Bearer <token>
{
  "display_name": "John Doe",
  "level": "intermediate"
}
```

#### Courses
```bash
# Get all courses
GET /api/v1/courses?language=en&level=A2
Authorization: Bearer <token>

# Get course by ID
GET /api/v1/courses/{course_id}
Authorization: Bearer <token>

# Get course lessons
GET /api/v1/courses/{course_id}/lessons
Authorization: Bearer <token>
```

## 🗄 Database Migrations

Using Alembic for database version control:

```bash
# Create a new migration
alembic revision --autogenerate -m "description"

# Apply migrations
alembic upgrade head

# Rollback one version
alembic downgrade -1

# View migration history
alembic history

# View current version
alembic current
```

## 🔐 Security

### JWT Tokens
- Access token expires in 30 minutes
- Refresh token expires in 7 days
- Passwords hashed with bcrypt

### Generate SECRET_KEY
```bash
openssl rand -hex 32
```

Add to `.env`:
```
SECRET_KEY=your-generated-secret-key-here
```

## 🧪 Testing

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=app tests/

# Run specific test file
pytest tests/test_auth.py

# Run with verbose output
pytest -v
```

## 📦 Deployment

### Docker (Production)

```bash
# Build image
docker build -t lexilingo-backend-app:latest .

# Run container
docker run -d \
  --name lexilingo-backend-app \
  -p 8000:8000 \
  --env-file .env \
  lexilingo-backend-app:latest
```

### Railway / Render / Fly.io

1. Connect GitHub repository
2. Set environment variables:
   - `DATABASE_URL` (PostgreSQL connection string)
   - `SECRET_KEY`
   - `ALLOWED_ORIGINS`
3. Deploy!

### Environment Variables

Required:
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY` - JWT secret key

Optional:
- `DEBUG` - Debug mode (default: False)
- `ALLOWED_ORIGINS` - CORS origins (default: localhost)
- `LOG_LEVEL` - Logging level (default: INFO)

## 🔗 Integration with Flutter

### API Client Setup

```dart
// lib/core/network/backend_api_client.dart
class BackendApiClient extends Dio {
  BackendApiClient() : super(BaseOptions(
    baseUrl: 'http://localhost:8000/api/v1',
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
  )) {
    interceptors.add(AuthInterceptor());
    interceptors.add(LoggingInterceptor());
  }
}
```

### Example Usage

```dart
// Login
final response = await apiClient.post('/auth/login', data: {
  'email': 'user@example.com',
  'password': 'password123',
});

// Get courses
final courses = await apiClient.get('/courses', 
  options: Options(headers: {
    'Authorization': 'Bearer $token',
  })
);
```

## 📊 Tech Stack

- **Framework**: FastAPI 0.109+
- **Database**: PostgreSQL 16+
- **ORM**: SQLAlchemy 2.0+ (Async)
- **Migrations**: Alembic
- **Auth**: JWT (python-jose) + bcrypt
- **Validation**: Pydantic 2.0+
- **Testing**: pytest + pytest-asyncio

## 🤝 Related Services

- **Backend AI**: AI chat, pronunciation analysis (MongoDB)
- **Flutter App**: Mobile/Web frontend

## 📝 License

MIT License - see LICENSE file

## 🆘 Support

- **Issues**: GitHub Issues
- **Docs**: `/docs` endpoint
- **Contact**: support@lexilingo.com
