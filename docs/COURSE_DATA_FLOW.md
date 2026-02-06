# LexiLingo Course Data Flow Documentation

## Overview
This document describes the complete data flow for courses, lessons, exercises, and user progress in LexiLingo.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────┐ │
│  │  Data Source │ -> │   Process    │ -> │   Database   │ -> │ Flutter UI │ │
│  │  (Crawl/Seed)│    │  & Validate  │    │  PostgreSQL  │    │   Display  │ │
│  └──────────────┘    └──────────────┘    └──────────────┘    └────────────┘ │
│                                                                              │
│  User Progress:                                                              │
│  ┌────────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────┐   │
│  │ Learn/Test │ -> │ Submit Answer│ -> │  Update XP   │ -> │ Level Up   │   │
│  │   in App   │    │  to Backend  │    │  & Progress  │    │ + Skills   │   │
│  └────────────┘    └──────────────┘    └──────────────┘    └────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 1. Database Schema

### Core Tables

| Table | Description | Key Fields |
|-------|-------------|------------|
| `courses` | Course definitions | id, title, level (CEFR), category_id, total_xp |
| `units` | Groups of lessons | id, course_id, title, order_index |
| `lessons` | Individual lessons | id, unit_id, content (JSON), exercises |
| `course_categories` | Course categories | id, name, slug, icon, color |
| `vocabulary_items` | Master vocabulary | word, definition, translation, level |

### Progress Tables

| Table | Description | Key Fields |
|-------|-------------|------------|
| `user_course_progress` | Course enrollment | user_id, course_id, progress_% |
| `lesson_completions` | Completed lessons | user_id, lesson_id, best_score |
| `user_proficiency_profiles` | Skill scores | user_id, assessed_level, total_xp |
| `exercise_attempts` | Exercise history | user_id, exercise_type, is_correct |

### Gamification Tables

| Table | Description | Key Fields |
|-------|-------------|------------|
| `achievements` | Badge definitions | name, condition_type, xp_reward |
| `user_achievements` | Earned badges | user_id, achievement_id, unlocked_at |
| `streaks` | Daily streaks | user_id, current_streak, longest_streak |
| `user_wallets` | Virtual currency | user_id, gems_balance |

## 2. Lesson Content Structure

Each lesson contains structured JSON content:

```json
{
  "introduction": "Lesson introduction text...",
  "vocabulary": [
    {
      "word": "Hello",
      "translation": "Xin chào",
      "example": "Hello, how are you?",
      "audio_url": null
    }
  ],
  "grammar_notes": [
    "Grammar rule 1...",
    "Grammar rule 2..."
  ],
  "exercises": [
    {
      "type": "multiple_choice",
      "question": "What do you say in the morning?",
      "options": ["Good evening", "Good morning", "Goodbye", "Good night"],
      "correct_answer": 1,
      "explanation": "Use 'Good morning' before noon.",
      "xp_reward": 5,
      "skill": "vocabulary"
    },
    {
      "type": "fill_blank",
      "question": "Complete: 'Good _____, nice to meet you.'",
      "correct_answer": "afternoon",
      "hint": "Used between 12 PM and 6 PM",
      "xp_reward": 10,
      "skill": "grammar"
    },
    {
      "type": "matching",
      "question": "Match greetings with translations",
      "pairs": [{"english": "Hello", "vietnamese": "Xin chào"}],
      "xp_reward": 15,
      "skill": "vocabulary"
    }
  ]
}
```

### Exercise Types

| Type | Description | XP Range |
|------|-------------|----------|
| `multiple_choice` | Select correct answer | 5-10 |
| `fill_blank` | Type missing word | 10-15 |
| `matching` | Match pairs | 15-20 |
| `reorder` | Arrange words/sentences | 10-15 |
| `listening` | Listen and answer | 10-15 |
| `speaking` | Speak response | 15-25 |
| `writing` | Write paragraph | 20-30 |
| `translation` | Translate text | 10-15 |
| `error_correction` | Fix grammar errors | 10-15 |

## 3. API Endpoints

### Courses API

```
GET  /api/v1/courses                    # List courses (paginated)
GET  /api/v1/courses/{id}               # Course detail with units/lessons
POST /api/v1/courses/{id}/enroll        # Enroll in course
GET  /api/v1/courses/enrolled           # User's enrolled courses
GET  /api/v1/course-categories          # List categories
```

### Learning API

```
GET  /api/v1/learning/lesson/{id}       # Get lesson content
POST /api/v1/learning/exercise/submit   # Submit exercise answer
GET  /api/v1/learning/progress          # User's overall progress
GET  /api/v1/learning/roadmap/{course}  # Course roadmap with unlock status
```

### Progress API

```
GET  /api/v1/progress/stats             # User statistics
GET  /api/v1/progress/streaks           # Streak information
GET  /api/v1/proficiency/profile        # Skill levels
```

## 4. User Learning Flow

### Step 1: Course Selection
```
User -> Browse Courses -> Select Course -> Enroll
                      └-> Filter by Category/Level
```

### Step 2: Learning
```
User -> Open Lesson -> Read Content -> Complete Exercises
                                    └-> Each correct answer = XP gain
```

### Step 3: Progress Tracking
```
Complete Lesson -> Update Progress % -> Check Prerequisites
               -> Award XP           -> Unlock Next Lesson
               -> Update Skill Scores -> Check Achievements
```

### Step 4: Level Up
```
Accumulate XP -> Check Level Thresholds -> Level Up!
            └-> Complete Proficiency Test -> Unlock Higher Courses
```

## 5. XP and Skill System

### XP Rewards

| Activity | XP Range |
|----------|----------|
| Complete exercise | 5-30 |
| Complete lesson | 50-100 |
| Complete unit | 100-200 |
| Daily streak bonus | 10-50 |
| Achievement unlock | 25-500 |

### Skill Categories

| Skill | Description | Exercises |
|-------|-------------|-----------|
| `vocabulary` | Word knowledge | Multiple choice, matching |
| `grammar` | Sentence structure | Fill blank, error correction |
| `listening` | Audio comprehension | Listen & answer |
| `speaking` | Pronunciation | Speak exercises |
| `reading` | Text comprehension | Reading passages |
| `writing` | Text production | Writing exercises |

### CEFR Levels

| Level | Description | XP Threshold |
|-------|-------------|--------------|
| A1 | Beginner | 0 |
| A2 | Elementary | 1,000 |
| B1 | Intermediate | 5,000 |
| B2 | Upper-Intermediate | 15,000 |
| C1 | Advanced | 35,000 |
| C2 | Proficient | 70,000 |

## 6. Data Seeding

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/seed_course_content.py` | Main seeding script |
| `scripts/seed_courses.py` | Course structure |
| `scripts/check_db_data.py` | Verify data |

### Run Seeding

```bash
cd backend-service
source venv/bin/activate

# Seed all course content
python -m scripts.seed_course_content

# Check database data
python -m scripts.check_db_data
```

### Current Data Summary

- **Categories**: 6 (Grammar, Vocabulary, Conversation, Business, Travel, Test Prep)
- **Courses**: 7 published courses
- **Units**: 10 units
- **Lessons**: 14 lessons (9 with rich content)
- **Exercises**: 65+ exercises across lessons
- **Vocabulary**: 35 items
- **Achievements**: 26 badges

## 7. Flutter UI Integration

### Key Screens

| Screen | Data Source | Features |
|--------|-------------|----------|
| `CourseListPage` | `/api/v1/courses` | Browse, filter, enroll |
| `CourseDetailPage` | `/api/v1/courses/{id}` | Units, lessons, progress |
| `LessonPage` | `/api/v1/learning/lesson/{id}` | Content, exercises |
| `ExercisePage` | Lesson content JSON | Interactive exercises |
| `ProgressPage` | `/api/v1/progress/stats` | XP, skills, streaks |
| `AchievementsPage` | `/api/v1/gamification/achievements` | Badges |

### State Management

```dart
// Provider for course data
class CourseProvider extends ChangeNotifier {
  List<Course> _courses = [];
  CourseProgress? _currentProgress;
  
  Future<void> loadCourses();
  Future<void> enrollInCourse(String courseId);
  Future<void> submitExercise(ExerciseAnswer answer);
}
```

## 8. Future Enhancements

### Planned Features

1. **Content Crawling**: Automated scraping of English learning resources
2. **AI-Generated Exercises**: Use LLM to create new exercises
3. **Adaptive Learning**: Adjust difficulty based on performance
4. **Spaced Repetition**: Optimal vocabulary review scheduling
5. **Social Features**: Leaderboards, study groups
6. **Offline Mode**: Download courses for offline learning

### Data Sources for Expansion

- British Council Learn English
- Cambridge Dictionary
- VOA Learning English
- English Grammar in Use
- IELTS/TOEFL practice materials

---

## Quick Reference

### Start Services

```bash
# Backend
cd backend-service && source venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000

# AI Service
cd ai-service
export PYTHONPATH=$(pwd)
python -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001

# Flutter
cd flutter-app && flutter run -d chrome --web-port=8080
```

### Test API

```bash
# Health check
curl http://localhost:8000/health

# Get courses
curl http://localhost:8000/api/v1/courses

# Get categories
curl http://localhost:8000/api/v1/course-categories
```

---

*Last Updated: February 2025*
*LexiLingo Team*
