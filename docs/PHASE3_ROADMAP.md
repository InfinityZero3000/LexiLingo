# 🎯 LexiLingo System Analysis & Phase 3 Roadmap

**Date:** January 25, 2026
**Status:** Phase 2 Complete ✅ → Ready for Phase 3

---

## 📊 Current System State

### ✅ Completed Features (Phase 1-2)

#### **Phase 1: Authentication & Foundation**
- ✅ JWT authentication with Firebase
- ✅ User registration/login
- ✅ Profile management
- ✅ Token refresh mechanism

#### **Phase 2: Course Management & Progress Tracking** ✅ COMPLETE
- ✅ **Backend APIs (7 endpoints):**
  - 3 Course endpoints (list, detail, enroll)
  - 4 Progress endpoints (my progress, course progress, lesson completion, XP)
- ✅ **Smart XP System:**
  - Idempotent lesson completion
  - XP awarded only on first pass (≥80%)
  - Best score tracking
  - Auto-calculated course progress
- ✅ **Flutter Implementation:**
  - Course browsing with pagination
  - Course detail with units/lessons roadmap
  - Progress tracking dashboard
  - Clean Architecture (Domain-Data-Presentation)
- ✅ **Testing:** 53 tests (13 backend + 40 flutter, 21/21 passing)
- ✅ **Documentation:** 3 comprehensive docs

---

## 🏗️ System Architecture Overview

### Backend (FastAPI)
```
backend-service/
├── app/
│   ├── models/
│   │   ├── user.py          ✅ Complete
│   │   ├── course.py        ✅ Complete
│   │   ├── progress.py      ✅ Complete (Phase 2)
│   │   └── gamification.py  ⏳ Planned (Phase 4)
│   ├── routes/
│   │   ├── auth.py          ✅ Complete
│   │   ├── courses.py       ✅ Complete (3 endpoints)
│   │   ├── progress.py      ✅ Complete (4 endpoints)
│   │   └── users.py         ✅ Complete
│   ├── crud/
│   │   ├── course.py        ✅ Complete
│   │   └── progress.py      ✅ Complete (347 lines)
│   └── schemas/
│       ├── course.py        ✅ Complete
│       └── progress.py      ✅ Complete (89 lines)
```

### Flutter (Clean Architecture)
```
flutter-app/lib/features/
├── auth/            ✅ Complete
├── user/            ✅ Complete
├── course/          ✅ Complete (Phase 2)
│   ├── domain/      ✅ Entities, Repository, UseCases
│   ├── data/        ✅ Models, DataSources, Repository impl
│   └── presentation/ ✅ Provider, Screens, Widgets
├── progress/        ✅ Complete (Phase 2)
│   ├── domain/      ✅ 7 entities, Repository, 3 UseCases
│   ├── data/        ✅ 6 models, DataSource, Repository
│   └── presentation/ ✅ ProgressProvider, MyProgressScreen
├── chat/            ⏳ Partially complete
├── vocabulary/      ⏳ Partially complete
└── notifications/   ❌ Not started
```

### AI Service (Separate)
```
ai-service/
├── STT: Whisper v3       ✅ Available
├── NLP: Qwen2.5          ✅ Available
├── TTS: Piper VITS       ✅ Available
├── Knowledge Graph       ✅ Available
└── MongoDB (Sessions)    ✅ Connected
```

---

## 🎯 Phase 3: Vocabulary & Spaced Repetition System (SRS)

### Objectives
Build intelligent vocabulary learning with spaced repetition, flashcards, and AI-powered review system.

### Why Phase 3?
1. **Natural Progression:** Users completed lessons → Need vocabulary retention
2. **High Impact:** SRS proven to increase retention by 200-400%
3. **Competitive Edge:** AI-powered personalized review schedule
4. **Foundation Ready:** Course/Progress systems provide data pipeline

---

## 🔧 Phase 3 Features (Priority Order)

### 3.1 Vocabulary Management 🌟 HIGH PRIORITY

#### Backend APIs (5 endpoints)
**Base URL:** `/api/v1/vocabulary`

| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/vocabulary` | GET | Get user's vocabulary list (pagination) | Yes |
| `/vocabulary/{id}` | GET | Get vocabulary detail with examples | Yes |
| `/vocabulary/{id}/add` | POST | Add word to personal collection | Yes |
| `/vocabulary/{id}/review` | POST | Submit review result | Yes |
| `/vocabulary/due` | GET | Get words due for review | Yes |

#### Database Schema
```sql
-- vocabulary_items
CREATE TABLE vocabulary_items (
  id UUID PRIMARY KEY,
  word VARCHAR(255) NOT NULL,
  definition TEXT,
  translation JSONB,  -- {"vi": "...", "examples": [...]}
  pronunciation VARCHAR(50),
  audio_url TEXT,
  part_of_speech VARCHAR(20),
  difficulty_level VARCHAR(10),
  course_id UUID REFERENCES courses(id),
  lesson_id UUID REFERENCES lessons(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- user_vocabulary (Personal collection)
CREATE TABLE user_vocabulary (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  vocabulary_id UUID REFERENCES vocabulary_items(id),
  status VARCHAR(20),  -- 'learning', 'reviewing', 'mastered'
  
  -- SRS Fields
  ease_factor FLOAT DEFAULT 2.5,
  interval INTEGER DEFAULT 1,  -- days
  repetitions INTEGER DEFAULT 0,
  next_review_date TIMESTAMP,
  last_reviewed_at TIMESTAMP,
  
  -- Stats
  total_reviews INTEGER DEFAULT 0,
  correct_reviews INTEGER DEFAULT 0,
  streak INTEGER DEFAULT 0,
  
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, vocabulary_id)
);

-- vocabulary_reviews
CREATE TABLE vocabulary_reviews (
  id UUID PRIMARY KEY,
  user_vocabulary_id UUID REFERENCES user_vocabulary(id),
  quality INTEGER,  -- 0-5 (SM-2 algorithm)
  time_spent_ms INTEGER,
  reviewed_at TIMESTAMP DEFAULT NOW()
);
```

#### SRS Algorithm (SuperMemo SM-2)
```python
def calculate_next_review(
    quality: int,  # 0-5 rating
    ease_factor: float,
    interval: int,
    repetitions: int
) -> tuple[float, int, int]:
    """
    Quality scale:
    5 - Perfect (instant recall)
    4 - Correct after hesitation
    3 - Correct with difficulty
    2 - Incorrect but remembered
    1 - Incorrect, barely remembered
    0 - Complete blackout
    """
    if quality < 3:
        # Reset if failed
        repetitions = 0
        interval = 1
    else:
        if repetitions == 0:
            interval = 1
        elif repetitions == 1:
            interval = 6
        else:
            interval = int(interval * ease_factor)
        repetitions += 1
    
    # Update ease factor
    ease_factor = ease_factor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    ease_factor = max(1.3, ease_factor)
    
    return ease_factor, interval, repetitions
```

#### Flutter Implementation
```
lib/features/vocabulary/
├── domain/
│   ├── entities/
│   │   ├── vocabulary_item_entity.dart
│   │   ├── user_vocabulary_entity.dart
│   │   └── review_session_entity.dart
│   ├── repositories/
│   │   └── vocabulary_repository.dart
│   └── usecases/
│       ├── get_vocabulary_list_usecase.dart
│       ├── add_to_collection_usecase.dart
│       ├── get_due_words_usecase.dart
│       └── submit_review_usecase.dart
├── data/
│   ├── models/
│   │   ├── vocabulary_model.dart
│   │   └── review_result_model.dart
│   ├── datasources/
│   │   └── vocabulary_remote_datasource.dart
│   └── repositories/
│       └── vocabulary_repository_impl.dart
└── presentation/
    ├── providers/
    │   └── vocabulary_provider.dart
    ├── screens/
    │   ├── vocabulary_list_screen.dart
    │   ├── flashcard_screen.dart
    │   └── review_session_screen.dart
    └── widgets/
        ├── vocabulary_card.dart
        ├── flashcard_widget.dart
        └── review_stats_widget.dart
```

**UI Components:**
1. **Vocabulary List Screen:**
   - Tabs: All, Learning, Reviewing, Mastered
   - Search & filter by course/lesson
   - Progress indicators (streak, next review)

2. **Flashcard Screen:**
   - Flip animation (front: word, back: definition + examples)
   - Audio pronunciation button
   - Swipe gestures (left: again, right: good, up: easy)

3. **Review Session Screen:**
   - Daily due words counter
   - Quality rating buttons (0-5)
   - Session statistics (accuracy, time per card)
   - Streak tracking

---

### 3.2 Lesson Content Enhancement 🌟 HIGH PRIORITY

#### Expand Lesson Types
Current: Basic lessons
Target: Rich interactive content

**New Lesson Types:**
1. **Vocabulary Introduction** - New words with context
2. **Grammar Explanation** - Interactive rules + examples
3. **Listening Practice** - Audio comprehension with TTS
4. **Speaking Practice** - Voice recording + pronunciation check
5. **Quiz** - Multiple choice, fill-in-the-blank
6. **Story Reading** - Narrative with vocabulary highlights

#### Backend Updates
```python
# app/models/course.py
class Lesson(Base):
    # ... existing fields ...
    content_type: Enum = Column(Enum(
        'vocabulary', 'grammar', 'listening', 
        'speaking', 'quiz', 'story'
    ))
    interactive_data: JSONB = Column(JSONB)  # Type-specific data
    
    # Vocabulary lesson:
    # {"words": [...], "examples": [...]}
    
    # Quiz lesson:
    # {"questions": [{"text": "...", "options": [...], "answer": 0}]}
    
    # Story lesson:
    # {"title": "...", "content": "...", "vocabulary": [...]}
```

#### Flutter Lesson Player
```dart
// Dynamic lesson renderer
class LessonPlayer extends StatelessWidget {
  Widget build(BuildContext context) {
    switch (lesson.contentType) {
      case 'vocabulary':
        return VocabularyLessonWidget(lesson);
      case 'quiz':
        return QuizLessonWidget(lesson);
      case 'listening':
        return ListeningLessonWidget(lesson);
      // ...
    }
  }
}
```

---

### 3.3 AI-Powered Vocabulary Collection 🚀 INNOVATION

#### Automatic Vocabulary Extraction
Extract vocabulary from lessons completed by user.

**Backend API:**
```python
POST /api/v1/vocabulary/extract
{
  "lesson_id": "uuid",
  "difficulty_level": "A1"  # Auto-detect from course
}

# AI Service Integration
# 1. Extract text from lesson content
# 2. Use Qwen to identify key vocabulary
# 3. Generate definitions + examples
# 4. Store in vocabulary_items table
# 5. Optionally add to user's collection
```

**AI Prompt:**
```python
prompt = f"""
Extract key vocabulary from this English lesson for {level} learners:

{lesson_content}

For each word, provide:
1. Word
2. Part of speech
3. Definition (simple English)
4. Vietnamese translation
5. Example sentence
6. Difficulty level (A1-C2)

Output as JSON array.
"""
```

---

### 3.4 Smart Review Scheduler 🧠 INTELLIGENCE

#### Features
1. **Daily Review Notifications** - Push/Email when words are due
2. **Optimal Review Time** - Based on user's learning patterns
3. **Adaptive Difficulty** - Adjust interval based on accuracy
4. **Streak Gamification** - Rewards for consecutive review days

#### Backend Implementation
```python
# app/services/review_scheduler.py
class ReviewScheduler:
    async def get_daily_review_plan(self, user_id: UUID):
        """Generate optimized review schedule"""
        # 1. Get all due words
        due_words = await get_due_vocabulary(user_id)
        
        # 2. Prioritize by:
        #    - Difficulty level
        #    - Last review date
        #    - Error rate
        #    - Importance (from course)
        
        # 3. Return batches (10-20 words per session)
        return create_review_batches(due_words)
    
    async def send_review_reminders(self, user_id: UUID):
        """Send notification when reviews are due"""
        due_count = await count_due_words(user_id)
        if due_count > 0:
            await send_notification(
                user_id,
                title="Time to Review!",
                body=f"You have {due_count} words due for review"
            )
```

---

## 📅 Phase 3 Implementation Timeline

### Week 1: Vocabulary Foundation
**Tasks:**
- [ ] Create vocabulary database tables (migration)
- [ ] Implement vocabulary CRUD APIs (5 endpoints)
- [ ] Build Pydantic schemas for vocabulary
- [ ] Create vocabulary models in Flutter
- [ ] Implement VocabularyRepository

**Deliverables:**
- Backend: 5 endpoints functional
- Database: Tables migrated
- Flutter: Data layer complete

### Week 2: SRS Core Logic
**Tasks:**
- [ ] Implement SM-2 algorithm in backend
- [ ] Create review submission API
- [ ] Build review calculation logic
- [ ] Implement GetDueWordsUseCase in Flutter
- [ ] Create SubmitReviewUseCase

**Deliverables:**
- SRS algorithm working
- Review logic tested
- UseCases implemented

### Week 3: Flutter UI - Vocabulary
**Tasks:**
- [ ] Build VocabularyListScreen with tabs
- [ ] Implement search & filter functionality
- [ ] Create VocabularyCard widget
- [ ] Add audio pronunciation integration
- [ ] Implement add-to-collection flow

**Deliverables:**
- Vocabulary browsing complete
- Audio playback working
- Collection management functional

### Week 4: Flutter UI - Flashcards & Review
**Tasks:**
- [ ] Build FlashcardScreen with flip animation
- [ ] Implement swipe gestures for rating
- [ ] Create ReviewSessionScreen
- [ ] Add progress tracking (session stats)
- [ ] Implement streak counter

**Deliverables:**
- Flashcard system complete
- Review flow working
- Gamification elements added

### Week 5: Testing & Polish
**Tasks:**
- [ ] Write backend tests (15+ tests)
- [ ] Write Flutter tests (30+ tests)
- [ ] Integration testing (E2E)
- [ ] Performance optimization
- [ ] Bug fixes & UX improvements

**Deliverables:**
- 45+ tests passing
- Performance benchmarks met
- Production-ready code

---

## 🎯 Success Metrics

### Technical Metrics
- **API Latency:** <200ms for vocabulary endpoints
- **Review Calculation:** <50ms per word
- **Test Coverage:** >80% for vocabulary features
- **Database Queries:** Optimized with indexes

### User Metrics
- **Daily Active Reviews:** >50% of users review daily
- **Retention Rate:** 7-day retention >60%
- **Review Completion:** >80% of due words reviewed
- **Vocabulary Growth:** Average 10-20 words/week per user

---

## 🔄 Integration Points

### With AI Service
```python
# Extract vocabulary from lessons using Qwen
POST http://localhost:8001/api/ai/extract-vocabulary
{
  "text": "lesson content",
  "level": "A1"
}

# Generate pronunciation audio using Piper TTS
POST http://localhost:8001/api/ai/tts
{
  "text": "vocabulary word",
  "language": "en"
}
```

### With Progress System
```python
# When user completes lesson:
# 1. Award XP (existing)
# 2. Auto-add vocabulary to collection (new)
# 3. Update vocabulary stats (new)

# Track vocabulary mastery in course progress
# "vocabulary_mastered": 45 out of 120
```

---

## 🚀 Quick Start Commands

### Database Migration
```bash
cd backend-service
alembic revision --autogenerate -m "Add vocabulary and SRS tables"
alembic upgrade head
```

### Run Tests
```bash
# Backend
pytest app/tests/test_vocabulary_api.py -v

# Flutter
flutter test test/features/vocabulary/
```

### Seed Vocabulary Data
```bash
python scripts/seed_vocabulary.py --course-id {uuid} --count 50
```

---

## 🎨 UI/UX Design Notes

### Color Scheme
- **Learning:** 🔵 Blue (#2196F3)
- **Reviewing:** 🟡 Yellow (#FFC107)
- **Mastered:** 🟢 Green (#4CAF50)
- **Failed:** 🔴 Red (#F44336)

### Animations
- Flashcard flip: 300ms ease-in-out
- Swipe gesture: 200ms
- Progress ring: Animated on load
- Confetti: On streak milestones

### Sound Effects
- ✅ Correct answer: success_sound.mp3
- ❌ Wrong answer: error_sound.mp3
- 🎉 Streak milestone: celebration_sound.mp3

---

## 🔮 Future Enhancements (Phase 4+)

### Phase 4: Advanced Features
- **Vocabulary Games:** Word matching, crossword puzzles
- **Context Learning:** Vocabulary in real conversations
- **AI Tutor:** Personalized vocabulary recommendations
- **Collaborative:** Share vocabulary collections with friends

### Phase 5: Premium Features
- **Offline Mode:** Download vocabulary for offline review
- **Advanced Analytics:** Learning insights dashboard
- **Custom Decks:** User-created vocabulary collections
- **Premium Audio:** Native speaker pronunciations

---

## ✅ Phase 3 Checklist

### Pre-Development
- [x] System analysis complete
- [x] Architecture designed
- [x] Database schema defined
- [ ] API contracts documented
- [ ] UI mockups created

### Development
- [ ] Backend APIs (5 endpoints)
- [ ] Database migration
- [ ] SRS algorithm implementation
- [ ] Flutter domain layer
- [ ] Flutter data layer
- [ ] Flutter presentation layer
- [ ] Testing (45+ tests)
- [ ] Documentation

### Post-Development
- [ ] Integration testing
- [ ] Performance testing
- [ ] User acceptance testing
- [ ] Production deployment
- [ ] Monitoring setup

---

## 📚 References

- **SuperMemo SM-2 Algorithm:** https://www.supermemo.com/en/archives1990-2015/english/ol/sm2
- **Spaced Repetition Research:** https://gwern.net/spaced-repetition
- **Anki Documentation:** https://docs.ankiweb.net/
- **Flutter Animations:** https://docs.flutter.dev/development/ui/animations

---

**Next Step:** Start Week 1 - Vocabulary Foundation 🚀

**Estimated Completion:** 5 weeks (February 28, 2026)

**Phase 3 Status:** 🟡 READY TO START
