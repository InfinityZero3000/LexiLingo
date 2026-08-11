# 🚀 Quick Start Guide - LexiLingo Backend

## 📋 Prerequisites

- Python 3.11+
- PostgreSQL 14+
- pip or poetry

## ⚡ Quick Setup

### 1. Clone & Install

```bash
cd backend-service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Environment Configuration

Create `.env` file:
```bash
cp .env.example .env
```

Edit `.env`:
```env
# Database
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/lexilingo

# Security
SECRET_KEY=your-secret-key-here-change-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

# CORS
ALLOWED_ORIGINS=["http://localhost:3000","http://localhost:8080"]

# App
APP_ENV=development
DEBUG=true
PORT=8000
```

### 3. Database Setup

```bash
# Create database
createdb lexilingo

# Run migrations
alembic upgrade head

# Seed sample data (development only, requires running backend + admin auth)
# POST /api/v1/admin/seed
# Optional test seed for proficiency module:
python -m tests.seed_proficiency_data
```

### 4. Run Server

```bash
# Development mode with auto-reload
uvicorn app.main:app --reload --port 8000

# Or use the run script
python -m app.main
```

### 5. Verify Setup

Open browser to:
- **API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health
- **Root**: http://localhost:8000

## 📚 Sample API Requests

### Register User
```bash
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "username": "testuser",
    "password": "password123"
  }'
```

### Login
```bash
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "nhthang312@gmail.com",
    "password": "admin123"
  }'
```

### Get Courses
```bash
curl http://localhost:8000/api/v1/courses \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## 🗂️ Project Structure

```
backend-service/
├── app/
│   ├── core/           # Core functionality
│   ├── models/         # Database models (25 tables)
│   ├── schemas/        # Pydantic schemas
│   ├── routes/         # API endpoints
│   └── main.py         # FastAPI app
├── alembic/            # Database migrations
├── scripts/            # Utility scripts
├── tests/              # Test files
├── .env                # Environment variables
├── alembic.ini         # Alembic config
└── requirements.txt    # Dependencies
```

## 🧪 Testing

```bash
# Run all tests
pytest

# With coverage
pytest --cov=app tests/

# Specific test file
pytest tests/test_auth.py
```

## 📖 Documentation

- **Backend overview**: [README.md](README.md)
- **System architecture**: [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- **Flutter application**: [../flutter-app/README.md](../flutter-app/README.md)

## 🐛 Troubleshooting

### Database Connection Error
```bash
# Check PostgreSQL is running
pg_isready

# Verify credentials
psql $DATABASE_URL
```

### Migration Issues
```bash
# Check current version
alembic current

# Show history
alembic history

# Reset if needed
alembic downgrade base
alembic upgrade head
```

### Port Already in Use
```bash
# Find process using port 8000
lsof -ti:8000

# Kill process
kill -9 $(lsof -ti:8000)
```

## 🔧 Development Tips

### Auto-format Code
```bash
pip install black isort
black app/
isort app/
```

### Type Checking
```bash
pip install mypy
mypy app/
```

### Database Shell
```bash
# PostgreSQL shell
psql $DATABASE_URL

# List tables
\dt

# Describe table
\d users
```

## 🚀 Next Steps

1. ✅ Backend models complete
2. ⏳ Update API routes with response envelopes
3. ⏳ Integrate with Flutter app
4. ⏳ Add comprehensive tests
5. ⏳ Deploy to production

## 📞 Support

- **Issues**: https://github.com/InfinityZero3000/LexiLingo/issues
- **Documentation**: See docs/ folder
- **API Docs**: http://localhost:8000/docs

---

**Happy Coding! 🎉**
