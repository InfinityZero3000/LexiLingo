"""Test Firebase initialization."""
import sys
from pathlib import Path

# Add app to path
sys.path.insert(0, str(Path(__file__).parent))

from app.core.config import settings
from app.core.firebase_auth import _init_firebase_app, verify_firebase_token

print("=" * 60)
print("🔥 FIREBASE INITIALIZATION TEST")
print("=" * 60)

# Check config
print("\n📋 Configuration:")
print(f"  FIREBASE_PROJECT_ID: {settings.FIREBASE_PROJECT_ID}")
print(f"  FIREBASE_CREDENTIALS_FILE: {settings.FIREBASE_CREDENTIALS_FILE}")
print(f"  FIREBASE_CREDENTIALS_JSON: {'<SET>' if settings.FIREBASE_CREDENTIALS_JSON else '<EMPTY>'}")

# Check file exists
if settings.FIREBASE_CREDENTIALS_FILE:
    file_path = Path(settings.FIREBASE_CREDENTIALS_FILE)
    if not file_path.is_absolute():
        file_path = Path(__file__).parent / file_path
    print(f"\n📁 Credentials file:")
    print(f"  Path: {file_path}")
    print(f"  Exists: {file_path.exists()}")
    if file_path.exists():
        print(f"  Size: {file_path.stat().st_size} bytes")

# Try to initialize
print("\n🔄 Initializing Firebase Admin SDK...")
try:
    _init_firebase_app()
    print("  ✅ SUCCESS: Firebase Admin SDK initialized!")
    
    # Check if app is initialized
    import firebase_admin
    apps = firebase_admin._apps  # type: ignore
    print(f"  Active apps: {len(apps)}")
    if apps:
        default_app = firebase_admin.get_app()
        print(f"  Default app project_id: {default_app.project_id}")
    
except Exception as e:
    print(f"  ❌ ERROR: {type(e).__name__}: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 60)
print("✅ All checks passed!")
print("=" * 60)
