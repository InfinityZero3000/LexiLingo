# Flutter App Development Tasks - LexiLingo

## 🎯 Mục Tiêu
Xây dựng Flutter app tích hợp với Backend mới (Phase 1-4) để tạo trải nghiệm học tiếng Anh hoàn chỉnh.

---

## 📋 Phase 1: Core Infrastructure & API Integration (Week 1-2)

### Task 1.1: Cập nhật API Client với Response Envelopes ⚡ HIGH PRIORITY

**File**: `lib/core/network/api_client.dart`

- [ ] **1.1.1** Tạo response models cho API envelopes
  ```dart
  // lib/core/network/response_models.dart
  class ApiResponse<T> {
    final T data;
    final RequestMeta meta;
  }
  
  class PaginatedResponse<T> {
    final List<T> data;
    final PaginationMeta pagination;
    final RequestMeta meta;
  }
  
  class ErrorResponse {
    final ErrorDetail error;
    final RequestMeta meta;
  }
  ```

- [ ] **1.1.2** Update ApiClient để handle envelopes
  ```dart
  // Parse response envelope
  ApiResponse<T> _parseResponse<T>(Response response) {
    final envelope = ApiResponse<T>.fromJson(response.data);
    return envelope;
  }
  ```

- [ ] **1.1.3** Implement error handling với ErrorCodes
  ```dart
  // Handle standard error codes
  switch (errorCode) {
    case 'AUTH_INVALID':
    case 'AUTH_EXPIRED':
      // Trigger refresh token
    case 'RATE_LIMITED':
      // Show rate limit message
  }
  ```

- [ ] **1.1.4** Add request ID tracking
  - Log request_id từ response meta
  - Store để debug và support

**Estimated Time**: 6-8 hours

---

### Task 1.2: Authentication Flow Update

**Files**: `lib/features/auth/`

- [ ] **1.2.1** Update auth schemas với backend models
  ```dart
  // lib/features/auth/data/models/user_model.dart
  class UserModel {
    final String id;  // UUID
    final String email;
    final String username;
    final String displayName;
    final String? avatarUrl;
    final String provider;  // NEW: local, google, facebook
    final bool isVerified;  // NEW
    final String level;
    final DateTime? lastLogin;
    final String? lastLoginIp;  // NEW
  }
  ```

- [ ] **1.2.2** Implement device tracking
  ```dart
  // lib/features/auth/data/datasources/device_datasource.dart
  Future<void> registerDevice() async {
    final deviceInfo = await _getDeviceInfo();
    await apiClient.post('/devices', data: {
      'device_id': deviceInfo.id,
      'device_type': Platform.isIOS ? 'ios' : 'android',
      'fcm_token': await _getFCMToken(),
    });
  }
  ```

- [ ] **1.2.3** Implement refresh token rotation
  ```dart
  // lib/features/auth/data/datasources/token_datasource.dart
  Future<TokenPair> refreshToken(String refreshToken) async {
    final response = await apiClient.post('/auth/refresh-token', 
      data: {'refresh_token': refreshToken}
    );
    // Rotate: old token invalidated, new pair returned
    return TokenPair.fromJson(response.data.data);
  }
  ```

- [ ] **1.2.4** Handle multi-provider auth (Google + local)
  - Update sign in flow
  - Store provider type
  - Handle provider switching

**Estimated Time**: 10-12 hours

---

### Task 1.3: Offline-First Architecture

**Files**: `lib/core/database/`, `lib/core/sync/`

- [ ] **1.3.1** Update local database schema
  ```dart
  // lib/core/database/tables.dart
  // Add content_version to all content tables
  class CoursesTable {
    static const String tableName = 'courses';
    static const String contentVersion = 'content_version';
  }
  ```

- [ ] **1.3.2** Implement sync strategy
  ```dart
  // lib/core/sync/sync_manager.dart
  class SyncManager {
    Future<void> syncCourses() async {
      final localVersion = await db.getContentVersion('courses');
      final remote = await api.getCourses(
        headers: {'If-None-Match': localVersion}
      );
      if (remote.hasNewVersion) {
        await db.updateCourses(remote.data);
      }
    }
  }
  ```

- [ ] **1.3.3** Queue offline actions
  ```dart
  // lib/core/sync/offline_queue.dart
  class OfflineQueue {
    Future<void> queueLessonSubmit(LessonAttempt attempt) async {
      await db.insert('offline_queue', {
        'action': 'submit_lesson',
        'payload': jsonEncode(attempt),
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    
    Future<void> processQueue() async {
      // Process when online
    }
  }
  ```

- [ ] **1.3.4** Implement conflict resolution
  - Server wins for content
  - Merge strategy for user data

**Estimated Time**: 12-16 hours

---

## 📚 Phase 2: Course Management & Learning UI (Week 3-4)

### Task 2.1: Course Hierarchy UI (Course → Unit → Lesson)

**Files**: `lib/features/course/`

- [ ] **2.1.1** Update Course models with Units
  ```dart
  // lib/features/course/domain/entities/course.dart
  class Course {
    final String id;
    final String title;
    final List<String> tags;  // NEW
    final int totalXp;        // NEW
    final int estimatedDuration;  // NEW
    final int contentVersion; // NEW
    final List<Unit> units;   // NEW: Hierarchical
  }
  
  class Unit {
    final String id;
    final String title;
    final String? backgroundColor;  // NEW: UI color
    final List<Lesson> lessons;
  }
  ```

- [ ] **2.1.2** Create Roadmap Widget (Duolingo-style)
  ```dart
  // lib/features/course/presentation/widgets/course_roadmap.dart
  class CourseRoadmap extends StatelessWidget {
    // Vẽ đường cong lượn sóng
    // Hiển thị Units và Lessons
    // State: locked, active, completed
  }
  ```

- [ ] **2.1.3** Implement prerequisite logic
  ```dart
  // Check if lesson is unlocked
  bool isLessonUnlocked(Lesson lesson) {
    if (lesson.prerequisiteLessonId == null) return true;
    return userProgress.isLessonCompleted(lesson.prerequisiteLessonId);
  }
  ```

- [ ] **2.1.4** Course detail page với Units
  - Expandable Units
  - Lesson list per Unit
  - Progress indicator
  - Start/Resume button

**Estimated Time**: 14-18 hours

---

### Task 2.2: Lesson Session Manager (Phase 3)

**Files**: `lib/features/learning/`

- [ ] **2.2.1** Create Learning Session State
  ```dart
  // lib/features/learning/domain/entities/learning_session.dart
  class LearningSession {
    final String lessonId;
    final List<Question> questions;
    final int currentQuestionIndex;
    final List<UserAnswer> answers;
    final int livesRemaining;
    final int hintsUsed;
    final DateTime startedAt;
    final SessionStats stats;
  }
  ```

- [ ] **2.2.2** Implement Question Types
  ```dart
  // Multiple choice
  class MultipleChoiceQuestion extends Question {
    final List<String> options;
    final int correctAnswerIndex;
  }
  
  // Fill in the blank
  class FillBlankQuestion extends Question {
    final String template;  // "My name ___ John"
    final String correctAnswer;
  }
  
  // Drag and drop
  class DragDropQuestion extends Question {
    final List<String> words;
    final String correctSentence;
  }
  
  // Listening
  class ListeningQuestion extends Question {
    final String audioUrl;
    final String correctTranscription;
  }
  ```

- [ ] **2.2.3** Build Interactive Widgets
  ```dart
  // lib/features/learning/presentation/widgets/
  - multiple_choice_widget.dart
  - fill_blank_widget.dart
  - drag_drop_widget.dart
  - listening_widget.dart (với audio player)
  - speaking_button.dart (record audio - mockup)
  ```

- [ ] **2.2.4** Implement Lives & Hints System
  ```dart
  class SessionManager {
    void answerQuestion(Answer answer) {
      if (!answer.isCorrect) {
        session.livesRemaining--;
        if (session.livesRemaining == 0) {
          _showGameOverDialog();
        }
      }
    }
    
    void useHint() {
      if (session.hintsUsed < MAX_HINTS) {
        session.hintsUsed++;
        _showHint();
      }
    }
  }
  ```

- [ ] **2.2.5** Track Performance Metrics
  ```dart
  // Track cho AI analysis
  class QuestionAttemptTracker {
    void trackAnswer(QuestionAttempt attempt) {
      attempt.timeSpentMs = stopwatch.elapsedMilliseconds;
      attempt.hintUsed = session.hintsUsed > 0;
      // Queue to sync với backend
      offlineQueue.queueQuestionAttempt(attempt);
    }
  }
  ```

**Estimated Time**: 20-24 hours

---

### Task 2.3: Progress Tracking & Submission

**Files**: `lib/features/progress/`

- [ ] **2.3.1** Create Progress data models
  ```dart
  // lib/features/progress/data/models/lesson_attempt_model.dart
  class LessonAttemptModel {
    final String id;
    final String lessonId;
    final DateTime startedAt;
    final DateTime? finishedAt;
    final int score;
    final bool passed;
    final int xpEarned;
    final SessionStats stats;
  }
  ```

- [ ] **2.3.2** Implement session APIs
  ```dart
  // Start lesson
  Future<LessonSession> startLesson(String lessonId) async {
    final response = await apiClient.post('/lessons/$lessonId/start');
    return LessonSession.fromJson(response.data.data);
  }
  
  // Submit lesson
  Future<LessonResult> submitLesson(
    String lessonId, 
    LessonAttempt attempt
  ) async {
    final response = await apiClient.post(
      '/lessons/$lessonId/submit',
      data: attempt.toJson(),
    );
    return LessonResult.fromJson(response.data.data);
  }
  ```

- [ ] **2.3.3** Build Progress Dashboard
  ```dart
  // lib/features/progress/presentation/pages/progress_page.dart
  - XP chart (weekly/monthly)
  - Streak calendar (GitHub heatmap style)
  - Completed lessons counter
  - Current level & progress to next
  - Time spent learning
  ```

- [ ] **2.3.4** Implement local progress caching
  - Cache progress locally
  - Sync khi có mạng
  - Show cached data khi offline

**Estimated Time**: 12-16 hours

---

## 🎮 Phase 3: Gamification Features (Week 5-6)

### Task 3.1: Achievement System

**Files**: `lib/features/gamification/achievements/`

- [ ] **3.1.1** Create Achievement models
  ```dart
  class Achievement {
    final String id;
    final String name;
    final String description;
    final String badgeIcon;
    final String category;
    final bool isUnlocked;
    final int progress;      // 0-100%
    final DateTime? unlockedAt;
  }
  ```

- [ ] **3.1.2** Build Achievements Grid UI
  ```dart
  // lib/features/gamification/presentation/pages/achievements_page.dart
  - GridView with badge icons
  - Locked badges (mờ đi)
  - Progress indicators
  - Filter by category
  - Showcase achievements on profile
  ```

- [ ] **3.1.3** Achievement notification
  ```dart
  void showAchievementUnlocked(Achievement achievement) {
    // Fancy animation overlay
    // Show badge + description
    // XP & Gems reward
  }
  ```

**Estimated Time**: 10-12 hours

---

### Task 3.2: Leaderboard & League System

**Files**: `lib/features/gamification/leaderboard/`

- [ ] **3.2.1** Create Leaderboard UI
  ```dart
  // lib/features/gamification/presentation/pages/leaderboard_page.dart
  - Weekly leaderboard
  - League badges (Bronze, Silver, Gold, Platinum, Diamond)
  - User rank highlight
  - Top 10 list
  - Promotion/Demotion indicators
  ```

- [ ] **3.2.2** Implement League logic
  ```dart
  class LeaderboardManager {
    Future<void> fetchLeaderboard(String league) async {
      final response = await api.get('/leaderboard?league=$league');
      // Update local state
    }
  }
  ```

- [ ] **3.2.3** Add animations
  - Rank change animation
  - Promotion celebration
  - League badge glow effect

**Estimated Time**: 12-14 hours

---

### Task 3.3: Virtual Shop & Wallet

**Files**: `lib/features/gamification/shop/`

- [ ] **3.3.1** Wallet widget
  ```dart
  // lib/features/gamification/presentation/widgets/wallet_widget.dart
  - Display gems balance
  - Gems earned today
  - Transaction history
  ```

- [ ] **3.3.2** Shop page
  ```dart
  // Items: Streak Freeze, Double XP, Hint Pack
  - Item cards với price
  - Purchase button
  - Confirmation dialog
  - Success animation
  ```

- [ ] **3.3.3** Inventory management
  ```dart
  - Active items indicator
  - Expiry countdown
  - Use/Activate button
  ```

**Estimated Time**: 10-12 hours

---

### Task 3.4: Social Features

**Files**: `lib/features/social/`

- [ ] **3.4.1** Following system
  ```dart
  - Search users
  - Follow/Unfollow button
  - Following/Followers list
  ```

- [ ] **3.4.2** Activity Feed
  ```dart
  // Newsfeed showing:
  - Friend completed lesson
  - Friend unlocked achievement
  - Friend reached streak milestone
  - Timeline UI
  ```

**Estimated Time**: 10-12 hours

---

## 🧪 Phase 4: Backend Integration & Testing (Week 7-8)

### Task 4.1: End-to-End Integration Testing

**Files**: `integration_test/`

- [ ] **4.1.1** Setup integration test environment
  ```dart
  // integration_test/app_test.dart
  void main() {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    
    group('E2E Tests', () {
      testWidgets('Complete user flow', (tester) async {
        // 1. Launch app
        // 2. Register
        // 3. Login
        // 4. Browse courses
        // 5. Start lesson
        // 6. Complete lesson
        // 7. Check progress
      });
    });
  }
  ```

- [ ] **4.1.2** Test offline scenarios
  ```dart
  testWidgets('Offline mode', (tester) async {
    // Disable network
    // Complete lesson offline
    // Verify queued
    // Enable network
    // Verify sync
  });
  ```

- [ ] **4.1.3** Test error handling
  ```dart
  testWidgets('Handle API errors', (tester) async {
    // 401 Unauthorized -> Refresh token
    // 429 Rate limit -> Show message
    // 500 Server error -> Retry
  });
  ```

**Estimated Time**: 16-20 hours

---

### Task 4.2: API Contract Testing

**Files**: `test/api_contract/`

- [ ] **4.2.1** Test response envelopes
  ```dart
  test('Auth endpoints return ApiResponse envelope', () async {
    final response = await api.login(...);
    expect(response, isA<ApiResponse<LoginData>>());
    expect(response.meta.requestId, isNotNull);
  });
  ```

- [ ] **4.2.2** Test error responses
  ```dart
  test('Invalid login returns ErrorResponse', () async {
    final response = await api.login(invalid: true);
    expect(response.error.code, equals('AUTH_INVALID'));
  });
  ```

- [ ] **4.2.3** Test pagination
  ```dart
  test('Course list pagination works', () async {
    final response = await api.getCourses(page: 1, pageSize: 20);
    expect(response.pagination.page, equals(1));
    expect(response.data.length, lessThanOrEqualTo(20));
  });
  ```

**Estimated Time**: 8-10 hours

---

### Task 4.3: Performance Testing

- [ ] **4.3.1** Profile app performance
  ```bash
  flutter run --profile
  # Check frame rendering
  # Monitor memory usage
  # Test on low-end devices
  ```

- [ ] **4.3.2** Optimize heavy operations
  - Image caching
  - Database query optimization
  - Reduce widget rebuilds (RepaintBoundary)

- [ ] **4.3.3** Load testing
  - Test với 1000+ courses
  - Test với large lesson content
  - Test offline database size

**Estimated Time**: 8-10 hours

---

### Task 4.4: Backend Connection Verification

**Files**: `test/backend_integration/`

- [ ] **4.4.1** Verify all endpoints working
  ```dart
  // Create checklist
  ✓ POST /auth/register
  ✓ POST /auth/login
  ✓ POST /auth/refresh-token
  ✓ GET  /courses
  ✓ GET  /courses/{id}
  ✓ POST /lessons/{id}/start
  ✓ POST /lessons/{id}/submit
  ✓ GET  /me/progress
  ✓ GET  /achievements
  ✓ GET  /leaderboard
  ✓ GET  /shop
  ✓ POST /shop/{id}/purchase
  ```

- [ ] **4.4.2** Test data flow
  ```dart
  // Verify data consistency
  test('Lesson completion updates progress', () async {
    final beforeXP = await api.getMe().then((u) => u.xp);
    await completeLesson(lessonId);
    final afterXP = await api.getMe().then((u) => u.xp);
    expect(afterXP, greaterThan(beforeXP));
  });
  ```

- [ ] **4.4.3** Security testing
  - Test without auth token → 401
  - Test with expired token → 401 + refresh
  - Test rate limiting
  - Test CORS headers

**Estimated Time**: 10-12 hours

---

## 📊 Progress Tracking

### Overall Progress Milestones

```
Week 1-2:  ████████░░░░░░░░░░░░  40% - API Integration
Week 3-4:  ████████████████░░░░  80% - Core Features
Week 5-6:  ████████████████████ 100% - Gamification
Week 7-8:  ████████████████████ 100% - Testing & Polish
```

---

## 🎯 Testing Checklist

### Manual Testing
- [ ] User can register and login
- [ ] User can browse courses
- [ ] User can start and complete lessons
- [ ] Progress is tracked correctly
- [ ] Achievements unlock properly
- [ ] Leaderboard updates
- [ ] Shop purchases work
- [ ] Offline mode functions
- [ ] Sync works after going online

### Automated Testing
- [ ] Unit tests: 80%+ coverage
- [ ] Widget tests: Critical UI components
- [ ] Integration tests: Main user flows
- [ ] API contract tests: All endpoints

---

## 📝 Documentation Required

- [ ] API integration guide
- [ ] Widget library documentation
- [ ] State management patterns
- [ ] Offline sync strategy
- [ ] Testing strategy
- [ ] Deployment guide

---

## 🚀 Ready for Production

- [ ] All tests passing
- [ ] Performance optimized
- [ ] Error handling complete
- [ ] Logging configured
- [ ] Analytics integrated
- [ ] App icons & splash screen
- [ ] Store listings ready
- [ ] Privacy policy & terms

---

**Estimated Total Time**: 150-180 hours (6-8 weeks)

**Team Recommendation**: 2 developers (1 senior + 1 mid-level)
