#!/bin/bash
# generate-content.sh - Generate module content via LLM
#
# Usage: ./generate-content.sh <chapter-url-or-id> [options]
#
# Options:
#   --track "Name"      Track name for context
#   --scope "Scope"     Track scope description
#   --roles "Roles"     Target roles (default: "Designer II → EIC Engineer II")
#   --model MODEL       OpenRouter model (default: anthropic/claude-sonnet-4)
#   --dry-run           Show prompt without calling API or creating pages
#   --no-create         Call API but don't create pages in BookStack
#
# Examples:
#   ./generate-content.sh https://learn.lceic.com/books/electrical-standards/chapter/power-distribution
#   ./generate-content.sh 45 --track "Power Distribution Design"
#   ./generate-content.sh 45 --dry-run

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HIERARCHY_FILE="${PROJECT_DIR}/data/hierarchy/hierarchy.json"
PROMPT_FILE="${SCRIPT_DIR}/prompts/module-template.md"

# Default model
DEFAULT_MODEL="anthropic/claude-sonnet-4"

# CLI options
CHAPTER_INPUT=""
TRACK_NAME=""
TRACK_SCOPE=""
TARGET_ROLES="Designer II → EIC Engineer II"
MODEL=""
DRY_RUN=false
NO_CREATE=false

# =============================================================================
# Parse Arguments
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 <chapter-url-or-id> [options]

Generate module content for a BookStack chapter using an LLM.

Arguments:
  chapter-url-or-id   BookStack chapter URL or numeric ID

Options:
  --track "Name"      Track name for context (will prompt if not provided)
  --scope "Scope"     Track scope description
  --roles "Roles"     Target roles (default: "$TARGET_ROLES")
  --model MODEL       OpenRouter model (default: $DEFAULT_MODEL)
  --dry-run, -n       Show prompt without calling API
  --no-create         Call API but don't create pages in BookStack
  --help, -h          Show this help

Examples:
  $0 https://learn.lceic.com/books/electrical-standards/chapter/power-distribution
  $0 45 --track "Power Distribution Design" --scope "Design 480V distribution systems"
  $0 45 --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --track|-t)
            TRACK_NAME="$2"
            shift 2
            ;;
        --scope|-s)
            TRACK_SCOPE="$2"
            shift 2
            ;;
        --roles|-r)
            TARGET_ROLES="$2"
            shift 2
            ;;
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --no-create)
            NO_CREATE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
        *)
            if [[ -z "$CHAPTER_INPUT" ]]; then
                CHAPTER_INPUT="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$CHAPTER_INPUT" ]]; then
    echo "ERROR: Chapter URL or ID required" >&2
    echo "Use --help for usage" >&2
    exit 1
fi

# =============================================================================
# Load Environment
# =============================================================================

if [[ -f "${SCRIPT_DIR}/.env.setup" ]]; then
    source "${SCRIPT_DIR}/.env.setup"
fi

# Set model
MODEL="${MODEL:-${OPENROUTER_MODEL:-$DEFAULT_MODEL}}"

# Check for API keys (not needed for dry-run)
if [[ "$DRY_RUN" != "true" && -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "ERROR: OPENROUTER_API_KEY not set" >&2
    echo "Add it to ${SCRIPT_DIR}/.env.setup" >&2
    exit 1
fi

# Source API helpers for BookStack (suppress output, not needed for dry-run)
if [[ "$DRY_RUN" != "true" ]]; then
    source "${SCRIPT_DIR}/api-helpers.sh" 2>/dev/null
fi

# =============================================================================
# Parse Chapter Input
# =============================================================================

CHAPTER_ID=""

# Check if input is a URL or ID
if [[ "$CHAPTER_INPUT" =~ ^https?:// ]]; then
    # Extract chapter slug from URL
    # URL format: https://learn.lceic.com/books/<book-slug>/chapter/<chapter-slug>
    if [[ "$CHAPTER_INPUT" =~ /chapter/([^/]+)$ ]]; then
        CHAPTER_SLUG="${BASH_REMATCH[1]}"
        echo "Extracted chapter slug: $CHAPTER_SLUG"

        # Look up chapter ID from hierarchy
        CHAPTER_ID=$(jq -r --arg slug "$CHAPTER_SLUG" '
            [.hierarchy.shelves[].books[].chapters[]? | select(.slug == $slug)] | .[0].id // empty
        ' "$HIERARCHY_FILE")
    else
        echo "ERROR: Could not parse chapter URL" >&2
        exit 1
    fi
elif [[ "$CHAPTER_INPUT" =~ ^[0-9]+$ ]]; then
    CHAPTER_ID="$CHAPTER_INPUT"
else
    echo "ERROR: Invalid input. Provide a chapter URL or numeric ID" >&2
    exit 1
fi

if [[ -z "$CHAPTER_ID" ]]; then
    echo "ERROR: Could not find chapter ID" >&2
    exit 1
fi

echo "Chapter ID: $CHAPTER_ID"

# =============================================================================
# Fetch Chapter Context from Hierarchy
# =============================================================================

echo "Loading chapter context from hierarchy.json..."

if [[ ! -f "$HIERARCHY_FILE" ]]; then
    echo "ERROR: Hierarchy file not found: $HIERARCHY_FILE" >&2
    echo "Run sync-hierarchy.sh first" >&2
    exit 1
fi

# Extract chapter details
CHAPTER_DATA=$(jq --argjson id "$CHAPTER_ID" '
    .hierarchy.shelves[] as $shelf |
    $shelf.books[] as $book |
    $book.chapters[]? | select(.id == $id) |
    {
        chapter_id: .id,
        chapter_name: .name,
        chapter_description: (.description // ""),
        chapter_slug: .slug,
        book_id: $book.id,
        book_name: $book.name,
        book_description: ($book.description // ""),
        shelf_name: $shelf.name,
        shelf_description: ($shelf.description // ""),
        sibling_chapters: [$book.chapters[]? | select(.id != $id) | {name: .name, description: (.description // "")}]
    }
' "$HIERARCHY_FILE" | head -1)

if [[ -z "$CHAPTER_DATA" || "$CHAPTER_DATA" == "null" ]]; then
    echo "ERROR: Chapter ID $CHAPTER_ID not found in hierarchy" >&2
    exit 1
fi

# Extract fields
CHAPTER_NAME=$(echo "$CHAPTER_DATA" | jq -r '.chapter_name')
CHAPTER_DESC=$(echo "$CHAPTER_DATA" | jq -r '.chapter_description')
BOOK_ID=$(echo "$CHAPTER_DATA" | jq -r '.book_id')
BOOK_NAME=$(echo "$CHAPTER_DATA" | jq -r '.book_name')
BOOK_DESC=$(echo "$CHAPTER_DATA" | jq -r '.book_description')
SHELF_NAME=$(echo "$CHAPTER_DATA" | jq -r '.shelf_name')
SIBLING_CHAPTERS=$(echo "$CHAPTER_DATA" | jq -r '.sibling_chapters | map("- \(.name): \(.description)") | join("\n")')

echo ""
echo "Context loaded:"
echo "  Shelf: $SHELF_NAME"
echo "  Book: $BOOK_NAME"
echo "  Chapter: $CHAPTER_NAME"
echo ""

# =============================================================================
# Interactive Prompts (if needed)
# =============================================================================

if [[ -z "$TRACK_NAME" ]]; then
    echo "Track name not provided. Using chapter name as track."
    TRACK_NAME="$CHAPTER_NAME"
fi

if [[ -z "$TRACK_SCOPE" ]]; then
    TRACK_SCOPE="$CHAPTER_DESC"
    if [[ -z "$TRACK_SCOPE" ]]; then
        TRACK_SCOPE="Module covering $CHAPTER_NAME within $BOOK_NAME"
    fi
fi

echo "Track: $TRACK_NAME"
echo "Scope: $TRACK_SCOPE"
echo "Roles: $TARGET_ROLES"
echo ""

# =============================================================================
# Build Prompt
# =============================================================================

echo "Building prompt..."

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ERROR: Prompt template not found: $PROMPT_FILE" >&2
    exit 1
fi

PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")

# Substitute placeholders
FULL_PROMPT="$PROMPT_TEMPLATE"
FULL_PROMPT="${FULL_PROMPT//\{\{TRACK_NAME\}\}/$TRACK_NAME}"
FULL_PROMPT="${FULL_PROMPT//\{\{TRACK_SCOPE\}\}/$TRACK_SCOPE}"
FULL_PROMPT="${FULL_PROMPT//\{\{TARGET_ROLES\}\}/$TARGET_ROLES}"
FULL_PROMPT="${FULL_PROMPT//\{\{SHELF_NAME\}\}/$SHELF_NAME}"
FULL_PROMPT="${FULL_PROMPT//\{\{BOOK_NAME\}\}/$BOOK_NAME}"
FULL_PROMPT="${FULL_PROMPT//\{\{BOOK_DESCRIPTION\}\}/$BOOK_DESC}"
FULL_PROMPT="${FULL_PROMPT//\{\{CHAPTER_NAME\}\}/$CHAPTER_NAME}"
FULL_PROMPT="${FULL_PROMPT//\{\{CHAPTER_DESCRIPTION\}\}/$CHAPTER_DESC}"
FULL_PROMPT="${FULL_PROMPT//\{\{SIBLING_CHAPTERS\}\}/$SIBLING_CHAPTERS}"

# =============================================================================
# Dry Run Output
# =============================================================================

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN MODE ==="
    echo "Model: $MODEL"
    echo "Chapter ID: $CHAPTER_ID"
    echo "Prompt length: ${#FULL_PROMPT} characters"
    echo ""
    echo "=== FULL PROMPT ==="
    echo "$FULL_PROMPT"
    echo ""
    echo "=== END DRY RUN ==="
    exit 0
fi

# =============================================================================
# Call OpenRouter API
# =============================================================================

echo "Calling OpenRouter API..."
echo "  Model: $MODEL"
echo "  This may take 30-60 seconds for a full module..."
echo ""

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
        max_tokens: 16000,
        temperature: 0.7
    }')

# Make API call
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://learn.lceic.com" \
    -H "X-Title: EIC Module Content Generator" \
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

echo "Content generated successfully!"
echo ""

# Save raw content
RAW_FILE="${PROJECT_DIR}/data/hierarchy/generated-${CHAPTER_ID}-$(date +%Y%m%d-%H%M%S).md"
echo "$CONTENT" > "$RAW_FILE"
echo "Raw content saved to: $RAW_FILE"

# Usage stats
USAGE=$(echo "$RESPONSE" | jq '.usage // empty')
if [[ -n "$USAGE" && "$USAGE" != "null" ]]; then
    echo ""
    echo "Token usage:"
    echo "$USAGE" | jq '.'
fi

# =============================================================================
# Parse Content into Pages
# =============================================================================

echo ""
echo "Parsing content into pages..."

# Split on PAGE_BREAK markers
# Format: ---PAGE_BREAK: Page Title---

declare -a PAGE_TITLES
declare -a PAGE_CONTENTS

# Use awk to split content
CURRENT_TITLE=""
CURRENT_CONTENT=""
PAGE_COUNT=0

while IFS= read -r line; do
    if [[ "$line" =~ ^---PAGE_BREAK:\ (.+)---$ ]]; then
        # Save previous page if exists
        if [[ -n "$CURRENT_TITLE" ]]; then
            PAGE_TITLES+=("$CURRENT_TITLE")
            PAGE_CONTENTS+=("$CURRENT_CONTENT")
            ((PAGE_COUNT++))
        fi
        CURRENT_TITLE="${BASH_REMATCH[1]}"
        CURRENT_CONTENT=""
    else
        CURRENT_CONTENT+="$line"$'\n'
    fi
done <<< "$CONTENT"

# Save last page
if [[ -n "$CURRENT_TITLE" ]]; then
    PAGE_TITLES+=("$CURRENT_TITLE")
    PAGE_CONTENTS+=("$CURRENT_CONTENT")
    ((PAGE_COUNT++))
fi

echo "Found $PAGE_COUNT pages:"
for i in "${!PAGE_TITLES[@]}"; do
    echo "  $((i+1)). ${PAGE_TITLES[$i]}"
done

# =============================================================================
# Create Pages in BookStack
# =============================================================================

if [[ "$NO_CREATE" == "true" ]]; then
    echo ""
    echo "=== NO-CREATE MODE ==="
    echo "Pages would be created but --no-create was specified"
    echo "Content saved to: $RAW_FILE"
    exit 0
fi

if [[ $PAGE_COUNT -eq 0 ]]; then
    echo ""
    echo "WARNING: No pages parsed from content"
    echo "The LLM may not have used the correct PAGE_BREAK format"
    echo "Check the raw content: $RAW_FILE"
    exit 1
fi

echo ""
echo "Creating pages in BookStack..."

CREATED_COUNT=0
for i in "${!PAGE_TITLES[@]}"; do
    PAGE_TITLE="${PAGE_TITLES[$i]}"
    PAGE_CONTENT="${PAGE_CONTENTS[$i]}"
    PAGE_ORDER=$((i + 1))

    echo "  Creating: $PAGE_TITLE (order: $PAGE_ORDER)..."

    # Create page via API
    RESULT=$(jq -n \
        --arg name "$PAGE_TITLE" \
        --arg content "$PAGE_CONTENT" \
        --argjson chapter "$CHAPTER_ID" \
        --argjson priority "$PAGE_ORDER" \
        '{
            name: $name,
            markdown: $content,
            chapter_id: $chapter,
            priority: $priority,
            tags: [
                {name: "status", value: "draft"},
                {name: "generated", value: "llm"}
            ]
        }' | api_post "/pages" - 2>/dev/null || echo '{"error": "API call failed"}')

    if echo "$RESULT" | jq -e '.id' > /dev/null 2>&1; then
        PAGE_ID=$(echo "$RESULT" | jq -r '.id')
        echo "    Created page ID: $PAGE_ID"
        ((CREATED_COUNT++))
    else
        echo "    ERROR: Failed to create page" >&2
        echo "    $RESULT" >&2
    fi

    # Rate limit
    sleep 0.2
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================"
echo "GENERATION COMPLETE"
echo "============================================================"
echo ""
echo "Chapter: $CHAPTER_NAME (ID: $CHAPTER_ID)"
echo "Pages created: $CREATED_COUNT / $PAGE_COUNT"
echo "Raw content: $RAW_FILE"
echo ""
echo "View in BookStack:"
echo "  https://learn.lceic.com/books/${BOOK_NAME// /-}/chapter/${CHAPTER_NAME// /-}"
echo ""
echo "Pages are tagged with status:draft - review and update status when ready."
