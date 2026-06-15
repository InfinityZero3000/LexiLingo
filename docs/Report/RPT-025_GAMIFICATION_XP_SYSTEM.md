# RPT-025 — Hệ Thống Gamification: XP, Streak, Wallet, Shop, Leaderboard

> **Cập nhật:** 2026-06-15 | **Nguồn:** `backend-service/app/routes/gamification.py`, `app/services/xp_service.py`, `app/models/gamification.py`

---

## 1. Tổng Quan

Hệ thống Gamification của LexiLingo là lớp động lực học tập, bao gồm **5 hệ thống con** hoạt động theo sự kiện (event-driven): XP, Streak, Wallet, Shop và Leaderboard. Toàn bộ được thiết kế để chống grinding (chống spam để tăng điểm mà không học thật).

---

## 2. Kiến Trúc Tổng Thể

```
User Action (học bài, chat, game, quiz)
        │
        ▼
XP Service ──► Achievement Checker ──► Notification
        │
        ├─ XP Pool (UserXP: total_xp, level_xp, level_number)
        ├─ Streak Tracker (UserStreak: current_streak, longest_streak)
        ├─ Wallet (UserWallet: gems, coins, total_earned)
        └─ Leaderboard (Redis cache + DB rank_service)
```

---

## 3. Hệ Thống XP (Experience Points)

### 3.1 Nguồn XP

| Sự Kiện | XP Nhận Được |
|---------|-------------|
| Hoàn thành lesson | 20-50 XP (theo độ khó) |
| Chat với AI (message) | 5-10 XP |
| Game mini (theo CEFR) | 10-30 XP |
| News quiz | 15 XP |
| Vocabulary review | 5 XP/từ |
| Daily login streak | 10 XP + streak bonus |
| Achievement unlock | 50-200 XP |

### 3.2 Level System

XP tích lũy vào `level_xp`. Khi đủ ngưỡng, user lên level:

```
Level 1:    0 - 100 XP
Level 2:  100 - 250 XP    (+150)
Level 3:  250 - 500 XP    (+250)
Level 4:  500 - 900 XP    (+400)
...
Level N:  Exponential growth (x1.5 mỗi level)
```

### 3.3 Chống XP Grinding

Hệ thống có các biện pháp chống spam:
- **Cooldown per action type**: Không tính XP nếu cùng action < 30s
- **Daily XP cap**: Giới hạn XP tối đa/ngày theo subscription tier
- **CEFR gate**: Một số XP bonus chỉ unlock khi đạt cấp độ nhất định

### 3.4 API XP

| Method | Endpoint | Mô Tả |
|--------|---------|--------|
| POST | `/api/v1/xp/add` | Thêm XP cho user |
| GET | `/api/v1/xp/profile` | Xem XP + level hiện tại |
| GET | `/api/v1/xp/history` | Lịch sử XP |
| GET | `/api/v1/xp/leaderboard` | Bảng xếp hạng XP |

---

## 4. Hệ Thống Streak (Chuỗi Ngày Học)

### 4.1 Logic Streak

```python
# Mỗi ngày user đăng nhập và học ít nhất 1 lesson/game/chat
if today > last_activity_date:
    if today == last_activity_date + 1 day:
        current_streak += 1      # Streak tiếp tục
        longest_streak = max(current_streak, longest_streak)
    elif today > last_activity_date + 1 day:
        current_streak = 1       # Streak reset
    last_activity_date = today
```

### 4.2 Streak Rewards

| Chuỗi | Phần Thưởng |
|-------|------------|
| 3 ngày | 10 Gems + 30 XP bonus |
| 7 ngày | 25 Gems + 70 XP bonus |
| 14 ngày | 50 Gems + 150 XP bonus |
| 30 ngày | 100 Gems + 300 XP + Achievement "30-Day Warrior" |

### 4.3 Streak Model (PostgreSQL)

```python
class UserStreak:
    user_id: str
    current_streak: int         # Ngày liên tiếp hiện tại
    longest_streak: int         # Kỷ lục dài nhất
    last_activity_date: date    # Ngày hoạt động gần nhất
    total_active_days: int      # Tổng số ngày đã học
    streak_shield_count: int    # Số lần bảo vệ streak
```

---

## 5. Hệ Thống Wallet và Gems

### 5.1 Tổng Quan

`UserWallet` quản lý 2 loại currency:

| Currency | Dùng Để | Nguồn |
|----------|---------|-------|
| **Gems** 💎 | Mua item trong Shop | Streak rewards, Achievements, Mua thêm |
| **Coins** 🪙 | Item nhỏ, power-up | XP milestones, Daily login |

### 5.2 Wallet API

| Method | Endpoint | Mô Tả |
|--------|---------|--------|
| GET | `/api/v1/gamification/wallet` | Xem số dư wallet |
| POST | `/api/v1/gamification/wallet/add` | Thêm currency (internal) |
| POST | `/api/v1/gamification/wallet/spend` | Tiêu currency (khi mua item) |
| GET | `/api/v1/gamification/wallet/transactions` | Lịch sử giao dịch |

### 5.3 ItemEffectsService

Service `item_effects_service.py` xử lý hiệu ứng khi mua item:

| Item Type | Hiệu Ứng |
|-----------|----------|
| `streak_shield` | Bảo vệ streak 1 lần khi bỏ lỡ |
| `xp_boost_2x` | Nhân đôi XP trong 24 giờ |
| `hint_pack` | Thêm lượt gợi ý trong game |
| `avatar_frame` | Cosmetic, thay đổi giao diện avatar |
| `theme_unlock` | Mở theme màu sắc mới |

---

## 6. Hệ Thống Achievement (13 Trigger Types)

### 6.1 Kiến Trúc AchievementCheckerService

Nằm trong `backend-service/app/services/__init__.py`. Đây là **stateless service** — chạy check sau mỗi action.

```python
class AchievementCheckerService:
    async def check_all_triggers(self, user_id: str, event: dict):
        for trigger_type in TRIGGER_TYPES:
            await self._check_trigger(user_id, event, trigger_type)
```

### 6.2 13 Loại Achievement Trigger

| Trigger Type | Điều Kiện Ví Dụ | Achievement Ví Dụ |
|-------------|----------------|-------------------|
| `lesson_complete` | Hoàn thành N bài | "First Lesson", "10 Lessons" |
| `streak_milestone` | Đạt streak N ngày | "7-Day Streak", "30-Day Warrior" |
| `xp_milestone` | Tổng XP đạt N | "100 XP Club", "XP Legend" |
| `level_up` | Lên level N | "Level 5 Achieved" |
| `game_complete` | Chơi N game thành công | "Gamer", "Game Master" |
| `vocabulary_mastered` | Nắm vững N từ | "Word Collector", "Vocabulary Pro" |
| `chat_sessions` | Hoàn thành N chat | "Chatty Learner" |
| `pronunciation_score` | Đạt score phát âm >= X | "Pronunciation Star" |
| `cefr_upgrade` | Lên 1 level CEFR | "CEFR Climber", "C1 Achiever" |
| `content_complete` | Đọc N bài báo/podcast | "News Reader", "Podcast Fan" |
| `social_action` | Thêm N bạn bè | "Social Butterfly" |
| `daily_goal` | Hoàn thành daily goal N ngày | "Goal Getter" |
| `special_event` | Sự kiện đặc biệt (holiday, launch) | "Early Bird" |

### 6.3 Achievement Response

```json
{
  "achievement_id": "streak_7_days",
  "title": "7-Day Warrior",
  "description": "Học liên tục 7 ngày",
  "icon": "trophy_streak",
  "xp_reward": 70,
  "gems_reward": 25,
  "unlocked_at": "2026-04-24T14:30:00Z"
}
```

---

## 7. Hệ Thống Leaderboard

### 7.1 Cấu Trúc

Leaderboard có 3 phạm vi:

| Phạm Vi | Mô Tả | Refresh |
|---------|--------|---------|
| `weekly` | Top 50 theo XP tuần | Mỗi ngày 00:00 UTC |
| `monthly` | Top 100 theo XP tháng | Ngày 1 hàng tháng |
| `all_time` | Top 100 mọi thời đại | Real-time |

### 7.2 RankService

`backend-service/app/services/rank_service.py`:
- Tính rank của user dựa trên XP
- Cache Redis cho top 50 để giảm DB query
- Trả về rank, xp, avatar, display_name, level

### 7.3 API Leaderboard

| Method | Endpoint | Mô Tả |
|--------|---------|--------|
| GET | `/api/v1/gamification/leaderboard` | Top users (weekly) |
| GET | `/api/v1/gamification/leaderboard/monthly` | Top users (monthly) |
| GET | `/api/v1/gamification/leaderboard/my-rank` | Rank hiện tại của user |

---

## 8. Hệ Thống Shop

### 8.1 Danh Mục Item

Items được tổ chức theo category:

| Category | Items |
|----------|-------|
| `power_ups` | XP boost, Hint pack, Time freeze |
| `streak_protection` | Streak Shield |
| `cosmetics` | Avatar frames, Themes, Badges |
| `premium_content` | Unlock advanced lessons |

### 8.2 Purchase Flow

```
Flutter ShopScreen → chọn item
    │
    ├─ GET /api/v1/gamification/shop/items (danh sách item + giá)
    ├─ POST /api/v1/gamification/shop/purchase {item_id}
    │    ├─ Kiểm tra số dư Wallet
    │    ├─ Trừ currency (wallet/spend)
    │    ├─ Ghi vào UserInventory
    │    └─ Kích hoạt ItemEffectsService nếu auto-apply
    └─ Response: {success, remaining_gems, item_activated}
```

---

## 9. Database Models (PostgreSQL)

```python
# Các models chính trong gamification.py
UserXP         → user_id, total_xp, level_xp, level_number, last_xp_at
UserStreak     → user_id, current_streak, longest_streak, last_activity_date
UserWallet     → user_id, gems, coins, total_earned_gems
UserAchievement → user_id, achievement_id, unlocked_at, xp_reward
Achievement    → id, title, description, trigger_type, condition_json, xp_reward, gems_reward
ShopItem       → id, name, description, category, price_gems, price_coins, effect_type
UserInventory  → user_id, item_id, quantity, activated_at, expires_at
```

---

## 10. Tích Hợp Với Các Module Khác

```
Games Engine  ──► XP Service ──► AchievementChecker
AI Chat       ──► XP Service ──► Streak Tracker
Learning      ──► XP Service ──► Leaderboard
Proficiency   ──► AchievementChecker (CEFR upgrade)
Daily Goal    ──► Streak Tracker ──► Wallet (streak rewards)
```

---

---

## Cập Nhật Security Model 2026-06-15

### source_id Requirement

Các `source_id` repeat-sensitive (`game`, `lesson`, `daily_challenge`) bắt buộc phải có `source_id` khi gọi `award_xp_transaction()`. Thiếu `source_id` → HTTP 422. Cơ chế này ngăn client tạo XP không có session server-issued.

```python
REPEAT_SENSITIVE_SOURCES = frozenset({"game", "lesson", "daily_challenge"})
```

### Test Coverage

`tests/test_xp_service.py` — 70 tests bao gồm:
- source_id validation cho tất cả 3 repeat-sensitive sources
- Daily XP cap per source type
- Streak multiplier calculation
- Level progression thresholds
- Achievement unlock triggers

*Tham khảo: [RPT-024](RPT-024_GAMES_ENGINE.md) | [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md)*
