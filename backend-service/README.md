# Backend Service

> RESTful API for user management, courses, vocabulary, and progress tracking.

[![FastAPI](https://img.shields.io/badge/FastAPI-0.128-009688?logo=fastapi)](https://fastapi.tiangolo.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](https://www.postgresql.org/)

---

## Features

### 🔐 Authentication
- JWT-based authentication với access/refresh tokens
- Firebase ID token verification (optional)
- Password hashing với bcrypt
- Token rotation & revocation

### 👤 User Management
- User registration & profile management
- Learning preferences (native/target language, level)
- User statistics & public profiles

### 📚 Courses & Learning
- Course catalog với multi-level structure (A1→C2)
- Lessons với vocabulary & exercises
- Enrollment management
- Learning sessions tracking

### 📈 Progress Tracking
- XP & streak tracking
- Lesson completion progress
- Daily goals & study time

### 🏆 Achievements & Notifications
- Achievement system với categories
- Push notification support via FCM
- Device token registration

### 📖 Vocabulary
- Personal vocabulary library
- Word collections & categories
- Review status tracking

---

## API Endpoints

```
/api/v1
├── /auth
│   ├── POST /register     — User registration
│   ├── POST /login        — Login with credentials
│   └── POST /refresh      — Refresh access token
│
├── /users
│   ├── GET /me            — Current user profile
│   ├── GET /me/stats      — Learning statistics
│   ├── PATCH /me/preferences — Update preferences
│   └── GET /{id}/public   — Public profile
│
├── /courses
│   ├── GET /              — List courses
│   ├── GET /{id}          — Course details
│   └── GET /{id}/lessons  — Course lessons
│
├── /progress
│   └── POST /sessions     — Record learning session
│
├── /vocabulary
│   ├── GET /              — User's vocabulary
│   ├── POST /             — Add word
│   └── PATCH /{id}        — Update word
│
├── /achievements
│   ├── GET /              — All achievements
│   └── GET /me            — User's achievements
│
├── /notifications
│   ├── POST /register-device — Register FCM token
│   ├── GET /              — List notifications
│   └── PATCH /{id}/read   — Mark as read
│
└── /health                — Service health check
```

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | FastAPI 0.128+ |
| Database | PostgreSQL 16+ |
| ORM | SQLAlchemy 2.0 (Async) |
| Auth | JWT + bcrypt |
| Validation | Pydantic 2.0+ |

---

## Project Structure

```
backend-service/
├── app/
│   ├── core/              # Config, database, security
│   ├── models/            # SQLAlchemy models
│   ├── schemas/           # Pydantic schemas
│   ├── routes/            # API endpoints
│   └── main.py           
├── alembic/               # Database migrations
├── tests/                 # Unit tests
├── requirements.txt
└── Dockerfile
```

---

## Configuration

Required environment variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY` | JWT secret key |

Optional:
- `AI_SERVICE_URL` — AI service endpoint
- `ALLOWED_ORIGINS` — CORS origins
- `FIREBASE_PROJECT_ID` — Firebase project for auth

---

## Related Services

- **AI Service** — AI chat & analytics at port 8001
- **Flutter App** — Mobile/Web frontend

---

## License

MIT License
