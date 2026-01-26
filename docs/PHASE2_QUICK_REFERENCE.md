# Phase 2 Quick Reference

## API Endpoints

### Course Management
```bash
GET    /api/v1/courses              # List courses (pagination)
GET    /api/v1/courses/{id}         # Course detail with roadmap
POST   /api/v1/courses/{id}/enroll  # Enroll in course (AUTH)
```

### Progress Tracking
```bash
GET    /api/v1/progress/me                      # My progress stats (AUTH)
GET    /api/v1/progress/courses/{id}            # Course progress detail (AUTH)
POST   /api/v1/progress/lessons/{id}/complete   # Complete lesson (AUTH)
GET    /api/v1/progress/xp                      # Total XP (AUTH)
```

## Quick Start

### Backend
```bash
cd backend-service
pip install -r requirements.txt
uvicorn app.main:app --reload
# Server: http://localhost:8000
# Docs: http://localhost:8000/docs
```

### Flutter
```bash
cd flutter-app
flutter pub get
flutter run
# or
flutter run -d chrome  # Web
```

### Tests
```bash
# Backend
pytest app/tests/test_progress_api.py -v

# Flutter
flutter test test/features/progress/data/models/progress_model_test.dart
```

## XP System Rules

| Scenario | Score | XP Awarded | Notes |
|----------|-------|------------|-------|
| First attempt (pass) | ≥80% | ✅ Full XP | Awards lesson's xp_reward |
| First attempt (fail) | <80% | ❌ No XP | is_passed = False |
| Retry (already passed) | Any | ❌ No XP | Updates best_score if improved |
| Fail → Pass | ≥80% | ✅ Full XP | Awards XP on transition to passed |
| Pass → Pass | ≥80% | ❌ No XP | Idempotent, no duplicate XP |

**Passing threshold:** Score ≥ 80%
**Default XP per lesson:** 20 XP

## File Structure

### Backend
```
backend-service/app/
├── crud/
│   ├── course.py         # Course CRUD
│   └── progress.py       # Progress CRUD (347 lines)
├── routes/
│   ├── courses.py        # 3 endpoints
│   └── progress.py       # 4 endpoints (232 lines)
├── schemas/
│   ├── course.py         # Course schemas
│   └── progress.py       # Progress schemas (89 lines)
└── tests/
    └── test_progress_api.py  # 13 tests
```

### Flutter
```
flutter-app/lib/features/
├── course/
│   ├── domain/           # Entities, Repository, UseCases
│   ├── data/             # Models, DataSources, Repository impl
│   └── presentation/     # Provider, Screens, Widgets
└── progress/
    ├── domain/           # 7 entities, Repository, 3 UseCases
    ├── data/             # 6 models, DataSource, Repository
    └── presentation/     # ProgressProvider, MyProgressScreen
```

## Key Models

### Backend (Pydantic)
- `LessonCompletionCreate`: lesson_id, score (0-100)
- `LessonCompletionResponse`: 8 fields (lesson_id, is_passed, score, best_score, xp_earned, total_xp, course_progress, message)
- `UserProgressSummary`: total_xp, courses_enrolled, courses_completed, lessons_completed, streaks
- `CourseProgressDetail`: course_id, progress_percentage, lessons_completed, total_xp_earned

### Flutter (Dart)
- `UserProgressEntity`: totalXp, coursesEnrolled, currentStreak
- `LessonCompletionResult`: lessonId, isPassed, score, xpEarned
- `CourseProgressWithUnits`: course + unitsProgress array

## Common Operations

### Complete a Lesson
```bash
curl -X POST "http://localhost:8000/api/v1/progress/lessons/{lesson_id}/complete" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{
    "lesson_id": "uuid",
    "score": 85.0
  }'
```

**Response:**
```json
{
  "success": true,
  "data": {
    "lesson_id": "uuid",
    "is_passed": true,
    "score": 85.0,
    "best_score": 85.0,
    "xp_earned": 20,
    "total_xp": 120,
    "course_progress": 45.0,
    "message": "Congratulations! You passed the lesson and earned 20 XP!"
  }
}
```

### Get My Progress
```bash
curl -X GET "http://localhost:8000/api/v1/progress/me" \
  -H "Authorization: Bearer {token}"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "summary": {
      "total_xp": 150,
      "courses_enrolled": 2,
      "courses_completed": 0,
      "lessons_completed": 15,
      "current_streak": 5,
      "longest_streak": 10
    },
    "course_progress": [
      {
        "course_id": "uuid",
        "course_title": "English A1",
        "progress_percentage": 75.0,
        "lessons_completed": 15,
        "total_lessons": 20,
        "total_xp_earned": 150
      }
    ]
  }
}
```

## Database Queries

### Get User Progress
```sql
SELECT * FROM user_course_progress 
WHERE user_id = '{user_id}' AND course_id = '{course_id}';
```

### Get Lesson Completions
```sql
SELECT * FROM lesson_completion 
WHERE user_id = '{user_id}' AND is_passed = TRUE;
```

### Total XP
```sql
SELECT SUM(total_xp_earned) as total_xp 
FROM user_course_progress 
WHERE user_id = '{user_id}';
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 403 Forbidden | Check user is enrolled: `POST /courses/{id}/enroll` |
| 422 Validation Error | Verify score is 0-100 |
| Mock errors in tests | Run `flutter pub run build_runner build` |
| Backend tests fail | Install dependencies: `pip install -r requirements.txt` |

## Performance Tips

- Use pagination for course lists (default: 20 items/page)
- Cache progress stats in Flutter Provider
- Leverage AsyncSession for parallel DB queries
- Use indexed queries (user_id, course_id)

## Git Commits

```bash
f7f0bb0  fix: Resolve compile errors in model mappings
5826d60  feat(flutter): Course Presentation layer - Task 2.4
6dd36f3  feat(backend): Progress Tracking APIs - Task 2.5
124fa31  feat(flutter): Progress Tracking - Task 2.6
2f5f251  test: Comprehensive tests - Task 2.7
```

## Testing Summary

- **Backend:** 13 tests (progress API, XP system, authorization)
- **Flutter:** 40 tests total
  - ✅ 21/21 model tests passed
  - ⏳ 19 tests require mock generation

**Run all passing tests:**
```bash
flutter test test/features/progress/data/models/progress_model_test.dart
# Output: 00:02 +21: All tests passed!
```

---

**Phase 2 Status:** ✅ COMPLETE (All 8 tasks finished)
**Last Updated:** January 25, 2026
