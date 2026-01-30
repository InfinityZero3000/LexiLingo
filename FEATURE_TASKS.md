# 📋 LexiLingo - Danh Sách Nhiệm Vụ Phát Triển

> **Ngày tạo**: 28/01/2026  
> **Mục tiêu**: Hoàn thiện và mở rộng tính năng LexiLingo theo Clean Architecture  
> **Branch**: feature

---

## 📊 Tổng Quan Hệ Thống Hiện Tại

### Kiến Trúc
- **Flutter App**: Clean Architecture 3 layers (Data → Domain → Presentation)
- **State Management**: Provider + GetIt DI
- **Backend**: FastAPI (Python) - Port 8000
- **AI Service**: FastAPI + Gemini/Orchestrator - Port 8001

### Thống Kê
| Thành phần | Số lượng |
|------------|----------|
| Feature Modules | 10 |
| Screens | 14 |
| Backend Endpoints | ~25 |
| AI Endpoints | ~20 |
| Providers | 9 |

---

## ✅ Checklist Nhiệm Vụ

### 🔴 Nhóm 1: Hoàn Thiện Tính Năng Dở Dang (Ưu tiên: CAO)

#### 1.1 Learning Roadmap Screen
- [ ] **1.1.1** Restore file `learning_roadmap_screen.dart` từ `.bak`
- [ ] **1.1.2** Tạo `GetRoadmapUseCase` trong `features/learning/domain/usecases/`
- [ ] **1.1.3** Tạo `RoadmapRepository` interface và implementation
- [ ] **1.1.4** Kết nối API `GET /learning/courses/{id}/roadmap`
- [ ] **1.1.5** Update `LearningProvider` với roadmap state
- [ ] **1.1.6** Thiết kế UI tree-style roadmap với animations
- [ ] **1.1.7** Test navigation từ Course Detail → Roadmap

#### 1.2 Lesson Content từ API
- [x] **1.2.1** Review endpoint `GET /learning/lessons/{id}` trong backend ✅ (30/01/2026)
- [x] **1.2.2** Implement logic fetch lesson content thực (không mock) ✅ (30/01/2026)
- [x] **1.2.3** Tạo `GetLessonContentUseCase` ✅ (đã có sẵn)
- [x] **1.2.4** Update `LearningProvider.startLesson()` để gọi API ✅ (30/01/2026)
- [x] **1.2.5** Handle loading/error states trong UI ✅ (đã có sẵn)
- [ ] **1.2.6** Cache lesson content locally với SQLite

#### 1.3 Answer Validation
- [x] **1.3.1** Review `POST /learning/lessons/{id}/submit` trong backend ✅ (30/01/2026)
- [x] **1.3.2** Implement validation logic (không trả mock `is_correct: true`) ✅ (30/01/2026)
- [ ] **1.3.3** Tích hợp AI validation cho câu trả lời tự do
- [x] **1.3.4** Update `LearningProvider.submitAnswer()` ✅ (đã có sẵn)
- [x] **1.3.5** Hiển thị feedback chi tiết khi sai ✅ (30/01/2026)

#### 1.4 Daily Goal UseCase
- [x] **1.4.1** Tạo file `get_daily_goal_usecase.dart` ✅ (đã có sẵn: get_today_goal_usecase.dart)
- [x] **1.4.2** Tạo file `update_daily_goal_usecase.dart` ✅ (đã có sẵn: set_daily_goal_usecase.dart)
- [x] **1.4.3** Uncomment registration trong `user_di.dart` ✅ (đã được đăng ký)
- [x] **1.4.4** Update `UserProvider` với daily goal methods ✅ (đã có sẵn)
- [ ] **1.4.5** Test flow cập nhật goal từ Profile screen

#### 1.5 Firebase Configuration
- [ ] **1.5.1** Tạo file `firebase_options.dart` với FlutterFire CLI
- [ ] **1.5.2** Uncomment Firebase initialization trong `main.dart`
- [ ] **1.5.3** Test Firebase Auth flow
- [ ] **1.5.4** Test Firebase Messaging (notifications)
- [ ] **1.5.5** Verify Firestore connection

---

### 🟠 Nhóm 2: Voice Learning Module (Ưu tiên: CAO - High Impact)

#### 2.1 Voice Service Core
- [ ] **2.1.1** Tạo folder structure `features/voice/`
  ```
  voice/
  ├── data/
  │   ├── datasources/
  │   │   └── voice_remote_datasource.dart
  │   └── repositories/
  │       └── voice_repository_impl.dart
  ├── domain/
  │   ├── entities/
  │   │   ├── transcription.dart
  │   │   └── audio_synthesis.dart
  │   ├── repositories/
  │   │   └── voice_repository.dart
  │   └── usecases/
  │       ├── transcribe_audio_usecase.dart
  │       └── synthesize_speech_usecase.dart
  ├── presentation/
  │   ├── providers/
  │   │   └── voice_provider.dart
  │   ├── screens/
  │   │   └── voice_practice_screen.dart
  │   └── widgets/
  │       ├── audio_waveform.dart
  │       ├── record_button.dart
  │       └── playback_controls.dart
  └── di/
      └── voice_di.dart
  ```
- [ ] **2.1.2** Thêm dependencies: `record`, `just_audio`, `permission_handler`
- [ ] **2.1.3** Implement `VoiceRemoteDataSource` gọi `/stt/transcribe` và `/tts/synthesize`

#### 2.2 Speech-to-Text (STT)
- [ ] **2.2.1** Tạo `TranscribeAudioUseCase`
- [ ] **2.2.2** Handle microphone permissions (iOS/Android)
- [ ] **2.2.3** Implement audio recording với `record` package
- [ ] **2.2.4** Upload audio file lên API
- [ ] **2.2.5** Parse transcription response
- [ ] **2.2.6** Hiển thị realtime transcription text

#### 2.3 Text-to-Speech (TTS)
- [ ] **2.3.1** Tạo `SynthesizeSpeechUseCase`
- [ ] **2.3.2** Cache audio files locally
- [ ] **2.3.3** Implement playback với `just_audio`
- [ ] **2.3.4** Add speed controls (0.5x, 1x, 1.5x)
- [ ] **2.3.5** Tích hợp vào Vocabulary cards (tap to pronounce)

#### 2.4 Pronunciation Practice Screen
- [ ] **2.4.1** Tạo `VoicePracticeScreen` UI
- [ ] **2.4.2** Hiển thị từ/câu cần đọc
- [ ] **2.4.3** Record user pronunciation
- [ ] **2.4.4** So sánh với native pronunciation
- [ ] **2.4.5** Tích hợp AI Orchestrator để đánh giá
- [ ] **2.4.6** Hiển thị pronunciation score (0-100)
- [ ] **2.4.7** Highlight lỗi phát âm cụ thể

#### 2.5 Voice Chat Integration
- [ ] **2.5.1** Add voice input button vào ChatPage
- [ ] **2.5.2** Record và transcribe user speech
- [ ] **2.5.3** Send text to AI chat
- [ ] **2.5.4** TTS response từ AI
- [ ] **2.5.5** Toggle voice/text mode

---

### 🟡 Nhóm 3: Gamification System (Ưu tiên: TRUNG BÌNH)

#### 3.1 Streak System
- [ ] **3.1.1** Implement streak calculation trong `backend-service/app/services/gamification.py`
- [ ] **3.1.2** Tạo API endpoint `GET /gamification/streak`
- [ ] **3.1.3** Tạo `GetStreakUseCase` trong Flutter
- [ ] **3.1.4** Update `ProgressProvider` với streak data
- [ ] **3.1.5** Animate streak counter trên Home screen
- [ ] **3.1.6** Add streak freeze feature (1 ngày nghỉ)

#### 3.2 Achievements/Badges
- [ ] **3.2.1** Design achievement types:
  - First Lesson Completed
  - 7-Day Streak
  - 30-Day Streak
  - 100 Words Mastered
  - Perfect Quiz Score
  - Voice Practice Champion
  - etc.
- [ ] **3.2.2** Tạo `Achievement` model trong backend
- [ ] **3.2.3** Tạo Alembic migration cho achievements table
- [ ] **3.2.4** Implement achievement unlock logic
- [ ] **3.2.5** Tạo `features/achievements/` module Flutter
- [ ] **3.2.6** Build `AchievementsScreen` với grid badges
- [ ] **3.2.7** Add unlock notification với confetti animation

#### 3.3 Leaderboard
- [ ] **3.3.1** Tạo API endpoint `GET /gamification/leaderboard`
- [ ] **3.3.2** Tạo `LeaderboardEntry` model
- [ ] **3.3.3** Implement weekly/monthly/all-time filters
- [ ] **3.3.4** Tạo `LeaderboardScreen` trong Flutter
- [ ] **3.3.5** Highlight current user position
- [ ] **3.3.6** Add friend filtering (optional)

#### 3.4 Daily Challenges
- [ ] **3.4.1** Design challenge types:
  - Learn X new words
  - Review Y flashcards
  - Complete Z minutes of practice
  - Get perfect score on quiz
  - Practice pronunciation
- [ ] **3.4.2** Tạo `DailyChallenge` model backend
- [ ] **3.4.3** Implement challenge generation logic
- [ ] **3.4.4** Tạo API endpoints CRUD challenges
- [ ] **3.4.5** Tạo `DailyChallengesWidget` cho Home screen
- [ ] **3.4.6** Track challenge progress realtime
- [ ] **3.4.7** Award bonus XP on completion

#### 3.5 XP & Level System Enhancement
- [ ] **3.5.1** Define XP curve cho levels
- [ ] **3.5.2** Add level badges/icons
- [ ] **3.5.3** Create level-up animation
- [ ] **3.5.4** Show XP gain popup sau mỗi activity
- [ ] **3.5.5** Add XP history/breakdown

---

### 🔵 Nhóm 4: Advanced Learning Features (Ưu tiên: TRUNG BÌNH)

#### 4.1 Grammar Practice Module
- [ ] **4.1.1** Tạo `features/grammar/` folder structure
- [ ] **4.1.2** Tạo `GenerateGrammarExerciseUseCase` gọi `/cag/grammar`
- [ ] **4.1.3** Build `GrammarPracticeScreen`
- [ ] **4.1.4** Implement fill-in-blank exercise UI
- [ ] **4.1.5** Implement sentence reordering UI
- [ ] **4.1.6** Add grammar explanation cards
- [ ] **4.1.7** Track grammar progress separately

#### 4.2 Writing Practice Module
- [ ] **4.2.1** Tạo `features/writing/` folder structure
- [ ] **4.2.2** Tạo `GenerateWritingPromptUseCase` gọi `/cag/writing`
- [ ] **4.2.3** Build `WritingPracticeScreen` với text editor
- [ ] **4.2.4** Implement word/character counter
- [ ] **4.2.5** Submit writing cho AI feedback
- [ ] **4.2.6** Display corrections với highlights
- [ ] **4.2.7** Save writing history

#### 4.3 Reading Comprehension Module
- [ ] **4.3.1** Tạo `features/reading/` folder structure
- [ ] **4.3.2** Tạo `GenerateReadingPassageUseCase` gọi `/cag/reading`
- [ ] **4.3.3** Build `ReadingScreen` với passage display
- [ ] **4.3.4** Add vocabulary highlighting (tap to see meaning)
- [ ] **4.3.5** Implement comprehension questions
- [ ] **4.3.6** Add read-aloud với TTS
- [ ] **4.3.7** Track reading speed/comprehension stats

#### 4.4 Conversation Practice
- [ ] **4.4.1** Tạo `GenerateConversationUseCase` gọi `/cag/conversation`
- [ ] **4.4.2** Build `ConversationPracticeScreen`
- [ ] **4.4.3** Implement role-play UI (User vs AI)
- [ ] **4.4.4** Add suggested responses
- [ ] **4.4.5** Integrate voice input/output
- [ ] **4.4.6** Score conversation naturalness

#### 4.5 Adaptive Learning
- [ ] **4.5.1** Fetch learner profile từ `/users/{id}/learning-pattern`
- [ ] **4.5.2** Analyze weak areas automatically
- [ ] **4.5.3** Suggest personalized lessons
- [ ] **4.5.4** Adjust difficulty dynamically
- [ ] **4.5.5** Show learning insights dashboard

---

### 🟢 Nhóm 5: UX Enhancements (Ưu tiên: TRUNG BÌNH)

#### 5.1 Onboarding Flow
- [ ] **5.1.1** Design 4-5 onboarding screens
- [ ] **5.1.2** Tạo `OnboardingScreen` với PageView
- [ ] **5.1.3** Add skip/next/done buttons
- [ ] **5.1.4** Language selection step
- [ ] **5.1.5** Level assessment mini-quiz
- [ ] **5.1.6** Daily goal setting
- [ ] **5.1.7** Store onboarding completion flag

#### 5.2 Skeleton Loading
- [x] **5.2.1** Tạo `SkeletonLoader` widget reusable ✅ (30/01/2026)
- [x] **5.2.2** Create skeleton variants: card, list, text ✅ (30/01/2026)
- [x] **5.2.3** Apply to Course list screen ✅ (30/01/2026)
- [x] **5.2.4** Apply to Vocabulary list screen ✅ (30/01/2026)
- [x] **5.2.5** Apply to Home screen sections ✅ (30/01/2026)
- [x] **5.2.6** Add shimmer animation ✅ (30/01/2026)

#### 5.3 Pull-to-Refresh
- [x] **5.3.1** Add RefreshIndicator to HomePageNew ✅ (đã có sẵn)
- [x] **5.3.2** Add RefreshIndicator to CourseListScreen ✅ (đã có sẵn)
- [x] **5.3.3** Add RefreshIndicator to VocabLibraryPage ✅ (đã có sẵn)
- [ ] **5.3.4** Add RefreshIndicator to NotificationsPage (cần backend)
- [x] **5.3.5** Implement proper refresh logic in providers ✅ (đã có sẵn)

#### 5.4 Empty States
- [x] **5.4.1** Design EmptyStateWidget với illustration ✅ (30/01/2026)
- [x] **5.4.2** Apply to empty course list ✅ (30/01/2026)
- [x] **5.4.3** Apply to empty vocabulary ✅ (30/01/2026)
- [ ] **5.4.4** Apply to empty notifications
- [ ] **5.4.5** Apply to empty chat history
- [x] **5.4.6** Add CTA button in empty states ✅ (30/01/2026)

#### 5.5 Error Handling UI
- [x] **5.5.1** Tạo `ErrorWidget` với retry button ✅ (30/01/2026)
- [x] **5.5.2** Design network error state ✅ (30/01/2026)
- [x] **5.5.3** Design server error state ✅ (30/01/2026)
- [x] **5.5.4** Design timeout error state ✅ (30/01/2026)
- [x] **5.5.5** Add offline mode indicator ✅ (30/01/2026)
- [ ] **5.5.6** Implement global error handler

#### 5.6 Dark Mode Polish
- [ ] **5.6.1** Review tất cả màu sắc trong dark mode
- [ ] **5.6.2** Fix contrast issues
- [ ] **5.6.3** Update card backgrounds
- [ ] **5.6.4** Update text colors
- [ ] **5.6.5** Test trên các screens
- [ ] **5.6.6** Add theme toggle trong Settings

---

### ⚪ Nhóm 6: Code Quality & Testing (Ongoing)

#### 6.1 Unit Tests
- [ ] **6.1.1** Setup test infrastructure
- [ ] **6.1.2** Write tests cho Use Cases
- [ ] **6.1.3** Write tests cho Repositories
- [ ] **6.1.4** Write tests cho Providers
- [ ] **6.1.5** Achieve 60%+ coverage

#### 6.2 Widget Tests
- [ ] **6.2.1** Test critical widgets
- [ ] **6.2.2** Test navigation flows
- [ ] **6.2.3** Test form validations

#### 6.3 Integration Tests
- [ ] **6.3.1** Test login → home flow
- [ ] **6.3.2** Test learning session flow
- [ ] **6.3.3** Test vocabulary review flow

#### 6.4 Code Refactoring
- [ ] **6.4.1** Remove duplicate code
- [ ] **6.4.2** Extract common widgets
- [ ] **6.4.3** Optimize imports
- [ ] **6.4.4** Add documentation comments
- [ ] **6.4.5** Follow Dart style guide

---

## 📅 Lộ Trình Đề Xuất

### Phase 1: Foundation (Tuần 1-2)
- Hoàn thành **Nhóm 1** (Tính năng dở dang)
- Hoàn thành **Nhóm 5.2-5.5** (UX cơ bản)

### Phase 2: Voice Learning (Tuần 3-4)
- Hoàn thành **Nhóm 2** (Voice Module)

### Phase 3: Engagement (Tuần 5-6)
- Hoàn thành **Nhóm 3** (Gamification)
- Hoàn thành **Nhóm 5.1** (Onboarding)

### Phase 4: Advanced (Tuần 7-8)
- Hoàn thành **Nhóm 4** (Advanced Learning)
- Hoàn thành **Nhóm 6** (Testing)

---

## 📝 Ghi Chú

### Files Quan Trọng Cần Chú Ý
- `flutter-app/lib/core/di/injection_container.dart` - DI registration
- `flutter-app/lib/core/startup/app_startup.dart` - App initialization
- `flutter-app/lib/core/network/api_client.dart` - API configuration
- `backend-service/app/routes/` - All API routes
- `ai-service/api/routes/` - AI API routes

### Conventions
- Mỗi feature folder theo cấu trúc: `data/`, `domain/`, `presentation/`, `di/`
- Use Cases trả về `Either<Failure, Success>` (dartz)
- Providers extend `ChangeNotifier`
- API calls qua Repository pattern

### Dependencies Cần Thêm
```yaml
# Voice features
record: ^5.0.0
just_audio: ^0.9.0
permission_handler: ^11.0.0

# Animations
shimmer: ^3.0.0
lottie: ^3.0.0

# Charts (for progress)
fl_chart: ^0.65.0
```

---

## 🏷️ Labels

- 🔴 **Ưu tiên CAO** - Cần hoàn thành ngay
- 🟠 **Ưu tiên CAO** - High impact features
- 🟡 **Ưu tiên TRUNG BÌNH** - Important nhưng không urgent
- 🔵 **Ưu tiên TRUNG BÌNH** - Nice to have
- 🟢 **Ưu tiên TRUNG BÌNH** - UX improvements
- ⚪ **Ongoing** - Luôn thực hiện song song

---

*Cập nhật lần cuối: 28/01/2026*
