#!/bin/bash
# Apply LAPORTE Brand Theme to BookStack
# This script sets the custom CSS and color settings to match the official LAPORTE palette
#
# Usage: ./apply-laporte-theme.sh
#
# Run this from the bookstack stack directory: /srv/stacks/work/bookstack/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"

# Check if we're in the right directory
if [[ ! -f "$STACK_DIR/compose.yml" ]]; then
    echo "Error: Must run from bookstack stack directory"
    exit 1
fi

cd "$STACK_DIR"

echo "Applying LAPORTE brand theme to BookStack..."
echo ""

# Get database credentials from .env
source "$STACK_DIR/.env"

# Apply custom CSS to app-custom-head setting
echo "1. Applying custom CSS stylesheet..."
CSS_FILE="$SCRIPT_DIR/theme/custom-head.html"
if [[ -f "$CSS_FILE" ]]; then
    CSS_CONTENT=$(cat "$CSS_FILE" | base64 -w 0)
    docker compose exec -T db mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
        -e "UPDATE settings SET value = FROM_BASE64('$CSS_CONTENT') WHERE setting_key = 'app-custom-head';"
    echo "   ✓ Custom CSS applied"
else
    echo "   ✗ CSS file not found: $CSS_FILE"
fi

# Apply LAPORTE color settings
echo "2. Applying LAPORTE color palette..."
docker compose exec -T db mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
-- LAPORTE Brand Colors for BookStack
-- Primary: #00263b (Dark Blue)
-- Accent: #E9B52D (Golden Yellow)

-- Light mode colors
UPDATE settings SET value = '#00263b' WHERE setting_key = 'app-color';
UPDATE settings SET value = 'rgba(0,38,59,0.15)' WHERE setting_key = 'app-color-light';
UPDATE settings SET value = '#00263b' WHERE setting_key = 'link-color';
UPDATE settings SET value = '#E9B52D' WHERE setting_key = 'bookshelf-color';
UPDATE settings SET value = '#00263b' WHERE setting_key = 'book-color';
UPDATE settings SET value = '#5a8f7b' WHERE setting_key = 'chapter-color';
UPDATE settings SET value = '#00263b' WHERE setting_key = 'page-color';
UPDATE settings SET value = '#7e50b1' WHERE setting_key = 'page-draft-color';

-- Dark mode colors (lighter versions for visibility)
UPDATE settings SET value = '#003350' WHERE setting_key = 'app-color-dark';
UPDATE settings SET value = 'rgba(0,51,80,0.15)' WHERE setting_key = 'app-color-light-dark';
UPDATE settings SET value = '#4a90c2' WHERE setting_key = 'link-color-dark';
UPDATE settings SET value = '#E9B52D' WHERE setting_key = 'bookshelf-color-dark';
UPDATE settings SET value = '#4a90c2' WHERE setting_key = 'book-color-dark';
UPDATE settings SET value = '#6ab090' WHERE setting_key = 'chapter-color-dark';
UPDATE settings SET value = '#4a90c2' WHERE setting_key = 'page-color-dark';
UPDATE settings SET value = '#a66ce8' WHERE setting_key = 'page-draft-color-dark';
EOF
echo "   ✓ Color palette applied"

# Clear cache
echo "3. Clearing application cache..."
docker compose exec bookstack php /app/www/artisan cache:clear > /dev/null 2>&1
echo "   ✓ Cache cleared"

echo ""
echo "LAPORTE theme applied successfully!"
echo ""
echo "Color Palette:"
echo "  Primary Dark Blue: #00263b"
echo "  Accent Golden Yellow: #E9B52D"
echo "  Background Light Blue: #eef6f9"
echo ""
echo "View at: https://learn.lceic.com"
