# BookStack - EIC Engineering Curriculum & Standards Library

## Overview

BookStack is a self-hosted documentation and wiki platform used to maintain the EIC (Electrical & Controls) engineering curriculum and standards library. It integrates with the **Content Generator** application for AI-powered content enrichment and management.

| Property | Value |
|----------|-------|
| Stack Location | `/srv/stacks/work/bookstack` |
| Port | 11200 (localhost only) |
| Public URL | https://learn.lceic.com |
| Content Generator | https://content-generator.lceic.com |
| Image | `linuxserver/bookstack:v25.12.1-ls240` |
| Database | MariaDB 11.4.5 |

## Admin Banner & Content Generator Integration

When logged in as an admin, BookStack displays a toolbar banner at the top of every page with quick actions:

| Button | Action |
|--------|--------|
| **Enrich** | Opens Content Generator to expand/improve the current page with AI |
| **Organize** | Reorganizes page content to match a template structure |
| **Flag for Review** | Flags the page for admin review |
| **Review Queue** | Shows pages flagged for review |
| **Health** | Opens content health dashboard |
| **Costs** | Opens AI cost tracking dashboard |
| **Generator** | Opens Content Generator home |

### How Enrich Works

When you click **Enrich** on a page:

1. Opens Content Generator with the page URL pre-filled
2. **Model**: Pre-selects Gemini 3 Flash Preview (fast, cost-effective)
3. **Guidance**: Pre-fills with "Review content and correct errors if observed. Otherwise add detail and expand the content while maintaining the existing organization and styles of the page."
4. **Auto-starts**: Begins enrichment immediately

The AI will:
- Add a **Metadata Header** table at the top (if not present)
- Set **Status** to "Active"
- Set **Last reviewed** to today's date
- Set **Next review** to 2 years from today
- Expand thin sections with more detail
- Correct any errors found
- Preserve existing structure and formatting

### Metadata Header Format

All enriched pages include this standard header:

| Field | Value |
|-------|-------|
| Owner role | Lead Engineer |
| Status | Active |
| Last reviewed | YYYY-MM-DD (generation date) |
| Next review | YYYY-MM-DD (2 years from generation) |
| Applies to | [Scope description] |

## Quick Start

### 1. Generate APP_KEY

```bash
echo "base64:$(openssl rand -base64 32)"
```

Copy the output (starts with `base64:...`).

### 2. Configure Environment

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

### 3. Start the Stack

```bash
cd /srv/stacks/work/bookstack
docker compose up -d
```

### 4. Verify Health

```bash
docker compose ps
curl -f http://localhost:11200/status
```

### 5. Initial Login

| Field | Value |
|-------|-------|
| Email | `admin@admin.com` |
| Password | `password` |

**IMPORTANT**: Change these credentials immediately after first login!

## Directory Structure

```
/srv/stacks/work/bookstack/
├── compose.yml           # Docker Compose configuration
├── .env                  # Secrets (never commit!)
├── README.md             # This file
├── CLAUDE.md             # AI coding guidelines
├── data/
│   ├── bookstack/        # BookStack config, uploads, themes
│   │   └── www/themes/   # Custom themes (LAPORTE)
│   ├── mariadb/          # Database files
│   └── hierarchy/        # Auto-generated hierarchy exports
└── setup/
    ├── .env.setup        # API credentials (gitignored)
    ├── deploy-theme.sh   # Deploy theme files to container
    ├── apply-laporte-theme.sh  # Apply theme to database
    ├── theme/            # Theme source files
    │   ├── functions.php
    │   ├── custom-head.html  # Admin banner CSS/JS
    │   └── layouts/      # Blade template overrides
    └── templates/        # Page templates
```

## LAPORTE Brand Theme

| Color | Hex | Usage |
|-------|-----|-------|
| Primary Dark Blue | `#00263b` | Headers, nav, primary elements |
| Accent Golden Yellow | `#E9B52D` | Shelves, highlights, CTAs |
| Light Blue | `#eef6f9` | Backgrounds |

### Reapply Theme

```bash
cd /srv/stacks/work/bookstack
./setup/deploy-theme.sh
./setup/apply-laporte-theme.sh
```

### Modify Theme

1. Edit `setup/templates/laporte-custom-head.html`
2. Copy: `cp setup/templates/laporte-custom-head.html setup/theme/custom-head.html`
3. Deploy: `./setup/deploy-theme.sh`
4. Apply: `./setup/apply-laporte-theme.sh`

## Common Operations

### View Logs

```bash
docker compose logs -f bookstack
docker compose logs -f db
```

### Restart Services

```bash
docker compose restart
docker compose down && docker compose up -d
```

### Backup

```bash
stack-backup bookstack
```

### Database CLI

```bash
docker compose exec db mariadb -u bookstack_user -p bookstack
```

## Setup Scripts

| Script | Purpose |
|--------|---------|
| `deploy-theme.sh` | Deploy theme files to BookStack container |
| `apply-laporte-theme.sh` | Apply custom head HTML via database |
| `sync-hierarchy.sh` | Export hierarchy to JSON/Markdown (runs every 30min) |
| `apply-structure.sh` | Push structure.json changes to BookStack |
| `configure-bookstack.sh` | Create roles, shelves, books, chapters |

All scripts are idempotent - safe to re-run.

## Troubleshooting

### Admin Banner Not Showing

```bash
./setup/deploy-theme.sh --restart
./setup/apply-laporte-theme.sh
# Clear browser cache (Ctrl+Shift+R)
```

### Container Won't Start

```bash
docker compose logs bookstack
# Check for missing APP_KEY or database connection issues
```

### Permission Errors

```bash
sudo chown -R 1000:1000 data/bookstack
sudo chown -R 999:999 data/mariadb
```

## API Configuration

**Token Location**: `/srv/stacks/work/bookstack/setup/.env.setup`

```bash
BOOKSTACK_URL="https://learn.lceic.com"
BOOKSTACK_TOKEN_ID="your-token-id"
BOOKSTACK_TOKEN_SECRET="your-token-secret"
```

**API Docs**: https://demo.bookstackapp.com/api/docs

## Resources

- [BookStack Documentation](https://www.bookstackapp.com/docs/)
- [LinuxServer.io BookStack Image](https://docs.linuxserver.io/images/docker-bookstack/)
- [Content Generator](https://content-generator.lceic.com) - AI content management

---

**Last Updated**: 2026-01-23
**Port**: 11200
**Maintainer**: EIC Engineering Team
