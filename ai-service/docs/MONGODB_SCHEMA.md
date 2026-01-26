# LexiLingo MongoDB Collections Schema

> **Version**: 1.0  
> **Last Updated**: January 15, 2026  
> **Purpose**: Define MongoDB collections structure for AI learning system

---

## Overview

LexiLingo uses 4 main collections to log AI interactions and support continuous learning:

1. **ai_interactions** - Full interaction logs with user feedback
2. **model_metrics** - Performance tracking over time
3. **learning_patterns** - Aggregated user error patterns
4. **training_queue** - Curated examples for LoRA fine-tuning

---

## Collection 1: ai_interactions

**Purpose**: Log every AI interaction for analysis and training data extraction

### Schema

```javascript
{
  _id: ObjectId,                    // Auto-generated
  session_id: String,               // Conversation session ID
  user_id: String,                  // User identifier
  timestamp: ISODate,               // When interaction occurred
  
  // User Input
  user_input: {
    text: String,                   // User's text input
    audio_features: Object | null,  // HuBERT phoneme features (if voice)
    context: Array<String>          // Last 5 conversation turns
  },
  
  // AI Processing
  models_used: Array<String>,       // ["qwen", "hubert", "llama3-vi"]
  processing_time_ms: {
    stt: Number,                    // Speech-to-text latency
    qwen: Number,                   // Qwen analysis latency
    hubert: Number,                 // HuBERT pronunciation latency
    llama3: Number,                 // LLaMA3-VI latency (if used)
    total: Number                   // Total pipeline latency
  },
  
  // AI Analysis Results
  analysis: {
    fluency_score: Number,          // 0.0 - 1.0
    vocabulary_level: String,       // "A1", "A2", "B1", "B2", "C1", "C2"
    
    grammar_errors: Array<{
      type: String,                 // "verb_tense", "subject_verb_agreement", etc.
      error: String,                // The incorrect text
      correction: String,           // The correct text
      explanation: String,          // Why it's wrong
      severity: String              // "minor", "moderate", "critical"
    }>,
    
    pronunciation_errors: Array<{
      phoneme: String,              // "/θ/", "/ð/", etc.
      expected: String,             // Expected phoneme
      actual: String,               // What user said
      position: Number,             // Word position in sentence
      word: String                  // The word containing error
    }> | null,
    
    vocabulary_suggestions: Array<{
      word: String,                 // Suggested word
      usage: String,                // How to use it
      level: String                 // CEFR level
    }>,
    
    tutor_response: String,         // AI tutor's feedback message
    tutor_response_vi: String | null // Vietnamese translation (if provided)
  },
  
  // User Feedback (for learning loop)
  user_feedback: {
    helpful: Boolean | null,        // Was feedback helpful?
    correction: String | null,      // User's correction if AI wrong
    rating: Number | null,          // 1-5 star rating
    submitted_at: ISODate | null
  } | null
}
```

### Indexes

```javascript
// Query by user and time
db.ai_interactions.createIndex({ user_id: 1, timestamp: -1 })

// Query by session
db.ai_interactions.createIndex({ session_id: 1 })

// Query recent interactions
db.ai_interactions.createIndex({ timestamp: -1 })

// Find specific error types
db.ai_interactions.createIndex({ "analysis.grammar_errors.type": 1 })

// TTL index: Auto-delete after 90 days
db.ai_interactions.createIndex(
  { timestamp: 1 }, 
  { expireAfterSeconds: 7776000 }
)
```

### Example Document

```json
{
  "_id": ObjectId("65a7f8b2c3d4e5f6g7h8i9j0"),
  "session_id": "sess_20260115_abc123",
  "user_id": "user_12345",
  "timestamp": ISODate("2026-01-15T10:30:00Z"),
  
  "user_input": {
    "text": "I goes to school yesterday and meet my friend",
    "audio_features": null,
    "context": [
      "Hello! How can I help you today?",
      "I want to practice past tense"
    ]
  },
  
  "models_used": ["qwen", "unified-adapter"],
  
  "processing_time_ms": {
    "stt": 0,
    "qwen": 120,
    "hubert": 0,
    "llama3": 0,
    "total": 150
  },
  
  "analysis": {
    "fluency_score": 0.72,
    "vocabulary_level": "A2",
    
    "grammar_errors": [
      {
        "type": "verb_tense",
        "error": "goes",
        "correction": "went",
        "explanation": "Use past tense 'went' with 'yesterday'",
        "severity": "moderate"
      },
      {
        "type": "verb_tense",
        "error": "meet",
        "correction": "met",
        "explanation": "Use past tense 'met' to match 'yesterday'",
        "severity": "moderate"
      }
    ],
    
    "pronunciation_errors": null,
    
    "vocabulary_suggestions": [
      {
        "word": "encountered",
        "usage": "I encountered my friend (more formal)",
        "level": "B1"
      }
    ],
    
    "tutor_response": "Good effort! You're using 'yesterday' correctly, but remember to use past tense verbs: 'I went to school yesterday and met my friend.' Keep practicing!",
    "tutor_response_vi": null
  },
  
  "user_feedback": {
    "helpful": true,
    "correction": null,
    "rating": 5,
    "submitted_at": ISODate("2026-01-15T10:31:00Z")
  }
}
```

---

## Collection 2: model_metrics

**Purpose**: Track model performance over time for monitoring and optimization

### Schema

```javascript
{
  _id: ObjectId,
  date: ISODate,                    // Metric collection date
  model_name: String,               // "qwen-unified", "hubert", etc.
  
  metrics: {
    // Performance metrics
    avg_latency: Number,            // Average response time (ms)
    p95_latency: Number,            // 95th percentile latency
    p99_latency: Number,            // 99th percentile latency
    
    // Accuracy metrics
    accuracy: Number,               // Overall accuracy (0.0 - 1.0)
    precision: Number,              // Precision score
    recall: Number,                 // Recall score
    f1_score: Number,               // F1 score
    
    // Usage metrics
    requests_count: Number,         // Total requests today
    error_rate: Number,             // Error percentage
    cache_hit_rate: Number,         // Cache hit percentage
    
    // Model-specific metrics
    avg_confidence: Number,         // Average model confidence
    low_confidence_count: Number    // Requests with confidence < 0.5
  },
  
  resource_usage: {
    gpu_percent: Number,            // GPU utilization %
    ram_gb: Number,                 // RAM usage in GB
    cpu_percent: Number,            // CPU utilization %
    requests_per_minute: Number     // Throughput
  }
}
```

### Indexes

```javascript
// Query metrics by date and model
db.model_metrics.createIndex({ date: -1, model_name: 1 })

// Query by model
db.model_metrics.createIndex({ model_name: 1 })

// TTL index: Delete after 180 days
db.model_metrics.createIndex(
  { date: 1 }, 
  { expireAfterSeconds: 15552000 }
)
```

---

## Collection 3: learning_patterns

**Purpose**: Store aggregated analysis of user learning patterns

### Schema

```javascript
{
  _id: ObjectId,
  user_id: String,                  // User identifier
  analyzed_at: ISODate,             // When pattern was analyzed
  
  // Aggregated errors
  common_errors: Array<{
    type: String,                   // Error type
    frequency: Number,              // How many times
    examples: Array<String>,        // Sample errors
    trend: String                   // "increasing", "stable", "decreasing"
  }>,
  
  // Improvement tracking
  improvement_rate: {
    grammar: Number,                // % improvement over last period
    pronunciation: Number,
    vocabulary: Number,
    fluency: Number
  },
  
  // Strengths and weaknesses
  strengths: Array<String>,         // What user is good at
  weaknesses: Array<String>,        // What needs improvement
  
  // Recommendations
  recommended_focus: Array<String>, // Topics to focus on
  estimated_level: String,          // Current CEFR level
  next_level_progress: Number,      // Progress to next level (0-100%)
  
  // Statistics
  stats: {
    total_interactions: Number,
    avg_fluency_score: Number,
    total_errors_corrected: Number,
    study_streak_days: Number
  }
}
```

### Indexes

```javascript
// Query latest pattern for user
db.learning_patterns.createIndex({ user_id: 1, analyzed_at: -1 })

// Find users with specific error types
db.learning_patterns.createIndex({ "common_errors.type": 1 })

// TTL index: Keep for 1 year
db.learning_patterns.createIndex(
  { analyzed_at: 1 }, 
  { expireAfterSeconds: 31536000 }
)
```

---

## Collection 4: training_queue

**Purpose**: Queue curated training examples for LoRA fine-tuning

### Schema

```javascript
{
  _id: ObjectId,
  created_at: ISODate,
  status: String,                   // "pending", "processing", "completed", "failed"
  updated_at: ISODate,
  
  // Training examples
  examples: Array<{
    input: String,                  // User input text
    correction: String,             // Corrected version
    explanation: String,            // Why correction needed
    learner_level: String,          // CEFR level
    error_types: Array<String>,     // Types of errors
    feedback_rating: Number         // Quality score from user feedback
  }>,
  
  // Training metadata
  use_for: String,                  // "lora_finetuning", "evaluation", etc.
  batch_id: String,                 // Training batch identifier
  total_examples: Number,           // Count of examples
  
  // Processing info
  processed_at: ISODate | null,
  processed_by: String | null,      // Worker ID
  error_message: String | null      // If failed
}
```

### Indexes

```javascript
// Query pending items
db.training_queue.createIndex({ status: 1, created_at: -1 })

// Query by batch
db.training_queue.createIndex({ batch_id: 1 })

// TTL index: Clean up after 30 days
db.training_queue.createIndex(
  { created_at: 1 }, 
  { expireAfterSeconds: 2592000 }
)
```

---

## Data Retention Policy

| Collection | Retention | Reason |
|------------|-----------|--------|
| ai_interactions | 90 days | Balance storage with training data needs |
| model_metrics | 180 days | Long-term performance tracking |
| learning_patterns | 365 days | User progress over time |
| training_queue | 30 days | Completed training jobs cleanup |

---

## Storage Estimation

### FREE Tier: 512 MB

**Estimated capacity**:
- ai_interactions: ~500,000 interactions (assuming ~1KB per document)
- model_metrics: ~180 daily snapshots per model
- learning_patterns: ~10,000 user patterns
- training_queue: ~5,000 pending examples

**With TTL indexes**, data auto-deletes keeping storage under 512MB.

---

## Querying Examples

### Get user's recent errors
```javascript
db.ai_interactions.aggregate([
  { $match: { user_id: "user_12345" } },
  { $unwind: "$analysis.grammar_errors" },
  { $group: {
    _id: "$analysis.grammar_errors.type",
    count: { $sum: 1 },
    examples: { $push: "$analysis.grammar_errors.error" }
  }},
  { $sort: { count: -1 } }
])
```

### Get model performance trend
```javascript
db.model_metrics.find(
  { model_name: "qwen-unified" }
).sort({ date: -1 }).limit(30)
```

### Find users needing help with specific error
```javascript
db.learning_patterns.find({
  "common_errors.type": "verb_tense",
  "common_errors.frequency": { $gte: 5 }
})
```

---

> **Note**: All schemas include validation rules in `mongo-init.js`  
> **See**: [MONGODB_ATLAS_SETUP.md](MONGODB_ATLAS_SETUP.md) for deployment guide
