# RPT-022 — Flutter App Architecture: Features, Providers & Navigation

> **Cập nhật:** 2026-04-24 | **Flutter Version:** 3.24+ | **Dart SDK:** ^3.8.1 | **App Version:** 0.4.0+4

---

## 1. Tổng Quan Flutter App

Flutter App (`flutter-app/`) là client đa nền tảng (iOS, Android, Web) của LexiLingo:
- **State Management**: Provider + GetIt (Dependency Injection)
- **Architecture**: Clean Architecture per feature (Domain/Data/Presentation)
- **API**: Dio-based custom ApiClient
- **Auth**: Firebase (Google + Facebook + Email)
- **Local DB**: SQLite (sqflite) + SharedPreferences
- **Voice**: record + just_audio + audio_service
- **i18n**: easy_localization (assets/i18n/)

---

## 2. App Entry Flow

```
main() async
├── EasyLocalization.ensureInitialized()
├── LocaleService.getSavedLocale()
├── databaseFactory = ffiWebNoWebWorker (web only)
├── dotenv.load(.env / .env.production)
├── Firebase.initializeApp()
├── LocalStateMigrationService().runIfNeeded()
├── di.initializeDependencies(skipDatabase: kIsWeb)
├── NotificationService.ensureInitialized()
├── StartupCoordinator.run() → health check backend /health (non-web)
└── runApp(EasyLocalization → LexiLingoApp)
```

**Post-render:**
```
WidgetsBinding.addPostFrameCallback:
└── FirebaseMessagingService.initialize()
    └── FCM permission + token registration
```

---

## 3. Provider Architecture

### 3.1 Toàn Bộ Providers

```dart
// File: flutter-app/lib/main.dart

MultiProvider([
    // Core
    AuthProvider, UserProvider, HomeProvider, ProfileProvider,
    
    // Learning
    ChatProvider, StoryProvider, CourseProvider, LearningProvider,
    ProgressProvider, VocabProvider, FlashcardProvider,
    
    // Voice
    VoiceProvider, SpeechRecognitionProvider, TtsSettingsProvider,
    
    // Progress & Gamification
    StreakProvider..loadStreak(),
    DailyChallengesProvider..loadChallenges(),
    AchievementProvider, GamificationProvider,
    
    // User & Settings
    NotificationProvider, LevelProvider, ProficiencyProvider,
    SettingsProvider, SocialProvider,
    
    // Phase 1: YouTube
    YouTubeProvider,
    
    // Phase 2: News
    NewsProvider,
    
    // Phase 3: Games + XP
    GamesProvider (skipXPLoad on web),
    
    // Phase 4: Podcast
    PodcastProvider (skipCurated on web),
    
    // Phase 5: Books
    BookProvider,
    
    // Phase 6: Lexi Chat
    LexiChatProvider,
])
```

### 3.2 Provider → Feature Mapping

| Provider | Feature | Backend/AI Connection |
|---------|---------|----------------------|
| `AuthProvider` | auth | Backend `/auth` + Firebase |
| `UserProvider` | user | Backend `/users` |
| `HomeProvider` | home | Aggregate data |
| `ProfileProvider` | profile | Backend `/users/me` |
| `CourseProvider` | course | Backend `/courses` |
| `LearningProvider` | learning | Backend `/learning` |
| `ProgressProvider` | progress | Backend `/progress` |
| `VocabProvider` | vocabulary | Backend `/vocabulary` |
| `FlashcardProvider` | vocabulary | Backend `/vocabulary/due` |
| `ChatProvider` | chat | AI Service `/chat` |
| `StoryProvider` | chat | AI Service `/topics` |
| `LexiChatProvider` | lexi_chat | AI Service `/lexi` |
| `VoiceProvider` | voice | AI Service `/ws` |
| `SpeechRecognitionProvider` | voice | AI Service `/stt` |
| `TtsSettingsProvider` | voice | AI Service `/tts` |
| `StreakProvider` | progress | Backend `/streak` |
| `DailyChallengesProvider` | progress | Backend `/challenges` |
| `AchievementProvider` | achievements | Backend `/achievements` |
| `GamificationProvider` | gamification | Backend `/gamification` |
| `LevelProvider` | level | Backend `/xp/profile` |
| `ProficiencyProvider` | level | Backend `/proficiency` |
| `NotificationProvider` | notifications | Firebase FCM |
| `SettingsProvider` | user | Backend `/preferences` |
| `SocialProvider` | social | Backend `/social` |
| `YouTubeProvider` | youtube | Backend `/youtube` |
| `NewsProvider` | news | Backend `/news` |
| `GamesProvider` | games | Backend `/games` |
| `PodcastProvider` | podcast | Backend `/podcasts` |
| `BookProvider` | books | Backend `/books` |

---

## 4. Feature Modules — Clean Architecture

Mỗi feature trong `lib/features/{feature}/` theo cấu trúc:

```
{feature}/
├── data/
│   ├── datasources/     → Remote (API) + Local (SQLite/SharedPrefs)
│   ├── models/          → JSON models + fromJson/toJson
│   └── repositories/    → Implementation của domain repositories
├── di/
│   └── {feature}_module.dart → GetIt registrations
├── domain/
│   ├── entities/        → Pure Dart entities (no dependencies)
│   ├── repositories/    → Abstract repository interfaces
│   └── usecases/        → Single-responsibility use cases
└── presentation/
    ├── pages/ hoặc screens/
    ├── providers/        → ChangeNotifier providers
    └── widgets/          → Feature-specific widgets
```

### 4.1 Feature: `auth`

```
auth/
├── data/
│   ├── datasources/
│   │   └── auth_backend_datasource.dart  → /auth endpoints
│   └── models/ → LoginResponse, RegisterRequest
├── domain/
│   ├── usecases/
│   │   ├── sign_in_with_google_usecase.dart
│   │   ├── sign_in_with_facebook_usecase.dart
│   │   └── sign_in_with_email_usecase.dart
└── presentation/
    ├── pages/
    │   ├── login_page.dart
    │   ├── register_page.dart
    │   └── reset_password_page.dart
    ├── providers/
    │   └── auth_provider.dart     → AuthState management
    └── widgets/
        └── auth_wrapper.dart     → Route guard
```

**Auth Flow:**
```
AuthWrapper
├── auth.isLoggedIn → HomeScreen
│
└── Not logged → LoginPage
    ├── Google Sign In → GoogleSignInService → Firebase → Backend /auth/google
    ├── Facebook Sign In → FacebookSignInService → Firebase → Backend /auth/facebook
    └── Email/Password → Backend /auth/login
```

### 4.2 Feature: `lexi_chat` (Phase 6 — Advanced)

```
lexi_chat/
├── presentation/
│   ├── pages/
│   │   └── lexi_chat_page.dart  → Main Lexi tutor interface
│   └── providers/
│       └── lexi_chat_provider.dart → Quản lý sessions, streaming
```

**Lexi Chat Flow:**
```
LexiChatPage
├── User types / speaks
├── LexiChatProvider.sendMessage(text)
│   └── AI Service POST /api/v1/lexi/chat
│       └── TRACECAG Pipeline
│           → SSE streaming response
├── Display streaming chunks
├── Show corrections sidebar
└── Show scores (grammar/fluency/overall)
```

### 4.3 Feature: `voice`

```
voice/
├── presentation/
│   ├── providers/
│   │   ├── voice_provider.dart          → WebSocket streaming voice
│   │   ├── tts_settings_provider.dart   → TTS config (voice, speed, pitch)
│   │   └── speech_recognition_provider.dart → STT control
└── (screens liên quan trong lexi_chat hoặc chat)
```

**Voice Call Flow:**
```
User presses mic
↓
SpeechRecognitionProvider.startListening()
├── record package → audio chunks
├── WebSocket → AI Service /ws/stream
├── VAD detection (server-side)
├── Partial transcript → display
└── Final response → TTS playback
```

---

## 5. Named Routes

```dart
// File: flutter-app/lib/main.dart

routes: {
    '/youtube'         → YouTubeExploreScreen
    '/youtube/player'  → YouTubePlayerScreen(video)
    '/news'            → NewsListScreen
    '/news/detail'     → NewsDetailScreen(article)
    '/news/quiz'       → NewsQuizScreen(article)
    '/games'           → GamesHubScreen
    '/podcast'         → PodcastExploreScreen
    '/podcast/detail'  → PodcastDetailScreen(podcast)
    '/podcast/player'  → PodcastPlayerScreen(episode, artworkUrl)
    '/books'           → BookLibraryScreen
    '/lexi'            → LexiChatPage
    '/reset-password'  → ResetPasswordPage(token)
}
```

---

## 6. Core Modules

### 6.1 Dependency Injection (`core/di/`)

```dart
// File: flutter-app/lib/core/di/injection_container.dart

GetIt sl = GetIt.instance;

initializeDependencies(skipDatabase: bool) async {
    // Core
    sl.registerSingleton<ApiClient>(...)
    sl.registerSingleton<HealthCheckService>(...)
    sl.registerSingleton<NotificationService>(...)
    
    // Auth
    sl.registerSingleton<GoogleSignInService>(...)
    sl.registerSingleton<FacebookSignInService>(...)
    
    // Features (via feature modules)
    await authModule.init(sl)
    await courseModule.init(sl)
    // ... 20+ modules
}
```

### 6.2 API Client (`core/network/`)

```dart
// File: flutter-app/lib/core/network/api_client.dart

ApiClient:
- Base URL: ApiConfig.baseUrl (from .env)
- AI URL:   ApiConfig.aiServiceUrl
- Interceptors:
  ├── AuthInterceptor → Add JWT Bearer token
  ├── RetryInterceptor → Retry on 401 (refresh token)
  └── LoggingInterceptor → Debug logging

ApiConfig (from .env):
- BACKEND_URL → http://localhost:8000
- AI_SERVICE_URL → http://localhost:8001
```

### 6.3 Theme (`core/theme/`)

```dart
// File: flutter-app/lib/core/theme/app_theme.dart

AppTheme.lightTheme → MaterialTheme (light)
AppTheme.darkTheme  → MaterialTheme (dark)

ThemeMode controlled by SettingsProvider.themeMode
Transition: Duration.zero (instant switch)
```

### 6.4 Localization (`core/l10n/`)

```
assets/i18n/
├── en.json    → English translations
├── vi.json    → Vietnamese translations
└── (others)

AppLocales.supportedLocales = [Locale('en'), Locale('vi'), ...]
AppLocales.fallback = Locale('en')

LocaleService:
- getSavedLocale()  → SharedPreferences
- updateAppLocale() → EasyLocalization.of(context).setLocale()
```

### 6.5 Local Database (`core/database/`)

```dart
// SQLite via sqflite (mobile) / sqflite_ffi_web (web)

Tables:
- vocab_items       → Cached vocabulary
- sync_queue        → Offline action queue
- (local learning state)

SyncQueueLifecycleRunner:
- Chạy khi app resume
- Flush pending actions → Backend
- Web: disabled (sqflite not supported)
```

### 6.6 AI Core (`core/ai/`)

```
core/ai/
- Gemini client (google_generative_ai)
- Local AI utilities
```

### 6.7 Services (`core/services/`)

| Service | Chức năng |
|---------|---------|
| `FirebaseMessagingService` | FCM token + message handling |
| `NotificationService` | Local notifications (flutter_local_notifications) |
| `HealthCheckService` | Ping backend /health |
| `LocaleService` | Locale management |
| `FacebookSignInService` | Facebook OAuth flow |
| `SyncQueueLifecycleRunner` | Offline sync queue |

---

## 7. Key Dependencies

### 7.1 UI/UX

| Package | Chức năng |
|---------|---------|
| `provider ^6.1.5` | State management |
| `google_fonts ^6.3.2` | Typography |
| `flutter_markdown ^0.7.4` | Markdown rendering |
| `lottie ^3.1.3` | Lottie animations |
| `shimmer ^3.0.0` | Loading skeleton |
| `confetti ^0.7.0` | Achievement confetti |
| `flutter_svg ^2.0.10` | SVG icons |
| `phosphor_flutter ^2.1.0` | Icon system |
| `cached_network_image ^3.4.1` | Image caching |

### 7.2 State & Infrastructure

| Package | Chức năng |
|---------|---------|
| `get_it ^8.0.3` | Dependency injection |
| `dartz ^0.10.1` | Functional programming (Either) |
| `equatable ^2.0.5` | Value equality |
| `uuid ^4.5.1` | UUID generation |
| `connectivity_plus` | Network status |
| `flutter_secure_storage` | Secure token storage |

### 7.3 Firebase & Auth

| Package | Chức năng |
|---------|---------|
| `firebase_core ^3.8.1` | Firebase foundation |
| `firebase_auth ^5.3.4` | Firebase authentication |
| `firebase_messaging ^15.1.5` | Push notifications |
| `cloud_firestore ^5.5.2` | Firestore (optional) |
| `google_sign_in ^6.2.1` | Google OAuth |
| `flutter_facebook_auth ^7.1.5` | Facebook OAuth |

### 7.4 Voice & Audio

| Package | Chức năng |
|---------|---------|
| `record ^5.2.1` | Audio recording |
| `just_audio ^0.9.46` | Audio playback |
| `audio_service ^0.18.16` | Background audio (podcast) |
| `permission_handler ^11.3.1` | Mic permissions |

### 7.5 Networking

| Package | Chức năng |
|---------|---------|
| `http ^1.6.0` | HTTP client |
| `flutter_dotenv ^6.0.0` | .env file loading |

---

## 8. Platform Support

```yaml
# Supported Platforms
iOS         → yes (setup_ios.sh cho configuration)
Android     → yes
Web         → yes (sqflite_ffi_web, audio limitations)
macOS       → yes (macos/)
Linux       → yes (linux/)
Windows     → yes (windows/)
```

**Web-specific adaptations:**
- SQLite → sqflite_ffi_web (no web worker)
- XP Profile load → deferred (avoid blocking)
- Podcast curated load → deferred (AudioService not web)
- Backend health check → skipped on web

---

## 9. App Lifecycle & Sync

```dart
class _LexiLingoAppState extends State<LexiLingoApp>
    with WidgetsBindingObserver {

    // Khi app resume → sync offline queue
    didChangeAppLifecycleState(resumed) {
        _syncQueueRunner?.onAppResumed()
    }
}

SyncQueueLifecycleRunner:
- start() → periodic sync check
- onAppResumed() → immediate sync
- stop() → cleanup
```

---

## 10. Deep Link Handling

```dart
// Reset password via deep link
_extractResetTokenFromDeepLink() {
    // Check query params: ?token=xxx
    Uri.base.queryParameters['token']
    
    // Check fragment: #?token=xxx
    Uri.base.fragment → parse fragment URI
}

// Route: /reset-password
ResetPasswordPage(initialToken: token)
```

---

## 11. Cấu Trúc Thư Mục

```
flutter-app/
├── lib/
│   ├── main.dart                    → App entry, MultiProvider
│   ├── firebase_options.dart        → Firebase config
│   ├── core/
│   │   ├── ai/                      → Gemini client
│   │   ├── database/                → SQLite setup
│   │   ├── di/                      → GetIt injection_container.dart
│   │   ├── error/                   → Failure types
│   │   ├── l10n/                    → Localization
│   │   ├── network/                 → ApiClient, ApiConfig
│   │   ├── services/                → Firebase, Health, Notifications
│   │   ├── startup/                 → StartupCoordinator, tasks
│   │   ├── theme/                   → AppTheme (light/dark)
│   │   ├── usecase/                 → BaseUseCase abstract
│   │   ├── utils/                   → AppLogger, helpers
│   │   └── widgets/                 → Shared widgets (SkeletonLoading, etc.)
│   └── features/
│       ├── achievements/
│       ├── auth/
│       ├── books/
│       ├── chat/
│       ├── course/
│       ├── games/
│       ├── gamification/
│       ├── home/
│       ├── learning/
│       ├── level/
│       ├── lexi_chat/
│       ├── news/
│       ├── notifications/
│       ├── podcast/
│       ├── profile/
│       ├── progress/
│       ├── social/
│       ├── user/
│       ├── vocabulary/
│       ├── voice/
│       └── youtube/
├── assets/
│   ├── i18n/          → Translation files
│   ├── badges/        → Achievement badges
│   ├── background-roadmap/
│   └── logo/
├── animation/         → Lottie animation files
├── android/
├── ios/
├── web/
├── pubspec.yaml
└── setup_ios.sh
```

---

*Tham khảo: [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md) | [RPT-004](RPT-004_FLUTTER_USER_FLOW_AND_NAVIGATION.md)*
