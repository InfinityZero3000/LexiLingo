#!/bin/bash

# Script to replace deprecated withOpacity() with withValues(alpha:) in Flutter code
# Usage: bash scripts/fix-with-opacity.sh

echo "🔧 Fixing deprecated withOpacity() calls..."

# Find all Dart files in lib directory
DART_FILES=$(find flutter-app/lib -name "*.dart" -type f)

COUNT=0

for file in $DART_FILES; do
  # Check if file contains withOpacity
  if grep -q "withOpacity(" "$file"; then
    echo "📝 Processing: $file"
    
    # Create backup
    cp "$file" "$file.bak"
    
    # Replace withOpacity with withValues(alpha:)
    # This handles the conversion: .withOpacity(0.5) -> .withValues(alpha: 0.5)
    sed -i '' 's/\.withOpacity(\([0-9.]*\))/\.withValues(alpha: \1)/g' "$file"
    
    COUNT=$((COUNT + 1))
  fi
done

echo "✅ Fixed $COUNT files"
echo "💡 Tip: Run 'flutter analyze' to verify changes"
