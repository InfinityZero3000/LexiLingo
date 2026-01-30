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
| 1.1.1 | Lấy user data từ UserProvider thay vì mock | ⬜ | | |
| 1.1.2 | Hiển thị avatar thực từ user profile | ⬜ | | |
| 1.1.3 | Thêm tap handler notification icon | ⬜ | | |

### Task 1.2: Tích hợp Enrolled Courses thực
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.2.1 | Thêm `getEnrolledCourses` usecase | ⬜ | | |
| 1.2.2 | Load enrolled courses trong `loadHomeData()` | ⬜ | | |
| 1.2.3 | Hiển thị "Continue Learning" section | ⬜ | | |

### Task 1.3: Week Progress từ Backend
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.3.1 | Tạo API endpoint `/api/progress/weekly` | ⬜ | | |
| 1.3.2 | Tạo `getWeeklyProgress` usecase | ⬜ | | |
| 1.3.3 | Cập nhật `weekProgress` getter | ⬜ | | |

### Task 1.4: UI Polish & Animations
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 1.4.1 | Hero animations cho course cards | ⬜ | | |
| 1.4.2 | Staggered animations khi load | ⬜ | | |
| 1.4.3 | Pull-to-refresh custom animation | ⬜ | | |
| 1.4.4 | Shimmer loading effects cải thiện | ⬜ | | |

---

## EPIC 2: 📚 Bố Trí Lại Trang Khóa Học

### Task 2.1: Tạo Course Category Entity
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.1.1 | Define `CourseCategoryEntity` | ⬜ | | |
| 2.1.2 | Tạo `course_category_model.dart` | ⬜ | | |

### Task 2.2: Backend - API Categories
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.2.1 | Tạo `CourseCategory` model | ⬜ | | |
| 2.2.2 | Tạo endpoint `GET /api/courses/categories` | ⬜ | | |
| 2.2.3 | Group courses by category | ⬜ | | |
| 2.2.4 | Tạo migration script | ⬜ | | |

### Task 2.3: Course Repository - Fetch by Category
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.3.1 | Thêm method `getCoursesByCategory()` | ⬜ | | |
| 2.3.2 | Thêm method `getCategories()` | ⬜ | | |
| 2.3.3 | Cache categories locally | ⬜ | | |

### Task 2.4: Redesign Course List Screen ⭐ KEY
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.4.1 | Thay ListView sang Column với Sections | ⬜ | | |
| 2.4.2 | Section với tiêu đề + horizontal ListView | ⬜ | | |
| 2.4.3 | Tạo `CourseCategorySection` widget | ⬜ | | |
| 2.4.4 | Tạo `HorizontalCourseCard` widget | ⬜ | | |
| 2.4.5 | "See All" button cho mỗi category | ⬜ | | |

### Task 2.5: Tạo Category Detail Screen
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 2.5.1 | Screen hiển thị all courses của category | ⬜ | | |
| 2.5.2 | Grid/List view toggle | ⬜ | | |
| 2.5.3 | Sort options | ⬜ | | |

---

## EPIC 3: 🔔 Trang Thông Báo Real-time

### Task 3.1: Notification Domain Layer
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.1.1 | Tạo `NotificationEntity` | ⬜ | | |
| 3.1.2 | Tạo `NotificationRepository` interface | ⬜ | | |
| 3.1.3 | Tạo usecases | ⬜ | | |

### Task 3.2: Notification Data Layer
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.2.1 | Local data source với SQLite/Hive | ⬜ | | |
| 3.2.2 | Remote data source (Firebase FCM) | ⬜ | | |
| 3.2.3 | Repository implementation | ⬜ | | |

### Task 3.3: Notification Provider
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.3.1 | State management cho notifications | ⬜ | | |
| 3.3.2 | Unread count tracking | ⬜ | | |
| 3.3.3 | Real-time listener | ⬜ | | |
| 3.3.4 | Background notification handling | ⬜ | | |

### Task 3.4: Redesign Notifications Page ⭐ KEY
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.4.1 | Kết nối NotificationProvider | ⬜ | | |
| 3.4.2 | Dynamic notification list | ⬜ | | |
| 3.4.3 | Swipe-to-delete gesture | ⬜ | | |
| 3.4.4 | Pull-to-refresh | ⬜ | | |
| 3.4.5 | Empty state UI | ⬜ | | |
| 3.4.6 | "Mark all as read" hoạt động | ⬜ | | |

### Task 3.5: Notification Badge
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 3.5.1 | Badge với unread count | ⬜ | | |
| 3.5.2 | Animate khi có notification mới | ⬜ | | |

---

## EPIC 4: 👤 Trang Hồ Sơ với Thông Tin Thực

### Task 4.1: User Profile Data Integration
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.1.1 | Full user profile từ UserProvider | ⬜ | | |
| 4.1.2 | Display name thực | ⬜ | | |
| 4.1.3 | Avatar từ user | ⬜ | | |
| 4.1.4 | Member since từ `joinDate` | ⬜ | | |

### Task 4.2: Learning Stats từ Backend
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.2.1 | API `GET /api/users/me/stats` | ⬜ | | |
| 4.2.2 | Response schema | ⬜ | | |
| 4.2.3 | `UserStatsEntity` và repository | ⬜ | | |
| 4.2.4 | Replace hardcoded stats | ⬜ | | |

### Task 4.3: Weekly Activity Chart
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.3.1 | API `GET /api/users/me/weekly-activity` | ⬜ | | |
| 4.3.2 | Response schema | ⬜ | | |
| 4.3.3 | Render chart với data thực | ⬜ | | |

### Task 4.4: Recent Badges từ Achievements
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.4.1 | Fetch user's unlocked achievements | ⬜ | | |
| 4.4.2 | Sort by `unlocked_at` DESC | ⬜ | | |
| 4.4.3 | Dynamic badge display | ⬜ | | |

### Task 4.5: Edit Profile Screen
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 4.5.1 | Form: display name, avatar | ⬜ | | |
| 4.5.2 | Language preferences | ⬜ | | |
| 4.5.3 | Daily goal setting | ⬜ | | |
| 4.5.4 | API update profile | ⬜ | | |

---

## EPIC 5: 🎯 Hệ Thống Level với Thuật Toán

### Task 5.1: Level System Design & Entity
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.1.1 | Define `LevelEntity` | ⬜ | | |
| 5.1.2 | Define level tiers | ⬜ | | |

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
| 5.2.1 | `calculateLevel(int totalXP)` | ⬜ | | |
| 5.2.2 | `calculateProgress(int totalXP)` | ⬜ | | |
| 5.2.3 | `xpToNextLevel(int totalXP)` | ⬜ | | |
| 5.2.4 | Unit tests | ⬜ | | |

### Task 5.3: Backend Level Endpoints
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.3.1 | Endpoint `GET /api/users/me/level` | ⬜ | | |
| 5.3.2 | Response schema | ⬜ | | |
| 5.3.3 | Auto-update level on XP change | ⬜ | | |

### Task 5.4: Level Provider & Integration
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.4.1 | State management cho level | ⬜ | | |
| 5.4.2 | Listen to XP changes | ⬜ | | |
| 5.4.3 | Level up animation | ⬜ | | |

### Task 5.5: UI Integration
| ID | Subtask | Status | Assignee | Notes |
|----|---------|--------|----------|-------|
| 5.5.1 | Profile: Level thực | ⬜ | | |
| 5.5.2 | Profile: XP progress bar | ⬜ | | |
| 5.5.3 | Home: Level badge | ⬜ | | |
| 5.5.4 | Level Up celebration dialog | ⬜ | | |

---

## 📊 Progress Summary

| Epic | Total Tasks | Completed | Progress |
|------|-------------|-----------|----------|
| EPIC 1: Home | 15 | 0 | 0% |
| EPIC 2: Courses | 16 | 0 | 0% |
| EPIC 3: Notifications | 15 | 0 | 0% |
| EPIC 4: Profile | 15 | 0 | 0% |
| EPIC 5: Level | 14 | 0 | 0% |
| **TOTAL** | **75** | **0** | **0%** |

---

## 📅 Sprint Planning

### Sprint 1 (Week 1-2)
**Goal**: Foundation - Domain layer & Backend APIs

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 5.1-5.2 Level Design & Algorithm | EPIC 5 | P0 | ⬜ |
| 3.1-3.2 Notification Domain & Data | EPIC 3 | P0 | ⬜ |
| 2.1-2.2 Course Category Backend | EPIC 2 | P0 | ⬜ |
| 4.1 User Profile Integration | EPIC 4 | P1 | ⬜ |

### Sprint 2 (Week 3-4)
**Goal**: Core Features - Main UI changes

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 2.3-2.4 Course List Redesign | EPIC 2 | P0 | ⬜ |
| 3.3-3.4 Notification Provider & UI | EPIC 3 | P0 | ⬜ |
| 5.3-5.5 Level Backend & Integration | EPIC 5 | P0 | ⬜ |
| 4.2-4.3 Profile Stats & Chart | EPIC 4 | P1 | ⬜ |

### Sprint 3 (Week 5-6)
**Goal**: Polish & Enhancement

| Task | Epic | Priority | Status |
|------|------|----------|--------|
| 1.1-1.3 Home Page Improvements | EPIC 1 | P1 | ⬜ |
| 4.4-4.5 Profile Badges & Edit | EPIC 4 | P1 | ⬜ |
| 2.5 Category Detail Screen | EPIC 2 | P2 | ⬜ |
| 1.4 UI Animations | EPIC 1 | P2 | ⬜ |
| 3.5 Notification Badge | EPIC 3 | P2 | ⬜ |

---

*Last Updated: 2026-01-30*
