"""
Create test user for email/password login
"""
import asyncio
import uuid
import bcrypt
from datetime import datetime

from app.core.database import AsyncSessionLocal
from app.models.user import User
from sqlalchemy import select

async def create_test_user():
    async with AsyncSessionLocal() as db:
        # Check if user already exists
        result = await db.execute(
            select(User).where(User.email == "nhthang312@gmail.com")
        )
        existing_user = result.scalar_one_or_none()
        
        if existing_user:
            print(f"✅ User already exists: {existing_user.email}")
            return
        
        # Hash password using bcrypt (same as security.py)
        hashed_password = bcrypt.hashpw(
            "thang123".encode('utf-8'),
            bcrypt.gensalt()
        ).decode('utf-8')
        
        # Create user
        new_user = User(
            id=uuid.uuid4(),
            email="nhthang312@gmail.com",
            username="nhthang312",
            hashed_password=hashed_password,
            display_name="Nguyen Huu Thang",
            native_language="vi",
            target_language="en",
            level="A1",
            total_xp=0,
            numeric_level=1,
            rank="bronze",
            is_active=True,
            is_verified=True,
            provider="local",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        
        db.add(new_user)
        await db.commit()
        await db.refresh(new_user)
        
        print(f"✅ Created test user:")
        print(f"   Email: {new_user.email}")
        print(f"   Username: {new_user.username}")
        print(f"   Password: thang123")
        print(f"   ID: {new_user.id}")

if __name__ == "__main__":
    asyncio.run(create_test_user())
