#!/bin/bash
# Create Equipment Class Pages - Simple flat structure
# One page per library, all in one book, no chapters

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/api-helpers.sh"

EIC_EQUIP_DIR="/srv/stacks/work/eic-equip/repo"
LIBRARY_MAP="${SCRIPT_DIR}/equipment-library-map.json"
BOOK_ID="$1"

DEFAULT_TAGS='[{"name": "status:draft"}, {"name": "source:eic-equip"}]'

# Get library README content
get_readme() {
    local library="$1"
    local readme_path="${EIC_EQUIP_DIR}/${library}/README.md"
    if [[ -f "$readme_path" ]]; then
        cat "$readme_path"
    else
        echo ""
    fi
}

# Generate full page content
generate_content() {
    local library="$1"
    
    local display_name manufacturer
    display_name=$(jq -r --arg lib "$library" '.library_metadata[$lib].display_name // $lib' "$LIBRARY_MAP")
    manufacturer=$(jq -r --arg lib "$library" '.library_metadata[$lib].manufacturer // "Various"' "$LIBRARY_MAP")
    
    local readme
    readme=$(get_readme "$library")
    
    cat << CONTENT_EOF
# ${display_name}

> **Manufacturer:** ${manufacturer}  
> **Library:** \`${library}\`  
> **Source:** eic-equip repository

---

${readme}

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

*Auto-generated from eic-equip repository. Update [PENDING] paths when Egnyte folders are established.*
CONTENT_EOF
}

# Create page
create_page() {
    local library="$1"
    
    local display_name
    display_name=$(jq -r --arg lib "$library" '.library_metadata[$lib].display_name // $lib' "$LIBRARY_MAP")
    
    log "Creating: $display_name"
    
    local content
    content=$(generate_content "$library")
    
    local data
    data=$(jq -n \
        --arg name "$display_name" \
        --arg content "$content" \
        --argjson book "$BOOK_ID" \
        --argjson tags "$DEFAULT_TAGS" \
        '{name: $name, markdown: $content, book_id: $book, tags: $tags}')
    
    local result
    result=$(api_post "/pages" "$data")
    local page_id=$(echo "$result" | jq -r '.id // empty')
    
    if [[ -n "$page_id" ]]; then
        echo "  Created page ID: $page_id"
    else
        log_error "Failed: $display_name"
    fi
    
    sleep 0.3
}

# Main
log "Creating 22 equipment pages in book $BOOK_ID"

libraries=$(jq -r '.library_metadata | keys[]' "$LIBRARY_MAP")
count=0

while IFS= read -r library; do
    [[ -z "$library" ]] && continue
    create_page "$library"
    ((count++)) || true
done <<< "$libraries"

log "Done. Created $count pages."
