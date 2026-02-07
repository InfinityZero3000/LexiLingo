#!/usr/bin/env python3
"""Setup test admin account with password for integration testing"""
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models.user import User
from app.models.rbac import Role
from app.core.security import get_password_hash
from app.core.config import settings

# Database connection
database_url = str(settings.DATABASE_URL).replace("postgresql+asyncpg://", "postgresql://")
engine = create_engine(database_url, echo=False)
SessionLocal = sessionmaker(bind=engine)

def setup_test_admin():
    """Create/update test admin account for integration testing"""
    db = SessionLocal()
    try:
        # Test admin credentials
        test_email = "test.admin@lexilingo.com"
        test_password = "admin123"
        
        # Find admin role
        admin_role = db.query(Role).filter(Role.slug == "admin").first()
        if not admin_role:
            print("❌ Admin role not found. Run seed_data.py first.")
            sys.exit(1)
        
        # Find existing user
        user = db.query(User).filter(User.email == test_email).first()
        
        if user:
            # Update existing user
            user.hashed_password = get_password_hash(test_password)
            user.provider = "local"
            user.is_verified = True
            user.is_active = True
            user.role_id = admin_role.id
            db.commit()
            print(f"✅ Updated test admin: {test_email}")
        else:
            # Create new user
            user = User(
                email=test_email,
                username=test_email.split('@')[0].replace('.', '_'),
                display_name="Test Admin",
                hashed_password=get_password_hash(test_password),
                provider="local",
                is_verified=True,
                is_active=True,
                role_id=admin_role.id
            )
            db.add(user)
            db.commit()
            print(f"✅ Created test admin: {test_email}")
        
        print(f"   - Email: {test_email}")
        print(f"   - Password: {test_password}")
        print(f"   - Role: {admin_role.slug} (level {admin_role.level})")
        print(f"   - Provider: local")
        print(f"\n✅ Test admin setup completed!")
        print(f"Use this account for integration testing.")
        
    except Exception as e:
        db.rollback()
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        db.close()

if __name__ == "__main__":
    setup_test_admin()
