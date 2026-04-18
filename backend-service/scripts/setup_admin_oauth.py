"""
Setup Admin Users with Google OAuth Support

Creates or updates admin users to support Google OAuth login:
- thefirestar312@gmail.com: Super Admin
- nhthang312@gmail.com: Admin

Run this script after seeding roles and permissions.
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path to import app modules
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models.user import User
from app.models.rbac import Role


async def setup_admin_oauth():
    """Create or update admin users with Google OAuth support."""
    async with AsyncSessionLocal() as db:
        print(" Setting up admin users with Google OAuth...")

        # Get roles
        result = await db.execute(select(Role).where(Role.slug == "admin"))
        admin_role = result.scalar_one_or_none()

        result = await db.execute(select(Role).where(Role.slug == "super_admin"))
        super_admin_role = result.scalar_one_or_none()

        if not admin_role or not super_admin_role:
            print(" Error: Roles not found. Please run Alembic migrations and seed_data.py first.")
            return

        print(f"  Found roles: Admin (ID: {admin_role.id}), Super Admin (ID: {super_admin_role.id})")

        # Admin users to setup — thefirestar312 = super_admin, nhthang312 = admin
        admin_users = [
            {
                "email": "thefirestar312@gmail.com",
                "username": "thefirestar312",
                "display_name": "Super Admin",
                "role_id": super_admin_role.id,
                "role_name": "Super Admin",
            },
            {
                "email": "nhthang312@gmail.com",
                "username": "nhthang312",
                "display_name": "Admin",
                "role_id": admin_role.id,
                "role_name": "Admin",
            },
        ]

        import bcrypt
        oauth_password_hash = bcrypt.hashpw(b"OAUTH_USER_NO_PASSWORD", bcrypt.gensalt(12)).decode()

        for user_data in admin_users:
            email = user_data["email"]

            # Check if user exists
            result = await db.execute(
                select(User).where(User.email == email)
            )
            user = result.scalar_one_or_none()

            if user:
                # Update existing user — fix role, provider, password
                old_role_id = user.role_id

                user.add_provider("google")
                # Only reset password to placeholder if user has no local credentials.
                # Multi-provider accounts keep their real local password intact.
                if not user.has_local_auth:
                    user.hashed_password = oauth_password_hash
                user.role_id = user_data["role_id"]
                user.display_name = user_data["display_name"]
                user.is_verified = True
                user.is_active = True

                print(f"\n   Updated user: {email}")
                print(f"     - Providers: {user.provider}")
                print(f"     - Role: {user_data['role_name']}")
                if old_role_id != user.role_id:
                    print(f"     - Role ID changed: {old_role_id} → {user.role_id}")
            else:
                # Create new user — ensure unique username
                username = user_data["username"]
                base_username = username
                counter = 1
                while True:
                    result = await db.execute(
                        select(User).where(User.username == username)
                    )
                    if not result.scalar_one_or_none():
                        break
                    username = f"{base_username}{counter}"
                    counter += 1

                user = User(
                    email=email,
                    username=username,
                    hashed_password=oauth_password_hash,
                    display_name=user_data["display_name"],
                    provider=["google"],
                    role_id=user_data["role_id"],
                    is_verified=True,
                    is_active=True,
                    level="A1",
                )
                db.add(user)

                print(f"\n   Created user: {email}")
                print(f"     - Username: {username}")
                print(f"     - Provider: google")
                print(f"     - Role: {user_data['role_name']}")

        await db.commit()
        print("\n Admin OAuth setup completed!")
        print("\n Next steps:")
        print("   1. Make sure GOOGLE_CLIENT_ID and GOOGLE_ADMIN_CLIENT_ID are set in backend .env")
        print("   2. Test Google OAuth login at /auth/google endpoint with source='admin'")


if __name__ == "__main__":
    asyncio.run(setup_admin_oauth())
