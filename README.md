# BookStack - EIC Engineering Curriculum & Standards Library

## Overview

BookStack is a self-hosted documentation and wiki platform used to maintain the EIC (Electrical & Controls) engineering curriculum and standards library.

| Property | Value |
|----------|-------|
| Stack Location | `/srv/stacks/work/bookstack` |
| Port | 11200 (localhost only) |
| Access | SSH tunnel, VS Code port forwarding, or Tailscale |
| Image | `linuxserver/bookstack:v25.12.1-ls240` |
| Database | MariaDB 11.4.5 |

## Quick Start

### 1. Generate APP_KEY

```bash
# Using OpenSSL (recommended)
echo "base64:$(openssl rand -base64 32)"
```

Copy the output (starts with `base64:...`).

### 2. Configure Environment

```bash
# Copy template
cp .env.example .env

# Edit and fill in values (especially APP_KEY, DB_PASSWORD, DB_ROOT_PASSWORD)
nano .env

# Set secure permissions
chmod 600 .env
```

### 3. Start the Stack

```bash
cd /srv/stacks/work/bookstack
docker compose up -d
```

### 4. Verify Health

```bash
# Check container status (wait for "healthy")
docker compose ps

# Test health endpoint
curl -f http://localhost:11200/status
```

### 5. Access BookStack

**Via SSH tunnel:**
```bash
ssh -L 11200:localhost:11200 admin@ssh.lceic.com
# Then open: http://localhost:11200
```

**Via VS Code:**
- Use Remote SSH extension
- Port 11200 will be auto-forwarded
- Or manually forward in the PORTS panel

**Via Tailscale:**
- Access directly via Tailscale IP: `http://<tailscale-ip>:11200`

### 6. Initial Login

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
├── .env.example          # Template
├── README.md             # This file
└── data/
    ├── bookstack/        # BookStack config, uploads, themes
    │   ├── www/          # Laravel application
    │   ├── log/          # Application logs
    │   └── keys/         # SSH keys (if configured)
    └── mariadb/          # Database files
```

## Common Operations

### View Logs

```bash
# All services
docker compose logs -f

# BookStack only
docker compose logs -f bookstack

# Database only
docker compose logs -f db

# Last 100 lines
docker compose logs --tail=100
```

### Restart Services

```bash
# Graceful restart
docker compose restart

# Full recreate (after config changes)
docker compose down && docker compose up -d
```

### Check Status

```bash
# Container health
docker compose ps

# Resource usage
docker stats bookstack-app bookstack-db

# Test health endpoint
curl http://localhost:11200/status
```

### Backup

```bash
# Using stack-backup (recommended)
stack-backup bookstack

# Manual backup with database dump
docker compose exec db mysqldump -u bookstack_user -p"${DB_PASSWORD}" bookstack > data/bookstack/db-backup.sql
tar -czf /srv/backups/work/bookstack/bookstack-$(date +%Y%m%d-%H%M%S).tar.gz \
  compose.yml .env data/
```

### Database Operations

```bash
# Connect to MariaDB CLI
docker compose exec db mariadb -u bookstack_user -p bookstack

# Export database
docker compose exec db mysqldump -u bookstack_user -p bookstack > backup.sql

# Import database
docker compose exec -T db mariadb -u bookstack_user -p bookstack < backup.sql
```

## Upgrade Procedure

### Before Upgrading

1. **Create backup**:
   ```bash
   stack-backup bookstack
   ```

2. **Check release notes**:
   - https://www.bookstackapp.com/blog/
   - https://github.com/linuxserver/docker-bookstack/releases

3. **Note current version**:
   ```bash
   docker compose exec bookstack cat /config/version
   ```

### Upgrade Steps

1. **Update image version in compose.yml**:
   ```yaml
   image: lscr.io/linuxserver/bookstack:NEW_VERSION_HERE
   ```

2. **Pull new image**:
   ```bash
   docker compose pull
   ```

3. **Recreate containers**:
   ```bash
   docker compose up -d
   ```

4. **Verify health**:
   ```bash
   docker compose ps
   curl -f http://localhost:11200/status
   ```

5. **Check logs for migration errors**:
   ```bash
   docker compose logs bookstack | grep -i error
   ```

### Rollback Procedure

If upgrade fails:

1. **Stop the stack**:
   ```bash
   docker compose down
   ```

2. **Restore from backup**:
   ```bash
   # Backup current (broken) state
   mv data data.failed.$(date +%Y%m%d)

   # Restore previous data
   tar -xzf /srv/backups/work/bookstack/bookstack-TIMESTAMP.tar.gz

   # Revert compose.yml image version
   nano compose.yml
   ```

3. **Restart with previous version**:
   ```bash
   docker compose up -d
   ```

## Health Checks

BookStack exposes a `/status` endpoint for health monitoring.

```bash
# Check application health
curl http://localhost:11200/status

# Expected: HTTP 200 with status information
```

**Portainer Integration**: Health status is visible in Portainer dashboard at https://localhost:9443.

## Security Checklist

Pre-deployment verification:

- [ ] Default admin credentials changed
- [ ] APP_KEY generated and unique
- [ ] .env file has 0600 permissions
- [ ] Port bound to 127.0.0.1 only (verify in compose.yml)
- [ ] Strong passwords (24+ chars) for DB_PASSWORD and DB_ROOT_PASSWORD
- [ ] Image version pinned (not :latest)
- [ ] Resource limits configured
- [ ] Regular backups configured

## SSO Configuration (Future)

BookStack supports multiple SSO methods. Configure when ready:

### SAML2 (Recommended for Enterprise)

Add to `.env`:
```bash
AUTH_METHOD=saml2
SAML2_NAME=Azure AD
SAML2_EMAIL_ATTRIBUTE=email
SAML2_EXTERNAL_ID_ATTRIBUTE=uid
SAML2_IDP_ENTITYID=https://login.microsoftonline.com/TENANT_ID
SAML2_AUTOLOAD_METADATA=true
```

### LDAP (Active Directory)

Add to `.env`:
```bash
AUTH_METHOD=ldap
LDAP_SERVER=ldap://dc.example.com
LDAP_BASE_DN=dc=example,dc=com
LDAP_USER_FILTER=(&(objectClass=user)(sAMAccountName=${user}))
```

### OIDC (OpenID Connect)

Add to `.env`:
```bash
AUTH_METHOD=oidc
OIDC_NAME=SSO Provider
OIDC_DISPLAY_NAME_CLAIMS=name
OIDC_CLIENT_ID=your_client_id
OIDC_CLIENT_SECRET=your_client_secret
OIDC_ISSUER=https://provider.example.com
```

See: https://www.bookstackapp.com/docs/admin/authentication/

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs bookstack

# Common issues:
# - Missing APP_KEY: Generate one (see Quick Start)
# - Database not ready: Wait for db health check
# - Permission issues: Check data/ directory ownership
```

### Database Connection Errors

```bash
# Verify database is healthy
docker compose ps db

# Check database logs
docker compose logs db

# Test connection
docker compose exec db mariadb -u bookstack_user -p -e "SELECT 1"
```

### Permission Errors

```bash
# Fix BookStack ownership (LinuxServer.io uses PUID/PGID 1000)
sudo chown -R 1000:1000 data/bookstack

# Fix MariaDB permissions (mysql user is 999)
sudo chown -R 999:999 data/mariadb
```

### Health Check Failing

```bash
# Test /status endpoint directly
docker compose exec bookstack curl -v http://localhost:80/status

# Check for PHP errors
docker compose logs bookstack | grep -i "PHP Fatal"

# Verify database connectivity
docker compose exec bookstack php /app/www/artisan tinker --execute="DB::connection()->getPdo();"
```

### Slow Performance

```bash
# Check resource usage
docker stats bookstack-app bookstack-db

# If memory constrained, increase limits in compose.yml
# If CPU constrained, consider adding Redis cache (see Future Enhancements)
```

## Resources

- [BookStack Documentation](https://www.bookstackapp.com/docs/)
- [LinuxServer.io BookStack Image](https://docs.linuxserver.io/images/docker-bookstack/)
- [VPS Platform Conventions](/srv/src/vps-platform/docs/CONVENTIONS.md)
- [VPS Platform Security](/srv/src/vps-platform/docs/SECURITY.md)
- [VPS Platform Backups](/srv/src/vps-platform/docs/BACKUPS.md)

---

**Stack Created**: 2026-01-12
**Port Allocation**: 11200 (see `/srv/src/vps-platform/docs/PORTS.md`)
**Maintainer**: EIC Engineering Team
