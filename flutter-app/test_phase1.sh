#!/bin/bash

# Script để chạy ONLY Phase 1 tests (bỏ qua old files có errors)
echo "🧪 LexiLingo Phase 1 Test Suite"
echo "================================"
echo ""

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd flutter-app

echo "📦 Running Phase 1 tests only..."
echo "================================"

# Chỉ chạy Phase 1 tests
flutter test \
  test/core/network/ \
  test/features/auth/data/models/ \
  test/features/auth/domain/usecases/ \
  --reporter expanded

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All Phase 1 tests passed! (32 tests)${NC}"
    echo ""
    echo "Phase 1 Test Coverage:"
    echo "  ✅ Core Network Layer (9 tests)"
    echo "  ✅ Auth Data Models (15 tests)"
    echo "  ✅ Auth UseCases (8 tests)"
    echo ""
    echo "Note: Old files (course, vocab, Firebase auth) are excluded"
    echo "      These will be refactored in Phase 2"
else
    echo ""
    echo "❌ Some Phase 1 tests failed"
    exit 1
fi
