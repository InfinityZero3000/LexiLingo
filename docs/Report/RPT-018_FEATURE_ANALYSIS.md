# RPT-018 — Phân Tích Tính Năng Toàn Diện LexiLingo

> **Cập nhật:** 2026-04-24 | **Phiên bản dự án:** v0.4.0 (Flutter), v1.0.1 (Backend), v2.1.0 (AI Service)

---

## 1. Tổng Quan Hệ Thống

LexiLingo là nền tảng học tiếng Anh enterprise-grade, tích hợp AI và machine learning để cung cấp **trải nghiệm học cá nhân hóa và thích ứng**. Hệ thống sử dụng kiến trúc microservices với 3 service chính: Backend, AI Service và Flutter App.

---

## 2. Danh Sách Tính Năng Chính

### 2.1 🤖 AI & Machine Learning Features

| Feature | Mô tả | Vị trí |
|---------|--------|--------|
| **GraphCAG Pipeline** | Graph + Cache-Augmented Generation qua LangGraph StateGraph | `ai-service/api/services/graph_cag/` |
| **Smart Model Router** | Tự động chọn model phù hợp dựa trên độ phức tạp | `ai-service/api/services/smart_router.py` |
| **Model Gateway** | Quản lý vòng đời tất cả AI models với lazy loading | `ai-service/api/services/model_gateway.py` |
| **CEFR Assessment** | Đánh giá trình độ tự động từ A1 đến C2 | `backend-service/app/services/proficiency_service.py` |
| **SM-2 Spaced Repetition** | Lịch ôn tập tối ưu theo thuật toán SuperMemo 2 | Backend/AI service |
| **HuBERT Pronunciation** | Phân tích phát âm cấp phoneme với Facebook HuBERT-large | `ai-service/api/services/hubert_service.py` |
| **Knowledge Graph (KuzuDB)** | Đồ thị tri thức curriculum với mastery tracking | `ai-service/api/services/kg_service_v3.py` |
| **Dual-Stream Voice** | STT → Thinking → TTS đồng thời với interruption handling | `ai-service/api/routes/websocket_stream.py` |
| **Content Auto-Generation** | AI tự tạo bài tập thích ứng với profil người học | `ai-service/api/services/graph_cag/nodes_v2.py` |

### 2.2 📚 Learning Features

| Feature | Mô tả | Backend Route |
|---------|--------|--------------|
| **Course System** | Khóa học có phân cấp (category → course → lesson) | `/api/v1/courses/` |
| **Learning Sessions** | Phiên học với tracking thời gian và kết quả | `/api/v1/learning/` |
| **Progress Tracking** | Theo dõi tiến độ học, streak, daily activity | `/api/v1/progress/` |
| **Vocabulary Library** | Thư viện từ vựng cá nhân với flashcard | `/api/v1/vocabulary/` |
| **Daily Challenges** | Thử thách hàng ngày với phần thưởng | `/api/v1/challenges/` |
| **Proficiency Assessment** | Kiểm tra trình độ CEFR multi-dimensional | `/api/v1/proficiency/` |

### 2.3 🎮 Gamification Features

| Feature | Mô tả | Backend Route |
|---------|--------|--------------|
| **XP System** | Hệ thống điểm kinh nghiệm phân cấp | `/api/v1/xp/` |
| **Streak System** | Chuỗi ngày học liên tiếp | `progress` module |
| **Achievement Badges** | Huy hiệu thành tích với điều kiện đa dạng | `backend/services/__init__.py` |
| **Leaderboard** | Bảng xếp hạng người dùng | `gamification` module |
| **English Games** | Mini-game học tiếng Anh (word puzzles, etc.) | `/api/v1/games/` |
| **Gems & Rewards** | Hệ thống gem và phần thưởng | `gamification` module |
| **Items/Power-ups** | Vật phẩm tăng sức mạnh học tập | `backend/services/item_effects_service.py` |

### 2.4 📰 Content Features

| Feature | Mô tả | Backend Route | Flutter Screen |
|---------|--------|--------------|----------------|
| **YouTube Videos** | Xem video YouTube kèm quiz | `/api/v1/youtube/` | `youtube_explore_screen.dart` |
| **News Reading** | Đọc tin tức với quiz kiểm tra hiểu bài | `/api/v1/news/` | `news_list_screen.dart`, `news_quiz_screen.dart` |
| **Podcast Player** | Nghe podcast với background playback | `/api/v1/podcasts/` | `podcast_player_screen.dart` |
| **Book Library** | Thư viện sách điện tử | `/api/v1/books/` | `book_library_screen.dart` |

### 2.5 🗣️ Voice & Communication Features

| Feature | Mô tả | Route |
|---------|--------|-------|
| **AI Tutor Chat** | Trò chuyện với gia sư AI cơ bản | `/api/v1/chat/` |
| **Lexi Chat (Advanced)** | Chat nâng cao với GraphCAG pipeline, voice support | `/api/v1/lexi/` |
| **Topic Chat** | Chat theo chủ đề với context đặc biệt | `/api/v1/topics/` |
| **Speech-to-Text** | Chuyển giọng nói thành văn bản (Whisper) | `/api/v1/stt/` |
| **Text-to-Speech** | Tạo âm thanh từ văn bản (Piper/gTTS) | `/api/v1/tts/` |
| **Voice WebSocket** | Luồng voice thời gian thực | `websocket_stream.py` |

### 2.6 👥 Social & User Features

| Feature | Mô tả | Route |
|---------|--------|-------|
| **Authentication** | JWT + Firebase (Google, Facebook, Email) | `/api/v1/auth/` |
| **User Profile** | Quản lý hồ sơ cá nhân | `/api/v1/users/` |
| **Social Features** | Tương tác xã hội giữa người học | `/api/v1/social/` |
| **Notifications** | Push notification qua Firebase FCM | `devices/notifications` |
| **Multi-language UI** | Giao diện đa ngôn ngữ (easy_localization) | `core/l10n/` |

### 2.7 🔧 Admin & Analytics Features

| Feature | Mô tả |
|---------|--------|
| **Admin Dashboard** | React/Vite dashboard quản lý nội dung | `admin-service/` |
| **Analytics API** | Số liệu học tập và hành vi người dùng | `/api/v1/analytics/` |
| **RBAC System** | Phân quyền dựa trên vai trò | `/api/v1/rbac/` |
| **User Management** | Quản lý người dùng nâng cao | `/api/v1/user-management/` |
| **AI Audit** | Kiểm tra và log AI decisions | `/api/v1/ai-audit/` |

---

## 3. Phân Tích Theo Provider Feature Phases

Flutter app được phát triển theo 6 phases rõ ràng:

```
Phase 1: YouTube Video Integration    → YouTubeProvider
Phase 2: News Reading                 → NewsProvider
Phase 3: English Games + XP System   → GamesProvider
Phase 4: Podcast (Background Audio)  → PodcastProvider
Phase 5: Book Reading                 → BookProvider
Phase 6: Lexi Chat (Story Adventure) → LexiChatProvider
```

---

## 4. Key Highlights — Tính Năng Liên Biệt

### 4.1 GraphCAG Pipeline (Đặc sắc nhất)
Không giống RAG truyền thống, GraphCAG kết hợp:
- **KuzuDB Knowledge Graph**: Đồ thị curriculum với quan hệ prerequisite
- **Redis Cache-Augmented Generation (CAG)**: Cache context người học, không cần re-retrieve
- **LangGraph StateGraph**: Orchestration đa bước stateful với conditional routing

### 4.2 CEFR Assessment (6 chiều đánh giá)
Thuật toán đánh giá trình độ tích hợp:
- Vocabulary (25%), Grammar (25%), Reading (15%), Listening (15%), Speaking (10%), Writing (10%)
- Chống "XP grinding" – không thể lên cấp chỉ bằng số lượng bài
- EMA (Exponential Moving Average) cho điểm kỹ năng

### 4.3 SM-2 Spaced Repetition
Thuật toán lập lịch ôn tập SuperMemo 2 với:
- Easiness Factor (EF) điều chỉnh per-concept
- Priority queue sắp xếp bài quá hạn
- Mastery Score tổng hợp từ accuracy, EF, interval, repetitions

---

## 5. Bản Đồ Tính Năng → Service

```
Flutter App
├── Auth (Google/Facebook/Email) → Backend /auth
├── Courses/Learning           → Backend /courses, /learning
├── Vocabulary + Flashcard     → Backend /vocabulary
├── Progress/Streak            → Backend /progress
├── Gamification/Achievements  → Backend /gamification, /xp
├── AI Chat (Basic)            → AI Service /chat
├── Lexi Chat (Advanced)       → AI Service /lexi
├── Voice (STT/TTS/Realtime)   → AI Service /stt, /tts, /ws
├── YouTube/News/Podcast/Books → Backend content APIs
└── Social/Notifications       → Backend /social, /devices
```

---

*Tham khảo: [RPT-001](RPT-001_REPORT_INDEX.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md)*
