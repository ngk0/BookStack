#!/bin/bash
# sync-hierarchy.sh - Sync BookStack content hierarchy to JSON and Markdown
#
# Usage: ./sync-hierarchy.sh [--verbose] [--dry-run]
#
# Outputs:
#   data/hierarchy/hierarchy.json  - Complete structured hierarchy for LLM use
#   data/hierarchy/hierarchy.md    - Human-readable markdown tree
#
# This script fetches the complete content hierarchy from BookStack via REST API
# and outputs it in formats suitable for programmatic use and human reading.

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/data/hierarchy"
LOG_FILE="${OUTPUT_DIR}/sync.log"
LOCK_FILE="${OUTPUT_DIR}/sync.lock"

# Rate limiting (ms between API calls)
RATE_LIMIT_MS=100

# CLI flags
VERBOSE=false
DRY_RUN=false

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
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--verbose] [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Logging
# =============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$msg" >&2
    fi
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "$@"
    fi
}

# =============================================================================
# Initialize
# =============================================================================

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Prevent overlapping runs (systemd timer can fire while a previous sync is still running).
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        # Avoid failing the unit; just log and exit.
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another sync is already running; exiting." >> "$LOG_FILE"
        exit 0
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: flock not found; cannot enforce single-instance sync." >> "$LOG_FILE"
fi

# Rotate log file if > 1MB
if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
fi

log "=== Starting hierarchy sync ==="

START_TIME=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))

# Source API helpers (this validates credentials)
# Temporarily disable strict mode for sourcing
set +u
source "${SCRIPT_DIR}/api-helpers.sh" 2>/dev/null
set -u

# =============================================================================
# API Functions with Pagination
# =============================================================================

# Rate limit helper
rate_limit() {
    if [[ "${RATE_LIMIT_MS}" -le 0 ]]; then
        return 0
    fi
    # sleep accepts fractional seconds; keep it portable with awk.
    sleep "$(awk -v ms="$RATE_LIMIT_MS" 'BEGIN { printf "%.3f", ms/1000 }')"
}

# Fetch all items from a paginated endpoint
# Usage: fetch_paginated "/endpoint"
# Returns: JSON array of all items
fetch_paginated() {
    local endpoint="$1"
    local all_items="[]"
    local offset=0
    local count=500
    local total=999999

    while [[ $offset -lt $total ]]; do
        local response
        response=$(api_get "${endpoint}?count=${count}&offset=${offset}")

        # Get total from first response
        if [[ $offset -eq 0 ]]; then
            total=$(echo "$response" | jq -r '.total // 0')
            log_verbose "  Fetching ${total} items from ${endpoint}"
        fi

        # Extract items
        local items
        items=$(echo "$response" | jq '.data // []')
        all_items=$(echo "$all_items" "$items" | jq -s 'add')

        offset=$((offset + count))
        rate_limit
    done

    echo "$all_items"
}

# Fetch single item details
# Usage: fetch_item "/endpoint/id"
fetch_item() {
    local endpoint="$1"
    api_get "$endpoint"
    rate_limit
}

# =============================================================================
# Data Fetching
# =============================================================================

log "Fetching shelves..."
SHELVES_LIST=$(fetch_paginated "/shelves")
SHELF_COUNT=$(echo "$SHELVES_LIST" | jq 'length')
log "  Found ${SHELF_COUNT} shelves"

log "Fetching books..."
BOOKS_LIST=$(fetch_paginated "/books")
BOOK_COUNT=$(echo "$BOOKS_LIST" | jq 'length')
log "  Found ${BOOK_COUNT} books"

# Map book ID -> slug for URL construction.
# Page/chapter detail endpoints don't always include book_slug.
BOOK_ID_TO_SLUG=$(echo "$BOOKS_LIST" | jq 'map({key:(.id|tostring), value:.slug}) | from_entries')

log "Fetching chapters..."
CHAPTERS_LIST=$(fetch_paginated "/chapters")
CHAPTER_COUNT=$(echo "$CHAPTERS_LIST" | jq 'length')
log "  Found ${CHAPTER_COUNT} chapters"

log "Fetching pages..."
PAGES_LIST=$(fetch_paginated "/pages")
PAGE_COUNT=$(echo "$PAGES_LIST" | jq 'length')
log "  Found ${PAGE_COUNT} pages"

# =============================================================================
# Fetch Detailed Info
# =============================================================================

log "Fetching shelf details..."
SHELVES_DETAILED_FILE="$(mktemp)"
trap 'rm -f "$SHELVES_DETAILED_FILE"' EXIT
for shelf_id in $(echo "$SHELVES_LIST" | jq -r '.[].id'); do
    log_verbose "  Fetching shelf ${shelf_id}"
    fetch_item "/shelves/${shelf_id}" | jq -c '.' >> "$SHELVES_DETAILED_FILE"
done
SHELVES_DETAILED=$(jq -s '.' "$SHELVES_DETAILED_FILE")
rm -f "$SHELVES_DETAILED_FILE"

# Books & chapters list endpoints already include the fields we need (slug/description/priority/cover/etc).
# Avoid N extra API calls to speed up sync and reduce flakiness.
BOOKS_DETAILED="$BOOKS_LIST"
CHAPTERS_DETAILED="$CHAPTERS_LIST"

# Pages: fetch details to get tags and content length
log "Fetching page details..."
PAGES_DETAILED_FILE="$(mktemp)"
trap 'rm -f "$PAGES_DETAILED_FILE"' EXIT
for page_id in $(echo "$PAGES_LIST" | jq -r '.[].id'); do
    log_verbose "  Fetching page ${page_id}"
    # Reduce payload size: compute content length and discard heavy fields.
    fetch_item "/pages/${page_id}" | jq -c '
        ((.html // .raw_html // .markdown // "") | length) as $len
        | del(.html, .raw_html, .markdown, .comments)
        | . + {content_length: $len}
    ' >> "$PAGES_DETAILED_FILE"
done
PAGES_DETAILED=$(jq -s '.' "$PAGES_DETAILED_FILE")
rm -f "$PAGES_DETAILED_FILE"

# =============================================================================
# Build Hierarchy
# =============================================================================

log "Building hierarchy..."

# Helper: Get status tag from tags array
get_status_tag() {
    local tags="$1"
    echo "$tags" | jq -r '[.[] | select(.name | startswith("status:"))] | .[0].name // ""' | sed 's/status://'
}

# Build pages for a chapter
build_chapter_pages() {
    local chapter_id="$1"
    echo "$PAGES_DETAILED" | jq \
        --argjson cid "$chapter_id" \
        --arg bookstack_url "${BOOKSTACK_URL}" \
        --argjson book_id_to_slug "$BOOK_ID_TO_SLUG" '
        [.[] | select((.chapter_id // 0) == $cid) | {
            id: .id,
            slug: .slug,
            name: .name,
            url: ($bookstack_url + "/books/" + ($book_id_to_slug[(.book_id | tostring)] // "unknown") + "/page/" + .slug),
            priority: .priority,
            draft: .draft,
            template: .template,
            revision_count: .revision_count,
            editor: .editor,
            tags: .tags,
            content_length: (.content_length // 0),
            created_at: .created_at,
            updated_at: .updated_at,
            _llm_hints: {
                needs_content: ((.content_length // 0) < 100),
                content_type: (
                    if (.name | test("(?i)procedure|sop|how to")) then "procedural"
                    elif (.name | test("(?i)standard|spec|requirement")) then "standard"
                    elif (.name | test("(?i)training|course|learn")) then "training"
                    elif (.name | test("(?i)template|form")) then "template"
                    else "reference"
                    end
                )
            }
        }] | sort_by(.priority // 999)
    '
}

# Build direct pages for a book (not in any chapter)
build_book_direct_pages() {
    local book_id="$1"
    echo "$PAGES_DETAILED" | jq \
        --argjson bid "$book_id" \
        --arg bookstack_url "${BOOKSTACK_URL}" \
        --argjson book_id_to_slug "$BOOK_ID_TO_SLUG" '
        [.[] | select(.book_id == $bid and ((.chapter_id // 0) == 0)) | {
            id: .id,
            slug: .slug,
            name: .name,
            url: ($bookstack_url + "/books/" + ($book_id_to_slug[(.book_id | tostring)] // "unknown") + "/page/" + .slug),
            priority: .priority,
            draft: .draft,
            template: .template,
            revision_count: .revision_count,
            editor: .editor,
            tags: .tags,
            content_length: (.content_length // 0),
            created_at: .created_at,
            updated_at: .updated_at,
            _llm_hints: {
                needs_content: ((.content_length // 0) < 100),
                content_type: "reference"
            }
        }] | sort_by(.priority // 999)
    '
}

# Build chapters for a book
build_book_chapters() {
    local book_id="$1"
    local chapters
    chapters=$(echo "$CHAPTERS_DETAILED" | jq --argjson bid "$book_id" '[.[] | select(.book_id == $bid)]')

    local result="[]"
    for chapter_id in $(echo "$chapters" | jq -r '.[].id'); do
        local chapter
        chapter=$(echo "$chapters" | jq --argjson cid "$chapter_id" '.[] | select(.id == $cid)')

        local chapter_pages
        chapter_pages=$(build_chapter_pages "$chapter_id")

        local chapter_with_pages
        chapter_with_pages=$(
            printf '%s\n%s\n' "$chapter" "$chapter_pages" |
            jq -s --arg bookstack_url "${BOOKSTACK_URL}" --argjson book_id_to_slug "$BOOK_ID_TO_SLUG" '
                .[0] as $chapter | .[1] as $pages |
                {
                    id: $chapter.id,
                    slug: $chapter.slug,
                    name: $chapter.name,
                    description: $chapter.description,
                    url: ($bookstack_url + "/books/" + ($book_id_to_slug[($chapter.book_id | tostring)] // "unknown") + "/chapter/" + $chapter.slug),
                    priority: $chapter.priority,
                    created_at: $chapter.created_at,
                    updated_at: $chapter.updated_at,
                    pages: $pages
                }'
        )

        result=$(
            printf '%s\n%s\n' "$result" "$chapter_with_pages" |
            jq -s '.[0] + [.[1]]'
        )
    done

    echo "$result" | jq 'sort_by(.priority // 999)'
}

# Build books for a shelf
build_shelf_books() {
    local shelf_id="$1"

    # Get book IDs from shelf details
    local book_ids
    book_ids=$(echo "$SHELVES_DETAILED" | jq --argjson sid "$shelf_id" '[.[] | select(.id == $sid) | .books[].id] | unique')

    local result="[]"
    for book_id in $(echo "$book_ids" | jq -r '.[]'); do
        local book
        book=$(echo "$BOOKS_DETAILED" | jq --argjson bid "$book_id" '.[] | select(.id == $bid)')

        if [[ -z "$book" || "$book" == "null" ]]; then
            continue
        fi

        local book_chapters
        book_chapters=$(build_book_chapters "$book_id")

        local direct_pages
        direct_pages=$(build_book_direct_pages "$book_id")

        local book_with_contents
        book_with_contents=$(
            printf '%s\n%s\n%s\n' "$book" "$book_chapters" "$direct_pages" |
            jq -s --arg bookstack_url "${BOOKSTACK_URL}" '
                .[0] as $book | .[1] as $chapters | .[2] as $dpages |
                {
                    id: $book.id,
                    slug: $book.slug,
                    name: $book.name,
                    description: $book.description,
                    url: ($bookstack_url + "/books/" + $book.slug),
                    cover_url: ($book.cover.url // null),
                    default_template_id: ($book.default_template_id // null),
                    created_at: $book.created_at,
                    updated_at: $book.updated_at,
                    chapters: $chapters,
                    direct_pages: $dpages
                }'
        )

        result=$(
            printf '%s\n%s\n' "$result" "$book_with_contents" |
            jq -s '.[0] + [.[1]]'
        )
    done

    echo "$result"
}

# Build complete shelves hierarchy
build_shelves_hierarchy() {
    local result="[]"

    for shelf_id in $(echo "$SHELVES_DETAILED" | jq -r '.[].id'); do
        local shelf
        shelf=$(echo "$SHELVES_DETAILED" | jq --argjson sid "$shelf_id" '.[] | select(.id == $sid)')

        local shelf_books
        shelf_books=$(build_shelf_books "$shelf_id")

        local shelf_with_books
        shelf_with_books=$(
            printf '%s\n%s\n' "$shelf" "$shelf_books" |
            jq -s --arg bookstack_url "${BOOKSTACK_URL}" '
                .[0] as $shelf | .[1] as $books |
                {
                    id: $shelf.id,
                    slug: $shelf.slug,
                    name: $shelf.name,
                    description: $shelf.description,
                    url: ($bookstack_url + "/shelves/" + $shelf.slug),
                    created_at: $shelf.created_at,
                    updated_at: $shelf.updated_at,
                    books: $books
                }'
        )

        result=$(
            printf '%s\n%s\n' "$result" "$shelf_with_books" |
            jq -s '.[0] + [.[1]]'
        )
    done

    echo "$result"
}

# Find orphan books (not assigned to any shelf)
find_orphan_books() {
    # Get all book IDs assigned to shelves
    local assigned_ids
    assigned_ids=$(echo "$SHELVES_DETAILED" | jq '[.[].books[].id] | unique')

    # Find books not in that list
    echo "$BOOKS_DETAILED" | jq --argjson assigned "$assigned_ids" '
        [.[] | select([.id] | inside($assigned) | not) | {
            id: .id,
            slug: .slug,
            name: .name,
            description: .description,
            url: ("'"${BOOKSTACK_URL}"'" + "/books/" + .slug),
            created_at: .created_at,
            updated_at: .updated_at
        }]
    '
}

# Build the complete hierarchy (write to temp files to avoid huge JSON on command line)
SHELVES_HIERARCHY_FILE="$(mktemp)"
ORPHAN_BOOKS_FILE="$(mktemp)"
trap 'rm -f "$SHELVES_HIERARCHY_FILE" "$ORPHAN_BOOKS_FILE"' EXIT

build_shelves_hierarchy > "$SHELVES_HIERARCHY_FILE"
find_orphan_books > "$ORPHAN_BOOKS_FILE"

# Calculate end time and duration
END_TIME=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
DURATION_MS=$((END_TIME - START_TIME))

# =============================================================================
# Generate JSON Output
# =============================================================================

log "Generating JSON output..."

GENERATED_AT=$(date -Iseconds)

JSON_OUTPUT=$(jq -n \
    --arg schema "hierarchy-v1" \
    --arg version "1.0" \
    --arg generated_at "$GENERATED_AT" \
    --arg bookstack_url "$BOOKSTACK_URL" \
    --argjson duration "$DURATION_MS" \
    --argjson shelf_count "$SHELF_COUNT" \
    --argjson book_count "$BOOK_COUNT" \
    --argjson chapter_count "$CHAPTER_COUNT" \
    --argjson page_count "$PAGE_COUNT" \
    --slurpfile shelves "$SHELVES_HIERARCHY_FILE" \
    --slurpfile orphan_books "$ORPHAN_BOOKS_FILE" \
    '{
        "$schema": $schema,
        meta: {
            version: $version,
            generated_at: $generated_at,
            bookstack_url: $bookstack_url,
            sync_duration_ms: $duration,
            stats: {
                shelves: $shelf_count,
                books: $book_count,
                chapters: $chapter_count,
                pages: $page_count
            }
        },
        hierarchy: {
            shelves: ($shelves[0] // []),
            orphan_books: ($orphan_books[0] // [])
        },
        _llm_context: {
            organization: "EIC - Engineering Integration Company",
            purpose: "Engineering standards, SOPs, and training documentation",
            primary_audience: ["engineers", "technicians", "new hires", "project managers"],
            content_guidelines: "Technical, professional, concise. Use clear language accessible to varying experience levels.",
            tag_workflow: {
                "status:draft": "Work in progress - internal review only",
                "status:review": "Ready for technical/management review",
                "status:approved": "Official approved content - can be referenced externally",
                "status:archived": "Historical reference only - superseded by newer content"
            }
        }
    }'
)

if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run - would write to ${OUTPUT_DIR}/hierarchy.json"
    echo "$JSON_OUTPUT" | head -50
else
    echo "$JSON_OUTPUT" > "${OUTPUT_DIR}/hierarchy.json"
    log "Wrote ${OUTPUT_DIR}/hierarchy.json"
fi

# =============================================================================
# Generate Markdown Output
# =============================================================================

log "Generating Markdown output..."

generate_markdown() {
    local json="$1"

    cat <<EOF
# BookStack Hierarchy
*Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')*
*Source: ${BOOKSTACK_URL}*

## Statistics
| Metric | Count |
|--------|-------|
| Shelves | ${SHELF_COUNT} |
| Books | ${BOOK_COUNT} |
| Chapters | ${CHAPTER_COUNT} |
| Pages | ${PAGE_COUNT} |

*Sync completed in ${DURATION_MS}ms*

---

## Content Tree

EOF

    # Generate tree for each shelf
    echo "$json" | jq -r '.hierarchy.shelves[] | "### [\(.name)](\(.url))\n> \(.description // "No description")\n"'

    for shelf_id in $(echo "$json" | jq -r '.hierarchy.shelves[].id'); do
        local shelf
        shelf=$(echo "$json" | jq --argjson sid "$shelf_id" '.hierarchy.shelves[] | select(.id == $sid)')

        # Books in shelf
        for book_id in $(echo "$shelf" | jq -r '.books[].id'); do
            local book
            book=$(echo "$shelf" | jq --argjson bid "$book_id" '.books[] | select(.id == $bid)')

            local book_name book_url book_desc
            book_name=$(echo "$book" | jq -r '.name')
            book_url=$(echo "$book" | jq -r '.url')
            book_desc=$(echo "$book" | jq -r '.description // "No description"')

            echo "#### [${book_name}](${book_url})"
            echo "> ${book_desc}"
            echo ""

            # Chapters in book
            for chapter_id in $(echo "$book" | jq -r '.chapters[].id'); do
                local chapter
                chapter=$(echo "$book" | jq --argjson cid "$chapter_id" '.chapters[] | select(.id == $cid)')

                local chapter_name
                chapter_name=$(echo "$chapter" | jq -r '.name')

                echo "- **${chapter_name}** (chapter)"

                # Pages in chapter
                for page_id in $(echo "$chapter" | jq -r '.pages[].id'); do
                    local page
                    page=$(echo "$chapter" | jq --argjson pid "$page_id" '.pages[] | select(.id == $pid)')

                    local page_name page_url page_draft needs_content
                    page_name=$(echo "$page" | jq -r '.name')
                    page_url=$(echo "$page" | jq -r '.url')
                    page_draft=$(echo "$page" | jq -r '.draft')
                    needs_content=$(echo "$page" | jq -r '._llm_hints.needs_content')

                    local status_badge=""
                    if [[ "$page_draft" == "true" ]]; then
                        status_badge=" [draft]"
                    elif [[ "$needs_content" == "true" ]]; then
                        status_badge=" [empty]"
                    fi

                    echo "  - [${page_name}](${page_url})${status_badge}"
                done
            done

            # Direct pages in book
            local direct_page_count
            direct_page_count=$(echo "$book" | jq '.direct_pages | length')
            if [[ "$direct_page_count" -gt 0 ]]; then
                echo "- **Direct Pages**"
                for page_id in $(echo "$book" | jq -r '.direct_pages[].id'); do
                    local page
                    page=$(echo "$book" | jq --argjson pid "$page_id" '.direct_pages[] | select(.id == $pid)')

                    local page_name page_url
                    page_name=$(echo "$page" | jq -r '.name')
                    page_url=$(echo "$page" | jq -r '.url')

                    echo "  - [${page_name}](${page_url})"
                done
            fi

            echo ""
        done
    done

    # Orphan books section
    local orphan_count
    orphan_count=$(echo "$json" | jq '.hierarchy.orphan_books | length')
    if [[ "$orphan_count" -gt 0 ]]; then
        echo "---"
        echo ""
        echo "## Orphan Books (Not Assigned to Shelves)"
        echo ""
        echo "$json" | jq -r '.hierarchy.orphan_books[] | "- [\(.name)](\(.url))"'
        echo ""
    fi

    # Empty pages summary
    echo "---"
    echo ""
    echo "## Pages Needing Content"
    echo ""
    echo "$json" | jq -r '
        [.hierarchy.shelves[].books[] | {book: .name, chapters: .chapters[]} |
         {book: .book, chapter: .chapters.name, pages: .chapters.pages[]} |
         select(.pages._llm_hints.needs_content == true) |
         "- [\(.pages.name)](\(.pages.url)) in \(.book) > \(.chapter)"
        ] | unique | .[]
    ' 2>/dev/null || echo "*No empty pages found*"
}

if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run - would write to ${OUTPUT_DIR}/hierarchy.md"
    generate_markdown "$JSON_OUTPUT" | head -50
else
    generate_markdown "$JSON_OUTPUT" > "${OUTPUT_DIR}/hierarchy.md"
    log "Wrote ${OUTPUT_DIR}/hierarchy.md"
fi

# =============================================================================
# Summary
# =============================================================================

log "=== Sync complete ==="
log "  Duration: ${DURATION_MS}ms"
log "  Shelves: ${SHELF_COUNT}"
log "  Books: ${BOOK_COUNT}"
log "  Chapters: ${CHAPTER_COUNT}"
log "  Pages: ${PAGE_COUNT}"

if [[ "$VERBOSE" == "true" ]]; then
    echo ""
    echo "Sync complete!"
    echo "  JSON: ${OUTPUT_DIR}/hierarchy.json"
    echo "  Markdown: ${OUTPUT_DIR}/hierarchy.md"
    echo "  Log: ${LOG_FILE}"
fi

# =============================================================================
# Structure Push (if structure.yaml changed)
# =============================================================================

if [[ "$DRY_RUN" != "true" ]]; then
    MTIME_FILE="${OUTPUT_DIR}/last-structure-mtime"
    STRUCTURE_FILE="${SCRIPT_DIR}/structure.yaml"

    if [[ -f "$STRUCTURE_FILE" ]]; then
        # Get current mtime (Linux stat -c, macOS stat -f)
        current_mtime=$(stat -c %Y "$STRUCTURE_FILE" 2>/dev/null || stat -f %m "$STRUCTURE_FILE" 2>/dev/null || echo "0")
        last_mtime=$(cat "$MTIME_FILE" 2>/dev/null || echo "0")

        if [[ "$current_mtime" != "$last_mtime" ]]; then
            log ""
            log "=== structure.yaml changed, applying updates ==="
            if [[ -x "${SCRIPT_DIR}/apply-structure.sh" ]]; then
                if [[ "$VERBOSE" == "true" ]]; then
                    "${SCRIPT_DIR}/apply-structure.sh" --verbose
                else
                    "${SCRIPT_DIR}/apply-structure.sh"
                fi
                echo "$current_mtime" > "$MTIME_FILE"
                log "Structure push complete, mtime updated"
            else
                log_error "apply-structure.sh not found or not executable"
            fi
        else
            log ""
            log "structure.yaml unchanged, skipping push"
        fi
    fi
fi
