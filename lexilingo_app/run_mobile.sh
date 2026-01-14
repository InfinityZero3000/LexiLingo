#!/bin/bash

# Script để chạy Flutter với hot reload

echo "🔍 Checking connected devices..."
flutter devices

echo ""
echo "Select device:"
echo "1) iOS Simulator"
echo "2) Android Emulator"
echo "3) Physical Device (auto-detect)"
echo "4) List all and choose by ID"

read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        echo "🍎 Starting iOS Simulator..."
        # Mở Simulator nếu chưa mở
        open -a Simulator
        sleep 3
        
        # Tìm device ID của iOS simulator
        IOS_DEVICE=$(flutter devices | grep "ios" | grep "simulator" | head -1 | awk '{print $5}')
        
        if [ -z "$IOS_DEVICE" ]; then
            echo "❌ No iOS simulator found. Please open Simulator app first."
            exit 1
        fi
        
        echo "📱 Using device: $IOS_DEVICE"
        flutter run -d "$IOS_DEVICE"
        ;;
    2)
        echo "🤖 Starting Android Emulator..."
        # Tìm Android emulator
        ANDROID_DEVICE=$(flutter devices | grep "android" | head -1 | awk '{print $5}')
        
        if [ -z "$ANDROID_DEVICE" ]; then
            echo "❌ No Android emulator found. Starting default emulator..."
            flutter emulators --launch Pixel_7_Pro_API_35 || flutter emulators --launch $(flutter emulators | grep "^" | head -1 | awk '{print $1}')
            sleep 5
            ANDROID_DEVICE=$(flutter devices | grep "android" | head -1 | awk '{print $5}')
        fi
        
        flutter run -d "$ANDROID_DEVICE"
        ;;
    3)
        echo "📱 Running on physical device..."
        flutter run
        ;;
    4)
        echo "📋 Available devices:"
        flutter devices
        echo ""
        read -p "Enter device ID: " DEVICE_ID
        flutter run -d "$DEVICE_ID"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac
