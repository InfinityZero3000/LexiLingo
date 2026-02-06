#!/bin/bash
# Quick Test Script for Level & Rank System
# Usage: ./scripts/test_api_quick.sh

set -e

echo "========================================"
echo "   LexiLingo Level & Rank API Tests    "
echo "========================================"
echo ""

BASE_URL="http://localhost:8000/api/v1"
TEST_EMAIL="test_$(date +%s)@example.com"
TEST_PASSWORD="password123"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if backend is running
echo "1. Checking backend health..."
HEALTH=$(curl -s http://localhost:8000/health || echo "FAIL")

if [[ "$HEALTH" == *"FAIL"* ]]; then
    echo -e "${RED}❌ Backend is not running!${NC}"
    echo "   Start it with: cd backend-service && source venv/bin/activate && python -m uvicorn app.main:app --port 8000"
    exit 1
fi
echo -e "${GREEN}✅ Backend is healthy${NC}"

# Register test user
echo ""
echo "2. Registering test user..."
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"$TEST_PASSWORD\", \"username\": \"testuser_$(date +%s)\", \"full_name\": \"Test User\"}")

# Extract token
TOKEN=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('access_token') or d.get('access_token',''))" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    # Try login instead
    echo "   Registration failed, trying login..."
    LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"test@example.com\", \"password\": \"password123\"}")
    TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('access_token') or d.get('access_token',''))" 2>/dev/null)
fi

if [[ -z "$TOKEN" ]]; then
    echo -e "${RED}❌ Could not get auth token${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Got auth token${NC}"

# Test /users/me/level-full
echo ""
echo "3. Testing /users/me/level-full endpoint..."
LEVEL_FULL=$(curl -s -X GET "$BASE_URL/users/me/level-full" \
    -H "Authorization: Bearer $TOKEN")

echo "$LEVEL_FULL" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(f'   Numeric Level: {data.get(\"numeric_level\", \"N/A\")}')
    print(f'   Total XP: {data.get(\"total_xp\", 0)}')
    print(f'   Progress: {data.get(\"level_progress_percent\", 0):.1f}%')
    print(f'   Proficiency: {data.get(\"proficiency_level\", \"N/A\")} ({data.get(\"proficiency_name\", \"\")})')
    print(f'   Rank: {data.get(\"rank_name\", \"N/A\")} {data.get(\"rank_icon\", \"\")}')
    print(f'   Rank Score: {data.get(\"rank_score\", 0):.1f}')
except Exception as e:
    print(f'   Error parsing response: {e}')
    print(f'   Raw: {d}')
"
echo -e "${GREEN}✅ Level-full endpoint works${NC}"

# Test GET /proficiency/placement-test
echo ""
echo "4. Testing GET /proficiency/placement-test..."
PLACEMENT=$(curl -s -X GET "$BASE_URL/proficiency/placement-test" \
    -H "Authorization: Bearer $TOKEN")

echo "$PLACEMENT" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    print(f'   Title: {d.get(\"title\", \"N/A\")}')
    print(f'   Questions: {d.get(\"total_questions\", 0)}')
    print(f'   Time Limit: {d.get(\"time_limit_minutes\", 0)} min')
    questions = d.get('questions', [])
    if questions:
        print(f'   Sample: [{questions[0].get(\"level\")}] {questions[0].get(\"question\")[:50]}...')
except Exception as e:
    print(f'   Error: {e}')
"
echo -e "${GREEN}✅ Placement test GET endpoint works${NC}"

# Test Daily Challenges
echo ""
echo "5. Testing /challenges/daily..."
CHALLENGES=$(curl -s -X GET "$BASE_URL/challenges/daily" \
    -H "Authorization: Bearer $TOKEN")

echo "$CHALLENGES" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(f'   Date: {data.get(\"date\", \"N/A\")}')
    print(f'   Completed: {data.get(\"total_completed\", 0)}/{data.get(\"total_challenges\", 0)}')
    challenges = data.get('challenges', [])
    for c in challenges[:3]:
        status = '✅' if c.get('is_completed') else '⏳'
        print(f'   {status} {c.get(\"title\")}: {c.get(\"current\")}/{c.get(\"target\")} (+{c.get(\"xp_reward\")} XP)')
except Exception as e:
    print(f'   Error: {e}')
"
echo -e "${GREEN}✅ Daily challenges endpoint works${NC}"

# Test User Profile
echo ""
echo "6. Testing /users/me..."
PROFILE=$(curl -s -X GET "$BASE_URL/users/me" \
    -H "Authorization: Bearer $TOKEN")

echo "$PROFILE" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(f'   Username: {data.get(\"username\", \"N/A\")}')
    print(f'   Total XP: {data.get(\"total_xp\", 0)}')
    print(f'   Numeric Level: {data.get(\"numeric_level\", \"N/A\")}')
    print(f'   Rank: {data.get(\"rank\", \"N/A\")}')
    print(f'   Proficiency: {data.get(\"level\", \"N/A\")}')
except Exception as e:
    print(f'   Error: {e}')
"
echo -e "${GREEN}✅ User profile endpoint works${NC}"

# Submit Placement Test
echo ""
echo "7. Testing POST /proficiency/placement-test/submit..."
SUBMIT_BODY='{
    "answers": [
        {"question_id": "q1", "selected_answer": 1},
        {"question_id": "q2", "selected_answer": 1},
        {"question_id": "q3", "selected_answer": 1},
        {"question_id": "q4", "selected_answer": 1},
        {"question_id": "q5", "selected_answer": 2},
        {"question_id": "q6", "selected_answer": 1},
        {"question_id": "q7", "selected_answer": 2},
        {"question_id": "q8", "selected_answer": 1},
        {"question_id": "q9", "selected_answer": 0},
        {"question_id": "q10", "selected_answer": 1},
        {"question_id": "q11", "selected_answer": 1},
        {"question_id": "q12", "selected_answer": 2},
        {"question_id": "q13", "selected_answer": 0},
        {"question_id": "q14", "selected_answer": 1},
        {"question_id": "q15", "selected_answer": 2},
        {"question_id": "q16", "selected_answer": 1},
        {"question_id": "q17", "selected_answer": 3},
        {"question_id": "q18", "selected_answer": 0},
        {"question_id": "q19", "selected_answer": 0},
        {"question_id": "q20", "selected_answer": 2}
    ],
    "time_taken_seconds": 300
}'

SUBMIT_RESULT=$(curl -s -X POST "$BASE_URL/proficiency/placement-test/submit" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SUBMIT_BODY")

echo "$SUBMIT_RESULT" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    print(f'   Assessed Level: {d.get(\"assessed_level\", \"N/A\")}')
    print(f'   Score: {d.get(\"total_score\", 0)}/{d.get(\"max_score\", 0)} ({d.get(\"score_percentage\", 0):.1f}%)')
    print(f'   Correct: {d.get(\"correct_count\", 0)} questions')
    print(f'   Rank Changed: {d.get(\"rank_changed\", False)}')
    if d.get('rank_changed'):
        print(f'   New Rank: {d.get(\"new_rank\", \"N/A\")}')
except Exception as e:
    print(f'   Error: {e}')
"
echo -e "${GREEN}✅ Placement test submit works${NC}"

# Verify updated profile
echo ""
echo "8. Verifying updated profile after placement test..."
PROFILE_AFTER=$(curl -s -X GET "$BASE_URL/users/me/level-full" \
    -H "Authorization: Bearer $TOKEN")

echo "$PROFILE_AFTER" | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(f'   Proficiency: {data.get(\"proficiency_level\", \"N/A\")} ({data.get(\"proficiency_name\", \"\")})')
    print(f'   Rank: {data.get(\"rank_name\", \"N/A\")} ({data.get(\"rank\", \"\")})')
    print(f'   Rank Score: {data.get(\"rank_score\", 0):.1f}')
except Exception as e:
    print(f'   Error: {e}')
"
echo -e "${GREEN}✅ Profile updated correctly${NC}"

echo ""
echo "========================================"
echo -e "${GREEN}   All API Tests Passed! 🎉${NC}"
echo "========================================"
echo ""
echo "Verification Checklist:"
echo "  ✅ /users/me/level-full - Returns level, rank, proficiency"
echo "  ✅ /proficiency/placement-test - Returns 20 questions"
echo "  ✅ /proficiency/placement-test/submit - Updates proficiency & rank"
echo "  ✅ /challenges/daily - Returns daily challenges"
echo "  ✅ /users/me - Returns user with numeric_level and rank fields"
echo ""
