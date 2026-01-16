#!/bin/bash
# enhance-structure.sh - LLM-powered structure review
#
# Usage: ./enhance-structure.sh [--model MODEL] [--dry-run]
#
# Options:
#   --model MODEL   OpenRouter model (default: anthropic/claude-sonnet-4)
#   --dry-run       Show what would be sent, don't call API
#
# Environment:
#   OPENROUTER_API_KEY  Required. Set in .env.setup
#   OPENROUTER_MODEL    Optional default model
#
# Examples:
#   ./enhance-structure.sh
#   ./enhance-structure.sh --model "deepseek/deepseek-r1"
#   ./enhance-structure.sh --dry-run

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STRUCTURE_FILE="${SCRIPT_DIR}/structure.yaml"
PROMPT_FILE="${SCRIPT_DIR}/prompts/structure-review.md"
BACKUP_DIR="${PROJECT_DIR}/data/hierarchy/backups"

# Default model
DEFAULT_MODEL="anthropic/claude-sonnet-4"

# CLI flags
DRY_RUN=false
MODEL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--model MODEL] [--dry-run]"
            echo ""
            echo "Options:"
            echo "  --model, -m MODEL   OpenRouter model (default: $DEFAULT_MODEL)"
            echo "  --dry-run, -n       Show prompt without calling API"
            echo "  --help, -h          Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Load Environment
# =============================================================================

if [[ -f "${SCRIPT_DIR}/.env.setup" ]]; then
    source "${SCRIPT_DIR}/.env.setup"
fi

# Set model (CLI > env > default)
MODEL="${MODEL:-${OPENROUTER_MODEL:-$DEFAULT_MODEL}}"

# Check for API key (not needed for dry-run)
if [[ "$DRY_RUN" != "true" && -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY not set" >&2
    echo "Add it to ${SCRIPT_DIR}/.env.setup:" >&2
    echo '  OPENROUTER_API_KEY="sk-or-..."' >&2
    exit 1
fi

# =============================================================================
# Verify Files
# =============================================================================

if [[ ! -f "$STRUCTURE_FILE" ]]; then
    echo "ERROR: Structure file not found: $STRUCTURE_FILE" >&2
    exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ERROR: Prompt template not found: $PROMPT_FILE" >&2
    exit 1
fi

# =============================================================================
# Backup
# =============================================================================

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/structure-$(date +%Y%m%d-%H%M%S).yaml"

if [[ "$DRY_RUN" != "true" ]]; then
    cp "$STRUCTURE_FILE" "$BACKUP_FILE"
    echo "Backed up to: $BACKUP_FILE"
fi

# =============================================================================
# Build Prompt
# =============================================================================

echo "Building prompt..."

# Read template and structure
PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")
STRUCTURE_CONTENT=$(cat "$STRUCTURE_FILE")

# Substitute placeholder
FULL_PROMPT="${PROMPT_TEMPLATE//\{\{STRUCTURE_YAML\}\}/$STRUCTURE_CONTENT}"

# =============================================================================
# Dry Run Output
# =============================================================================

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN MODE ==="
    echo "Model: $MODEL"
    echo "Prompt length: ${#FULL_PROMPT} characters"
    echo ""
    echo "=== PROMPT PREVIEW (first 2000 chars) ==="
    echo "${FULL_PROMPT:0:2000}"
    echo "..."
    echo ""
    echo "=== END DRY RUN ==="
    exit 0
fi

# =============================================================================
# Call OpenRouter API
# =============================================================================

echo "Calling OpenRouter API..."
echo "  Model: $MODEL"

# Build JSON payload
PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$FULL_PROMPT" \
    '{
        model: $model,
        messages: [
            {
                role: "user",
                content: $prompt
            }
        ],
        max_tokens: 4096,
        temperature: 0.7
    }')

# Make API call
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://learn.lceic.com" \
    -H "X-Title: EIC BookStack Structure Review" \
    -d "$PAYLOAD")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "ERROR: API call failed" >&2
    echo "$RESPONSE" | jq '.error' >&2
    exit 1
fi

# Extract content
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$CONTENT" ]]; then
    echo "ERROR: No content in response" >&2
    echo "$RESPONSE" | jq '.' >&2
    exit 1
fi

# =============================================================================
# Output Results
# =============================================================================

echo ""
echo "============================================================"
echo "STRUCTURE REVIEW SUGGESTIONS"
echo "============================================================"
echo ""
echo "$CONTENT"
echo ""
echo "============================================================"
echo ""

# Save to file
OUTPUT_FILE="${PROJECT_DIR}/data/hierarchy/structure-suggestions-$(date +%Y%m%d-%H%M%S).md"
echo "$CONTENT" > "$OUTPUT_FILE"
echo "Suggestions saved to: $OUTPUT_FILE"

# Usage stats
USAGE=$(echo "$RESPONSE" | jq '.usage // empty')
if [[ -n "$USAGE" ]]; then
    echo ""
    echo "Token usage:"
    echo "$USAGE" | jq '.'
fi
