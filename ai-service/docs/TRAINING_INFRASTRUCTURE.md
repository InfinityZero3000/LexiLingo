# Training & Learning Infrastructure

## 📚 Tổng quan

Backend infrastructure để hỗ trợ AI module tự học và cải thiện từ dữ liệu thực tế của users.

**Mục tiêu chính:**
- Ghi lại mọi tương tác AI để phân tích
- Thu thập feedback từ users
- Curate training data cho LoRA fine-tuning
- Theo dõi tiến độ học tập của users
- Phát hiện error patterns
- Track model performance metrics

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRAINING DATA PIPELINE                        │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ AI Model     │    │ User         │    │ Flutter      │
│ Interaction  │    │ Interaction  │    │ App          │
│              │    │              │    │              │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │  AIRepository           │
              │  log_interaction()      │
              │  + Enhanced Metadata    │
              └────────────┬────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ MongoDB      │  │ Auto-Queue   │  │ Quality      │
│ Storage      │  │ High-Quality │  │ Indicators   │
│              │  │ Examples     │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
        ▼                                     ▼
┌──────────────┐                    ┌──────────────┐
│ User Feedback│                    │ Training     │
│ Collection   │                    │ Queue        │
│ (ratings,    │                    │ (curated     │
│  issues)     │                    │  examples)   │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       └───────────────────┬───────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │  Validation             │
              │  (Human-in-the-loop)    │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │  Export for Training    │
              │  (JSONL, CSV, Parquet)  │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │  LoRA Fine-tuning       │
              │  (External ML Pipeline) │
              └─────────────────────────┘
```

---

## 📊 MongoDB Collections

### 1. `ai_interactions`
Lưu trữ mọi tương tác với AI models.

**Schema:**
```json
{
  "_id": ObjectId,
  "session_id": "string",
  "user_id": "string",
  "timestamp": ISODate,
  "user_input": {
    "text": "string",
    "audio_features": {},
    "context": []
  },
  "models_used": ["qwen-unified", "hubert"],
  "processing_time_ms": {
    "qwen": 120,
    "hubert": 150
  },
  "analysis": {
    "fluency_score": 0.87,
    "vocabulary_level": "B1",
    "grammar_errors": [...],
    "tutor_response": "string"
  },
  "user_feedback": {...},
  "quality_indicators": {
    "has_grammar_errors": true,
    "error_count": 2,
    "fluency_score": 0.87,
    "vocabulary_level": "B1"
  },
  "training_eligible": true,
  "training_validated": false,
  "indexed_at": ISODate
}
```

**Indexes:**
- `user_id`, `session_id`, `timestamp`
- `training_eligible`, `quality_score`
- Composite: `(user_id, timestamp DESC)`
- TTL: 90 days auto-cleanup

---

### 2. `user_feedback`
User feedback trên AI responses.

**Schema:**
```json
{
  "_id": ObjectId,
  "interaction_id": ObjectId,
  "user_id": "string",
  "rating": 4,  // 1-5 stars
  "helpful": true,
  "accurate": true,
  "feedback_text": "Great explanation!",
  "reported_issues": ["incorrect_grammar"],
  "timestamp": ISODate
}
```

**Indexes:**
- `interaction_id`, `user_id`, `rating`
- Composite: `(user_id, timestamp DESC)`

---

### 3. `training_queue`
Curated examples cho LoRA fine-tuning.

**Schema:**
```json
{
  "_id": ObjectId,
  "source_interaction_id": ObjectId,
  "user_id": "string",
  "user_input": "I go to school yesterday",
  "expected_output": {
    "fluency_score": 0.75,
    "grammar_errors": [...]
  },
  "task_types": ["grammar", "fluency"],
  "difficulty_level": "A2",
  "quality_score": 0.85,
  "validated": false,
  "validated_by": null,
  "notes": "Auto-queued",
  "created_at": ISODate,
  "used_in_training": false
}
```

**Indexes:**
- `task_types`, `quality_score`, `validated`
- Composite: `(quality_score DESC, validated)`
- Composite: `(task_types, quality_score DESC)`

---

### 4. `user_progress`
User learning progress snapshots.

**Schema:**
```json
{
  "_id": ObjectId,
  "user_id": "string",
  "snapshot_date": ISODate,
  "level": "B1",
  "fluency_score_avg": 0.82,
  "grammar_accuracy": 0.78,
  "vocabulary_count": 1500,
  "pronunciation_score_avg": 0.85,
  "total_interactions": 150,
  "study_streak_days": 12,
  "common_errors": [
    {"type": "verb_tense", "count": 25},
    {"type": "article", "count": 18}
  ],
  "improvement_trend": "improving"
}
```

**Indexes:**
- `user_id`, `snapshot_date`, `level`
- Composite: `(user_id, snapshot_date DESC)`

---

### 5. `error_patterns`
Detected error patterns across users.

**Schema:**
```json
{
  "_id": ObjectId,
  "error_type": "verb_tense",
  "level": "A2",
  "frequency": 145,
  "affected_users": ["user1", "user2", ...],
  "example_errors": [
    {"error": "go", "correction": "went"},
    ...
  ],
  "detected_at": ISODate
}
```

**Indexes:**
- `error_type`, `level`, `frequency`
- Composite unique: `(error_type, level)`

---

### 6. `model_metrics`
Model performance metrics over time.

**Schema:**
```json
{
  "_id": ObjectId,
  "model_name": "qwen-unified",
  "version": "v1.2.3",
  "metrics": {
    "accuracy": 0.92,
    "f1_score": 0.89,
    "latency_ms": 120
  },
  "metadata": {
    "training_examples": 5000,
    "epochs": 3
  },
  "timestamp": ISODate
}
```

**Indexes:**
- `model_name`, `version`, `timestamp`
- Composite: `(model_name, timestamp DESC)`

---

## 🔌 API Endpoints

### Feedback Collection

#### `POST /api/v1/training/feedback`
Submit user feedback on AI response.

**Request:**
```json
{
  "interaction_id": "507f1f77bcf86cd799439011",
  "user_id": "user123",
  "rating": 4,
  "helpful": true,
  "accurate": true,
  "feedback_text": "Great explanation!",
  "reported_issues": []
}
```

**Response:**
```json
{
  "success": true,
  "message": "Feedback submitted successfully"
}
```

---

#### `GET /api/v1/training/feedback/stats?user_id={id}&days=30`
Get feedback statistics.

**Response:**
```json
{
  "avg_rating": 4.2,
  "total_feedbacks": 150,
  "helpful_percentage": 85.3,
  "accurate_percentage": 92.1
}
```

---

### Training Queue

#### `POST /api/v1/training/training-queue`
Add interaction to training queue.

**Request:**
```json
{
  "interaction_id": "507f1f77bcf86cd799439011",
  "task_types": ["grammar", "fluency"],
  "quality_score": 0.85,
  "notes": "Good example of past tense errors"
}
```

---

#### `GET /api/v1/training/training-queue?task_type=grammar&validated_only=false&min_quality_score=0.7`
Get training examples.

**Response:**
```json
[
  {
    "_id": "...",
    "user_input": "I go to school yesterday",
    "expected_output": {...},
    "task_types": ["grammar"],
    "quality_score": 0.85,
    "validated": false
  }
]
```

---

#### `PUT /api/v1/training/training-queue/{example_id}/validate`
Validate training example (human-in-the-loop).

**Request:**
```json
{
  "approved": true,
  "validated_by": "ml_engineer_1",
  "notes": "Excellent example"
}
```

---

### Progress Tracking

#### `POST /api/v1/training/progress/snapshot`
Save user progress snapshot.

**Request:**
```json
{
  "user_id": "user123",
  "snapshot_date": "2026-01-16T10:00:00Z",
  "level": "B1",
  "fluency_score_avg": 0.82,
  "grammar_accuracy": 0.78,
  "vocabulary_count": 1500,
  "total_interactions": 150,
  "study_streak_days": 12,
  "common_errors": [...]
}
```

---

#### `GET /api/v1/training/progress/history/{user_id}?days=30`
Get progress history for charts.

---

### Error Pattern Analysis

#### `GET /api/v1/training/error-patterns?min_frequency=5`
Get detected error patterns across all users.

**Response:**
```json
[
  {
    "_id": {
      "type": "verb_tense",
      "level": "A2"
    },
    "count": 145,
    "users": ["user1", "user2", ...],
    "examples": [...]
  }
]
```

---

#### `GET /api/v1/training/error-patterns/user/{user_id}?days=30`
Get user-specific error patterns.

---

### Analytics

#### `POST /api/v1/training/analytics`
Get analytics data.

**Request:**
```json
{
  "user_id": "user123",
  "start_date": "2026-01-01",
  "end_date": "2026-01-16",
  "metric": "fluency",
  "group_by": "day"
}
```

**Response:**
```json
{
  "metric": "fluency",
  "data": [
    {"_id": "2026-01-01", "avg_score": 0.75, "count": 10},
    {"_id": "2026-01-02", "avg_score": 0.78, "count": 12},
    ...
  ],
  "summary": {
    "overall_avg": 0.82,
    "min": 0.65,
    "max": 0.95,
    "total_interactions": 150
  }
}
```

---

### Data Export

#### `POST /api/v1/training/export/training-data`
Export training data for LoRA fine-tuning.

**Request:**
```json
{
  "task_types": ["grammar"],
  "min_quality_score": 0.7,
  "validated_only": true,
  "format": "jsonl"
}
```

**Response:**
```json
{
  "export_id": "export_123",
  "data": [
    {
      "input": "I go to school yesterday",
      "output": {...},
      "task_types": ["grammar"],
      "quality_score": 0.85
    }
  ],
  "record_count": 1234,
  "format": "jsonl"
}
```

---

### Model Metrics

#### `POST /api/v1/training/metrics/model-performance`
Log model performance after training.

**Request:**
```json
{
  "model_name": "qwen-unified",
  "version": "v1.2.3",
  "metrics": {
    "accuracy": 0.92,
    "f1_score": 0.89,
    "latency_ms": 120
  },
  "metadata": {
    "training_examples": 5000,
    "epochs": 3
  }
}
```

---

#### `GET /api/v1/training/metrics/model-performance/{model_name}?limit=50`
Get model performance history.

---

## 🔄 Auto-Queuing Logic

System tự động thêm high-quality examples vào training queue:

```python
# Criteria:
1. Has 1-3 grammar errors (good for grammar task) → +0.2 quality
2. Fluency score >= 0.7 (good for fluency task) → +0.2 quality
3. Vocabulary level B2+ (good for vocab task) → +0.1 quality

# Auto-queue if quality_score >= 0.8
if quality_score >= 0.8:
    add_to_training_queue()
```

---

## 📈 Quality Scoring

User feedback được convert sang quality score:

```python
def calculate_quality_score(rating, helpful, accurate):
    score = rating / 5.0  # Normalize to 0-1
    
    if helpful:
        score += 0.1
    
    if accurate:
        score += 0.2
    
    return min(score, 1.0)
```

**Example:**
- Rating 5/5 + helpful + accurate = 1.0 (perfect)
- Rating 4/5 + helpful + accurate = 1.0 (capped)
- Rating 3/5 + not helpful + not accurate = 0.6 (low)

---

## 🚨 Flagging System

Low-quality responses được flag để human review:

```python
# Auto-flag if:
- rating <= 2 stars
- accurate == False
- reported_issues exists

# Flagged interactions:
- training_eligible = False
- flagged_for_review = True
- Excluded from training queue
```

---

## 🎯 Use Cases

### 1. Flutter App Integration

```dart
// After AI analysis
await trainingApi.submitFeedback(
  interactionId: interaction.id,
  rating: 5,
  helpful: true,
  accurate: true,
);

// Get user progress
final progress = await trainingApi.getProgressHistory(
  userId: userId,
  days: 30,
);

// Show error patterns
final patterns = await trainingApi.getUserErrorPatterns(
  userId: userId,
  days: 7,
);
```

---

### 2. ML Engineer Workflow

```python
# 1. Get training examples
examples = requests.get(
    "http://localhost:8000/api/v1/training/training-queue",
    params={
        "task_type": "grammar",
        "validated_only": False,
        "min_quality_score": 0.8,
        "limit": 1000
    }
).json()

# 2. Validate examples (human-in-the-loop)
for example in examples[:10]:  # Review first 10
    if is_good_example(example):
        requests.put(
            f"http://localhost:8000/api/v1/training/training-queue/{example['_id']}/validate",
            json={
                "approved": True,
                "validated_by": "engineer_alice",
                "notes": "Good example"
            }
        )

# 3. Export for training
training_data = requests.post(
    "http://localhost:8000/api/v1/training/export/training-data",
    json={
        "task_types": ["grammar"],
        "validated_only": True,
        "min_quality_score": 0.8,
        "format": "jsonl"
    }
).json()

# 4. Train LoRA adapter
train_lora(training_data["data"])

# 5. Log metrics
requests.post(
    "http://localhost:8000/api/v1/training/metrics/model-performance",
    json={
        "model_name": "qwen-unified",
        "version": "v1.3.0",
        "metrics": {
            "accuracy": 0.94,  # Improved!
            "f1_score": 0.91
        }
    }
)
```

---

### 3. Analytics Dashboard

```python
# Get fluency improvement over time
analytics = requests.post(
    "http://localhost:8000/api/v1/training/analytics",
    json={
        "user_id": "user123",
        "start_date": "2026-01-01",
        "metric": "fluency",
        "group_by": "week"
    }
).json()

# Plot improvement trend
plot_trend(analytics["data"])
```

---

## 🛠️ Setup Instructions

### 1. Initialize MongoDB
```bash
# Run initialization script
python scripts/init_db.py
```

### 2. Verify Collections
```bash
# Check MongoDB
mongosh
> use lexilingo
> show collections
> db.ai_interactions.getIndexes()
```

### 3. Test Endpoints
```bash
# Start server
uvicorn api.main:app --reload

# Visit Swagger UI
open http://localhost:8000/docs#tag/Training-&-Learning-(ML-Pipeline)
```

---

## 📊 Monitoring

### Key Metrics to Track:
- **Training Queue Size**: Should grow steadily
- **Validation Rate**: % of examples validated
- **Quality Score Distribution**: Ensure high quality
- **Feedback Submission Rate**: User engagement
- **Error Pattern Trends**: Identify systematic issues

---

## 🎓 Best Practices

1. **Always collect feedback**: Crucial for quality assessment
2. **Validate before training**: Human-in-the-loop prevents bad data
3. **Monitor quality scores**: Low scores = model issues
4. **Export regularly**: Don't wait until you have millions of examples
5. **Track model metrics**: Ensure continuous improvement
6. **Analyze error patterns**: Fix systematic issues in prompts/models

---

## 🚀 Next Steps

1. ✅ **Infrastructure ready**: All endpoints implemented
2. 🔄 **Integrate with Flutter app**: Add feedback UI
3. 🧪 **Test with real users**: Collect initial data
4. 📊 **Build analytics dashboard**: Visualize metrics
5. 🤖 **Setup LoRA training pipeline**: Automate fine-tuning
6. 📈 **Monitor & iterate**: Continuous improvement

---

**Documentation Version:** 1.0.0  
**Last Updated:** January 16, 2026  
**Author:** LexiLingo Backend Team
