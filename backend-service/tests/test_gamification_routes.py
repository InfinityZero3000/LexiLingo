"""
Tests for Gamification Routes
Testing achievements, wallet, leaderboard, shop, and social features
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import uuid4

from app.core.cache import build_cache_key, set_cached
from app.core.security import create_access_token
from app.crud.gamification import LeaderboardCRUD
from app.models.gamification import (
    Achievement,
    LeaderboardEntry,
    ShopItem,
    UserInventory,
    UserWallet,
)
from app.models.user import User


class TestAchievements:
    """Tests for achievement endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_all_achievements(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test listing all achievements"""
        # Create test achievement
        achievement = Achievement(
            name="Test Achievement",
            description="Test description",
            condition_type="test_condition",
            condition_value=1,
            category="test",
            rarity="common",
            xp_reward=10,
            gems_reward=5
        )
        db_session.add(achievement)
        await db_session.commit()
        
        response = await async_client.get(
            "/api/v1/gamification/achievements",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_get_my_achievements(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting user's unlocked achievements"""
        response = await async_client.get(
            "/api/v1/gamification/achievements/me",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)


class TestWallet:
    """Tests for wallet endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_wallet(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting user wallet"""
        response = await async_client.get(
            "/api/v1/gamification/wallet",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "gems" in data["data"]
    
    @pytest.mark.asyncio
    async def test_get_wallet_history(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting wallet transaction history"""
        response = await async_client.get(
            "/api/v1/gamification/wallet/history",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)

    @pytest.mark.asyncio
    async def test_pending_starter_reward_can_be_acknowledged(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession,
        test_user: User,
    ):
        from app.services.starter_reward_service import StarterRewardService

        await StarterRewardService.grant_new_user_reward(
            db_session,
            test_user.id,
        )
        await db_session.commit()

        pending = await async_client.get(
            "/api/v1/gamification/rewards/starter/pending",
            headers=auth_headers,
        )
        assert pending.status_code == 200
        assert pending.json()["data"]["gems_awarded"] == 100

        seen = await async_client.post(
            "/api/v1/gamification/rewards/starter/seen",
            headers=auth_headers,
        )
        assert seen.status_code == 200
        assert seen.json()["data"] is True

        no_longer_pending = await async_client.get(
            "/api/v1/gamification/rewards/starter/pending",
            headers=auth_headers,
        )
        assert no_longer_pending.json()["data"] is None


class TestLeaderboard:
    """Tests for leaderboard endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_leaderboard(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting weekly leaderboard"""
        response = await async_client.get(
            "/api/v1/gamification/leaderboard?league=bronze",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "league" in data["data"]
        assert "entries" in data["data"]
    
    @pytest.mark.asyncio
    async def test_get_my_league_status(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting user's league status"""
        response = await async_client.get(
            "/api/v1/gamification/leaderboard/me",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "league" in data["data"]

    @pytest.mark.asyncio
    async def test_tied_weekly_xp_uses_the_same_rank_for_entries_and_viewer(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession,
        test_user: User,
    ):
        competitor = User(
            email=f"leaderboard-{uuid4()}@test.dev",
            username=f"leaderboard_{uuid4().hex[:8]}",
            hashed_password="hashed",
            display_name="Tied Competitor",
            target_language="en",
            level="A1",
            numeric_level=1,
            total_xp=500,
            rank="bronze",
            is_active=True,
        )
        test_user.rank = "bronze"
        test_user.total_xp = 100
        db_session.add(competitor)
        await db_session.flush()

        week_start, week_end = LeaderboardCRUD.get_current_week_range()
        db_session.add_all(
            [
                LeaderboardEntry(
                    user_id=test_user.id,
                    week_start=week_start,
                    week_end=week_end,
                    league="bronze",
                    xp_earned=100,
                ),
                LeaderboardEntry(
                    user_id=competitor.id,
                    week_start=week_start,
                    week_end=week_end,
                    league="bronze",
                    xp_earned=100,
                ),
            ]
        )
        await db_session.commit()

        response = await async_client.get(
            "/api/v1/gamification/leaderboard?league=bronze",
            headers=auth_headers,
        )

        assert response.status_code == 200, response.text
        payload = response.json()["data"]
        entries = {entry["user_id"]: entry for entry in payload["entries"]}
        viewer = entries[str(test_user.id)]
        tied_competitor = entries[str(competitor.id)]
        assert viewer["rank"] == tied_competitor["rank"] == 1
        assert payload["current_user_rank"] == viewer["rank"]

    @pytest.mark.asyncio
    async def test_shared_cache_personalizes_each_viewer_without_resyncing(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession,
        test_user: User,
        monkeypatch,
    ):
        from app.routes import gamification as gamification_route

        competitor = User(
            email=f"cache-viewer-{uuid4()}@test.dev",
            username=f"cache_viewer_{uuid4().hex[:8]}",
            hashed_password="hashed",
            display_name="Cache Viewer",
            target_language="en",
            level="A1",
            numeric_level=1,
            total_xp=100,
            rank="bronze",
            is_active=True,
        )
        test_user.rank = "bronze"
        db_session.add(competitor)
        await db_session.flush()

        week_start, week_end = LeaderboardCRUD.get_current_week_range()
        db_session.add_all(
            [
                LeaderboardEntry(
                    user_id=test_user.id,
                    week_start=week_start,
                    week_end=week_end,
                    league="bronze",
                    xp_earned=200,
                ),
                LeaderboardEntry(
                    user_id=competitor.id,
                    week_start=week_start,
                    week_end=week_end,
                    league="bronze",
                    xp_earned=100,
                ),
            ]
        )
        await db_session.commit()

        cache: dict[str, dict] = {}
        sync_calls = 0
        original_sync = LeaderboardCRUD.sync_current_week_entries_to_user_rank

        async def fake_get_cached(key: str):
            return cache.get(key)

        async def fake_set_cached(key: str, value: dict, ttl: int):
            cache[key] = value

        async def counted_sync(db: AsyncSession):
            nonlocal sync_calls
            sync_calls += 1
            await original_sync(db)

        monkeypatch.setattr(gamification_route, "get_cached", fake_get_cached)
        monkeypatch.setattr(gamification_route, "set_cached", fake_set_cached)
        monkeypatch.setattr(
            LeaderboardCRUD,
            "sync_current_week_entries_to_user_rank",
            staticmethod(counted_sync),
        )

        first = await async_client.get(
            "/api/v1/gamification/leaderboard?league=bronze",
            headers=auth_headers,
        )
        competitor_headers = {
            "Authorization": f"Bearer {create_access_token(data={'sub': str(competitor.id)})}"
        }
        second = await async_client.get(
            "/api/v1/gamification/leaderboard?league=bronze",
            headers=competitor_headers,
        )

        assert first.status_code == second.status_code == 200
        first_entries = first.json()["data"]["entries"]
        second_entries = second.json()["data"]["entries"]
        assert next(entry for entry in first_entries if entry["is_current_user"])[
            "user_id"
        ] == str(test_user.id)
        assert next(entry for entry in second_entries if entry["is_current_user"])[
            "user_id"
        ] == str(competitor.id)
        assert first.headers["X-Cache-Source"] == "origin"
        assert second.headers["X-Cache-Source"] == "redis"
        assert sync_calls == 1
        assert len(cache) == 1


class TestShop:
    """Tests for shop endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_shop_items(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test listing shop items"""
        # Create test shop item
        item = ShopItem(
            name="Test Item",
            description="Test description",
            item_type="test",
            price_gems=100,
            is_available=True
        )
        db_session.add(item)
        await db_session.commit()
        
        response = await async_client.get(
            "/api/v1/gamification/shop",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_purchase_insufficient_gems(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test purchase with insufficient gems"""
        # Create expensive item
        item = ShopItem(
            name="Expensive Item",
            description="Very expensive",
            item_type="premium",
            price_gems=999999,
            is_available=True
        )
        db_session.add(item)
        await db_session.commit()
        await db_session.refresh(item)
        
        response = await async_client.post(
            "/api/v1/gamification/shop/purchase",
            headers=auth_headers,
            json={"item_id": str(item.id), "quantity": 1}
        )
        
        assert response.status_code == 400
        assert "Insufficient gems" in response.json()["error"]["message"]


class TestInventory:
    """Tests for inventory endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_inventory(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting user inventory"""
        response = await async_client.get(
            "/api/v1/gamification/inventory",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "items" in data["data"]

    @pytest.mark.asyncio
    async def test_equip_owned_avatar_is_permanent(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession,
        test_user: User,
    ):
        avatar_url = (
            "https://api.dicebear.com/7.x/adventurer/svg?seed=RouteTest"
        )
        item = ShopItem(
            name="Route Test Avatar",
            description="Owned avatar",
            item_type="avatar",
            price_gems=10,
            icon_url=avatar_url,
            effects={"avatar_url": avatar_url},
            is_available=True,
        )
        db_session.add(item)
        await db_session.flush()
        inventory = UserInventory(
            user_id=test_user.id,
            shop_item_id=item.id,
            quantity=1,
        )
        db_session.add(inventory)
        await db_session.commit()
        await db_session.refresh(inventory)

        response = await async_client.post(
            "/api/v1/gamification/inventory/avatar/equip",
            headers=auth_headers,
            json={"inventory_id": str(inventory.id)},
        )

        assert response.status_code == 200
        assert response.json()["data"]["avatar_url"] == avatar_url
        await db_session.refresh(test_user)
        await db_session.refresh(inventory)
        assert test_user.avatar_url == avatar_url
        assert inventory.quantity == 1

    @pytest.mark.asyncio
    async def test_cannot_purchase_owned_avatar_again(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession,
        test_user: User,
    ):
        item = ShopItem(
            name="Already Owned Avatar",
            description="Owned avatar",
            item_type="avatar",
            price_gems=10,
            effects={"avatar_url": "https://example.com/avatar.svg"},
            is_available=True,
        )
        db_session.add(item)
        await db_session.flush()
        db_session.add(
            UserInventory(
                user_id=test_user.id,
                shop_item_id=item.id,
                quantity=1,
            )
        )
        await db_session.commit()

        response = await async_client.post(
            "/api/v1/gamification/shop/purchase",
            headers=auth_headers,
            json={"item_id": str(item.id), "quantity": 1},
        )

        assert response.status_code == 400
        assert "already owned" in response.json()["error"]["message"].lower()


class TestSocial:
    """Tests for social endpoints"""
    
    @pytest.mark.asyncio
    async def test_follow_self_fails(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        test_user: User
    ):
        """Test that following yourself fails"""
        response = await async_client.post(
            f"/api/v1/gamification/users/{test_user.id}/follow",
            headers=auth_headers
        )
        
        data = response.json()
        assert data["data"]["success"] is False
        assert "yourself" in data["data"]["message"].lower()
    
    @pytest.mark.asyncio
    async def test_get_followers(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        test_user: User
    ):
        """Test getting followers list"""
        response = await async_client.get(
            f"/api/v1/gamification/users/{test_user.id}/followers",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "users" in data["data"]
    
    @pytest.mark.asyncio
    async def test_get_activity_feed(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test getting activity feed"""
        response = await async_client.get(
            "/api/v1/gamification/feed",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "activities" in data["data"]

    @pytest.mark.asyncio
    async def test_get_friend_suggestions(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession,
    ):
        """Test getting friend suggestions endpoint."""
        candidate = User(
            email=f"suggest-{uuid4()}@test.dev",
            username=f"suggest_{uuid4().hex[:8]}",
            hashed_password="hashed",
            display_name="Suggestion Candidate",
            target_language="en",
            level="A1",
            numeric_level=1,
            total_xp=120,
            rank="bronze",
            is_active=True,
        )
        db_session.add(candidate)
        await db_session.commit()

        response = await async_client.get(
            "/api/v1/gamification/users/suggestions?limit=5",
            headers=auth_headers,
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "users" in data["data"]
        assert "total" in data["data"]

    @pytest.mark.asyncio
    async def test_update_location_and_get_nearby_users(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        test_user: User,
        db_session: AsyncSession,
    ):
        """Test hybrid location sharing and nearby learners endpoint."""
        candidate = User(
            email=f"nearby-{uuid4()}@test.dev",
            username=f"nearby_{uuid4().hex[:8]}",
            hashed_password="hashed",
            display_name="Nearby Candidate",
            target_language="en",
            level="A1",
            numeric_level=1,
            total_xp=200,
            rank="bronze",
            is_active=True,
        )
        db_session.add(candidate)
        await db_session.commit()

        # Seed candidate coarse location in cache (normally this user sets it from their own client).
        candidate_key = build_cache_key("social_location", user_id=str(candidate.id))
        await set_cached(
            candidate_key,
            {
                "user_id": str(candidate.id),
                "latitude": 10.78,
                "longitude": 106.69,
                "updated_at": "2026-04-17T10:00:00+00:00",
            },
            ttl=600,
        )

        update_response = await async_client.post(
            "/api/v1/gamification/users/location",
            headers=auth_headers,
            json={
                "enabled": True,
                "latitude": 10.77,
                "longitude": 106.68,
                "accuracy_meters": 120,
            },
        )
        assert update_response.status_code == 200
        update_data = update_response.json()
        assert update_data["success"] is True
        assert update_data["data"]["enabled"] is True

        nearby_response = await async_client.get(
            "/api/v1/gamification/users/nearby?limit=10&radius_km=25",
            headers=auth_headers,
        )
        assert nearby_response.status_code == 200
        nearby_data = nearby_response.json()
        assert nearby_data["success"] is True
        assert nearby_data["data"]["location_enabled"] is True
        assert "users" in nearby_data["data"]

        disable_response = await async_client.post(
            "/api/v1/gamification/users/location",
            headers=auth_headers,
            json={"enabled": False},
        )
        assert disable_response.status_code == 200
        disable_data = disable_response.json()
        assert disable_data["success"] is True
        assert disable_data["data"]["enabled"] is False
