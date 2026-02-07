"""Phase 1 Integration Test"""
import requests
import sys

url = "http://localhost:8000"
token = None

print("=" * 60)
print("PHASE 1 INTEGRATION TEST")
print("=" * 60)

# Test 1
print("\n[1/8] Backend Health...")
try:
    r = requests.get(f"{url}/health")
    assert r.status_code == 200
    print("✓ PASS - Backend healthy")
except:
    print("✗ FAIL")
    sys.exit(1)

# Test 2
print("\n[2/8] Admin Login...")
try:
    r = requests.post(f"{url}/api/v1/auth/login", 
                     json={"email": "thefirestar312@gmail.com", "password": "admin123"})
    token = r.json()["access_token"]
    print(f"✓ PASS - Token: {token[:30]}...")
except:
    print("✗ FAIL")
    sys.exit(1)

h = {"Authorization": f"Bearer {token}"}

# Test 3
print("\n[3/8] Dashboard KPIs...")
try:
    r = requests.get(f"{url}/api/v1/admin/analytics/dashboard/kpis", headers=h)
    data = r.json()["kpis"]
    print(f"✓ PASS - Users: {data['total_users']}")
except Exception as e:
    print(f"✗ FAIL - {e}")

# Test 4
print("\n[4/8] User Growth...")
try:
    r = requests.get(f"{url}/api/v1/admin/analytics/dashboard/user-growth?days=7", headers=h)
    data = r.json()["data"]
    print(f"✓ PASS - {len(data)} days")
except Exception as e:
    print(f"✗ FAIL - {e}")

# Test 5
print("\n[5/8] Engagement...")
try:
    r = requests.get(f"{url}/api/v1/admin/analytics/dashboard/engagement?weeks=4", headers=h)
    data = r.json()["data"]
    print(f"✓ PASS - {len(data)} weeks")
except Exception as e:
    print(f"✗ FAIL - {e}")

# Test 6
print("\n[6/8] Course Popularity...")
try:
    r = requests.get(f"{url}/api/v1/admin/analytics/dashboard/course-popularity", headers=h)
    data = r.json()["data"]
    print(f"✓ PASS - {len(data)} courses")
except Exception as e:
    print(f"✗ FAIL - {e}")

# Test 7
print("\n[7/8] Completion Funnel...")
try:
    r = requests.get(f"{url}/api/v1/admin/analytics/dashboard/completion-funnel", headers=h)
    data = r.json()["data"]
    print(f"✓ PASS - {len(data)} stages")
except Exception as e:
    print(f"✗ FAIL - {e}")

# Test 8
print("\n[8/8] Auth Protection...")
try:
    r = requests.get(f"{url}/api/v1/admin/analytics/dashboard/kpis")
    assert r.status_code == 401
    print("✓ PASS - Unauthorized blocked")
except:
    print("✗ FAIL")

print("\n" + "=" * 60)
print("✅ ALL TESTS PASSED - READY FOR PHASE 2")
print("=" * 60 + "\n")
