"""
Tests for Admin Gifting Functionality
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models.user import User
from app.models.course import Course
from app.models.gamification import ShopItem, UserInventory, UserWallet, WalletTransaction
from app.models.progress import UserCourseProgress
from app.models.notification import Notification


@pytest.mark.asyncio
class TestAdminGifting:
    """Tests for gifting items to users via admin api"""

    async def test_gift_gems(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
        test_user: User,
        db_session: AsyncSession
    ):
        """Test gifting gems to a user"""
        payload = {
            "gift_type": "gems",
            "amount": 150
        }

        response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            headers=admin_headers,
            json=payload
        )
        if response.status_code != 200:
            print("FAILED RESPONSE DETAILS:", response.status_code, response.text)
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "150 Gems" in data["data"]["gift_description"]

        # Verify wallet balance
        stmt = select(UserWallet).where(UserWallet.user_id == test_user.id)
        result = await db_session.execute(stmt)
        wallet = result.scalar_one_or_none()
        assert wallet is not None
        assert wallet.gems == 150

        # Verify transaction
        stmt_tx = select(WalletTransaction).where(WalletTransaction.user_id == test_user.id)
        result_tx = await db_session.execute(stmt_tx)
        tx = result_tx.scalars().first()
        assert tx is not None
        assert tx.amount == 150
        assert tx.source == "admin_gift"

        # Verify notification
        stmt_notif = select(Notification).where(Notification.user_id == test_user.id)
        result_notif = await db_session.execute(stmt_notif)
        notif = result_notif.scalars().first()
        assert notif is not None
        assert "150 Gems" in notif.body
        assert notif.type == "system"

    async def test_gift_course(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
        test_user: User,
        db_session: AsyncSession
    ):
        """Test gifting a course enrollment to a user"""
        # Create a published course
        course = Course(
            title="French for Admins",
            description="Special admin course",
            language="fr",
            level="A1",
            is_published=True
        )
        db_session.add(course)
        await db_session.commit()
        await db_session.refresh(course)

        payload = {
            "gift_type": "course",
            "course_id": str(course.id)
        }

        response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            headers=admin_headers,
            json=payload
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "French for Admins" in data["data"]["gift_description"]

        # Verify enrollment in DB
        stmt = select(UserCourseProgress).where(
            and_(
                UserCourseProgress.user_id == test_user.id,
                UserCourseProgress.course_id == course.id
            )
        )
        result = await db_session.execute(stmt)
        enrollment = result.scalar_one_or_none()
        assert enrollment is not None
        assert enrollment.progress_percentage == 0.0

        # Verify duplicate gift fails
        dup_response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            headers=admin_headers,
            json=payload
        )
        assert dup_response.status_code == 400
        assert "already enrolled" in dup_response.json()["error"]["message"]

    async def test_gift_avatar(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
        test_user: User,
        db_session: AsyncSession
    ):
        """Test gifting a profile avatar to a user"""
        # Create a shop avatar item
        avatar = ShopItem(
            name="Super Agent Avatar",
            description="Cool avatar",
            item_type="avatar",
            price_gems=50,
            is_available=True
        )
        db_session.add(avatar)
        await db_session.commit()
        await db_session.refresh(avatar)

        payload = {
            "gift_type": "avatar",
            "shop_item_id": str(avatar.id)
        }

        response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            headers=admin_headers,
            json=payload
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "Super Agent Avatar" in data["data"]["gift_description"]

        # Verify inventory has avatar
        stmt = select(UserInventory).where(
            and_(
                UserInventory.user_id == test_user.id,
                UserInventory.shop_item_id == avatar.id
            )
        )
        result = await db_session.execute(stmt)
        inv = result.scalar_one_or_none()
        assert inv is not None
        assert inv.quantity == 1

        # Verify duplicate avatar gifting fails (avatars are single-owned)
        dup_response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            headers=admin_headers,
            json=payload
        )
        assert dup_response.status_code == 400
        assert "already owns this avatar" in dup_response.json()["error"]["message"]

    async def test_gift_shop_item(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
        test_user: User,
        db_session: AsyncSession
    ):
        """Test gifting consumable shop items to a user"""
        # Create a consumable shop item
        item = ShopItem(
            name="Streak Freeze",
            description="Saves your streak",
            item_type="streak_freeze",
            price_gems=25,
            is_available=True
        )
        db_session.add(item)
        await db_session.commit()
        await db_session.refresh(item)

        payload = {
            "gift_type": "shop_item",
            "shop_item_id": str(item.id),
            "amount": 3
        }

        response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            headers=admin_headers,
            json=payload
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "3x Streak Freeze" in data["data"]["gift_description"]

        # Verify inventory quantity
        stmt = select(UserInventory).where(
            and_(
                UserInventory.user_id == test_user.id,
                UserInventory.shop_item_id == item.id
            )
        )
        result = await db_session.execute(stmt)
        inv = result.scalar_one_or_none()
        assert inv is not None
        assert inv.quantity == 3

    async def test_gifting_rbac_security(
        self,
        async_client: AsyncClient,
        test_user: User,
    ):
        """Test that non-admin users are unauthorized to send gifts"""
        payload = {
            "gift_type": "gems",
            "amount": 100
        }

        # Send request without admin headers (unauthorized/forbidden)
        # Assuming no auth header means 401, normal user auth header means 403
        response = await async_client.post(
            f"/api/v1/admin/users/{test_user.id}/gift",
            json=payload
        )

        assert response.status_code in (401, 403)
