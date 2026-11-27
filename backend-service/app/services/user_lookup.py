"""One way to find an account by email."""
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


def normalize_email(email: str) -> str:
    return email.strip().lower()


async def find_user_by_email(db: AsyncSession, email: str) -> User | None:
    """The exact address first, then the same address in another letter case.

    Older accounts were stored as typed, so a few may differ only by case. The exact
    match keeps each reachable; otherwise the verified, then oldest, one answers.
    """
    exact = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if exact is not None:
        return exact
    query = (
        select(User)
        .where(func.lower(User.email) == normalize_email(email))
        .order_by(User.is_verified.desc(), User.created_at.asc())
        .limit(1)
    )
    return (await db.execute(query)).scalar_one_or_none()
