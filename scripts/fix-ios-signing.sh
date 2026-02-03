#!/bin/bash
# Fix iOS code signing for simulator builds

echo "🔧 Fixing iOS code signing for simulator..."

cd "$(dirname "$0")/../flutter-app/ios"

# Backup original
cp Runner.xcodeproj/project.pbxproj Runner.xcodeproj/project.pbxproj.backup

# For simulator builds, we don't need code signing
# Set CODE_SIGN_IDENTITY to empty for Debug configuration
sed -i '' 's/CODE_SIGN_STYLE = Automatic;/CODE_SIGN_STYLE = Manual;\
				CODE_SIGN_IDENTITY = "";/g' Runner.xcodeproj/project.pbxproj

echo "✅ Fixed! Now try:"
echo "   cd flutter-app"
echo "   flutter run -d 'iPhone 16e'"
