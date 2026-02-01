# 🎨 Phân Tích Giao Diện & Chức Năng Hệ Thống LexiLingo

## Mục Lục
1. [Tổng Quan Hệ Thống Hiện Tại](#1-tổng-quan-hệ-thống-hiện-tại)
2. [Phân Tích Từng Module](#2-phân-tích-từng-module)
3. [Danh Sách Task Phát Triển Chi Tiết](#3-danh-sách-task-phát-triển-chi-tiết)
4. [Lộ Trình Thực Hiện](#4-lộ-trình-thực-hiện)

---

## 1. Tổng Quan Hệ Thống Hiện Tại

### 1.1 Kiến Trúc Flutter App
```
flutter-app/lib/
├── core/                    # Core utilities, theme, widgets
├── features/
│   ├── home/               # Trang chủ
│   ├── course/             # Khóa học
│   ├── notifications/      # Thông báo
│   ├── profile/            # Hồ sơ người dùng
│   ├── progress/           # Tiến độ học tập
│   ├── user/               # Quản lý người dùng
│   ├── vocabulary/         # Từ vựng
│   ├── achievements/       # Thành tích
│   └── ...
└── main.dart
```

### 1.2 Backend Service (Python/FastAPI)
- **Models**: User, Course, Progress, Gamification
- **Routes**: Auth, Courses, Progress, Gamification, Health
- **Database**: PostgreSQL với SQLAlchemy ORM

---

## 2. Phân Tích Từng Module

### 2.1 📍 Trang Chủ (Home Page)

#### Trạng thái hiện tại:
| Component | Trạng thái | Vấn đề |
|-----------|------------|--------|
| Header | ✅ Có | Hiển thị avatar, XP, welcome message |
| Streak Card | ✅ Có | Tích hợp StreakProvider, hiển thị tuần |
| Daily XP Goal | ✅ Có | Hiển thị progress bar |
| Daily Challenges | ✅ Có | Widget challenges hàng ngày |
| Daily Review Card | ✅ Có | Ôn tập từ vựng |
| Continue Learning | ⚠️ Một phần | List enrolled courses (hiện tại trống) |
| Featured Courses | ✅ Có | Horizontal scroll list |
| Quick Actions | ✅ Có | AI Tutor, Vocabulary |

#### Cần cải thiện:
- [ ] **Enrolled courses chưa hoạt động** - `enrolledCourses` luôn trả về empty list
- [ ] **Week progress hardcoded** - Trả về `List.filled(7, false)`
- [ ] **User stats chưa đồng bộ real-time** với backend
- [ ] **UI/UX có thể hiện đại hơn** - thêm animations, gradients

---

### 2.2 📚 Trang Khóa Học (Course List)

#### Trạng thái hiện tại:
| Component | Trạng thái | Vấn đề |
|-----------|------------|--------|
| Layout | Vertical List | Cần đổi sang Horizontal theo chủ đề |
| Course Card | ✅ Có | Hiển thị đầy đủ thông tin |
| Filter | ✅ Có | Language, Level filters |
| Pagination | ✅ Có | Infinite scroll |

#### Vấn đề chính:
```dart
// course_list_screen.dart:79-91 - HIỆN TẠI: Vertical ListView
return ListView.builder(
  controller: _scrollController,
  padding: const EdgeInsets.all(16),
  itemCount: provider.courses.length + (provider.isLoadingCourses ? 1 : 0),
  itemBuilder: (context, index) {
    final course = provider.courses[index];
    return _CourseCard(course: course, ...);
  },
);
```

#### Yêu cầu mới:
```
Cấu trúc mới:
├── Category: "English for Business"
│   └── Horizontal ListView of courses
├── Category: "Daily Conversation"
│   └── Horizontal ListView of courses
├── Category: "Grammar Mastery"
│   └── Horizontal ListView of courses
└── ...
```

---

### 2.3 🔔 Trang Thông Báo (Notifications)

#### Trạng thái hiện tại:
| Component | Trạng thái | Vấn đề |
|-----------|------------|--------|
| Notification List | HARDCODED | Tất cả data đều static |
| Firebase FCM | ✅ Service có | Nhưng chưa kết nối UI |
| Mark as Read | Không hoạt động | Button không có logic |
| Real-time | Không có | Không nhận push real-time |

#### Code hiện tại (HARDCODED):
```dart
// notifications_page.dart:33-41
_buildNotificationItem(
  context,
  icon: Icons.schedule,
  iconColor: AppColors.primary,
  title: "Time for your AI Chat!",  // HARDCODED
  subtitle: "Your daily 5-minute conversation practice is ready.", // HARDCODED
  time: "2m ago", // HARDCODED
  isUnread: true,
),
```

#### Cần thêm:
- **NotificationProvider** để quản lý state
- **NotificationEntity** domain model
- **NotificationRepository** kết nối Firebase FCM
- **Local storage** cho notifications

---

### 2.4 👤 Trang Hồ Sơ (Profile)

#### Trạng thái hiện tại:
| Component | Trạng thái | Vấn đề |
|-----------|------------|--------|
| Avatar | ⚠️ Có | Fallback hardcoded URL |
| Display Name | ⚠️ Có | Fallback "Alex Johnson" |
| Level Display | HARDCODED | "B2 Upper Intermediate" |
| XP Progress | HARDCODED | "1,250 / 1,500 XP" |
| Learning Stats | HARDCODED | Streak, Words, AI Talk, Badges |
| Weekly Activity | HARDCODED | Chart data static |
| Recent Badges | HARDCODED | Fixed badges |

#### Code hiện tại (HARDCODED):
```dart
// profile_page.dart:74-78
Text(user?.displayName ?? 'Alex Johnson', ...), // Fallback hardcoded
const Text('B2 Upper Intermediate', ...),       // COMPLETELY HARDCODED
const Text('Member since Jan 2023', ...),       // HARDCODED

// profile_page.dart:96-100
Text('1,250 / 1,500 XP', ...),    // HARDCODED
LinearProgressIndicator(value: 0.75, ...), // HARDCODED
```

---

### 2.5 🎯 Hệ Thống Level

#### Trạng thái hiện tại:
| Component | Trạng thái |
|-----------|------------|
| Level trong User model | ✅ Có field `level` |
| XP tracking | ✅ Backend có |
| Level calculation | KHÔNG CÓ |
| Level progression | KHÔNG CÓ |

#### Backend User Model:
```python
# backend-service/app/models/user.py:38
level: Mapped[str] = mapped_column(String(20), default="beginner")  # A1, A2, B1, B2, C1, C2
```

#### Cần xây dựng:
- **Level System Entity** với thuật toán tính toán
- **XP thresholds** cho mỗi level
- **Level progression API**
- **Level badge display**

---

## 3. Danh Sách Task Phát Triển Chi Tiết

### 📋 EPIC 1: Nâng Cấp Trang Chủ (Home Page)

#### Task 1.1: Cải thiện Header với User Data thực
- **File**: `home_page.dart`, `home_provider.dart`
- **Subtasks**:
  - [ ] 1.1.1 Lấy user data từ UserProvider thay vì mock
  - [ ] 1.1.2 Hiển thị avatar thực từ user profile
  - [ ] 1.1.3 Thêm tap handler cho notification icon → navigate to NotificationsPage
- **Estimate**: 2h

#### Task 1.2: Tích hợp Enrolled Courses thực
- **Files**: `home_provider.dart`, `course_repository.dart`
- **Subtasks**:
  - [ ] 1.2.1 Thêm `getEnrolledCourses` usecase
  - [ ] 1.2.2 Load enrolled courses trong `loadHomeData()`
  - [ ] 1.2.3 Hiển thị "Continue Learning" section với data thực
- **Estimate**: 3h

#### Task 1.3: Week Progress từ Backend
- **Files**: `home_provider.dart`, `progress_repository.dart`
- **Subtasks**:
  - [ ] 1.3.1 Tạo API endpoint `/api/progress/weekly`
  - [ ] 1.3.2 Tạo `getWeeklyProgress` usecase
  - [ ] 1.3.3 Cập nhật `weekProgress` getter với data thực
- **Estimate**: 4h

#### Task 1.4: UI Polish & Animations
- **Files**: `home_page.dart`, various widgets
- **Subtasks**:
  - [ ] 1.4.1 Thêm Hero animations cho course cards
  - [ ] 1.4.2 Staggered animations khi load content
  - [ ] 1.4.3 Pull-to-refresh với custom animation
  - [ ] 1.4.4 Shimmer loading effects cải thiện
- **Estimate**: 4h

---

### 📋 EPIC 2: Bố Trí Lại Trang Khóa Học

#### Task 2.1: Tạo Course Category Entity
- **Files**: Tạo mới `course_category_entity.dart`
- **Subtasks**:
  - [ ] 2.1.1 Define `CourseCategoryEntity` với fields: id, name, description, icon, courses[]
  - [ ] 2.1.2 Tạo `course_category_model.dart` cho API response mapping
- **Estimate**: 1h

#### Task 2.2: Backend - API Categories
- **Files**: `backend-service/app/routes/courses.py`, models
- **Subtasks**:
  - [ ] 2.2.1 Tạo `CourseCategory` model trong database
  - [ ] 2.2.2 Tạo endpoint `GET /api/courses/categories`
  - [ ] 2.2.3 Group courses by category trong response
  - [ ] 2.2.4 Tạo migration script
- **Estimate**: 4h

#### Task 2.3: Course Repository - Fetch by Category
- **Files**: `course_repository.dart`, `course_data_source.dart`
- **Subtasks**:
  - [ ] 2.3.1 Thêm method `getCoursesByCategory()`
  - [ ] 2.3.2 Thêm method `getCategories()`
  - [ ] 2.3.3 Cache categories locally
- **Estimate**: 2h

#### Task 2.4: Redesign Course List Screen
- **Files**: `course_list_screen.dart`
- **Subtasks**:
  - [ ] 2.4.1 Thay đổi từ ListView sang Column với Sections
  - [ ] 2.4.2 Mỗi section có tiêu đề category + horizontal ListView
  - [ ] 2.4.3 Tạo `CourseCategorySection` widget
  - [ ] 2.4.4 Tạo `HorizontalCourseCard` widget (compact version)
  - [ ] 2.4.5 Thêm "See All" button cho mỗi category
- **Estimate**: 6h

#### Task 2.5: Tạo Category Detail Screen
- **Files**: Tạo mới `category_courses_screen.dart`
- **Subtasks**:
  - [ ] 2.5.1 Screen hiển thị tất cả courses của 1 category
  - [ ] 2.5.2 Grid/List view toggle
  - [ ] 2.5.3 Sort options (popularity, newest, XP)
- **Estimate**: 3h

---

### 📋 EPIC 3: Trang Thông Báo Real-time

#### Task 3.1: Notification Domain Layer
- **Files**: Tạo structure trong `features/notifications/`
- **Subtasks**:
  - [ ] 3.1.1 Tạo `NotificationEntity` với fields: id, type, title, body, timestamp, isRead, data
  - [ ] 3.1.2 Tạo `NotificationRepository` interface
  - [ ] 3.1.3 Tạo usecases: `GetNotifications`, `MarkAsRead`, `MarkAllAsRead`, `DeleteNotification`
- **Estimate**: 2h

#### Task 3.2: Notification Data Layer
- **Files**: `notification_data_source.dart`, `notification_model.dart`
- **Subtasks**:
  - [ ] 3.2.1 Local data source với SQLite/Hive storage
  - [ ] 3.2.2 Remote data source kết nối Firebase FCM
  - [ ] 3.2.3 Repository implementation với sync logic
- **Estimate**: 4h

#### Task 3.3: Notification Provider
- **Files**: Tạo `notification_provider.dart`
- **Subtasks**:
  - [ ] 3.3.1 State management cho notifications list
  - [ ] 3.3.2 Unread count tracking
  - [ ] 3.3.3 Real-time listener từ FirebaseMessagingService
  - [ ] 3.3.4 Background notification handling
- **Estimate**: 3h

#### Task 3.4: Redesign Notifications Page
- **Files**: `notifications_page.dart`
- **Subtasks**:
  - [ ] 3.4.1 Kết nối NotificationProvider
  - [ ] 3.4.2 Dynamic notification list từ provider
  - [ ] 3.4.3 Swipe-to-delete gesture
  - [ ] 3.4.4 Pull-to-refresh
  - [ ] 3.4.5 Empty state khi không có notifications
  - [ ] 3.4.6 "Mark all as read" hoạt động thực
- **Estimate**: 4h

#### Task 3.5: Notification Badge trên Bottom Nav
- **Files**: `main.dart` hoặc navigation widget
- **Subtasks**:
  - [ ] 3.5.1 Hiển thị badge với unread count
  - [ ] 3.5.2 Animate khi có notification mới
- **Estimate**: 1h

---

### 📋 EPIC 4: Trang Hồ Sơ với Thông Tin Thực

#### Task 4.1: User Profile Data Integration
- **Files**: `profile_page.dart`, `user_provider.dart`
- **Subtasks**:
  - [ ] 4.1.1 Lấy full user profile từ UserProvider
  - [ ] 4.1.2 Display name thực (không fallback hardcoded)
  - [ ] 4.1.3 Avatar từ user hoặc generated placeholder
  - [ ] 4.1.4 Member since date từ `user.joinDate`
- **Estimate**: 2h

#### Task 4.2: Learning Stats từ Backend
- **Files**: `profile_page.dart`, tạo `user_stats_provider.dart`
- **Subtasks**:
  - [ ] 4.2.1 Tạo API endpoint `GET /api/users/me/stats`
  - [ ] 4.2.2 Response: streak, totalWords, aiTalkMinutes, badgesCount
  - [ ] 4.2.3 Tạo `UserStatsEntity` và repository
  - [ ] 4.2.4 Thay thế hardcoded stats trong Profile
- **Estimate**: 4h

#### Task 4.3: Weekly Activity Chart từ Backend
- **Files**: `profile_page.dart`, backend routes
- **Subtasks**:
  - [ ] 4.3.1 API endpoint `GET /api/users/me/weekly-activity`
  - [ ] 4.3.2 Response: array 7 ngày với XP/minutes học
  - [ ] 4.3.3 Render chart với data thực
- **Estimate**: 3h

#### Task 4.4: Recent Badges từ Achievements
- **Files**: `profile_page.dart`, `achievements_provider.dart`
- **Subtasks**:
  - [ ] 4.4.1 Fetch user's unlocked achievements
  - [ ] 4.4.2 Sort by `unlocked_at` DESC, limit 4
  - [ ] 4.4.3 Dynamic badge icons/colors từ achievement data
- **Estimate**: 2h

#### Task 4.5: Edit Profile Screen
- **Files**: Tạo mới `edit_profile_screen.dart`
- **Subtasks**:
  - [ ] 4.5.1 Form: display name, avatar upload
  - [ ] 4.5.2 Language preferences
  - [ ] 4.5.3 Daily goal setting
  - [ ] 4.5.4 API update profile
- **Estimate**: 4h

---

### 📋 EPIC 5: Hệ Thống Level với Thuật Toán

#### Task 5.1: Level System Design & Entity
- **Files**: Tạo `features/level/` hoặc trong `progress/`
- **Subtasks**:
  - [ ] 5.1.1 Define `LevelEntity`: level code, name, minXP, maxXP, badge, color
  - [ ] 5.1.2 Define level tiers (xem bảng dưới)
- **Estimate**: 1h

##### Bảng Level System:
| Level | Tên | Min XP | Max XP | Badge |
|-------|-----|--------|--------|-------|
| A1 | Beginner | 0 | 999 | 🌱 |
| A2 | Elementary | 1,000 | 2,999 | 🌿 |
| B1 | Intermediate | 3,000 | 6,999 | 🌳 |
| B2 | Upper Intermediate | 7,000 | 14,999 | 🌲 |
| C1 | Advanced | 15,000 | 29,999 | ⭐ |
| C2 | Mastery | 30,000+ | ∞ | 👑 |

#### Task 5.2: Level Calculation Algorithm
- **Files**: `level_service.dart` hoặc `level_calculator.dart`
- **Subtasks**:
  - [ ] 5.2.1 Function `calculateLevel(int totalXP) → LevelEntity`
  - [ ] 5.2.2 Function `calculateProgress(int totalXP) → double` (0.0 - 1.0)
  - [ ] 5.2.3 Function `xpToNextLevel(int totalXP) → int`
  - [ ] 5.2.4 Unit tests cho calculations
- **Estimate**: 2h

```dart
// Thuật toán đề xuất
class LevelCalculator {
  static const List<LevelTier> tiers = [
    LevelTier('A1', 'Beginner', 0, 999),
    LevelTier('A2', 'Elementary', 1000, 2999),
    LevelTier('B1', 'Intermediate', 3000, 6999),
    LevelTier('B2', 'Upper Intermediate', 7000, 14999),
    LevelTier('C1', 'Advanced', 15000, 29999),
    LevelTier('C2', 'Mastery', 30000, null),
  ];

  static LevelTier getCurrentLevel(int totalXP) {
    for (final tier in tiers.reversed) {
      if (totalXP >= tier.minXP) return tier;
    }
    return tiers.first;
  }

  static double getProgressInLevel(int totalXP) {
    final current = getCurrentLevel(totalXP);
    if (current.maxXP == null) return 1.0; // Max level
    
    final xpInLevel = totalXP - current.minXP;
    final levelRange = current.maxXP! - current.minXP;
    return (xpInLevel / levelRange).clamp(0.0, 1.0);
  }

  static int xpToNextLevel(int totalXP) {
    final current = getCurrentLevel(totalXP);
    if (current.maxXP == null) return 0; // Max level
    return current.maxXP! - totalXP + 1;
  }
}
```

#### Task 5.3: Backend Level Endpoints
- **Files**: `backend-service/app/routes/users.py`
- **Subtasks**:
  - [ ] 5.3.1 Endpoint `GET /api/users/me/level`
  - [ ] 5.3.2 Response: currentLevel, progress, xpToNext, totalXP
  - [ ] 5.3.3 Auto-update level khi XP thay đổi
- **Estimate**: 2h

#### Task 5.4: Level Provider & Integration
- **Files**: Tạo `level_provider.dart`
- **Subtasks**:
  - [ ] 5.4.1 State management cho level data
  - [ ] 5.4.2 Listen to XP changes
  - [ ] 5.4.3 Level up animation/notification
- **Estimate**: 2h

#### Task 5.5: UI Integration
- **Files**: `profile_page.dart`, `home_page.dart`
- **Subtasks**:
  - [ ] 5.5.1 Profile: Replace hardcoded "B2 Upper Intermediate" với level thực
  - [ ] 5.5.2 Profile: XP progress bar với actual values
  - [ ] 5.5.3 Home: Show level badge next to user name
  - [ ] 5.5.4 Level Up celebration dialog
- **Estimate**: 3h

---

## 4. Lộ Trình Thực Hiện

### Sprint 1 (Tuần 1-2): Foundation
| Priority | Task | Estimate |
|----------|------|----------|
| P0 | 5.1-5.2 Level System Design & Algorithm | 3h |
| P0 | 3.1-3.2 Notification Domain & Data Layer | 6h |
| P0 | 2.1-2.2 Course Category Backend | 5h |
| P1 | 4.1 User Profile Data Integration | 2h |

### Sprint 2 (Tuần 3-4): Core Features
| Priority | Task | Estimate |
|----------|------|----------|
| P0 | 2.3-2.4 Course List Redesign | 8h |
| P0 | 3.3-3.4 Notification Provider & UI | 7h |
| P0 | 5.3-5.5 Level Backend & Integration | 7h |
| P1 | 4.2-4.3 Profile Stats & Chart | 7h |

### Sprint 3 (Tuần 5-6): Polish & Enhancement
| Priority | Task | Estimate |
|----------|------|----------|
| P1 | 1.1-1.3 Home Page Improvements | 9h |
| P1 | 4.4-4.5 Profile Badges & Edit | 6h |
| P2 | 2.5 Category Detail Screen | 3h |
| P2 | 1.4 UI Polish & Animations | 4h |
| P2 | 3.5 Notification Badge | 1h |

---

## Tổng Kết

### Effort Summary:
| Epic | Total Hours |
|------|-------------|
| EPIC 1: Home Page | ~13h |
| EPIC 2: Course List | ~16h |
| EPIC 3: Notifications | ~14h |
| EPIC 4: Profile | ~15h |
| EPIC 5: Level System | ~10h |
| **TOTAL** | **~68h** |

### Files Cần Tạo Mới:
1. `features/notifications/domain/entities/notification_entity.dart`
2. `features/notifications/domain/repositories/notification_repository.dart`
3. `features/notifications/data/datasources/notification_data_source.dart`
4. `features/notifications/presentation/providers/notification_provider.dart`
5. `features/course/domain/entities/course_category_entity.dart`
6. `features/course/presentation/screens/category_courses_screen.dart`
7. `features/course/presentation/widgets/horizontal_course_card.dart`
8. `features/course/presentation/widgets/course_category_section.dart`
9. `features/level/domain/entities/level_entity.dart`
10. `features/level/services/level_calculator.dart`
11. `features/level/presentation/providers/level_provider.dart`
12. `features/profile/presentation/pages/edit_profile_screen.dart`
13. `features/user/presentation/providers/user_stats_provider.dart`

### Backend Endpoints Cần Tạo:
1. `GET /api/courses/categories`
2. `GET /api/users/me/stats`
3. `GET /api/users/me/weekly-activity`
4. `GET /api/users/me/level`
5. `GET /api/progress/weekly`

---

*Document created: 2026-01-30*
*Author: LexiLingo Development Team*
