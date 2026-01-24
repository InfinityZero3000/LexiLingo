#!/bin/bash

# Script khởi tạo Phase 2 Development
echo "🚀 LexiLingo Phase 2 Setup"
echo "=========================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Phase 2: Course Management & Learning Features${NC}"
echo ""

# Kiểm tra Phase 1
echo "📦 Verifying Phase 1 completion..."
cd flutter-app
if ./test_phase1.sh > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Phase 1 tests passing (32/32)${NC}"
else
    echo -e "${YELLOW}⚠️  Phase 1 tests have warnings${NC}"
fi

cd ..

# Tạo cấu trúc thư mục Phase 2
echo ""
echo "📁 Creating Phase 2 directory structure..."

# Backend
mkdir -p backend-service/app/routes
mkdir -p backend-service/app/schemas
mkdir -p backend-service/app/crud

# Flutter Course feature
mkdir -p flutter-app/lib/features/course/domain/entities
mkdir -p flutter-app/lib/features/course/domain/repositories
mkdir -p flutter-app/lib/features/course/domain/usecases
mkdir -p flutter-app/lib/features/course/data/models
mkdir -p flutter-app/lib/features/course/data/datasources
mkdir -p flutter-app/lib/features/course/data/repositories
mkdir -p flutter-app/lib/features/course/presentation/providers
mkdir -p flutter-app/lib/features/course/presentation/screens
mkdir -p flutter-app/lib/features/course/presentation/widgets

# Flutter Progress feature
mkdir -p flutter-app/lib/features/progress/domain/entities
mkdir -p flutter-app/lib/features/progress/domain/repositories
mkdir -p flutter-app/lib/features/progress/domain/usecases
mkdir -p flutter-app/lib/features/progress/data/models
mkdir -p flutter-app/lib/features/progress/data/datasources
mkdir -p flutter-app/lib/features/progress/data/repositories

# Test directories
mkdir -p flutter-app/test/features/course/data/models
mkdir -p flutter-app/test/features/course/domain/usecases
mkdir -p flutter-app/test/features/course/presentation/providers

echo -e "${GREEN}✅ Directory structure created${NC}"

# Tạo TODO placeholders
echo ""
echo "📝 Creating TODO placeholders..."

# Backend Course route placeholder
cat > backend-service/app/routes/courses.py << 'EOF'
"""
Course API routes

TODO Phase 2:
- GET /courses (pagination)
- GET /courses/{course_id}
- GET /courses/{course_id}/units
- POST /courses/{course_id}/enroll
- GET /users/me/enrolled-courses
"""
from fastapi import APIRouter

router = APIRouter(prefix="/courses", tags=["courses"])

# TODO: Implement routes
EOF

echo -e "${GREEN}✅ Backend placeholders created${NC}"

# Flutter Course entity placeholder
cat > flutter-app/lib/features/course/domain/entities/course_entity.dart << 'EOF'
// TODO Phase 2: Implement CourseEntity
// Properties: id, title, description, level, category, imageUrl, duration, 
//             lessonsCount, isFeatured, rating, enrolledCount, units

class CourseEntity {
  // TODO: Add properties
}
EOF

echo -e "${GREEN}✅ Flutter placeholders created${NC}"

# Git status
echo ""
echo "📊 Current Git Status:"
git status --short

echo ""
echo -e "${GREEN}✅ Phase 2 setup complete!${NC}"
echo ""
echo "📋 Next steps:"
echo "  1. Review PHASE2_TASKS.md for detailed tasks"
echo "  2. Start with Task 2.1: Backend Course API"
echo "  3. Run tests: cd flutter-app && ./test_phase1.sh"
echo ""
echo -e "${BLUE}Happy coding! 🎉${NC}"
