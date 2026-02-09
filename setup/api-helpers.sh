#!/bin/bash
# BookStack API Helper Functions
# Source this file in other scripts: source ./api-helpers.sh

set -euo pipefail

# Load credentials
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.env.setup" ]]; then
    source "${SCRIPT_DIR}/.env.setup"
else
    echo "ERROR: .env.setup not found in ${SCRIPT_DIR}" >&2
    exit 1
fi

# Validate required variables
: "${BOOKSTACK_URL:?BOOKSTACK_URL not set}"
: "${BOOKSTACK_TOKEN_ID:?BOOKSTACK_TOKEN_ID not set}"
: "${BOOKSTACK_TOKEN_SECRET:?BOOKSTACK_TOKEN_SECRET not set}"

# API base URL
# Use an internal API URL (localhost) when provided to avoid Cloudflare/edge flakiness.
API_HOST="${BOOKSTACK_API_URL:-$BOOKSTACK_URL}"
API_HOST="${API_HOST%/}"
API_BASE="${API_HOST}/api"

# =============================================================================
# Core API Functions
# =============================================================================

# Make authenticated API request
# Usage: api_request METHOD ENDPOINT [DATA]
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    # Avoid putting API secrets in the curl command line (visible via ps/systemd status).
    # Use a temp header file and ensure it is removed even if curl fails.
    (
        set -euo pipefail
        local header_file
        header_file=$(mktemp)
        trap 'rm -f "$header_file"' EXIT

        cat > "$header_file" <<EOF
Authorization: Token ${BOOKSTACK_TOKEN_ID}:${BOOKSTACK_TOKEN_SECRET}
Content-Type: application/json
Accept: application/json
EOF

        local attempts=${BOOKSTACK_API_ATTEMPTS:-3}
        local attempt=1
        local response=""

        while [[ $attempt -le $attempts ]]; do
            local curl_args=(
                -sS
                --connect-timeout "${BOOKSTACK_API_CONNECT_TIMEOUT:-5}"
                --max-time "${BOOKSTACK_API_MAX_TIME:-60}"
                -X "$method"
                -H "@$header_file"
            )

            if [[ -n "$data" ]]; then
                curl_args+=(-d "$data")
            fi

            # If BookStack (or an edge proxy) returns an HTML error page, jq will fail later.
            # Detect non-JSON early and retry a few times.
            response="$(curl "${curl_args[@]}" "${API_BASE}${endpoint}" || true)"

            # Trim leading whitespace and check the first character.
            local trimmed="${response#"${response%%[![:space:]]*}"}"

            local first="${trimmed:0:1}"

            if [[ "$first" == "{" || "$first" == "[" ]]; then
                printf '%s' "$response"
                exit 0
            fi

            if [[ $attempt -lt $attempts ]]; then
                sleep $((attempt * 2))
                attempt=$((attempt + 1))
                continue
            fi

            echo "ERROR: Non-JSON response from BookStack API (${method} ${endpoint})" >&2
            echo "ERROR: API base: ${API_BASE}" >&2
            if [[ -n "$response" ]]; then
                echo "ERROR: Response (first 200 bytes):" >&2
                echo "$response" | head -c 200 >&2
                echo "" >&2
            fi
            exit 4
        done
    )
}
# GET request
api_get() {
    api_request GET "$1"
}

# POST request
api_post() {
    api_request POST "$1" "$2"
}

# PUT request
api_put() {
    api_request PUT "$1" "$2"
}

# DELETE request
api_delete() {
    api_request DELETE "$1"
}

# =============================================================================
# Update Functions
# =============================================================================

# Update a shelf
# Usage: update_shelf ID "Name" "Description"
update_shelf() {
    local id="$1"
    local name="$2"
    local description="${3:-}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        '{name: $name, description: $desc}')

    api_put "/shelves/${id}" "$data"
}

# Update a book
# Usage: update_book ID "Name" "Description"
update_book() {
    local id="$1"
    local name="$2"
    local description="${3:-}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        '{name: $name, description: $desc}')

    api_put "/books/${id}" "$data"
}

# Update a chapter
# Usage: update_chapter ID "Name" "Description"
update_chapter() {
    local id="$1"
    local name="$2"
    local description="${3:-}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        '{name: $name, description: $desc}')

    api_put "/chapters/${id}" "$data"
}

# =============================================================================
# Shelf Functions
# =============================================================================

# Create a shelf
# Usage: create_shelf "Name" "Description"
create_shelf() {
    local name="$1"
    local description="${2:-}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        '{name: $name, description: $desc}')

    api_post "/shelves" "$data"
}

# Get shelf by name (returns ID or empty)
get_shelf_id_by_name() {
    local name="$1"
    api_get "/shelves" | jq -r --arg name "$name" '.data[] | select(.name == $name) | .id // empty'
}

# List all shelves
list_shelves() {
    api_get "/shelves" | jq -r '.data[] | "\(.id)\t\(.name)"'
}

# =============================================================================
# Book Functions
# =============================================================================

# Create a book
# Usage: create_book "Name" "Description" [shelf_id]
create_book() {
    local name="$1"
    local description="${2:-}"
    local shelf_id="${3:-}"

    local data
    if [[ -n "$shelf_id" ]]; then
        data=$(jq -n \
            --arg name "$name" \
            --arg desc "$description" \
            --argjson shelf "$shelf_id" \
            '{name: $name, description: $desc}')
    else
        data=$(jq -n \
            --arg name "$name" \
            --arg desc "$description" \
            '{name: $name, description: $desc}')
    fi

    api_post "/books" "$data"
}

# Get book by name
get_book_id_by_name() {
    local name="$1"
    api_get "/books" | jq -r --arg name "$name" '.data[] | select(.name == $name) | .id // empty'
}

# Add book to shelf
add_book_to_shelf() {
    local book_id="$1"
    local shelf_id="$2"

    # Get current shelf books
    local current_books
    current_books=$(api_get "/shelves/${shelf_id}" | jq -r '[.books[].id]')

    # Add new book if not already present
    local new_books
    new_books=$(echo "$current_books" | jq --argjson id "$book_id" '. + [$id] | unique')

    api_put "/shelves/${shelf_id}" "{\"books\": $new_books}"
}

# List all books
list_books() {
    api_get "/books" | jq -r '.data[] | "\(.id)\t\(.name)"'
}

# =============================================================================
# Chapter Functions
# =============================================================================

# Create a chapter in a book
# Usage: create_chapter "Name" "Description" book_id
create_chapter() {
    local name="$1"
    local description="${2:-}"
    local book_id="$3"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        --argjson book "$book_id" \
        '{name: $name, description: $desc, book_id: $book}')

    api_post "/chapters" "$data"
}

# Get chapter by name in book
get_chapter_id_by_name() {
    local name="$1"
    local book_id="$2"
    api_get "/chapters" | jq -r --arg name "$name" --argjson book "$book_id" \
        '.data[] | select(.name == $name and .book_id == $book) | .id // empty'
}

# =============================================================================
# Page Functions
# =============================================================================

# Create a page in a chapter
# Usage: create_page "Name" "Markdown Content" chapter_id [tags_json]
create_page() {
    local name="$1"
    local content="$2"
    local chapter_id="$3"
    local tags="${4:-[]}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg content "$content" \
        --argjson chapter "$chapter_id" \
        --argjson tags "$tags" \
        '{name: $name, markdown: $content, chapter_id: $chapter, tags: $tags}')

    api_post "/pages" "$data"
}

# Create a page in a book (not in a chapter)
# Usage: create_page_in_book "Name" "Markdown Content" book_id [tags_json]
create_page_in_book() {
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

# =============================================================================
# Role Functions
# =============================================================================

# Create a role
# Usage: create_role "Name" "Description" permissions_json
create_role() {
    local name="$1"
    local description="${2:-}"
    local permissions="${3:-[]}"

    local data
    data=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        --argjson perms "$permissions" \
        '{display_name: $name, description: $desc, permissions: $perms}')

    api_post "/roles" "$data"
}

# Get role by name
get_role_id_by_name() {
    local name="$1"
    api_get "/roles" | jq -r --arg name "$name" '.data[] | select(.display_name == $name) | .id // empty'
}

# List all roles
list_roles() {
    api_get "/roles" | jq -r '.data[] | "\(.id)\t\(.display_name)"'
}

# =============================================================================
# User Functions
# =============================================================================

# List all users
list_users() {
    api_get "/users" | jq -r '.data[] | "\(.id)\t\(.name)\t\(.email)"'
}

# Get user by email
get_user_id_by_email() {
    local email="$1"
    api_get "/users" | jq -r --arg email "$email" '.data[] | select(.email == $email) | .id // empty'
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if API is accessible
check_api() {
    local response
    response=$(api_get "/shelves" 2>&1) || {
        echo "ERROR: API request failed" >&2
        return 1
    }

    if echo "$response" | jq -e '.data' > /dev/null 2>&1; then
        echo "OK: API is accessible"
        return 0
    else
        echo "ERROR: Unexpected API response: $response" >&2
        return 1
    fi
}

# Pretty print JSON
pp_json() {
    jq '.'
}

# Extract ID from API response
extract_id() {
    jq -r '.id'
}

# Log message with timestamp (to stderr so it doesn't mix with function return values)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Log error
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if resource exists (returns 0 if exists, 1 if not)
resource_exists() {
    local type="$1"
    local name="$2"

    case "$type" in
        shelf)
            [[ -n "$(get_shelf_id_by_name "$name")" ]]
            ;;
        book)
            [[ -n "$(get_book_id_by_name "$name")" ]]
            ;;
        role)
            [[ -n "$(get_role_id_by_name "$name")" ]]
            ;;
        *)
            log_error "Unknown resource type: $type"
            return 1
            ;;
    esac
}

# Create resource if it doesn't exist
# Usage: ensure_shelf "Name" "Description"
ensure_shelf() {
    local name="$1"
    local description="${2:-}"

    local existing_id
    existing_id=$(get_shelf_id_by_name "$name")

    if [[ -n "$existing_id" ]]; then
        log "Shelf '$name' already exists (ID: $existing_id)"
        echo "$existing_id"
    else
        log "Creating shelf: $name"
        create_shelf "$name" "$description" | extract_id
    fi
}

# Ensure book exists
ensure_book() {
    local name="$1"
    local description="${2:-}"

    local existing_id
    existing_id=$(get_book_id_by_name "$name")

    if [[ -n "$existing_id" ]]; then
        log "Book '$name' already exists (ID: $existing_id)"
        echo "$existing_id"
    else
        log "Creating book: $name"
        create_book "$name" "$description" | extract_id
    fi
}

# Ensure role exists
ensure_role() {
    local name="$1"
    local description="${2:-}"
    local permissions="${3:-[]}"

    local existing_id
    existing_id=$(get_role_id_by_name "$name")

    if [[ -n "$existing_id" ]]; then
        log "Role '$name' already exists (ID: $existing_id)"
        echo "$existing_id"
    else
        log "Creating role: $name"
        create_role "$name" "$description" "$permissions" | extract_id
    fi
}

# =============================================================================
# Delete Functions
# =============================================================================

# Delete a page
# Usage: delete_page ID
# Returns: API response (empty on success, error JSON on failure)
delete_page() {
    local id="$1"
    api_delete "/pages/${id}"
}

# Delete a chapter (and all its pages)
# Usage: delete_chapter ID
# Returns: API response (empty on success, error JSON on failure)
delete_chapter() {
    local id="$1"
    api_delete "/chapters/${id}"
}

# Delete a book (and all its chapters/pages)
# Usage: delete_book ID
# Returns: API response (empty on success, error JSON on failure)
delete_book() {
    local id="$1"
    api_delete "/books/${id}"
}

# Delete a shelf (books are NOT deleted, just unassigned)
# Usage: delete_shelf ID
# Returns: API response (empty on success, error JSON on failure)
delete_shelf() {
    local id="$1"
    api_delete "/shelves/${id}"
}

echo "API helpers loaded. Base URL: ${API_BASE}" >&2
