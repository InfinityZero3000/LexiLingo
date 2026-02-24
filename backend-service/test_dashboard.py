#!/usr/bin/env python3
"""Phase 1 Dashboard Integration Test"""
import requests
import sys

BASE = "http://localhost:8000/api/v1"
passed = failed = 0

def test(name, ok, msg=""):
    global passed, failed
    if ok:
        print(f"✓ {name}")
        passed += 1
    else:
        print(f"✗ {name} - {msg}")
        failed += 1

print("=" * 60)
print("PHASE 1 DASHBOARD TEST")
print("=" * 60)

# 1. Health
try:
    r = requests.get("http://localhost:8000/health", timeout=5)
    test("Health check", r.status_code == 200 and r.json().get("status") == "healthy")
except Exception as e:
    test("Health check", False, str(e))
    sys.exit(1)

# 2. Login
try:
    r = requests.post(f"{BASE}/auth/login", 
                     json={"email":"thefirestar312@gmail.com","password":"admin123"}, 
                     timeout=5)
    test("Admin login", r.status_code == 200)
    token = r.json().get("access_token") if r.status_code == 200 else None
    test("Token received", token is not None)
except Exception as e:
    test("Admin login", False, str(e))
    sys.exit(1)

headers = {"Authorization": f"Bearer {token}"}

# 3. KPIs
try:
    r = requests.get(f"{BASE}/admin/analytics/dashboard/kpis", headers=headers, timeout=5)
    test("KPIs endpoint", r.status_code == 200)
    if r.status_code == 200:
        data = r.json()
        test("KPIs structure", "kpis" in data and all(k in data["kpis"] for k in ["total_users","active_users_7d","total_courses"]))
except Exception as e:
    test("KPIs endpoint", False, str(e))

# 4. User Growth
try:
    r = requests.get(f"{BASE}/admin/analytics/dashboard/user-growth?days=30", headers=headers, timeout=5)
    test("User growth endpoint", r.status_code == 200)
    if r.status_code == 200:
        data = r.json()
        test("User growth data", "data" in data and isinstance(data["data"], list))
except Exception as e:
    test("User growth endpoint", False, str(e))

# 5. Engagement
try:
    r = requests.get(f"{BASE}/admin/analytics/dashboard/engagement?weeks=12", headers=headers, timeout=5)
    test("Engagement endpoint", r.status_code == 200)
    if r.status_code == 200:
        data = r.json()
        test("Engagement data", "data" in data and isinstance(data["data"], list))
except Exception as e:
    test("Engagement endpoint", False, str(e))

# 6. Course Popularity
try:
    r = requests.get(f"{BASE}/admin/analytics/dashboard/course-popularity", headers=headers, timeout=5)
    test("Course popularity endpoint", r.status_code == 200)
    if r.status_code == 200:
        data = r.json()
        test("Course data", "data" in data and isinstance(data["data"], list))
except Exception as e:
    test("Course popularity endpoint", False, str(e))

# 7. Completion Funnel
try:
    r = requests.get(f"{BASE}/admin/analytics/dashboard/completion-funnel", headers=headers, timeout=5)
    test("Completion funnel endpoint", r.status_code == 200, f"Status: {r.status_code}")
    if r.status_code == 200:
        data = r.json()
        test("Funnel has 4 stages", "data" in data and isinstance(data["data"], list) and len(data["data"]) == 4)
except Exception as e:
    test("Completion funnel endpoint", False, str(e))

# 8. RBAC Dashboard
try:
    r = requests.get(f"{BASE}/admin/rbac/dashboard", headers=headers, timeout=5)
    test("RBAC dashboard endpoint", r.status_code == 200)
except Exception as e:
    test("RBAC dashboard endpoint", False, str(e))

# Summary
print("=" * 60)
print(f"RESULT: {passed} passed, {failed} failed")
print("=" * 60)
sys.exit(0 if failed == 0 else 1)
