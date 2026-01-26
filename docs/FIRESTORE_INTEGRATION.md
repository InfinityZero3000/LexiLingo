# Firestore Integration Guide

## Tổng quan

LexiLingo sử dụng **Hybrid Storage Architecture**:
- **SQLite**: Local storage cho offline access, fast queries, course content cache
- **Firestore**: Cloud sync cho user data, chat history, cross-device progress

## Kiến trúc

```
┌─────────────────────────────────────────────────────────────┐
│                         App Layer                            │
├─────────────────────────────────────────────────────────────┤
│  Repositories (UserRepository, ChatRepository)              │
│  ↓ Write both / Read local first (Offline-First)           │
├─────────────────┬───────────────────────────────────────────┤
│  Local Layer    │           Cloud Layer                      │
│  (SQLite)       │           (Firestore)                     │
├─────────────────┼───────────────────────────────────────────┤
│ UserLocalDS     │  UserFirestoreDS                          │
│ ChatLocalDS     │  ChatFirestoreDS                          │
│ CourseLocalDS   │  ProgressFirestoreDS                      │
└─────────────────┴───────────────────────────────────────────┘
         ↑                        ↑
         │                        │
    DatabaseHelper         FirestoreService
    (SQLite v3)          (Cloud Firestore)
```

## Các Service đã implement

### 1. FirestoreService (Core)
**Location**: `/lib/core/services/firestore_service.dart`

**Chức năng**:
- Singleton wrapper cho Firestore instance
- Quản lý collections và subcollections
- Batch operations và transactions
- Connection health check

**Usage**:
```dart
final firestoreService = FirestoreService.instance;

// Get user document reference
final userDoc = firestoreService.getUserDocument(userId);

// Get subcollections
final enrollments = firestoreService.getUserEnrollments(userId);
final chatSessions = firestoreService.getUserChatSessions(userId);
```

### 2. UserFirestoreDataSource
**Location**: `/lib/features/user/data/datasources/user_firestore_data_source.dart`

**Methods**:
- `getUser(userId)`: Get user profile from cloud
- `createUser(user)`: Create new user in Firestore
- `updateUser(user)`: Update user profile
- `updateUserStats(...)`: Update XP, streaks, stats
- `getSettings(userId)`: Get user settings
- `updateSettings(settings)`: Update settings
- `watchUser(userId)`: Real-time stream of user updates

**Firestore Structure**:
```
users/{userId}
├── name: string
├── email: string
├── avatarUrl: string?
├── joinDate: timestamp
├── lastLoginDate: timestamp?
├── totalXP: number
├── currentStreak: number
├── longestStreak: number
├── totalLessonsCompleted: number
├── totalWordsLearned: number
├── settings: {
│   ├── notificationEnabled: boolean
│   ├── notificationTime: string
│   ├── theme: string
│   ├── language: string
│   ├── soundEnabled: boolean
│   └── dailyGoalXP: number
│   }
├── createdAt: serverTimestamp
└── updatedAt: serverTimestamp
```

### 3. ChatFirestoreDataSource
**Location**: `/lib/features/chat/data/datasources/chat_firestore_data_source.dart`

**Methods**:
- `saveMessage(userId, sessionId, message)`: Backup chat message
- `getSessionHistory(userId, sessionId)`: Load session messages
- `getUserSessions(userId)`: List all sessions
- `createSession(userId, sessionId, title)`: Initialize new session
- `watchSessionMessages(userId, sessionId)`: Real-time chat stream

**Firestore Structure**:
```
users/{userId}/chatSessions/{sessionId}
├── title: string
├── createdAt: serverTimestamp
├── lastMessageAt: serverTimestamp
├── messageCount: number
└── messages/{messageId}
    ├── content: string
    ├── isUser: boolean
    ├── timestamp: string
    └── createdAt: serverTimestamp
```

### 4. ProgressFirestoreDataSource
**Location**: `/lib/core/services/progress_firestore_data_source.dart`

**Methods**:
- `syncDailyGoal(userId, goal)`: Backup daily goal progress
- `getDailyGoal(userId, date)`: Retrieve goal for specific date
- `syncEnrollment(userId, enrollment)`: Sync course enrollment
- `getUserEnrollments(userId)`: Get all enrollments

**Firestore Structure**:
```
users/{userId}/dailyGoals/{YYYY-MM-DD}
├── date: string
├── targetXP: number
├── earnedXP: number
├── lessonsCompleted: number
├── wordsLearned: number
├── minutesSpent: number
└── updatedAt: serverTimestamp

users/{userId}/enrollments/{courseId}
├── courseId: number
├── enrolledAt: timestamp
├── lastAccessedAt: timestamp?
├── completedAt: timestamp?
├── currentProgress: number (0-100)
└── updatedAt: serverTimestamp
```

### 5. ProgressSyncService
**Location**: `/lib/core/services/progress_sync_service.dart`

**Chức năng**: Background sync service giữa SQLite và Firestore

**Methods**:
- `isOnline()`: Check Firestore connectivity
- `syncUserProfile()`: Push local → cloud
- `syncUserStats()`: Push stats → cloud
- `pullUserData()`: Pull cloud → local with merge logic
- `fullSync()`: Bi-directional sync
- `startPeriodicSync()`: Auto-sync every 5 minutes
- `forceSyncNow()`: Manual immediate sync

**Merge Strategy**:
```dart
// When pulling from cloud, keep higher values
totalXP = max(cloud.totalXP, local.totalXP)
currentStreak = max(cloud.currentStreak, local.currentStreak)
longestStreak = max(cloud.longestStreak, local.longestStreak)
```

## Repository Updates

### UserRepositoryImpl
**Strategy**: Offline-First với Cloud Sync

**Read Flow**:
```
1. Try local SQLite first (fast)
2. If not found AND online → Try Firestore
3. If found in Firestore → Cache to local
4. Return data
```

**Write Flow**:
```
1. Write to local SQLite immediately (offline support)
2. Try write to Firestore (best-effort)
3. If Firestore fails → Queued for retry by ProgressSyncService
```

### ChatRepositoryImpl
**3 Data Sources**:
- `aiDataSource`: Gemini AI (generate responses)
- `localDataSource`: SQLite (offline cache)
- `firestoreDataSource`: Cloud backup (cross-device history)

## Dependency Injection

**Updated**: `/lib/core/di/injection_container.dart`

**New Registrations**:
```dart
// Core services
sl.registerLazySingleton<FirestoreService>(() => FirestoreService.instance);

// Firestore data sources
sl.registerLazySingleton<UserFirestoreDataSource>(
  () => UserFirestoreDataSourceImpl(firestoreService: sl()),
);
sl.registerLazySingleton<ChatFirestoreDataSource>(
  () => ChatFirestoreDataSourceImpl(firestoreService: sl()),
);
sl.registerLazySingleton<ProgressFirestoreDataSource>(
  () => ProgressFirestoreDataSourceImpl(firestoreService: sl()),
);

// Repositories with cloud support
sl.registerLazySingleton<UserRepository>(
  () => UserRepositoryImpl(
    localDataSource: sl(),
    firestoreDataSource: sl(), // ← NEW
  ),
);

// Sync service
sl.registerLazySingleton<ProgressSyncService>(
  () => ProgressSyncService(
    userLocalDataSource: sl(),
    userFirestoreDataSource: sl(),
    progressFirestoreDataSource: sl(),
    firestoreService: sl(),
  ),
);
```

## Cách sử dụng

### 1. Sync ngay khi login
```dart
// In auth_provider.dart after successful login
final syncService = sl<ProgressSyncService>();
await syncService.fullSync(); // Pull cloud data to this device
```

### 2. Auto-sync trong background
```dart
// In main.dart after authentication
if (user != null) {
  final syncService = sl<ProgressSyncService>();
  syncService.startPeriodicSync(); // Sync every 5 minutes
}
```

### 3. Manual force sync
```dart
// In settings page or refresh button
final syncService = sl<ProgressSyncService>();
await syncService.forceSyncNow();
```

### 4. Real-time user updates
```dart
// Watch for cloud changes
final firestoreDataSource = sl<UserFirestoreDataSource>();
firestoreDataSource.watchUser(userId).listen((user) {
  if (user != null) {
    // Update UI with cloud data
    userProvider.updateFromCloud(user);
  }
});
```

## Benefits của Hybrid Architecture

### 1. Offline-First
- App hoạt động ngay cả khi mất mạng
- SQLite đảm bảo performance cao
- User experience không bị gián đoạn

### 2. Cross-Device Sync
- Login trên thiết bị mới → progress được restore
- Real-time sync giữa devices
- Không mất data khi đổi phone

### 3. Cloud Backup
- User data an toàn trên cloud
- Có thể recover nếu xóa app
- Chat history được lưu lâu dài

### 4. Scalable
- Firestore scale tự động
- Support millions of users
- Real-time features (leaderboard, multiplayer)

## Next Steps

1. Tất cả services đã được implement
2. DI container đã cập nhật
3. Repositories support hybrid storage
4. ⏳ Config Firebase Security Rules (xem `FIRESTORE_SECURITY_RULES.md`)
5. ⏳ Test sync logic with multiple devices
6. ⏳ Implement sync UI indicator (loading spinner)
7. ⏳ Add retry mechanism for failed syncs

## Troubleshooting

### Issue: "User not found in Firestore"
- User chưa được create trong Firestore
- Fix: Call `createUser()` sau khi signup thành công

### Issue: "Permission Denied"
- Firebase Auth chưa config đúng
- Firestore rules chưa publish
- Fix: Check `FIRESTORE_SECURITY_RULES.md`

### Issue: "Sync quá chậm"
- Network connection yếu
- Quá nhiều data sync cùng lúc
- Fix: Implement pagination, sync theo batches

### Issue: "Conflict giữa local và cloud"
- Merge strategy: Keep higher values
- Future: Implement last-write-wins or custom conflict resolution
