# RPT-003 — Báo Cáo Tính Năng Flutter App

> **Cập nhật:** 2026-04-24

---

## 1. Mục Đích Báo Cáo

Tài liệu này mô tả đầy đủ các tính năng Flutter app theo góc nhìn chức năng và trải nghiệm người dùng. Nội dung được viết theo văn phong báo cáo: kết hợp đoạn văn mô tả dài với các danh sách mục để dễ truy vết.

---

## 2. Tổng Quan Phạm Vi Tính Năng

Flutter app của LexiLingo không chỉ là UI renderer mà là lớp điều phối trải nghiệm học tập. App phối hợp với `backend-service` và `ai-service` để tạo thành chu trình học: vào app → chọn nội dung → tương tác → nhận phản hồi → cập nhật tiến độ.

App được phát triển theo **6 phases** tích lũy:

| Phase | Tính Năng | Provider |
|-------|-----------|---------|
| Phase 1 | YouTube Video Integration | YouTubeProvider |
| Phase 2 | News Reading + Quiz | NewsProvider |
| Phase 3 | English Games + XP System | GamesProvider |
| Phase 4 | Podcast (Background Audio) | PodcastProvider |
| Phase 5 | Book Reading Library | BookProvider |
| Phase 6 | Lexi Chat (Story Adventure) | LexiChatProvider |

---

## 3. Hệ Thống Tính Năng Theo Hành Trình Người Dùng

### 3.1 Đăng Nhập và Khởi Tạo Phiên Học

Người dùng bắt đầu từ `AuthWrapper` flow với các màn hình welcome, login, register, reset password và onboarding. Mục tiêu là đưa người dùng vào `MainScreen` trong trạng thái đã xác thực.

**Thành phần chính:**
- `WelcomePage` — Màn hình chào lần đầu
- `LoginPage` — Đăng nhập Email/Google/Facebook
- `RegisterPage` — Tạo tài khoản mới
- `ResetPasswordPage` — Đặt lại mật khẩu qua token
- `OnboardingPage` — Khởi tạo mục tiêu học tập

### 3.2 Hub Điều Hướng Chính (Bottom Navigation)

Sau khi xác thực, `MainScreen` đóng vai trò hub trung tâm, gồm 5 tab chính:

| Tab | Màn Hình | Mục Đích |
|-----|---------|---------|
| Discovery | `HomePageNew` | Tổng hợp gợi ý nội dung, streak, XP |
| Learning | `CourseListScreen` | Danh sách khóa học theo cấp độ |
| Lexi | `LexiChatPage` | Trò chuyện với AI tutor (TRACECAG) |
| Chat | `StorySelectionPage` | Chat theo chủ đề |
| Account | `ProfilePage` | Hồ sơ, thành tích, cài đặt |

### 3.3 Nhóm Học Tập Có Cấu Trúc

Đây là trụ cột nghiệp vụ của ứng dụng, bao gồm:
- Danh sách khóa học và danh mục khóa học
- Chi tiết khóa học và lộ trình học
- Lộ trình học (Learning Roadmap)
- Phiên học bài (Learning Session)

**Giá trị nghiệp vụ:**
- Chuẩn hóa quá trình học theo cấp độ CEFR.
- Có thể đo được tiến độ và completion rate.
- Làm nền tảng cho đề xuất học tiếp theo từ AI.

### 3.4 Nhóm AI Chat và Luyện Giao Tiếp

Hệ thống chat được triển khai theo hai hướng:
- **`LexiChatPage`** — Tương tác nhanh, trợ lý AI liên tục qua TRACECAG Pipeline (phân tích ngữ pháp, sửa lỗi, CEFR scoring).
- **`StorySelectionPage` → `TopicChatPage`** — Học theo chủ đề có định hướng (business, travel, daily life...).

**Điểm mạnh:**
- Có định hướng theo chủ đề học tập.
- Kết hợp dữ liệu từ backend/ai-service để tạo phản hồi bối cảnh.
- Streaming response SSE cho trải nghiệm tức thì.

### 3.5 Nhóm Nội Dung Bổ Trợ và Luyện Tập

Ứng dụng cung cấp bộ nội dung đa kênh để tránh đơn điệu:

| Kênh | Màn Hình | Tính Năng |
|------|---------|---------|
| News | `NewsListScreen` → `NewsDetailScreen` → `NewsQuizScreen` | Đọc báo + quiz kiểm tra |
| Podcast | `PodcastExploreScreen` → `PodcastPlayerScreen` | Nghe background, lock screen controls |
| Books | `BookLibraryScreen` → `BookDetailScreen` | Thư viện sách điện tử |
| Games | `GamesHubScreen` → Game screens | Mini-game từ vựng/ngữ pháp |
| Vocabulary | `FlashcardReviewScreen` | Ôn tập theo SM-2 Spaced Repetition |
| Voice | `VoicePracticeScreen` | Luyện phát âm, thu âm, đánh giá HuBERT |
| YouTube | `YouTubeExploreScreen` → `YouTubePlayerScreen` | Xem video học tiếng Anh |

**Tác động đến trải nghiệm:**
- Tăng tần suất quay lại app (retention).
- Hỗ trợ học theo tình huống và theo sở thích cá nhân.
- Giữ cân bằng giữa học nghiêm túc và học tương tác.

### 3.6 Nhóm Gamification và Duy Trì Động Lực

Các tính năng wallet, shop, leaderboard, achievement, progress và social được thiết kế để duy trì nhiệt học:

| Tính Năng | Mô Tả |
|-----------|--------|
| **Wallet** | Quản lý xu/điểm thưởng (Gems) |
| **Shop** | Đổi quà/tùy chọn vật phẩm tăng sức mạnh |
| **Leaderboard** | So sánh với cộng đồng |
| **Achievements** | Ghi nhận cột mốc với 13 loại trigger |
| **Streak** | Chuỗi ngày học liên tiếp |
| **XP System** | Điểm kinh nghiệm theo cấp độ |
| **Social Screen** | Kết nối bạn bè |

---

## 4. Tính Năng Hỗ Trợ Vận Hành Người Dùng

Từ profile page, người dùng truy cập:
- Edit profile và avatar upload
- Settings (theme, ngôn ngữ UI, thông báo)
- Voice shortcut (mic trên app bar)
- Friends/Social networking
- My Progress (tổng hợp tiến độ học)

Nhóm chức năng này đảm bảo app không chỉ phục vụ học mà còn hỗ trợ quản trị tài khoản và thói quen sử dụng dài hạn.

---

## 5. Đánh Giá Mức Độ Đầy Đủ Hiện Tại

Dựa trên route map và danh mục screen đã wiring, bộ tính năng Flutter hiện tại đã đạt mức đầy đủ cho giai đoạn MVP mở rộng:

| Luồng | Trạng Thái |
|-------|-----------|
| Auth flow rõ ràng | ✅ Hoàn chỉnh |
| Học có cấu trúc | ✅ Hoàn chỉnh |
| Chat AI | ✅ Hoàn chỉnh (Basic + TRACECAG) |
| Content & Game hóa | ✅ Hoàn chỉnh |
| Quản lý tài khoản | ✅ Hoàn chỉnh |
| Voice luyện tập | ✅ Có — cần mở rộng |

---

## 6. Kiến Nghị Tài Liệu Tiếp Theo

Để tiếp tục nâng cao chất lượng báo cáo, nên bổ sung:
- Ma trận feature → API endpoint chi tiết.
- Ma trận feature → metric theo dõi (DAU, completion, retention).
- Bộ test case UAT cho từng luồng màn hình.

---

*Tham khảo: [RPT-004](RPT-004_FLUTTER_USER_FLOW_AND_NAVIGATION.md) | [RPT-022](RPT-022_FLUTTER_APP_ARCHITECTURE.md) | [RPT-018](RPT-018_FEATURE_ANALYSIS.md)*
