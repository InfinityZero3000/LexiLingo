# RPT-028 — Tích Hợp Nội Dung Thực Tế (News & YouTube)

> **Cập nhật:** 2026-04-24 | **Nguồn:** `backend-service/app/routes/news.py` (21KB), `backend-service/app/routes/youtube.py` (14KB)

---

## 1. Tổng Quan

Hệ thống học tập của LexiLingo không chỉ giới hạn ở các câu hỏi tạo sẵn mà hỗ trợ "Real-world Custom Content" thông qua tích hợp **NewsAPI/NewsData** và **YouTube Data API**.
Nội dung này được lấy về qua proxy của Backend (để giấu API Key và quản lý Quota), sau đó được AI phân tích và độ lại thành tài liệu học tập chuẩn CEFR.

---

## 2. API Proxy Caching & Quota Management

Do các 3rd-party API (Google, NewsAPI) có giới hạn Free-tier nghiêm ngặt, backend thiết lập cơ chế cache 3 lớp (Memory → Redis → PostgreSQL) và Quota Manager.

### 2.1 Caching Strategy
- **YouTube Search:** Cache Redis 6 giờ, Cache DB 12 giờ.
- **YouTube Captions:** Cache vĩnh viễn (do nội dung video không đổi).
- **News List:** Cache Redis 1 giờ.
- **News Full Content (Trafilatura):** Cache Redis 24 giờ.

### 2.2 Quota Near Limit Handling
Nếu Quota đạt 95% limit hàng ngày, backend sẽ trả về `429 Too Many Requests` sớm, hoặc chuyển sang Fallback API.

---

## 3. Hệ Thống News Reading

Endpoint: `/api/v1/news/*`

### 3.1 Nguồn Data
- **Primary:** `NewsAPI.org` (endpoints: `/everything`, `/top-headlines`).
- **Fallback:** `NewsData.io` (endpoint: `/news`).
- **Web Scraping:** Dùng thư viện `trafilatura` (chạy qua Async Executor) để lấy nội dung chuẩn html thay vì bản tóm tắt cụt lủn (200 ký tự) của NewsAPI.

### 3.2 AI CEFR Grading & Processing
Mỗi bài báo khi fetch về sẽ được chạy qua pipeline nhẹ:
1. **Estimate CEFR:** Dựa trên độ dài trung bình chữ (word length) và tổng số từ.
2. **Reading Time:** Tính theo công thức `150 words / minute` (chuẩn ESL).
3. **Highlight Words:** Quét và tìm các từ vựng dài (>7 ký tự) không nằm trong list "Common Long Words", trả về để UI bôi đậm.

### 3.3 Article Quiz Generator
Endpoint `/{article_id}/quiz` sinh ra **5 câu hỏi trắc nghiệm** (comprehension, vocabulary, grammar) dựa trên bài báo đó. Đây là cách nối nội dung bên ngoài vào gamification system.

---

## 4. Hệ Thống YouTube Integration

Endpoint: `/api/v1/youtube/*`

Bao gồm 3 phần: **Curated Channels**, **Video Search**, và **Caption Parse**.

### 4.1 Curated Channels (Bypass Quota)
Thay vì liên tục hit API để lấy channel nổi tiếng, backend hardcode danh sách kênh chuẩn học tập:
- BBC Learning English (A2-B2)
- TED-Ed (B1-C1)
- English with Lucy
- EngVid
- Rachel's English (Pronunciation)
- VOA Learning English (News, A1-A2)

### 4.2 Caption Parser (VTT/SRT)
Flow lấy subtitle an toàn:
1. Gọi YouTube API `captions.list` lấy Track ID (ưu tiên tiếng Anh, nếu không có thì lấy ASR).
2. Gọi TimedText endpoint không cần OAuth: `https://www.youtube.com/api/timedtext?v={id}`
3. Deserialize JSON3 format thành dạng đoạn timeline chuẩn:
```json
[
  { "start_ms": 1200, "end_ms": 4500, "text": "Welcome to LexiLingo" },
  { "start_ms": 4500, "end_ms": 8000, "text": "Today we will learn..." }
]
```

Dữ liệu này được Mobile App dùng để kết hợp với YouTube Player SDK, bôi màu text đang đọc và hiển thị tra từ điển (tap-to-translate).

---

## 5. Luồng Dữ Liệu Thực Tế trên Mobile

Ứng dụng Flutter sẽ tiêu thụ API này trong các màn hình `NewsScreen` và `VideoLearningScreen`.

**News Flow:**
```
Chọn danh mục (Tech) → List tóm tắt bài báo (có nhãn CEFR) → Tap vào 1 bài
→ Gọi /news/full-content lấy HTML → Render bằng flutter_html
→ Hiển thị 5 từ vựng khó cuối bài → Nút [View Quiz] để kiếm XP.
```

**Video Flow:**
```
Chọn Video → Load YoutubePlayerController
→ Gọi /youtube/captions/{id} lấy array subtitle
→ Khi video phát tới ms X, UI scroll tới dòng text tương ứng
→ User tap vào text → Pause video, mở BottomSheet tra từ điển.
```

---

*Tham khảo: [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md)*
