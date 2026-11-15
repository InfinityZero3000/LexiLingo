import asyncio, sys, os, json
sys.path.insert(0, os.path.dirname(__file__))
from audit import *
T = {"learn": "^Học tập", "lexi": "^Lexi", "practice": "^Luyện tập", "account": "^Tài khoản"}
# name, labels clicked from a fresh Home ("@scroll" scrolls), extra scrolled shots
SCREENS = [
 ("01-home", [], 2),
 ("02-learn", [T["learn"]], 1),
 ("03-lexi", [T["lexi"]], 0),
 ("04-practice", [T["practice"]], 1),
 ("05-account", [T["account"]], 1),
 ("10-notifications", ["^Thông báo"], 0),
 ("11-roadmap", ["^Tiếp tục học$"], 1),
 ("12-study-plan", ["^Xem kế hoạch"], 0),
 ("13-vocab-review", ["^Ôn từ vựng"], 0),
 ("14-speaking", ["^Luyện nói"], 0),
 ("15-streak-calendar", ["^Chuỗi"], 0),
 ("16-daily-goal", ["^Mục tiêu hôm nay"], 0),
 ("17-level", ["^Cấp độ"], 0),
 ("18-daily-challenges", ["^Thử thách hàng ngày"], 0),
 ("19-youtube", ["^YouTube$"], 1),
 ("20-news", ["^Tin tức$"], 1),
 ("21-games", ["^Trò chơi$"], 1),
 ("22-podcast", ["^Podcast$"], 1),
 ("23-books", ["^Sách$"], 1),
 ("24-vocab-library", ["^Từ vựng$"], 1),
 ("30-learn-filter", [T["learn"], "^Bộ lọc"], 0),
 ("31-category", [T["learn"], "^Xem tất cả"], 1),
 ("32-course-detail", [T["learn"], "IELTS Foundation"], 1),
 ("40-lexi-history", [T["lexi"], "^Lịch sử phiên"], 0),
 ("41-lexi-topics", [T["lexi"], "^Chủ đề$"], 1),
 ("50-ielts", [T["practice"], "^Đề thi thử IELTS"], 1),
 ("60-shop", [T["account"], "^Cửa hàng"], 1),
 ("61-leaderboard", [T["account"], "^Xếp hạng"], 1),
 ("62-friends", [T["account"], "^Bạn bè"], 0),
 ("63-progress", [T["account"], "^Tiến độ"], 2),
 ("64-settings", [T["account"], "^Cài đặt"], 2),
 ("65-premium", [T["account"], "^Nâng cấp Premium"], 1),
 ("66-edit-profile", [T["account"], "^Sửa hồ sơ"], 0),
 ("67-gems", [T["account"], r"^\d+$"], 0),
 # secondary screens (second pass)
 ("70-roadmap", [T["learn"], "IELTS Foundation", "Xem lộ trình"], 1),
 ("71-book-detail", ["^Sách$", "Grimms"], 1),
 ("72-book-reader", ["^Sách$", "Grimms", "Bắt đầu đọc"], 0),
 ("73-podcast-show", ["^Podcast$", "BBC Learning English Stories"], 1),
 ("74-video-player", ["^YouTube$", "Xem ngay"], 0),
 ("75-news-article", ["^Tin tức$", "FAA says"], 2),
 ("76-game-scramble", ["^Trò chơi$", "Word Scramble"], 0),
 ("77-game-fill", ["^Trò chơi$", "Fill in the Blank"], 0),
 ("78-game-matching", ["^Trò chơi$", "Matching Game"], 0),
 ("79-word-of-day", ["^Từ vựng hôm nay"], 1),
 ("80-vocab-decks", ["^Từ vựng$", "Thẻ ghi nhớ"], 0),
 ("81-speaking-from-practice", [T["practice"], "^Nói"], 0),
 ("82-practice-listen", [T["practice"], "^Nghe"], 0),
 ("85-roadmap", [T["learn"], "@scroll", "Daily Vocabulary Starter", "Xem lộ trình"], 0),
 ("86-lesson", [T["learn"], "@scroll", "Daily Vocabulary Starter", "Xem lộ trình", "^1$"], 0),
]
async def main():
    out, size = sys.argv[1], sys.argv[2]
    only = sys.argv[3:] 
    async with async_playwright() as p:
        b, ctx, a = await open_app(p, size, out)
        await ensure_login(a)
        for name, path, scrolls in SCREENS:
            if only and not any(o in name for o in only): continue
            try:
                await a.page.goto("http://localhost:8080/"); await a.page.wait_for_timeout(6500)
                for step in path:
                    if step == '@scroll': await a.scroll(600)
                    else: await a.click(step, wait=2800)
                r = await a.shot(name, wait=900)
                for i in range(scrolls):
                    await a.scroll(a.h * 0.8); await a.shot(f"{name}-s{i+1}")
                print(size, name, "ok", "small=%d over=%d" % (len(r["small"]), len(r["overflow_right"])), flush=True)
            except Exception as e:
                print(size, name, "MISS", str(e)[:90], flush=True)
        await b.close()
asyncio.run(main())
