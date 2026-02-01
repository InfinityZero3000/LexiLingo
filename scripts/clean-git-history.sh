#!/bin/bash
# ===========================================
# Script to remove sensitive data from Git history
# WARNING: This rewrites Git history!
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}⚠️  WARNING: This will rewrite Git history!${NC}"
echo -e "${YELLOW}Before proceeding:${NC}"
echo "  1. Make sure all team members have committed and pushed their work"
echo "  2. Backup your repository"
echo "  3. Coordinate with your team"
echo ""
read -p "Do you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 1
fi

# API key to remove
API_KEY="***REMOVED***"

echo -e "${YELLOW}🧹 Step 1: Creating backup...${NC}"
BACKUP_DIR="../LexiLingo-backup-$(date +%Y%m%d-%H%M%S)"
cp -r . "$BACKUP_DIR"
echo -e "${GREEN}✅ Backup created at: $BACKUP_DIR${NC}"
echo ""

echo -e "${YELLOW}🔍 Step 2: Searching for API key in Git history...${NC}"
if git log --all --full-history --source --pretty=format:"%H" -S "$API_KEY" | head -1; then
    echo -e "${RED}Found API key in Git history!${NC}"
else
    echo -e "${GREEN}No API key found in current commits (may be in older history)${NC}"
fi
echo ""

echo -e "${YELLOW}🔨 Step 3: Removing API key from Git history...${NC}"

# Use git filter-repo if available (faster and safer)
if command -v git-filter-repo &> /dev/null; then
    echo "Using git-filter-repo (recommended method)..."
    git filter-repo --replace-text <(echo "$API_KEY==>***REMOVED***") --force
else
    echo "git-filter-repo not found. Using git filter-branch (slower)..."
    echo "Tip: Install git-filter-repo for better performance:"
    echo "  brew install git-filter-repo"
    echo ""
    
    # Use filter-branch as fallback
    git filter-branch --force --index-filter \
        "git grep -l '$API_KEY' | xargs -r sed -i '' 's/$API_KEY/***REMOVED***/g'" \
        --prune-empty --tag-name-filter cat -- --all
fi

echo -e "${GREEN}✅ API key removed from history${NC}"
echo ""

echo -e "${YELLOW}🗑️  Step 4: Cleaning up...${NC}"
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Git history cleaned successfully!    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review changes: git log --oneline -10"
echo "  2. Force push to remote:"
echo -e "     ${GREEN}git push origin --force --all${NC}"
echo -e "     ${GREEN}git push origin --force --tags${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANT:${NC}"
echo "  • Revoke the old API key immediately at:"
echo "    https://makersuite.google.com/app/apikey"
echo "  • Tell team members to re-clone the repository"
echo "  • They should run: git fetch origin && git reset --hard origin/main"
