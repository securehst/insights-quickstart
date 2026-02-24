# SecureHST Insights

SecureHST Insights is a managed data visualization and business intelligence platform built on Apache Superset. This repository contains everything you need to deploy your own branded instance using pre-built Docker images.

## Prerequisites

| Requirement | Minimum |
|-------------|---------|
| Docker | 24+ |
| Docker Compose | v2+ (`docker compose` — note: no hyphen) |
| RAM | 4 GB |
| CPUs | 2 |

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

   Paste the output into `.env` as the value of `SUPERSET_SECRET_KEY`.

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

   When you see `Init Step 3/3 [Complete]` (or `4/4` if loading examples), open **http://localhost:8088** and log in with `admin` / your chosen password.

## Customizing Your Instance

### Branding

Drop your logo and favicon into the `assets/` directory (see [`assets/README.md`](assets/README.md)), then set these in `.env`:

```bash
SUPERSET_APP_NAME=My Company Analytics
SUPERSET_APP_ICON=/app/superset_home/assets/logo.png
SUPERSET_FAVICON=/app/superset_home/assets/favicon.png
```

Restart the stack to apply: `docker compose restart superset`

### Theme

Customize colors, fonts, and sizing via environment variables:

```bash
# Primary brand color
SUPERSET_THEME_COLOR_PRIMARY=#1a73e8

# Background
SUPERSET_THEME_COLOR_BG_BASE=#ffffff
SUPERSET_THEME_COLOR_BG_LAYOUT=#f5f5f5

# Typography
SUPERSET_THEME_FONT_FAMILY=Inter, sans-serif
SUPERSET_CUSTOM_FONT_URLS=https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700

# Sizing
SUPERSET_THEME_BORDER_RADIUS=8
```

See the [Configuration Reference](#configuration-reference) for all available theme tokens.

### Navigation Links

Point the help and documentation links to your own resources:

```bash
SUPERSET_DOCUMENTATION_URL=https://docs.example.com
SUPERSET_DOCUMENTATION_TEXT=Help Center
SUPERSET_BUG_REPORT_URL=https://support.example.com/tickets/new
SUPERSET_BUG_REPORT_TEXT=Report an Issue
```

### Email / SMTP

Required for alerts and scheduled reports:

```bash
SUPERSET_SMTP_HOST=smtp.example.com
SUPERSET_SMTP_PORT=587
SUPERSET_SMTP_USER=insights@example.com
SUPERSET_SMTP_PASSWORD=your-smtp-password
SUPERSET_SMTP_MAIL_FROM=insights@example.com
SUPERSET_SMTP_STARTTLS=true
```

### Feature Flags

Enable or disable features by setting boolean values:

```bash
SUPERSET_FEATURE_TAGGING=true           # Organize with tags
SUPERSET_FEATURE_EMBEDDED=true          # Embed dashboards via iframe
SUPERSET_FEATURE_SSH_TUNNELING=true     # SSH tunnels for databases
SUPERSET_FEATURE_TEMPLATE_PROCESSING=true  # Jinja in SQL Lab
```

## Production Deployment

### Security Checklist

Before going to production, verify these settings:

- [ ] `SUPERSET_SECRET_KEY` is set to a unique random value
- [ ] `ADMIN_PASSWORD` is changed from default
- [ ] `DATABASE_PASSWORD` and `POSTGRES_PASSWORD` are changed from default
- [ ] `FLASK_DEBUG=false`
- [ ] `SUPERSET_ENABLE_PROXY_FIX=true` (if behind a reverse proxy)
- [ ] `SUPERSET_SESSION_COOKIE_SECURE=true` (HTTPS deployments)
- [ ] `SUPERSET_FORCE_HTTPS=true` (HTTPS deployments)
- [ ] `SUPERSET_TALISMAN_ENABLED=true`

### Running Behind a Reverse Proxy

When running behind nginx, an ALB, or another reverse proxy:

```bash
SUPERSET_ENABLE_PROXY_FIX=true
SUPERSET_SESSION_COOKIE_SECURE=true
SUPERSET_FORCE_HTTPS=true
SUPERSET_SESSION_COOKIE_SAMESITE=Lax
```

Example nginx location block:

```nginx
location / {
    proxy_pass http://127.0.0.1:8088;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

### Rate Limiting

Enable Redis-backed rate limiting for production:

```bash
SUPERSET_RATELIMIT_ENABLED=true
# Storage URI is auto-configured from REDIS_HOST/REDIS_PORT
```

### Multi-Worker Results Backend

For multi-worker deployments, switch from filesystem to Redis for query results:

```bash
SUPERSET_RESULTS_BACKEND_USE_REDIS=true
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
curl -f http://localhost:8088/health
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
| `SUPERSET_SECRET_KEY` | — | **Required.** Application secret key |
| `ADMIN_PASSWORD` | `admin` | Initial admin user password |
| `SUPERSET_LOAD_EXAMPLES` | `no` | Load sample dashboards on first init |
| `SUPERSET_PORT` | `8088` | Host port mapping |
| `FLASK_DEBUG` | `false` | Flask debug mode |
| `SUPERSET_LOG_LEVEL` | `info` | Logging verbosity |

### Branding

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_APP_NAME` | `Insights` | Application name in navbar |
| `SUPERSET_APP_ICON` | Superset logo | Path to logo image |
| `SUPERSET_LOGO_TARGET_PATH` | `/` | Logo click destination |
| `SUPERSET_LOGO_TOOLTIP` | — | Logo hover tooltip |
| `SUPERSET_LOGO_RIGHT_TEXT` | — | Text displayed beside logo |
| `SUPERSET_FAVICON` | — | Path to favicon |

### Theme

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_BRAND_LOGO_HEIGHT` | — | Logo height (e.g. `28px`) |
| `SUPERSET_BRAND_LOGO_MARGIN` | — | Logo margin (e.g. `8px 0`) |
| `SUPERSET_THEME_COLOR_PRIMARY` | — | Primary brand color |
| `SUPERSET_THEME_COLOR_ERROR` | — | Error color |
| `SUPERSET_THEME_COLOR_WARNING` | — | Warning color |
| `SUPERSET_THEME_COLOR_SUCCESS` | — | Success color |
| `SUPERSET_THEME_COLOR_INFO` | — | Info color |
| `SUPERSET_THEME_COLOR_BG_BASE` | — | Base background color |
| `SUPERSET_THEME_COLOR_BG_LAYOUT` | — | Layout background color |
| `SUPERSET_THEME_COLOR_TEXT_BASE` | — | Base text color |
| `SUPERSET_THEME_COLOR_LINK` | — | Link color |
| `SUPERSET_THEME_BORDER_RADIUS` | `6` | Border radius (px) |
| `SUPERSET_THEME_FONT_SIZE` | `14` | Base font size (px) |
| `SUPERSET_THEME_CONTROL_HEIGHT` | `32` | Control height (px) |
| `SUPERSET_THEME_FONT_FAMILY` | — | Font family |
| `SUPERSET_CUSTOM_FONT_URLS` | — | Comma-separated font URLs |

### Navigation Links

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_BUG_REPORT_URL` | — | Bug report URL |
| `SUPERSET_BUG_REPORT_TEXT` | `Report a bug` | Bug report link text |
| `SUPERSET_DOCUMENTATION_URL` | — | Documentation URL |
| `SUPERSET_DOCUMENTATION_TEXT` | `Documentation` | Documentation link text |
| `SUPERSET_TROUBLESHOOTING_LINK` | — | Troubleshooting page URL |
| `SUPERSET_PERMISSION_INSTRUCTIONS_LINK` | — | Permission help URL |

### Email / SMTP

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_SMTP_HOST` | `localhost` | SMTP server hostname |
| `SUPERSET_SMTP_PORT` | `25` | SMTP server port |
| `SUPERSET_SMTP_USER` | `superset` | SMTP username |
| `SUPERSET_SMTP_PASSWORD` | `superset` | SMTP password |
| `SUPERSET_SMTP_MAIL_FROM` | `superset@superset.com` | From address |
| `SUPERSET_SMTP_STARTTLS` | `true` | Use STARTTLS |
| `SUPERSET_SMTP_SSL` | `false` | Use SSL |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_ENABLE_PROXY_FIX` | `false` | Enable reverse proxy support |
| `SUPERSET_SESSION_COOKIE_SECURE` | `false` | Secure cookie flag |
| `SUPERSET_SESSION_COOKIE_SAMESITE` | `Lax` | SameSite cookie policy |
| `SUPERSET_TALISMAN_ENABLED` | `true` | Security headers |
| `SUPERSET_FORCE_HTTPS` | `false` | Force HTTPS redirects |
| `SUPERSET_CORS_EMBED_ORIGINS` | — | CORS origins (comma-separated) |
| `SUPERSET_RATELIMIT_ENABLED` | `false` | Enable rate limiting |
| `SUPERSET_RATELIMIT_REDIS_DB` | `2` | Redis DB for rate limits |
| `SUPERSET_RATELIMIT_STORAGE_URI` | auto | Rate limit storage URI |

### Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_FEATURE_THUMBNAILS` | `true` | Dashboard/chart thumbnails |
| `SUPERSET_FEATURE_PLAYWRIGHT` | `true` | Use Playwright for screenshots |
| `SUPERSET_FEATURE_TAGGING` | `false` | Tagging system |
| `SUPERSET_FEATURE_EMBEDDED` | `false` | Embedded dashboards |
| `SUPERSET_FEATURE_EMBEDDABLE_CHARTS` | `true` | Embeddable chart links |
| `SUPERSET_FEATURE_SSH_TUNNELING` | `false` | SSH tunnels for DB connections |
| `SUPERSET_FEATURE_TEMPLATE_PROCESSING` | `false` | Jinja templates in SQL Lab |
| `SUPERSET_FEATURE_GLOBAL_ASYNC_QUERIES` | `false` | WebSocket async queries |
| `SUPERSET_FEATURE_THUMBNAILS_SQLA_LISTENERS` | `true` | Auto-invalidate thumbnails |

### Reports

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_WEBDRIVER_BASEURL` | — | Internal screenshot URL |
| `SUPERSET_WEBDRIVER_BASEURL_USER_FRIENDLY` | — | Public URL for report links |
| `SUPERSET_EMAIL_REPORTS_SUBJECT_PREFIX` | `[Report]` | Email subject prefix |
| `SUPERSET_EMAIL_REPORTS_CTA` | `Explore in Superset` | Email call-to-action text |
| `SUPERSET_ALERT_DRY_RUN` | `false` | Suppress delivery (testing) |
| `SUPERSET_ALERT_MINIMUM_INTERVAL_MINUTES` | — | Min alert interval |
| `SUPERSET_REPORT_MINIMUM_INTERVAL_MINUTES` | — | Min report interval |
| `SUPERSET_ALERT_REPORTS_USE_FIXED_EXECUTOR` | `false` | Fixed executor chain |
| `SUPERSET_ALERT_REPORTS_FIXED_EXECUTOR_USER` | `admin` | Fixed executor user |
| `SUPERSET_SCREENSHOT_PLAYWRIGHT_TIMEOUT_MS` | — | Playwright timeout |
| `SUPERSET_SCREENSHOT_PLAYWRIGHT_WAIT_EVENT` | — | Playwright wait event |
| `SUPERSET_WEBDRIVER_EXTRA_ARGS` | — | Extra Chromium flags |

### Guest / Embedded

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_GUEST_TOKEN_JWT_SECRET` | — | JWT secret for guest tokens |
| `SUPERSET_GUEST_TOKEN_JWT_EXP` | `300` | Token expiry (seconds) |
| `SUPERSET_GUEST_ROLE_NAME` | `Public` | Guest user role |
| `SUPERSET_GLOBAL_ASYNC_QUERIES_JWT_SECRET` | — | JWT secret for async queries |

### SQL Lab

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_SQLLAB_DEFAULT_LIMIT` | `1000` | Default row limit |
| `SUPERSET_SQL_MAX_ROW` | `100000` | Maximum rows returned |
| `SUPERSET_SQLLAB_TIMEOUT` | `30` | Query timeout (seconds) |
| `SUPERSET_RESULTS_BACKEND_USE_REDIS` | `false` | Redis results backend |
| `REDIS_RESULTS_DB` | `1` | Redis DB for results |

### Other

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERSET_BABEL_DEFAULT_LOCALE` | `en` | Default locale |
| `SUPERSET_MAPBOX_API_KEY` | — | Mapbox API key |
| `SUPERSET_SLACK_API_TOKEN` | — | Slack API token |
| `SUPERSET_ENVIRONMENT_TAG` | — | Navbar badge (development/staging/production) |

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

### Port 8088 already in use

Change the port mapping in `.env`:

```bash
SUPERSET_PORT=8090
```

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

### "SECRET_KEY must be set" error

Generate and set `SUPERSET_SECRET_KEY` in your `.env` file:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(42))"
```

### Need to completely reset

```bash
docker compose down -v   # Warning: destroys all data
docker compose up -d
```
