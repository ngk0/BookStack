#!/bin/bash
# delete-orphans.sh - Delete orphaned BookStack items from orphans.json
#
# Usage: ./delete-orphans.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ORPHANS_FILE="${PROJECT_DIR}/data/hierarchy/orphans.json"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE ==="
fi

# Load API helpers
source "${SCRIPT_DIR}/api-helpers.sh"

if [[ ! -f "$ORPHANS_FILE" ]]; then
    echo "ERROR: Orphans file not found: $ORPHANS_FILE"
    echo "Run apply-structure.sh first to generate orphans report"
    exit 1
fi

echo ""
echo "Reading orphans from: $ORPHANS_FILE"
echo ""

# Extract IDs
CHAPTER_IDS=$(jq -r '.orphaned_chapters[].id' "$ORPHANS_FILE")
BOOK_IDS=$(jq -r '.orphaned_books[].id' "$ORPHANS_FILE")
SHELF_IDS=$(jq -r '.orphaned_shelves[].id' "$ORPHANS_FILE")

CHAPTER_COUNT=$(echo "$CHAPTER_IDS" | grep -c . || true)
BOOK_COUNT=$(echo "$BOOK_IDS" | grep -c . || true)
SHELF_COUNT=$(echo "$SHELF_IDS" | grep -c . || true)

echo "Found orphans:"
echo "  Chapters: $CHAPTER_COUNT"
echo "  Books: $BOOK_COUNT"
echo "  Shelves: $SHELF_COUNT"
echo ""

DELETED_CHAPTERS=0
DELETED_BOOKS=0
DELETED_SHELVES=0

# Delete chapters first
echo "=== Deleting Chapters ==="
for id in $CHAPTER_IDS; do
    name=$(jq -r --argjson id "$id" '.orphaned_chapters[] | select(.id == $id) | .name' "$ORPHANS_FILE")
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would delete chapter: $name (ID: $id)"
    else
        echo "  Deleting chapter: $name (ID: $id)..."
        if delete_chapter "$id" 2>/dev/null; then
            DELETED_CHAPTERS=$((DELETED_CHAPTERS + 1))
            echo "    ✓ Deleted"
        else
            echo "    ✗ Failed (may already be deleted)"
        fi
        sleep 0.1  # Rate limit
    fi
done

echo ""
echo "=== Deleting Books ==="
for id in $BOOK_IDS; do
    name=$(jq -r --argjson id "$id" '.orphaned_books[] | select(.id == $id) | .name' "$ORPHANS_FILE")
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would delete book: $name (ID: $id)"
    else
        echo "  Deleting book: $name (ID: $id)..."
        if delete_book "$id" 2>/dev/null; then
            DELETED_BOOKS=$((DELETED_BOOKS + 1))
            echo "    ✓ Deleted"
        else
            echo "    ✗ Failed (may already be deleted)"
        fi
        sleep 0.1  # Rate limit
    fi
done

echo ""
echo "=== Deleting Shelves ==="
for id in $SHELF_IDS; do
    name=$(jq -r --argjson id "$id" '.orphaned_shelves[] | select(.id == $id) | .name' "$ORPHANS_FILE")
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would delete shelf: $name (ID: $id)"
    else
        echo "  Deleting shelf: $name (ID: $id)..."
        if delete_shelf "$id" 2>/dev/null; then
            DELETED_SHELVES=$((DELETED_SHELVES + 1))
            echo "    ✓ Deleted"
        else
            echo "    ✗ Failed (may already be deleted)"
        fi
        sleep 0.1  # Rate limit
    fi
done

echo ""
echo "============================================================"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN COMPLETE"
    echo "Would delete: $CHAPTER_COUNT chapters, $BOOK_COUNT books, $SHELF_COUNT shelves"
else
    echo "DELETION COMPLETE"
    echo "Deleted: $DELETED_CHAPTERS chapters, $DELETED_BOOKS books, $DELETED_SHELVES shelves"

    # Clear the orphans file
    echo ""
    echo "Clearing orphans file..."
    echo '{"generated_at": "'$(date -Iseconds)'", "note": "Orphans deleted", "orphaned_shelves": [], "orphaned_books": [], "orphaned_chapters": []}' > "$ORPHANS_FILE"
    echo "Done."
fi
echo "============================================================"
