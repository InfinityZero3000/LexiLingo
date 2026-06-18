"""Auth CRUD — RefreshToken table queries."""
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import RefreshToken


class AuthCRUD:
    @staticmethod
    async def get_refresh_token(db: AsyncSession, token: str) -> Optional[RefreshToken]:
        result = await db.execute(
            select(RefreshToken).where(RefreshToken.token == token)
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def get_active_refresh_token(db: AsyncSession, token: str) -> Optional[RefreshToken]:
        result = await db.execute(
            select(RefreshToken).where(
                RefreshToken.token == token,
                RefreshToken.is_revoked == False,
            )
        )
        return result.scalar_one_or_none()
