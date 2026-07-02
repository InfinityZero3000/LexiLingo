"""Canonical shop catalog used by migrations and development seeding."""

from typing import Any


def _avatar_item(seed: str, price: int) -> dict[str, Any]:
    avatar_url = f"https://api.dicebear.com/7.x/adventurer/svg?seed={seed}"
    return {
        "name": f"{seed} Avatar",
        "description": f"Exclusive {seed} profile avatar",
        "item_type": "avatar",
        "price_gems": price,
        "icon_url": avatar_url,
        "effects": {"avatar_url": avatar_url},
        "is_available": True,
    }


CONSUMABLE_SHOP_ITEMS: list[dict[str, Any]] = [
    {
        "name": "Hint Pack (5)",
        "description": "Add 5 hints to your active lesson",
        "item_type": "hint_pack",
        "price_gems": 12,
        "effects": {"quantity": 5},
        "is_available": True,
    },
    {
        "name": "Hint Pack (10)",
        "description": "Add 10 hints to your active lesson",
        "item_type": "hint_pack",
        "price_gems": 20,
        "effects": {"quantity": 10},
        "is_available": True,
    },
    {
        "name": "Heart Refill",
        "description": "Restore your active lesson to 3 hearts",
        "item_type": "heart_refill",
        "price_gems": 15,
        "effects": {"hearts": 3},
        "is_available": True,
    },
    {
        "name": "Double XP (1 hour)",
        "description": "Earn double XP for 1 hour",
        "item_type": "double_xp",
        "price_gems": 25,
        "effects": {"duration_hours": 1, "multiplier": 2},
        "is_available": True,
    },
    {
        "name": "Double XP (2 hours)",
        "description": "Earn double XP for 2 hours",
        "item_type": "double_xp",
        "price_gems": 40,
        "effects": {"duration_hours": 2, "multiplier": 2},
        "is_available": True,
    },
    {
        "name": "Double XP (4 hours)",
        "description": "Earn double XP for 4 hours",
        "item_type": "double_xp",
        "price_gems": 65,
        "effects": {"duration_hours": 4, "multiplier": 2},
        "is_available": True,
    },
    {
        "name": "Triple XP (1 hour)",
        "description": "Earn triple XP for 1 hour",
        "item_type": "double_xp",
        "price_gems": 50,
        "effects": {"duration_hours": 1, "multiplier": 3},
        "is_available": True,
    },
    {
        "name": "Streak Freeze",
        "description": "Add one streak freeze",
        "item_type": "streak_freeze",
        "price_gems": 25,
        "effects": {"quantity": 1},
        "is_available": True,
    },
    {
        "name": "Streak Freeze Pack (3)",
        "description": "Add three streak freezes",
        "item_type": "streak_freeze",
        "price_gems": 60,
        "effects": {"quantity": 3},
        "is_available": True,
    },
    {
        "name": "Time Freeze",
        "description": "Pause the countdown timer for 10 seconds in any timed game",
        "item_type": "time_freeze",
        "price_gems": 10,
        "effects": {"seconds": 10},
        "is_available": True,
    },
    {
        "name": "Extra Time",
        "description": "Add 20 seconds straight to the clock in any timed game",
        "item_type": "extra_time",
        "price_gems": 15,
        "effects": {"seconds": 20},
        "is_available": True,
    },
    {
        "name": "Skip Token",
        "description": "Skip the current word or question with no penalty",
        "item_type": "skip_token",
        "price_gems": 12,
        "effects": {},
        "is_available": True,
    },
    {
        "name": "Magnifying Glass",
        "description": "Free reveal: the next letter, or eliminate 2 wrong options",
        "item_type": "reveal_hint",
        "price_gems": 8,
        "effects": {"mode": "letter"},
        "is_available": True,
    },
    {
        "name": "Quick Translate",
        "description": "Reveal the Vietnamese translation of the current word",
        "item_type": "translate_hint",
        "price_gems": 8,
        "effects": {"mode": "translation"},
        "is_available": True,
    },
    {
        "name": "Shield",
        "description": "Negate the next wrong answer or life loss",
        "item_type": "mistake_shield",
        "price_gems": 18,
        "effects": {},
        "is_available": True,
    },
    {
        "name": "Extra Heart",
        "description": "Start Hangman with one extra life",
        "item_type": "extra_heart",
        "price_gems": 15,
        "effects": {"lives": 1},
        "is_available": True,
    },
    {
        "name": "Lucky Clover",
        "description": "30% chance to auto-correct your next wrong answer",
        "item_type": "lucky_clover",
        "price_gems": 20,
        "effects": {"chance": 0.3},
        "is_available": True,
    },
    {
        "name": "Score Multiplier",
        "description": "Double your in-game score for the rest of this session",
        "item_type": "score_multiplier",
        "price_gems": 22,
        "effects": {"multiplier": 2},
        "is_available": True,
    },
    {
        "name": "Pair Swap",
        "description": "Undo one wrong match in Matching Game for a free retry",
        "item_type": "pair_swap",
        "price_gems": 10,
        "effects": {},
        "is_available": True,
    },
]

GAME_POWERUP_ITEM_TYPES: list[str] = [
    "time_freeze",
    "extra_time",
    "skip_token",
    "reveal_hint",
    "translate_hint",
    "mistake_shield",
    "extra_heart",
    "lucky_clover",
    "score_multiplier",
    "pair_swap",
]

_AVATAR_SEEDS_BY_TIER = {
    10: [
        "Sunny",
        "Coco",
        "Pip",
        "Mochi",
        "Daisy",
        "Benji",
        "Kiki",
        "Toby",
        "Poppy",
        "Remy",
        "Skye",
        "Winnie",
    ],
    15: [
        "Sage",
        "Indie",
        "Raven",
        "Maple",
        "Echo",
        "River",
        "Juno",
        "Orion",
        "Cleo",
        "Phoenix",
        "Robin",
        "Storm",
    ],
    20: [
        "Cosmo",
        "Galaxy",
        "Comet",
        "Solstice",
        "Velvet",
        "Onyx",
        "Saffron",
        "Zephyr",
        "Lyric",
        "Quest",
        "Vesper",
        "Zenith",
    ],
}

AVATAR_SHOP_ITEMS = [
    _avatar_item(seed, price)
    for price, seeds in _AVATAR_SEEDS_BY_TIER.items()
    for seed in seeds
]

SHOP_CATALOG = CONSUMABLE_SHOP_ITEMS + AVATAR_SHOP_ITEMS

