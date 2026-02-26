# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **SecureHST Insights**, a Docker Compose deployment project for Apache Superset. It is not a source code project — it orchestrates pre-built container images (`ghcr.io/securehst/securehst-insights`) with configuration for branding, theming, TLS, and security.

## Common Commands

```bash
# Start/stop the stack
docker compose up -d
docker compose down

# View logs
docker compose logs -f superset          # App logs
docker compose logs -f superset-init     # Init/migration logs
docker compose logs -f superset-worker   # Celery worker logs

# Health check
curl -kf https://localhost/health

# Restart a single service
docker compose restart superset

# Pull latest images and redeploy
docker compose pull && docker compose down && docker compose up -d

# Reset admin password
docker compose exec superset superset fab reset-password --username admin --password newpassword

# Database backup/restore
docker compose exec db pg_dumpall -U superset > backup_$(date +%Y%m%d).sql
docker compose exec -T db psql -U superset < backup_YYYYMMDD.sql

# Full reset (destroys all data)
docker compose down -v && docker compose up -d
```

## Architecture

```
Internet → Traefik (TLS/proxy, ports 80+443)
              ↓
           Superset (Gunicorn, port 8088 internal)
           ├── PostgreSQL 16 (metadata store)
           ├── Redis 7 (cache + Celery broker + results backend)
           ├── Celery Worker (async tasks, reports)
           └── Celery Beat (scheduled tasks)
```

**Services** (docker-compose.yml):
- `traefik` — Reverse proxy with automatic Let's Encrypt TLS in production, HTTP-only for localhost
- `db` — PostgreSQL 16 for Superset metadata
- `redis` — Cache, Celery message broker, and async query results
- `superset-init` — One-shot: runs migrations, creates admin user, then exits
- `superset` — Main web app (Gunicorn)
- `superset-worker` — Celery background worker
- `superset-worker-beat` — Celery periodic task scheduler

All Superset services use the same image and share volumes defined via YAML anchors (`x-superset-image`, `x-superset-volumes`, `x-superset-defaults`).

## Key Files

- `.env` / `.env.example` — All configuration (branding, theme, features, security, SMTP, etc.). The `.env.example` has 200+ lines organized by section. This is the primary file users edit.
- `docker-compose.yml` — Service orchestration with YAML anchors for DRY config
- `traefik/entrypoint.sh` — Bash script that dynamically generates Traefik config based on `INSIGHTS_DOMAIN` (localhost = HTTP-only, real domain = HTTPS + Let's Encrypt + HSTS)
- `traefik/dynamic/middlewares.yml` — Security headers (HSTS, nosniff, X-Frame-Options SAMEORIGIN)
- `docker/requirements-local.txt` — Additional Python packages (database drivers) installed at container startup
- `assets/logo.png`, `assets/favicon.png` — Branding assets mounted into the container

## Configuration Pattern

All customization flows through environment variables in `.env`. Variable naming convention: `INSIGHTS_*` for app settings, with sections for branding, theme (light/dark mode), features, security, SMTP, and integrations. The container image reads these at startup — no rebuild needed.

## Local vs Production

The `INSIGHTS_DOMAIN` value controls the deployment mode:
- `localhost` / `*.local` / `127.0.0.1` → HTTP only, no TLS, relaxed security
- Any real domain → HTTPS with Let's Encrypt, HTTP→HTTPS redirect, HSTS enabled

This logic lives in `traefik/entrypoint.sh`.