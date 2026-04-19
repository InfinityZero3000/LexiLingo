# Flutter App

> Cross-platform language learning application for iOS, Android, and Web.

[![Flutter](https://img.shields.io/badge/Flutter-3.24.0-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.8.1-0175C2?logo=dart)](https://dart.dev)

---

## Features

### 🎓 Learning
- **AI Chat Tutor** — Practice with Gemini-powered AI
- **Structured Courses** — Multi-level curriculum (A1→C2)
- **Lessons & Exercises** — Interactive learning activities
- **Learning Sessions** — Timed practice with XP rewards

### 📚 Vocabulary
- **Personal Library** — Save and organize words
- **Word of the Day** — Daily vocabulary notifications
- **Smart Search** — Find words quickly
- **Review System** — Track learning progress

### 📈 Progress & Gamification
- **XP & Levels** — Earn experience points
- **Streaks** — Maintain daily learning habits
- **Achievements** — Unlock badges and milestones
- **Statistics** — Track learning analytics

### 🔐 Authentication
- **Google Sign-In** — Quick OAuth login
- **Email/Password** — Traditional authentication
- **Firebase Integration** — Secure user management

### 🔔 Engagement
- **Push Notifications** — Learning reminders
- **Daily Goals** — Set and track targets
- **Offline Mode** — Learn without internet

---

## Architecture

Clean Architecture với 3 layers:

```
lib/
├── core/                     # Shared infrastructure
│   ├── di/                  # Dependency Injection (GetIt)
│   ├── network/             # API clients
│   ├── services/            # Shared services
│   └── theme/               # App theming
│
└── features/                 # Feature modules
    ├── auth/                # Authentication
    ├── chat/                # AI Chat
    ├── course/              # Courses & Lessons
    ├── learning/            # Learning Sessions
    ├── vocabulary/          # Vocabulary Management
    ├── progress/            # Progress Tracking
    ├── notifications/       # Push Notifications
    └── home/                # Dashboard
```

Each feature follows:
```
feature/
├── domain/          # Business logic (entities, use cases)
├── data/            # Data layer (models, repositories)
└── presentation/    # UI layer (pages, providers)
```

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.24 |
| Language | Dart 3.8 |
| State | Provider |
| DI | GetIt |
| Local DB | SQLite (sqflite) |
| Auth | Firebase Auth |
| AI | Google Generative AI |

---

## Data Flow

```
UI (Widgets)
    ↓
Provider (State)
    ↓
Use Case (Business Logic)
    ↓
Repository (Data Access)
    ↓
Data Source
├── Remote → Backend API / AI Service
└── Local  → SQLite Database
```

---

## API Integration

```dart
// Environment configuration
API_BASE_URL=https://lexilingo-4gu6.onrender.com/api/v1
GEMINI_API_KEY=your_key
```

For local development, you can override `API_BASE_URL` to `http://localhost:8000/api/v1`.

The app connects to:
- **Backend Service** (port 8000) — User, courses, progress
- **AI Service** (port 8001) — Chat, analytics

## Vercel Production Deploy Checklist

Use this checklist to prevent Google OAuth and env drift in production/preview deploys.

1. `flutter-app/.env.production` is the single source of production config.
2. `flutter-app/web/index.html` `google-signin-client_id` matches `GOOGLE_SERVER_CLIENT_ID` in `.env.production`.
3. `flutter-app/lib/firebase_options.dart` points to the same Firebase project used by production OAuth credentials.
4. Firebase Console -> Authentication -> Settings -> Authorized domains contains:
    - production domain (for example your custom domain)
    - Vercel preview domain pattern being used for testing
5. Deploy with the Flutter Vercel script (prebuilt flow):

```bash
bash scripts/deploy-flutter-vercel.sh
```

This script enforces `.env.production` usage for release build, validates Google client ID sync, and deploys using `vercel deploy --prebuilt --prod`.

---

## Platforms

| Platform | Minimum Version |
|----------|-----------------|
| iOS | 13.0+ |
| Android | API 24 (7.0) |
| Web | Modern browsers |

---

## Related Services

- **Backend Service** — REST API at port 8000
- **AI Service** — AI chat at port 8001

---

## License

MIT License
