# GitHub Copilot Instructions - BookStack CMS Platform

## Canonical Rules
Read `CLAUDE.md` at project root before any work. It is the source of truth.

## Project Role
BookStack is the CMS platform for LAPORTE Engineering documentation. Content-generator publishes to this system via REST API at `/api/pages`, `/api/chapters`, `/api/books`.

## Architecture
- **Stack**: LinuxServer BookStack image + MariaDB 11.4.5
- **Port**: `127.0.0.1:11200` (localhost only, behind Caddy reverse proxy)
- **Data**: `data/bookstack/` (app), `data/mariadb/` (database), `data/hierarchy/` (exported JSON/MD)
- **Health check**: `curl http://localhost:11200/status`

## Content Hierarchy (6 Shelves)
1. Getting Started - Onboarding, task indexes
2. EIC Standards Library - Normative standards, delta overlays
3. SOPs & Procedures - Workflows, deliverable playbooks
4. Training & Development - Tracks, modules, competencies
5. Reference Materials - Vendor docs, templates
6. Project Knowledge Base - Lessons learned, case studies

## LAPORTE Brand Colors
- Primary Dark Blue: `#00263b`
- Accent Golden Yellow: `#E9B52D`
- Light Blue Background: `#eef6f9`

## Shell Script Conventions
All scripts in `setup/` follow these patterns:
```bash
set -euo pipefail  # Strict mode (always)
```
- **Idempotent**: Safe to re-run without side effects
- **Flags**: Support `--dry-run`, `--verbose`, `--force`
- **Rate limiting**: 100ms between API calls (`sleep 0.1`)
- **Logging**: `[$(date '+%Y-%m-%d %H:%M:%S')] message`
- **Validation**: `: "${VAR:?VAR not set}"` for required env vars

## Credential Flow
| Scope | File | Purpose |
|-------|------|---------|
| Docker | `.env` | APP_KEY, DB passwords (chmod 600) |
| API Scripts | `setup/.env.setup` | BOOKSTACK_URL, TOKEN_ID, TOKEN_SECRET (chmod 600) |

Never commit `.env` or `.env.setup`. Use `.example` templates.

## Key Files
| File | Purpose |
|------|---------|
| [setup/api-helpers.sh](setup/api-helpers.sh) | Reusable BookStack API functions |
| [setup/sync-hierarchy.sh](setup/sync-hierarchy.sh) | Export hierarchy to JSON/MD (runs via systemd timer) |
| [setup/apply-structure.sh](setup/apply-structure.sh) | Push structure.yaml to BookStack |
| [setup/structure.yaml](setup/structure.yaml) | Content hierarchy definition |
| [setup/prompts/](setup/prompts/) | LLM prompt templates for content generation |

## Validation
Run before deploying:
```bash
./setup/validate-env.sh
docker compose up -d
curl -f http://localhost:11200/status
```

## Security
- Ports bind to `127.0.0.1` only (not `0.0.0.0`)
- Run as non-root (PUID/PGID 1000)
- Never delete orphans automatically—manual review required
