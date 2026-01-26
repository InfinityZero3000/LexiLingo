#!/bin/bash

BASE_URL="http://127.0.0.1:8000/api/v1"

echo "========================================="
echo "1. REGISTER NEW USER"
echo "========================================="
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "refresh_test@example.com",
    "password": "TestPassword123!",
    "full_name": "Refresh Test User"
  }')

echo "$REGISTER_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$REGISTER_RESPONSE"
echo ""

echo "========================================="
echo "2. LOGIN TO GET TOKENS"
echo "========================================="
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "refresh_test@example.com",
    "password": "TestPassword123!"
  }')

echo "$LOGIN_RESPONSE" | python3 -m json.tool
echo ""

# Extract tokens
ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))")
REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('refresh_token', ''))")

if [ -z "$REFRESH_TOKEN" ]; then
    echo "❌ Failed to get refresh token from login response"
    exit 1
fi

echo "✅ Got access_token: ${ACCESS_TOKEN:0:50}..."
echo "✅ Got refresh_token: ${REFRESH_TOKEN:0:50}..."
echo ""

echo "========================================="
echo "3. DECODE REFRESH TOKEN (check type field)"
echo "========================================="
# Decode JWT payload (base64 decode the middle part)
PAYLOAD=$(echo "$REFRESH_TOKEN" | cut -d. -f2)
# Add padding if needed
PADDING=$((4 - ${#PAYLOAD} % 4))
if [ $PADDING -ne 4 ]; then
    PAYLOAD="${PAYLOAD}$(printf '=%.0s' $(seq 1 $PADDING))"
fi
echo "$PAYLOAD" | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Failed to decode"
echo ""

echo "========================================="
echo "4. USE REFRESH TOKEN TO GET NEW ACCESS TOKEN"
echo "========================================="
REFRESH_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{
    \"refresh_token\": \"$REFRESH_TOKEN\"
  }")

echo "$REFRESH_RESPONSE" | python3 -m json.tool
echo ""

# Check if refresh was successful
NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)

if [ -n "$NEW_ACCESS_TOKEN" ]; then
    echo "========================================="
    echo "✅ SUCCESS! Refresh token worked!"
    echo "========================================="
    echo "New access_token: ${NEW_ACCESS_TOKEN:0:50}..."
else
    echo "========================================="
    echo "❌ FAILED! Refresh token didn't work"
    echo "========================================="
    # Show error details
    ERROR_DETAIL=$(echo "$REFRESH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('detail', 'Unknown error'))" 2>/dev/null)
    echo "Error: $ERROR_DETAIL"
fi
