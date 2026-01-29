# Course Seeding Guide

## Overview
This guide explains how to populate the database with sample courses for the LexiLingo application.

## What Was Fixed

### Problem
The Courses page showed "No courses available" due to:
1. Empty database (no courses seeded)
2. API validation error: `ResponseValidationError` in `/api/v1/courses` endpoint

### Solution

#### 1. Database Seeding
Created `scripts/seed_courses.py` with 6 sample courses:

**Free Courses:**
- **English for Beginners** (A1) - Basic vocabulary and grammar
- **Everyday Conversation** (A2) - Practical dialogue skills  
- **Travel English** (A2) - Essential phrases for travelers

**Paid Courses:**
- **Business English Essentials** (B1) - Professional communication
- **Advanced Grammar Mastery** (B2) - Complex grammar topics
- **IELTS Preparation Course** (C1) - Test preparation

Each course includes:
- Units and Lessons with hierarchical structure
- XP rewards (10-30 XP per lesson)
- Duration estimates (15-35 minutes)
- Tags for categorization
- Thumbnail URLs
- CEFR level classification (A1-C2)

#### 2. API Fix
Fixed the response model generic type in `app/routes/courses.py`:

**Before (Wrong):**
```python
@router.get("", response_model=PaginatedResponse[List[CourseListItem]])
```

**After (Correct):**
```python
@router.get("", response_model=PaginatedResponse[CourseListItem])
```

**Why?** `PaginatedResponse` already defines `data: list[DataT]`, so the generic parameter should be the item type (`CourseListItem`), not the list type (`List[CourseListItem]`). Using the list type caused FastAPI to serialize CourseListItem objects as tuples instead of dictionaries.

## How to Run Course Seeding

### Prerequisites
- Backend service must be running
- PostgreSQL database must be accessible
- Virtual environment activated (if using one)

### Steps

1. **Navigate to backend directory:**
   ```bash
   cd backend-service
   ```

2. **Run the seeding script:**
   ```bash
   python -m scripts.seed_courses
   ```

3. **Verify success:**
   The script will output:
   ```
   ✨ Successfully seeded 6 courses!
   📊 Database Summary:
     Courses: 6
     Units: 7
     Lessons: 11
   ```

### Re-seeding (if needed)

To clear existing courses and re-seed:

```bash
python -c "
import asyncio
from app.database import get_db
from app.models.course import Course, Unit, Lesson

async def clear_courses():
    async for db in get_db():
        # Delete all lessons first (due to foreign key constraints)
        await db.execute('DELETE FROM lessons')
        await db.execute('DELETE FROM units')
        await db.execute('DELETE FROM courses')
        await db.commit()
        print('✅ Cleared all courses')

asyncio.run(clear_courses())
"

python -m scripts.seed_courses
```

## Testing the API

### Test Course List Endpoint

```bash
curl -s "http://localhost:8000/api/v1/courses?page=1&page_size=3" | python3 -m json.tool
```

**Expected Response:**
```json
{
    "data": [
        {
            "id": "uuid-here",
            "title": "Travel English - Free Course",
            "description": "Essential English phrases...",
            "language": "en",
            "level": "A2",
            "tags": ["travel", "practical", "elementary", "free"],
            "thumbnail_url": "https://...",
            "total_lessons": 1,
            "total_xp": 400,
            "estimated_duration": 240,
            "is_enrolled": null
        }
        // ... more courses
    ],
    "pagination": {
        "page": 1,
        "page_size": 3,
        "total": 6,
        "total_pages": 2
    },
    "meta": {
        "request_id": "...",
        "timestamp": "..."
    }
}
```

### Test with Authentication

```bash
# Login first
TOKEN=$(curl -s -X POST "http://localhost:8000/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['data']['access_token'])")

# Get courses with auth
curl -s "http://localhost:8000/api/v1/courses?page=1&page_size=3" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

When authenticated, `is_enrolled` will show `true` or `false` instead of `null`.

## Course Data Structure

### Course Schema
```python
{
    "id": UUID,
    "title": str,
    "description": str,
    "language": str,           # e.g., "en", "vi"
    "level": str,              # A1, A2, B1, B2, C1, C2
    "tags": List[str],         # e.g., ["beginner", "free"]
    "thumbnail_url": str,
    "total_lessons": int,
    "total_xp": int,
    "estimated_duration": int, # minutes
    "is_enrolled": bool | null
}
```

### Hierarchy
```
Course
└── Unit (e.g., "Unit 1: Introduction")
    └── Lesson (e.g., "Greetings and Introductions")
        ├── xp_reward: int
        ├── duration_minutes: int
        ├── order_index: int
```

## Frontend Integration

The Flutter app should now display courses on the Courses page:
1. Navigate to http://localhost:8080 in Chrome
2. Login with credentials
3. Click on "Courses" tab
4. Should see 6 courses with titles, descriptions, levels, and tags

## Troubleshooting

### Issue: "No courses available"
**Solution:** Check if seeding was successful:
```bash
python -c "
import asyncio
from app.database import get_db
from app.models.course import Course
from sqlalchemy import select

async def check():
    async for db in get_db():
        result = await db.execute(select(Course))
        courses = result.scalars().all()
        print(f'Found {len(courses)} courses')
        for c in courses:
            print(f'  - {c.title}')

asyncio.run(check())
"
```

### Issue: ResponseValidationError
**Solution:** Ensure `response_model=PaginatedResponse[CourseListItem]` (not `List[CourseListItem]`)

### Issue: IntegrityError during seeding
**Solution:** Ensure `await db.flush()` is called after adding Units before adding Lessons

## Next Steps

To add more courses:
1. Edit `scripts/seed_courses.py`
2. Add new course definitions in `seed_data()` function
3. Follow the existing pattern with Units and Lessons
4. Run the seeding script again

## Related Files

- **Seeding Script:** `backend-service/scripts/seed_courses.py`
- **API Route:** `backend-service/app/routes/courses.py`
- **CRUD Logic:** `backend-service/app/crud/course.py`
- **Database Models:** `backend-service/app/models/course.py`
- **Response Schemas:** `backend-service/app/schemas/course.py`
- **Generic Response:** `backend-service/app/schemas/common.py`

---

**Status:** ✅ Fully functional (as of 2026-01-29)
