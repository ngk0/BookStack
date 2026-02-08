#!/bin/bash
# BookStack Content Enrichment via OpenAI Codex
# Scans pages for <CODEX:...> directives and generates content
#
# Usage: ./enrich-pages.sh [--dry-run] [--page-id ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/api-helpers.sh" 2>/dev/null

# Configuration
DRY_RUN=false
SPECIFIC_PAGE=""
CODEX_MODEL="gpt-5.3-codex"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --page-id)
            SPECIFIC_PAGE="$2"
            shift 2
            ;;
        --model)
            CODEX_MODEL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "BookStack Content Enrichment"
log "Dry run: $DRY_RUN"
log "Model: $CODEX_MODEL"

# Extract CODEX directive from HTML content
extract_codex_directive() {
    local html="$1"
    echo "$html" | grep -oP '(?i)&lt;CODEX:\s*\K[^&]+(?=&gt;)' | head -1 || true
}

# Generate content using Codex
generate_content() {
    local instruction="$1"
    local page_name="$2"
    local output_file="/tmp/codex-output-$$.txt"

    local prompt="You are writing content for an engineering knowledge base used by electrical and controls engineers at an engineering firm (Laporte EIC).

Context: This content is for a page titled '${page_name}'.

Task: ${instruction}

Requirements:
- Write in a professional, technical style appropriate for engineers
- Use markdown formatting
- Be concise but comprehensive
- Include practical guidance where applicable
- Do not include any preamble or meta-commentary, just the content itself"

    log "Calling Codex to generate content..."

    # Run codex, redirect stderr to suppress console output, capture content to file
    if codex exec \
        --skip-git-repo-check \
        -m "$CODEX_MODEL" \
        -o "$output_file" \
        "$prompt" >/dev/null 2>&1; then
        
        if [[ -f "$output_file" && -s "$output_file" ]]; then
            cat "$output_file"
            rm -f "$output_file"
        else
            log_error "Codex output file empty or missing"
            return 1
        fi
    else
        log_error "Codex execution failed"
        rm -f "$output_file"
        return 1
    fi
}

# Update page with new content
update_page_content() {
    local page_id="$1"
    local new_content="$2"

    local data
    data=$(jq -n --arg md "$new_content" '{markdown: $md}')

    api_put "/pages/${page_id}" "$data"
}

# Process a single page
process_page() {
    local page_id="$1"

    log "Fetching page $page_id..."
    local page_data
    page_data=$(api_get "/pages/${page_id}")

    local page_name
    page_name=$(echo "$page_data" | jq -r '.name')

    local page_html
    page_html=$(echo "$page_data" | jq -r '.html')

    local directive
    directive=$(extract_codex_directive "$page_html")

    if [[ -z "$directive" ]]; then
        log "No CODEX directive found in page: $page_name"
        return 0
    fi

    log "Found directive in '$page_name': $directive"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would generate content for: $directive"
        return 0
    fi

    local generated_content
    generated_content=$(generate_content "$directive" "$page_name")

    if [[ -z "$generated_content" ]]; then
        log_error "No content generated for page $page_id"
        return 1
    fi

    log "Generated ${#generated_content} characters of content"

    log "Updating page $page_id..."
    local result
    result=$(update_page_content "$page_id" "$generated_content")

    if echo "$result" | jq -e '.id' > /dev/null 2>&1; then
        log "Successfully updated page: $page_name"
    else
        log_error "Failed to update page: $result"
        return 1
    fi
}

# Main
if [[ -n "$SPECIFIC_PAGE" ]]; then
    process_page "$SPECIFIC_PAGE"
else
    log "Scanning all pages for CODEX directives..."

    offset=0
    count=50
    total=0
    found=0

    while true; do
        response=$(api_get "/pages?count=${count}&offset=${offset}")

        page_ids=$(echo "$response" | jq -r '.data[].id')

        if [[ -z "$page_ids" ]]; then
            break
        fi

        for page_id in $page_ids; do
            ((total++)) || true

            page_html=$(api_get "/pages/${page_id}" | jq -r '.html')

            if echo "$page_html" | grep -qi "CODEX:"; then
                ((found++)) || true
                log "Found CODEX directive in page $page_id"
                process_page "$page_id"
            fi
        done

        offset=$((offset + count))

        total_in_response=$(echo "$response" | jq -r '.total')
        if [[ $offset -ge $total_in_response ]]; then
            break
        fi
    done

    log "Scan complete. Checked $total pages, found $found with CODEX directives."
fi

log "Enrichment complete."
