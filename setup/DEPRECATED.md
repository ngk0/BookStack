# DEPRECATED - Scripts Migrated to Content-Generator

**Date:** 2026-01-14

The following scripts and templates in this directory have been migrated to the **content-generator** application and should no longer be used directly.

## Migrated Components

### Shell Scripts → TypeScript Services

| Old Script | New Location | Notes |
|------------|--------------|-------|
| `api-helpers.sh` | `content-generator/app/src/server/routes/bookstack.ts` | Full CRUD API now in TypeScript |
| `apply-structure.sh` | `content-generator/app/src/server/services/structure.ts` | Sync via `POST /api/structure/sync` |
| `sync-hierarchy.sh` | `content-generator/app/src/server/routes/bookstack.ts` | Export via `GET /api/bookstack/export/json` |
| `delete-orphans.sh` | `content-generator/app/src/server/routes/structure.ts` | Orphan mgmt via `/api/structure/orphans` |
| `generate-content.sh` | `content-generator/app/src/server/services/workflow.ts` | Book generation workflow |
| `enhance-structure.sh` | `content-generator/app/src/server/routes/structure.ts` | Preview via `POST /api/structure/preview` |

### Templates → Content-Generator Data

| Old Location | New Location |
|--------------|--------------|
| `prompts/module-template.md` | `content-generator/data/templates/bookstack/prompts/` |
| `prompts/structure-review.md` | `content-generator/data/templates/bookstack/prompts/` |
| `prompts/chapter-defaults.yaml` | `content-generator/data/templates/bookstack/prompts/` |
| `templates/sop-template.md` | `content-generator/data/templates/bookstack/documents/` |
| `templates/competency-checklist-template.md` | `content-generator/data/templates/bookstack/documents/` |
| `templates/qc-checklist-template.md` | `content-generator/data/templates/bookstack/documents/` |
| `templates/technical-specification-template.md` | `content-generator/data/templates/bookstack/documents/` |

### Structure Definition

| Old Location | New Location |
|--------------|--------------|
| `structure.yaml` | `content-generator/data/structure.yaml` |

## Scripts Still in Use

The following remain in bookstack and are NOT deprecated:

| Script | Purpose |
|--------|---------|
| `validate-env.sh` | Validates `.env` configuration |
| `configure-bookstack.sh` | Initial BookStack configuration |
| `create-guide.sh` | Deploys static usage guide (one-time) |
| `apply-laporte-theme.sh` | Applies brand CSS theme |
| `bookstack-sync.timer` | Systemd timer (update to call content-generator API) |

## New API Endpoints

Use these content-generator endpoints instead of shell scripts:

```bash
# Structure Management
POST /api/structure/definition      # Upload structure.yaml
POST /api/structure/validate        # Validate YAML
POST /api/structure/preview         # Preview changes
POST /api/structure/sync            # Execute sync
GET  /api/structure/orphans         # List orphans
DELETE /api/structure/orphans/:id   # Delete orphan

# Hierarchy Export
GET /api/bookstack/export/json      # Full hierarchy JSON
GET /api/bookstack/export/markdown  # Human-readable markdown

# BookStack CRUD
POST/PUT/DELETE /api/bookstack/shelves/:id
POST/PUT/DELETE /api/bookstack/books/:id
POST/PUT/DELETE /api/bookstack/chapters/:id
```

## Migration Notes

1. **Systemd Timer**: Update `bookstack-sync.timer` to call content-generator API:
   ```bash
   curl -X POST -u $AUTH_USER:$AUTH_PASS \
     http://localhost:11400/api/structure/sync
   ```

2. **Structure YAML**: The canonical source is now `content-generator/data/structure.yaml`

3. **Orphan Review**: Use the content-generator UI or API to review and delete orphans

## Removal Timeline

These deprecated scripts will be removed in a future cleanup. Until then, they remain for reference but should not be executed.
