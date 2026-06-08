from app.core.shop_catalog import AVATAR_SHOP_ITEMS, CONSUMABLE_SHOP_ITEMS, SHOP_CATALOG


def test_catalog_contains_affordable_consumables_and_many_avatars():
    assert len(CONSUMABLE_SHOP_ITEMS) == 9
    assert len(AVATAR_SHOP_ITEMS) == 36
    assert len(SHOP_CATALOG) == 45

    prices = {item["name"]: item["price_gems"] for item in CONSUMABLE_SHOP_ITEMS}
    assert prices["Hint Pack (5)"] == 12
    assert prices["Heart Refill"] == 15
    assert prices["Double XP (1 hour)"] == 25
    assert prices["Streak Freeze"] == 25


def test_avatar_catalog_uses_adventurer_urls_and_low_price_tiers():
    assert {item["price_gems"] for item in AVATAR_SHOP_ITEMS} == {10, 15, 20}
    assert all(item["item_type"] == "avatar" for item in AVATAR_SHOP_ITEMS)
    assert all("/adventurer/svg?seed=" in item["icon_url"] for item in AVATAR_SHOP_ITEMS)
    assert all(
        item["effects"]["avatar_url"] == item["icon_url"]
        for item in AVATAR_SHOP_ITEMS
    )
