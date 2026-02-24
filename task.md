# LexiLingo New Features — Implementation Tracker

> Ref: [implementation_plan.md](file:///Users/nguyenhuuthang/.gemini/antigravity/brain/3c00adb5-6de3-4362-b0d8-ba519d62f7c4/implementation_plan.md)

---

## Phase 0: Core Infrastructure (Caching & Rate Limiting)

> Phải hoàn thành TRƯỚC khi implement bất kỳ feature nào. Tất cả features đều phụ thuộc vào caching layer.

### Backend — Caching Service
- [x] Tạo `backend-service/app/services/api_cache_service.py`
  - [x] Implement class `APICacheService` với 3-layer cache (Redis → PostgreSQL → External API)
  - [x] Implement `CacheResult` dataclass (data, source, is_stale)
  - [x] Method `get_or_fetch()` với priority-aware quota checking
  - [x] Xử lý stale data fallback khi quota exhausted
  - [x] Logging: log cache source (redis/db/api/db_stale) cho mỗi request
  - [ ] Unit tests cho APICacheService

### Backend — Quota Manager (Near-Limit Thresholds)
- [x] Tạo `backend-service/app/services/quota_manager.py`
  - [x] Implement `QuotaStatus` enum: NORMAL / WARNING / CRITICAL / BLOCKED
  - [x] Implement `Priority` enum: HIGH / MEDIUM / LOW
  - [x] Implement class `QuotaManager`
    - [x] `LIMITS` dict với internal budget per API (20% buffer)
    - [x] `WARNING_THRESHOLD = 0.70`, `CRITICAL_THRESHOLD = 0.90`
    - [x] Method `check_status(api_name, cost)` → QuotaStatus
    - [x] Method `record_request(api_name, cost)` + auto-log warnings
    - [x] Method `get_usage(api_name)` → detailed dict (used, budget, remaining, status)
    - [x] Method `get_all_usage()` → list of all API usages
    - [x] Method `get_reset_time()` → time until midnight UTC reset
  - [x] Redis key pattern: `quota:{api_name}:{date.today()}` → tự động reset daily
  - [ ] Unit tests cho QuotaManager (test tất cả threshold levels)

### Backend — Cache Models & DB
- [x] Tạo `backend-service/app/models/api_cache.py`
  - [x] Model `APICacheEntry`: cache_key, api_name, data (JSON), created_at, updated_at, hit_count
  - [x] Method `is_expired(ttl_seconds)`
- [ ] Tạo Alembic migration cho `api_cache_entries` table
- [ ] Tạo Alembic migration cho `api_quota_usage` table (backup tracking)

### Backend — Content Prefetch Cron
- [x] Tạo `backend-service/app/tasks/content_prefetch.py`
  - [x] `prefetch_news()` — 4x/day, fetch + AI grade CEFR
  - [x] `prefetch_youtube()` — 2x/day, curated channels
  - [x] `prefetch_podcasts()` — 1x/day, curated RSS feeds
- [ ] Setup APScheduler hoặc Celery Beat scheduler
- [ ] Register cron tasks trong app startup

### Backend — Error Types
- [x] Tạo `QuotaExhaustedError` exception (kèm reset_time)
- [x] Tạo `QuotaNearLimitError` exception (kèm threshold level + message)
- [x] Handle exceptions trong API endpoints → return 429 + retry_after header

### Flutter — Local Cache Service
- [x] Tạo `flutter-app/lib/core/services/local_cache_service.dart`
  - [x] SQLite table `api_cache` (key, type, data, updated_at)
  - [x] TTL config per content type (news: 2h, youtube: 24h, podcast: 6h, book: 7d, dict: 30d)
  - [x] Method `getOrFetch<T>()` — check SQLite → fetch → serve stale on error
  - [x] Method `clearExpired()` — dọn cache hết hạn
- [x] Register trong DI container
- [x] Tạo SQLite migration script (DB version 5)

### Backend — Admin Endpoints
- [x] `GET /api/admin/quota-usage` → get_all_usage() (monitor dashboard)
- [x] `POST /api/admin/quota-reset/{api_name}` → manual reset (emergency)

---

## Phase 1: YouTube Video + Subtitles

> **Skills**: `ui-ux-pro-max` · `language-learning-patterns` → `content-difficulty-levels`, `progress-xp-system` · `speech-processing` → `tts-caching-strategy`

### Backend
- [x] Tạo `backend-service/app/routes/youtube.py`
  - [x] `GET /api/youtube/search` — proxy YouTube search.list (100 units/req)
    - [x] Accept: q, maxResults, channelId
    - [x] Cache Redis 6h + DB 12h
    - [x] Priority: HIGH (user search) / LOW (prefetch)
  - [x] `GET /api/youtube/captions/{videoId}` — fetch & parse captions
    - [x] Call captions.list → filter by language → download JSON3
    - [x] Parse thành `List<CaptionSegment>` (startMs, endMs, text)
    - [x] Cache permanently (captions không đổi)
  - [x] `GET /api/youtube/channels` — curated channel list
- [x] Config YouTube Data API v3 key trong `app/core/config.py`
- [x] Register router trong `main.py`
- [ ] Tests cho YouTube endpoints

### Flutter — Feature Module
- [x] Tạo `flutter-app/lib/features/youtube/` structure
  - [x] `domain/entities/`
    - [x] `youtube_entities.dart` — YouTubeVideo, YouTubeChannel, CaptionSegment, YouTubeSearchResult models
  - [x] `data/repositories/youtube_repository.dart`
    - [x] `searchVideos(query)` — gọi backend + local cache
    - [x] `getCaptions(videoId)` — gọi backend + cache permanently
    - [x] `getCuratedChannels()` — prefetched data
    - [x] `getChannelVideos(channelId)` — channel video list
  - [x] `presentation/providers/youtube_provider.dart`
  - [x] `presentation/screens/`
    - [x] `youtube_explore_screen.dart` — curated channels carousel, category chips, search
    - [x] `youtube_player_screen.dart` — video player + subtitle panel + tap-to-translate
    - [ ] `channel_detail_screen.dart` — channel info + video list
  - [ ] `presentation/widgets/` (extracted components)
    - [ ] `video_card.dart` — thumbnail + title + channel + duration
    - [ ] `subtitle_overlay.dart` — synced subtitle display + tap-to-translate
    - [ ] `channel_card.dart` — avatar + name + subscriber count
- [ ] Thêm `youtube_player_flutter` vào pubspec.yaml
- [ ] Thêm `youtube_caption_scraper` vào pubspec.yaml
- [x] Register routes + providers trong main.dart
- [ ] Thêm YouTube card vào Home screen

### UI/UX (skill: ui-ux-pro-max)
- [x] YouTubeExploreScreen: curated channels carousel, category chips, search bar
- [x] YouTubePlayerScreen: video player + subtitle panel + word dictionary sheet
- [x] Subtitle overlay: highlight current word, tap-to-translate bottom sheet
- [ ] Smooth animations: page transitions, search results loading shimmer

### Integration & Logic
- [ ] Course model thêm field `youtubeVideoIds: List<String>`
- [ ] CourseDetailScreen thêm tab "Video Lessons"
- [ ] Xem ≥80% video → auto XP award (POST /api/xp/award)
- [ ] Debounce search 500ms, min 3 chars
- [ ] Quota-aware: hiển thị curated content khi API approaching limit

### Verification
- [ ] Video player loads và plays correctly
- [ ] Captions hiển thị đồng bộ với video
- [ ] Tap từ trong caption → dictionary bottom sheet hiện
- [ ] Search hoạt động với cache (search lần 2 cùng query = instant)
- [ ] XP awarded sau khi xem video
- [ ] Offline: cached search results hiển thị khi mất mạng

---

## Phase 2: News Reading

> **Skills**: `ui-ux-pro-max` · `language-learning-patterns` → `content-difficulty-levels`, `adaptive-weak-points`, `progress-xp-system` · `speech-processing` → `tts-neural-voices`

### Backend
- [x] Tạo `backend-service/app/routes/news.py`
  - [x] `GET /api/news` — fetch + AI grade articles
    - [x] Accept: level (CEFR), category, page
    - [x] Call NewsAPI.org → parse → AI grade_text → assign CEFR
    - [x] Cache Redis 1h + DB 6h
    - [x] Return: articles with cefrLevel, highlightedWords
  - [x] `GET /api/news/{id}/quiz` — AI-generated comprehension quiz
    - [x] 5 questions: comprehension + vocabulary + grammar
    - [x] Cache quiz per article permanently
- [x] Config NewsAPI key trong `app/core/config.py`
- [x] Fallback: NewsData.io khi NewsAPI quota exhausted
- [x] Register router
- [ ] Tests

### Flutter — Feature Module
- [x] Tạo `flutter-app/lib/features/news/` structure
  - [x] `domain/entities/`
    - [x] `news_entities.dart` — NewsArticle, SavedWord, NewsQuiz models
  - [x] `data/repositories/news_repository.dart`
  - [x] `presentation/providers/news_provider.dart`
  - [x] `presentation/screens/`
    - [x] `news_list_screen.dart` — article list với CEFR badges
    - [x] `news_detail_screen.dart` — full article + vocabulary highlighting
    - [x] `news_quiz_screen.dart` — comprehension quiz
  - [ ] `presentation/widgets/` (extracted components)
    - [ ] `news_card.dart` — card với CEFR color badge
    - [ ] `vocabulary_bottom_sheet.dart` — tap-to-translate
    - [ ] `cefr_badge.dart` — color-coded level badge

### UI/UX (skill: ui-ux-pro-max)
- [x] NewsListScreen: CEFR-filtered cards, pull-to-refresh, color-coded badges
- [x] NewsDetailScreen: highlighted vocabulary, listen button, reading progress bar
- [x] Quiz UI: multiple choice cards, score summary, explanations
- [x] Category tabs: technology, science, world, education

### Integration & Logic
- [x] Tap word → dictionary bottom sheet (Free Dictionary API)
- [ ] "Save to Vocabulary" → SQLite + sync backend
- [ ] Listen button → AI TTS (Piper) → just_audio playback
- [x] Reading progress (scroll ≥90%) → show "Take Quiz"
- [ ] Quiz complete → XP award (POST /api/xp/award, 15 XP)
- [x] Pull-to-refresh: respect quota (chỉ refresh nếu cache > 30 min)

### Verification
- [ ] Articles load với đúng CEFR level
- [ ] Vocabulary highlighting hoạt động
- [ ] Tap word → definition + IPA + audio
- [ ] TTS playback hoạt động
- [ ] Quiz generates, submits, scores correctly
- [ ] XP awarded after quiz

---

## Phase 3: English Games + XP System

> **Skills**: `ui-ux-pro-max` · `language-learning-patterns` → `gamification-*`, `progress-*`, `adaptive-difficulty-adjustment`, `content-difficulty-levels` · `speech-processing` → `tts-neural-voices` (Spelling Bee)

### Backend
- [ ] Tạo `backend-service/app/routers/games.py`
  - [ ] `GET /api/games/word-scramble` — words phù hợp CEFR + shuffle
  - [ ] `GET /api/games/fill-blank` — AI-generated fill-in-blank questions
  - [ ] `GET /api/games/matching` — word-definition pairs
  - [ ] `GET /api/games/spelling-bee` — words + TTS audio URLs
  - [ ] `GET /api/games/grammar-quiz` — AI-generated grammar questions by topic
  - [ ] `GET /api/games/hangman` — random word by category + CEFR
- [ ] Tạo `backend-service/app/routers/xp.py`
  - [ ] `POST /api/xp/award` — validate + award XP
    - [ ] Anti-cheat: check duration ≥ minimum, daily cap 500 XP
    - [ ] Calculate streak bonus multiplier
    - [ ] Check level up → return new level info
  - [ ] `GET /api/xp/profile` — user XP, level, streak, history
  - [ ] `GET /api/xp/leaderboard` — weekly top users
- [ ] DB models: UserXP, XPTransaction, DailyStreak, GameSession
- [ ] Alembic migrations
- [ ] Seed data: word lists per CEFR level, grammar topics
- [ ] Tests

### Flutter — Feature Module
- [ ] Tạo `flutter-app/lib/features/games/` structure
  - [ ] `domain/entities/` — GameSession, GameWord, DailyChallenge, etc.
  - [ ] `data/repositories/games_repository.dart`
  - [ ] `presentation/providers/games_provider.dart`
  - [ ] `presentation/screens/`
    - [ ] `games_hub_screen.dart` — XP bar, daily challenge, game grid, leaderboard
    - [ ] `word_scramble_screen.dart` — drag-drop letter tiles
    - [ ] `fill_blank_screen.dart` — multiple choice sentences
    - [ ] `matching_game_screen.dart` — tap-to-connect word pairs
    - [ ] `spelling_bee_screen.dart` — audio + text input
    - [ ] `grammar_quiz_screen.dart` — topic-based quiz
    - [ ] `hangman_screen.dart` — classic hangman + keyboard
    - [ ] `game_result_screen.dart` — score summary + XP earned + level up
  - [ ] `presentation/widgets/`
    - [ ] `xp_progress_bar.dart` — animated gradient XP bar
    - [ ] `game_card.dart` — icon + name + best score
    - [ ] `daily_challenge_card.dart` — challenge info + timer
    - [ ] `letter_tile.dart` — draggable letter (Word Scramble)
    - [ ] `hangman_figure.dart` — progressive body drawing
    - [ ] `streak_indicator.dart` — fire animation + day count
    - [ ] `level_up_dialog.dart` — confetti + badge reveal

### Individual Games — Detailed Implementation
- [ ] **Game 1: Word Scramble**
  - [ ] Drag-drop tiles hoặc tap-to-select letter order
  - [ ] Timer scaling: A1=90s, B1=60s, C1=45s cho 10 words
  - [ ] Hint system: sai lần 1 → hint, lần 2 → first letter, lần 3 → skip
  - [ ] Streak bonus: 3+ correct in a row → +2 XP/word
  - [ ] Confetti + sound on correct
- [ ] **Game 2: Fill in the Blank**
  - [ ] 4-option multiple choice per sentence
  - [ ] AI-generated based on CEFR grammar rules
  - [ ] Grammar tip hiển thị sau mỗi câu (đúng hoặc sai)
  - [ ] Timer: 15s/question
- [ ] **Game 3: Matching Game**
  - [ ] Tap word → tap definition → connect
  - [ ] Variations: Word↔Definition, Word↔Synonym, Word↔Vietnamese
  - [ ] Scaling: A1=4 pairs, B1=6 pairs, C1=8 pairs
  - [ ] Time bonus khi finish trước 50% time
- [ ] **Game 4: Spelling Bee**
  - [ ] Play audio (TTS) → user types word
  - [ ] Allow replay max 3 times
  - [ ] Partial credit: 1 letter wrong → 50% XP
  - [ ] Show IPA + definition after each word
- [ ] **Game 5: Grammar Quiz**
  - [ ] Topics by CEFR (A1: to be, present simple → C2: inversion, cleft)
  - [ ] Adaptive: sai liên tiếp → giảm difficulty
  - [ ] Grammar mastery tracking (KuzuDB)
  - [ ] 10 questions/round, 12s/question
- [ ] **Game 6: Hangman**
  - [ ] On-screen keyboard, 6 lives
  - [ ] Category system (Food, Animals, Travel, etc.)
  - [ ] 3-tier hint: free category → -5 XP definition → -5 XP letter reveal
  - [ ] Progressive body drawing animation

### XP System Integration
- [ ] Extend existing `GamificationService` (không tạo parallel)
- [ ] Extend existing `AchievementService` 
- [ ] Level formula: `level = floor(sqrt(total_xp / 50))`
- [ ] Streak multiplier: 3d→1.2x, 7d→1.5x, 30d→2.0x
- [ ] Daily XP cap: 500 XP/day
- [ ] XP sources: games, news reading (15), podcast (20), YouTube (15), book chapter (25)

### UI/UX (skill: ui-ux-pro-max)
- [ ] GamesHub: animated XP bar, fire streak animation, game grid with gradient cards
- [ ] Each game: timer animation, correct/wrong feedback, confetti on win
- [ ] Game result: score stars, XP counter animation, level up celebration
- [ ] Leaderboard preview: top 3 with podium animation

### Verification
- [ ] Mỗi game chơi được đầy đủ flow (start → play → end → XP)
- [ ] XP tính đúng: base × difficulty × streak bonus
- [ ] Daily cap 500 XP works
- [ ] Level up triggers correctly
- [ ] Streak tracking: miss 1 day → reset
- [ ] Anti-cheat: rapid-fire submissions rejected
- [ ] Leaderboard hiển thị đúng rankings

---

## Phase 4: Podcast

> **Skills**: `ui-ux-pro-max` · `speech-processing` → `tts-speed-control`, `audio-format-optimization`, `performance-offline-fallback`, `stt-streaming-vs-batch` · `language-learning-patterns` → `content-difficulty-levels`, `progress-xp-system`

### Backend
- [ ] Tạo `backend-service/app/routers/podcasts.py`
  - [ ] `GET /api/podcasts/search` — PodcastIndex API search
  - [ ] `GET /api/podcasts/curated` — pre-configured podcast list by CEFR
  - [ ] `GET /api/podcasts/episodes/{feedUrl}` — parse RSS feed
  - [ ] `POST /api/podcasts/transcript` — AI STT for transcript generation (optional)
- [ ] Config PodcastIndex API keys
- [ ] RSS feed parser utility
- [ ] Tests

### Flutter — Feature Module
- [ ] Tạo `flutter-app/lib/features/podcast/` structure
  - [ ] `domain/entities/` — Podcast, PodcastEpisode, ListeningHistory, UserPodcastFollow
  - [ ] `data/repositories/podcast_repository.dart`
  - [ ] `presentation/providers/podcast_provider.dart`
  - [ ] `presentation/screens/`
    - [ ] `podcast_explore_screen.dart` — "For You", curated, categories, search
    - [ ] `podcast_detail_screen.dart` — podcast info + episode list
    - [ ] `podcast_player_screen.dart` — audio player + transcript panel
  - [ ] `presentation/widgets/`
    - [ ] `podcast_card.dart` — artwork + title + author
    - [ ] `episode_tile.dart` — title + duration + CEFR + download button
    - [ ] `audio_player_controls.dart` — play/pause, skip ±15s, speed
    - [ ] `transcript_panel.dart` — scrollable text + tap-to-translate
- [ ] Thêm `audio_service` vào [pubspec.yaml](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/flutter-app/pubspec.yaml)
- [ ] Thêm `webfeed_plus` vào [pubspec.yaml](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/flutter-app/pubspec.yaml)

### Audio & Playback
- [ ] Background playback (audio_service) + lock screen controls
- [ ] Speed control: 0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2.0x
- [ ] Progress tracking: save last position + total listened
- [ ] Download for offline: save audio file to device storage
- [ ] Download state management: notDownloaded → downloading → downloaded

### Integration & Logic
- [ ] CEFR-based recommendations (A1-A2: slow speech, C1-C2: native speed)
- [ ] RSS parsing trực tiếp → no API cost cho episode list
- [ ] Transcript: tap word → dictionary (same as News feature)
- [ ] Listen ≥80% → XP award (20 XP)
- [ ] "Follow" podcast → save to followed list

### Verification
- [ ] Podcast search hoạt động
- [ ] Episode list load từ RSS feed
- [ ] Audio plays, pauses, seeks correctly
- [ ] Background playback works (locked screen)
- [ ] Speed control works
- [ ] Offline download + playback works
- [ ] XP awarded after listening

---

## Phase 5: Book Reading

> **Skills**: `ui-ux-pro-max` · `language-learning-patterns` → `content-difficulty-levels`, `adaptive-weak-points`, `progress-xp-system`, `srs-sm2-algorithm`

### Backend
- [ ] Tạo `backend-service/app/routers/books.py`
  - [ ] `GET /api/books/search` — search Gutendex + Open Library → merge + deduplicate
    - [ ] AI estimate CEFR level from description
    - [ ] Cache Redis 24h + DB 7d
  - [ ] `GET /api/books/{id}/quiz` — AI comprehension quiz per chapter
  - [ ] `GET /api/books/recommended` — curated books by CEFR level
- [ ] Tests

### Flutter — Feature Module
- [ ] Tạo `flutter-app/lib/features/books/` structure
  - [ ] `domain/entities/` — Book, UserBook, Bookmark, ReadingSession
  - [ ] `data/repositories/book_repository.dart`
  - [ ] `presentation/providers/book_provider.dart`
  - [ ] `presentation/screens/`
    - [ ] `book_library_screen.dart` — "Continue Reading", recommendations, categories, "My Library"
    - [ ] `book_detail_screen.dart` — cover, synopsis, CEFR level, "Read Now"
    - [ ] `book_reader_screen.dart` — paginated reader (EPUB or plain text)
  - [ ] `presentation/widgets/`
    - [ ] `book_card.dart` — cover + title + author + CEFR badge
    - [ ] `reader_controls.dart` — font size, theme (light/sepia/dark), line spacing
    - [ ] `bookmark_button.dart` — save page position
- [ ] Thêm `vocsy_epub_viewer` vào [pubspec.yaml](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/flutter-app/pubspec.yaml)
- [ ] Thêm `flutter_widget_from_html` vào [pubspec.yaml](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/flutter-app/pubspec.yaml)

### Reader Features
- [ ] EPUB rendering: vocsy_epub_viewer with custom themes
- [ ] Plain text rendering: flutter_widget_from_html + custom pagination
- [ ] Reader controls: font size (14-28px), theme (Light/Sepia/Dark), line spacing
- [ ] Bookmarks: tap top-right → save position
- [ ] Tap-to-translate: long press word → dictionary bottom sheet
- [ ] "Save Word" → vocabulary list + spaced repetition (existing SM-2)
- [ ] Reading progress: current page / total pages → sync backend
- [ ] Chapter end → optional comprehension quiz (AI-generated)
- [ ] XP: 25 XP per chapter completed

### Offline Support
- [ ] Download EPUB/text to device documents directory
- [ ] Register downloaded books in local SQLite DB
- [ ] All reading features work 100% offline after download
- [ ] Book content cached permanently (public domain)

### Verification
- [ ] Book search returns results from Gutenberg + Open Library
- [ ] EPUB reader displays correctly with pagination
- [ ] Reader controls (font, theme, spacing) work
- [ ] Tap-to-translate shows dictionary
- [ ] Bookmarks save and restore position
- [ ] Reading progress tracks correctly
- [ ] Downloaded books available offline
- [ ] XP awarded per chapter

---

## Phase 6: Cross-Feature Integration & Final Polish

### Home Screen
- [ ] Thêm feature cards cho mỗi feature mới (YouTube, News, Podcast, Games, Books)
- [ ] "Continue" sections: tiếp tục video/article/podcast/book đang xem dở
- [ ] Quick stats: articles read today, games played, minutes listened

### Dictionary Service (shared)
- [ ] Tạo `flutter-app/lib/core/services/dictionary_service.dart` (shared across features)
- [ ] Integrate Free Dictionary API + WordsAPI fallback
- [ ] Shared vocabulary saving → SQLite + backend sync
- [ ] Spaced repetition cho saved words (leverage existing SM-2)

### Navigation
- [ ] Thêm bottom nav items hoặc feature discovery section
- [ ] Deep linking: notification → specific content
- [ ] Register tất cả routes trong app router

### pubspec.yaml — All Dependencies
- [ ] `youtube_player_flutter`
- [ ] `youtube_caption_scraper`
- [ ] `audio_service`
- [ ] `webfeed_plus`
- [ ] `vocsy_epub_viewer`
- [ ] `flutter_widget_from_html`
- [ ] `teqani_rewards`

### Performance & Quality
- [ ] Run `flutter analyze` → fix all warnings
- [ ] Run existing tests → ensure no regressions
- [ ] Test offline mode cho mỗi feature
- [ ] Test quota exhaustion fallback (fake high usage → verify stale data served)
- [ ] Test daily quota reset (verify counters reset at midnight)

---

## API Keys Checklist

- [ ] YouTube Data API v3 key (Google Cloud Console)
- [ ] NewsAPI.org key
- [ ] PodcastIndex.org API key + secret
- [ ] WordsAPI key (RapidAPI) — optional
- [ ] Configure tất cả keys trong [backend-service/.env](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/.env)
