#!/bin/bash
# BookStack Configuration Script
# Creates shelves, books, chapters, and roles via the BookStack API
#
# Usage: ./configure-bookstack.sh [--dry-run] [--roles-only] [--content-only]
#
# Options:
#   --dry-run       Show what would be created without making changes
#   --roles-only    Only create/verify roles
#   --content-only  Only create content structure (shelves, books, chapters)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source API helpers
source "${SCRIPT_DIR}/api-helpers.sh"

# Configuration
STRUCTURE_FILE="${SCRIPT_DIR}/structure.json"
DRY_RUN=false
ROLES_ONLY=false
CONTENT_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --roles-only)
            ROLES_ONLY=true
            shift
            ;;
        --content-only)
            CONTENT_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

# Read structure.json
read_structure() {
    if [[ ! -f "$STRUCTURE_FILE" ]]; then
        log_error "Structure file not found: $STRUCTURE_FILE"
        exit 1
    fi
    cat "$STRUCTURE_FILE"
}

# Count items in structure
count_shelves() {
    read_structure | jq '.shelves | length'
}

count_books() {
    read_structure | jq '[.shelves[].books[]] | length'
}

count_chapters() {
    read_structure | jq '[.shelves[].books[].chapters[]?] | length'
}

count_roles() {
    read_structure | jq '.roles | length'
}

# =============================================================================
# Role Creation
# =============================================================================

create_roles() {
    log "=== Creating Roles ==="

    local roles
    roles=$(read_structure | jq -c '.roles[]')

    while IFS= read -r role; do
        local name description permissions
        name=$(echo "$role" | jq -r '.name')
        description=$(echo "$role" | jq -r '.description')
        permissions=$(echo "$role" | jq -c '.permissions')

        if $DRY_RUN; then
            log "[DRY-RUN] Would create role: $name"
            continue
        fi

        local existing_id
        existing_id=$(get_role_id_by_name "$name" 2>/dev/null || echo "")

        if [[ -n "$existing_id" ]]; then
            log "Role '$name' already exists (ID: $existing_id)"
        else
            log "Creating role: $name"
            local result
            result=$(create_role "$name" "$description" "$permissions")
            local new_id
            new_id=$(echo "$result" | jq -r '.id // empty')
            if [[ -n "$new_id" ]]; then
                log "  Created role '$name' (ID: $new_id)"
            else
                log_error "  Failed to create role '$name': $result"
            fi
        fi
    done <<< "$roles"

    log "=== Roles Complete ==="
}

# =============================================================================
# Content Structure Creation
# =============================================================================

create_content_structure() {
    log "=== Creating Content Structure ==="

    local shelves
    shelves=$(read_structure | jq -c '.shelves[]')

    while IFS= read -r shelf; do
        local shelf_name shelf_desc
        shelf_name=$(echo "$shelf" | jq -r '.name')
        shelf_desc=$(echo "$shelf" | jq -r '.description')

        if $DRY_RUN; then
            log "[DRY-RUN] Would create shelf: $shelf_name"
        else
            log "Processing shelf: $shelf_name"
        fi

        # Create or get shelf
        local shelf_id
        if $DRY_RUN; then
            shelf_id="DRY-RUN"
        else
            shelf_id=$(ensure_shelf "$shelf_name" "$shelf_desc")
        fi

        # Process books in this shelf
        local books
        books=$(echo "$shelf" | jq -c '.books[]')

        while IFS= read -r book; do
            local book_name book_desc
            book_name=$(echo "$book" | jq -r '.name')
            book_desc=$(echo "$book" | jq -r '.description')

            if $DRY_RUN; then
                log "[DRY-RUN]   Would create book: $book_name"
            else
                log "  Processing book: $book_name"
            fi

            # Create or get book
            local book_id
            if $DRY_RUN; then
                book_id="DRY-RUN"
            else
                book_id=$(ensure_book "$book_name" "$book_desc")

                # Add book to shelf if not already there
                if [[ -n "$shelf_id" && -n "$book_id" ]]; then
                    add_book_to_shelf "$book_id" "$shelf_id" > /dev/null 2>&1 || true
                fi
            fi

            # Process chapters in this book
            local chapters
            chapters=$(echo "$book" | jq -c '.chapters[]?' 2>/dev/null || echo "")

            if [[ -n "$chapters" ]]; then
                while IFS= read -r chapter; do
                    local chapter_name chapter_desc
                    chapter_name=$(echo "$chapter" | jq -r '.name')
                    chapter_desc=$(echo "$chapter" | jq -r '.description')

                    if $DRY_RUN; then
                        log "[DRY-RUN]     Would create chapter: $chapter_name"
                    else
                        # Check if chapter exists
                        local existing_chapter_id
                        existing_chapter_id=$(get_chapter_id_by_name "$chapter_name" "$book_id" 2>/dev/null || echo "")

                        if [[ -n "$existing_chapter_id" ]]; then
                            log "    Chapter '$chapter_name' already exists (ID: $existing_chapter_id)"
                        else
                            log "    Creating chapter: $chapter_name"
                            local result
                            result=$(create_chapter "$chapter_name" "$chapter_desc" "$book_id")
                            local chapter_id
                            chapter_id=$(echo "$result" | jq -r '.id // empty')
                            if [[ -n "$chapter_id" ]]; then
                                log "    Created chapter '$chapter_name' (ID: $chapter_id)"
                            else
                                log_error "    Failed to create chapter '$chapter_name': $result"
                            fi
                        fi
                    fi
                done <<< "$chapters"
            fi

        done <<< "$books"

    done <<< "$shelves"

    log "=== Content Structure Complete ==="
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "BookStack Configuration Script"
    log "=============================="
    log ""

    if $DRY_RUN; then
        log "*** DRY RUN MODE - No changes will be made ***"
        log ""
    fi

    # Show structure summary
    log "Structure Summary:"
    log "  Shelves:  $(count_shelves)"
    log "  Books:    $(count_books)"
    log "  Chapters: $(count_chapters)"
    log "  Roles:    $(count_roles)"
    log ""

    # Verify API connectivity
    log "Checking API connectivity..."
    if ! check_api > /dev/null 2>&1; then
        log_error "Cannot connect to BookStack API at ${BOOKSTACK_URL}"
        log_error "Please verify:"
        log_error "  1. BookStack is running"
        log_error "  2. API credentials in .env.setup are correct"
        log_error "  3. Network connectivity to ${BOOKSTACK_URL}"
        exit 1
    fi
    log "API connection successful"
    log ""

    # Create roles (unless content-only mode)
    if ! $CONTENT_ONLY; then
        create_roles
        log ""
    fi

    # Create content structure (unless roles-only mode)
    if ! $ROLES_ONLY; then
        create_content_structure
        log ""
    fi

    log "=============================="
    log "Configuration complete!"

    if $DRY_RUN; then
        log ""
        log "This was a dry run. Run without --dry-run to apply changes."
    fi
}

main "$@"
