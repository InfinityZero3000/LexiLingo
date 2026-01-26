import requests
import json

BASE_URL = "http://127.0.0.1:8000/api/v1"

print("=" * 60)
print("Testing Refresh Token Endpoint")
print("=" * 60)

# 1. Register
print("\n1. Registering new user...")
register_data = {
    "email": "refresh_tester@example.com",
    "username": "refreshtester",
    "password": "StrongPass123!",
    "display_name": "Refresh Tester"
}
try:
    r = requests.post(f"{BASE_URL}/auth/register", json=register_data)
    print(f"Status: {r.status_code}")
    if r.status_code == 200:
        print("✅ User registered")
    elif r.status_code == 400 and "already exists" in r.text.lower():
        print("ℹ️  User already exists, will use for login")
    else:
        print(f"Response: {r.text}")
except Exception as e:
    print(f"Error: {e}")

# 2. Login
print("\n2. Logging in to get tokens...")
login_data = {
    "email": "refresh_tester@example.com",
    "password": "StrongPass123!"
}
try:
    r = requests.post(f"{BASE_URL}/auth/login", json=login_data)
    print(f"Status: {r.status_code}")
    if r.status_code == 200:
        tokens = r.json()
        access_token = tokens['access_token']
        refresh_token = tokens['refresh_token']
        print(f"✅ Got tokens:")
        print(f"   Access token: {access_token[:50]}...")
        print(f"   Refresh token: {refresh_token[:50]}...")
        
        # Decode refresh token to check type
        import base64
        payload_part = refresh_token.split('.')[1]
        # Add padding
        padding = 4 - len(payload_part) % 4
        if padding != 4:
            payload_part += '=' * padding
        
        payload = json.loads(base64.b64decode(payload_part))
        print(f"\n   Refresh token payload:")
        print(f"   - type: {payload.get('type', 'NOT FOUND')}")
        print(f"   - sub: {payload.get('sub')}")
        print(f"   - exp: {payload.get('exp')}")
    else:
        print(f"❌ Login failed: {r.text}")
        exit(1)
except Exception as e:
    print(f"Error: {e}")
    exit(1)

# 3. Test refresh endpoint
print("\n3. Testing refresh endpoint with new refresh token...")
try:
    r = requests.post(f"{BASE_URL}/auth/refresh", 
                     json={"refresh_token": refresh_token})
    print(f"Status: {r.status_code}")
    if r.status_code == 200:
        new_tokens = r.json()
        print(f"✅ SUCCESS! Got new access token:")
        print(f"   New access token: {new_tokens['access_token'][:50]}...")
        print(f"\n🎉 Refresh endpoint is working correctly!")
    else:
        print(f"❌ FAILED! Response: {r.text}")
        response_data = r.json()
        print(f"   Error detail: {response_data.get('detail', 'Unknown')}")
except Exception as e:
    print(f"Error: {e}")
    exit(1)

# 4. Test with access token (should fail)
print("\n4. Testing refresh endpoint with ACCESS token (should fail)...")
try:
    r = requests.post(f"{BASE_URL}/auth/refresh",
                     json={"refresh_token": access_token})
    print(f"Status: {r.status_code}")
    if r.status_code == 401:
        response = r.json()
        print(f"✅ Correctly rejected access token!")
        print(f"   Error: {response.get('detail', 'Unknown')}")
    else:
        print(f"❌ Should have been 401, got: {r.status_code}")
        print(f"   Response: {r.text}")
except Exception as e:
    print(f"Error: {e}")

print("\n" + "=" * 60)
print("Test complete!")
print("=" * 60)
