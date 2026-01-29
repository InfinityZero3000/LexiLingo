# Learning Roadmap Feature

## 📚 Tổng quan

Tính năng **Learning Roadmap** (Lộ trình học tập) cho phép người dùng xem tiến trình học tập của mình theo dạng **roadmap trực quan** với các unit và lesson được sắp xếp theo thứ tự logic.

## 🎯 Tính năng chính

### Backend API

#### 1. **Lesson Session Management** (`/api/v1/learning`)

- **POST `/lessons/{lesson_id}/start`** - Bắt đầu bài học mới hoặc tiếp tục bài đang dở
- **POST `/attempts/{attempt_id}/answer`** - Submit câu trả lời cho câu hỏi
- **POST `/attempts/{attempt_id}/complete`** - Hoàn thành bài học

#### 2. **Course Roadmap Visualization** (`/api/v1/learning`)

- **GET `/courses/{course_id}/roadmap`** - Lấy roadmap đầy đủ của khóa học

### Frontend UI

**Learning Roadmap Screen** - Màn hình hiển thị lộ trình học tập:

- ✅ Vertical scrolling roadmap design (giống Duolingo)
- ✅ Unit cards với progress indicator
- ✅ Lesson items với trạng thái: locked 🔒, current ▶️, completed ✅
- ✅ Smooth animations khi scroll
- ✅ Stars display (0-3 sao) cho mỗi lesson hoàn thành
- ✅ Continue Learning button floating

## 🏗️ Cấu trúc Code

### Backend

```
backend-service/
├── app/
│   ├── routes/
│   │   └── learning.py          # NEW: Learning session endpoints
│   ├── schemas/
│   │   └── progress.py          # UPDATED: Added roadmap schemas
│   └── main.py                  # UPDATED: Include learning router
├── tests/
│   ├── conftest.py              # NEW: Test fixtures
│   └── test_learning_routes.py # NEW: 15+ test cases
```

### Frontend

```
flutter-app/
└── lib/
    └── features/
        └── learning/
            ├── presentation/
            │   └── screens/
            │       └── learning_roadmap_screen.dart  # NEW: Roadmap UI
            └── data/
                └── models/
                    └── roadmap_models.dart            # NEW: Data models
```

## 📊 Data Flow

### 1. Start Lesson

```
User taps lesson
    ↓
POST /api/v1/learning/lessons/{id}/start
    ↓
Backend creates LessonAttempt
    ↓
Returns: attempt_id, lives, hints
    ↓
Navigate to lesson screen
```

### 2. Submit Answer

```
User answers question
    ↓
POST /api/v1/learning/attempts/{id}/answer
    ↓
Backend validates answer
    ↓
Updates: score, lives, hints
    ↓
Returns: feedback, XP earned
```

### 3. Complete Lesson

```
User finishes all questions
    ↓
POST /api/v1/learning/attempts/{id}/complete
    ↓
Backend calculates final score
    ↓
Updates: UserProgress, Streak, XP
    ↓
Returns: stars, achievements
    ↓
Show completion dialog
```

### 4. Load Roadmap

```
User opens course
    ↓
GET /api/v1/learning/courses/{id}/roadmap
    ↓
Backend fetches: Units, Lessons, Progress
    ↓
Determines: locked/unlocked/current
    ↓
Returns: full roadmap structure
    ↓
Render beautiful UI
```

## 🎨 UI Design

### Roadmap Screen Components

1. **App Bar** - Course title với gradient background
2. **Progress Header** - Overall progress với stats (XP, streak)
3. **Unit Cards** - Mỗi unit là 1 card với:
   - Unit number badge
   - Unit title & subtitle
   - Progress bar
   - Lessons list
4. **Lesson Items** - Mỗi lesson hiển thị:
   - Status icon (lock/play/check)
   - Lesson number & title
   - Stars earned (nếu đã complete)
   - Connection line giữa các lesson
5. **Continue Button** - FAB để tiếp tục học

### Color Scheme

- **Completed** 🟢 Green (#4CAF50)
- **Current** 🔵 Blue (#2196F3)
- **Locked** ⚫ Grey (#9E9E9E)

## 🧪 Testing

### Test Coverage

✅ **15+ test cases** đã được viết:

**Lesson Session Tests:**
- Start lesson successfully
- Resume existing attempt
- Start non-existent lesson (404)
- Submit correct answer
- Submit wrong answer (loses life)
- Submit with hint (reduced XP)
- Complete lesson - passed
- Complete lesson - failed
- Complete updates UserProgress
- Cannot complete twice

**Roadmap Tests:**
- Get roadmap successfully
- Roadmap unit structure
- Lesson lock states
- Roadmap not found (404)

### Run Tests

```bash
cd backend-service

# Run all tests
pytest tests/test_learning_routes.py -v

# Run with coverage
pytest tests/test_learning_routes.py --cov=app.routes.learning

# Run specific test
pytest tests/test_learning_routes.py::TestLearningSession::test_start_lesson_success -v
```

## 📈 Performance

### Backend Response Times (Target)

- Start lesson: < 100ms
- Submit answer: < 50ms
- Complete lesson: < 150ms (includes UserProgress update)
- Get roadmap: < 200ms (with 10 units, 50 lessons)

### Frontend Rendering

- Smooth 60 FPS scrolling
- Staggered animations cho unit cards
- Lazy loading cho large roadmaps

## 🚀 Next Steps

### Phase 1 (Current) ✅
- [x] Backend API endpoints
- [x] Frontend UI components
- [x] Test cases
- [ ] **TODO: Run tests & fix bugs**
- [ ] **TODO: Commit to GitHub**

### Phase 2 (Future)
- [ ] Real question validation logic
- [ ] Achievement system integration
- [ ] Next lesson auto-unlock
- [ ] Offline support
- [ ] Analytics tracking

## 🔗 Related Files

**Backend:**
- `app/routes/learning.py` - Main endpoints
- `app/schemas/progress.py` - Request/response models
- `app/models/progress.py` - Database models
- `tests/test_learning_routes.py` - Unit tests

**Frontend:**
- `learning_roadmap_screen.dart` - Main UI
- `roadmap_models.dart` - Data models
- (TODO) `learning_repository.dart` - API calls
- (TODO) `learning_provider.dart` - State management

## 📝 API Examples

### Start Lesson

**Request:**
```bash
POST /api/v1/learning/lessons/{lesson_id}/start
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "message": "Lesson started",
  "data": {
    "attempt_id": "uuid",
    "lesson_id": "uuid",
    "started_at": "2026-01-25T10:00:00Z",
    "total_questions": 10,
    "lives_remaining": 3,
    "hints_available": 3
  }
}
```

### Get Roadmap

**Request:**
```bash
GET /api/v1/learning/courses/{course_id}/roadmap
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "course_id": "uuid",
    "course_title": "PrepTalk - 500 từ vựng",
    "completion_percentage": 10.0,
    "total_xp_earned": 125,
    "current_streak": 5,
    "units": [
      {
        "unit_id": "uuid",
        "unit_number": 1,
        "title": "CORPORATE FINANCE",
        "is_current": true,
        "lessons": [
          {
            "lesson_id": "uuid",
            "lesson_number": 1,
            "title": "Introduction to Finance",
            "is_locked": false,
            "is_current": true,
            "is_completed": false,
            "stars_earned": 0
          }
        ]
      }
    ]
  }
}
```

## ✨ Features Highlights

1. **Smart Unlocking** - Lessons unlock sequentially based on completion
2. **Progress Persistence** - Resume incomplete attempts
3. **Gamification** - Lives, hints, stars, XP rewards
4. **Streak Tracking** - Daily learning streak updates
5. **Beautiful UI** - Smooth animations, modern design
6. **Performance** - Optimized queries, lazy loading

---

**Created:** January 25, 2026  
**Status:** ✅ Implementation Complete, ⏳ Testing in Progress
