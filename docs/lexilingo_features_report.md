# BÁO CÁO PHÂN TÍCH CHỨC NĂNG HỆ THỐNG LEXILINGO
**(Tài liệu tham khảo chuyên sâu chuẩn Đồ án/Dự án phần mềm)**

---

## LỜI MỞ ĐẦU
**LexiLingo** là một hệ sinh thái học tiếng Anh thông minh toàn diện, tích hợp trí tuệ nhân tạo (AI) và các phương pháp học tập hiện đại. Hệ thống không chỉ cung cấp các bài học truyền thống mà còn cá nhân hóa trải nghiệm người dùng thông qua trợ lý ảo AI, hệ thống Gamification (Trò chơi hóa), và kết nối với các nguồn nội dung thực tế (YouTube, Podcast, News).

Báo cáo này trình bày phân tích chi tiết về kiến trúc phần mềm và chức năng của từng phân hệ (module) trên ứng dụng phía Client (Flutter), bao gồm luồng dữ liệu (Data Flow), các dịch vụ (Services), API Endpoints được sử dụng, cũng như các điểm nhấn về mặt công nghệ (Technical Highlights).

---

## PHẦN 1: KIẾN TRÚC TỔNG THỂ HỆ THỐNG

### 1.1 Kiến trúc Client (Flutter App)
Ứng dụng sử dụng kiến trúc phân chia theo tính năng (**Feature-first Architecture**), kết hợp với Dependency Injection (`get_it`) và State Management thông qua `Provider`. 
Tầng giao tiếp mạng (Network Layer) sử dụng package `http` và `dio`, đi kèm cơ chế tự động chuyển đổi môi trường (Development/Production).

### 1.2 Kiến trúc Server-side (Microservices-oriented)
Ứng dụng kết nối với hai cụm server chính:
1. **Backend Gateway (`API_BASE_URL`):** Quản lý định tuyến, xác thực JWT, lưu trữ dữ liệu người dùng, quản lý hệ thống Gamification và làm Proxy cho các dịch vụ bên thứ ba (để ẩn API Keys và tối ưu Caching).
2. **AI Service (`AI_SERVICE_URL`):** Cụm server chuyên biệt dùng để xử lý các tác vụ nặng về AI như Large Language Models (LLM) cho hội thoại tự nhiên, Speech-to-Text (STT) và Text-to-Speech (TTS).

---

## PHẦN 2: PHÂN TÍCH CHI TIẾT CÁC PHÂN HỆ VÀ TRANG (PAGES)

### 2.1 Phân Hệ Xác Thực & Quản Lý Người Dùng (Authentication & User Profile)
Phân hệ này đảm bảo tính bảo mật của toàn bộ hệ thống, cung cấp cơ chế định danh cho người học.

*   **Các trang (Pages) chính:**
    *   `LoginPage` / `RegisterPage` (Đăng nhập / Đăng ký)
    *   `ResetPasswordPage` (Khôi phục mật khẩu)
    *   `ProfilePage` (Trang cá nhân)
*   **Service & Provider chịu trách nhiệm:**
    *   `AuthProvider`, `UserProvider`, `SettingsProvider`.
*   **API Endpoints & Dịch vụ:**
    *   `POST /auth/login`, `POST /auth/register`, `POST /auth/logout`
    *   `POST /auth/verify-email`, `POST /auth/forgot-password`
    *   `POST /devices`: Quản lý danh sách thiết bị để gửi Firebase Push Notifications.
    *   `GET /users/me/stats`, `GET /users/me/weekly-activity`: Thống kê tần suất học tập cá nhân.
*   **Điểm nhấn công nghệ (Features):**
    *   **OAuth 2.0 (Firebase):** Tích hợp đăng nhập qua mạng xã hội (Facebook, Google) kết hợp với Backend tự quản lý.
    *   **Deep-linking:** Tự động bắt đường dẫn URL (Deep-link) từ email khôi phục mật khẩu để mở thẳng màn hình `ResetPasswordPage` mà không cần nhập code thủ công.

### 2.2 Phân Hệ Bảng Điều Khiển Trung Tâm (Home Dashboard)
Trang chủ đóng vai trò là "Bộ não" dẫn đường, giúp người dùng nắm bắt tiến độ của bản thân ngay khi mở ứng dụng.

*   **Các trang (Pages) chính:**
    *   `HomePageNew` (Trang chủ ứng dụng)
    *   `NotificationsPage` (Thông báo)
*   **Service & Provider chịu trách nhiệm:**
    *   `HomeProvider`, `StreakProvider`, `DailyChallengesProvider`, `LevelProvider`.
*   **API Endpoints & Dịch vụ:**
    *   `GET /users/me/level-full`: Tính toán tổng điểm kinh nghiệm (XP) hiện có, cấp độ hiện tại và mức độ cần đạt để lên cấp.
    *   `GET /progress/streak`: Kiểm tra chuỗi ngày đăng nhập liên tục (Streak).
    *   `GET /challenges/daily`: Tải danh sách nhiệm vụ ngẫu nhiên mỗi ngày.
*   **Điểm nhấn công nghệ (Features):**
    *   **Thuật toán hiển thị Progress Ring:** Sử dụng UI Glassmorphism kết hợp animation tính toán chính xác % XP hoàn thành mục tiêu ngày (Daily Goal).
    *   **Level-Up Listener:** Kiến trúc Reactive cho phép ứng dụng tự động pop-up `LevelUpDialog` với animation pháo hoa khi người dùng vừa nhận đủ XP từ bất kỳ nguồn nào trong ứng dụng.
    *   **Skeleton Loading:** Đảm bảo trải nghiệm UX mượt mà khi dữ liệu đang được đồng bộ.

### 2.3 Phân Hệ Trợ Lý Ảo Trí Tuệ Nhân Tạo (Lexi Chat & Story)
Đây là "Trái tim" công nghệ của LexiLingo, nơi người dùng luyện tập kỹ năng phản xạ tự nhiên.

*   **Các trang (Pages) chính:**
    *   `LexiChatPage` (Giao diện nhắn tin với AI Lexi).
    *   `StoryAdventureScreen` (Nhập vai vào tình huống thực tế).
*   **Service & Provider chịu trách nhiệm:**
    *   `LexiChatProvider`, `VoiceProvider`, `SpeechRecognitionProvider`.
    *   `VoiceRemoteDataSource`.
*   **API Endpoints & Dịch vụ:**
    *   **AI Service endpoints:** 
        *   `POST /stt/transcribe` (truyền Audio dạng `Uint8List` để nhận diện giọng nói).
        *   `POST /tts/synthesize` (nhận đoạn text từ AI và trả về bytes âm thanh).
    *   **Backend endpoints:**
        *   `POST /chat/sessions`, `GET /chat/sessions/user/{userId}`
        *   `GET /lexi/sessions/{id}/messages` (Truy xuất lịch sử hội thoại Contextual).
*   **Điểm nhấn công nghệ (Features):**
    *   **GraphCAG (Graph Context-Aware Generation):** Kiến trúc cốt lõi kết hợp giữa Knowledge Graph (KuzuDB) và Redis KV Cache, giúp truy xuất ngữ cảnh (ngữ pháp, từ vựng) siêu tốc. Hệ thống tự động phân tích câu nói của người dùng, ánh xạ với đồ thị tri thức để đưa ra chẩn đoán lỗi sai và phản hồi (correction/explanation) cực kỳ chính xác.
    *   **Contextual LLM (Mô hình ngôn ngữ lớn có ngữ cảnh):** AI có khả năng nhớ bối cảnh (ví dụ: bối cảnh đang ở sân bay, mua sắm) kết hợp lịch sử hội thoại được lưu trên Redis để phản hồi tự nhiên.
    *   **Giao tiếp Âm thanh hai chiều (Two-way Voice Interaction):** Quá trình chuyển đổi từ Speech $\rightarrow$ Text (Người dùng) $\rightarrow$ GraphCAG/LLM Processing $\rightarrow$ Text $\rightarrow$ Speech (AI) diễn ra gần như tức thời.

### 2.4 Phân Hệ Nội Dung Thực Tế (Real-World Media Integrations)
Mục đích là đưa người dùng nhúng (immerse) vào tiếng Anh đời thực thay vì các bài học sách giáo khoa.

*   **Các trang (Pages) chính:**
    *   **YouTube:** `YouTubeExploreScreen`, `YouTubePlayerScreen`.
    *   **Podcast:** `PodcastExploreScreen`, `PodcastPlayerScreen`.
    *   **News:** `NewsListScreen`, `NewsDetailScreen`, `NewsQuizScreen`.
    *   **Books:** `BookLibraryScreen`.
*   **Service & Provider chịu trách nhiệm:**
    *   `YouTubeProvider`, `PodcastProvider`, `NewsProvider`, `BookProvider`.
*   **API Endpoints & Dịch vụ:**
    *   `GET /youtube/channels`, `GET /youtube/search`, `GET /youtube/captions/{videoId}`.
    *   `GET /podcasts/...`, `GET /news/...`, `GET /books/...`
*   **Điểm nhấn công nghệ (Features):**
    *   **Backend Proxy & Server-side Caching:** Để tránh bị giới hạn (Rate-limiting) API từ YouTube hay RSS Feeds, Backend Gateway hoạt động như một Proxy. Client gọi Backend thay vì gọi trực tiếp YouTube, giúp hệ thống lưu trữ đệm (Cache) kết quả tìm kiếm trên Server, tiết kiệm chi phí vận hành.
    *   **Subtitle Extraction:** Trình phát YouTube tự động trích xuất Captions (Phụ đề) và đồng bộ hóa với thời gian chạy video.
    *   **Automated Quizzes:** Tính năng `NewsQuizScreen` tích hợp AI sinh tự động các câu hỏi đọc hiểu (Reading Comprehension) trực tiếp từ bản tin người dùng vừa đọc.

### 2.5 Phân Hệ Trò Chơi Hóa & Mạng Xã Hội (Gamification & Social)
Kích thích động lực học tập thông qua cạnh tranh và phần thưởng.

*   **Các trang (Pages) chính:**
    *   `GamesHubScreen` (Khu vực chọn Minigame với 6 loại hình: Word Scramble, Matching, Spelling Bee, Hangman, Fill in the Blank, Grammar Quiz).
    *   `LeaderboardPage`, `ShopPage`, `InventoryPage`.
    *   `SocialFeedPage`.
*   **Service & Provider chịu trách nhiệm:**
    *   `GamificationProvider`, `GamesProvider`, `AchievementProvider`, `SocialProvider`.
*   **API Endpoints & Dịch vụ:**
    *   `GET /xp/leaderboard`, `POST /xp/award` (Nhận thưởng).
    *   `GET /gamification/wallet`, `GET /gamification/shop`.
    *   `GET /gamification/achievements/me`, `POST /gamification/achievements/check` (Kiểm tra mở khóa danh hiệu mới).
    *   `GET /gamification/feed`, `POST /gamification/users/{id}/follow`.
*   **Điểm nhấn công nghệ (Features):**
    *   **Games Engine Tích hợp Backend:** Toàn bộ logic trò chơi, randomize câu hỏi theo chuẩn CEFR, tính điểm XP và đếm giờ đều được xử lý thống nhất ở Backend, ngăn chặn gian lận (cheat) và đảm bảo công bằng.
    *   **Hệ thống Kinh tế ảo (Virtual Economy):** Chuyển đổi XP thành Coin, sử dụng Coin để mua vật phẩm bảo vệ chuỗi ngày học (Streak Freeze) hoặc giao diện.
    *   **Social Feed Real-time:** Hoạt động học tập, thành tựu của bạn bè được push lên bảng tin (Feed) tạo cảm giác thi đua.

### 2.6 Phân Hệ Lộ Trình Học & Từ Vựng (Courses & Vocabulary Spaced Repetition)
Nền tảng kiến thức cơ bản cho người học từ mất gốc đến nâng cao.

*   **Các trang (Pages) chính:**
    *   `CourseDetailScreen`, `LearningSessionScreen`.
    *   `VocabLibraryPage`, `DailyReviewCard`.
*   **Service & Provider chịu trách nhiệm:**
    *   `CourseProvider`, `LearningProvider`, `VocabProvider`, `FlashcardProvider`.
*   **API Endpoints & Dịch vụ:**
    *   `GET /courses`, `POST /courses/{id}/enroll` (Ghi danh).
    *   `POST /learning/lessons/{id}/start` (Đánh dấu tiến độ).
    *   `GET /vocabulary/items`, `GET /vocabulary/due` (Từ đến hạn ôn).
*   **Điểm nhấn công nghệ (Features):**
    *   **Thuật toán Spaced Repetition System (SRS):** Endpoint `/vocabulary/due` sử dụng thuật toán (ví dụ SM-2 hoặc SuperMemo) để tính toán điểm rơi quên lãng của não bộ, từ đó hiển thị thẻ flashcard cần ôn tập ngay trong ngày lên trên màn hình chính (Daily Review Card).

### 2.7 Phân Hệ Đánh Giá Năng Lực (CEFR Proficiency Assessment)
Đây là hệ thống ngầm (Background System) quan trọng giúp cá nhân hóa lộ trình học và độ khó của AI. Khác với XP (đo lường sự chăm chỉ), Proficiency đo lường thực lực người học.

*   **Service chịu trách nhiệm (Backend):**
    *   `ProficiencyService`
*   **API Endpoints & Dịch vụ:**
    *   `GET /api/v1/proficiency/` (Lấy dữ liệu biểu đồ mạng nhện kỹ năng).
    *   `GET /api/v1/proficiency/history` (Biểu đồ lịch sử tăng trưởng điểm).
*   **Điểm nhấn công nghệ (Features):**
    *   **Thuật toán Đánh giá Đa chiều:** Tính điểm dựa trên 6 kỹ năng (Vocab, Grammar, Reading, Listening, Speaking, Writing) với trọng số (Skill Weighting) và hệ số độ khó (Difficulty Multiplier).
    *   **Phân tích Xu hướng (Trend Analysis) & Time Decay:** Đánh giá người học đang cải thiện, giữ vững hay đi xuống; đồng thời tự động giảm nhẹ điểm (Time Decay) nếu người dùng nghỉ học quá lâu (quên kiến thức).
    *   **Đồng bộ với AI Service:** Điểm CEFR được đồng bộ làm `Learner Profile` cho GraphCAG, giúp AI quyết định nên dùng từ vựng khó hay độ khắt khe khi sửa lỗi ngữ pháp.

---

## PHẦN 3: ĐÁNH GIÁ VÀ KẾT LUẬN

### 3.1 Đánh giá ưu điểm kiến trúc
1. **Khả năng mở rộng (Scalability):** Việc tách rời giữa **Backend Gateway** (xử lý logic nghiệp vụ, database) và **AI Service** (xử lý các model phân tích giọng nói, LLM) cho phép mở rộng (Scale) hạ tầng độc lập khi lượng user tương tác voice tăng cao.
2. **Quản lý trạng thái thông minh:** Sử dụng `Provider` đi kèm `get_it` (Service Locator) giúp việc chia sẻ dữ liệu (như Level XP, Username) giữa trang Home và các Minigames diễn ra tức thời (Reactive) mà không cần phải reload lại màn hình.
3. **Hiệu năng & Tối ưu mạng:** Áp dụng cơ chế Local Cache và Proxy API giúp giảm đáng kể lượng request gửi ra ngoài Internet (đặc biệt đối với APIs từ bên thứ ba như YouTube).

### 3.2 Hướng phát triển tương lai (Future Works)
- **Offline Mode:** Tích hợp Hive/Isar Database trên local để lưu trữ từ vựng và bài học, cho phép đồng bộ `SyncQueueLifecycleRunner` khi có kết nối mạng lại.
- **Micro-Frontend:** Nếu ứng dụng lớn hơn, có thể chuyển đổi cấu trúc các Feature thành các package Flutter độc lập (Melos workspace) để tăng tốc độ build và quản lý team.
- **Mở rộng Đồ thị tri thức (Knowledge Graph):** Bổ sung thêm các quy tắc ngữ âm (Phonetics) và thành ngữ (Idioms) phức tạp vào KuzuDB để AI Tutor (GraphCAG) có thể chẩn đoán và hướng dẫn phát âm chuyên sâu hơn, tiệm cận với giáo viên bản ngữ.

---
*Báo cáo được trích xuất dựa trên kiến trúc và mã nguồn thực tế của dự án LexiLingo.*
