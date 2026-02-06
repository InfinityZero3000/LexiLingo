#!/bin/bash
# Start Flutter Web in profile mode (faster than debug)
# Or serve pre-built web app

set -e
cd "$(dirname "$0")/../flutter-app"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE=${1:-"debug"}  # debug, profile, or serve

case $MODE in
    "serve")
        echo -e "${GREEN}🌐 Building and serving Flutter Web (Release)...${NC}"
        flutter build web --release
        echo -e "${GREEN}✅ Build complete! Serving on port 8080...${NC}"
        cd build/web
        python3 -m http.server 8080
        ;;
    "profile")
        echo -e "${GREEN}🚀 Running Flutter Web (Profile mode - faster)...${NC}"
        flutter run -d chrome --web-port=8080 --profile
        ;;
    "debug")
        echo -e "${YELLOW}🐛 Running Flutter Web (Debug mode - slower)...${NC}"
        flutter run -d chrome --web-port=8080
        ;;
    *)
        echo "Usage: $0 [debug|profile|serve]"
        echo "  debug   - Debug mode with hot reload (slowest)"
        echo "  profile - Profile mode (faster compilation)"
        echo "  serve   - Build release and serve with Python (fastest startup)"
        ;;
esac
