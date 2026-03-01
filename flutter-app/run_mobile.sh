#!/bin/bash

# Script để chạy Flutter với hot reload

# Ensure we always run from the flutter-app directory (where pubspec.yaml lives)
cd "$(dirname "$0")"

# Helper: extract device ID from `flutter devices` output using bullet separator
# Usage: get_device_id "<platform_pattern>"
# The flutter devices output format: "  Name (type) • DEVICE_ID • platform •"
get_device_id() {
    local pattern="$1"
    flutter devices 2>/dev/null \
        | grep -E "[•].*${pattern}" \
        | head -1 \
        | awk -F'•' '{gsub(/^ +| +$/, "", $2); print $2}'
}

echo "🔍 Checking connected devices..."
flutter devices 2>&1 | grep -v "^Error:" | grep -v "^No wireless" | grep -v "^Run " | grep -v "^If you" | grep -v "^The device" | grep -v "^Visit"

echo ""
echo "Select device:"
echo "1) iOS Simulator"
echo "2) Android Emulator"
echo "3) macOS Desktop"
echo "4) Physical Device (auto-detect)"
echo "5) List all and choose by ID"

read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        echo "🍎 Starting iOS Simulator..."
        # Open Simulator app if not already running
        open -a Simulator 2>/dev/null
        sleep 3

        # Extract iOS device ID — flutter devices output has "• ios" on one line,
        # "(simulator)" on the NEXT line, so only grep on the platform field.
        IOS_DEVICE=$(get_device_id "ios")

        if [ -z "$IOS_DEVICE" ]; then
            # Fallback: try xcrun to get a booted simulator UUID
            IOS_DEVICE=$(xcrun simctl list devices booted 2>/dev/null \
                | grep "Booted" | head -1 \
                | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
        fi

        if [ -z "$IOS_DEVICE" ]; then
            echo "❌ No iOS simulator found. Please open Xcode Simulator first."
            echo "   Run: open -a Simulator"
            exit 1
        fi

        echo "📱 Using device: $IOS_DEVICE"
        flutter run -d "$IOS_DEVICE"
        ;;
    2)
        # Check Android SDK before proceeding
        if ! flutter doctor 2>&1 | grep -q "Android toolchain.*✓\|Android toolchain - develop"; then
            if flutter doctor 2>&1 | grep -q "Unable to locate Android SDK"; then
                echo "❌ Android SDK not found."
                echo "   Install Android Studio: https://developer.android.com/studio"
                echo "   Or run: flutter config --android-sdk <path>"
                exit 1
            fi
        fi

        echo "🤖 Starting Android Emulator..."
        ANDROID_DEVICE=$(get_device_id "android")

        if [ -z "$ANDROID_DEVICE" ]; then
            echo "   No running Android emulator. Launching one..."
            # Try common emulator names, fall back to first available
            EMULATOR=$(flutter emulators 2>/dev/null | grep -v "^$\|^No emulators\|^List of" | head -1 | awk '{print $1}')
            if [ -n "$EMULATOR" ]; then
                flutter emulators --launch "$EMULATOR"
                echo "   Waiting for emulator to boot..."
                sleep 10
                ANDROID_DEVICE=$(get_device_id "android")
            fi
        fi

        if [ -z "$ANDROID_DEVICE" ]; then
            echo "❌ No Android emulator available. Create one via Android Studio AVD Manager."
            exit 1
        fi

        echo "📱 Using device: $ANDROID_DEVICE"
        flutter run -d "$ANDROID_DEVICE"
        ;;
    3)
        echo "🖥️  Running on macOS..."
        flutter run -d macos
        ;;
    4)
        echo "📱 Running on physical device (auto-detect)..."
        flutter run
        ;;
    5)
        echo "Available devices:"
        flutter devices 2>&1
        echo ""
        read -p "Enter device ID: " DEVICE_ID
        flutter run -d "$DEVICE_ID"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac
