"""Gem balance, unlocked badges and badge CDN rows must never be served stale."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import select

from app.core import cache
from app.core.redis import RedisClient
from app.crud.gamification import WalletCRUD
from app.models.gamification import Achievement
from app.services.achievement_checker_service import AchievementCheckerService

@pytest.fixture
def live_cache():
    """Response cache on (pytest normally disables it), Redis down, memory fallback."""
    cache._memory_cache.clear()
    with patch.object(cache, "_cache_disabled", return_value=False), patch.object(
        RedisClient, "get_instance", new=AsyncMock(return_value=None)
    ):
        yield
    cache._memory_cache.clear()


class _FakeRedis:
    def __init__(self, data=None):
        self.data = data or {}

    async def get(self, key):
        return self.data.get(key)

    async def delete(self, *keys):
        return sum(self.data.pop(k, None) is not None for k in keys)

    async def scan_iter(self, match, count):
        prefix = match[:-1]
        for key in list(self.data):
            if key.startswith(prefix):
                yield key


async def test_delete_cached_drops_the_memory_copy(live_cache):
    await cache.set_cached("k:1", {"a": 1}, ttl=60)
    assert await cache.get_cached("k:1") == {"a": 1}

    await cache.delete_cached("k:1")

    assert await cache.get_cached("k:1") is None


async def test_delete_cached_drops_the_memory_copy_when_redis_is_up(live_cache):
    await cache.set_cached("k:1", {"a": 1}, ttl=60)
    redis = _FakeRedis()
    with patch.object(RedisClient, "get_instance", new=AsyncMock(return_value=redis)):
        await cache.delete_cached("k:1")
    assert cache._memory_get("k:1") is None


async def test_invalidate_cache_drops_memory_copies_when_redis_is_up(live_cache):
    await cache.set_cached("pfx:a", 1, ttl=60)
    redis = _FakeRedis({"pfx:b": "2"})
    with patch.object(RedisClient, "get_instance", new=AsyncMock(return_value=redis)):
        deleted = await cache.invalidate_cache("pfx")
    assert deleted == 1
    assert cache._memory_get("pfx:a") is None


async def test_redis_miss_is_not_answered_from_a_leftover_memory_copy(live_cache):
    await cache.set_cached("k:1", {"a": 1}, ttl=60)
    with patch.object(RedisClient, "get_instance", new=AsyncMock(return_value=_FakeRedis())):
        assert await cache.get_cached("k:1") is None


async def test_wallet_reflects_a_write_immediately(
    live_cache, async_client, auth_headers, db_session, test_user
):
    first = await async_client.get("/api/v1/gamification/wallet", headers=auth_headers)
    assert first.json()["data"]["gems"] == 0

    # Same writer the ranking agent and the achievement checker use: no cache call.
    await WalletCRUD.add_gems(
        db_session, test_user.id, 25, source="test", description="grant", commit=False
    )
    await db_session.commit()

    second = await async_client.get("/api/v1/gamification/wallet", headers=auth_headers)
    assert second.json()["data"]["gems"] == 25


async def test_unlock_through_the_checker_is_visible_in_achievements_me_at_once(
    live_cache, async_client, auth_headers, db_session, test_user
):
    # Start from one badge: an empty list would never have been cached.
    first, second = (
        Achievement(
            name=slug, slug=slug, description="d",
            condition_type="vocab_reviewed", condition_value=1,
        )
        for slug in ("cache_probe_a", "cache_probe_b")
    )
    db_session.add_all([first, second])
    await db_session.commit()

    checker = AchievementCheckerService(db_session)
    await checker._unlock_achievement(test_user.id, first)
    await db_session.commit()

    url = "/api/v1/gamification/achievements/me"
    warm = await async_client.get(url, headers=auth_headers)
    assert [r["achievement"]["slug"] for r in warm.json()["data"]] == ["cache_probe_a"]

    # What the vocabulary, streak and challenge paths do: unlock, then the
    # caller commits. Nothing here invalidates the cache by hand.
    await checker._unlock_achievement(test_user.id, second)
    await db_session.commit()

    after = await async_client.get(url, headers=auth_headers)
    slugs = {r["achievement"]["slug"] for r in after.json()["data"]}
    assert slugs == {"cache_probe_a", "cache_probe_b"}


def _load_badge_migration():
    path = (
        Path(__file__).resolve().parents[1]
        / "alembic/versions/d7a2f5c1e9b3_badge_cdn_pin_main.py"
    )
    spec = spec_from_file_location("badge_cdn_pin_main", path)
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_badge_migration_chains_on_the_current_head():
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    root = Path(__file__).resolve().parents[1]
    cfg = Config(str(root / "alembic.ini"))
    cfg.set_main_option("script_location", str(root / "alembic"))
    scripts = ScriptDirectory.from_config(cfg)
    assert len(scripts.get_heads()) == 1
    assert scripts.get_revision("d7a2f5c1e9b3").down_revision == "c4e8a1b7d3f6"


async def test_badge_migration_rewrites_feature_pins_and_is_idempotent(db_session):
    repo = "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo"
    rows = {
        "legacy": f"{repo}@feature/flutter-app/assets/badges/streak3.png",
        "current": f"{repo}@main/flutter-app/assets/badges/streak7.png",
        "upload": "/media/badges/custom.png",
        "other": "https://example.com/@feature/x.png",
    }
    for slug, icon in rows.items():
        db_session.add(
            Achievement(
                name=slug, slug=slug, description="d", condition_type="t",
                condition_value=1, badge_icon=icon,
            )
        )
    await db_session.commit()

    migration = _load_badge_migration()

    def run(sync_conn):
        with Operations.context(MigrationContext.configure(sync_conn)):
            migration.upgrade()

    async def icons():
        db_session.expire_all()
        result = await db_session.execute(select(Achievement.slug, Achievement.badge_icon))
        return dict(result.all())

    conn = await db_session.connection()
    await conn.run_sync(run)
    once = await icons()
    await conn.run_sync(run)
    twice = await icons()

    assert once["legacy"] == f"{repo}@main/flutter-app/assets/badges/streak3.png"
    assert once["current"] == rows["current"]
    assert once["upload"] == rows["upload"]
    assert once["other"] == rows["other"]
    assert twice == once
