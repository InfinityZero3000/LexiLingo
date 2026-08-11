# RPT-029 — Kiểm Kê File Giao Diện Flutter (Loại Trừ Admin)

> **Cập nhật:** 2026-06-21
> **Liên quan:** [`RPT-005_FLUTTER_MODULE_CATALOG.md`](./RPT-005_FLUTTER_MODULE_CATALOG.md) (catalog module ở mức feature), [`RPT-022_FLUTTER_APP_ARCHITECTURE.md`](./RPT-022_FLUTTER_APP_ARCHITECTURE.md) (kiến trúc tổng thể)

---

## 1. Mục Đích

Báo cáo này kiểm kê **chính xác** toàn bộ file giao diện (UI rendering) trong `flutter-app/lib/`, phục vụ cho chiến dịch cải cách giao diện ("biến app giống một game hơn", dùng icon tự tạo thay icon thư viện Material). Phạm vi: **toàn app, trừ `features/admin/*`** (module quản trị riêng, không thuộc app người dùng cuối).

> **Lưu ý sửa số liệu:** một báo cáo miệng trước đó trong cùng phiên làm việc đã nói "~190 file giao diện" — số đó thực chất là **tổng số file trong toàn bộ lớp `presentation/`**, bao gồm cả `providers/` (state management) và `utils/` (helper, không vẽ UI). Báo cáo này tách rõ ba nhóm để số liệu phản ánh đúng "file giao diện" theo nghĩa hẹp.

---

## 2. Phương Pháp Kiểm Kê

- Quét toàn bộ `*.dart` dưới `lib/features/*/presentation/` và `lib/core/`, loại `lib/features/admin/**`.
- Phân loại theo subfolder thực tế trong từng feature:
  - **File giao diện thật** (UI rendering — đối tượng cải cách): `pages/`, `screens/`, `widgets/`, `painters/`
  - **Không phải giao diện** (giữ nguyên khi redesign): `providers/` (state/ViewModel), `utils/` (resolver/helper logic)
- Core dùng chung (`lib/core/widgets/`, `lib/core/theme/`, `lib/core/services/theme_preference_store.dart`) tính riêng vì áp dụng cho mọi feature.
- Độ ưu tiên redesign mỗi feature = số lượt gọi `Icons.*` (Material icon) hiện có trong feature đó — càng nhiều, càng cần thay icon tự tạo (`GameIcon`, xem mục 6).

---

## 3. Số Liệu Tổng Quan

| Nhóm | Số file |
|---|---|
| **File giao diện thật** (pages + screens + widgets + painters), trong `features/*` (trừ admin) | **134** |
| Core/Shared UI (`core/widgets/` × 22 + `core/theme/app_theme.dart` + `core/services/theme_preference_store.dart`) | **24** |
| **Tổng file giao diện thật (core + feature)** | **158** |
| Providers (state management, *không* phải giao diện) | 31 |
| Utils (resolver/helper, *không* phải giao diện) | 2 |
| **Tổng toàn bộ lớp `presentation/` (giao diện + provider + utils)** | 167 |

Breakdown theo loại subfolder trong `features/*/presentation/`:

| Loại | Số file |
|---|---|
| `widgets/` | 74 |
| `screens/` | 39 |
| `providers/` | 31 |
| `pages/` | 20 |
| `utils/` | 2 |
| `painters/` | 1 |

---

## 4. Core / Shared UI (áp dụng toàn app — ưu tiên cải cách đầu tiên)

| File | Vai trò |
|---|---|
| `core/theme/app_theme.dart` | Theme tokens trung tâm (màu, `AppColorRoles`, gradient) |
| `core/services/theme_preference_store.dart` | Lưu lựa chọn dark/light mode |
| `core/widgets/game_icon.dart` | **Mới** — registry `GameIcon` enum, map icon bán → asset `assets/icon-library/`, fallback Material khi chưa có art |
| `core/widgets/widgets.dart` | Barrel export toàn bộ widget dùng chung |
| `core/widgets/app_button.dart` | Button chuẩn |
| `core/widgets/animated_components.dart` / `animated_ui_components.dart` / `custom_animations.dart` | Hiệu ứng animation dùng chung |
| `core/widgets/animation_showcase_page.dart` | Trang demo animation (dev tool) |
| `core/widgets/badge_generator.dart` / `cefr_badge.dart` | Sinh badge cấp độ CEFR |
| `core/widgets/celebration_widget.dart` | Hiệu ứng ăn mừng (level up, hoàn thành) |
| `core/widgets/empty_state_widget.dart` / `error_widget.dart` | Trạng thái rỗng / lỗi chuẩn |
| `core/widgets/glassmorphic_components.dart` | Hiệu ứng glassmorphism (progress ring...) |
| `core/widgets/language_switcher_button.dart` | Đổi ngôn ngữ app |
| `core/widgets/lottie_animation_widget.dart` / `lottie_loading_widget.dart` | Lottie animation wrapper |
| `core/widgets/network_avatar_image.dart` | Avatar tải từ network |
| `core/widgets/premium_gate.dart` | Khoá tính năng premium |
| `core/widgets/quick_save_selection_area.dart` / `quick_save_word_sheet.dart` | Lưu nhanh từ vựng |
| `core/widgets/skeleton_loading.dart` | Skeleton/shimmer loading |
| `core/widgets/stagger_list.dart` | List có animation stagger |

---

## 5. File Giao Diện Theo Feature (134 file, sort theo số lượng)

| # | Feature | File giao diện | Lượt dùng `Icons.*` (độ ưu tiên đổi icon) | Trạng thái redesign |
|---|---|---|---|---|
| 1 | `games` | 16 | 32 | Chưa làm |
| 2 | `gamification` | 15 | 53 | Chưa làm |
| 3 | `vocabulary` | 11 | 91 | Chưa làm |
| 4 | `learning` | 10 | 72 | Chưa làm |
| 5 | `chat` | 10 | 162 (cao nhất) | Chưa làm |
| 6 | `auth` | 10 | 57 | Chưa làm |
| 7 | `progress` | 9 | 64 | Chưa làm |
| 8 | `voice` | 7 | 33 | Chưa làm |
| 9 | `podcast` | 7 | 36 | Chưa làm |
| 10 | `books` | 7 | 37 | Chưa làm |
| 11 | `profile` | 4 | 61 | Chưa làm |
| 12 | `lexi_chat` | 4 | 20 | Chưa làm |
| 13 | `achievements` | 4 | 62 | Chưa làm |
| 14 | `news` | 3 | 28 | Chưa làm |
| 15 | `level` | 3 | 20 | Chưa làm |
| 16 | `home` | 3 | 28 (↓ từ 58) | ✅ **Pilot xong** |
| 17 | `course` | 3 | 76 | Chưa làm |
| 18 | `youtube` | 2 | 45 | Chưa làm |
| 19 | `user` | 2 | 32 | Chưa làm |
| 20 | `notifications` | 2 | 15 | Chưa làm |
| 21 | `social` | 1 | 23 | Chưa làm |
| 22 | `premium` | 1 | 6 | Chưa làm |

> `course` có 76 lượt `Icons.*` chỉ trong 3 file UI — đa số nằm ở `home_page.dart` (đã giảm khi redesign Home) hiển thị card khoá học; cần kiểm tra lại khi vào lượt `course`.

### Danh sách đầy đủ từng file (bấm để mở rộng từng feature)

<details><summary><strong>features/achievements</strong> — 4 file</summary>

- `features/achievements/presentation/screens/achievements_screen.dart`
- `features/achievements/presentation/screens/screens.dart`
- `features/achievements/presentation/widgets/achievement_unlock_overlay.dart`
- `features/achievements/presentation/widgets/achievement_widgets.dart`

</details>

<details><summary><strong>features/auth</strong> — 10 file</summary>

- `features/auth/presentation/pages/email_verification_pending_page.dart`
- `features/auth/presentation/pages/forgot_password_page.dart`
- `features/auth/presentation/pages/login_page.dart`
- `features/auth/presentation/pages/onboarding_page.dart`
- `features/auth/presentation/pages/pre_auth_questions_page.dart`
- `features/auth/presentation/pages/register_page.dart`
- `features/auth/presentation/pages/reset_password_page.dart`
- `features/auth/presentation/pages/welcome_page.dart`
- `features/auth/presentation/widgets/auth_gradient_background.dart`
- `features/auth/presentation/widgets/auth_wrapper.dart`

</details>

<details><summary><strong>features/books</strong> — 7 file</summary>

- `features/books/presentation/screens/book_detail_screen.dart`
- `features/books/presentation/screens/book_library_screen.dart`
- `features/books/presentation/screens/book_quiz_screen.dart`
- `features/books/presentation/screens/book_reader_screen.dart`
- `features/books/presentation/widgets/book_card.dart`
- `features/books/presentation/widgets/bookmark_button.dart`
- `features/books/presentation/widgets/reader_controls.dart`

</details>

<details><summary><strong>features/chat</strong> — 10 file</summary>

- `features/chat/presentation/pages/story_selection_page.dart`
- `features/chat/presentation/pages/topic_chat_page.dart`
- `features/chat/presentation/widgets/audio_waveform.dart`
- `features/chat/presentation/widgets/chat_ui_components.dart`
- `features/chat/presentation/widgets/educational_hints_widgets.dart`
- `features/chat/presentation/widgets/markdown_message_content.dart`
- `features/chat/presentation/widgets/message_bubble.dart`
- `features/chat/presentation/widgets/session_list_drawer.dart`
- `features/chat/presentation/widgets/topic_card.dart`
- `features/chat/presentation/widgets/widgets.dart`

</details>

<details><summary><strong>features/course</strong> — 3 file</summary>

- `features/course/presentation/screens/category_detail_screen.dart`
- `features/course/presentation/screens/course_detail_screen.dart`
- `features/course/presentation/screens/course_list_screen.dart`

</details>

<details><summary><strong>features/games</strong> — 16 file</summary>

- `features/games/presentation/screens/fill_blank_screen.dart`
- `features/games/presentation/screens/game_result_screen.dart`
- `features/games/presentation/screens/games_hub_screen.dart`
- `features/games/presentation/screens/grammar_quiz_screen.dart`
- `features/games/presentation/screens/hangman_screen.dart`
- `features/games/presentation/screens/matching_game_screen.dart`
- `features/games/presentation/screens/spelling_bee_screen.dart`
- `features/games/presentation/screens/word_scramble_screen.dart`
- `features/games/presentation/widgets/daily_challenge_card.dart`
- `features/games/presentation/widgets/game_card.dart`
- `features/games/presentation/widgets/game_load_state.dart`
- `features/games/presentation/widgets/hangman_figure.dart`
- `features/games/presentation/widgets/letter_tile.dart`
- `features/games/presentation/widgets/level_up_dialog.dart`
- `features/games/presentation/widgets/streak_indicator.dart`
- `features/games/presentation/widgets/xp_progress_bar.dart`

</details>

<details><summary><strong>features/gamification</strong> — 15 file</summary>

- `features/gamification/presentation/screens/leaderboard_screen.dart`
- `features/gamification/presentation/screens/league_ceremony_screen.dart`
- `features/gamification/presentation/screens/shop_screen.dart`
- `features/gamification/presentation/screens/wallet_screen.dart`
- `features/gamification/presentation/widgets/active_boosts_bar.dart`
- `features/gamification/presentation/widgets/boost_purchase_animation.dart`
- `features/gamification/presentation/widgets/gem_counter.dart`
- `features/gamification/presentation/widgets/leaderboard_podium.dart`
- `features/gamification/presentation/widgets/league_card.dart`
- `features/gamification/presentation/widgets/level_rank_display.dart`
- `features/gamification/presentation/widgets/rank_asset_icon.dart`
- `features/gamification/presentation/widgets/rank_badge.dart`
- `features/gamification/presentation/widgets/rank_up_dialog.dart`
- `features/gamification/presentation/widgets/shop_item_card.dart`
- `features/gamification/presentation/widgets/starter_reward_dialog.dart`

</details>

<details><summary><strong>features/home</strong> — 3 file (✅ pilot redesign đã xong)</summary>

- `features/home/presentation/pages/home_page.dart`
- `features/home/presentation/pages/main_screen.dart` *(bottom nav dùng `phosphor_flutter`, không phải Material icon — chưa cần đổi)*
- `features/home/presentation/widgets/home_ui_components.dart`

</details>

<details><summary><strong>features/learning</strong> — 10 file</summary>

- `features/learning/presentation/painters/roadmap_path_painter.dart`
- `features/learning/presentation/screens/learning_roadmap_screen.dart`
- `features/learning/presentation/screens/learning_session_screen.dart`
- `features/learning/presentation/widgets/lesson_content_widget.dart`
- `features/learning/presentation/widgets/lesson_speaking_recorder.dart`
- `features/learning/presentation/widgets/lesson_ui_components.dart`
- `features/learning/presentation/widgets/premium_exercise_widgets.dart`
- `features/learning/presentation/widgets/quiz_widget.dart`
- `features/learning/presentation/widgets/roadmap_header_widget.dart`
- `features/learning/presentation/widgets/roadmap_node_widget.dart`

</details>

<details><summary><strong>features/level</strong> — 3 file</summary>

- `features/level/presentation/widgets/level_widgets.dart`
- `features/level/presentation/widgets/proficiency_card.dart`
- `features/level/presentation/widgets/proficiency_radar_chart.dart`

</details>

<details><summary><strong>features/lexi_chat</strong> — 4 file</summary>

- `features/lexi_chat/presentation/pages/lexi_chat_page.dart`
- `features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart`
- `features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart`
- `features/lexi_chat/presentation/widgets/lexi_typing_indicator.dart`

</details>

<details><summary><strong>features/news</strong> — 3 file</summary>

- `features/news/presentation/screens/news_detail_screen.dart`
- `features/news/presentation/screens/news_list_screen.dart`
- `features/news/presentation/screens/news_quiz_screen.dart`

</details>

<details><summary><strong>features/notifications</strong> — 2 file</summary>

- `features/notifications/presentation/pages/notifications_page.dart`
- `features/notifications/presentation/widgets/empty_notification_widget.dart`

</details>

<details><summary><strong>features/podcast</strong> — 7 file</summary>

- `features/podcast/presentation/screens/podcast_detail_screen.dart`
- `features/podcast/presentation/screens/podcast_explore_screen.dart`
- `features/podcast/presentation/screens/podcast_player_screen.dart`
- `features/podcast/presentation/widgets/audio_player_controls.dart`
- `features/podcast/presentation/widgets/episode_tile.dart`
- `features/podcast/presentation/widgets/podcast_card.dart`
- `features/podcast/presentation/widgets/transcript_panel.dart`

</details>

<details><summary><strong>features/premium</strong> — 1 file</summary>

- `features/premium/presentation/screens/paywall_screen.dart`

</details>

<details><summary><strong>features/profile</strong> — 4 file</summary>

- `features/profile/presentation/pages/edit_profile_screen.dart`
- `features/profile/presentation/pages/learning_stats_pages.dart`
- `features/profile/presentation/pages/profile_page.dart`
- `features/profile/presentation/widgets/profile_ui_components.dart`

</details>

<details><summary><strong>features/progress</strong> — 9 file</summary>

- `features/progress/presentation/screens/my_progress_screen.dart`
- `features/progress/presentation/widgets/course_progress_card.dart`
- `features/progress/presentation/widgets/daily_challenges_widget.dart`
- `features/progress/presentation/widgets/daily_reward_dialog.dart`
- `features/progress/presentation/widgets/points_calendar_dialog.dart`
- `features/progress/presentation/widgets/progress_card.dart`
- `features/progress/presentation/widgets/streak_milestone_overlay.dart`
- `features/progress/presentation/widgets/streak_widget.dart`
- `features/progress/presentation/widgets/xp_line_chart.dart`

</details>

<details><summary><strong>features/social</strong> — 1 file</summary>

- `features/social/presentation/screens/social_screen.dart`

</details>

<details><summary><strong>features/user</strong> — 2 file</summary>

- `features/user/presentation/pages/legal_page.dart`
- `features/user/presentation/pages/settings_page.dart`

</details>

<details><summary><strong>features/vocabulary</strong> — 11 file</summary>

- `features/vocabulary/presentation/pages/vocab_library_page.dart`
- `features/vocabulary/presentation/screens/flashcard_review_screen.dart`
- `features/vocabulary/presentation/screens/session_complete_screen.dart`
- `features/vocabulary/presentation/screens/vocabulary_speaking_practice_screen.dart`
- `features/vocabulary/presentation/screens/word_of_day_screen.dart`
- `features/vocabulary/presentation/widgets/daily_review_card.dart`
- `features/vocabulary/presentation/widgets/flashcard_widget.dart`
- `features/vocabulary/presentation/widgets/review_quality_buttons.dart`
- `features/vocabulary/presentation/widgets/session_header.dart`
- `features/vocabulary/presentation/widgets/vocab_word_detail_sheet.dart`
- `features/vocabulary/presentation/widgets/word_of_day_card.dart`

</details>

<details><summary><strong>features/voice</strong> — 7 file</summary>

- `features/voice/presentation/screens/voice_practice_screen.dart`
- `features/voice/presentation/widgets/playback_controls.dart`
- `features/voice/presentation/widgets/pronunciation_score_card.dart`
- `features/voice/presentation/widgets/record_button.dart`
- `features/voice/presentation/widgets/speak_button.dart`
- `features/voice/presentation/widgets/speech_recognition_button.dart`
- `features/voice/presentation/widgets/tts_speed_selector.dart`

</details>

<details><summary><strong>features/youtube</strong> — 2 file</summary>

- `features/youtube/presentation/screens/youtube_explore_screen.dart`
- `features/youtube/presentation/screens/youtube_player_screen.dart`

</details>

---

## 6. Hệ Thống Icon Tự Tạo (`GameIcon`)

Hạ tầng đã dựng tại `lib/core/widgets/game_icon.dart`, nguồn art tại `assets/icon-library/` (gitignore — xem [`.gitignore`](../../flutter-app/.gitignore), cần tự giải nén `assets/icon-library.zip` khi build máy mới) + `assets/learning-icons/` (đã track).

**Đã có asset thật (24 icon):** star, trophy, xp, gem, crown, checkmark, giftBox, treasureChest, speechBubble, settings, padlockUnlocked, clock, lessonBoard, playArrow, fastForward, rewind, backArrow, speakerOn, speakerMuted, lightBulb, heart, flashcards, grammar, listening, quizzes, speaking, vocabulary, streakFire, bolt, gameController, notificationBell, calendar, sunMorning, moonNight, book.

**Còn thiếu, đang fallback Material icon:** `newspaper`, `headphones`, `sunsetAfternoon`, `translate`.

Cách dùng: `AppGameIcon(GameIcon.trophy, size: 24)` thay cho `Icon(Icons.emoji_events)`. Icon chưa có asset vẫn render được (fallback), nên có thể wire toàn bộ feature trước, bổ sung art sau mà không cần sửa lại UI lần hai.

---

## 7. Đề Xuất Thứ Tự Cải Cách Tiếp Theo

Dựa trên độ ưu tiên (mục 5) — feature càng nhiều `Icons.*` + càng hay gặp trong hành trình hằng ngày của user nên làm trước:

1. **`learning`** — roadmap zigzag là màn hình lõi của trải nghiệm "giống game", đã có layout game sẵn, chỉ cần thay icon + polish thêm.
2. **`games`** — trung tâm 7 mini-game, nơi cảm giác "game" cần rõ nhất.
3. **`gamification`** — shop, leaderboard, wallet, đã mang tinh thần game nhẹ.
4. **`vocabulary`** — nhiều `Icons.*` nhất sau chat (91 lượt), tần suất dùng cao (flashcard, ôn tập hằng ngày).
5. **`chat` / `lexi_chat`** — nhiều `Icons.*` nhất tuyệt đối (162) nhưng bản chất là giao diện chat, mức độ "game hoá" cần cân nhắc riêng (tránh làm rối giao diện hội thoại).
6. Các feature còn lại theo bảng mục 5.

---

## 8. Quy Tắc Bảo Trì

- File này nên cập nhật lại số liệu mỗi khi một feature hoàn thành redesign (đổi cột "Trạng thái redesign" ở mục 5, cập nhật lại lượt `Icons.*` còn lại).
- Khi thêm icon mới vào `GameIcon`, cập nhật danh sách "Đã có asset thật" / "Còn thiếu" ở mục 6.
- Không tính `features/admin/*` vào báo cáo này — module quản trị có vòng đời thiết kế riêng.
