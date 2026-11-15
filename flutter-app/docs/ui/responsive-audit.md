# Responsive audit: learner app at 390 / 768 / 1440 px

Baseline taken 2026-11-15 on `dev` at `4c0f2c77`, before any responsive fix. It lists what fails; the fixes land in later PRs and this file is updated until the tables are empty.

## How it was measured

A profile web build (`flutter build web --profile --dart-define=API_BASE_URL=http://localhost:8000/api/v1`, with `.env.development` as `.env`) served on `localhost:8080`, driven by Playwright through Flutter's semantics tree (`tool/responsive_audit/`). Each screen was captured at 390x844, 768x1024 and 1440x900, and every tappable semantics node smaller than 44 px in either direction was recorded.

```bash
export AUDIT_EMAIL=... AUDIT_PASSWORD=...
python tool/responsive_audit/crawl.py <out>/shots 390     # then 768, 1440
python tool/responsive_audit/crawl_auth.py <out>/shots
```

Traps: a release build always talks to production (`ApiConfig._mustUseProductionBackend`), so use `--profile`. Local login answers 503 while the Redis container is stopped. The seeded `@lexilingo.test` accounts cannot log in at all: the login schema rejects the reserved `.test` domain, so the audit account needs a real-looking domain.

## Correction: measure 390 and 768 as a phone, not as a desktop browser

The first pass ran every width in desktop Chrome. Flutter chooses `MaterialTapTargetSize.shrinkWrap` and compact density on desktop platforms, so stock buttons, chips and switches measured 40 px or less there while being 48 px on a real phone. Of the 106 controls listed below, about 30 were under 44 px on a phone; the rest were an artefact of the platform. The crawler now emulates a phone below 840 px (touch, mobile user agent, `navigator.platform`), and the table below is kept as the desktop-browser reading.

The fixes are in #702: the touch theme now applies by width, so a narrow desktop window matches a phone, and the hand-built controls get a 44 px hit area. After it, the phone-emulated crawl finds one control under 44 px: the stock `Switch` at 60x40.

## Coverage

35 screens at all three sizes: the five tabs, notifications, course detail, study plan, flashcard review, speaking practice, streak calendar, daily goal, level and daily-challenge sheets, YouTube, news, games, podcast, books, vocabulary library, course filter, category, Lexi history and topics, IELTS tests, shop, leaderboard, friends, progress, settings, premium, edit profile, gems, welcome and login.

**Second pass (secondary screens), at 390 and 768 px as a phone:** full roadmap, a lesson question, book detail and reader, podcast show, video player, news article, word of the day, vocabulary decks, three games (word scramble, fill in the blank, matching), speaking from Practice, the Practice listening card, premium, register, forgot password and onboarding. No page-level horizontal scroll on any of them.

What that pass found and how it ended:

| Screen | Problem | Status |
|---|---|---|
| Book detail | The premium lock (a centred 36 px icon) covered the middle of the "Tải về để đọc offline" label | Fixed: a 20 px badge at the end of the button |
| News article | Vocabulary chips 29 px tall | Fixed: 44 px hit area |
| Login, register, onboarding | Language button 34 px tall | Fixed |
| Welcome | Globe button 40x40 with no accessible label | Fixed: 44 px, labelled "Ngôn ngữ" |
| Register | "Đăng nhập" link 87x24 | Fixed |
| Streak calendar | Reminder switch forced to `shrinkWrap` (60x40) | Fixed |
| Lexi practice hint, deck delete | Compact density / removed constraints | Fixed |
| Video player | Each transcript word is a 20 px tall tap target | Left as is: these are words inside running text, the inline-target exception in WCAG 2.5.8. A 44 px row per word would make the transcript unreadable |

**Still not captured:** quizzes beyond the first lesson question, an IELTS paper (no published test in the local data) and a shop purchase. A lesson's answered state was not captured because the check button stays disabled until an option is chosen and the crawler did not select one.

## Result by requirement

| Requirement | Result |
|---|---|
| No page-level horizontal scroll | Pass on all 35 screens at all three sizes. Horizontal movement exists only in carousels and chip rows. |
| Tables stack below 768 px | Nothing to convert on the captured screens: the app has no table widget, and its row lists (progress stats, leaderboard, gem history, friends) are already single-column cards at 390 px. The league had one participant in the test data, so a full leaderboard is unverified. |
| Tap targets at least 44x44 | In a desktop browser: fails on 27 of 35 screens, 106 controls. On a phone: about 30 controls, all hand-built. See the correction above. |
| Layout at 768 px | **Weak.** Phone layouts are stretched to the full width; see below. |
| Desktop layout unchanged | Baseline screenshots at 1440 px are the reference for later PRs. |

## Tap targets under 44 px

Sizes are `390 / 768 / 1440`; `ok` means 44 px or more at that size. Semantics bounds are what was measured, which is what assistive technology and the hit test both use.

| Screen | Control [width x height] |
|---|---|
| Home | Tiếp tục học [322x40 / 700x31 / 1112x40]; Xem kế hoạch [121x36 / 121x36 / 121x36] |
| Học tập | B2 [18x87 / 40x242 / ok]; Bộ lọc [40x40 / 40x40 / 40x40]; Xem tất cả [99x32 / 99x32 / 99x32] |
| Lexi (chat) | Bật/tắt giọng nói [40x40 / 40x40 / 40x40]; Cho mình ví dụ [121x40 / 121x40 / 121x40]; Chủ đề [117x35 / 306x35 / 547x35]; Cuộc trò chuyện mới [40x40 / 40x40 / 40x40]; Dịch sang tiếng Việt [50x40 / 154x40 / 154x40]; Giải thích đơn giản hơn [171x40 / 171x40 / 171x40]; Lịch sử phiên [40x40 / 40x40 / 40x40]; Trò chuyện [117x35 / 306x35 / 547x35] |
| Tài khoản | 240 [72x31 / 72x31 / 72x31]; Cài đặt [40x40 / 40x40 / 40x40]; Gold [71x31 / 71x31 / 71x31]; Nâng cấp Premium [40x40 / 40x40 / 40x40]; Sửa hồ sơ [124x35 / 124x35 / 124x35] |
| Thông báo | Đánh dấu đã đọc tất cả [40x40 / 40x40 / 40x40] |
| Ôn từ vựng (flashcard) | Luyện nói [40x40 / 40x40 / 40x40]; Nghe [40x40 / 40x40 / 40x40]; Tốc độ đọc: 1x [40x40 / 40x40 / 40x40]; button [40x40 / 40x40 / 40x40] |
| Luyện nói | Câu ngẫu nhiên [40x40 / 40x40 / 40x40]; Cấp quyền micro [183x32 / 183x32 / 183x32]; Hello, how are you today? [232x34 / 232x34 / 232x34]; I love learning languages. [ok / 138x34 / 138x34]; Nghe mẫu [290x42 / 660x42 / 660x42]; Nice to meet you! [110x34 / 155x34 / 155x34]; Quay lại [40x40 / 40x40 / 40x40]; What is your name? [ok / 171x34 / 171x34]; button [40x40 / 40x40 / 40x40] |
| Lịch điểm danh (dialog) | button [22x22 / 22x22 / 22x22]; switch [54x36 / 54x36 / 54x36] |
| YouTube | Xem tất cả [106x36 / 106x36 / 106x36] |
| Trò chơi | A1 [71x34 / 71x34 / 71x34]; A2 [52x34 / 52x34 / 52x34]; B1 [51x34 / 51x34 / 51x34]; B2 [51x34 / 51x34 / 51x34]; C1 [51x34 / 51x34 / 51x34]; C2 [42x34 / 51x34 / 51x34]; Quay lại [40x40 / 40x40 / 40x40] |
| Thư viện từ vựng | button [44x28 / 44x28 / 44x28] |
| Bộ lọc khoá học (sheet) | A → Z [ok / 89x27 / 89x37]; Academic English [145x37 / 145x37 / 145x37]; Advanced [95x37 / 95x37 / 95x37]; All [62x35 / 62x35 / 62x35]; Beginner [89x37 / 89x37 / 89x37]; Business English [137x37 / 137x37 / 137x37]; Conversation [ok / 116x37 / 116x37]; Default [ok / 114x27 / 114x35]; EN [124x37 / 124x37 / 124x37]; ES [180x37 / 180x37 / 180x37]; Elementary [104x37 / 104x37 / 105x37]; General English [132x37 / 132x37 / 132x37]; Grammar [ok / 92x37 / 92x37]; Highest XP [ok / 122x27 / 122x37]; IELTS Preparation [149x37 / 149x37 / 149x37]; Intermediate [117x37 / 117x37 / 117x37]; Most Lessons [ok / 137x27 / 137x37]; Pre-Intermediate [144x37 / 144x37 / 144x37]; Travel English [120x37 / 120x37 / 120x37]; Tất cả [86x35 / 86x35 / 86x35]; Upper-Intermediate [162x37 / 162x37 / 162x37]; VI [123x37 / 123x37 / 123x37]; Vocabulary [ok / 104x37 / 104x37]; switch [ok / 60x40 / 60x40] |
| Danh mục khoá học | Grid view [40x40 / 40x40 / 40x40]; Hiển thị menu [56x40 / 56x40 / 56x40]; Quay lại [40x40 / 40x40 / 40x40] |
| Chi tiết khoá học | 25 bài học [124x34 / 124x34 / 124x34]; 540 phút [115x34 / 115x34 / 115x34]; 700 XP [102x34 / 102x34 / 102x34]; A1 [71x34 / 71x34 / 71x34]; Quay lại [40x40 / 40x40 / 40x40]; Xem lộ trình đầy đủ [358x32 / 736x32 / 1148x32]; en [71x34 / 71x34 / 71x34] |
| Lexi: lịch sử phiên | Hiển thị menu [40x40 / 40x40 / 40x40]; Phiên mới [40x40 / 40x40 / 40x40] |
| Lexi: chủ đề | Chủ đề [175x35 / 364x35 / 605x35]; Thử lại [94x32 / 94x32 / 94x32]; Trò chuyện [175x35 / 364x35 / 605x35]; Trò chuyện với Lexi [180x32 / 180x32 / 180x32] |
| Đề thi thử IELTS | Quay lại [40x40 / 40x40 / 40x40] |
| Cửa hàng | 240 [81x37 / 81x37 / 81x37]; Quay lại [40x40 / 40x40 / 40x40] |
| Bảng xếp hạng | Quay lại [40x40 / 40x40 / 40x40] |
| Bạn bè | Làm mới gợi ý [40x40 / 40x40 / 40x40]; Quay lại [40x40 / 40x40 / 40x40]; Theo dõi [83x32 / 83x32 / 83x32]; Tìm bạn bè [124x40 / 124x40 / 124x40] |
| Tiến độ | Quay lại [40x40 / 40x40 / 40x40] |
| Cài đặt | button [40x40 / 40x40 / 40x40]; switch [60x40 / 60x40 / 60x40] |
| Premium | Khôi phục mua hàng [167x32 / 167x32 / 167x32]; button [40x40 / 40x40 / 40x40] |
| Sửa hồ sơ | Lưu [56x32 / 56x32 / 56x32]; button [42x42 / 42x42 / 42x42] |
| Đá quý | Quay lại [40x40 / 40x40 / 40x40]; Xem tất cả [99x32 / 99x32 / 99x32] |
| Chào mừng | button [40x40 / 40x40 / 40x40] |
| Đăng nhập | Quên mật khẩu? [137x32 / 137x32 / 137x32]; VI [59x34 / 59x34 / 59x34]; button [40x40 / 40x40 / 40x40]; checkbox [40x40 / 40x40 / 40x40]; Đăng ký miễn phí [144x30 / 144x32 / ok] |

The same few sources account for most rows:

| Source | Measured | Where it shows |
|---|---|---|
| Back button | 40x40 | every pushed screen |
| App-bar icon buttons (filter, settings, premium, history, new chat, voice, refresh, close) | 40x40 | Learn, Account, Lexi, Notifications, Friends, Premium, flashcards, speaking |
| Filter and level chips | 34-37 px tall | course filter sheet (24 chips), games, course detail meta chips, speaking phrases |
| Text buttons ("Xem tất cả", "Theo dõi", "Lưu", "Khôi phục mua hàng", "Quên mật khẩu?") | 30-36 px tall | Home, Learn, Friends, Edit profile, Premium, Login |
| Lexi mode switch and quick replies | 35 and 40 px tall | Lexi chat and topics |
| Primary buttons with a custom height ("Tiếp tục học", "Xem lộ trình đầy đủ", "Nghe mẫu") | 31-42 px tall | Home, course detail, speaking |
| Switches | 54x36, 60x40 | streak calendar, settings |
| Calendar close button | 22x22 | streak calendar dialog |

## Clipped text at 390 px

| Screen | What is wrong |
|---|---|
| Friends | The middle tab label is cut ("Người theo dõ"); every suggestion subtitle is ellipsised ("Cùng trình độ • XP tương …"). |
| Leaderboard | The learner's own name is ellipsised ("Nhung Ngu…") beside the "YOU" badge and the XP pill. |
| Shop | The third category tab is cut at the screen edge with no hint that the row scrolls. |

## Layout at 768 px

At 768 px the app still uses the bottom bar and the phone layout (the rail starts at 840 px), so content is stretched rather than rearranged:

| Screen | What is wrong |
|---|---|
| News | One article per row; each image is about 300 px tall, so one and a half cards fill the screen. |
| Home | Single column at full width; the Explore carousel starts under the bottom bar. |
| Practice, study plan, notifications, settings, progress | Full-width single-column rows with the label far left and the value or chevron far right. |
| Course detail | The hero image fills the width (about 290 px tall) and pushes the roadmap below the fold. |
| Podcast, books | Shelves keep phone-sized covers (about 75-90 px), leaving the right half of each row empty. |
| Lexi history | The drawer covers the left third and the chat behind it is cut mid-word. |

## Observations outside the three requirements

- **Category screen shows the wrong count (fixed in #701).** "Xem tất cả" on a category with 5 courses opened a page saying "Có 0 khóa học" (768 px), and a 2-course category listed 1 (1440 px). This looks like data or filtering, not layout.
- Book covers and the featured-book banner rendered blank in some captures. A second crawl showed them loaded; it was slow images, not layout.
- At 1440 px every pushed screen replaces the navigation rail, and the category screen keeps its content in the left 580 px. Both are existing desktop behaviour and are left alone, per the "desktop does not change" rule.
- The Home "continue learning" card looked doubled in two captures; it is the cross-fade between its two messages caught mid-animation, not a layout fault.
