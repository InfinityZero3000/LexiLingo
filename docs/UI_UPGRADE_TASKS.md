# 📋 LexiLingo UI/Feature Upgrade - Task Tracker

## Quick Reference

### 🎯 Priority Legend
- **P0** - Critical (Must have)
- **P1** - High (Should have)
- **P2** - Medium (Nice to have)

### 📊 Status Legend
- ⬜ Not Started
- 🔄 In Progress
- ✅ Completed
- ❌ Blocked

---

## EPIC 1: 🏠 Nâng Cấp Trang Chủ (Home Page)

### Task 1.1: Cải thiện Header với User Data thực
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.1.1 | Lấy user data từ UserProvider thay vì mock | ✅ | | Đã dùng AuthProvider.currentUser |
| 1.1.2 | Hiển thị avatar thực từ user profile | ✅ | | Đã hiển thị user.avatarUrl |
| 1.1.3 | Thêm tap handler notification icon | ✅ | | Navigate tới NotificationsPage |

### Task 1.2: Tích hợp Enrolled Courses thực
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.2.1 | Thêm `getEnrolledCourses` usecase | ✅ | | API `/courses/enrolled` đã tạo |
| 1.2.2 | Load enrolled courses trong `loadHomeData()` | ✅ | | Flutter repository đã update |
| 1.2.3 | Hiển thị "Continue Learning" section | ✅ | | UI đã có data thực |

### Task 1.3: Week Progress từ Backend
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.3.1 | Tạo API endpoint `/api/progress/weekly` | ✅ | | DailyActivity model, /progress/weekly endpoint |
| 1.3.2 | Tạo `getWeeklyProgress` usecase | ✅ | | GetWeeklyProgressUseCase full stack |
| 1.3.3 | Cập nhật `weekProgress` getter | ✅ | | HomeProvider tích hợp weekly progress |

### Task 1.4: UI Polish & Animations
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.4.1 | Hero animations cho course cards | ✅ | | Hero widget cho course card và detail |
| 1.4.2 | Staggered animations khi load | ✅ | | AnimatedListItem for home/course pages |
| 1.4.3 | Pull-to-refresh custom animation | ✅ | | RefreshIndicator đã có |
| 1.4.4 | Shimmer loading effects cải thiện | ✅ | | Shimmer đã implement |

---

## EPIC 2: 📚 Bố Trí Lại Trang Khóa Học

### Task 2.1: Tạo Course Category Entity
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.1.1 | Define `CourseCategoryEntity` | ✅ | | course_category_entity.dart |
| 2.1.2 | Tạo `course_category_model.dart` | ✅ | | Model với JSON serialization |

### Task 2.2: Backend - API Categories
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.2.1 | Tạo `CourseCategory` model | ✅ | | course_category.py |
| 2.2.2 | Tạo endpoint `GET /api/v1/categories` | ✅ | | course_categories.py router |
| 2.2.3 | Group courses by category | ✅ | | GET /categories/{id}/courses |
| 2.2.4 | Tạo migration script | ✅ | | add_course_categories.py |

### Task 2.3: Course Repository - Fetch by Category
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.3.1 | Thêm method `getCoursesByCategory()` | ✅ | | Repository đã update |
| 2.3.2 | Thêm method `getCategories()` | ✅ | | Repository đã update |
| 2.3.3 | Cache categories locally | ✅ | | SharedPreferences cache 1h expiry |

### Task 2.4: Redesign Course List Screen ⭐ KEY
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.4.1 | Thay ListView sang Column với Sections | ✅ | | Category-based layout |
| 2.4.2 | Section với tiêu đề + horizontal ListView | ✅ | | Horizontal scrolling |
| 2.4.3 | Tạo `CourseCategorySection` widget | ✅ | | _CategorySection widget |
| 2.4.4 | Tạo `HorizontalCourseCard` widget | ✅ | | _HorizontalCourseCard widget |
| 2.4.5 | "See All" button cho mỗi category | ✅ | | Navigates to CategoryDetailScreen |

### Task 2.5: Tạo Category Detail Screen
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.5.1 | Screen hiển thị all courses của category | ✅ | | CategoryDetailScreen với SliverAppBar |
| 2.5.2 | Grid/List view toggle | ✅ | | _isGridView toggle với SliverGrid |
| 2.5.3 | Sort options | ✅ | | CourseSortOption enum, sort dropdown |

---

## EPIC 3: 🔔 Trang Thông Báo Real-time

### Task 3.1: Notification Domain Layer
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.1.1 | Tạo `NotificationEntity` | ✅ | | notification_entity.dart đầy đủ |
| 3.1.2 | Tạo `NotificationRepository` interface | ✅ | | notification_repository.dart |
| 3.1.3 | Tạo usecases | ✅ | | notification_usecases.dart (7 usecases) |

### Task 3.2: Notification Data Layer
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.2.1 | Local data source với SQLite/Hive | ✅ | | SharedPreferences impl |
| 3.2.2 | Remote data source (Firebase FCM) | ✅ | | FCM integrated |
| 3.2.3 | Repository implementation | ✅ | | notification_repository_impl.dart |

### Task 3.3: Notification Provider
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.3.1 | State management cho notifications | ✅ | | NotificationProvider |
| 3.3.2 | Unread count tracking | ✅ | | hasUnread, unreadCount |
| 3.3.3 | Real-time listener | ✅ | | Stream subscription |
| 3.3.4 | Background notification handling | ✅ | | FCM background handler |

### Task 3.4: Redesign Notifications Page ⭐ KEY
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.4.1 | Kết nối NotificationProvider | ✅ | | Consumer pattern |
| 3.4.2 | Dynamic notification list | ✅ | | ListView.builder |
| 3.4.3 | Swipe-to-delete gesture | ✅ | | Dismissible widget |
| 3.4.4 | Pull-to-refresh | ✅ | | RefreshIndicator |
| 3.4.5 | Empty state UI | ✅ | | _buildEmptyState() |
| 3.4.6 | "Mark all as read" hoạt động | ✅ | | markAllAsRead() |

### Task 3.5: Notification Badge
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.5.1 | Badge với unread count | ✅ | | Badge in AppBar |
| 3.5.2 | Animate khi có notification mới | ✅ | | PulseAnimation widget |

---

## EPIC 4: 👤 Trang Hồ Sơ với Thông Tin Thực

### Task 4.1: User Profile Data Integration
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.1.1 | Full user profile từ UserProvider | ✅ | | AuthProvider.currentUser |
| 4.1.2 | Display name thực | ✅ | | user.displayName |
| 4.1.3 | Avatar từ user | ✅ | | user.avatarUrl với fallback |
| 4.1.4 | Member since từ `joinDate` | ✅ | | user.createdAt với _formatMemberSince() |

### Task 4.2: Learning Stats từ Backend
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.2.1 | API `GET /api/users/me/stats` | ✅ | | users.py router |
| 4.2.2 | Response schema | ✅ | | level.py - UserStatsResponse |
| 4.2.3 | `UserStatsEntity` và repository | ✅ | | Domain + Data layer complete |
| 4.2.4 | Replace hardcoded stats | ✅ | | ProfilePage uses ProfileProvider |

### Task 4.3: Weekly Activity Chart
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.3.1 | API `GET /api/users/me/weekly-activity` | ✅ | | users.py router |
| 4.3.2 | Response schema | ✅ | | level.py - WeeklyActivityResponse |
| 4.3.3 | Render chart với data thực | ✅ | | ProfilePage chart with real data |

### Task 4.4: Recent Badges từ Achievements
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.4.1 | Fetch user's unlocked achievements | ✅ | | AchievementProvider integration |
| 4.4.2 | Sort by `unlocked_at` DESC | ✅ | | Sorted in ProfilePage |
| 4.4.3 | Dynamic badge display | ✅ | | _buildRecentBadges() widget |

### Task 4.5: Edit Profile Screen
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.5.1 | Form: display name, avatar | ✅ | | updateUserProfile() |
| 4.5.2 | Language preferences | ✅ | | SettingsPage language selector |
| 4.5.3 | Daily goal setting | ✅ | | SettingsPage daily goal presets |
| 4.5.4 | API update profile | ✅ | | updateProfile endpoint |

---

## EPIC 5: 🎯 Hệ Thống Level với Thuật Toán

### Task 5.1: Level System Design & Entity
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.1.1 | Define `LevelEntity` | ✅ | | level_entity.dart (LevelTier, LevelStatus) |
| 5.1.2 | Define level tiers | ✅ | | LevelTiers class với A1-C2 |

**Level Tiers Reference:**
| Level | Name | Min XP | Max XP |
|-------|------|--------|--------|
| A1 | Beginner | 0 | 999 |
| A2 | Elementary | 1,000 | 2,999 |
| B1 | Intermediate | 3,000 | 6,999 |
| B2 | Upper Intermediate | 7,000 | 14,999 |
| C1 | Advanced | 15,000 | 29,999 |
| C2 | Mastery | 30,000+ | ∞ |

### Task 5.2: Level Calculation Algorithm ⭐ KEY
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.2.1 | `calculateLevel(int totalXP)` | ✅ | | LevelCalculator.getCurrentTier() |
| 5.2.2 | `calculateProgress(int totalXP)` | ✅ | | calculateLevelStatus() |
| 5.2.3 | `xpToNextLevel(int totalXP)` | ✅ | | Trong LevelStatus |
| 5.2.4 | Unit tests | ✅ | | level_calculator_test.dart |

### Task 5.3: Backend Level Endpoints
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.3.1 | Endpoint `GET /api/users/me/level` | ✅ | | users.py router |
| 5.3.2 | Response schema | ✅ | | level.py schemas |
| 5.3.3 | Auto-update level on XP change | ✅ | | POST /users/me/xp endpoint |

### Task 5.4: Level Provider & Integration
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.4.1 | State management cho level | ✅ | | LevelProvider |
| 5.4.2 | Listen to XP changes | ✅ | | updateLevel() từ AuthProvider |
| 5.4.3 | Level up animation | ✅ | | showLevelUpDialog flag |

### Task 5.5: UI Integration
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.5.1 | Profile: Level thực | ✅ | | LevelProgressCard |
| 5.5.2 | Profile: XP progress bar | ✅ | | LevelProgressBar |
| 5.5.3 | Home: Level badge | ✅ | | LevelProgressCard trên HomePage |
| 5.5.4 | Level Up celebration dialog | ✅ | | LevelUpDialog widget |

---

## 📊 Progress Summary

| Epic | Total Tasks | Completed | Progress |
|------|-------------|-----------|----------|
| EPIC 1: Home | 15 | 15 | 100% |
| EPIC 2: Courses | 16 | 16 | 100% |
| EPIC 3: Notifications | 15 | 15 | 100% |
| EPIC 4: Profile | 15 | 15 | 100% |
| EPIC 5: Level | 14 | 14 | 100% |
| **TOTAL** | **75** | **75** | **100%** |

---

## 📅 Sprint Planning

### Sprint 1 (Week 1-2) ✅ COMPLETED
**Goal**: Foundation - Domain layer & Backend APIs

| Task | Epic | Priority | Status |
### Sprint 1 (Week 1-2) ✅ COMPLETED
**Goal**: Foundation - Domain layer & Backend APIs

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 5.1-5.2 Level Design & Algorithm | EPIC 5 | P0 | ✅ |
| 3.1-3.2 Notification Domain & Data | EPIC 3 | P0 | ✅ |
| 2.1-2.2 Course Category Backend | EPIC 2 | P0 | ✅ |
| 4.1 User Profile Integration | EPIC 4 | P1 | ✅ |

### Sprint 2 (Week 3-4) ✅ COMPLETED
**Goal**: Core Features - Backend APIs & Main Integrations

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 2.2 Course Category API | EPIC 2 | P0 | ✅ |
| 3.3-3.4 Notification Provider & UI | EPIC 3 | P0 | ✅ |
| 5.3 Level Backend Endpoints | EPIC 5 | P0 | ✅ |
| 4.2-4.3 Profile Stats & Chart API | EPIC 4 | P1 | ✅ |
| 1.2.1 Enrolled Courses API | EPIC 1 | P1 | ✅ |

### Sprint 3 (Week 5-6) ✅ COMPLETED
**Goal**: Flutter Integration & UI Polish

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 2.3-2.4 Course List Redesign (Flutter) | EPIC 2 | P0 | ✅ |
| 1.2.2 Home Page - Enrolled Courses Integration | EPIC 1 | P1 | ✅ |
| 4.2.4 Profile - Stats Integration | EPIC 4 | P1 | ✅ |
| 4.3.3 Profile - Weekly Activity Chart | EPIC 4 | P1 | ✅ |
| 1.1-1.3 Home Page Real Data | EPIC 1 | P1 | ✅ |
| 2.5 Category Detail Screen | EPIC 2 | P2 | ✅ |
| 1.4 UI Animations | EPIC 1 | P2 | ✅ |
| 3.5 Notification Badge | EPIC 3 | P2 | ✅ |

### Sprint 4 (Week 7-8) ✅ COMPLETED
**Goal**: Final Polish & Remaining Features

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 4.4 Profile Badges Display | EPIC 4 | P1 | ✅ |
| 1.4 UI Animations Polish | EPIC 1 | P2 | ✅ |
| 3.5.2 Notification Badge Animation | EPIC 3 | P2 | ✅ |
| 2.3.3 Category Cache | EPIC 2 | P2 | ✅ |
| 1.3 Week Progress API | EPIC 1 | P2 | ✅ |

---

## 🎯 Next Steps (Sprint 3 Priorities)

### High Priority (Complete First)
1. **Course Categories Flutter Integration**
   - Create domain entities
   - Update repositories
   - Redesign courses page with category sections

2. **Home Page Data Integration**
   - Connect enrolled courses API
   - Update HomeProvider with real data
   - Test "Continue Learning" section

3. **Profile Stats Integration**
   - Create UserStats entity
   - Update UserRepository
   - Connect ProfilePage to stats API

### Medium Priority
- Category detail screen
- Weekly activity chart integration
- Achievement badges display

### Low Priority
- UI animations polish
- Notification badge animations

---

*Last Updated: 2026-02-01 (Verified)*
*🎉 ALL SPRINTS COMPLETED - 100% Overall Progress 🎉*

### ✅ Final Session Completed Tasks
- Task 1.4.2: Staggered animations with AnimatedListItem (home_page, course_list_screen, category_detail_screen)
- Task 2.5.2: Grid/List view toggle for CategoryDetailScreen
- Task 2.5.3: Sort options (newest, popular, alphabetical, level) 
- Task 4.5.2: Language preferences in SettingsPage (8 languages)
- Task 4.5.3: Daily goal setting with 5 presets (10-200 XP)
- Task 3.5.2: Notification badge bounce animation with PulseAnimation
- Task 4.4: Recent Badges display with AchievementProvider
- Task 2.3.3: Category local cache with SharedPreferences

### 📁 New Files Created
- `/features/user/presentation/providers/settings_provider.dart` - Settings state management
- `/features/user/presentation/pages/settings_page.dart` - Full settings UI

### 🔧 Key Implementations
1. **Staggered Animations**: AnimatedListItem widget with configurable delay per item
2. **Grid/List Toggle**: CategoryDetailScreen supports both views with smooth transition
3. **Course Sorting**: 4 sort options (newest, popular, alphabetical, level) with enum
4. **Settings Page**: Complete settings with language selector, daily goal presets, notifications, sound, theme
5. **Badge Animation**: PulseAnimation widget for notification badge bounce effect
