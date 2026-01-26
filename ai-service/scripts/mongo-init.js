// MongoDB initialization script for LexiLingo Backend
// This script runs automatically when MongoDB container starts

// Switch to lexilingo database
db = db.getSiblingDB('lexilingo');

// Create collections with validation schema
db.createCollection('ai_interactions', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['session_id', 'user_id', 'timestamp', 'user_input'],
      properties: {
        session_id: { bsonType: 'string' },
        user_id: { bsonType: 'string' },
        timestamp: { bsonType: 'date' },
        interaction_type: { enum: ['grammar_check', 'chat', 'vocabulary'] },
        user_input: {
          bsonType: 'object',
          required: ['text'],
          properties: {
            text: { bsonType: 'string' },
            audio_features: { bsonType: 'object' },
            context: { bsonType: 'array' }
          }
        },
        models_used: { bsonType: 'array' },
        processing_time_ms: { bsonType: 'object' },
        analysis: { bsonType: 'object' },
        user_feedback: { bsonType: 'object' }
      }
    }
  }
});

db.createCollection('chat_sessions', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['session_id', 'user_id', 'created_at'],
      properties: {
        session_id: { bsonType: 'string' },
        user_id: { bsonType: 'string' },
        title: { bsonType: 'string' },
        created_at: { bsonType: 'date' },
        last_activity: { bsonType: 'date' },
        message_count: { bsonType: 'int' }
      }
    }
  }
});

db.createCollection('chat_messages', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['message_id', 'session_id', 'content', 'role', 'timestamp'],
      properties: {
        message_id: { bsonType: 'string' },
        session_id: { bsonType: 'string' },
        user_id: { bsonType: 'string' },
        content: { bsonType: 'string' },
        role: { enum: ['user', 'ai', 'system'] },
        timestamp: { bsonType: 'date' }
      }
    }
  }
});

db.creatimprovement_rate: { bsonType: 'object' },
        recommended_focus: { bsonType: 'array' },
        recommendations: { bsonType: 'array' },
        stats: { bsonType: 'object' }
      }
    }
  }
});

db.createCollection('model_metrics', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['date', 'model_name', 'metrics'],
      properties: {
        date: { bsonType: 'date' },
        model_name: { bsonType: 'string' },
        metrics: { bsonType: 'object' },
        resource_usage: { bsonType: 'object' }
      }
    }timestamp: -1 });
db.ai_interactions.createIndex({ interaction_type: 1 });
db.ai_interactions.createIndex({ "analysis.grammar_errors.type": 1 });

db.chat_sessions.createIndex({ user_id: 1, last_activity: -1 });
db.chat_sessions.createIndex({ session_id: 1 }, { unique: true });

db.chat_messages.createIndex({ session_id: 1, timestamp: 1 });
db.chat_messages.createIndex({ message_id: 1 }, { unique: true });

db.learning_patterns.createIndex({ user_id: 1, analyzed_at: -1 });
db.learning_patterns.createIndex({ "common_errors.type": 1 });

db.model_metrics.createIndex({ date: -1, model_name: 1 });
db.model_metrics.createIndex({ model_name: 1 });

db.training_queue.createIndex({ status: 1, created_at: -1 });

// Create TTL index for ai_interactions (auto-delete after 90 days)
db.ai_interactions.createIndex(
  { timestamp: 1 }, 
  { expireAfterSeconds: 7776000 }  // 90 days = 7776000 seconds
);

// Insert sample data for testing
db.ai_interactions.insertOne({
  session_id: 'test_session_001',
  user_id: 'test_user',
  timestamp: new Date(),
  interaction_type: 'grammar_check',
  user_input: {
    text: 'I goes to school yesterday',
    audio_features: null,
    context: []
  },
  models_used: ['qwen', 'unified-adapter'],
  processing_time_ms: {
    qwen: 120,
    total: 150
  },
  analysis: {
    fluency_score: 0.75,
    vocabulary_level: 'A2',
    grammar_errors: [
      {
        type: 'verb_tense',
        error: 'goes',
        correction: 'went',
        explanation: 'Past tense should be used with "yesterday"'
      }
    ],
    tutor_response: 'Good attempt! Remember to use past tense with "yesterday". Try: "I went to school yesterday."'
  },
  user_feedback: null
});

print('OK LexiLingo database initialized successfully!');
print('Collections Collections created: ai_interactions, chat_sessions, chat_messages, learning_patterns, model_metrics, training_queue');
print('Indexes Indexes created for optimal query performance');
print('Sample data Sample data inserted for testing
        status: { 
          enum: ['pending', 'processing', 'completed', 'failed']
        },
        examples: { bsonType: 'array' },
        use_for: { bsonType: 'string
    $jsonSchema: {
      bsonType: 'object',
      required: ['user_id', 'analyzed_at'],
      properties: {
        user_id: { bsonType: 'string' },
        analyzed_at: { bsonType: 'date' },
        common_errors: { bsonType: 'array' },
        strengths: { bsonType: 'array' },
        recommendations: { bsonType: 'array' },
        stats: { bsonType: 'object' }
      }
    }
  }
});

// Create indexes for better query performance
db.ai_interactions.createIndex({ user_id: 1, timestamp: -1 });
db.ai_interactions.createIndex({ session_id: 1 });
db.ai_interactions.createIndex({ interaction_type: 1 });

db.chat_sessions.createIndex({ user_id: 1, last_activity: -1 });
db.chat_sessions.createIndex({ session_id: 1 }, { unique: true });

db.chat_messages.createIndex({ session_id: 1, timestamp: 1 });
db.chat_messages.createIndex({ message_id: 1 }, { unique: true });

db.learning_patterns.createIndex({ user_id: 1, analyzed_at: -1 });

print('OK LexiLingo database initialized successfully!');
