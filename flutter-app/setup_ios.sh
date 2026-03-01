#!/bin/bash

# Setup iOS Development Environment
# LexiLingo App

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        🍎 iOS Development Environment Setup               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}Step 1: Kiểm tra Xcode${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d "/Applications/Xcode.app" ]; then
    echo "${GREEN}Xcode đã được cài đặt${NC}"
else
    echo "${RED}Xcode chưa được cài đặt${NC}"
    echo "   Tải Xcode từ App Store hoặc:"
    echo "   https://developer.apple.com/xcode/"
    exit 1
fi

echo ""
echo "${BLUE}Step 2: Cấu hình Xcode Command Line Tools${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Chạy lệnh sau (cần password sudo):"
echo "${YELLOW}sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer${NC}"
echo ""
read -p "Đã chạy lệnh trên? (y/n): " xcode_select_done

if [ "$xcode_select_done" != "y" ]; then
    echo "${RED}Vui lòng chạy lệnh trên trước!${NC}"
    exit 1
fi

echo ""
echo "${BLUE}Step 3: Chạy Xcode First Launch${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Chạy lệnh sau (cần password sudo):"
echo "${YELLOW}sudo xcodebuild -runFirstLaunch${NC}"
echo ""
echo "⏳ Lệnh này có thể mất vài phút..."
read -p "Nhấn Enter để tiếp tục..."

sudo xcodebuild -runFirstLaunch

if [ $? -eq 0 ]; then
    echo "${GREEN}Xcode first launch hoàn tất${NC}"
else
    echo "${YELLOW} Có thể cần chạy lại hoặc đã chạy rồi${NC}"
fi

echo ""
echo "${BLUE}Step 4: Accept Xcode License${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Chạy lệnh sau để chấp nhận license:"
echo "${YELLOW}sudo xcodebuild -license accept${NC}"
echo ""
read -p "Nhấn Enter để tiếp tục..."

sudo xcodebuild -license accept

if [ $? -eq 0 ]; then
    echo "${GREEN}Xcode license đã được chấp nhận${NC}"
else
    echo "${YELLOW} Có thể đã chấp nhận rồi${NC}"
fi

echo ""
echo "${BLUE}Step 5: Cài đặt CocoaPods${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v pod &> /dev/null; then
    echo "${GREEN}CocoaPods đã được cài đặt: $(pod --version)${NC}"
else
    echo "${YELLOW} CocoaPods chưa được cài đặt${NC}"
    echo "Cài đặt CocoaPods:"
    echo "${YELLOW}sudo gem install cocoapods${NC}"
    echo ""
    read -p "Cài đặt ngay? (y/n): " install_cocoapods
    
    if [ "$install_cocoapods" = "y" ]; then
        sudo gem install cocoapods
        if [ $? -eq 0 ]; then
            echo "${GREEN}CocoaPods đã được cài đặt${NC}"
        else
            echo "${RED}Cài đặt CocoaPods thất bại${NC}"
            exit 1
        fi
    fi
fi

echo ""
echo "${BLUE}Step 6: Setup iOS Dependencies${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Navigate to the ios directory relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/ios"

if [ -f "Podfile" ]; then
    echo "Chạy pod install..."
    pod install --repo-update
    
    if [ $? -eq 0 ]; then
        echo "${GREEN}iOS dependencies đã được cài đặt${NC}"
    else
        echo "${RED}Pod install thất bại${NC}"
        echo "Thử chạy thủ công:"
        echo "  cd ios"
        echo "  pod install --repo-update"
    fi
else
    echo "${YELLOW} Không tìm thấy Podfile${NC}"
fi

cd "$SCRIPT_DIR"

echo ""
echo "${BLUE}Step 7: Kiểm tra iOS Simulators${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

xcrun simctl list devices available | grep "iPhone"

echo ""
echo "${BLUE}Step 8: Mở Xcode để thiết lập Signing${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Mở Xcode:"
echo "   ${YELLOW}open ios/Runner.xcworkspace${NC}"
echo ""
echo "2. Trong Xcode:"
echo "   - Chọn Runner project (bên trái)"
echo "   - Tab 'Signing & Capabilities'"
echo "   - Chọn Team (Apple Developer Account của bạn)"
echo "   - Hoặc tick 'Automatically manage signing'"
echo ""
read -p "Mở Xcode ngay? (y/n): " open_xcode

if [ "$open_xcode" = "y" ]; then
    open ios/Runner.xcworkspace
    echo "${GREEN}Đã mở Xcode${NC}"
    echo ""
    echo "Sau khi setup Signing trong Xcode, đóng Xcode lại."
    read -p "Nhấn Enter sau khi đã setup xong..."
fi

echo ""
echo "${BLUE}Step 9: Kiểm tra Flutter Doctor${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

flutter doctor -v

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              SETUP HOÀN TẤT!                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "${GREEN}📱 Chạy app trên iOS Simulator:${NC}"
echo "   ${YELLOW}flutter run${NC}"
echo ""
echo "${GREEN}📱 Chọn device cụ thể:${NC}"
echo "   ${YELLOW}flutter devices${NC}"
echo "   ${YELLOW}flutter run -d <device-id>${NC}"
echo ""
echo "${GREEN}📱 Chạy trên iPhone cụ thể:${NC}"
echo "   ${YELLOW}open -a Simulator${NC}  (mở Simulator)"
echo "   ${YELLOW}flutter run${NC}  (chọn simulator từ list)"
echo ""
echo "${GREEN}🔧 Nếu gặp lỗi:${NC}"
echo "   1. flutter clean"
echo "   2. cd ios && pod install --repo-update"
echo "   3. cd .. && flutter run"
echo ""
echo " Useful Commands:"
echo "   - Xem simulators: xcrun simctl list devices"
echo "   - Mở Simulator: open -a Simulator"
echo "   - Mở Xcode: open ios/Runner.xcworkspace"
echo ""
