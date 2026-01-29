"""
Tests for Gamification Routes
Testing achievements, wallet, leaderboard, shop, and social features
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import uuid4

from app.models.gamification import Achievement, ShopItem, UserWallet
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
        assert "Insufficient gems" in response.json()["detail"]


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
