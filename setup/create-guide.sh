#!/bin/bash
# Create "How to Use This BookStack" Guide
# Deploys the user guide book and pages via the BookStack API
#
# Usage: ./create-guide.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source API helpers
source "${SCRIPT_DIR}/api-helpers.sh"

# Configuration
GUIDE_DIR="${SCRIPT_DIR}/templates/guide"
BOOK_NAME="How to Use This BookStack"
BOOK_DESCRIPTION="Complete guide to using our BookStack knowledge base - navigation, editing, roles, and best practices"
SHELF_NAME="Getting Started"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Page definitions (order matters for display)
declare -A PAGES=(
    ["01"]="Introduction & Purpose|01-introduction.md"
    ["02"]="Content Organization|02-content-organization.md"
    ["03"]="Finding Information|03-finding-information.md"
    ["04"]="Editing & Contributing|04-editing-contributing.md"
    ["05"]="Roles & Permissions|05-roles-permissions.md"
    ["06"]="Tag Workflow|06-tag-workflow.md"
    ["07"]="Best Practices|07-best-practices.md"
)

# =============================================================================
# Helper Functions
# =============================================================================

# Read markdown file content
read_markdown() {
    local file="$1"
    cat "$file"
}

# Create a page with markdown content
create_page_with_content() {
    local name="$1"
    local content="$2"
    local book_id="$3"
    local tags="${4:-[]}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg content "$content" \
        --argjson book "$book_id" \
        --argjson tags "$tags" \
        '{name: $name, markdown: $content, book_id: $book, tags: $tags}')

    api_post "/pages" "$data"
}

# Check if page exists in book
get_page_id_by_name_in_book() {
    local name="$1"
    local book_id="$2"
    api_get "/pages" | jq -r --arg name "$name" --argjson book "$book_id" \
        '.data[] | select(.name == $name and .book_id == $book) | .id // empty'
}

# Update existing page
update_page() {
    local page_id="$1"
    local content="$2"
    local tags="${3:-[]}"

    local data
    data=$(jq -n \
        --arg content "$content" \
        --argjson tags "$tags" \
        '{markdown: $content, tags: $tags}')

    api_put "/pages/${page_id}" "$data"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "Creating BookStack User Guide"
    log "=============================="
    log ""

    if $DRY_RUN; then
        log "*** DRY RUN MODE - No changes will be made ***"
        log ""
    fi

    # Check API connectivity
    log "Checking API connectivity..."
    if ! check_api > /dev/null 2>&1; then
        log_error "Cannot connect to BookStack API"
        exit 1
    fi
    log "API connection successful"
    log ""

    # Get the Getting Started shelf ID
    log "Finding '${SHELF_NAME}' shelf..."
    local shelf_id
    shelf_id=$(get_shelf_id_by_name "$SHELF_NAME")
    if [[ -z "$shelf_id" ]]; then
        log_error "Shelf '${SHELF_NAME}' not found"
        exit 1
    fi
    log "Found shelf ID: $shelf_id"
    log ""

    # Create or get the book
    log "Creating book: ${BOOK_NAME}"
    local book_id
    if $DRY_RUN; then
        log "[DRY-RUN] Would create book: ${BOOK_NAME}"
        book_id="DRY-RUN"
    else
        book_id=$(get_book_id_by_name "$BOOK_NAME")
        if [[ -n "$book_id" ]]; then
            log "Book already exists (ID: $book_id)"
        else
            local book_result
            book_result=$(create_book "$BOOK_NAME" "$BOOK_DESCRIPTION")
            book_id=$(echo "$book_result" | jq -r '.id')
            log "Created book (ID: $book_id)"

            # Add book to shelf
            log "Adding book to shelf..."
            add_book_to_shelf "$book_id" "$shelf_id" > /dev/null 2>&1 || true
        fi
    fi
    log ""

    # Create pages
    log "Creating pages..."
    local tags='[{"name": "status:approved", "value": ""}]'

    # Sort keys to ensure correct order
    for key in $(echo "${!PAGES[@]}" | tr ' ' '\n' | sort); do
        local page_info="${PAGES[$key]}"
        local page_name="${page_info%%|*}"
        local page_file="${page_info##*|}"
        local file_path="${GUIDE_DIR}/${page_file}"

        if [[ ! -f "$file_path" ]]; then
            log_error "Content file not found: $file_path"
            continue
        fi

        if $DRY_RUN; then
            log "[DRY-RUN] Would create page: ${page_name}"
            continue
        fi

        # Check if page exists
        local existing_page_id
        existing_page_id=$(get_page_id_by_name_in_book "$page_name" "$book_id" 2>/dev/null || echo "")

        # Read content
        local content
        content=$(read_markdown "$file_path")

        if [[ -n "$existing_page_id" ]]; then
            log "  Updating page: ${page_name} (ID: $existing_page_id)"
            update_page "$existing_page_id" "$content" "$tags" > /dev/null
        else
            log "  Creating page: ${page_name}"
            local page_result
            page_result=$(create_page_with_content "$page_name" "$content" "$book_id" "$tags")
            local page_id
            page_id=$(echo "$page_result" | jq -r '.id // empty')
            if [[ -n "$page_id" ]]; then
                log "    Created (ID: $page_id)"
            else
                log_error "    Failed to create page: $page_result"
            fi
        fi
    done

    log ""
    log "=============================="
    log "Guide creation complete!"

    if $DRY_RUN; then
        log ""
        log "This was a dry run. Run without --dry-run to apply changes."
    else
        log ""
        log "View the guide at: https://learn.lceic.com/books/how-to-use-this-bookstack"
    fi
}

main "$@"
