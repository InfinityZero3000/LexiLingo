#!/usr/bin/env python3
"""Phase 2 User Management - Integration Test"""
import requests
import sys

BASE = "http://localhost:8000/api/v1"
passed = failed = 0

def test(name, ok, msg=""):
    global passed, failed
    if ok:
        print(f"  ✓ {name}")
        passed += 1
    else:
        print(f"  ✗ {name} - {msg}")
        failed += 1

def unwrap(response_json):
    """Unwrap ApiResponse: {success, message, data, error} -> data"""
    if isinstance(response_json, dict) and "data" in response_json:
        return response_json["data"]
    return response_json

print("=" * 60)
print("PHASE 2 USER MANAGEMENT TEST")
print("=" * 60)

# 1. Health
print("\n[1] Health Check")
try:
    r = requests.get("http://localhost:8000/health", timeout=5)
    test("Health check", r.status_code == 200 and r.json().get("status") == "healthy")
except Exception as e:
    test("Health check", False, str(e))
    sys.exit(1)

# 2. Login
print("\n[2] Admin Login")
try:
    r = requests.post(f"{BASE}/auth/login", 
                     json={"email":"test.admin@lexilingo.com","password":"admin123"}, 
                     timeout=5)
    test("Admin login", r.status_code == 200)
    login_data = unwrap(r.json())
    token = login_data.get("access_token") if isinstance(login_data, dict) else None
    test("Token received", token is not None, f"Response: {str(r.json())[:200]}")
    if not token:
        sys.exit(1)
except Exception as e:
    test("Admin login", False, str(e))
    sys.exit(1)

headers = {"Authorization": f"Bearer {token}"}

# 3. List Users (default)
print("\n[3] List Users (default)")
try:
    r = requests.get(f"{BASE}/admin/users", headers=headers, timeout=5)
    test("List users endpoint", r.status_code == 200, f"Status: {r.status_code}")
    if r.status_code == 200:
        data = unwrap(r.json())
        test("Users list structure", 
             all(k in data for k in ["users", "total", "page", "page_size", "total_pages"]),
             f"Keys: {list(data.keys()) if isinstance(data, dict) else type(data)}")
        test("Users list not empty", len(data.get("users", [])) > 0, 
             f"Found {len(data.get('users', []))} users")
except Exception as e:
    test("List users endpoint", False, str(e))

# 4. List Users with Filters
print("\n[4] List Users with Filters")
try:
    r = requests.get(f"{BASE}/admin/users?page=1&page_size=10&sort_by=email&order=asc", headers=headers, timeout=5)
    test("List users with filters", r.status_code == 200)
    if r.status_code == 200:
        data = unwrap(r.json())
        test("Filtered users page size", data.get("page_size") == 10)
except Exception as e:
    test("List users with filters", False, str(e))

# 5. Search Users
print("\n[5] Search Users")
try:
    r = requests.get(f"{BASE}/admin/users?search=admin", headers=headers, timeout=5)
    test("Search users", r.status_code == 200)
    if r.status_code == 200:
        data = unwrap(r.json())
        test("Search results", len(data.get("users", [])) > 0, 
             f"Found {len(data.get('users', []))} matching users")
except Exception as e:
    test("Search users", False, str(e))

# 6. Get User Detail
print("\n[6] Get User Detail")
try:
    r_list = requests.get(f"{BASE}/admin/users?page_size=1", headers=headers, timeout=5)
    if r_list.status_code == 200:
        list_data = unwrap(r_list.json())
        if len(list_data.get("users", [])) > 0:
            user_id = list_data["users"][0]["id"]
            
            r = requests.get(f"{BASE}/admin/users/{user_id}", headers=headers, timeout=5)
            test("Get user detail", r.status_code == 200, f"Status: {r.status_code}")
            if r.status_code == 200:
                user = unwrap(r.json())
                test("User detail structure", 
                     all(k in user for k in ["id", "email", "role_slug", "role_level", "is_active"]),
                     f"Keys: {list(user.keys()) if isinstance(user, dict) else 'not a dict'}")
                test("User has stats", 
                     all(k in user for k in ["courses_enrolled", "courses_completed", "lessons_completed"]))
        else:
            test("Get user detail", False, "No users found")
    else:
        test("Get user detail", False, f"List failed: {r_list.status_code}")
except Exception as e:
    test("Get user detail", False, str(e))

# 7. Update User
print("\n[7] Update User")
try:
    r_list = requests.get(f"{BASE}/admin/users?page_size=1&is_active=true", headers=headers, timeout=5)
    if r_list.status_code == 200:
        list_data = unwrap(r_list.json())
        if len(list_data.get("users", [])) > 0:
            user_id = list_data["users"][0]["id"]
            
            r = requests.put(
                f"{BASE}/admin/users/{user_id}",
                headers=headers,
                json={"display_name": "Test Update"},
                timeout=5
            )
            test("Update user", r.status_code == 200, f"Status: {r.status_code}")
            if r.status_code == 200:
                updated = unwrap(r.json())
                test("Update applied", updated.get("display_name") == "Test Update",
                     f"display_name: {updated.get('display_name')}")
        else:
            test("Update user", False, "No active users found")
    else:
        test("Update user", False, f"List failed: {r_list.status_code}")
except Exception as e:
    test("Update user", False, str(e))

# 8. Get User Activity
print("\n[8] Get User Activity")
try:
    r_list = requests.get(f"{BASE}/admin/users?page_size=1", headers=headers, timeout=5)
    if r_list.status_code == 200:
        list_data = unwrap(r_list.json())
        if len(list_data.get("users", [])) > 0:
            user_id = list_data["users"][0]["id"]
            
            r = requests.get(f"{BASE}/admin/users/{user_id}/activity?days=30", headers=headers, timeout=5)
            test("Get user activity", r.status_code == 200, f"Status: {r.status_code}")
            if r.status_code == 200:
                activities = unwrap(r.json())
                test("Activity is list", isinstance(activities, list),
                     f"Type: {type(activities).__name__}")
        else:
            test("Get user activity", False, "No users found")
    else:
        test("Get user activity", False, f"List failed: {r_list.status_code}")
except Exception as e:
    test("Get user activity", False, str(e))

# 9. Role Filter
print("\n[9] Role Filter")
try:
    r = requests.get(f"{BASE}/admin/users?role=0", headers=headers, timeout=5)
    test("Filter by role (user)", r.status_code == 200)
    if r.status_code == 200:
        data = unwrap(r.json())
        users = data.get("users", [])
        if users:
            test("All role=0 users correct", all(u.get("role_level") == 0 for u in users))

    r = requests.get(f"{BASE}/admin/users?role=1", headers=headers, timeout=5)
    test("Filter by role (admin)", r.status_code == 200)
    if r.status_code == 200:
        data = unwrap(r.json())
        users = data.get("users", [])
        if users:
            test("All role=1 users correct", all(u.get("role_level") == 1 for u in users))
except Exception as e:
    test("Filter by role", False, str(e))

# 10. Status Filter
print("\n[10] Status Filter")
try:
    r = requests.get(f"{BASE}/admin/users?is_active=true", headers=headers, timeout=5)
    test("Filter by active status", r.status_code == 200)
    if r.status_code == 200:
        data = unwrap(r.json())
        users = data.get("users", [])
        if users:
            test("All users active", all(u.get("is_active") == True for u in users))
except Exception as e:
    test("Filter by status", False, str(e))

# 11. Pagination
print("\n[11] Pagination")
try:
    r1 = requests.get(f"{BASE}/admin/users?page=1&page_size=2", headers=headers, timeout=5)
    r2 = requests.get(f"{BASE}/admin/users?page=2&page_size=2", headers=headers, timeout=5)
    test("Pagination page 1", r1.status_code == 200)
    test("Pagination page 2", r2.status_code == 200)
    if r1.status_code == 200 and r2.status_code == 200:
        d1 = unwrap(r1.json())
        d2 = unwrap(r2.json())
        users1 = set(u["id"] for u in d1.get("users", []))
        users2 = set(u["id"] for u in d2.get("users", []))
        test("Pages have different users", len(users1 & users2) == 0, 
             f"Overlap: {len(users1 & users2)}")
except Exception as e:
    test("Pagination", False, str(e))

# 12. Sorting
print("\n[12] Sorting")
try:
    r_asc = requests.get(f"{BASE}/admin/users?sort_by=email&order=asc&page_size=5", headers=headers, timeout=5)
    r_desc = requests.get(f"{BASE}/admin/users?sort_by=email&order=desc&page_size=5", headers=headers, timeout=5)
    test("Sort ascending", r_asc.status_code == 200)
    test("Sort descending", r_desc.status_code == 200)
    if r_asc.status_code == 200 and r_desc.status_code == 200:
        asc_emails = [u["email"] for u in unwrap(r_asc.json()).get("users", [])]
        desc_emails = [u["email"] for u in unwrap(r_desc.json()).get("users", [])]
        test("Sort order correct", 
             asc_emails == sorted(asc_emails) and desc_emails == sorted(desc_emails, reverse=True),
             f"Asc: {asc_emails[:3]}, Desc: {desc_emails[:3]}")
except Exception as e:
    test("Sorting", False, str(e))

# 13. Auth Protection
print("\n[13] Auth Protection")
try:
    r = requests.get(f"{BASE}/admin/users", timeout=5)
    test("Requires authentication", r.status_code == 401)
except Exception as e:
    test("Auth protection", False, str(e))

# Summary
print("\n" + "=" * 60)
print(f"RESULT: {passed} passed, {failed} failed, {passed + failed} total")
print("=" * 60)

if failed == 0:
    print("\n✅ ALL PHASE 2 TESTS PASSED!")
    print("\nPhase 2 User Management is ready for use:")
    print("  - Backend: http://localhost:8000/api/v1/admin/users")
    print("  - Frontend: http://localhost:5173/admin/user-management")
    print("  - API Docs: http://localhost:8000/docs")
else:
    print(f"\n❌ {failed} test(s) failed")

sys.exit(0 if failed == 0 else 1)
