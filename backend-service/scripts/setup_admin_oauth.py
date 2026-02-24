"""
Setup Admin Users with Google OAuth Support

Creates or updates admin users to support Google OAuth login:
- thefirestar312@gmail.com: Admin
- nhthang312@gmail.com: Super Admin

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
        print("🔧 Setting up admin users with Google OAuth...")
        
        # Get roles
        result = await db.execute(select(Role).where(Role.slug == "admin"))
        admin_role = result.scalar_one_or_none()
        
        result = await db.execute(select(Role).where(Role.slug == "super_admin"))
        super_admin_role = result.scalar_one_or_none()
        
        if not admin_role or not super_admin_role:
            print("❌ Error: Roles not found. Please run seed_data.py first to create roles.")
            return
        
        print(f"  Found roles: Admin (ID: {admin_role.id}), Super Admin (ID: {super_admin_role.id})")
        
        # Admin users to setup
        admin_users = [
            {
                "email": "thefirestar312@gmail.com",
                "username": "thefirestar312",
                "display_name": "Admin User",
                "role_id": admin_role.id,
                "role_name": "Admin"
            },
            {
                "email": "nhthang312@gmail.com",
                "username": "nhthang312",
                "display_name": "Super Admin",
                "role_id": super_admin_role.id,
                "role_name": "Super Admin"
            }
        ]
        
        for user_data in admin_users:
            email = user_data["email"]
            
            # Check if user exists
            result = await db.execute(
                select(User).where(User.email == email)
            )
            user = result.scalar_one_or_none()
            
            if user:
                # Update existing user
                old_provider = user.provider
                old_role_id = user.role_id
                
                user.provider = "google"
                user.hashed_password = ""  # Empty string for OAuth users (NOT NULL constraint)
                user.role_id = user_data["role_id"]
                user.is_verified = True
                user.is_active = True
                
                print(f"\n  ✅ Updated user: {email}")
                print(f"     - Provider: {old_provider} → google")
                print(f"     - Password: Empty (OAuth only)")
                print(f"     - Role: {user_data['role_name']}")
                
                if old_role_id != user.role_id:
                    print(f"     - Role ID changed: {old_role_id} → {user.role_id}")
            else:
                # Create new user
                # Ensure unique username
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
                    hashed_password="",  # Empty string for OAuth users (NOT NULL constraint)
                    display_name=user_data["display_name"],
                    provider="google",
                    role_id=user_data["role_id"],
                    is_verified=True,
                    is_active=True,
                    level=user_data["role_id"]  # Use role_id as level for consistency
                )
                db.add(user)
                
                print(f"\n  ✅ Created user: {email}")
                print(f"     - Username: {username}")
                print(f"     - Provider: google")
                print(f"     - Role: {user_data['role_name']}")
        
        await db.commit()
        print("\n✅ Admin OAuth setup completed!")
        print("\n📝 Next steps:")
        print("   1. Make sure GOOGLE_CLIENT_ID and GOOGLE_ADMIN_CLIENT_ID are set in backend .env")
        print("   2. Make sure firebase-service-account.json is properly configured")
        print("   3. Test Google OAuth login at /auth/google endpoint")
        print("   4. Admin dashboard users can now login with their Google accounts")


if __name__ == "__main__":
    asyncio.run(setup_admin_oauth())
