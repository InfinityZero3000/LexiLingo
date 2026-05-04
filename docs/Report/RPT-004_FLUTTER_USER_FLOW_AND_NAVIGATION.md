# RPT-004 — Bản Đồ Luồng Người Dùng và Điều Hướng Flutter

> **Cập nhật:** 2026-04-24 | **Phạm vi:** Kiểm tra navigation toàn bộ `flutter-app/lib`

---

## 1. Luồng Khởi Động Ứng Dụng

**Entry point chính:**
- App root: [flutter-app/lib/main.dart](../../flutter-app/lib/main.dart)
- `home` trỏ đến `AuthWrapper`

**Auth wrapper flow:**
- File: [flutter-app/lib/features/auth/presentation/widgets/auth_wrapper.dart](../../flutter-app/lib/features/auth/presentation/widgets/auth_wrapper.dart)
- Chưa xác thực:
  - `WelcomePage` (lần đầu dùng app — kiểm tra local flag)
  - `LoginPage`
  - `RegisterPage`
- Đã xác thực:
  - `OnboardingPage` (nếu chưa hoàn thành onboarding)
  - `MainScreen` (luồng bình thường sau đăng nhập)

---

## 2. Hub Điều Hướng Chính (Bottom Navigation)

**File host:** [flutter-app/lib/features/home/presentation/pages/main_screen.dart](../../flutter-app/lib/features/home/presentation/pages/main_screen.dart)

**Các tab theo thứ tự:**

| Index | Màn Hình | Tab Name |
|-------|---------|---------|
| 0 | `HomePageNew` | Discovery |
| 1 | `CourseListScreen` | Learning |
| 2 | `LexiChatPage` | Lexi |
| 3 | `StorySelectionPage` | Chat |
| 4 | `ProfilePage` | Account |

---

## 3. Named Routes (MaterialApp)

Bảng routes được khai báo trong: [flutter-app/lib/main.dart](../../flutter-app/lib/main.dart)

| Route | Màn Hình | Tham số |
|-------|---------|--------|
| `/youtube` | `YouTubeExploreScreen` | — |
| `/youtube/player` | `YouTubePlayerScreen` | video object |
| `/news` | `NewsListScreen` | — |
| `/news/detail` | `NewsDetailScreen` | article object |
| `/news/quiz` | `NewsQuizScreen` | article object |
| `/games` | `GamesHubScreen` | — |
| `/podcast` | `PodcastExploreScreen` | — |
| `/podcast/detail` | `PodcastDetailScreen` | podcast object |
| `/podcast/player` | `PodcastPlayerScreen` | episode, artworkUrl |
| `/books` | `BookLibraryScreen` | — |
| `/lexi` | `LexiChatPage` | — |
| `/reset-password` | `ResetPasswordPage` | token (query param / fragment) |

---

## 4. Các Trang Đã Được Wiring (Xác Nhận Có Thể Truy Cập)

Các trang dưới đây được wired qua tab navigation, named routes, hoặc `Navigator.push(...)` từ các màn hình có thể truy cập.

### 4.1 Auth và Tài Khoản
- `WelcomePage`, `LoginPage`, `RegisterPage`, `OnboardingPage` — qua `AuthWrapper`
- `ResetPasswordPage` — qua route `/reset-password` (hỗ trợ deep link từ email)
- `EditProfileScreen` — từ `ProfilePage`
- `SettingsPage` — từ `ProfilePage`
- `VoicePracticeScreen` — từ mic shortcut trên app bar của `ProfilePage`

### 4.2 Social và Gamification
- `SocialScreen` — từ `ProfilePage` quick action "Friends"
- `ShopScreen` — từ `ProfilePage`
- `LeaderboardScreen` — từ `ProfilePage`
- `WalletScreen` — từ `ProfilePage` và `HomePageNew`
- `AchievementsScreen` — từ `ProfilePage`
- `MyProgressScreen` — từ `ProfilePage` quick action "Progress"

### 4.3 Learning và Chat

| Luồng | Màn Hình |
|-------|---------|
| Học có cấu trúc | `CourseListScreen` → `CategoryDetailScreen` → `CourseDetailScreen` → `LearningRoadmapScreen` → `LearningSessionScreen` |
| Chat theo chủ đề | `StorySelectionPage` → `TopicChatPage` |
| Lexi AI | `LexiChatPage` (tab + `/lexi`) |

### 4.4 Các Module Nội Dung

| Module | Luồng Màn Hình |
|--------|---------------|
| News | `NewsListScreen` → `NewsDetailScreen` → `NewsQuizScreen` |
| Games | `GamesHubScreen` → game screens → `GameResultScreen` |
| Podcast | `PodcastExploreScreen` → `PodcastDetailScreen` → `PodcastPlayerScreen` |
| Books | `BookLibraryScreen` → `BookDetailScreen` |
| Vocabulary | `FlashcardReviewScreen` → `SessionCompleteScreen` |
| YouTube | `YouTubeExploreScreen` → `YouTubePlayerScreen` |

---

## 5. Các Trang Hiện Không Wired (Tiềm Năng Không Truy Cập Được)

Không có trang nào được ghi nhận là không thể truy cập trong tập đã kiểm tra.

**Các hành động sửa gần đây:**
- Đã xóa `PlacementTestScreen` vì chưa được wiring.
- Đã wire `MyProgressScreen` từ `ProfilePage` quick actions.
- Đã wire `VoicePracticeScreen` từ mic shortcut trên app bar của `ProfilePage`.

> **Lưu ý:** "Tiềm năng không truy cập được" có nghĩa là hiện tại chưa được wiring trong navigation path. Có thể vẫn được dự định cho công việc trong tương lai.

---

## 6. Checklist Xác Minh Thủ Công Nhanh

Chạy app và kiểm tra:
1. Đăng nhập → đổ vào `MainScreen`.
2. Mở tab Account → tap "Friends" → mở `SocialScreen`.
3. Từ Discovery, mở ít nhất một trang sâu (Wallet hoặc Course detail).
4. Mở từng named route feature từ UI entry tương ứng: News, Games, Podcast, Books.
5. Xác nhận quick action "Progress" mở `MyProgressScreen`.
6. Xác nhận mic shortcut trên app bar mở `VoicePracticeScreen`.

---

## 7. Quy Tắc Bảo Trì Navigation

Khi thêm trang/màn hình mới:
1. Thêm route wiring (tab, named route, hoặc push từ trang có thể truy cập).
2. Thêm một dòng trong tài liệu này ở mục 4.
3. Nếu trang tạm thời/thử nghiệm, ghi nhận ở mục 5 kèm lý do.

---

*Tham khảo: [RPT-003](RPT-003_FLUTTER_FEATURE_REPORT.md) | [RPT-022](RPT-022_FLUTTER_APP_ARCHITECTURE.md)*
