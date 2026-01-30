# LexiLingo

**Intelligent Language Learning Platform with AI-Powered Assessment and Personalized Learning Paths**

[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white)](https://www.python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14+-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[![Build](https://img.shields.io/badge/build-passing-success)](https://github.com/InfinityZero3000/LexiLingo)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20Web-lightgrey)](https://github.com/InfinityZero3000/LexiLingo)
[![API](https://img.shields.io/badge/API-REST%20%7C%20WebSocket-informational)](https://github.com/InfinityZero3000/LexiLingo)

---

## Overview

LexiLingo is an enterprise-grade language learning platform that leverages artificial intelligence and machine learning to provide personalized, adaptive learning experiences. The system employs a microservices architecture with specialized services for assessment, recommendation, and real-time interaction.

**Key Capabilities:**
- AI-driven language proficiency assessment (CEFR-aligned)
- Deep learning models for fluency, vocabulary, and grammatical analysis
- Adaptive learning paths with real-time progress tracking
- Gamified learning experience with achievement systems
- Multi-platform support (iOS, Android, Web)

---

## System Architecture

LexiLingo implements a **microservices architecture** with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client Layer                             │
│              (Flutter - iOS / Android / Web)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                      API Gateway Layer                          │
│                   (Load Balancing / Routing)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ↓               ↓               ↓
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ Backend  │    │    AI    │    │   DL     │
    │ Service  │    │ Service  │    │  Model   │
    └────┬─────┘    └────┬─────┘    └────┬─────┘
         │               │               │
         └───────────────┴───────────────┘
                         │
              ┌──────────┴──────────┐
              ↓                     ↓
        ┌──────────┐          ┌──────────┐
        │PostgreSQL│          │  Redis   │
        │          │          │  Cache   │
        └──────────┘          └──────────┘
```

### Service Components

**Backend Service (FastAPI)**
- User authentication and authorization (JWT)
- Course management and curriculum delivery
- Progress tracking and analytics
- Gamification engine (XP, achievements, leaderboards)

**AI Service (FastAPI)**
- Language assessment engine
- Conversational AI integration (Google Gemini)
- Speech-to-Text and Text-to-Speech processing
- Real-time feedback generation

**DL Model Service**
- Fine-tuned Qwen 2.5 model for language analysis
- Fluency scoring algorithms
- Vocabulary complexity assessment
- Grammatical error detection

**Client Application (Flutter)**
- Cross-platform native experience
- Offline-first architecture
- Real-time synchronization
- Responsive UI/UX design

---

## Core Features

### Intelligent Assessment System
- **CEFR-aligned Proficiency Testing**: Automated language level assessment (A1-C2)
- **Multi-dimensional Analysis**: Fluency, vocabulary, grammar, and pronunciation scoring
- **Adaptive Question Generation**: Dynamic difficulty adjustment based on performance
- **Real-time Feedback**: Instant error detection and correction suggestions

### Personalized Learning Engine
- **AI-driven Learning Paths**: Customized curriculum based on proficiency and goals
- **Spaced Repetition System**: Optimized vocabulary retention algorithms
- **Progress Analytics**: Comprehensive learning metrics and insights
- **Adaptive Content Delivery**: Dynamic lesson difficulty and pacing

### Gamification Framework
- **Experience Points (XP)**: Progress-based reward system
- **Achievement Badges**: Milestone recognition and motivation
- **Streak Tracking**: Daily engagement monitoring
- **Leaderboards**: Competitive learning environment

### Interactive Learning
- **Conversational AI**: Practice with AI tutors powered by large language models
- **Speech Recognition**: Real-time pronunciation assessment
- **Interactive Exercises**: Multiple question types and formats
- **Multimedia Content**: Audio, visual, and text-based learning materials

### Enterprise Capabilities
- **Multi-tenant Architecture**: Scalable for institutions and organizations
- **REST & WebSocket APIs**: Real-time data synchronization
- **Offline Support**: Local caching and background sync
- **Analytics Dashboard**: Detailed learning insights and reporting

---

## Technology Stack

### Backend Services
| Component | Technology | Purpose |
|-----------|-----------|---------|
| API Framework | FastAPI | High-performance async APIs |
| Database | PostgreSQL 14+ | Relational data storage |
| Cache Layer | Redis | Session management and caching |
| Authentication | JWT | Secure token-based auth |
| ORM | SQLAlchemy | Database abstraction |
| Migration | Alembic | Schema version control |

### AI & Machine Learning
| Component | Technology | Purpose |
|-----------|-----------|---------|
| LLM | Qwen 2.5 (Fine-tuned) | Language analysis and generation |
| Framework | Unsloth | Efficient model training |
| Inference | llama.cpp (GGUF) | Optimized model serving |
| Conversational AI | Google Gemini API | Interactive tutoring |
| Speech Processing | Whisper / TTS APIs | Voice interaction |

### Frontend Application
| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | Flutter | 3.24+ |
| Language | Dart | 3.8+ |
| State Management | Provider | 6.1+ |
| Dependency Injection | GetIt | 8.0+ |
| Local Storage | SQLite | Latest |
| HTTP Client | Dio | 5.0+ |

### Infrastructure & DevOps
| Component | Technology | Purpose |
|-----------|-----------|---------|
| Containerization | Docker | Service deployment |
| Orchestration | Docker Compose | Multi-service management |
| CI/CD | GitHub Actions | Automated testing and deployment |
| API Documentation | OpenAPI/Swagger | Interactive API docs |

---

## Project Structure

```
LexiLingo/
├── backend-service/          # Core backend API service
│   ├── app/
│   │   ├── core/            # Configuration and security
│   │   ├── models/          # SQLAlchemy ORM models
│   │   ├── routes/          # API endpoints
│   │   ├── schemas/         # Pydantic schemas
│   │   └── crud/            # Database operations
│   ├── alembic/             # Database migrations
│   └── tests/               # Backend test suite
│
├── ai-service/              # AI and ML service
│   ├── api/                 # FastAPI application
│   ├── models/              # ML model artifacts
│   ├── config/              # Service configuration
│   └── scripts/             # Utility scripts
│
├── flutter-app/             # Cross-platform client
│   ├── lib/
│   │   ├── core/           # Core utilities and DI
│   │   ├── features/       # Feature modules
│   │   │   ├── auth/       # Authentication
│   │   │   ├── learning/   # Learning sessions
│   │   │   ├── course/     # Course management
│   │   │   └── user/       # User profile
│   │   └── main.dart       # Application entry
│   └── test/               # Flutter test suite
│
├── DL-Model-Support/        # Deep learning pipeline
│   ├── datasets/           # Training datasets
│   ├── scripts/            # Training scripts
│   ├── export/             # Model export utilities
│   └── docs/               # Model documentation
│
├── scripts/                # Development scripts
│   ├── setup-all.sh       # Environment setup
│   ├── start-all.sh       # Start all services
│   └── stop-all.sh        # Stop all services
│
└── docs/                   # System documentation
    ├── architecture.md     # Architecture overview
    ├── api/               # API documentation
    └── guides/            # Development guides
```

---

## Quick Start

### Prerequisites
- Python 3.11+
- Flutter SDK 3.24+
- PostgreSQL 14+
- Docker & Docker Compose (optional)

### Local Development

```bash
# Clone repository
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo

# Setup all services
bash scripts/setup-all.sh

# Start all services
bash scripts/start-all.sh
```

### Service Endpoints

| Service | URL | Documentation |
|---------|-----|---------------|
| Backend API | http://localhost:8000 | http://localhost:8000/docs |
| AI Service | http://localhost:8001 | http://localhost:8001/docs |
| Flutter Web | http://localhost:8080 | - |

### Docker Deployment

```bash
# Build and start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

---

## API Documentation

Interactive API documentation is available via Swagger UI:

- **Backend API**: http://localhost:8000/docs
- **AI Service**: http://localhost:8001/docs

### Key Endpoints

**Authentication**
```
POST   /auth/register          Register new user
POST   /auth/login            User login
POST   /auth/refresh          Refresh access token
GET    /auth/me               Get current user
```

**Learning**
```
GET    /courses               List available courses
POST   /learning/lessons/{id}/start     Start lesson
POST   /learning/attempts/{id}/answer   Submit answer
POST   /learning/attempts/{id}/complete Complete lesson
GET    /learning/courses/{id}/roadmap   Get progress
```

**Assessment**
```
POST   /ai/assess/fluency     Analyze fluency
POST   /ai/assess/vocabulary  Assess vocabulary level
POST   /ai/chat              Conversational interaction
```

---

## Development

### Architecture Principles

The system follows industry best practices:

- **Clean Architecture**: Clear separation of concerns
- **Domain-Driven Design**: Business logic isolation
- **SOLID Principles**: Maintainable and extensible code
- **Repository Pattern**: Data access abstraction
- **Dependency Injection**: Loose coupling

### Code Quality

- **Static Analysis**: Automated code quality checks
- **Unit Testing**: Comprehensive test coverage
- **Integration Testing**: End-to-end API testing
- **Code Reviews**: Mandatory peer reviews
- **CI/CD Pipeline**: Automated testing and deployment

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and coding standards.

---

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | System architecture and design |
| [API Reference](docs/api/) | Complete API documentation |
| [Development Guide](QUICKSTART.md) | Setup and development workflow |
| [Git Workflow](GIT_WORKFLOW.md) | Git branching and commit standards |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Contact & Support

- **Issues**: [GitHub Issues](https://github.com/InfinityZero3000/LexiLingo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/InfinityZero3000/LexiLingo/discussions)
- **Documentation**: [Project Wiki](https://github.com/InfinityZero3000/LexiLingo/wiki)

---

<div align="center">

**LexiLingo** - Intelligent Language Learning Platform

[Documentation](https://github.com/InfinityZero3000/LexiLingo/wiki) • [API Reference](http://localhost:8000/docs) • [Report Issue](https://github.com/InfinityZero3000/LexiLingo/issues)

</div>
