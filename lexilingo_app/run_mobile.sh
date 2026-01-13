#!/bin/bash

# Script để chạy Flutter với hot reload

echo "🔍 Checking connected devices..."
flutter devices

echo ""
echo "Select device:"
echo "1) iOS Simulator"
echo "2) Android Emulator"
echo "3) Physical Device (auto-detect)"

read -p "Enter choice [1-3]: " choice

case $choice in
    1)
        echo "🍎 Starting iOS Simulator..."
        open -a Simulator
        sleep 3
        flutter run -d ios
        ;;
    2)
        echo "🤖 Starting Android Emulator..."
        flutter run -d android
        ;;
    3)
        echo "📱 Running on physical device..."
        flutter run
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
