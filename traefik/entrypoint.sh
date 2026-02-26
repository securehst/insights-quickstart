#!/bin/sh
# =============================================================================
# Traefik entrypoint — auto-configure based on INSIGHTS_DOMAIN
# =============================================================================
# Detects whether INSIGHTS_DOMAIN is a local address (localhost, *.local,
# 127.0.0.1) or a real domain, then generates the appropriate Traefik
# static and dynamic configuration before starting Traefik.
#
# Local mode:  HTTP-only, no TLS, no HSTS, no Let's Encrypt
# Production:  HTTPS with Let's Encrypt, HTTP→HTTPS redirect, full HSTS

set -e

DOMAIN="${INSIGHTS_DOMAIN:-localhost}"

# ---------------------------------------------------------------------------
# Detect local vs production
# ---------------------------------------------------------------------------
is_local=false
case "$DOMAIN" in
  localhost|127.0.0.1|"") is_local=true ;;
  *.localhost|*.local)    is_local=true ;;
esac

echo "traefik-entrypoint: INSIGHTS_DOMAIN=${DOMAIN} (local=${is_local})"

# ---------------------------------------------------------------------------
# Ensure output directories exist
# ---------------------------------------------------------------------------
mkdir -p /etc/traefik/dynamic

# ---------------------------------------------------------------------------
# Generate static configuration (traefik.yml)
# ---------------------------------------------------------------------------
if [ "$is_local" = "true" ]; then
cat > /etc/traefik/traefik.yml <<'EOF'
entryPoints:
  web:
    address: ":80"

providers:
  file:
    directory: /etc/traefik/dynamic/
    watch: true

log:
  level: WARN
EOF
else
cat > /etc/traefik/traefik.yml <<EOF
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  file:
    directory: /etc/traefik/dynamic/
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: WARN
EOF
fi

# ---------------------------------------------------------------------------
# Generate dynamic middlewares
# ---------------------------------------------------------------------------
if [ "$is_local" = "true" ]; then
cat > /etc/traefik/dynamic/middlewares.yml <<'EOF'
http:
  middlewares:
    secHeaders:
      headers:
        contentTypeNosniff: true
        frameDeny: false
        customFrameOptionsValue: "SAMEORIGIN"
EOF
else
cat > /etc/traefik/dynamic/middlewares.yml <<'EOF'
http:
  middlewares:
    secHeaders:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        contentTypeNosniff: true
        frameDeny: false
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""
EOF
fi

# ---------------------------------------------------------------------------
# Generate dynamic routers
# ---------------------------------------------------------------------------
if [ "$is_local" = "true" ]; then
cat > /etc/traefik/dynamic/routers.yml <<EOF
http:
  routers:
    superset:
      rule: "Host(\`${DOMAIN}\`)"
      entryPoints:
        - web
      service: superset
      middlewares:
        - secHeaders

  services:
    superset:
      loadBalancer:
        servers:
          - url: "http://superset:8088"
EOF
else
cat > /etc/traefik/dynamic/routers.yml <<EOF
http:
  routers:
    superset:
      rule: "Host(\`${DOMAIN}\`)"
      entryPoints:
        - websecure
      service: superset
      middlewares:
        - secHeaders
      tls:
        certResolver: letsencrypt

  services:
    superset:
      loadBalancer:
        servers:
          - url: "http://superset:8088"
EOF
fi

echo "traefik-entrypoint: configuration generated, starting Traefik..."

# ---------------------------------------------------------------------------
# Start Traefik
# ---------------------------------------------------------------------------
exec traefik
