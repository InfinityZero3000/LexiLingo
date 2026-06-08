# RPT-002 — Tổng Quan Chức Năng Dự Án LexiLingo

> **Cập nhật:** 2026-04-24 | **Phiên bản:** 1.0

---

## 1. Tổng Quan Sản Phẩm

LexiLingo là nền tảng học tiếng Anh sử dụng AI, kết hợp giữa lộ trình học có cấu trúc và trải nghiệm luyện tập giao tiếp thời gian thực. Ứng dụng Flutter đóng vai trò client đa nền tảng (mobile + web), kết nối đến `backend-service` (quản lý dữ liệu học tập) và `ai-service` (phân tích ngôn ngữ, hội thoại AI, voice).

Mục tiêu của hệ thống không chỉ là "trả lời câu hỏi" mà là tạo chu trình học liên tục: người dùng đăng nhập → học bài → luyện tập → nhận phản hồi AI → được chấm tiến độ → quay lại với các đề xuất học tiếp theo.

---

## 2. Mục Tiêu Chức Năng Chính

- Hỗ trợ người học tiếp cận bài học theo cấp độ CEFR (A1 → C2).
- Cung cấp trợ lý AI để luyện hội thoại và sửa lỗi ngữ pháp/phát âm.
- Ghi nhận tiến độ học, streak, achievement để duy trì động lực.
- Hỗ trợ kênh nội dung đa dạng: khóa học, từ vựng, game, tin tức, podcast, sách, voice practice.
- Vận hành đa nền tảng bằng Flutter với kiến trúc dễ mở rộng.

---

## 3. Nhóm Người Dùng và Nhu Cầu

### 3.1 Người Học Mới Bắt Đầu (A1–A2)
- Cần onboarding rõ ràng, bài học dễ, giao diện gọn.
- Được nhắc nhở học tập qua push notification.
- Nhận giải thích bằng tiếng Việt khi gặp lỗi khó.

### 3.2 Người Học Đã Có Nền Tảng (B1–B2)
- Cần lộ trình theo mục tiêu, luyện nhanh theo chủ đề.
- Theo dõi thống kê tiến bộ và tự tối ưu cách học.
- Sử dụng Lexi Chat cho hội thoại AI nâng cao.

### 3.3 Người Học Cần Luyện Giao Tiếp (B2–C2)
- Cần hội thoại AI, đánh giá phát âm (HuBERT), và phản hồi theo lỗi sai cụ thể.
- Sử dụng voice streaming thời gian thực.
- Nhận báo cáo kỹ năng chi tiết (fluency, grammar, vocabulary).

---

## 4. Giá Trị Chức Năng Theo Nhóm

| Nhóm | Tính Năng |
|------|-----------|
| **Learning Core** | Khóa học, roadmap, session bài học, CEFR assessment |
| **AI Interaction** | Lexi Chat (TRACECAG), Topic Chat, phân tích hội thoại |
| **Practice Content** | Games, News, Podcast, Books, Vocabulary review |
| **Motivation Layer** | Wallet, Shop, Leaderboard, Achievement, Streak, XP |
| **Account & Safety** | Login (Email/Google/Facebook), Register, Reset password, Profile, Settings |

---

## 5. Luồng Người Dùng Điển Hình

```
Mở App
  └─ AuthWrapper
       ├─ Chưa đăng nhập → WelcomePage → LoginPage
       └─ Đã đăng nhập → MainScreen
            ├─ Tab 1: Discovery (HomePageNew)
            │    ├─ Xem streak, XP, progress tổng hợp
            │    └─ Gợi ý nội dung: course, news, podcast
            ├─ Tab 2: Learning (CourseListScreen)
            │    └─ Course → Lesson → LearningSession → Progress update
            ├─ Tab 3: Lexi (LexiChatPage — TRACECAG AI)
            │    └─ Chat → AI phân tích → Sửa lỗi → Cập nhật KG mastery
            ├─ Tab 4: Chat (StorySelectionPage → TopicChatPage)
            └─ Tab 5: Account (ProfilePage)
                 ├─ Achievements, Wallet, Leaderboard
                 └─ Settings, Profile edit
```

---

## 6. Định Hướng Vận Hành

Về mặt vận hành sản phẩm, Flutter app là điểm tiếp xúc trung tâm. Mọi thay đổi API, model AI, hoặc content pipeline đều phải được phản ánh vào luồng sử dụng trên app. Vì vậy, bộ báo cáo trong thư mục Report được sắp xếp theo thứ tự để đội phát triển có thể:

- Hiểu đúng nghiệp vụ từ góc nhìn người dùng.
- Truy vết luồng màn hình và navigation flow.
- Đối chiếu với module code theo feature.
- Chốt quy trình setup/triển khai an toàn.

---

## 7. Kết Luận Tổng Quan

Hệ thống hiện tại đã đạt mức "feature-rich" cho một ứng dụng học ngôn ngữ: vừa có học có cấu trúc, vừa có trải nghiệm AI tương tác, vừa có gamification và nội dung bổ trợ. Công việc tài liệu hóa theo mã flow giúp team nhìn được bức tranh tổng thể, xác định nhanh chỗ nào đã đầy đủ và chỗ nào cần bổ sung.

---

*Tham khảo: [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-022](RPT-022_FLUTTER_APP_ARCHITECTURE.md)*
