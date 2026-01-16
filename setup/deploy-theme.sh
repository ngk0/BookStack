#!/bin/bash
#
# Deploy LAPORTE theme to BookStack
#
# This script copies theme files from setup/theme/ (version controlled)
# to data/bookstack/themes/laporte/ (runtime location)
#
# Usage:
#   ./deploy-theme.sh [--restart]
#
# Options:
#   --restart    Restart BookStack after deploying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"
THEME_SRC="$SCRIPT_DIR/theme"
THEME_DEST="$STACK_DIR/data/bookstack/themes/laporte"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check source exists
if [[ ! -d "$THEME_SRC" ]]; then
    error "Theme source not found: $THEME_SRC"
fi

# Create destination if needed
mkdir -p "$THEME_DEST/lang/en"

info "Deploying LAPORTE theme..."

# Copy all theme files
cp -r "$THEME_SRC/"* "$THEME_DEST/"

info "Theme files deployed to: $THEME_DEST"

# List what was deployed
echo ""
echo "Deployed files:"
find "$THEME_DEST" -type f -name "*.php" -o -name "*.css" | while read -r file; do
    echo "  - ${file#$THEME_DEST/}"
done

# Restart if requested
if [[ "${1:-}" == "--restart" ]]; then
    echo ""
    info "Restarting BookStack..."
    cd "$STACK_DIR"
    docker compose restart bookstack
    info "BookStack restarted"
fi

echo ""
info "Done! Clear browser cache to see changes."
