# Content Auto-Generation (CAG) System

Complete implementation for **automatic adaptive learning content generation**!

## 🎯 Overview

CAG automatically generates personalized learning content based on:
- **User Level** (A1-C2 CEFR)
- **Error Patterns** (grammar mistakes, vocabulary gaps)
- **Learning History** (past performance, trends)
- **Interests** (topics the user enjoys)

## 🚀 Features

### 1. **Vocabulary Exercises**
- Adaptive word selection by level and topic
- Definitions, examples, and usage context
- Fill-in-the-blank tasks
- Error pattern targeting

### 2. **Grammar Drills**
- Focused grammar practice
- Level-appropriate explanations
- Multiple choice and fill-in exercises
- Tips and common mistakes

### 3. **Conversation Prompts**
- Role-play scenarios (restaurant, job interview, etc.)
- Starter phrases and vocabulary hints
- Cultural notes
- Objectives and guidance

### 4. **Reading Passages**
- Level-appropriate texts
- Comprehension questions (multiple choice, T/F, short answer)
- Vocabulary glossary
- Adjustable length (short/medium/long)

### 5. **Writing Prompts**
- Various types (essay, email, letter, story)
- Structure guidelines
- Sample phrases
- Rubric for self-assessment

### 6. **Pronunciation Exercises**
- Phoneme practice
- Word stress and intonation
- Minimal pairs
- Tips and techniques

### 7. **Personalized Lessons** ⭐
- **Complete adaptive lesson packages**
- Combines multiple content types
- Error-focused + interest-based
- Estimated duration

## 📡 API Endpoints

Base URL: `/api/v1/cag`

### Generate Vocabulary
```bash
POST /api/v1/cag/vocabulary
{
  "level": "B1",
  "topic": "business",
  "count": 10,
  "error_patterns": ["vocabulary_range"]
}
```

### Generate Grammar Drill
```bash
POST /api/v1/cag/grammar
{
  "level": "A2",
  "grammar_point": "past_simple",
  "error_patterns": ["tense_confusion"],
  "count": 15
}
```

### Generate Conversation Prompt
```bash
POST /api/v1/cag/conversation
{
  "level": "B1",
  "topic": "travel",
  "scenario": "hotel_checkin"
}
```

### Generate Reading Passage
```bash
POST /api/v1/cag/reading
{
  "level": "B2",
  "topic": "technology",
  "length": "medium"
}
```

### Generate Writing Prompt
```bash
POST /api/v1/cag/writing
{
  "level": "C1",
  "writing_type": "essay",
  "topic": "climate_change"
}
```

### Generate Pronunciation Exercise
```bash
POST /api/v1/cag/pronunciation
{
  "level": "A2",
  "focus": "phoneme",
  "error_patterns": ["th_sound"]
}
```

### 🌟 Generate Personalized Lesson (MAIN ENDPOINT)
```bash
POST /api/v1/cag/personalized-lesson
{
  "user_id": "user123",
  "user_level": "B1",
  "error_patterns": ["past_tense", "articles"],
  "interests": ["travel", "food", "technology"],
  "learning_history": {
    "grammar_accuracy": 0.75,
    "vocabulary_progress": 0.82,
    "recent_topics": ["travel", "business"]
  }
}
```

**Response includes:**
- Grammar drills (if errors detected)
- Vocabulary exercises (interest-based)
- Conversation prompts (contextual)
- Reading passages (level-appropriate)
- Estimated duration

### Generate Multiple Content Types
```bash
POST /api/v1/cag/batch?level=B1&types=vocabulary&types=grammar&types=conversation&topic=travel
```

### Health Check
```bash
GET /api/v1/cag/health
```

## 🎓 Use Cases

### For Flutter App
```dart
// Generate daily personalized lesson
final response = await http.post(
  Uri.parse('$baseUrl/api/v1/cag/personalized-lesson'),
  body: jsonEncode({
    'user_id': userId,
    'user_level': userProfile.level,
    'error_patterns': errorAnalysis.topErrors,
    'interests': userProfile.interests,
    'learning_history': userProfile.learningHistory,
  }),
);

final lesson = jsonDecode(response.body);
// Display lesson components in UI
```

### For Practice Mode
```dart
// Generate specific exercise type
final vocabulary = await generateVocabulary(
  level: 'B1',
  topic: 'business',
  count: 10,
);

// Display flashcards or fill-in-the-blank
```

### For Conversation Practice
```dart
// Get conversation scenario
final conversation = await generateConversation(
  level: userLevel,
  topic: 'travel',
  scenario: 'airport',
);

// Start role-play chat with AI
```

## 🔧 Architecture

### CAG Service (`api/services/cag_service.py`)
```
ContentAutoGenerator
├── generate_vocabulary_exercise()
├── generate_grammar_drill()
├── generate_conversation_prompt()
├── generate_reading_passage()
├── generate_writing_prompt()
├── generate_pronunciation_exercise()
└── generate_personalized_lesson() ⭐

ContentTemplates
├── get_vocabulary_pool()
├── get_grammar_templates()
├── get_conversation_template()
├── get_reading_template()
├── get_writing_template()
└── get_pronunciation_template()

DifficultyAdjuster
└── adjust_reading()

TopicSelector
├── select_topic()
├── select_scenario()
├── select_reading_topic()
└── select_writing_topic()
```

### API Routes (`api/routes/cag.py`)
- 8 endpoints for different content types
- Pydantic models for validation
- Comprehensive documentation
- Error handling

## 🎯 Integration with Training Pipeline

CAG works seamlessly with the Training Infrastructure:

1. **Generate Content** → User practices
2. **Log Interaction** → Record performance
3. **Submit Feedback** → User rates exercise
4. **Analyze Errors** → Detect patterns
5. **Generate New Content** → Target weaknesses ♻️

```python
# CAG → Training cycle
lesson = cag.generate_personalized_lesson(
    user_id=user_id,
    error_patterns=error_analysis.patterns,  # From training pipeline
    interests=user_profile.interests,
    learning_history=progress_tracker.history
)
```

## 📊 Content Quality

### Vocabulary
- Level-appropriate words
- Real usage examples
- Contextual definitions
- Topic coherence

### Grammar
- Targeted error correction
- Progressive difficulty
- Clear explanations
- Immediate feedback

### Conversations
- Realistic scenarios
- Cultural context
- Practical phrases
- Clear objectives

### Reading
- Appropriate complexity
- Engaging topics
- Comprehension check
- Vocabulary support

## 🚀 Next Steps

### Phase 1: Template Expansion ✅
- ✅ Core CAG service
- ✅ 8 API endpoints
- ✅ Personalized lesson generation
- ✅ Integration with training pipeline

### Phase 2: Template Database (TODO)
- [ ] MongoDB collections for templates
  - `vocabulary_pool` (by level & topic)
  - `grammar_templates` (by grammar point)
  - `conversation_scenarios` (by level & situation)
  - `reading_passages` (by level & topic)
  - `writing_prompts` (by type & level)
  - `pronunciation_exercises` (by focus)

### Phase 3: AI-Enhanced Generation (TODO)
- [ ] Use Gemini/GPT to generate content
- [ ] Dynamic difficulty adjustment
- [ ] Real-time error analysis integration
- [ ] A/B testing for effectiveness

### Phase 4: Advanced Features (TODO)
- [ ] Multi-modal content (audio, images)
- [ ] Gamification elements
- [ ] Adaptive difficulty algorithms
- [ ] Content effectiveness metrics

## 🧪 Testing

### Test CAG Health
```bash
curl http://localhost:8000/api/v1/cag/health
```

### Test Vocabulary Generation
```bash
curl -X POST http://localhost:8000/api/v1/cag/vocabulary \
  -H "Content-Type: application/json" \
  -d '{
    "level": "B1",
    "topic": "business",
    "count": 5
  }'
```

### Test Personalized Lesson
```bash
curl -X POST http://localhost:8000/api/v1/cag/personalized-lesson \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test_user",
    "user_level": "B1",
    "error_patterns": ["past_tense"],
    "interests": ["travel", "technology"],
    "learning_history": {}
  }'
```

### Test in Swagger UI
1. Start server: `uvicorn api.main:app --reload`
2. Open http://localhost:8000/docs
3. Find **"Content Auto-Generation (CAG)"** section
4. Try the endpoints!

## 📝 Example Response

### Personalized Lesson Response
```json
{
  "user_id": "user123",
  "level": "B1",
  "lesson_type": "personalized",
  "focus_areas": ["grammar", "vocabulary"],
  "components": [
    {
      "type": "grammar",
      "level": "B1",
      "grammar_point": "past_tense",
      "exercises": [...]
    },
    {
      "type": "vocabulary",
      "level": "B1",
      "topic": "travel",
      "words": [...]
    },
    {
      "type": "conversation",
      "level": "B1",
      "scenario": "hotel_checkin",
      "role_play": {...}
    },
    {
      "type": "reading",
      "level": "B1",
      "topic": "travel",
      "passage": "...",
      "comprehension_questions": [...]
    }
  ],
  "generated_at": "2026-01-18T...",
  "estimated_duration_minutes": 40
}
```

## 🎉 Summary

**CAG System is READY!**

✅ 6 content types + personalized lessons  
✅ 8 API endpoints  
✅ Adaptive to user level, errors, and interests  
✅ Integration with training pipeline  
✅ Complete documentation  
✅ Ready for Flutter integration  

**Backend đã có hệ thống tự động sinh nội dung học tập thích ứng!** 🚀
