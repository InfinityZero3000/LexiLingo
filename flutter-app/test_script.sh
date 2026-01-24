#!/bin/bash

# Script kiểm tra Phase 1 implementation
echo "🧪 LexiLingo Phase 1 Test Suite"
echo "================================"
echo ""

# Màu sắc cho output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Kiểm tra Flutter installation
echo "📦 Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Flutter is installed${NC}"
flutter --version | head -n 1
echo ""

# Kiểm tra dependencies
echo "📦 Checking dependencies..."
cd flutter-app
if [ ! -d "pubspec.lock" ]; then
    echo -e "${YELLOW}⚠️  Dependencies not installed. Running flutter pub get...${NC}"
    flutter pub get
fi
echo -e "${GREEN}✅ Dependencies ready${NC}"
echo ""

# Build runner để generate mocks (nếu cần)
echo "🔧 Generating test mocks..."
flutter pub run build_runner build --delete-conflicting-outputs
echo ""

# Chạy all tests
echo "🧪 Running all tests..."
echo "================================"
flutter test --coverage

# Kiểm tra test results
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    
    # Hiển thị coverage summary
    if [ -f "coverage/lcov.info" ]; then
        echo "📊 Test Coverage Summary:"
        echo "================================"
        # Cài đặt lcov nếu chưa có (macOS)
        if command -v lcov &> /dev/null; then
            lcov --summary coverage/lcov.info
        else
            echo -e "${YELLOW}⚠️  Install lcov to see coverage details: brew install lcov${NC}"
        fi
    fi
else
    echo ""
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi

# Kiểm tra file structure
echo ""
echo "📁 Verifying Phase 1 files..."
echo "================================"

FILES=(
    "lib/core/network/response_models.dart"
    "lib/core/network/api_client.dart"
    "lib/core/network/interceptors/token_refresh_interceptor.dart"
    "lib/features/auth/domain/entities/user_entity.dart"
    "lib/features/auth/data/models/user_model.dart"
    "lib/features/auth/data/models/auth_models.dart"
    "lib/features/auth/data/datasources/device_manager.dart"
    "lib/features/auth/data/datasources/token_storage.dart"
    "lib/features/auth/data/datasources/auth_backend_datasource.dart"
    "lib/features/auth/domain/repositories/auth_repository.dart"
    "lib/features/auth/data/repositories/auth_repository_impl.dart"
    "lib/features/auth/domain/usecases/register_usecase.dart"
    "lib/features/auth/domain/usecases/login_usecase.dart"
    "lib/features/auth/domain/usecases/logout_usecase.dart"
    "lib/features/auth/presentation/providers/auth_backend_provider.dart"
)

MISSING_FILES=()
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅${NC} $file"
    else
        echo -e "${RED}❌${NC} $file"
        MISSING_FILES+=("$file")
    fi
done

echo ""
if [ ${#MISSING_FILES[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All Phase 1 files present!${NC}"
else
    echo -e "${RED}❌ Missing ${#MISSING_FILES[@]} files${NC}"
    exit 1
fi

# Kiểm tra code analysis
echo ""
echo "🔍 Running Flutter analyze..."
echo "================================"
flutter analyze

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ No analysis issues${NC}"
else
    echo -e "${YELLOW}⚠️  Some analysis warnings found${NC}"
fi

echo ""
echo "================================"
echo -e "${GREEN}✅ Phase 1 verification complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Setup dependency injection (lib/core/di/injection_container.dart)"
echo "2. Configure API base URL in lib/core/network/api_config.dart"
echo "3. Start backend server (cd ../backend-service && uvicorn app.main:app --reload)"
echo "4. Run app: flutter run"
echo "5. Test login flow end-to-end"
