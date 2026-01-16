#!/usr/bin/env bash
# =============================================================================
# validate-env.sh - Validate environment configuration for BookStack
# =============================================================================
# Usage: ./validate-env.sh [--fix]
#
# Checks:
#   1. .env exists and has correct permissions (600)
#   2. .env.setup exists and has correct permissions (600)
#   3. Required variables are set and non-empty
#
# Options:
#   --fix   Attempt to fix permission issues automatically
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FIX_MODE=false
ERRORS=0
WARNINGS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_error() {
    echo -e "${RED}ERROR:${NC} $1"
    ((ERRORS++))
}

log_warn() {
    echo -e "${YELLOW}WARN:${NC} $1"
    ((WARNINGS++))
}

log_ok() {
    echo -e "${GREEN}OK:${NC} $1"
}

check_file_exists() {
    local file="$1"
    local name="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "$name not found: $file"
        echo "       Copy from ${file}.example and fill in values"
        return 1
    fi
    return 0
}

check_permissions() {
    local file="$1"
    local name="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    local perms
    perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null)
    
    if [[ "$perms" != "600" ]]; then
        if $FIX_MODE; then
            chmod 600 "$file"
            log_ok "$name permissions fixed to 600"
        else
            log_error "$name has insecure permissions: $perms (should be 600)"
            echo "       Run: chmod 600 $file"
            return 1
        fi
    else
        log_ok "$name has correct permissions (600)"
    fi
    return 0
}

check_var_set() {
    local file="$1"
    local var="$2"
    local description="$3"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # Extract value (handles quotes and inline comments)
    local value
    value=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)
    
    if [[ -z "$value" ]]; then
        log_error "$var is not set in $(basename "$file")"
        echo "       $description"
        return 1
    elif [[ "$value" == changeme* ]]; then
        log_error "$var contains placeholder value in $(basename "$file")"
        echo "       $description"
        return 1
    else
        log_ok "$var is set"
    fi
    return 0
}

echo "=============================================="
echo "BookStack Environment Validation"
echo "=============================================="
echo ""

# Check .env file
echo "--- Checking .env ---"
ENV_FILE="$PROJECT_ROOT/.env"

if check_file_exists "$ENV_FILE" ".env"; then
    check_permissions "$ENV_FILE" ".env"
    
    # Required variables for Docker Compose
    check_var_set "$ENV_FILE" "APP_KEY" "Generate with: echo \"base64:\$(openssl rand -base64 32)\""
    check_var_set "$ENV_FILE" "DB_PASSWORD" "Generate with: openssl rand -base64 24"
    check_var_set "$ENV_FILE" "DB_ROOT_PASSWORD" "Generate with: openssl rand -base64 24"
fi

echo ""

# Check .env.setup file
echo "--- Checking setup/.env.setup ---"
SETUP_ENV_FILE="$SCRIPT_DIR/.env.setup"

if check_file_exists "$SETUP_ENV_FILE" ".env.setup"; then
    check_permissions "$SETUP_ENV_FILE" ".env.setup"
    
    # Required variables for API scripts
    check_var_set "$SETUP_ENV_FILE" "BOOKSTACK_URL" "BookStack instance URL (e.g., https://learn.lceic.com)"
    check_var_set "$SETUP_ENV_FILE" "BOOKSTACK_TOKEN_ID" "API token ID from BookStack Settings > API Tokens"
    check_var_set "$SETUP_ENV_FILE" "BOOKSTACK_TOKEN_SECRET" "API token secret from BookStack Settings > API Tokens"
fi

echo ""
echo "=============================================="

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}Validation failed with $ERRORS error(s)${NC}"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}Validation passed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo -e "${GREEN}All checks passed${NC}"
    exit 0
fi
