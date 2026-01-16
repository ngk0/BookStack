# Stack: bookstack

## Platform Rules

This stack is part of the standardized VPS Platform. When working on this application, **always follow these rules**:

### 1. Platform Documentation

Read and follow these platform docs (located in `/srv/src/vps-platform/docs/`):

- **GETTING-STARTED.md** - Deploying applications to the platform
- **CONVENTIONS.md** - Naming, ports, health checks, and standards
- **RUNBOOK.md** - Operations and troubleshooting
- **SECURITY.md** - Security best practices
- **PORTS.md** - Port allocation registry
- **BACKUPS.md** - Backup and restore procedures

### 2. Required Standards

#### Health Check Endpoint

BookStack exposes a `/status` endpoint that returns HTTP 200 when healthy.

```bash
# Check health
curl -f http://localhost:11200/status
```

#### Environment Variables

**All configuration comes from environment variables** (defined in `.env`), not hardcoded.

Key variables:
- `APP_KEY` - Laravel encryption key (base64 encoded)
- `APP_URL` - Public URL for the application
- `DB_*` - Database connection settings

#### Port Binding

The compose.yml binds to `127.0.0.1:11200` (localhost only). Public access is via the centralized reverse proxy.

### 3. Directory Structure

This stack follows the standard structure:

```
/srv/stacks/work/bookstack/
├── compose.yml          # Docker orchestration (DO NOT commit secrets here)
├── .env                 # Secrets and config (NEVER commit to git)
├── .env.example         # Template for new deployments
├── .gitignore           # Excludes .env and data/
├── README.md            # Operational documentation
├── CLAUDE.md            # This file (AI guidance)
├── data/                # Persistent data (backed up regularly)
│   ├── bookstack/       # App config, uploads, themes
│   ├── mariadb/         # Database files
│   └── hierarchy/       # Auto-generated hierarchy exports
│       ├── hierarchy.json   # LLM-ready structured export
│       ├── hierarchy.md     # Human-readable tree
│       ├── orphans.json     # Items in BookStack but not in structure.json
│       ├── last-structure-mtime  # Tracks when structure.json was last pushed
│       └── sync.log         # Sync execution log
└── setup/               # API configuration scripts
    ├── .env.setup       # API credentials (gitignored)
    ├── api-helpers.sh   # Reusable API functions
    ├── configure-bookstack.sh  # Creates roles, shelves, books, chapters
    ├── create-guide.sh  # Creates user guide book
    ├── sync-hierarchy.sh     # Exports hierarchy (runs every 30min)
    ├── apply-structure.sh     # Pushes structure.json to BookStack
    ├── bookstack-sync.service  # Systemd service unit
    ├── bookstack-sync.timer    # Systemd timer (30min)
    ├── structure.json   # Content hierarchy definition
    └── templates/       # Page templates and guide content
```

### 4. Security Rules

- **NEVER commit .env** to git (secrets go here only)
- **Ports bind to 127.0.0.1** in compose.yml (localhost only, not 0.0.0.0)
- **Run as non-root** user (PUID/PGID 1000 configured)
- **.env permissions** must be 0600 (`chmod 600 .env`)
- **Change default admin** credentials immediately after first login

### 5. Operations

**Deploy/restart stack**:
```bash
cd /srv/stacks/work/bookstack
docker compose up -d
```

**View logs**:
```bash
docker compose logs -f
docker compose logs -f bookstack  # App only
docker compose logs -f db         # Database only
```

**Check health**:
```bash
docker compose ps  # Look for "(healthy)" status
curl http://localhost:11200/status
```

**Backup before major changes**:
```bash
stack-backup bookstack
# Or manually:
tar -czf backup-$(date +%Y%m%d-%H%M%S).tar.gz data/
```

### 6. Git Workflow

This stack does not contain custom application code - it runs the official BookStack Docker image. Configuration and setup scripts are managed in this directory.

```bash
cd /srv/stacks/work/bookstack/

# Setup scripts can be version controlled
git status
git add setup/
git commit -m "Update content structure"
```

### 7. Independence

**This stack is completely independent** from other stacks:

- Own Docker network (default bridge + proxy-net for reverse proxy)
- Own secrets (.env)
- Own persistent data (data/)
- Own database (MariaDB container)
- Can be managed by different Claude sessions

### 8. Port Allocation

This stack uses port **11200** (allocated in PORTS.md).

| Port | Service | Binding |
|------|---------|---------|
| 11200 | BookStack Web | 127.0.0.1 (localhost only) |

Public access is via the centralized reverse proxy at https://learn.lceic.com

### 9. When in Doubt

- **Check existing docs first**: Look in `/srv/src/vps-platform/docs/`
- **Follow conventions**: Consistency across stacks is important
- **Ask before breaking standards**: These rules exist for security and maintainability

---

## Application-Specific Notes

### Application Architecture

BookStack is a documentation/wiki platform deployed as two containers:

```
┌─────────────────────────────────────────────────────────────┐
│                      Docker Network                         │
│  ┌─────────────────────┐    ┌─────────────────────────┐   │
│  │   bookstack-app     │    │     bookstack-db        │   │
│  │                     │    │                         │   │
│  │ linuxserver/        │───▶│ mariadb:11.4.5          │   │
│  │ bookstack:v25.12.1  │    │                         │   │
│  │                     │    │ Port: 3306 (internal)   │   │
│  │ Port: 80 (internal) │    └─────────────────────────┘   │
│  └──────────┬──────────┘                                   │
│             │                                               │
└─────────────┼───────────────────────────────────────────────┘
              │
              ▼ (via proxy-net)
┌─────────────────────────────────────────────────────────────┐
│              reverse-proxy-caddy                            │
│              https://learn.lceic.com                        │
└─────────────────────────────────────────────────────────────┘
```

**Images Used:**
- `linuxserver/bookstack:v25.12.1-ls240` - BookStack application
- `mariadb:11.4.5` - Database (LTS, supported through 2029)

### URLs

| Environment | URL | Notes |
|-------------|-----|-------|
| Production | https://learn.lceic.com | Public via reverse proxy |
| Local | http://localhost:11200 | Via SSH tunnel or Tailscale |
| Health Check | http://localhost:11200/status | Returns HTTP 200 |
| API | https://learn.lceic.com/api | REST API endpoints |

### Default Credentials

**CRITICAL: Change these immediately after first login!**

- **Email**: admin@admin.com
- **Password**: password

### API Configuration

BookStack has a REST API for programmatic content management.

**Token Location**: `/srv/stacks/work/bookstack/setup/.env.setup`

```bash
# API credentials (DO NOT commit to git)
BOOKSTACK_URL="https://learn.lceic.com"
BOOKSTACK_TOKEN_ID="your-token-id"
BOOKSTACK_TOKEN_SECRET="your-token-secret"
```

**API Documentation**: https://demo.bookstackapp.com/api/docs

### Setup Scripts

Located in `/srv/stacks/work/bookstack/setup/`:

| Script | Purpose | Usage |
|--------|---------|-------|
| `api-helpers.sh` | Reusable API functions | `source ./api-helpers.sh` |
| `configure-bookstack.sh` | Creates roles, shelves, books, chapters | `./configure-bookstack.sh [--dry-run]` |
| `create-guide.sh` | Creates "How to Use This BookStack" guide | `./create-guide.sh [--dry-run]` |
| `sync-hierarchy.sh` | Exports content hierarchy to JSON/Markdown | `./sync-hierarchy.sh [--verbose]` |
| `apply-structure.sh` | Pushes structure.json changes to BookStack | `./apply-structure.sh [--dry-run]` |

**All scripts are idempotent** - safe to re-run. They skip existing resources.

### Hierarchy Sync (Automated)

The content hierarchy is automatically exported every 30 minutes via systemd timer.

**Output Files** (in `data/hierarchy/`):

| File | Purpose |
|------|---------|
| `hierarchy.json` | Structured JSON for programmatic use and future LLM integration |
| `hierarchy.md` | Human-readable markdown tree |
| `sync.log` | Execution log |

**JSON Schema Features (LLM-Ready):**
- `_llm_hints.needs_content` - Flags pages with < 100 chars of content
- `_llm_hints.content_type` - Auto-classified (procedural, standard, training, etc.)
- `_llm_context` - Organization-wide context for content generation prompts

**Manual Run:**
```bash
cd /srv/stacks/work/bookstack/setup
./sync-hierarchy.sh --verbose
```

**Check Timer Status:**
```bash
systemctl list-timers | grep bookstack
journalctl -u bookstack-sync.service -f
```

**Query Empty Pages (via jq):**
```bash
jq '[.hierarchy.shelves[].books[].chapters[].pages[] | select(._llm_hints.needs_content == true)]' data/hierarchy/hierarchy.json
```

**Systemd Units:**
- Service: `/etc/systemd/system/bookstack-sync.service`
- Timer: `/etc/systemd/system/bookstack-sync.timer`

### Structure Push (Edit & Auto-Apply)

Edit `structure.json` and changes are automatically pushed to BookStack on the next 30-minute sync cycle.

**Workflow:**
1. Edit `setup/structure.json` (add/modify shelves, books, chapters)
2. Wait for next sync cycle (or run manually: `./sync-hierarchy.sh`)
3. Changes are detected via file mtime and pushed automatically

**What happens:**
- **Missing items**: Created in BookStack
- **Changed descriptions**: Updated in BookStack
- **Orphaned items**: Flagged in `orphans.json` (never auto-deleted)

**Manual Run:**
```bash
cd /srv/stacks/work/bookstack/setup

# Dry run - see what would change
./apply-structure.sh --dry-run --verbose

# Actually apply changes
./apply-structure.sh --verbose
```

**Orphans Report:**
Items in BookStack but not in `structure.json` are written to `data/hierarchy/orphans.json`:
```bash
cat ../data/hierarchy/orphans.json | jq '.orphaned_books'
```

**Important:** Orphans are NEVER deleted automatically. Review `orphans.json` and delete manually via BookStack UI if needed.

### Content Management via API

```bash
cd /srv/stacks/work/bookstack/setup

# Load API helpers
source ./api-helpers.sh

# Check API connectivity
check_api

# List shelves
list_shelves

# List books
list_books

# Create a new shelf
create_shelf "My Shelf" "Description here"

# Create a book
create_book "My Book" "Description here"

# Add book to shelf
add_book_to_shelf $BOOK_ID $SHELF_ID
```

### Content Structure

The BookStack is organized into 6 shelves (defined in `setup/structure.json`):

| Shelf | Purpose |
|-------|---------|
| Getting Started | Onboarding, orientation, finding things |
| EIC Standards Library | Official engineering standards |
| SOPs & Procedures | Step-by-step procedures |
| Training & Development | Career tracks, competencies |
| Reference Materials | Vendor docs, codes, templates |
| Project Knowledge Base | Lessons learned, case studies |

**To modify structure:**
1. Edit `setup/structure.json`
2. Run `./configure-bookstack.sh`

### Database Operations

The MariaDB database is stored at `./data/mariadb/`.

```bash
# Backup database
docker compose exec db mariadb-dump -u root -p bookstack > backup.sql

# Access database shell
docker compose exec db mariadb -u bookstack_user -p bookstack

# View database size
docker compose exec db du -sh /var/lib/mysql/
```

### Environment Variables

Key variables in `.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `APP_KEY` | Laravel encryption key | `base64:xxxxx` |
| `APP_URL` | Public URL | `https://learn.lceic.com` |
| `TZ` | Timezone | `America/New_York` |
| `DB_NAME` | Database name | `bookstack` |
| `DB_USER` | Database user | `bookstack_user` |
| `DB_PASSWORD` | Database password | (secret) |
| `DB_ROOT_PASSWORD` | MariaDB root password | (secret) |

**Mail Configuration** (optional, commented out by default):
- `MAIL_DRIVER`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_ENCRYPTION`
- `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM`, `MAIL_FROM_NAME`

### Roles & Permissions

Custom roles created via API:

| Role | Description |
|------|-------------|
| Standards Authority | Senior engineers who approve standards |
| Lead Engineer | Project leads with broad edit access |
| Engineer | Working engineers with standard access |
| Technician | Field technicians - SOPs focus |
| New Hire | Onboarding - limited access |
| Read-Only | External stakeholders |

### Tag-Based Workflow

Documents use tags to track approval status:

| Tag | Meaning |
|-----|---------|
| `status:draft` | Work in progress |
| `status:review` | Ready for review |
| `status:approved` | Officially approved |
| `status:archived` | No longer current |
| `owner:XXX` | Content owner (initials) |

### Updating BookStack

```bash
cd /srv/stacks/work/bookstack

# 1. Backup first
tar -czf backup-$(date +%Y%m%d-%H%M%S).tar.gz data/

# 2. Update image tag in compose.yml
# Edit: image: linuxserver/bookstack:vXX.XX.X-lsXXX

# 3. Pull and restart
docker compose pull
docker compose up -d

# 4. Verify health
docker compose ps
curl http://localhost:11200/status
```

### Troubleshooting

**Container won't start:**
```bash
docker compose logs bookstack
# Check for APP_KEY or database connection issues
```

**Health check failing:**
```bash
# Health check has 60s start_period - wait for DB init
docker compose ps
# Should show "healthy" after ~60 seconds
```

**Database connection errors:**
```bash
# Verify DB container is healthy
docker compose ps db
# Check credentials in .env match compose.yml
```

**API not working:**
```bash
# Verify token in setup/.env.setup
source setup/api-helpers.sh
check_api
```

**Content not showing:**
```bash
# Check if books are assigned to shelves
source setup/api-helpers.sh
list_shelves
list_books
```

### LAPORTE Brand Theme

BookStack has been customized with the official LAPORTE color palette.

**Color Palette:**

| Color | Hex | Usage |
|-------|-----|-------|
| Primary Dark Blue | `#00263b` | Headers, nav, primary elements |
| Accent Golden Yellow | `#E9B52D` | Shelves, highlights, CTAs |
| Light Blue | `#eef6f9` | Backgrounds |
| White | `#ffffff` | Page backgrounds |

**Theme Files:**
- `setup/templates/laporte-custom-head.html` - Custom CSS wrapped in `<style>` tags
- `data/bookstack/themes/laporte/styles.css` - Source CSS file

**Reapply Theme:**
```bash
cd /srv/stacks/work/bookstack
./setup/apply-laporte-theme.sh
```

**Modify Theme:**
1. Edit `data/bookstack/themes/laporte/styles.css`
2. Regenerate HTML: `echo "<style>" > setup/templates/laporte-custom-head.html && cat data/bookstack/themes/laporte/styles.css >> setup/templates/laporte-custom-head.html && echo "</style>" >> setup/templates/laporte-custom-head.html`
3. Reapply: `./setup/apply-laporte-theme.sh`

### Reverse Proxy Integration

This stack connects to the centralized reverse proxy via the `proxy-net` Docker network.

**Caddyfile entry** (in `/srv/stacks/work/reverse-proxy/Caddyfile`):
```
learn.lceic.com {
    reverse_proxy bookstack-app:80
    # ... headers and compression
}
```

**To add/change domain:**
1. Edit the reverse proxy Caddyfile
2. Reload Caddy: `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`
3. Update `APP_URL` in this stack's `.env`
4. Restart: `docker compose restart`

---

**Platform Version**: 1.0
**Application Version**: BookStack v25.12.1
**Last Updated**: 2026-01-13
