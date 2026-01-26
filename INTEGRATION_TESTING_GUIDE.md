# 🧪 Backend-Frontend Integration Testing Guide

## 🎯 Objective
Verify complete integration between Flutter app and Backend service với Phase 1-4 features.

---

## 🔧 Setup Test Environment

### Backend Setup

```bash
# Terminal 1: Start backend
cd backend-service

# Ensure database is migrated
alembic upgrade head

# Seed test data
python scripts/seed_data.py

# Start server
uvicorn app.main:app --reload --port 8000
```

**Verify Backend**:
- ✅ http://localhost:8000/health → Status 200
- ✅ http://localhost:8000/docs → Swagger UI loads
- ✅ Database has sample data

---

### Flutter Setup

```bash
# Terminal 2: Start Flutter app
cd flutter-app

# Update API endpoint
# lib/core/network/api_config.dart
class ApiConfig {
  static const baseUrl = 'http://localhost:8000/api/v1';
  // For Android Emulator: 'http://10.0.2.2:8000/api/v1'
  // For iOS Simulator: 'http://localhost:8000/api/v1'
}

# Run app
flutter run
```

---

## 📋 Integration Test Scenarios

### Scenario 1: Authentication Flow ✅

**Test Case 1.1: Register New User**

1. **Action**: Tap "Register" button
2. **Input**:
   ```
   Email: test@example.com
   Username: testuser
   Password: password123
   ```
3. **Expected Backend Call**:
   ```
   POST http://localhost:8000/api/v1/auth/register
   Body: {
     "email": "test@example.com",
     "username": "testuser", 
     "password": "password123"
   }
   ```
4. **Expected Response**:
   ```json
   {
     "data": {
       "id": "uuid-here",
       "email": "test@example.com",
       "username": "testuser",
       "is_verified": false,
       "provider": "local"
     },
     "meta": {
       "request_id": "uuid",
       "timestamp": "2026-01-24T..."
     }
   }
   ```
5. **Flutter Actions**:
   - ✅ Parse ApiResponse envelope
   - ✅ Store user data locally
   - ✅ Navigate to onboarding/home
6. **Verify**:
   ```bash
   # Check user in database
   psql $DATABASE_URL -c "SELECT * FROM users WHERE email='test@example.com';"
   ```

---

**Test Case 1.2: Login with Credentials**

1. **Action**: Enter credentials and tap "Login"
2. **Expected Backend Call**:
   ```
   POST http://localhost:8000/api/v1/auth/login
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "access_token": "eyJ...",
       "refresh_token": "eyJ...",
       "token_type": "bearer",
       "user": { ... }
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Store tokens securely (flutter_secure_storage)
   - ✅ Store user data
   - ✅ Register device (POST /devices)
   - ✅ Navigate to home
5. **Verify**:
   - Token stored in secure storage
   - User data in local database
   - Device registered in backend

---

**Test Case 1.3: Token Refresh on 401**

1. **Setup**: Wait for access token to expire (or manually invalidate)
2. **Action**: Make any authenticated API call
3. **Expected Flow**:
   ```
   GET /courses -> 401 Unauthorized
   → Interceptor catches 401
   → POST /auth/refresh-token with refresh_token
   → Get new access_token
   → Retry original request with new token
   ```
4. **Verify**:
   - Original request succeeds
   - New token stored
   - User not logged out

---

### Scenario 2: Course Browsing & Learning 📚

**Test Case 2.1: Fetch Courses with Pagination**

1. **Action**: Open "Courses" tab
2. **Expected Backend Call**:
   ```
   GET http://localhost:8000/api/v1/courses?page=1&page_size=20
   Headers: {
     "Authorization": "Bearer eyJ..."
   }
   ```
3. **Expected Response**:
   ```json
   {
     "data": [
       {
         "id": "uuid",
         "title": "English for Beginners",
         "level": "A1",
         "tags": ["grammar", "vocabulary"],
         "content_version": 1
       }
     ],
     "pagination": {
       "page": 1,
       "page_size": 20,
       "total": 50,
       "total_pages": 3
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Parse PaginatedResponse
   - ✅ Display courses in grid/list
   - ✅ Load more on scroll
5. **Verify**:
   - Courses display correctly
   - Pagination works
   - Content version stored locally

---

**Test Case 2.2: Load Course Details with Units**

1. **Action**: Tap on a course
2. **Expected Backend Call**:
   ```
   GET http://localhost:8000/api/v1/courses/{id}/roadmap
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "course": { ... },
       "units": [
         {
           "id": "uuid",
           "title": "Greetings & Introductions",
           "order_index": 1,
           "background_color": "#4CAF50",
           "lessons": [
             {
               "id": "uuid",
               "title": "Saying Hello",
               "order_index": 1,
               "is_locked": false,
               "user_progress": {
                 "status": "not_started",
                 "score": 0
               }
             }
           ]
         }
       ]
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Display roadmap UI
   - ✅ Show units expandable
   - ✅ Indicate locked/unlocked lessons
   - ✅ Show progress on completed lessons
5. **Verify**:
   - Roadmap matches backend data
   - Locked lessons cannot be started

---

**Test Case 2.3: Start Lesson Session**

1. **Action**: Tap "Start" on an unlocked lesson
2. **Expected Backend Call**:
   ```
   POST http://localhost:8000/api/v1/lessons/{id}/start
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "session_id": "uuid",
       "lesson": { ... },
       "questions": [ ... ],
       "max_lives": 5
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Create local session state
   - ✅ Load questions
   - ✅ Start timer
   - ✅ Initialize lives counter
5. **Verify**:
   - Session created in backend
   - Questions displayed correctly

---

**Test Case 2.4: Submit Lesson Answers**

1. **Action**: Complete all questions and submit
2. **Expected Backend Call**:
   ```
   POST http://localhost:8000/api/v1/lessons/{id}/submit
   Body: {
     "session_id": "uuid",
     "answers": [
       {
         "question_id": "q1",
         "user_answer": "is",
         "time_spent_ms": 5000,
         "hint_used": false
       }
     ],
     "started_at": "2026-01-24T10:00:00Z",
     "finished_at": "2026-01-24T10:05:30Z"
   }
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "score": 85,
       "passed": true,
       "xp_earned": 15,
       "correct_answers": 9,
       "total_questions": 10,
       "feedback": [ ... ]
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Show results screen
   - ✅ Display score & XP
   - ✅ Update user's total XP
   - ✅ Mark lesson as completed locally
5. **Verify**:
   ```bash
   # Check lesson_attempts table
   psql $DATABASE_URL -c "SELECT * FROM lesson_attempts WHERE lesson_id='...';"
   
   # Check question_attempts table
   psql $DATABASE_URL -c "SELECT * FROM question_attempts WHERE lesson_attempt_id='...';"
   
   # Check user_progress updated
   psql $DATABASE_URL -c "SELECT * FROM user_progress WHERE lesson_id='...';"
   ```

---

### Scenario 3: Progress & Gamification 🎮

**Test Case 3.1: Fetch User Progress**

1. **Action**: Open "Progress" tab
2. **Expected Backend Call**:
   ```
   GET http://localhost:8000/api/v1/me/progress/summary
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "total_xp": 150,
       "current_streak": 5,
       "lessons_completed": 12,
       "time_spent_minutes": 240,
       "weekly_xp": [10, 25, 30, 20, 35, 15, 15]
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Display XP chart
   - ✅ Show streak calendar
   - ✅ Render stats

---

**Test Case 3.2: Unlock Achievement**

1. **Setup**: Complete first lesson (triggers "First Steps" achievement)
2. **Expected Backend Flow**:
   - Lesson submitted → Achievement check → Achievement unlocked
3. **Flutter Actions**:
   - ✅ Show achievement unlock animation
   - ✅ Display badge
   - ✅ Add XP & gems reward
4. **Verify**:
   ```bash
   psql $DATABASE_URL -c "SELECT * FROM user_achievements WHERE user_id='...';"
   ```

---

**Test Case 3.3: Fetch Leaderboard**

1. **Action**: Open "Leaderboard" tab
2. **Expected Backend Call**:
   ```
   GET http://localhost:8000/api/v1/leaderboard?league=bronze
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "entries": [
         {
           "rank": 1,
           "user": { "username": "user1", "avatar_url": "..." },
           "xp_earned": 500
         }
       ],
       "user_entry": {
         "rank": 15,
         "xp_earned": 150
       }
     },
     "meta": { ... }
   }
   ```
4. **Verify**:
   - User's rank highlighted
   - Top 10 displayed
   - League badge shown

---

**Test Case 3.4: Purchase Shop Item**

1. **Action**: Tap "Buy" on "Streak Freeze" (10 gems)
2. **Expected Backend Call**:
   ```
   POST http://localhost:8000/api/v1/shop/{item_id}/purchase
   ```
3. **Expected Response**:
   ```json
   {
     "data": {
       "transaction_id": "uuid",
       "item": { ... },
       "gems_spent": 10,
       "new_balance": 90
     },
     "meta": { ... }
   }
   ```
4. **Flutter Actions**:
   - ✅ Update wallet balance
   - ✅ Add item to inventory
   - ✅ Show success message
5. **Verify**:
   ```bash
   psql $DATABASE_URL -c "SELECT * FROM wallet_transactions WHERE user_id='...';"
   psql $DATABASE_URL -c "SELECT * FROM user_inventory WHERE user_id='...';"
   ```

---

### Scenario 4: Offline Mode & Sync 📴

**Test Case 4.1: Complete Lesson Offline**

1. **Setup**: Disable network connection
2. **Action**: Complete a lesson
3. **Flutter Actions**:
   - ✅ Store attempt in offline queue
   - ✅ Update local progress
   - ✅ Show offline indicator
4. **Verify**:
   ```dart
   // Check offline_queue table
   await db.query('offline_queue');
   ```

---

**Test Case 4.2: Sync When Online**

1. **Setup**: Re-enable network
2. **Expected Flow**:
   - Detect network available
   - Process offline queue
   - Submit queued attempts
   - Sync progress
3. **Verify**:
   - Queue emptied
   - Backend has all attempts
   - Progress consistent

---

## 🐛 Error Scenario Testing

### Error Case 1: Rate Limit Exceeded

1. **Setup**: Make 61 requests in 1 minute
2. **Expected Response**:
   ```
   Status: 429 Too Many Requests
   {
     "error": {
       "code": "RATE_LIMITED",
       "message": "Rate limit exceeded...",
       "details": {"retry_after_seconds": 60}
     }
   }
   ```
3. **Flutter Actions**:
   - ✅ Show rate limit message
   - ✅ Disable requests temporarily
   - ✅ Retry after delay

---

### Error Case 2: Server Error (500)

1. **Setup**: Trigger server error (invalid data)
2. **Expected Response**:
   ```
   Status: 500
   {
     "error": {
       "code": "INTERNAL_ERROR",
       "message": "An internal server error occurred"
     }
   }
   ```
3. **Flutter Actions**:
   - ✅ Show friendly error message
   - ✅ Log error details
   - ✅ Allow retry

---

### Error Case 3: Network Timeout

1. **Setup**: Simulate slow network
2. **Flutter Actions**:
   - ✅ Show loading indicator
   - ✅ Timeout after 30s
   - ✅ Show timeout message
   - ✅ Queue for offline if possible

---

## 📊 Performance Verification

### Load Testing

```bash
# Use Apache Bench to test backend
ab -n 1000 -c 10 http://localhost:8000/api/v1/courses

# Verify:
# - Average response time < 200ms
# - No failed requests
# - Rate limiting working
```

### Flutter Performance

```bash
flutter run --profile

# In DevTools:
# - Check FPS (should be 60fps)
# - Monitor memory usage
# - Profile widget rebuilds
```

---

## ✅ Integration Checklist

### Backend Verification
- [ ] Server running on port 8000
- [ ] Database migrated with Phase 1-4 models
- [ ] Sample data seeded
- [ ] Swagger UI accessible
- [ ] All endpoints return proper ApiResponse envelopes
- [ ] Error responses use ErrorCodes
- [ ] Rate limiting active
- [ ] CORS configured for Flutter origins

### Flutter Verification
- [ ] ApiClient handles response envelopes
- [ ] Error handling with ErrorCodes
- [ ] Token refresh on 401
- [ ] Request ID logging
- [ ] Offline queue implemented
- [ ] Sync manager working
- [ ] All screens connected to backend
- [ ] Loading states implemented
- [ ] Error states implemented

### Data Flow Verification
- [ ] User registration → Database user created
- [ ] Login → Tokens issued → Device registered
- [ ] Course fetch → Content version checked
- [ ] Lesson start → Session created
- [ ] Lesson submit → Attempts recorded → Progress updated
- [ ] Achievement unlock → User achievements updated
- [ ] Shop purchase → Wallet transaction recorded
- [ ] Offline action → Queued → Synced when online

---

## 📝 Test Execution Log

**Date**: ___________  
**Tester**: ___________

| Test Case | Status | Notes | Issues |
|-----------|--------|-------|--------|
| 1.1 Register | ⬜ | | |
| 1.2 Login | ⬜ | | |
| 1.3 Token Refresh | ⬜ | | |
| 2.1 Fetch Courses | ⬜ | | |
| 2.2 Course Details | ⬜ | | |
| 2.3 Start Lesson | ⬜ | | |
| 2.4 Submit Lesson | ⬜ | | |
| 3.1 User Progress | ⬜ | | |
| 3.2 Achievement | ⬜ | | |
| 3.3 Leaderboard | ⬜ | | |
| 3.4 Shop Purchase | ⬜ | | |
| 4.1 Offline Lesson | ⬜ | | |
| 4.2 Sync | ⬜ | | |

---

## 🚨 Common Issues & Solutions

### Issue: Cannot connect to localhost from Android emulator
**Solution**: Use `http://10.0.2.2:8000` instead of `http://localhost:8000`

### Issue: CORS error
**Solution**: Add Flutter origin to `ALLOWED_ORIGINS` in backend config

### Issue: Token not attached to requests
**Solution**: Check ApiClient interceptor is adding Authorization header

### Issue: Response parsing error
**Solution**: Verify response matches ApiResponse<T> schema

### Issue: Database not found
**Solution**: Run `alembic upgrade head` and `python scripts/seed_data.py`

---

## 📞 Support

For issues during integration testing:
1. Check backend logs: `tail -f backend.log`
2. Check Flutter logs: `flutter logs`
3. Verify API contract: http://localhost:8000/docs
4. Review [IMPLEMENTATION_PROGRESS.md](backend-service/IMPLEMENTATION_PROGRESS.md)
