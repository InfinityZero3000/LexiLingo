# RPT-005 — Catalog Module Flutter

> **Cập nhật:** 2026-04-24

---

## 1. Mục Đích

Báo cáo này cung cấp danh mục module Flutter theo hướng phân ra theo `features/*`, giúp team xác định nhanh trách nhiệm từng khối code và flow nghiệp vụ liên quan.

---

## 2. Cấu Trúc Tổng Thể

Ứng dụng áp dụng cách tổ chức theo feature, mỗi feature có xu hướng tách thành:
- **`domain`**: entity, repository interface, usecase
- **`data`**: datasource, model, repository implementation
- **`presentation`**: page/screen/provider/widget

Cách tổ chức này phù hợp với **Clean Architecture + Provider**, giúp dễ test và dễ thay thế backend datasource.

---

## 3. Danh Mục Module Chính

### 3.1 Nhóm Truy Cập và Tài Khoản

| Module | Trách nhiệm | Màn hình chính |
|--------|------------|--------------|
| `features/auth` | Đăng nhập, đăng ký, reset password, onboarding | `LoginPage`, `RegisterPage`, `OnboardingPage` |
| `features/user` | Thông tin người dùng, settings, daily goal, streak | `SettingsPage` |
| `features/profile` | Profile page, edit profile, thống kê học | `ProfilePage`, `EditProfileScreen` |

### 3.2 Nhóm Học Tập Cốt Lõi

| Module | Trách nhiệm | Màn hình chính |
|--------|------------|--------------|
| `features/course` | Danh mục khóa học, danh sách khóa học, chi tiết | `CourseListScreen`, `CourseDetailScreen` |
| `features/learning` | Roadmap và lesson session | `LearningRoadmapScreen`, `LearningSessionScreen` |
| `features/progress` | Theo dõi quá trình học và thống kê tiến bộ | `MyProgressScreen` |
| `features/level` | Mô hình cấp độ/phân tích trình độ CEFR | — |

### 3.3 Nhóm AI và Hội Thoại

| Module | Trách nhiệm | Màn hình chính |
|--------|------------|--------------|
| `features/chat` | Topic/story chat, thông điệp, session | `StorySelectionPage`, `TopicChatPage` |
| `features/lexi_chat` | Luồng chat trợ lý Lexi (TRACECAG) | `LexiChatPage` |
| `features/voice` | Transcribe, pronunciation, speech synthesis | `VoicePracticeScreen` |

### 3.4 Nhóm Nội Dung Bổ Trợ

| Module | Trách nhiệm | Màn hình chính |
|--------|------------|--------------|
| `features/news` | Bản tin học tập và quiz | `NewsListScreen`, `NewsDetailScreen`, `NewsQuizScreen` |
| `features/podcast` | Podcast explore/detail/player | `PodcastExploreScreen`, `PodcastPlayerScreen` |
| `features/books` | Thư viện sách, đọc sách, quiz | `BookLibraryScreen`, `BookDetailScreen` |
| `features/youtube` | Explore và player nội dung video | `YouTubeExploreScreen`, `YouTubePlayerScreen` |
| `features/vocabulary` | Thư viện từ vựng, review flashcard | `FlashcardReviewScreen` |
| `features/games` | Mini game học từ vựng/ngữ pháp | `GamesHubScreen`, game screens |

### 3.5 Nhóm Động Lực và Xã Hội

| Module | Trách nhiệm | Màn hình chính |
|--------|------------|--------------|
| `features/gamification` | Wallet, shop, leaderboard | `WalletScreen`, `ShopScreen`, `LeaderboardScreen` |
| `features/achievements` | Badge, thành tích | `AchievementsScreen` |
| `features/social` | Kết nối bạn bè/chức năng xã hội | `SocialScreen` |
| `features/notifications` | Thông báo và nhắc học tập | — |

### 3.6 Nhóm Điều Hướng và Trang Chủ

| Module | Trách nhiệm | Màn hình chính |
|--------|------------|--------------|
| `features/home` | Main screen, home page, bottom navigation | `MainScreen`, `HomePageNew` |

---

## 4. Nhận Xét Kỹ Thuật

- Số lượng feature module đã phong phú, cho thấy sản phẩm đang ở giai đoạn MVP nâng cao.
- Nhiều module đã có đầy đủ 3 lớp domain/data/presentation, tạo nền tảng tốt cho bảo trì.
- Một số module có tên gần nhau (`chat` và `lexi_chat`) cần tiếp tục thống nhất quy ước tên để dễ onboarding developer mới.

**Phân biệt `chat` vs `lexi_chat`:**

| Module | Kết Nối | AI Engine |
|--------|---------|----------|
| `chat` | AI Service `/chat` + `/topics` | Basic LLM, topic-based |
| `lexi_chat` | AI Service `/lexi` | TRACECAG Pipeline (đầy đủ) |

---

## 5. Đề Xuất Quản Trị Module

- Áp dụng bảng ma trận "Feature → Owner → API → Test" để giảm rủi ro xung đột.
- Chuẩn hóa README ngắn cho từng feature lớn (`auth`, `course`, `learning`, `chat`, `voice`).
- Định kỳ audit route reachability để tránh màn hình mồ côi (unreachable screen).
- Theo dõi tỉ lệ coverage test theo từng module để ưu tiên viết test cho module quan trọng.

---

*Tham khảo: [RPT-003](RPT-003_FLUTTER_FEATURE_REPORT.md) | [RPT-004](RPT-004_FLUTTER_USER_FLOW_AND_NAVIGATION.md) | [RPT-022](RPT-022_FLUTTER_APP_ARCHITECTURE.md)*
