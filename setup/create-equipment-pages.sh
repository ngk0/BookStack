#!/bin/bash
# Create Equipment Class Documentation Pages in Bookstack
# Generates AI-enhanced pages for each eic-equip library with placeholder sections
#
# Usage: ./create-equipment-pages.sh [--dry-run] [--verbose] [--library LIBRARY_NAME]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/api-helpers.sh"

# Configuration
EIC_EQUIP_DIR="/srv/stacks/work/eic-equip/repo"
LIBRARY_MAP="${SCRIPT_DIR}/equipment-library-map.json"
BOOK_ID=361  # Basis of Design Equipment

# Default tags for all pages
DEFAULT_TAGS='[{"name": "status:draft"}, {"name": "source:eic-equip"}]'

# Chapter cache to avoid creating duplicates
declare -A CHAPTER_CACHE

# Parse arguments
DRY_RUN=false
VERBOSE=false
SINGLE_LIBRARY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --library)
            SINGLE_LIBRARY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Logging
log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "$@"
    fi
}

# ============================================================================
# Chapter Management
# ============================================================================

# Initialize chapter cache from existing chapters
init_chapter_cache() {
    log_verbose "Initializing chapter cache..."
    local chapters
    chapters=$(api_get "/chapters?count=500" | jq -c "[.data[] | select(.book_id == $BOOK_ID)]")
    
    while IFS= read -r chapter; do
        local id name
        id=$(echo "$chapter" | jq -r '.id')
        name=$(echo "$chapter" | jq -r '.name')
        CHAPTER_CACHE["$name"]="$id"
        log_verbose "  Cached: '$name' -> $id"
    done < <(echo "$chapters" | jq -c '.[]')
}

# Get or create chapter for a category
# Usage: get_or_create_chapter "chapter_name" "description"
# Returns: chapter_id
get_or_create_chapter() {
    local name="$1"
    local description="${2:-}"
    
    # Check cache first
    if [[ -n "${CHAPTER_CACHE[$name]:-}" ]]; then
        log_verbose "Chapter cached: $name (ID: ${CHAPTER_CACHE[$name]})"
        echo "${CHAPTER_CACHE[$name]}"
        return 0
    fi
    
    # Create new chapter
    log "Creating chapter: $name"
    if [[ "$DRY_RUN" == "true" ]]; then
        CHAPTER_CACHE["$name"]="DRY_RUN_CHAPTER_ID"
        echo "DRY_RUN_CHAPTER_ID"
        return 0
    fi
    
    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        --argjson book "$BOOK_ID" \
        '{name: $name, description: $desc, book_id: $book}')
    
    local chapter_id
    chapter_id=$(api_post "/chapters" "$data" | jq -r '.id')
    CHAPTER_CACHE["$name"]="$chapter_id"
    log "Created chapter: $name (ID: $chapter_id)"
    echo "$chapter_id"
}

# ============================================================================
# Page Content Generation
# ============================================================================

# Read and parse library README
# Usage: get_library_readme "LIBRARY_NAME"
get_library_readme() {
    local library="$1"
    local readme_path="${EIC_EQUIP_DIR}/${library}/README.md"
    
    if [[ -f "$readme_path" ]]; then
        cat "$readme_path"
    else
        echo "No README available for this library."
    fi
}

# Generate enhanced page content for a library
# Usage: generate_page_content "LIBRARY_NAME"
generate_page_content() {
    local library="$1"
    
    # Get metadata from library map
    local display_name short_name manufacturer
    display_name=$(jq -r --arg lib "$library" '.library_metadata[$lib].display_name // $lib' "$LIBRARY_MAP")
    short_name=$(jq -r --arg lib "$library" '.library_metadata[$lib].short_name // $lib' "$LIBRARY_MAP")
    manufacturer=$(jq -r --arg lib "$library" '.library_metadata[$lib].manufacturer // "Various"' "$LIBRARY_MAP")
    
    # Get README content
    local readme
    readme=$(get_library_readme "$library")
    
    # Extract key sections from README
    local overview cross_refs key_notes
    overview=$(echo "$readme" | sed -n '/^## Overview/,/^## /p' | sed '1d;$d' || echo "")
    cross_refs=$(echo "$readme" | sed -n '/^## Cross-References/,/^## /p' | sed '1d;$d' || echo "")
    key_notes=$(echo "$readme" | sed -n '/^## Key Design Notes/,/^## /p' | sed '1d;$d' || echo "")
    
    # Generate the page content
    cat << CONTENT_EOF
# ${display_name}

> **Manufacturer:** ${manufacturer}
> **Selection Library:** \`${library}\`
> **Source:** eic-equip repository

---

## Overview

${overview:-This library contains standardized equipment selections for ${display_name}.}

## Key Design Notes

${key_notes:-Refer to the selection spreadsheet for detailed specifications and design guidance.}

## Selection Guidance

When selecting equipment from this library:

1. **Identify the application requirements** — voltage, current, environment, etc.
2. **Consult the selection spreadsheet** — filter by specifications to find matching products
3. **Verify with manufacturer documentation** — always confirm specs against current datasheets
4. **Consider cross-references** — this equipment integrates with other library selections

## Cross-References

${cross_refs:-This library integrates with other equipment in the eic-equip repository.}

---

## Documentation Resources

### Selection Spreadsheets

| Document | Egnyte Path |
|----------|-------------|
| Master Selection Table | **[PENDING]** |
| Quick Reference Guide | **[PENDING]** |

### Product Documentation

| Folder | Egnyte Path |
|--------|-------------|
| Datasheets | **[PENDING]** |
| Installation Manuals | **[PENDING]** |
| User Guides | **[PENDING]** |
| Brochures | **[PENDING]** |

### Design Resources

| Resource | Egnyte Path |
|----------|-------------|
| CAD Blocks / Symbols | **[PENDING]** |
| Specifications | **[PENDING]** |
| Application Notes | **[PENDING]** |

---

*This page was auto-generated from the eic-equip repository. Content will be enhanced with Egnyte paths once the documentation folder structure is established.*
CONTENT_EOF
}

# ============================================================================
# Page Creation
# ============================================================================

# Check if page exists in chapter
# Usage: page_exists "page_name" chapter_id
page_exists() {
    local name="$1"
    local chapter_id="$2"
    
    local page_id
    page_id=$(api_get "/pages?count=500" | jq -r --arg name "$name" --argjson chapter "$chapter_id" \
        '.data[] | select(.name == $name and .chapter_id == $chapter) | .id // empty' | head -1)
    
    [[ -n "$page_id" ]]
}

# Create a page in a chapter
# Usage: create_equipment_page "LIBRARY_NAME" chapter_id
create_equipment_page() {
    local library="$1"
    local chapter_id="$2"
    
    # Get display name
    local display_name
    display_name=$(jq -r --arg lib "$library" '.library_metadata[$lib].display_name // $lib' "$LIBRARY_MAP")
    
    # Check if page exists (skip for dry run with dummy chapter ID)
    if [[ "$chapter_id" != "DRY_RUN_CHAPTER_ID" ]]; then
        if page_exists "$display_name" "$chapter_id"; then
            log "Page exists: $display_name (skipping)"
            return 0
        fi
    fi
    
    log "Creating page: $display_name"
    
    # Generate content
    local content
    content=$(generate_page_content "$library")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_verbose "DRY RUN: Would create page '$display_name' in chapter $chapter_id"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "--- Content Preview (first 20 lines) ---"
            echo "$content" | head -20
            echo "--- End Preview ---"
        fi
        return 0
    fi
    
    # Create the page
    local data
    data=$(jq -n \
        --arg name "$display_name" \
        --arg content "$content" \
        --argjson chapter "$chapter_id" \
        --argjson tags "$DEFAULT_TAGS" \
        '{name: $name, markdown: $content, chapter_id: $chapter, tags: $tags}')
    
    local response
    response=$(api_post "/pages" "$data")
    
    local page_id
    page_id=$(echo "$response" | jq -r '.id // empty')
    
    if [[ -n "$page_id" ]]; then
        log "Created page: $display_name (ID: $page_id)"
    else
        log_error "Failed to create page: $display_name"
        log_error "Response: $response"
        return 1
    fi
}

# ============================================================================
# Main Processing
# ============================================================================

# Map libraries to their chapter assignments
# Returns: chapter_id for the library
get_chapter_for_library() {
    local library="$1"
    
    # Check existing chapters first (from JSON map)
    local existing_chapters
    existing_chapters=$(jq -r '.existing_chapters | to_entries[] | "\(.key):\(.value.covers[])"' "$LIBRARY_MAP")
    
    local entry chapter_id covered_lib
    while IFS= read -r entry; do
        chapter_id="${entry%%:*}"
        covered_lib="${entry#*:}"
        if [[ "$covered_lib" == "$library" ]]; then
            echo "$chapter_id"
            return 0
        fi
    done <<< "$existing_chapters"
    
    # Find category for this library and create/get chapter
    local category=""
    local categories cat
    categories=$(jq -r '.categories | keys[]' "$LIBRARY_MAP")
    
    while IFS= read -r cat; do
        if jq -e --arg lib "$library" --arg cat "$cat" '.categories[$cat].libraries | index($lib)' "$LIBRARY_MAP" > /dev/null 2>&1; then
            category="$cat"
            break
        fi
    done <<< "$categories"
    
    if [[ -z "$category" ]]; then
        log_error "Library $library not found in any category"
        return 1
    fi
    
    local chapter_name chapter_desc
    chapter_name=$(jq -r --arg cat "$category" '.categories[$cat].chapter_name' "$LIBRARY_MAP")
    chapter_desc=$(jq -r --arg cat "$category" '.categories[$cat].description' "$LIBRARY_MAP")
    
    get_or_create_chapter "$chapter_name" "$chapter_desc"
}

# Process all libraries
process_all_libraries() {
    log "Starting equipment page creation"
    log "Book ID: $BOOK_ID"
    log "Dry run: $DRY_RUN"
    
    # Initialize chapter cache
    init_chapter_cache
    
    # Get list of libraries
    local libraries
    if [[ -n "$SINGLE_LIBRARY" ]]; then
        libraries="$SINGLE_LIBRARY"
    else
        libraries=$(jq -r '.library_metadata | keys[]' "$LIBRARY_MAP")
    fi
    
    local total=0
    local created=0
    local skipped=0
    local errors=0
    local library
    
    while IFS= read -r library; do
        [[ -z "$library" ]] && continue
        ((total++)) || true
        log ""
        log "Processing: $library"
        
        # Get chapter for this library
        local chapter_id
        chapter_id=$(get_chapter_for_library "$library") || {
            log_error "Could not determine chapter for $library"
            ((errors++)) || true
            continue
        }
        
        log_verbose "Using chapter ID: $chapter_id"
        
        # Create the page
        if create_equipment_page "$library" "$chapter_id"; then
            ((created++)) || true
        else
            ((errors++)) || true
        fi
        
        # Rate limiting
        if [[ "$DRY_RUN" != "true" ]]; then
            sleep 0.5
        fi
    done <<< "$libraries"
    
    log ""
    log "=========================================="
    log "Summary"
    log "=========================================="
    log "Total libraries: $total"
    log "Pages created: $created"
    log "Errors: $errors"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log ""
        log "This was a DRY RUN — no changes were made."
    fi
}

# ============================================================================
# Entry Point
# ============================================================================

# Verify prerequisites
if [[ ! -f "$LIBRARY_MAP" ]]; then
    log_error "Library map not found: $LIBRARY_MAP"
    exit 1
fi

if [[ ! -d "$EIC_EQUIP_DIR" ]]; then
    log_error "eic-equip directory not found: $EIC_EQUIP_DIR"
    exit 1
fi

# Check API connectivity
log "Checking API connectivity..."
if ! check_api > /dev/null; then
    log_error "Cannot connect to Bookstack API"
    exit 1
fi
log "API OK"

# Run
process_all_libraries
