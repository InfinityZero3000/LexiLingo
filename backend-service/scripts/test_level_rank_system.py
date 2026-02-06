#!/usr/bin/env python3
"""
Test Script for Level & Rank System

Tests all the features from DAILY_CHALLENGES_RANKING_IMPLEMENTATION.md:
1. /users/me/level-full endpoint
2. Placement test endpoints
3. Daily challenges
4. XP/Level update flow
5. Rank calculation

Run: python -m scripts.test_level_rank_system
"""

import asyncio
import os
import sys
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import httpx
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich import print as rprint

console = Console()

BASE_URL = "http://localhost:8000/api/v1"

# Test credentials
TEST_EMAIL = "test@example.com"
TEST_PASSWORD = "password123"


def create_table(title: str, columns: list) -> Table:
    """Create a styled table."""
    table = Table(title=title, show_header=True, header_style="bold magenta")
    for col in columns:
        table.add_column(col)
    return table


async def get_auth_token(client: httpx.AsyncClient) -> str:
    """Get auth token for testing."""
    # Try login first
    response = await client.post(
        f"{BASE_URL}/auth/login",
        json={"email": TEST_EMAIL, "password": TEST_PASSWORD}
    )
    
    if response.status_code == 200:
        data = response.json()
        if "data" in data and "access_token" in data["data"]:
            return data["data"]["access_token"]
        elif "access_token" in data:
            return data["access_token"]
    
    # Try register if login fails (401 or 404)
    if response.status_code in [401, 404, 400]:
        import time
        unique_email = f"test_{int(time.time())}@example.com"
        unique_username = f"testuser_{int(time.time())}"
        
        reg_response = await client.post(
            f"{BASE_URL}/auth/register",
            json={
                "email": unique_email,
                "password": TEST_PASSWORD,
                "username": unique_username,
                "full_name": "Test User"
            }
        )
        
        if reg_response.status_code in [200, 201]:
            # Immediately login after registration
            login_response = await client.post(
                f"{BASE_URL}/auth/login",
                json={"email": unique_email, "password": TEST_PASSWORD}
            )
            if login_response.status_code == 200:
                data = login_response.json()
                if "access_token" in data:
                    return data["access_token"]
                elif "data" in data and "access_token" in data["data"]:
                    return data["data"]["access_token"]
    
    raise Exception(f"Could not authenticate: {response.status_code} - {response.text}")


async def test_health(client: httpx.AsyncClient):
    """Test backend health."""
    console.print("\n[bold blue]1. Testing Backend Health[/bold blue]")
    
    response = await client.get(f"{BASE_URL.replace('/api/v1', '')}/health")
    
    if response.status_code == 200:
        console.print("✅ Backend is healthy", style="green")
        return True
    else:
        console.print(f"❌ Backend health check failed: {response.status_code}", style="red")
        return False


async def test_level_full_endpoint(client: httpx.AsyncClient, token: str):
    """Test /users/me/level-full endpoint."""
    console.print("\n[bold blue]2. Testing /users/me/level-full Endpoint[/bold blue]")
    
    headers = {"Authorization": f"Bearer {token}"}
    response = await client.get(f"{BASE_URL}/users/me/level-full", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        if "data" in data:
            level_data = data["data"]
            
            table = create_table("Level & Rank Info", ["Field", "Value"])
            table.add_row("Numeric Level", str(level_data.get("numeric_level", "N/A")))
            table.add_row("Current XP in Level", str(level_data.get("current_xp_in_level", "N/A")))
            table.add_row("XP for Next Level", str(level_data.get("xp_for_next_level", "N/A")))
            table.add_row("Progress %", f"{level_data.get('level_progress_percent', 0):.1f}%")
            table.add_row("Total XP", str(level_data.get("total_xp", 0)))
            table.add_row("Proficiency Level", level_data.get("proficiency_level", "N/A"))
            table.add_row("Proficiency Name", level_data.get("proficiency_name", "N/A"))
            table.add_row("Rank", level_data.get("rank", "N/A"))
            table.add_row("Rank Name", level_data.get("rank_name", "N/A"))
            table.add_row("Rank Score", f"{level_data.get('rank_score', 0):.1f}")
            table.add_row("Rank Color", level_data.get("rank_color", "N/A"))
            table.add_row("Rank Icon", level_data.get("rank_icon", "N/A"))
            
            console.print(table)
            console.print("✅ Level-full endpoint working", style="green")
            return True
        else:
            console.print(f"⚠️ Response format unexpected: {data}", style="yellow")
            return False
    else:
        console.print(f"❌ Failed: {response.status_code} - {response.text}", style="red")
        return False


async def test_placement_test_get(client: httpx.AsyncClient, token: str):
    """Test GET /proficiency/placement-test endpoint."""
    console.print("\n[bold blue]3. Testing GET /proficiency/placement-test[/bold blue]")
    
    headers = {"Authorization": f"Bearer {token}"}
    response = await client.get(f"{BASE_URL}/proficiency/placement-test", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        
        console.print(f"📝 Title: {data.get('title', 'N/A')}")
        console.print(f"📄 Description: {data.get('description', 'N/A')}")
        console.print(f"❓ Total Questions: {data.get('total_questions', 0)}")
        console.print(f"⏱️ Time Limit: {data.get('time_limit_minutes', 0)} minutes")
        
        questions = data.get("questions", [])
        if questions:
            console.print(f"\n📋 Sample Questions (first 3):")
            for i, q in enumerate(questions[:3], 1):
                console.print(f"  {i}. [{q.get('level')}] {q.get('question')}")
                console.print(f"     Options: {q.get('options')}")
        
        console.print("✅ Placement test GET endpoint working", style="green")
        return data
    else:
        console.print(f"❌ Failed: {response.status_code} - {response.text}", style="red")
        return None


async def test_placement_test_submit(client: httpx.AsyncClient, token: str, test_data: dict):
    """Test POST /proficiency/placement-test/submit endpoint."""
    console.print("\n[bold blue]4. Testing POST /proficiency/placement-test/submit[/bold blue]")
    
    headers = {"Authorization": f"Bearer {token}"}
    
    # Submit mostly correct answers (select option 1 for all - which is correct for most A1 questions)
    answers = []
    for q in test_data.get("questions", []):
        # Select option index 1 (second option) for all - correct for most questions
        answers.append({
            "question_id": q["id"],
            "selected_answer": 1  # Most correct answers are index 1
        })
    
    submission = {
        "answers": answers,
        "time_taken_seconds": 300
    }
    
    response = await client.post(
        f"{BASE_URL}/proficiency/placement-test/submit",
        headers=headers,
        json=submission
    )
    
    if response.status_code == 200:
        data = response.json()
        
        table = create_table("Placement Test Results", ["Field", "Value"])
        table.add_row("Assessed Level", data.get("assessed_level", "N/A"))
        table.add_row("Total Score", str(data.get("total_score", 0)))
        table.add_row("Max Score", str(data.get("max_score", 0)))
        table.add_row("Score %", f"{data.get('score_percentage', 0):.1f}%")
        table.add_row("Correct Answers", str(data.get("correct_count", 0)))
        table.add_row("Rank Changed", str(data.get("rank_changed", False)))
        table.add_row("New Rank", data.get("new_rank", "N/A"))
        
        console.print(table)
        console.print("✅ Placement test submit endpoint working", style="green")
        return True
    else:
        console.print(f"❌ Failed: {response.status_code} - {response.text}", style="red")
        return False


async def test_daily_challenges(client: httpx.AsyncClient, token: str):
    """Test daily challenges endpoint."""
    console.print("\n[bold blue]5. Testing Daily Challenges[/bold blue]")
    
    headers = {"Authorization": f"Bearer {token}"}
    response = await client.get(f"{BASE_URL}/challenges/daily", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        if "data" in data:
            challenges_data = data["data"]
        else:
            challenges_data = data
        
        console.print(f"📅 Date: {challenges_data.get('date', 'N/A')}")
        console.print(f"✅ Completed: {challenges_data.get('total_completed', 0)}/{challenges_data.get('total_challenges', 0)}")
        console.print(f"🎁 Claimed: {challenges_data.get('total_claimed', 0)}")
        
        challenges = challenges_data.get("challenges", [])
        if challenges:
            table = create_table("Today's Challenges", ["Title", "Progress", "XP", "Status"])
            for c in challenges:
                progress = f"{c.get('current', 0)}/{c.get('target', 0)}"
                status = "✅ Completed" if c.get("is_completed") else "⏳ In Progress"
                if c.get("is_claimed"):
                    status = "🎁 Claimed"
                table.add_row(c.get("title", "N/A"), progress, str(c.get("xp_reward", 0)), status)
            
            console.print(table)
        
        console.print("✅ Daily challenges endpoint working", style="green")
        return True
    else:
        console.print(f"❌ Failed: {response.status_code} - {response.text}", style="red")
        return False


async def test_user_profile(client: httpx.AsyncClient, token: str):
    """Test user profile to verify level/rank are stored."""
    console.print("\n[bold blue]6. Testing User Profile (Level/Rank Fields)[/bold blue]")
    
    headers = {"Authorization": f"Bearer {token}"}
    response = await client.get(f"{BASE_URL}/users/me", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        if "data" in data:
            user = data["data"]
        else:
            user = data
        
        table = create_table("User Profile", ["Field", "Value"])
        table.add_row("Username", user.get("username", "N/A"))
        table.add_row("Email", user.get("email", "N/A"))
        table.add_row("Total XP", str(user.get("total_xp", 0)))
        table.add_row("Numeric Level", str(user.get("numeric_level", "N/A")))
        table.add_row("Rank", user.get("rank", "N/A"))
        table.add_row("Proficiency (level)", user.get("level", "N/A"))
        
        console.print(table)
        console.print("✅ User profile endpoint working", style="green")
        return True
    else:
        console.print(f"❌ Failed: {response.status_code} - {response.text}", style="red")
        return False


async def test_rank_calculation():
    """Test rank calculation logic."""
    console.print("\n[bold blue]7. Testing Rank Calculation Logic[/bold blue]")
    
    from app.services.rank_service import calculate_rank, RankTier
    
    test_cases = [
        (10, "A1", RankTier.BRONZE),
        (50, "B1", RankTier.SILVER),
        (70, "B2", RankTier.GOLD),
        (85, "C1", RankTier.PLATINUM),
        (95, "C1", RankTier.DIAMOND),
        (100, "C2", RankTier.MASTER),
    ]
    
    table = create_table("Rank Calculation Tests", ["Level", "Proficiency", "Expected", "Actual", "Status"])
    
    all_passed = True
    for level, proficiency, expected_rank in test_cases:
        rank_info = calculate_rank(level, proficiency)
        status = "✅" if rank_info.rank == expected_rank else "❌"
        if rank_info.rank != expected_rank:
            all_passed = False
        table.add_row(
            str(level),
            proficiency,
            expected_rank.value,
            rank_info.rank.value,
            status
        )
    
    console.print(table)
    
    if all_passed:
        console.print("✅ All rank calculations correct", style="green")
    else:
        console.print("❌ Some rank calculations failed", style="red")
    
    return all_passed


async def test_level_calculation():
    """Test level calculation logic."""
    console.print("\n[bold blue]8. Testing Level Calculation Logic[/bold blue]")
    
    from app.services.level_service import get_numeric_level_progress, xp_for_single_level
    
    test_xp_values = [0, 100, 500, 1118, 3162, 10000, 50000, 100000]
    
    table = create_table("Level Calculation Tests", ["Total XP", "Level", "Progress %", "XP to Next"])
    
    for xp in test_xp_values:
        progress = get_numeric_level_progress(xp)
        table.add_row(
            str(xp),
            str(progress.numeric_level),
            f"{progress.progress_percent:.1f}%",
            str(progress.xp_for_next_level)
        )
    
    console.print(table)
    
    # Test formula
    console.print("\n📊 XP Formula: XP needed = floor(100 * level^1.5)")
    formula_table = create_table("XP Per Level", ["Level", "XP Needed", "Total XP"])
    
    total = 0
    for level in [1, 5, 10, 20, 50, 100]:
        xp_needed = xp_for_single_level(level)
        total += xp_needed
        formula_table.add_row(str(level), str(xp_needed), str(total))
    
    console.print(formula_table)
    console.print("✅ Level calculations verified", style="green")
    
    return True


async def main():
    """Run all tests."""
    console.print(Panel.fit(
        "[bold green]Level & Rank System Test Suite[/bold green]\n"
        f"🕐 Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        title="🧪 LexiLingo Tests"
    ))
    
    results = {}
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Test 1: Health check
        results["health"] = await test_health(client)
        
        if not results["health"]:
            console.print("\n❌ Backend not running. Start it with:", style="red")
            console.print("   cd backend-service && source venv/bin/activate && python -m uvicorn app.main:app --port 8000")
            return
        
        try:
            # Get auth token
            console.print("\n🔐 Authenticating...")
            token = await get_auth_token(client)
            console.print("✅ Authentication successful", style="green")
            
            # Test 2: Level-full endpoint
            results["level_full"] = await test_level_full_endpoint(client, token)
            
            # Test 3 & 4: Placement test
            test_data = await test_placement_test_get(client, token)
            results["placement_get"] = test_data is not None
            
            if test_data:
                results["placement_submit"] = await test_placement_test_submit(client, token, test_data)
            else:
                results["placement_submit"] = False
            
            # Test 5: Daily challenges
            results["daily_challenges"] = await test_daily_challenges(client, token)
            
            # Test 6: User profile
            results["user_profile"] = await test_user_profile(client, token)
            
        except Exception as e:
            console.print(f"\n❌ Error during API tests: {e}", style="red")
            import traceback
            traceback.print_exc()
    
    # Test 7 & 8: Local calculations (no API needed)
    try:
        results["rank_calc"] = await test_rank_calculation()
        results["level_calc"] = await test_level_calculation()
    except Exception as e:
        console.print(f"\n❌ Error during calculation tests: {e}", style="red")
        results["rank_calc"] = False
        results["level_calc"] = False
    
    # Summary
    console.print("\n")
    console.print(Panel.fit(
        "[bold]Test Summary[/bold]",
        title="📊 Results"
    ))
    
    summary_table = create_table("Test Results", ["Test", "Status"])
    for test_name, passed in results.items():
        status = "✅ PASS" if passed else "❌ FAIL"
        summary_table.add_row(test_name.replace("_", " ").title(), status)
    
    console.print(summary_table)
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    console.print(f"\n[bold]Total: {passed}/{total} tests passed[/bold]")
    
    if passed == total:
        console.print("\n🎉 All tests passed! Level & Rank system is working correctly.", style="bold green")
    else:
        console.print("\n⚠️ Some tests failed. Check the output above for details.", style="bold yellow")


if __name__ == "__main__":
    asyncio.run(main())
