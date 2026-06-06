"""
Tests for Gamification Routes
Testing achievements, wallet, leaderboard, shop, and social features
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import uuid4

from app.core.cache import build_cache_key, set_cached
from app.models.gamification import (
    Achievement,
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
