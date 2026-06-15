# RPT-024 — Hệ Thống Câu Hỏi và Mini-Game (Games Engine)

> **Cập nhật:** 2026-06-15 | **Nguồn:** `backend-service/app/routes/games.py`, `app/services/`, `flutter-app/lib/features/games/`

---

## 1. Tổng Quan

Games Engine là một module học tập tương tác **được nhúng hoàn toàn trong backend**, cung cấp 6 loại mini-game tiếng Anh với ngân hàng câu hỏi (question bank) theo từng cấp độ CEFR (A1→C2). Toàn bộ logic game, randomization, XP tính điểm và seed data đều nằm trong một file duy nhất.

---

## 2. Kiến Trúc Games Engine

```
Backend API: /api/v1/games/*
        │
        ├─ 6 Game Types (stateless endpoints)
        ├─ GameWord DB Table (PostgreSQL)
        ├─ GAME_WORDS_SEED (embedded — auto-seed if empty)
        ├─ FILL_BLANK_BANK (embedded per CEFR level)
        └─ GRAMMAR_QUIZ_BANK (embedded per CEFR level)
```

**Điểm đặc biệt:** Game data được tổ chức theo 2 nguồn:
1. **`GameWord` table** từ PostgreSQL — cho Word Scramble, Matching, Spelling Bee, Hangman
2. **Hardcoded banks** (`FILL_BLANK_BANK`, `GRAMMAR_QUIZ_BANK`) — cho Fill Blank và Grammar Quiz

---

## 3. Danh Sách 6 Mini-Games

### 3.1 Word Scramble
**Endpoint:** `GET /api/v1/games/word-scramble`

Người chơi nhận các chữ cái xáo trộn và đoán lại từ đúng.

| Field | Mô tả |
|-------|--------|
| `word` | Từ gốc (ẩn đi với người chơi) |
| `scrambled` | Chuỗi đã xáo trộn ngẫu nhiên |
| `hint` | Gợi ý ngắn |
| `definition` | Định nghĩa tiếng Anh |
| `timer_seconds` | Thời gian giới hạn theo CEFR: A1/A2=90s, B1/B2=60s, C1/C2=45s |
| `xp_value` | XP nhận được: A1=10, B1=15, B2=20, C1/C2=25-30 |

### 3.2 Matching Game
**Endpoint:** `GET /api/v1/games/matching`

Nối từ với định nghĩa (4 cặp mỗi game, shuffle ngẫu nhiên cả 2 cột).

### 3.3 Spelling Bee
**Endpoint:** `GET /api/v1/games/spelling-bee`

Nghe phiên âm IPA và gõ lại từ đúng chính tả.

| Field | Mô tả |
|-------|--------|
| `ipa_pronunciation` | Phiên âm IPA của từ |
| `hint` | Gợi ý chữ cái đầu |
| `letter_count` | Số chữ cái (để người chơi biết độ dài) |

### 3.4 Hangman
**Endpoint:** `GET /api/v1/games/hangman`

Đoán từ từng chữ cái một, giới hạn 6 lần sai.

| Field | Mô tả |
|-------|--------|
| `masked_display` | Từ dưới dạng `_ _ _ _ _` |
| `hint` | Gợi ý chủ đề/ngữ cảnh |
| `max_attempts` | Luôn = 6 (6 phần của hình treo cổ) |

Fallback: nếu DB trống, dùng `HANGMAN_FALLBACK_WORDS` embedded (8 từ A1-B2).

### 3.5 Fill in the Blank
**Endpoint:** `GET /api/v1/games/fill-blank`

Điền vào chỗ trống với câu hỏi ngữ pháp theo CEFR level.

**Ngân hàng câu hỏi FILL_BLANK_BANK:**

| Level | Số Câu | Chủ Đề Ngữ Pháp |
|-------|--------|----------------|
| A1 | 14 câu | To Be, Present Simple, Possessives, Articles |
| A2 | 14 câu | Past Simple, Going to, Comparatives |
| B1 | 13 câu | Present Perfect, Modals (must/can/should/might) |
| B2 | 13 câu | Passive Voice, 2nd/3rd Conditional, Unless |

### 3.6 Grammar Quiz
**Endpoint:** `GET /api/v1/games/grammar-quiz`

Quiz 4 lựa chọn theo chủ đề ngữ pháp có phân loại (topic) rõ ràng.

**Ngân hàng câu hỏi GRAMMAR_QUIZ_BANK:**

| Level | Số Câu | Topics |
|-------|--------|--------|
| A1 | 12 câu | `to_be`, `present_simple` |
| A2 | 11 câu | `past_simple`, `future` |
| B1 | 10 câu | `present_perfect`, `modals` |
| B2 | 12 câu | `passive`, `conditional` |

---

## 4. XP và Timer Theo CEFR

```python
TIMER_BY_LEVEL = {
    "A1": 90, "A2": 90,     # Người mới — thời gian rộng
    "B1": 60, "B2": 60,     # Trung cấp
    "C1": 45, "C2": 45,     # Nâng cao — áp lực cao hơn
}

XP_BY_LEVEL = {
    "A1": 10, "A2": 10,
    "B1": 15, "B2": 20,
    "C1": 25, "C2": 30,
}
```

---

## 5. Ngân Hàng Từ Vựng (Game Words Seed)

Bộ từ vựng embedded `GAME_WORDS_SEED` gồm **38 từ** có đầy đủ metadata:

| Field | Mô tả |
|-------|--------|
| `word` | Từ tiếng Anh |
| `definition` | Định nghĩa tiếng Anh |
| `hint` | Gợi ý ngắn gọn |
| `cefr_level` | A1 → C1 |
| `category` | animals, food, education, travel, home, emotions, transport... |
| `letter_count` | Số chữ cái |
| `xp_value` | XP khi trả lời đúng (5-30 XP) |
| `ipa_pronunciation` | Phiên âm quốc tế |
| `example_sentence` | Câu ví dụ trong context |
| `synonyms` | Danh sách từ đồng nghĩa |
| `vietnamese_translation` | Bản dịch tiếng Việt |

**Phân phối từ theo level:**
- A1: 12 từ (cat, dog, book, house, apple, water, school, happy, chair, bread, table, car)
- A2: 8 từ (travel, garden, family, kitchen, museum, weather, healthy, library)
- B1: 8 từ (adventure, knowledge, necessary, environment, government, education, beautiful, successful)
- B2: 6 từ (enormous, purchase, ancient, journey, accomplish, accommodation)
- C1: 4 từ (sophisticated, unprecedented, conscientious, ambiguous)

---

## 6. Luồng Randomization

Mỗi request trả về câu hỏi ngẫu nhiên từ DB hoặc bank:

```
Request: GET /api/v1/games/word-scramble?level=B1
    │
    ├─ Query: SELECT * FROM game_words WHERE cefr_level='B1' ORDER BY RANDOM() LIMIT 1
    ├─ Scramble: random.shuffle(list(word))  # Python random
    └─ Response: {scrambled, hint, definition, timer_seconds, xp_value, ...}
```

---

## 7. Auto-Seed Logic

Khi DB `game_words` trống (lần đầu deploy), hệ thống tự động seed `GAME_WORDS_SEED`:

```python
# Trong games.py — auto-seed on first request
if not db_has_game_words:
    for word_data in GAME_WORDS_SEED:
        session.add(GameWord(**word_data))
    session.commit()
```

---

## 8. Tích Hợp Flutter

**Màn hình:** `GamesHubScreen` → individual game screens → `GameResultScreen`

**XP Flow:**
```
Game hoàn thành → score được tính
→ POST /api/v1/xp/add {user_id, xp_amount, source: "game"}
→ XP lưu vào UserXP profile
→ AchievementCheckerService kiểm tra các trigger liên quan đến game
→ Flutter nhận response → hiển thị kết quả + animation XP
```

---

## 9. API Endpoints Đầy Đủ

| Method | Endpoint | Mô Tả |
|--------|---------|--------|
| GET | `/api/v1/games/word-scramble` | Word Scramble game data |
| GET | `/api/v1/games/matching` | Matching game pairs |
| GET | `/api/v1/games/spelling-bee` | Spelling Bee word + IPA |
| GET | `/api/v1/games/hangman` | Hangman masked word |
| GET | `/api/v1/games/fill-blank` | Fill Blank question |
| GET | `/api/v1/games/grammar-quiz` | Grammar Quiz question |

**Query params chung:**
- `level` — CEFR level (A1/A2/B1/B2/C1/C2)
- `category` — Lọc theo chủ đề (animals/food/travel...)

---

---

## Cập Nhật Stability 2026-06-15

### Server-Authoritative XP

Tất cả XP từ game đi qua `xp_service.py::award_xp_transaction()`. Client không thể submit `base_xp` tuỳ ý — server tính lại từ game type và CEFR level. `source_id` (game session ID) là khoá dedup để chống duplicate award.

### Pronunciation Service (Flutter)

`GamePronunciationService` ưu tiên `audio_url` từ payload, fallback TTS qua `VoiceRemoteDataSource`, emit `AudioError` state nếu cả hai đều fail.

### Flutter Game Tests (104 tests)

- `game_completion_test.dart` — 13 tests: tất cả 6 game types, XP earned/capped/failed
- `game_load_state_test.dart` — 13 tests: loading spinner, error + retry
- `game_accessibility_test.dart` — 14 tests: semantic labels, touch targets ≥40px, 375/390/768px
- `game_pronunciation_service_test.dart` — 10 tests: audio_url prefer, TTS fallback, error

### Acceptance Verification

Xem `docs/qa/game-system-acceptance.md` để biết kết quả automated tests và checklist manual validation.

---

*Tham khảo: [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md) | [RPT-025](RPT-025_GAMIFICATION_XP_SYSTEM.md)*
