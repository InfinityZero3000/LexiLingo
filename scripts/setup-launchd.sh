#!/bin/bash

###############################################################################
# Setup LaunchAgent for Auto-start AI Service on macOS
# Usage: bash scripts/setup-launchd.sh
###############################################################################

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_SOURCE="$PROJECT_ROOT/scripts/com.lexilingo.ai.local.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.lexilingo.ai.local.plist"

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Setup Auto-start for LexiLingo AI Service        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if plist exists
if [ ! -f "$PLIST_SOURCE" ]; then
    echo -e "${RED}✗${NC} plist file not found: $PLIST_SOURCE"
    exit 1
fi

# Create LaunchAgents directory if not exists
mkdir -p "$HOME/Library/LaunchAgents"

# Unload existing service (if any)
if [ -f "$PLIST_DEST" ]; then
    echo -e "${BLUE}→${NC} Unloading existing service..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Copy plist file
echo -e "${BLUE}→${NC} Installing LaunchAgent..."
cp "$PLIST_SOURCE" "$PLIST_DEST"

# Update paths in plist (replace placeholder username)
CURRENT_USER=$(whoami)
sed -i '' "s|/Users/nguyenhuuthang|$HOME|g" "$PLIST_DEST"

# Load service
echo -e "${BLUE}→${NC} Loading service..."
launchctl load "$PLIST_DEST"

# Start service immediately
echo -e "${BLUE}→${NC} Starting service..."
launchctl start com.lexilingo.ai.local

sleep 3

# Check status
if launchctl list | grep -q "lexilingo"; then
    echo ""
    echo -e "${GREEN}✓${NC} Service installed and started successfully!"
    echo ""
    echo -e "${BLUE}Service Details:${NC}"
    echo "  Name: com.lexilingo.ai.local"
    echo "  Status: Active"
    echo "  Auto-start: Enabled (runs on boot)"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  Status:  launchctl list | grep lexilingo"
    echo "  Stop:    launchctl stop com.lexilingo.ai.local"
    echo "  Start:   launchctl start com.lexilingo.ai.local"
    echo "  Restart: launchctl kickstart -k gui/\$(id -u)/com.lexilingo.ai.local"
    echo "  Logs:    tail -f $PROJECT_ROOT/logs/ai-launchd.log"
    echo "  Remove:  launchctl unload $PLIST_DEST"
    echo ""
else
    echo -e "${YELLOW}⚠${NC} Service may not be running. Check logs:"
    echo "  tail -f $PROJECT_ROOT/logs/ai-launchd.error.log"
fi
