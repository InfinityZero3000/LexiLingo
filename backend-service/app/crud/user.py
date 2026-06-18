"""User CRUD — single place for all User table queries."""
from typing import Optional
from uuid import UUID

from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.gamification import UserFollowing


class UserCRUD:
    @staticmethod
    async def get_by_id(db: AsyncSession, user_id: UUID | str) -> Optional[User]:
        result = await db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    @staticmethod
    async def get_by_email(db: AsyncSession, email: str) -> Optional[User]:
        result = await db.execute(select(User).where(User.email == email))
        return result.scalar_one_or_none()

    @staticmethod
    async def get_by_username(db: AsyncSession, username: str) -> Optional[User]:
        result = await db.execute(select(User).where(User.username == username))
        return result.scalar_one_or_none()

    @staticmethod
    async def search(
        db: AsyncSession,
        query: str,
        exclude_id: UUID | str | None = None,
        limit: int = 20,
    ) -> list[User]:
        pattern = f"%{query}%"
        stmt = (
            select(User)
            .where(
                User.is_active == True,
                or_(User.username.ilike(pattern), User.display_name.ilike(pattern)),
            )
            .limit(limit)
        )
        if exclude_id is not None:
            stmt = stmt.where(User.id != exclude_id)
        result = await db.execute(stmt)
        return list(result.scalars().all())

    @staticmethod
    async def get_following_ids(
        db: AsyncSession, follower_id: UUID | str, user_ids: list
    ) -> set:
        if not user_ids:
            return set()
        result = await db.execute(
            select(UserFollowing.following_id).where(
                UserFollowing.follower_id == follower_id,
                UserFollowing.following_id.in_(user_ids),
            )
        )
        return {row[0] for row in result.all()}
