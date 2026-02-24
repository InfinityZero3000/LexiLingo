"""
Seed shop items for LexiLingo.
Run: python -m scripts.seed_shop_items
"""
import asyncio
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select
from app.core.database import AsyncSessionLocal, engine
from app.models.gamification import ShopItem


SHOP_ITEMS = [
    # ── Streak & Protection ──────────────────────────────────────────
    {
        "name": "Streak Freeze",
        "description": "Bảo vệ chuỗi ngày học của bạn khi bỏ lỡ 1 ngày. Tự động kích hoạt khi bạn không hoàn thành bài học trong ngày.",
        "item_type": "streak_freeze",
        "price_gems": 200,
        "icon_url": "https://img.icons8.com/3d-fluency/94/snowflake.png",
        "effects": {"duration_days": 1, "auto_activate": True},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Super Streak Freeze",
        "description": "Bảo vệ chuỗi ngày học trong 3 ngày liên tiếp. Phù hợp khi bạn đi du lịch hoặc bận rộn.",
        "item_type": "streak_freeze",
        "price_gems": 500,
        "icon_url": "https://img.icons8.com/3d-fluency/94/ice-cream-sundae.png",
        "effects": {"duration_days": 3, "auto_activate": True},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Streak Repair",
        "description": "Khôi phục chuỗi ngày học đã mất. Sử dụng sau khi chuỗi bị gián đoạn để lấy lại tiến độ.",
        "item_type": "streak_repair",
        "price_gems": 350,
        "icon_url": "https://img.icons8.com/3d-fluency/94/toolbox.png",
        "effects": {"restore_streak": True},
        "is_available": True,
        "stock_quantity": None,
    },

    # ── XP Boost ─────────────────────────────────────────────────────
    {
        "name": "Double XP (1 giờ)",
        "description": "Nhân đôi XP nhận được trong 1 giờ. Hoàn hảo cho phiên học tập ngắn nhưng hiệu quả.",
        "item_type": "double_xp",
        "price_gems": 150,
        "icon_url": "https://img.icons8.com/3d-fluency/94/star.png",
        "effects": {"duration_hours": 1, "multiplier": 2},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Double XP (4 giờ)",
        "description": "Nhân đôi XP nhận được trong 4 giờ. Lý tưởng cho buổi ôn tập dài.",
        "item_type": "double_xp",
        "price_gems": 400,
        "icon_url": "https://img.icons8.com/3d-fluency/94/shooting-stars.png",
        "effects": {"duration_hours": 4, "multiplier": 2},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Triple XP (1 giờ)",
        "description": "Nhân ba XP nhận được trong 1 giờ! Vật phẩm hiếm cho những ai muốn tăng tốc.",
        "item_type": "triple_xp",
        "price_gems": 350,
        "icon_url": "https://img.icons8.com/3d-fluency/94/firework-explosion.png",
        "effects": {"duration_hours": 1, "multiplier": 3},
        "is_available": True,
        "stock_quantity": 50,
    },

    # ── Hint & Help ──────────────────────────────────────────────────
    {
        "name": "Gói Gợi ý (5 lần)",
        "description": "Nhận 5 gợi ý để sử dụng trong các bài tập khó. Mỗi gợi ý giúp bạn loại bỏ 1 đáp án sai.",
        "item_type": "hint_pack",
        "price_gems": 100,
        "icon_url": "https://img.icons8.com/3d-fluency/94/light-on.png",
        "effects": {"hints": 5, "type": "eliminate_wrong"},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Gói Gợi ý Pro (15 lần)",
        "description": "Nhận 15 gợi ý cao cấp. Bao gồm gợi ý loại bỏ đáp án sai và hiển thị chữ cái đầu tiên.",
        "item_type": "hint_pack",
        "price_gems": 250,
        "icon_url": "https://img.icons8.com/3d-fluency/94/idea.png",
        "effects": {"hints": 15, "type": "pro"},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Bỏ qua câu hỏi (3 lần)",
        "description": "Cho phép bỏ qua 3 câu hỏi khó mà không mất điểm trong bài kiểm tra.",
        "item_type": "skip_question",
        "price_gems": 180,
        "icon_url": "https://img.icons8.com/3d-fluency/94/forward.png",
        "effects": {"skips": 3},
        "is_available": True,
        "stock_quantity": None,
    },

    # ── Hearts & Lives ───────────────────────────────────────────────
    {
        "name": "Tim đầy",
        "description": "Nạp đầy tim (mạng sống). Tiếp tục học mà không cần chờ tim hồi phục.",
        "item_type": "heart_refill",
        "price_gems": 120,
        "icon_url": "https://img.icons8.com/3d-fluency/94/like.png",
        "effects": {"hearts": 5, "full_refill": True},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Tim vô hạn (24h)",
        "description": "Không giới hạn số tim trong 24 giờ. Học bao nhiêu cũng được mà không lo hết mạng!",
        "item_type": "unlimited_hearts",
        "price_gems": 450,
        "icon_url": "https://img.icons8.com/3d-fluency/94/valentine-heart-monitor.png",
        "effects": {"duration_hours": 24, "unlimited": True},
        "is_available": True,
        "stock_quantity": None,
    },

    # ── Cosmetics & Profile ──────────────────────────────────────────
    {
        "name": "Khung avatar Vàng",
        "description": "Khung avatar sang trọng màu vàng kim. Thể hiện đẳng cấp của bạn với bạn bè.",
        "item_type": "avatar_frame",
        "price_gems": 600,
        "icon_url": "https://img.icons8.com/3d-fluency/94/circled-user-male-skin-type-4.png",
        "effects": {"frame_id": "gold", "rarity": "rare"},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Khung avatar Kim cương",
        "description": "Khung avatar cực hiếm với hiệu ứng lấp lánh kim cương. Chỉ dành cho người chơi thực thụ.",
        "item_type": "avatar_frame",
        "price_gems": 1500,
        "icon_url": "https://img.icons8.com/3d-fluency/94/expensive-2.png",
        "effects": {"frame_id": "diamond", "rarity": "legendary", "animated": True},
        "is_available": True,
        "stock_quantity": 20,
    },
    {
        "name": "Biệt danh tùy chỉnh",
        "description": "Đổi màu và font chữ cho tên hiển thị của bạn trên bảng xếp hạng.",
        "item_type": "custom_name",
        "price_gems": 300,
        "icon_url": "https://img.icons8.com/3d-fluency/94/name-tag.png",
        "effects": {"custom_color": True, "custom_font": True},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Gói nhãn dán Động vật",
        "description": "Bộ 12 nhãn dán động vật dễ thương để sử dụng trong chat và bình luận.",
        "item_type": "sticker_pack",
        "price_gems": 250,
        "icon_url": "https://img.icons8.com/3d-fluency/94/cat.png",
        "effects": {"stickers": 12, "pack_id": "animals"},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Gói nhãn dán Du lịch",
        "description": "Bộ 10 nhãn dán chủ đề du lịch thế giới. Khám phá các biểu tượng nổi tiếng!",
        "item_type": "sticker_pack",
        "price_gems": 250,
        "icon_url": "https://img.icons8.com/3d-fluency/94/around-the-globe.png",
        "effects": {"stickers": 10, "pack_id": "travel"},
        "is_available": True,
        "stock_quantity": None,
    },

    # ── Power-ups ────────────────────────────────────────────────────
    {
        "name": "Thời gian thêm (+30s)",
        "description": "Thêm 30 giây cho các bài kiểm tra có giới hạn thời gian. Không bao giờ bị hết giờ!",
        "item_type": "time_extension",
        "price_gems": 80,
        "icon_url": "https://img.icons8.com/3d-fluency/94/clock.png",
        "effects": {"extra_seconds": 30},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Bùa may mắn",
        "description": "Tăng 25% cơ hội nhận thưởng bonus sau mỗi bài học trong 2 giờ.",
        "item_type": "luck_charm",
        "price_gems": 200,
        "icon_url": "https://img.icons8.com/3d-fluency/94/clover.png",
        "effects": {"duration_hours": 2, "bonus_chance_percent": 25},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Lá chắn điểm",
        "description": "Bảo vệ XP không bị trừ khi trả lời sai trong 1 bài học tiếp theo.",
        "item_type": "score_shield",
        "price_gems": 130,
        "icon_url": "https://img.icons8.com/3d-fluency/94/shield.png",
        "effects": {"duration_lessons": 1, "prevent_xp_loss": True},
        "is_available": True,
        "stock_quantity": None,
    },

    # ── Special / Limited ────────────────────────────────────────────
    {
        "name": "Hộp quà bí ẩn",
        "description": "Mở ra để nhận 1 vật phẩm ngẫu nhiên! Có thể là vật phẩm hiếm hoặc siêu hiếm.",
        "item_type": "mystery_box",
        "price_gems": 300,
        "icon_url": "https://img.icons8.com/3d-fluency/94/gift.png",
        "effects": {"random_item": True, "rarities": ["common", "rare", "epic"]},
        "is_available": True,
        "stock_quantity": 100,
    },
    {
        "name": "Vé mở khóa khóa học",
        "description": "Mở khóa bất kỳ 1 khóa học Premium nào. Trải nghiệm nội dung độc quyền!",
        "item_type": "course_unlock",
        "price_gems": 2000,
        "icon_url": "https://img.icons8.com/3d-fluency/94/key.png",
        "effects": {"unlock_premium_course": True, "quantity": 1},
        "is_available": True,
        "stock_quantity": None,
    },
    {
        "name": "Badge tùy chỉnh",
        "description": "Tạo 1 huy hiệu riêng với tên và biểu tượng do bạn chọn để hiển thị trên hồ sơ.",
        "item_type": "custom_badge",
        "price_gems": 800,
        "icon_url": "https://img.icons8.com/3d-fluency/94/medal2.png",
        "effects": {"custom_badge": True, "slots": 1},
        "is_available": True,
        "stock_quantity": 30,
    },
]


async def seed():
    async with AsyncSessionLocal() as session:
        # Check existing
        result = await session.execute(select(ShopItem))
        existing = result.scalars().all()
        existing_names = {item.name for item in existing}
        print(f"Existing shop items: {len(existing)}")

        added = 0
        for item_data in SHOP_ITEMS:
            if item_data["name"] in existing_names:
                print(f"  [SKIP] {item_data['name']} (already exists)")
                continue

            item = ShopItem(**item_data)
            session.add(item)
            added += 1
            print(f"  [ADD]  {item_data['name']} — {item_data['price_gems']} gems ({item_data['item_type']})")

        await session.commit()
        print(f"\nDone! Added {added} new shop items. Total: {len(existing) + added}")


if __name__ == "__main__":
    asyncio.run(seed())
