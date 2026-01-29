# AI Service

> AI chat, text analysis, and learning analytics service.

[![FastAPI](https://img.shields.io/badge/FastAPI-0.109-009688?logo=fastapi)](https://fastapi.tiangolo.com/)
[![MongoDB](https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb)](https://www.mongodb.com/)

---

## Features

### 🤖 AI Chat (Gemini)
- Context-aware conversations với AI tutor
- Session management với message history
- Language learning focused responses
- Multi-language support

### 📝 Text Analysis
- Grammar checking & correction
- Vocabulary extraction
- Fluency scoring
- Error pattern detection

### 📊 Learning Analytics
- User learning patterns
- Common error analysis
- Progress recommendations
- Interaction statistics

### 💬 Chat Management
- Session creation & retrieval
- Message history
- Conversation context

---

## API Endpoints

```
/api/v1
├── /chat
│   ├── POST /sessions             — Create chat session
│   ├── POST /messages             — Send message, get AI response
│   ├── GET /sessions/{id}/messages — Get session history
│   └── GET /sessions/user/{id}    — User's sessions
│
├── /ai
│   ├── POST /interactions         — Log AI interaction
│   ├── GET /interactions/user/{id} — User's history
│   ├── POST /{id}/feedback        — Submit feedback
│   └── GET /analytics/user/{id}/errors — Error analytics
│
├── /users
│   ├── GET /{id}/learning-pattern — Learning patterns
│   └── GET /{id}/stats            — AI interaction stats
│
└── /health                        — Service health
```

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | FastAPI |
| Database | MongoDB |
| AI | Google Gemini API |
| Async Driver | Motor |

---

## Project Structure

```
ai-service/
├── api/
│   ├── core/              # Config, database
│   ├── models/            # Pydantic schemas
│   ├── routes/            # API endpoints
│   ├── services/          # Business logic
│   │   └── qwen_engine.py # AI engine
│   └── main.py
├── config/                # MongoDB config
├── scripts/               # DB initialization
├── requirements.txt
└── Dockerfile
```

---

## Data Models

### Chat Session
```json
{
  "session_id": "uuid",
  "user_id": "string",
  "title": "Conversation Title",
  "created_at": "2024-01-01T00:00:00Z",
  "message_count": 10
}
```

### AI Interaction
```json
{
  "user_id": "string",
  "session_id": "uuid",
  "interaction_type": "chat|grammar_check|vocabulary",
  "input_text": "User input",
  "ai_response": { ... },
  "feedback": { "rating": 5 }
}
```

### Learning Pattern
```json
{
  "user_id": "string",
  "common_errors": ["article", "tense"],
  "strengths": ["vocabulary", "pronunciation"],
  "recommendations": ["Focus on grammar"],
  "stats": { "total_interactions": 150 }
}
```

---

## Configuration

Required environment variables:

| Variable | Description |
|----------|-------------|
| `MONGODB_URI` | MongoDB connection string |
| `GEMINI_API_KEY` | Google Gemini API key |

Optional:
- `MONGODB_DB_NAME` — Database name (default: lexilingo)
- `ALLOWED_ORIGINS` — CORS origins
- `RATE_LIMIT_PER_MINUTE` — API rate limiting

---

## Related Services

- **Backend Service** — User & course data at port 8000
- **Flutter App** — Mobile/Web frontend

---

## License

MIT License
