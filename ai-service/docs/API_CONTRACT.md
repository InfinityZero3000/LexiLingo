# LexiLingo API Contract

> **Version**: 1.0.0  
> **Last Updated**: January 16, 2026  
> **Base URL**: `https://api.lexilingo.com` (Production) | `http://localhost:8000` (Development)

---

## Table of Contents

1. [Backend API (FastAPI)](#1-backend-api-fastapi) - For Flutter App
2. [DL-Model-Support API Contract](#2-dl-model-support-api-contract) - For AI Models
3. [Authentication](#3-authentication)
4. [Error Handling](#4-error-handling)
5. [Rate Limiting](#5-rate-limiting)

---

## 1. Backend API (FastAPI)

**Base URL**: `http://localhost:8000`

### 1.1 Health & Status

#### GET `/health`

Check system health and service availability.

**Response** (200 OK):
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "environment": "development",
  "services": {
    "mongodb": true,
    "redis": true,
    "ai_model": false
  }
}
```

#### GET `/ping`

Simple ping for quick health check.

**Response** (200 OK):
```json
{
  "ping": "pong",
  "timestamp": "2026-01-16T10:30:00.000Z"
}
```

---

### 1.2 AI Interactions

#### POST `/api/v1/ai/interactions`

Log AI interaction for learning analytics.

**Request Body**:
```json
{
  "user_id": "user_123",
  "session_id": "session_abc",
  "interaction_type": "grammar_check",
  "input_text": "I goes to school yesterday",
  "ai_response": {
    "fluency_score": 0.75,
    "vocabulary_level": "A2",
    "grammar_errors": [
      {
        "type": "verb_tense",
        "error": "goes",
        "correction": "went",
        "explanation": "Use past tense with 'yesterday'"
      }
    ],
    "tutor_response": "Good attempt! Remember to use past tense..."
  },
  "context": {
    "learner_level": "B1",
    "previous_errors": ["past_tense"]
  }
}
```

**Response** (200 OK):
```json
{
  "interaction_id": "int_xyz789",
  "message": "Interaction logged successfully"
}
```

**Errors**:
- `500`: Failed to log interaction

---

#### GET `/api/v1/ai/interactions/user/{user_id}`

Get user's interaction history.

**Query Parameters**:
- `limit` (optional, default=100): Number of interactions to return
- `skip` (optional, default=0): Number of interactions to skip

**Response** (200 OK):
```json
[
  {
    "_id": "64a1b2c3d4e5f6789abc",
    "user_id": "user_123",
    "session_id": "session_abc",
    "interaction_type": "grammar_check",
    "timestamp": "2026-01-16T10:15:00.000Z",
    "user_input": {
      "text": "I goes to school yesterday"
    },
    "analysis": {
      "fluency_score": 0.75,
      "grammar_errors": [...]
    }
  }
]
```

---

#### GET `/api/v1/ai/interactions/session/{session_id}`

Get all interactions in a chat session.

**Response** (200 OK):
```json
[
  {
    "interaction_id": "int_1",
    "timestamp": "2026-01-16T10:00:00.000Z",
    "user_input": {...},
    "ai_response": {...}
  },
  {
    "interaction_id": "int_2",
    "timestamp": "2026-01-16T10:05:00.000Z",
    "user_input": {...},
    "ai_response": {...}
  }
]
```

---

#### POST `/api/v1/ai/interactions/{interaction_id}/feedback`

Update interaction with user feedback.

**Request Body**:
```json
{
  "helpful": true,
  "applied_correction": true,
  "comment": "Very clear explanation!"
}
```

**Response** (200 OK):
```json
{
  "message": "Feedback updated successfully"
}
```

**Errors**:
- `404`: Interaction not found

---

#### GET `/api/v1/ai/analytics/user/{user_id}/errors`

Get user's error statistics.

**Query Parameters**:
- `days` (optional, default=30): Number of days to analyze

**Response** (200 OK):
```json
[
  {
    "_id": "verb_tense",
    "count": 15,
    "percentage": 0.35,
    "recent_examples": [
      {
        "text": "I goes to school",
        "correction": "I go to school",
        "timestamp": "2026-01-15T14:00:00.000Z"
      }
    ]
  },
  {
    "_id": "articles",
    "count": 8,
    "percentage": 0.19
  }
]
```

---

### 1.3 Chat (Gemini AI)

#### POST `/api/v1/chat/sessions`

Create a new chat session.

**Request Body**:
```json
{
  "user_id": "user_123",
  "title": "English Practice Session"
}
```

**Response** (200 OK):
```json
{
  "session_id": "session_abc123",
  "title": "English Practice Session",
  "created_at": "2026-01-16T10:00:00.000Z"
}
```

---

#### POST `/api/v1/chat/messages`

Send message and get AI response.

**Request Body**:
```json
{
  "session_id": "session_abc123",
  "user_id": "user_123",
  "message": "Hello! Can you help me with English grammar?"
}
```

**Response** (200 OK):
```json
{
  "message_id": "msg_xyz456",
  "ai_response": "Hello! I'd be happy to help you with English grammar. What would you like to learn about?",
  "analysis": {
    "fluency_score": 0.92,
    "grammar_errors": [],
    "vocabulary_level": "B2"
  },
  "processing_time_ms": 850
}
```

**Errors**:
- `503`: Gemini API not configured
- `500`: Failed to send message

---

#### GET `/api/v1/chat/sessions/{session_id}/messages`

Get session chat history.

**Query Parameters**:
- `limit` (optional, default=100): Number of messages to return

**Response** (200 OK):
```json
[
  {
    "id": "msg_1",
    "session_id": "session_abc123",
    "content": "Hello! Can you help me?",
    "role": "user",
    "timestamp": "2026-01-16T10:00:00.000Z"
  },
  {
    "id": "msg_2",
    "session_id": "session_abc123",
    "content": "Of course! I'd be happy to help.",
    "role": "ai",
    "timestamp": "2026-01-16T10:00:01.000Z"
  }
]
```

---

#### GET `/api/v1/chat/sessions/user/{user_id}`

Get all sessions for a user.

**Query Parameters**:
- `limit` (optional, default=20): Number of sessions to return

**Response** (200 OK):
```json
[
  {
    "session_id": "session_abc123",
    "user_id": "user_123",
    "title": "English Practice Session",
    "created_at": "2026-01-16T10:00:00.000Z",
    "last_activity": "2026-01-16T10:30:00.000Z",
    "message_count": 15
  }
]
```

---

### 1.4 User Data

#### GET `/api/v1/users/{user_id}/learning-pattern`

Get user's learning pattern analysis.

**Response** (200 OK):
```json
{
  "user_id": "user_123",
  "analyzed_at": "2026-01-16T10:00:00.000Z",
  "common_errors": [
    {
      "type": "verb_tense",
      "count": 15,
      "percentage": 0.35
    },
    {
      "type": "articles",
      "count": 8,
      "percentage": 0.19
    }
  ],
  "strengths": [
    "vocabulary",
    "pronunciation"
  ],
  "improvement_rate": {
    "last_7_days": 0.15,
    "last_30_days": 0.28
  },
  "recommended_focus": [
    "past_tense_practice",
    "article_usage"
  ],
  "stats": {
    "total_interactions": 120,
    "avg_fluency_score": 0.82,
    "study_streak_days": 15
  }
}
```

**Errors**:
- `404`: No learning pattern found for user

---

#### GET `/api/v1/users/{user_id}/stats`

Get user statistics summary.

**Response** (200 OK):
```json
{
  "total_interactions": 120,
  "avg_fluency_score": 0.82,
  "common_errors": [
    "verb_tense",
    "articles"
  ],
  "improvement_rate": {
    "weekly": 0.15,
    "monthly": 0.28
  },
  "study_streak_days": 15
}
```

---

## 2. DL-Model-Support API Contract

**Base URL**: `http://localhost:8001`

> Note: **Note**: DL-Model-Support team implements this API

### 2.1 Text Analysis (Qwen + Unified Adapter)

#### POST `/api/v1/analyze`

Comprehensive text analysis with Qwen2.5-1.5B + Unified LoRA Adapter.

**Request Body**:
```json
{
  "text": "I goes to school yesterday",
  "context": {
    "user_id": "user_123",
    "learner_level": "B1",
    "common_errors": ["past_tense"],
    "history": [
      {
        "user": "I am learning English",
        "ai": "Great! Let's practice together."
      }
    ]
  },
  "model": "qwen-unified",
  "tasks": ["fluency", "grammar", "vocabulary", "tutor"]
}
```

**Response** (200 OK):
```json
{
  "fluency_score": 0.75,
  "vocabulary_level": "A2",
  "grammar_errors": [
    {
      "type": "verb_tense",
      "error": "goes",
      "correction": "went",
      "start_pos": 2,
      "end_pos": 6,
      "explanation": "Use past tense 'went' with time marker 'yesterday'",
      "rule": "Simple Past Tense"
    },
    {
      "type": "subject_verb_agreement",
      "error": "goes",
      "correction": "go",
      "start_pos": 2,
      "end_pos": 6,
      "explanation": "Use 'go' with subject 'I'",
      "rule": "Subject-Verb Agreement"
    }
  ],
  "tutor_response": "Good attempt! I notice you used 'goes' with 'yesterday'. Remember, when talking about the past, we use past tense verbs. Try: 'I went to school yesterday.' Would you like to practice more past tense verbs?",
  "processing_time_ms": 120,
  "model_info": {
    "name": "qwen-2.5-1.5b",
    "adapter": "unified-lora-r48",
    "version": "1.0"
  }
}
```

**Errors**:
- `400`: Invalid request (missing text)
- `500`: Model inference failed
- `503`: Model not loaded

---

### 2.2 Pronunciation Analysis (HuBERT)

#### POST `/api/v1/pronunciation`

Analyze pronunciation with HuBERT-large.

**Request** (multipart/form-data):
- `audio`: Audio file (WAV format, 16kHz)
- `transcript`: Expected text for forced alignment

**Example**:
```bash
curl -X POST http://localhost:8001/api/v1/pronunciation \
  -F "audio=@recording.wav" \
  -F "transcript=I went to school yesterday"
```

**Response** (200 OK):
```json
{
  "phoneme_accuracy": 0.85,
  "overall_score": 0.82,
  "errors": [
    {
      "phoneme": "/θ/",
      "actual": "/s/",
      "word": "think",
      "position": 2.5,
      "severity": "medium",
      "suggestion": "Place tongue between teeth for /θ/ sound"
    }
  ],
  "word_scores": [
    {
      "word": "I",
      "score": 0.95,
      "phonemes": ["/aɪ/"]
    },
    {
      "word": "went",
      "score": 0.88,
      "phonemes": ["/w/", "/ɛ/", "/n/", "/t/"]
    }
  ],
  "prosody_score": 0.78,
  "prosody_feedback": {
    "stress_pattern": "good",
    "intonation": "needs_improvement",
    "rhythm": "good"
  },
  "processing_time_ms": 150
}
```

**Errors**:
- `400`: Invalid audio format
- `413`: Audio file too large (max 10MB)
- `500`: Pronunciation analysis failed

---

### 2.3 Vietnamese Explanation (LLaMA3-8B-VI)

#### POST `/api/v1/explain-vi`

Get Vietnamese explanation (lazy load, triggered conditionally).

**Trigger Conditions**:
- Learner level is A2
- Confidence < 0.8
- Explicit Vietnamese request

**Request Body**:
```json
{
  "text": "I goes to school yesterday",
  "analysis": {
    "grammar_errors": [
      {
        "type": "verb_tense",
        "error": "goes",
        "correction": "went",
        "explanation": "Use past tense with 'yesterday'"
      }
    ]
  },
  "model": "llama3-vi"
}
```

**Response** (200 OK):
```json
{
  "explanation": "Chào bạn! Mình thấy bạn đã dùng 'goes' với 'yesterday'. Khi nói về quá khứ (yesterday = hôm qua), chúng ta cần dùng thì quá khứ đơn. Động từ 'go' ở thì quá khứ là 'went'. \n\nVí dụ:\n- Hiện tại: I go to school (Tôi đi học)\n- Quá khứ: I went to school yesterday (Tôi đã đi học hôm qua)\n\nHãy thử lại nhé: 'I went to school yesterday.' Bạn làm rất tốt rồi đấy! ",
  "processing_time_ms": 200,
  "model_info": {
    "name": "llama3-8b-vi",
    "load_time_ms": 2000
  }
}
```

**Errors**:
- `500`: Vietnamese explanation failed (gracefully degrade to English only)

---

### 2.4 Model Health

#### GET `/health`

Check DL Model API health.

**Response** (200 OK):
```json
{
  "status": "healthy",
  "models": {
    "qwen-unified": {
      "loaded": true,
      "memory_usage_mb": 1600
    },
    "hubert": {
      "loaded": true,
      "memory_usage_mb": 960
    },
    "llama3-vi": {
      "loaded": false,
      "lazy_load": true
    }
  },
  "gpu_available": true,
  "gpu_memory_used": "3.5GB / 8GB"
}
```

---

## 3. Authentication

### 3.1 Current Implementation (v1.0)

**Status**: No authentication (development phase)

All endpoints are public during development.

### 3.2 Future Implementation (v2.0)

**Planned**: JWT Bearer Token

**Header**:
```
Authorization: Bearer <token>
```

**Token Structure**:
```json
{
  "user_id": "user_123",
  "exp": 1705488000,
  "iat": 1705401600
}
```

---

## 4. Error Handling

### 4.1 Standard Error Response

All errors follow this format:

```json
{
  "detail": "Error message",
  "error_code": "ERROR_CODE",
  "timestamp": "2026-01-16T10:00:00.000Z",
  "path": "/api/v1/chat/messages"
}
```

### 4.2 HTTP Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Success |
| 201 | Created | Resource created |
| 400 | Bad Request | Invalid request body/params |
| 401 | Unauthorized | Missing/invalid auth token |
| 403 | Forbidden | No permission |
| 404 | Not Found | Resource not found |
| 413 | Payload Too Large | File/request too large |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |
| 503 | Service Unavailable | Service down (e.g., Gemini API) |

### 4.3 Graceful Degradation

Backend implements fallbacks:

1. **DL Model API unavailable** → Rule-based analysis
2. **Redis unavailable** → No caching, direct DB
3. **Gemini API unavailable** → Return 503 with message

---

## 5. Rate Limiting

### 5.1 Production Limits

- **General API**: 60 requests/minute per user
- **Chat API**: 20 messages/minute per user
- **File Upload**: 5 files/minute per user

### 5.2 Rate Limit Headers

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1705401660
```

### 5.3 Rate Limit Error

**Response** (429 Too Many Requests):
```json
{
  "detail": "Rate limit exceeded. Try again in 30 seconds.",
  "error_code": "RATE_LIMIT_EXCEEDED",
  "retry_after": 30
}
```

---

## 6. Data Models

### 6.1 GrammarError

```typescript
interface GrammarError {
  type: string;              // "verb_tense", "articles", etc.
  error: string;             // Original error text
  correction: string;        // Corrected text
  start_pos?: number;        // Start position in text
  end_pos?: number;          // End position in text
  explanation: string;       // Human-readable explanation
  rule?: string;             // Grammar rule name
  severity?: "low" | "medium" | "high";
}
```

### 6.2 AIAnalysis

```typescript
interface AIAnalysis {
  fluency_score: number;           // 0-1
  vocabulary_level: string;        // "A1", "A2", "B1", "B2", "C1", "C2"
  grammar_errors: GrammarError[];
  tutor_response: string;
  processing_time_ms: number;
  model_info?: {
    name: string;
    adapter?: string;
    version: string;
  };
}
```

### 6.3 ChatMessage

```typescript
interface ChatMessage {
  id: string;
  session_id: string;
  user_id?: string;
  content: string;
  role: "user" | "ai" | "system";
  timestamp: string;           // ISO 8601
  metadata?: Record<string, any>;
}
```

### 6.4 LearnerProfile

```typescript
interface LearnerProfile {
  user_id: string;
  level: string;               // "A2", "B1", "B2", etc.
  common_errors: string[];     // ["past_tense", "articles"]
  recent_sessions: SessionSummary[];
  stats?: {
    total_interactions: number;
    avg_fluency_score: number;
    study_streak_days: number;
  };
}
```

### 6.5 SessionSummary

```typescript
interface SessionSummary {
  session_id: string;
  title?: string;
  created_at: string;
  last_activity: string;
  message_count: number;
  topics?: string[];
}
```

---

## 7. WebSocket API (Future)

### 7.1 Real-time Chat (Planned v2.0)

**Endpoint**: `ws://localhost:8000/ws/chat/{session_id}`

**Connect**:
```javascript
const ws = new WebSocket('ws://localhost:8000/ws/chat/session_abc');
```

**Send Message**:
```json
{
  "type": "message",
  "content": "Hello, can you help me?",
  "user_id": "user_123"
}
```

**Receive Message**:
```json
{
  "type": "ai_response",
  "message_id": "msg_xyz",
  "content": "Of course! What would you like to learn?",
  "analysis": {...}
}
```

---

## 8. Testing

### 8.1 Postman Collection

Import collection: `docs/postman/LexiLingo_API.json`

### 8.2 Example cURL Commands

**Health Check**:
```bash
curl http://localhost:8000/health
```

**Send Chat Message**:
```bash
curl -X POST http://localhost:8000/api/v1/chat/messages \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test_session",
    "user_id": "test_user",
    "message": "Hello!"
  }'
```

**Log AI Interaction**:
```bash
curl -X POST http://localhost:8000/api/v1/ai/interactions \
  -H "Content-Type: application/json" \
  -d @interaction_sample.json
```

---

## 9. Versioning

### 9.1 API Versioning Strategy

- **Current**: v1 (prefix `/api/v1/`)
- **Breaking changes**: New version `/api/v2/`
- **Non-breaking changes**: Same version, changelog

### 9.2 Deprecation Policy

1. Announce deprecation 3 months in advance
2. Support old version for 6 months
3. Document migration guide
4. Return deprecation warning header:
   ```
   X-API-Deprecation: This endpoint will be deprecated on 2026-06-01
   ```

---

## 10. Support

- **Documentation**: `https://docs.lexilingo.com`
- **API Status**: `https://status.lexilingo.com`
- **Swagger UI**: `http://localhost:8000/docs`
- **ReDoc**: `http://localhost:8000/redoc`

---

**Last Updated**: January 16, 2026  
**Maintained by**: LexiLingo Backend Team
