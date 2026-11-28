"""Who may take privileges away from whom, and when allowlisted emails grant a role."""
import time
from datetime import timedelta
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.refusal import refusal
from app.models.rbac import Role
from app.models.user import User

SUPER_ADMIN_LEVEL = 2
RECENT_SIGN_IN = timedelta(minutes=15)


async def active_super_admin_ids(db: AsyncSession, *, lock: bool = False) -> set[UUID]:
    query = (
        select(User.id)
        .join(Role, User.role_id == Role.id)
        .where(Role.level >= SUPER_ADMIN_LEVEL, User.is_active.is_(True))
    )
    if lock:
        # Two super admins removing each other at once must not both succeed. One lock
        # order for everyone, so they queue instead of deadlocking.
        query = query.order_by(User.id).with_for_update(of=User)
    return set((await db.execute(query)).scalars().all())


def ensure_recent_sign_in(user: User, message: str) -> None:
    """For actions a long-lived or borrowed session must not perform on its own."""
    signed_in = getattr(user, "authenticated_at", None)
    if (
        not isinstance(signed_in, (int, float))
        or time.time() - signed_in > RECENT_SIGN_IN.total_seconds()
    ):
        raise refusal(status.HTTP_403_FORBIDDEN, message, {"reason": "recent_sign_in_required"})


def is_protected_owner(user: User) -> bool:
    """Listed in the server's super admin allowlist: only server config can revoke it."""
    return settings.get_admin_role_for_email(user.email) == "super_admin"


async def ensure_may_change_privileged_account(
    db: AsyncSession, actor: User, target: User, *, revoking: bool
) -> None:
    """Guard a change to someone at the actor's level or higher. Lower levels pass."""
    if target.id == actor.id or target.role_level < actor.role_level:
        return
    if actor.role_level < SUPER_ADMIN_LEVEL or target.role_level > actor.role_level:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Cannot modify a user with equal or higher role level"
        )
    if revoking and is_protected_owner(target):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "This super admin is protected by the server configuration (SUPER_ADMIN_EMAIL_WHITELIST).",
        )
    ensure_recent_sign_in(
        actor,
        "Changing another super admin needs a recent sign-in: sign out, sign in again, then retry.",
    )
    if actor.id not in await active_super_admin_ids(db, lock=True):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Super admin privileges required")


async def ensure_not_last_super_admin(db: AsyncSession, user: User) -> None:
    """Closing your own account must not leave the system without a super admin."""
    ids = await active_super_admin_ids(db, lock=True)
    if user.id in ids and len(ids) == 1:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "You are the only super admin. Make someone else a super admin first.",
        )


async def allowlisted_role_for_sign_in(
    db: AsyncSession, email: str, *, email_verified: bool, is_new_account: bool, provider: str
) -> str | None:
    """The role the allowlist grants at this sign-in, if any.

    It applies when the account is created. Afterwards roles belong to the admin panel,
    so a demotion stays a demotion. The one exception is recovery: with no active super
    admin left, a listed super admin is restored.
    """
    # Admins sign in with Google only, so only a Google sign-in earns the role.
    if not email_verified or provider != "google":
        return None
    role = settings.get_admin_role_for_email(email)
    if role is None or is_new_account:
        return role
    if role == "super_admin" and not await active_super_admin_ids(db):
        return role
    return None
