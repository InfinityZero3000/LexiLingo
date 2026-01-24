# Architectural Diagram for LexiLingo Application
┌─────────────────────────────────────────────────────────────────┐
│                    FLUTTER APP (Frontend)                        │
│                  Clean Architecture (Như hiện tại)               │
└────────────────┬────────────────────────┬───────────────────────┘
                 │                        │
                 │                        │
         ┌───────▼────────┐      ┌───────▼────────┐
         │  API Client 1  │      │  API Client 2  │
         │ (User/Course)  │      │   (AI Chat)    │
         └───────┬────────┘      └───────┬────────┘
                 │                        │
                 │                        │
    ┌────────────▼──────────┐  ┌─────────▼──────────────┐
    │                       │  │                         │
    │   BACKEND SERVICE     │  │     AI SERVICE          │
    │   (FastAPI/Django)    │  │     (FastAPI)           │
    │                       │  │                         │
    │   Port: 8000          │  │   Port: 8001            │
    │                       │  │                         │
    ├───────────────────────┤  ├─────────────────────────┤
    │ • Authentication      │  │ • Qwen NLP              │
    │ • User Management     │  │ • LLaMA3-VI             │
    │ • Course CRUD         │  │ • HuBERT                │
    │ • Progress Tracking   │  │ • STT/TTS               │
    │ • Vocabulary Lists    │  │ • AI Orchestrator       │
    │ • Notifications       │  │ • Pronunciation         │
    │ • Achievements        │  │                         │
    └───────────┬───────────┘  └────────────┬────────────┘
                │                           │
                │                           │
                ▼                           ▼
    ┌───────────────────────┐  ┌───────────────────────┐
    │                       │  │                        │
    │    PostgreSQL         │  │      MongoDB           │
    │                       │  │                        │
    ├───────────────────────┤  ├────────────────────────┤
    │ • users               │  │ • chat_sessions        │
    │ • courses             │  │ • messages             │
    │ • lessons             │  │ • ai_analysis          │
    │ • user_progress       │  │ • conversation_context │
    │ • vocabulary          │  │ • model_cache          │
    │ • achievements        │  │ • knowledge_graph      │
    │ • notifications       │  │ • embeddings           │
    │ • enrollments         │  │                        │
    └───────────────────────┘  └────────────────────────┘
    
    ┌─────────────────────────────────────────────────┐
    │         SHARED: Redis Cache (Optional)          │
    │  • Session tokens                               │
    │  • Learner profiles                             │
    │  • Common AI responses                          │
    └─────────────────────────────────────────────────┘

# Project Structure for LexiLingo Application
LexiLingo/
│
├── flutter-app/                # Flutter Frontend (Đã có)
│   ├── lib/
│   │   ├── core/
│   │   │   ├── network/
│   │   │   │   ├── api_client.dart          # Backend API
│   │   │   │   └── ai_api_client.dart       # AI Service API
│   │   └── features/
│
├── LexiLingo_backend/          # Backend Service (NEW)
│   ├── app/
│   │   ├── main.py             # FastAPI app
│   │   ├── config.py           # Database config
│   │   ├── models/             # SQLAlchemy models
│   │   ├── routes/
│   │   │   ├── auth.py         # /api/auth/*
│   │   │   ├── users.py        # /api/users/*
│   │   │   ├── courses.py      # /api/courses/*
│   │   │   ├── vocab.py        # /api/vocabulary/*
│   │   │   └── progress.py     # /api/progress/*
│   │   ├── services/           # Business logic
│   │   └── database/
│   │       └── postgres.py     # PostgreSQL connection
│   ├── requirements.txt
│   ├── .env
│   └── Dockerfile
│
└── LexiLingo_ai_service/       # AI Service (NEW)
    ├── app/
    │   ├── main.py             # FastAPI app
    │   ├── config.py           # MongoDB config
    │   ├── routes/
    │   │   ├── chat.py         # /api/chat/*
    │   │   ├── analyze.py      # /api/ai/analyze
    │   │   ├── pronunciation.py # /api/ai/pronunciation
    │   │   └── stt_tts.py      # /api/ai/stt, /api/ai/tts
    │   ├── services/
    │   │   ├── orchestrator.py # AI orchestrator
    │   │   ├── qwen_service.py
    │   │   ├── llama_service.py
    │   │   └── hubert_service.py
    │   ├── models/             # MongoDB schemas
    │   └── database/
    │       └── mongodb.py      # MongoDB connection
    ├── requirements.txt
    ├── .env
    └── Dockerfile