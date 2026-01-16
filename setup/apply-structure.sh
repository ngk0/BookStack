#!/bin/bash
# apply-structure.sh - Push structure.yaml changes to BookStack
#
# Usage: ./apply-structure.sh [--dry-run] [--force] [--verbose]
#
# This script compares the desired structure (structure.yaml) with the current
# BookStack state (hierarchy.json) and:
#   - Creates missing shelves, books, and chapters
#   - Updates descriptions that have changed
#   - Flags orphaned items (in BookStack but not in structure.yaml)
#
# Orphans are NEVER deleted automatically - they're written to orphans.json
# for manual review.

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/data/hierarchy"
STRUCTURE_FILE="${SCRIPT_DIR}/structure.yaml"
HIERARCHY_FILE="${OUTPUT_DIR}/hierarchy.json"
ORPHANS_FILE="${OUTPUT_DIR}/orphans.json"
LOG_FILE="${OUTPUT_DIR}/sync.log"

# CLI flags
VERBOSE=false
DRY_RUN=false
FORCE=false

# Counters
CREATED_SHELVES=0
CREATED_BOOKS=0
CREATED_CHAPTERS=0
UPDATED_SHELVES=0
UPDATED_BOOKS=0
UPDATED_CHAPTERS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--verbose] [--dry-run] [--force]" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Logging
# =============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [apply-structure] $*"
    echo "$msg" >> "$LOG_FILE"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$msg" >&2
    fi
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [apply-structure] ERROR: $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

log_action() {
    local action="$1"
    local type="$2"
    local name="$3"
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [apply-structure] ${action}: ${type} '${name}'"
    echo "$msg" >> "$LOG_FILE"
    if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] ${action}: ${type} '${name}'" >&2
        else
            echo "${action}: ${type} '${name}'" >&2
        fi
    fi
}

# =============================================================================
# Initialize
# =============================================================================

# Source API helpers
set +u
source "${SCRIPT_DIR}/api-helpers.sh" 2>/dev/null
set -u

# Check required files
if [[ ! -f "$STRUCTURE_FILE" ]]; then
    log_error "Structure file not found: $STRUCTURE_FILE"
    exit 1
fi

if [[ ! -f "$HIERARCHY_FILE" ]]; then
    log_error "Hierarchy file not found: $HIERARCHY_FILE"
    log_error "Run sync-hierarchy.sh first to generate it"
    exit 1
fi

log "=== Starting structure push ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "*** DRY RUN MODE - No changes will be made ***"
fi

# =============================================================================
# Load State
# =============================================================================

# Check for yq
if ! command -v yq &> /dev/null; then
    log_error "yq is required but not installed. Install with: sudo snap install yq"
    exit 1
fi

# Convert YAML structure to JSON format expected by the script
# YAML format: shelves.<name>.description, shelves.<name>.books.<name>.chapters.<name>: desc
# JSON format: shelves[].{name, description, books[].{name, description, chapters[].{name, description}}}
# Note: Using cat + pipe because snap yq has path confinement restrictions
convert_yaml_to_json() {
    cat "$STRUCTURE_FILE" | yq -o=json '
        {
            "shelves": [
                .shelves | to_entries[] | {
                    "name": .key,
                    "description": .value.description,
                    "books": [
                        .value.books | to_entries[] | {
                            "name": .key,
                            "description": .value.description,
                            "chapters": [
                                .value.chapters | to_entries[] | {
                                    "name": .key,
                                    "description": .value
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    '
}

DESIRED=$(convert_yaml_to_json)
CURRENT=$(cat "$HIERARCHY_FILE")

# =============================================================================
# Helper Functions
# =============================================================================

# Get shelf ID by name from current hierarchy
get_current_shelf_id() {
    local name="$1"
    echo "$CURRENT" | jq -r --arg name "$name" \
        '.hierarchy.shelves[] | select(.name == $name) | .id // empty'
}

# Get shelf description from current hierarchy
get_current_shelf_desc() {
    local name="$1"
    echo "$CURRENT" | jq -r --arg name "$name" \
        '.hierarchy.shelves[] | select(.name == $name) | .description // ""'
}

# Get book ID by name from current hierarchy
get_current_book_id() {
    local name="$1"
    echo "$CURRENT" | jq -r --arg name "$name" \
        '[.hierarchy.shelves[].books[] | select(.name == $name)] | .[0].id // empty'
}

# Get book description from current hierarchy
get_current_book_desc() {
    local name="$1"
    echo "$CURRENT" | jq -r --arg name "$name" \
        '[.hierarchy.shelves[].books[] | select(.name == $name)] | .[0].description // ""'
}

# Get chapter ID by name and book ID
get_current_chapter_id() {
    local chapter_name="$1"
    local book_name="$2"
    echo "$CURRENT" | jq -r --arg cname "$chapter_name" --arg bname "$book_name" \
        '[.hierarchy.shelves[].books[] | select(.name == $bname) | .chapters[]? | select(.name == $cname)] | .[0].id // empty'
}

# Get chapter description
get_current_chapter_desc() {
    local chapter_name="$1"
    local book_name="$2"
    echo "$CURRENT" | jq -r --arg cname "$chapter_name" --arg bname "$book_name" \
        '[.hierarchy.shelves[].books[] | select(.name == $bname) | .chapters[]? | select(.name == $cname)] | .[0].description // ""'
}

# Rate limit helper
rate_limit() {
    sleep 0.1
}

# =============================================================================
# Sync Shelves
# =============================================================================

sync_shelves() {
    log "Processing shelves..."

    # Iterate through desired shelves
    local shelves
    shelves=$(echo "$DESIRED" | jq -c '.shelves[]')

    while IFS= read -r shelf; do
        local name desc
        name=$(echo "$shelf" | jq -r '.name')
        desc=$(echo "$shelf" | jq -r '.description // ""')

        local current_id current_desc
        current_id=$(get_current_shelf_id "$name")
        current_desc=$(get_current_shelf_desc "$name")

        if [[ -z "$current_id" ]]; then
            # Shelf doesn't exist - create it
            log_action "CREATE" "shelf" "$name"
            if [[ "$DRY_RUN" != "true" ]]; then
                local result
                result=$(create_shelf "$name" "$desc")
                local new_id
                new_id=$(echo "$result" | jq -r '.id // empty')
                if [[ -n "$new_id" ]]; then
                    log "  Created shelf '$name' (ID: $new_id)"
                    CREATED_SHELVES=$((CREATED_SHELVES + 1))
                else
                    log_error "  Failed to create shelf '$name': $result"
                fi
                rate_limit
            else
                CREATED_SHELVES=$((CREATED_SHELVES + 1))
            fi
        elif [[ "$desc" != "$current_desc" ]]; then
            # Shelf exists but description changed - update it
            log_action "UPDATE" "shelf" "$name"
            if [[ "$DRY_RUN" != "true" ]]; then
                update_shelf "$current_id" "$name" "$desc"
                log "  Updated shelf '$name' (ID: $current_id)"
                UPDATED_SHELVES=$((UPDATED_SHELVES + 1))
                rate_limit
            else
                UPDATED_SHELVES=$((UPDATED_SHELVES + 1))
            fi
        else
            log "  Shelf '$name' is up to date"
        fi
    done <<< "$shelves"
}

# =============================================================================
# Sync Books
# =============================================================================

sync_books() {
    log "Processing books..."

    # Iterate through desired shelves and their books
    local shelves
    shelves=$(echo "$DESIRED" | jq -c '.shelves[]')

    while IFS= read -r shelf; do
        local shelf_name
        shelf_name=$(echo "$shelf" | jq -r '.name')
        local shelf_id
        shelf_id=$(get_current_shelf_id "$shelf_name")

        # If shelf was just created, we need to fetch its ID
        if [[ -z "$shelf_id" && "$DRY_RUN" != "true" ]]; then
            shelf_id=$(get_shelf_id_by_name "$shelf_name")
        fi

        local books
        books=$(echo "$shelf" | jq -c '.books[]?')

        while IFS= read -r book; do
            [[ -z "$book" ]] && continue

            local name desc
            name=$(echo "$book" | jq -r '.name')
            desc=$(echo "$book" | jq -r '.description // ""')

            local current_id current_desc
            current_id=$(get_current_book_id "$name")
            current_desc=$(get_current_book_desc "$name")

            if [[ -z "$current_id" ]]; then
                # Book doesn't exist - create it
                log_action "CREATE" "book" "$name"
                if [[ "$DRY_RUN" != "true" ]]; then
                    local result
                    result=$(create_book "$name" "$desc")
                    local new_id
                    new_id=$(echo "$result" | jq -r '.id // empty')
                    if [[ -n "$new_id" ]]; then
                        log "  Created book '$name' (ID: $new_id)"
                        # Add to shelf
                        if [[ -n "$shelf_id" ]]; then
                            add_book_to_shelf "$new_id" "$shelf_id" > /dev/null 2>&1 || true
                            log "  Added book to shelf '$shelf_name'"
                        fi
                        CREATED_BOOKS=$((CREATED_BOOKS + 1))
                    else
                        log_error "  Failed to create book '$name': $result"
                    fi
                    rate_limit
                else
                    CREATED_BOOKS=$((CREATED_BOOKS + 1))
                fi
            elif [[ "$desc" != "$current_desc" ]]; then
                # Book exists but description changed - update it
                log_action "UPDATE" "book" "$name"
                if [[ "$DRY_RUN" != "true" ]]; then
                    update_book "$current_id" "$name" "$desc"
                    log "  Updated book '$name' (ID: $current_id)"
                    UPDATED_BOOKS=$((UPDATED_BOOKS + 1))
                    rate_limit
                else
                    UPDATED_BOOKS=$((UPDATED_BOOKS + 1))
                fi
            else
                log "  Book '$name' is up to date"
            fi
        done <<< "$books"
    done <<< "$shelves"
}

# =============================================================================
# Sync Chapters
# =============================================================================

sync_chapters() {
    log "Processing chapters..."

    # Iterate through desired books and their chapters
    local shelves
    shelves=$(echo "$DESIRED" | jq -c '.shelves[]')

    while IFS= read -r shelf; do
        local books
        books=$(echo "$shelf" | jq -c '.books[]?')

        while IFS= read -r book; do
            [[ -z "$book" ]] && continue

            local book_name
            book_name=$(echo "$book" | jq -r '.name')
            local book_id
            book_id=$(get_current_book_id "$book_name")

            # If book was just created, we need to fetch its ID
            if [[ -z "$book_id" && "$DRY_RUN" != "true" ]]; then
                book_id=$(get_book_id_by_name "$book_name")
            fi

            local chapters
            chapters=$(echo "$book" | jq -c '.chapters[]?')

            while IFS= read -r chapter; do
                [[ -z "$chapter" ]] && continue

                local name desc
                name=$(echo "$chapter" | jq -r '.name')
                desc=$(echo "$chapter" | jq -r '.description // ""')

                local current_id current_desc
                current_id=$(get_current_chapter_id "$name" "$book_name")
                current_desc=$(get_current_chapter_desc "$name" "$book_name")

                if [[ -z "$current_id" ]]; then
                    # Chapter doesn't exist - create it
                    log_action "CREATE" "chapter" "$name (in $book_name)"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        if [[ -n "$book_id" ]]; then
                            local result
                            result=$(create_chapter "$name" "$desc" "$book_id")
                            local new_id
                            new_id=$(echo "$result" | jq -r '.id // empty')
                            if [[ -n "$new_id" ]]; then
                                log "  Created chapter '$name' (ID: $new_id)"
                                CREATED_CHAPTERS=$((CREATED_CHAPTERS + 1))
                            else
                                log_error "  Failed to create chapter '$name': $result"
                            fi
                        else
                            log_error "  Cannot create chapter '$name' - book '$book_name' not found"
                        fi
                        rate_limit
                    else
                        CREATED_CHAPTERS=$((CREATED_CHAPTERS + 1))
                    fi
                elif [[ "$desc" != "$current_desc" ]]; then
                    # Chapter exists but description changed - update it
                    log_action "UPDATE" "chapter" "$name (in $book_name)"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        update_chapter "$current_id" "$name" "$desc"
                        log "  Updated chapter '$name' (ID: $current_id)"
                        UPDATED_CHAPTERS=$((UPDATED_CHAPTERS + 1))
                        rate_limit
                    else
                        UPDATED_CHAPTERS=$((UPDATED_CHAPTERS + 1))
                    fi
                else
                    log "  Chapter '$name' is up to date"
                fi
            done <<< "$chapters"
        done <<< "$books"
    done <<< "$shelves"
}

# =============================================================================
# Find Orphans
# =============================================================================

find_orphans() {
    log "Checking for orphaned items..."

    local orphaned_shelves="[]"
    local orphaned_books="[]"
    local orphaned_chapters="[]"

    # Get all desired names
    local desired_shelf_names desired_book_names desired_chapter_names
    desired_shelf_names=$(echo "$DESIRED" | jq '[.shelves[].name]')
    desired_book_names=$(echo "$DESIRED" | jq '[.shelves[].books[].name]')
    desired_chapter_names=$(echo "$DESIRED" | jq '[.shelves[].books[].chapters[]?.name]')

    # Find orphaned shelves
    orphaned_shelves=$(echo "$CURRENT" | jq --argjson desired "$desired_shelf_names" '
        [.hierarchy.shelves[] | select([.name] | inside($desired) | not) |
         {id: .id, name: .name, url: .url}]
    ')

    # Find orphaned books
    orphaned_books=$(echo "$CURRENT" | jq --argjson desired "$desired_book_names" '
        [.hierarchy.shelves[].books[] | select([.name] | inside($desired) | not) |
         {id: .id, name: .name, url: .url}]
    ')

    # Find orphaned chapters
    orphaned_chapters=$(echo "$CURRENT" | jq --argjson desired "$desired_chapter_names" '
        [.hierarchy.shelves[].books[] as $book | $book.chapters[]? |
         select([.name] | inside($desired) | not) |
         {id: .id, name: .name, book: $book.name, url: .url}]
    ')

    # Count orphans
    local shelf_count book_count chapter_count
    shelf_count=$(echo "$orphaned_shelves" | jq 'length')
    book_count=$(echo "$orphaned_books" | jq 'length')
    chapter_count=$(echo "$orphaned_chapters" | jq 'length')

    if [[ "$shelf_count" -gt 0 || "$book_count" -gt 0 || "$chapter_count" -gt 0 ]]; then
        log "Found orphans: $shelf_count shelves, $book_count books, $chapter_count chapters"

        # Write orphans report
        local report
        report=$(jq -n \
            --arg generated "$(date -Iseconds)" \
            --argjson shelves "$orphaned_shelves" \
            --argjson books "$orphaned_books" \
            --argjson chapters "$orphaned_chapters" \
            '{
                generated_at: $generated,
                note: "These items exist in BookStack but not in structure.json. Review and delete manually if no longer needed.",
                orphaned_shelves: $shelves,
                orphaned_books: $books,
                orphaned_chapters: $chapters
            }')

        if [[ "$DRY_RUN" != "true" ]]; then
            echo "$report" > "$ORPHANS_FILE"
            log "Wrote orphans report to $ORPHANS_FILE"
        else
            log "[DRY-RUN] Would write orphans report to $ORPHANS_FILE"
        fi

        # Log details
        if [[ "$shelf_count" -gt 0 ]]; then
            log "  Orphaned shelves:"
            echo "$orphaned_shelves" | jq -r '.[] | "    - \(.name) (ID: \(.id))"' | while read -r line; do
                log "$line"
            done
        fi
        if [[ "$book_count" -gt 0 ]]; then
            log "  Orphaned books:"
            echo "$orphaned_books" | jq -r '.[] | "    - \(.name) (ID: \(.id))"' | while read -r line; do
                log "$line"
            done
        fi
        if [[ "$chapter_count" -gt 0 ]]; then
            log "  Orphaned chapters:"
            echo "$orphaned_chapters" | jq -r '.[] | "    - \(.name) in \(.book) (ID: \(.id))"' | while read -r line; do
                log "$line"
            done
        fi
    else
        log "No orphaned items found"
        # Clear orphans file if it exists
        if [[ -f "$ORPHANS_FILE" && "$DRY_RUN" != "true" ]]; then
            rm -f "$ORPHANS_FILE"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Verify API connectivity
    if ! check_api > /dev/null 2>&1; then
        log_error "Cannot connect to BookStack API"
        exit 1
    fi

    # Sync in order: shelves -> books -> chapters
    sync_shelves
    sync_books
    sync_chapters

    # Find orphans
    find_orphans

    # Summary
    log "=== Structure push complete ==="
    log "  Created: $CREATED_SHELVES shelves, $CREATED_BOOKS books, $CREATED_CHAPTERS chapters"
    log "  Updated: $UPDATED_SHELVES shelves, $UPDATED_BOOKS books, $UPDATED_CHAPTERS chapters"

    if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "Summary:"
        echo "  Created: $CREATED_SHELVES shelves, $CREATED_BOOKS books, $CREATED_CHAPTERS chapters"
        echo "  Updated: $UPDATED_SHELVES shelves, $UPDATED_BOOKS books, $UPDATED_CHAPTERS chapters"
        if [[ -f "$ORPHANS_FILE" ]]; then
            echo "  Orphans report: $ORPHANS_FILE"
        fi
    fi
}

main "$@"
