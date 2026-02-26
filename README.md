# SecureHST Insights

SecureHST Insights is a managed data visualization and business intelligence platform built on Apache Superset. This repository contains everything you need to deploy your own branded instance using pre-built Docker images.

## Prerequisites

| Requirement | Minimum |
|-------------|---------|
| Docker | 24+ |
| Docker Compose | v2+ (`docker compose` — note: no hyphen) |
| RAM | 4 GB |
| CPUs | 2 |

### Platform Compatibility

All container images are built for **linux/amd64**. This works on every major OS:

| Platform | Notes |
|----------|-------|
| **Linux (x86_64)** | Runs natively — no extra steps. |
| **macOS (Intel)** | Runs natively — no extra steps. |
| **macOS (Apple Silicon)** | Runs via emulation. **Enable Rosetta** in Docker Desktop for best performance (see below). |
| **Windows (x86_64)** | Runs natively inside Docker Desktop's Linux VM — no extra steps. |

#### Apple Silicon (M1/M2/M3/M4) Setup

Docker Desktop emulates amd64 on Apple Silicon Macs. For significantly better performance, enable Rosetta:

1. Open **Docker Desktop** → **Settings** → **General**
2. Check **Use Rosetta for x86_64/amd64 emulation on Apple Silicon**
3. Click **Apply & restart**

> Without Rosetta enabled the containers will still run, but you may notice slower startup times and higher CPU usage.

## Quick Start

1. **Clone this repository**

   ```bash
   git clone <your-repo-url> insights
   cd insights
   ```

2. **Create your environment file**

   ```bash
   cp .env.example .env
   ```

3. **Generate a secret key**

   ```bash
   python3 -c "import secrets; print(secrets.token_urlsafe(42))"
   ```

   Paste the output into `.env` as the value of `INSIGHTS_SECRET_KEY`.

4. **Set your admin password**

   Edit `.env` and change `ADMIN_PASSWORD` to something secure.

5. **Start the stack**

   ```bash
   docker compose up -d
   ```

6. **Wait for initialization to complete**

   The first run takes a few minutes while the database is set up. Watch progress with:

   ```bash
   docker compose logs -f superset-init
   ```

   When you see `Init Step 3/3 [Complete]` (or `4/4` if loading examples), open **https://your-domain** (or `https://localhost` for local testing) and log in with `admin` / your chosen password.

   > **Note:** Traefik handles TLS termination. For production, set `INSIGHTS_DOMAIN` and `ACME_EMAIL` in `.env` and ensure DNS points to your server. See [Traefik Reverse Proxy](#traefik-reverse-proxy) for details.

## Customizing Your Instance

### Branding

Drop your logo and favicon into the `assets/` directory (see [`assets/README.md`](assets/README.md)), then set these in `.env`:

```bash
INSIGHTS_APP_NAME=My Company Analytics
INSIGHTS_APP_ICON=/app/superset_home/assets/logo.png
INSIGHTS_FAVICON=/app/superset_home/assets/favicon.png
```

Restart the stack to apply: `docker compose restart superset`

### Theme

Customize colors, fonts, and sizing via environment variables:

```bash
# Primary brand color
INSIGHTS_THEME_COLOR_PRIMARY=#1a73e8

# Background
INSIGHTS_THEME_COLOR_BG_BASE=#ffffff
INSIGHTS_THEME_COLOR_BG_LAYOUT=#f5f5f5

# Typography
INSIGHTS_THEME_FONT_FAMILY=Inter, sans-serif
INSIGHTS_CUSTOM_FONT_URLS=https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700

# Sizing
INSIGHTS_THEME_BORDER_RADIUS=8
```

See the [Configuration Reference](#configuration-reference) for all available theme tokens.

### Navigation Links

Point the help and documentation links to your own resources:

```bash
INSIGHTS_DOCUMENTATION_URL=https://docs.example.com
INSIGHTS_DOCUMENTATION_TEXT=Help Center
INSIGHTS_BUG_REPORT_URL=https://support.example.com/tickets/new
INSIGHTS_BUG_REPORT_TEXT=Report an Issue
```

### Email / SMTP

Required for alerts and scheduled reports:

```bash
INSIGHTS_SMTP_HOST=smtp.example.com
INSIGHTS_SMTP_PORT=587
INSIGHTS_SMTP_USER=insights@example.com
INSIGHTS_SMTP_PASSWORD=your-smtp-password
INSIGHTS_SMTP_MAIL_FROM=insights@example.com
INSIGHTS_SMTP_STARTTLS=true
```

### Feature Flags

Enable or disable features by setting boolean values:

```bash
INSIGHTS_FEATURE_TAGGING=true           # Organize with tags
INSIGHTS_FEATURE_EMBEDDED=true          # Embed dashboards via iframe
INSIGHTS_FEATURE_SSH_TUNNELING=true     # SSH tunnels for databases
INSIGHTS_FEATURE_TEMPLATE_PROCESSING=true  # Jinja in SQL Lab
```

## Production Deployment

### Security Checklist

Before going to production, verify these settings:

- [ ] `INSIGHTS_SECRET_KEY` is set to a unique random value
- [ ] `ADMIN_PASSWORD` is changed from default
- [ ] `DATABASE_PASSWORD` and `POSTGRES_PASSWORD` are changed from default
- [ ] `FLASK_DEBUG=false`
- [ ] `INSIGHTS_DOMAIN` is set to your public domain name
- [ ] `ACME_EMAIL` is set to a valid email address
- [ ] `INSIGHTS_ENABLE_PROXY_FIX=true` (enabled by default in `.env.example`)
- [ ] `INSIGHTS_SESSION_COOKIE_SECURE=true` (enabled by default in `.env.example`)
- [ ] `INSIGHTS_FORCE_HTTPS=true` (enabled by default in `.env.example`)
- [ ] `INSIGHTS_TALISMAN_ENABLED=true`
- [ ] DNS A/AAAA record for `INSIGHTS_DOMAIN` points to your server

### Traefik Reverse Proxy

This stack includes a **Traefik v3 reverse proxy** that handles TLS termination with automatic Let's Encrypt certificates.

#### Prerequisites

1. A **public domain name** (e.g. `insights.example.com`) with DNS pointing to your server's IP
2. Ports **80** and **443** open on the server (for HTTP challenge and HTTPS traffic)

#### Configuration

Set these variables in `.env`:

```bash
# Your domain (must resolve to this server)
INSIGHTS_DOMAIN=insights.example.com

# Email for Let's Encrypt certificate expiry notifications
ACME_EMAIL=admin@example.com

# These are set by default in .env.example for HTTPS deployments:
INSIGHTS_ENABLE_PROXY_FIX=true
INSIGHTS_SESSION_COOKIE_SECURE=true
INSIGHTS_FORCE_HTTPS=true
```

Then start the stack:

```bash
docker compose up -d
```

Traefik will automatically:
- Obtain a TLS certificate from Let's Encrypt via HTTP challenge
- Redirect all HTTP traffic to HTTPS
- Add security headers (HSTS, X-Content-Type-Options, etc.)
- Proxy traffic to the Superset application on port 8088 internally

#### Security Headers

Traefik applies a `secHeaders` middleware with:
- **HSTS** (1 year, includeSubdomains, preload)
- **X-Content-Type-Options**: nosniff
- **X-Frame-Options**: SAMEORIGIN (allows Superset embedded dashboards)
- **Referrer-Policy**: strict-origin-when-cross-origin

Superset also has its own Talisman-based security headers (`INSIGHTS_TALISMAN_ENABLED`). Both layers can coexist as defense-in-depth. If you prefer a single source of truth, disable Talisman:

```bash
INSIGHTS_TALISMAN_ENABLED=false
```

#### Certificates

Let's Encrypt certificates are stored in a Docker volume (`letsencrypt`) and persist across container restarts. Traefik renews them automatically before expiry.

#### Local Development

For local testing without a valid domain, Traefik will still start but won't obtain a valid certificate. You can access the application at `https://localhost` with a browser warning (self-signed/staging cert), or use:

```bash
curl -k https://localhost/health
```

### Rate Limiting

Enable Redis-backed rate limiting for production:

```bash
INSIGHTS_RATELIMIT_ENABLED=true
# Storage URI is auto-configured from REDIS_HOST/REDIS_PORT
```

### Multi-Worker Results Backend

For multi-worker deployments, switch from filesystem to Redis for query results:

```bash
INSIGHTS_RESULTS_BACKEND_USE_REDIS=true
REDIS_RESULTS_DB=1
```

## Adding Database Drivers

To connect to databases beyond PostgreSQL, add the required Python driver to `docker/requirements-local.txt` (one package per line):

```
clickhouse-connect>=0.6
```

Common drivers:

| Database | Package |
|----------|---------|
| ClickHouse | `clickhouse-connect` |
| SQL Server | `pymssql` |
| Oracle | `cx_Oracle` |
| MySQL | `mysqlclient` |
| Snowflake | `snowflake-sqlalchemy` |
| Databricks | `databricks-sql-connector` |
| Trino | `trino` |
| BigQuery | `pybigquery` |
| ODBC | `pyodbc` |

After editing, restart the stack: `docker compose down && docker compose up -d`

## Operations

### Start / Stop / Restart

```bash
# Start all services
docker compose up -d

# Stop all services (preserves data)
docker compose down

# Restart a specific service
docker compose restart superset

# Restart everything
docker compose down && docker compose up -d
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f superset
docker compose logs -f superset-worker
```

### Health Check

```bash
# Production (with valid domain)
curl -f https://${INSIGHTS_DOMAIN}/health

# Local development
curl -kf https://localhost/health
```

### Upgrading

When a new image version is released:

```bash
# Pull the latest image
docker compose pull

# Restart (init will run migrations automatically)
docker compose down && docker compose up -d

# Watch the init process
docker compose logs -f superset-init
```

To pin a specific version instead of `latest`, set `TAG` in your `.env`:

```bash
TAG=1.2.0
```

### Backup & Restore

**Backup the PostgreSQL database:**

```bash
docker compose exec db pg_dumpall -U superset > backup_$(date +%Y%m%d).sql
```

**Restore from backup:**

```bash
docker compose down
docker volume rm insights_db_home
docker compose up -d db
docker compose exec -T db psql -U superset < backup_20240101.sql
docker compose up -d
```

## Configuration Reference

All environment variables supported in `.env`:

### Infrastructure

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_DB` | `superset` | PostgreSQL database name |
| `DATABASE_HOST` | `db` | Database hostname |
| `DATABASE_PORT` | `5432` | Database port |
| `DATABASE_USER` | `superset` | Database username |
| `DATABASE_PASSWORD` | `superset` | Database password |
| `REDIS_HOST` | `redis` | Redis hostname |
| `REDIS_PORT` | `6379` | Redis port |
| `INSIGHTS_SECRET_KEY` | — | **Required.** Application secret key |
| `ADMIN_PASSWORD` | `admin` | Initial admin user password |
| `SUPERSET_LOAD_EXAMPLES` | `no` | Load sample dashboards on first init |
| `FLASK_DEBUG` | `false` | Flask debug mode |
| `INSIGHTS_LOG_LEVEL` | `info` | Logging verbosity |

### Traefik / TLS

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_DOMAIN` | `insights.example.com` | Domain for TLS certificate and routing |
| `ACME_EMAIL` | `admin@example.com` | Let's Encrypt notification email |

### Branding

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_APP_NAME` | `Insights` | Application name in navbar |
| `INSIGHTS_APP_ICON` | Superset logo | Path to logo image |
| `INSIGHTS_LOGO_TARGET_PATH` | `/` | Logo click destination |
| `INSIGHTS_LOGO_TOOLTIP` | — | Logo hover tooltip |
| `INSIGHTS_LOGO_RIGHT_TEXT` | — | Text displayed beside logo |
| `INSIGHTS_FAVICON` | — | Path to favicon |

### Theme

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_BRAND_LOGO_HEIGHT` | — | Logo height (e.g. `28px`) |
| `INSIGHTS_BRAND_LOGO_MARGIN` | — | Logo margin (e.g. `8px 0`) |
| `INSIGHTS_THEME_COLOR_PRIMARY` | — | Primary brand color |
| `INSIGHTS_THEME_COLOR_ERROR` | — | Error color |
| `INSIGHTS_THEME_COLOR_WARNING` | — | Warning color |
| `INSIGHTS_THEME_COLOR_SUCCESS` | — | Success color |
| `INSIGHTS_THEME_COLOR_INFO` | — | Info color |
| `INSIGHTS_THEME_COLOR_BG_BASE` | — | Base background color |
| `INSIGHTS_THEME_COLOR_BG_LAYOUT` | — | Layout background color |
| `INSIGHTS_THEME_COLOR_TEXT_BASE` | — | Base text color |
| `INSIGHTS_THEME_COLOR_LINK` | — | Link color |
| `INSIGHTS_THEME_BORDER_RADIUS` | `6` | Border radius (px) |
| `INSIGHTS_THEME_FONT_SIZE` | `14` | Base font size (px) |
| `INSIGHTS_THEME_CONTROL_HEIGHT` | `32` | Control height (px) |
| `INSIGHTS_THEME_FONT_FAMILY` | — | Font family |
| `INSIGHTS_CUSTOM_FONT_URLS` | — | Comma-separated font URLs |

### Navigation Links

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_BUG_REPORT_URL` | — | Bug report URL |
| `INSIGHTS_BUG_REPORT_TEXT` | `Report a bug` | Bug report link text |
| `INSIGHTS_DOCUMENTATION_URL` | — | Documentation URL |
| `INSIGHTS_DOCUMENTATION_TEXT` | `Documentation` | Documentation link text |
| `INSIGHTS_TROUBLESHOOTING_LINK` | — | Troubleshooting page URL |
| `INSIGHTS_PERMISSION_INSTRUCTIONS_LINK` | — | Permission help URL |

### Email / SMTP

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_SMTP_HOST` | `localhost` | SMTP server hostname |
| `INSIGHTS_SMTP_PORT` | `25` | SMTP server port |
| `INSIGHTS_SMTP_USER` | `superset` | SMTP username |
| `INSIGHTS_SMTP_PASSWORD` | `superset` | SMTP password |
| `INSIGHTS_SMTP_MAIL_FROM` | `superset@superset.com` | From address |
| `INSIGHTS_SMTP_STARTTLS` | `true` | Use STARTTLS |
| `INSIGHTS_SMTP_SSL` | `false` | Use SSL |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_ENABLE_PROXY_FIX` | `false` | Enable reverse proxy support |
| `INSIGHTS_SESSION_COOKIE_SECURE` | `false` | Secure cookie flag |
| `INSIGHTS_SESSION_COOKIE_SAMESITE` | `Lax` | SameSite cookie policy |
| `INSIGHTS_TALISMAN_ENABLED` | `true` | Security headers |
| `INSIGHTS_FORCE_HTTPS` | `false` | Force HTTPS redirects |
| `INSIGHTS_CORS_EMBED_ORIGINS` | — | CORS origins (comma-separated) |
| `INSIGHTS_RATELIMIT_ENABLED` | `false` | Enable rate limiting |
| `INSIGHTS_RATELIMIT_REDIS_DB` | `2` | Redis DB for rate limits |
| `INSIGHTS_RATELIMIT_STORAGE_URI` | auto | Rate limit storage URI |

### Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_FEATURE_THUMBNAILS` | `true` | Dashboard/chart thumbnails |
| `INSIGHTS_FEATURE_PLAYWRIGHT` | `true` | Use Playwright for screenshots |
| `INSIGHTS_FEATURE_TAGGING` | `false` | Tagging system |
| `INSIGHTS_FEATURE_EMBEDDED` | `false` | Embedded dashboards |
| `INSIGHTS_FEATURE_EMBEDDABLE_CHARTS` | `true` | Embeddable chart links |
| `INSIGHTS_FEATURE_SSH_TUNNELING` | `false` | SSH tunnels for DB connections |
| `INSIGHTS_FEATURE_TEMPLATE_PROCESSING` | `false` | Jinja templates in SQL Lab |
| `INSIGHTS_FEATURE_GLOBAL_ASYNC_QUERIES` | `false` | WebSocket async queries |
| `INSIGHTS_FEATURE_THUMBNAILS_SQLA_LISTENERS` | `true` | Auto-invalidate thumbnails |

### Reports

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_WEBDRIVER_BASEURL` | — | Internal screenshot URL |
| `INSIGHTS_WEBDRIVER_BASEURL_USER_FRIENDLY` | — | Public URL for report links |
| `INSIGHTS_EMAIL_REPORTS_SUBJECT_PREFIX` | `[Report]` | Email subject prefix |
| `INSIGHTS_EMAIL_REPORTS_CTA` | `Explore in Superset` | Email call-to-action text |
| `INSIGHTS_ALERT_DRY_RUN` | `false` | Suppress delivery (testing) |
| `INSIGHTS_ALERT_MINIMUM_INTERVAL_MINUTES` | — | Min alert interval |
| `INSIGHTS_REPORT_MINIMUM_INTERVAL_MINUTES` | — | Min report interval |
| `INSIGHTS_ALERT_REPORTS_USE_FIXED_EXECUTOR` | `false` | Fixed executor chain |
| `INSIGHTS_ALERT_REPORTS_FIXED_EXECUTOR_USER` | `admin` | Fixed executor user |
| `INSIGHTS_SCREENSHOT_PLAYWRIGHT_TIMEOUT_MS` | — | Playwright timeout |
| `INSIGHTS_SCREENSHOT_PLAYWRIGHT_WAIT_EVENT` | — | Playwright wait event |
| `INSIGHTS_WEBDRIVER_EXTRA_ARGS` | — | Extra Chromium flags |

### Guest / Embedded

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_GUEST_TOKEN_JWT_SECRET` | — | JWT secret for guest tokens |
| `INSIGHTS_GUEST_TOKEN_JWT_EXP` | `300` | Token expiry (seconds) |
| `INSIGHTS_GUEST_ROLE_NAME` | `Public` | Guest user role |
| `INSIGHTS_GLOBAL_ASYNC_QUERIES_JWT_SECRET` | — | JWT secret for async queries |

### SQL Lab

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_SQLLAB_DEFAULT_LIMIT` | `1000` | Default row limit |
| `INSIGHTS_SQL_MAX_ROW` | `100000` | Maximum rows returned |
| `INSIGHTS_SQLLAB_TIMEOUT` | `30` | Query timeout (seconds) |
| `INSIGHTS_RESULTS_BACKEND_USE_REDIS` | `false` | Redis results backend |
| `REDIS_RESULTS_DB` | `1` | Redis DB for results |

### Other

| Variable | Default | Description |
|----------|---------|-------------|
| `INSIGHTS_BABEL_DEFAULT_LOCALE` | `en` | Default locale |
| `INSIGHTS_MAPBOX_API_KEY` | — | Mapbox API key |
| `INSIGHTS_SLACK_API_TOKEN` | — | Slack API token |
| `INSIGHTS_ENVIRONMENT_TAG` | — | Navbar badge (development/staging/production) |

## Troubleshooting

### Container won't start / restarts in a loop

```bash
docker compose logs superset-init
```

Check for database connection errors. Ensure `db` and `redis` containers are healthy before `superset-init` runs (they should be — compose handles this automatically).

### "Invalid login" after first setup

The default credentials are `admin` / the value of `ADMIN_PASSWORD` in your `.env`. The password is only set during the first `superset-init` run. If you need to reset it:

```bash
docker compose exec superset superset fab reset-password --username admin --password newpassword
```

### Port 80 or 443 already in use

Traefik needs ports 80 and 443. Stop any other web server (nginx, Apache, etc.) or adjust the port mappings in `docker-compose.yml` under the `traefik` service.

### Certificate not issued / Let's Encrypt errors

- Ensure `INSIGHTS_DOMAIN` resolves to your server's public IP (`dig +short ${INSIGHTS_DOMAIN}`)
- Ensure port 80 is reachable from the internet (Let's Encrypt HTTP challenge requires this)
- Check Traefik logs: `docker compose logs traefik`
- Let's Encrypt has [rate limits](https://letsencrypt.org/docs/rate-limits/) — if testing frequently, consider using a staging resolver

### Database driver not found

Add the driver to `docker/requirements-local.txt` and restart:

```bash
docker compose down && docker compose up -d
```

### Slow first load / thumbnails not generating

Thumbnail generation uses Playwright and can take a moment on first access. Check the worker logs:

```bash
docker compose logs -f superset-worker
```

### Slow performance on Apple Silicon Macs

The images are linux/amd64 and run under emulation on M-series Macs. Enable Rosetta in Docker Desktop for a significant speedup:

**Docker Desktop** → **Settings** → **General** → check **Use Rosetta for x86_64/amd64 emulation on Apple Silicon** → **Apply & restart**

Then restart the stack:

```bash
docker compose down && docker compose up -d
```

### "SECRET_KEY must be set" error

Generate and set `INSIGHTS_SECRET_KEY` in your `.env` file:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(42))"
```

### Need to completely reset

```bash
docker compose down -v   # Warning: destroys all data
docker compose up -d
```
