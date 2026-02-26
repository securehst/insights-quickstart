#!/usr/bin/env bash
# =============================================================================
# SecureHST Insights — Interactive Setup Wizard
# =============================================================================
# Walks through configuration in tiers: essential → production → customization.
# Auto-generates secrets, validates input, and gets you to a running stack.
#
# Usage: bash setup.sh [options]
#   --non-interactive, -y   Use defaults + generated secrets, no prompts
#   --no-color              Disable ANSI colors
#   --no-start              Skip "start services?" prompt
#   --domain <value>        Pre-set domain
#   --admin-password <val>  Pre-set admin password
#   --acme-email <value>    Pre-set ACME email
#   --help, -h              Show this help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
ENV_FILE="${SCRIPT_DIR}/.env"

NON_INTERACTIVE=false
NO_COLOR=false
NO_START=false
FLAG_DOMAIN=""
FLAG_ADMIN_PASSWORD=""
FLAG_ACME_EMAIL=""

# Values collected during configuration (written at confirmation)
CONF_DOMAIN=""
CONF_ACME_EMAIL=""
CONF_SECRET_KEY=""
CONF_ADMIN_PASSWORD=""
CONF_DB_PASSWORD=""
CONF_SMTP_HOST=""
CONF_SMTP_PORT=""
CONF_SMTP_USER=""
CONF_SMTP_PASSWORD=""
CONF_SMTP_MAIL_FROM=""
CONF_SMTP_STARTTLS=""
CONF_SMTP_SSL=""
CONF_RATELIMIT=""
CONF_APP_NAME=""
CONF_LOGO_RIGHT_TEXT=""
CONF_THEME_PRIMARY=""
CONF_FEATURE_CHANGES=""  # newline-separated KEY=VALUE pairs

# Track what changed for the summary
CHANGES=""  # newline-separated "KEY|display_value" pairs

# ---------------------------------------------------------------------------
# Trap — clean exit on Ctrl+C (no writes until confirmation)
# ---------------------------------------------------------------------------
cleanup() {
    echo ""
    printf '%s\n' "Setup cancelled. No changes were made."
    exit 1
}
trap cleanup SIGINT

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --non-interactive|-y) NON_INTERACTIVE=true ;;
            --no-color)           NO_COLOR=true ;;
            --no-start)           NO_START=true ;;
            --domain)
                shift
                [ $# -eq 0 ] && { echo "Error: --domain requires a value"; exit 1; }
                FLAG_DOMAIN="$1"
                ;;
            --admin-password)
                shift
                [ $# -eq 0 ] && { echo "Error: --admin-password requires a value"; exit 1; }
                FLAG_ADMIN_PASSWORD="$1"
                ;;
            --acme-email)
                shift
                [ $# -eq 0 ] && { echo "Error: --acme-email requires a value"; exit 1; }
                FLAG_ACME_EMAIL="$1"
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

usage() {
    cat <<'EOF'
Usage: bash setup.sh [options]

Options:
  --non-interactive, -y   Use defaults + generated secrets, no prompts
  --no-color              Disable ANSI colors
  --no-start              Skip "start services?" prompt
  --domain <value>        Pre-set domain
  --admin-password <val>  Pre-set admin password
  --acme-email <value>    Pre-set ACME email
  --help, -h              Show this help
EOF
}

# ---------------------------------------------------------------------------
# Color support
# ---------------------------------------------------------------------------
color_init() {
    BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" CYAN=""
    if [ "$NO_COLOR" = "false" ] && [ -t 1 ]; then
        ncolors=$(tput colors 2>/dev/null || echo 0)
        if [ "${ncolors:-0}" -ge 8 ]; then
            BOLD=$(tput bold)
            DIM=$(tput setaf 7)
            RESET=$(tput sgr0)
            RED=$(tput setaf 1)
            GREEN=$(tput setaf 2)
            YELLOW=$(tput setaf 3)
            BLUE=$(tput setaf 4)
            CYAN=$(tput setaf 6)
        fi
    fi
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Darwin*)  OS="macos" ;;
        Linux*)   OS="linux" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        *)        OS="unknown" ;;
    esac
}

# ---------------------------------------------------------------------------
# Print helpers
# ---------------------------------------------------------------------------
print_header() {
    echo ""
    echo "${BOLD}${BLUE}  ╔═══════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${BLUE}  ║       SecureHST Insights — Setup Wizard      ║${RESET}"
    echo "${BOLD}${BLUE}  ╚═══════════════════════════════════════════════╝${RESET}"
    echo ""
}

info()    { echo "${BLUE}[info]${RESET} $*"; }
success() { echo "${GREEN}[ok]${RESET} $*"; }
warn()    { echo "${YELLOW}[warn]${RESET} $*"; }
error()   { echo "${RED}[error]${RESET} $*"; }

section() {
    echo ""
    echo "${BOLD}── $1 ──${RESET}"
    echo ""
}

# ---------------------------------------------------------------------------
# Cross-platform sed -i
# ---------------------------------------------------------------------------
sed_inplace() {
    if [ "$OS" = "macos" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ---------------------------------------------------------------------------
# Secret generation
# ---------------------------------------------------------------------------
generate_secret() {
    local length="${1:-42}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$length" | tr -d '/+=\n' | head -c "$length"
    elif [ -r /dev/urandom ]; then
        head -c "$length" /dev/urandom | base64 | tr -d '/+=\n' | head -c "$length"
    else
        error "Cannot generate secret: no openssl or /dev/urandom"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# set_env_value — write a key=value to the .env file
#   Uses | as sed delimiter to avoid conflicts with / in paths and URLs
#   Handles: existing uncommented key, commented key, or missing key
# ---------------------------------------------------------------------------
set_env_value() {
    local key="$1"
    local value="$2"
    local file="${3:-$ENV_FILE}"

    # Escape special characters for sed replacement (using | delimiter)
    # We need to escape |, &, \, and newlines in the value
    local escaped_value
    escaped_value=$(printf '%s' "$value" | sed -e 's/[&|\]/\\&/g')

    # Check if the key exists uncommented
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed_inplace "s|^${key}=.*|${key}=${escaped_value}|" "$file"
    # Check if the key exists commented out
    elif grep -q "^#${key}=" "$file" 2>/dev/null; then
        sed_inplace "s|^#${key}=.*|${key}=${escaped_value}|" "$file"
    else
        # Append to end of file
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# ---------------------------------------------------------------------------
# get_env_value — read a value from .env (or .env.example as fallback)
# ---------------------------------------------------------------------------
get_env_value() {
    local key="$1"
    local val=""

    if [ -f "$ENV_FILE" ]; then
        val=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | sed "s/^${key}=//" | sed 's/^"//' | sed 's/"$//' | tr -d '\r')
    fi

    if [ -z "$val" ] && [ -f "$ENV_EXAMPLE" ]; then
        val=$(grep "^${key}=" "$ENV_EXAMPLE" 2>/dev/null | head -1 | sed "s/^${key}=//" | sed 's/^"//' | sed 's/"$//' | tr -d '\r')
    fi

    printf '%s' "$val"
}

# ---------------------------------------------------------------------------
# Input helpers
# ---------------------------------------------------------------------------
prompt_value() {
    local prompt_text="$1"
    local default="$2"
    local result=""

    if [ "$NON_INTERACTIVE" = "true" ]; then
        printf '%s' "$default"
        return
    fi

    if [ -n "$default" ]; then
        printf '%s [%s]: ' "$prompt_text" "$default" >&2
    else
        printf '%s: ' "$prompt_text" >&2
    fi

    if [ -t 0 ]; then
        read -r result
    else
        read -r result < /dev/tty || true
    fi
    result=$(printf '%s' "$result" | tr -d '\r')

    if [ -z "$result" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$result"
    fi
}

prompt_password() {
    local prompt_text="$1"
    local default="$2"
    local result=""
    local confirm=""

    if [ "$NON_INTERACTIVE" = "true" ]; then
        printf '%s' "$default"
        return
    fi

    while true; do
        if [ -n "$default" ]; then
            printf '%s [%s]: ' "$prompt_text" "********" >&2
        else
            printf '%s: ' "$prompt_text" >&2
        fi

        # Read password silently if terminal supports it
        if [ -t 0 ]; then
            read -rs result
            echo "" >&2
        else
            read -r result < /dev/tty || true
        fi

        result=$(printf '%s' "$result" | tr -d '\r')

        if [ -z "$result" ] && [ -n "$default" ]; then
            printf '%s' "$default"
            return
        fi

        if [ -z "$result" ]; then
            warn "Password cannot be empty."
            continue
        fi

        if ! validate_password "$result"; then
            warn "Password must be at least 8 characters."
            continue
        fi

        printf 'Confirm password: ' >&2
        if [ -t 0 ]; then
            read -rs confirm
            echo "" >&2
        else
            read -r confirm < /dev/tty || true
        fi

        confirm=$(printf '%s' "$confirm" | tr -d '\r')

        if [ "$result" = "$confirm" ]; then
            printf '%s' "$result"
            return
        else
            warn "Passwords do not match. Try again."
        fi
    done
}

prompt_yes_no() {
    local prompt_text="$1"
    local default="$2"  # "y" or "n"

    if [ "$NON_INTERACTIVE" = "true" ]; then
        [ "$default" = "y" ] && return 0 || return 1
    fi

    local hint
    if [ "$default" = "y" ]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        printf '%s [%s]: ' "$prompt_text" "$hint" >&2
        if [ -t 0 ]; then
            read -r answer
        else
            read -r answer < /dev/tty || true
        fi
        answer=$(printf '%s' "$answer" | tr -d '\r')

        case "$answer" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO])     return 1 ;;
            "")
                [ "$default" = "y" ] && return 0 || return 1
                ;;
            *)
                warn "Please enter y or n."
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
validate_domain() {
    local domain="$1"
    [ -z "$domain" ] && return 1
    # Allow localhost, IPs, and valid hostnames
    case "$domain" in
        localhost) return 0 ;;
        127.0.0.1) return 0 ;;
    esac
    # Basic hostname regex: alphanumeric, hyphens, dots
    if printf '%s' "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$'; then
        return 0
    fi
    return 1
}

validate_email() {
    local email="$1"
    [ -z "$email" ] && return 1
    if printf '%s' "$email" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
        return 0
    fi
    return 1
}

validate_password() {
    local pw="$1"
    [ ${#pw} -ge 8 ] && return 0
    return 1
}

# ---------------------------------------------------------------------------
# Domain classification (mirrors traefik/entrypoint.sh)
# ---------------------------------------------------------------------------
is_local_domain() {
    case "$1" in
        localhost|127.0.0.1|"") return 0 ;;
        *.localhost|*.local)    return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# record_change — track changes for the summary
# ---------------------------------------------------------------------------
record_change() {
    local key="$1"
    local display="$2"
    if [ -z "$CHANGES" ]; then
        CHANGES="${key}|${display}"
    else
        CHANGES="${CHANGES}
${key}|${display}"
    fi
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
check_prerequisites() {
    section "Checking prerequisites"

    local failed=false

    # Docker
    if command -v docker >/dev/null 2>&1; then
        success "Docker found"
        # Check if daemon is running
        if ! docker info >/dev/null 2>&1; then
            warn "Docker daemon is not running — start Docker Desktop or dockerd before running 'docker compose up'"
        fi
    else
        error "Docker is not installed (required)"
        failed=true
    fi

    # Docker Compose v2
    if docker compose version >/dev/null 2>&1; then
        success "Docker Compose v2 found"
    else
        error "Docker Compose v2 not found (need 'docker compose' — no hyphen)"
        failed=true
    fi

    # openssl (for secret generation)
    if command -v openssl >/dev/null 2>&1; then
        success "openssl found"
    elif [ -r /dev/urandom ]; then
        success "/dev/urandom available (fallback for secrets)"
    else
        error "No openssl or /dev/urandom — cannot generate secrets"
        failed=true
    fi

    # .env.example
    if [ -f "$ENV_EXAMPLE" ]; then
        success ".env.example found"
    else
        error ".env.example not found in ${SCRIPT_DIR}"
        failed=true
    fi

    # Port warnings
    local port_warning=false
    if command -v lsof >/dev/null 2>&1; then
        if lsof -iTCP:80 -sTCP:LISTEN >/dev/null 2>&1; then
            warn "Port 80 is in use — Traefik may fail to bind"
            port_warning=true
        fi
        if lsof -iTCP:443 -sTCP:LISTEN >/dev/null 2>&1; then
            warn "Port 443 is in use — Traefik may fail to bind"
            port_warning=true
        fi
    fi

    if [ "$failed" = "true" ]; then
        echo ""
        error "Prerequisites not met. Please fix the issues above and re-run."
        exit 1
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Load existing .env values as defaults
# ---------------------------------------------------------------------------
load_existing_env() {
    EXISTING_DOMAIN=$(get_env_value "INSIGHTS_DOMAIN")
    EXISTING_SECRET=$(get_env_value "INSIGHTS_SECRET_KEY")
    EXISTING_ADMIN_PW=$(get_env_value "ADMIN_PASSWORD")
    EXISTING_DB_PW=$(get_env_value "DATABASE_PASSWORD")
    EXISTING_ACME_EMAIL=$(get_env_value "ACME_EMAIL")
}

# ---------------------------------------------------------------------------
# Tier 1 — Essential Configuration
# ---------------------------------------------------------------------------
configure_essential() {
    section "Essential Configuration"

    # --- Domain ---
    local default_domain="${EXISTING_DOMAIN:-localhost}"
    if [ -n "$FLAG_DOMAIN" ]; then
        CONF_DOMAIN="$FLAG_DOMAIN"
    else
        while true; do
            CONF_DOMAIN=$(prompt_value "Domain (e.g. localhost, insights.example.com)" "$default_domain")
            if validate_domain "$CONF_DOMAIN"; then
                break
            fi
            warn "Invalid domain. Use a hostname like 'localhost' or 'insights.example.com'."
        done
    fi
    record_change "INSIGHTS_DOMAIN" "$CONF_DOMAIN"

    # --- ACME email (production only) ---
    if ! is_local_domain "$CONF_DOMAIN"; then
        local default_email="${EXISTING_ACME_EMAIL:-}"
        if [ -n "$FLAG_ACME_EMAIL" ]; then
            CONF_ACME_EMAIL="$FLAG_ACME_EMAIL"
        else
            while true; do
                CONF_ACME_EMAIL=$(prompt_value "ACME email for Let's Encrypt" "$default_email")
                if validate_email "$CONF_ACME_EMAIL"; then
                    break
                fi
                warn "Invalid email address."
            done
        fi
        record_change "ACME_EMAIL" "$CONF_ACME_EMAIL"
    fi

    # --- Secret key ---
    if [ -n "$EXISTING_SECRET" ] && [ "$EXISTING_SECRET" != "CHANGE_ME_TO_A_RANDOM_SECRET" ]; then
        CONF_SECRET_KEY="$EXISTING_SECRET"
        info "Keeping existing secret key"
    else
        CONF_SECRET_KEY=$(generate_secret 42)
        info "Generated new secret key"
    fi
    record_change "INSIGHTS_SECRET_KEY" "$(printf '%s' "$CONF_SECRET_KEY" | head -c 8)..."

    # --- Admin password ---
    if [ -n "$FLAG_ADMIN_PASSWORD" ]; then
        CONF_ADMIN_PASSWORD="$FLAG_ADMIN_PASSWORD"
    elif [ -n "$EXISTING_ADMIN_PW" ] && [ "$EXISTING_ADMIN_PW" != "admin" ] && validate_password "$EXISTING_ADMIN_PW"; then
        CONF_ADMIN_PASSWORD="$EXISTING_ADMIN_PW"
        info "Keeping existing admin password"
    else
        if [ "$NON_INTERACTIVE" = "true" ]; then
            CONF_ADMIN_PASSWORD=$(generate_secret 16)
            info "Generated admin password"
        else
            if [ "$EXISTING_ADMIN_PW" = "admin" ] || [ -z "$EXISTING_ADMIN_PW" ]; then
                warn "Admin password is set to the insecure default."
            fi
            CONF_ADMIN_PASSWORD=$(prompt_password "Admin password (min 8 chars)" "")
        fi
    fi
    record_change "ADMIN_PASSWORD" "********"

    # --- Database password ---
    if [ -n "$EXISTING_DB_PW" ] && [ "$EXISTING_DB_PW" != "superset" ]; then
        CONF_DB_PASSWORD="$EXISTING_DB_PW"
        info "Keeping existing database password"
    else
        CONF_DB_PASSWORD=$(generate_secret 24)
        info "Generated new database password"
    fi
    record_change "DATABASE_PASSWORD" "$(printf '%s' "$CONF_DB_PASSWORD" | head -c 4)..."
}

# ---------------------------------------------------------------------------
# Tier 2 — Production (opt-in)
# ---------------------------------------------------------------------------
configure_production() {
    if ! prompt_yes_no "Configure SMTP and rate limiting?" "n"; then
        return
    fi

    section "SMTP Configuration"

    local default_host default_port default_user default_pw default_from default_tls default_ssl
    default_host=$(get_env_value "INSIGHTS_SMTP_HOST")
    default_port=$(get_env_value "INSIGHTS_SMTP_PORT")
    default_user=$(get_env_value "INSIGHTS_SMTP_USER")
    default_pw=$(get_env_value "INSIGHTS_SMTP_PASSWORD")
    default_from=$(get_env_value "INSIGHTS_SMTP_MAIL_FROM")
    default_tls=$(get_env_value "INSIGHTS_SMTP_STARTTLS")
    default_ssl=$(get_env_value "INSIGHTS_SMTP_SSL")

    CONF_SMTP_HOST=$(prompt_value "SMTP host" "${default_host:-localhost}")
    record_change "INSIGHTS_SMTP_HOST" "$CONF_SMTP_HOST"

    CONF_SMTP_PORT=$(prompt_value "SMTP port" "${default_port:-587}")
    record_change "INSIGHTS_SMTP_PORT" "$CONF_SMTP_PORT"

    CONF_SMTP_USER=$(prompt_value "SMTP username" "${default_user:-}")
    record_change "INSIGHTS_SMTP_USER" "$CONF_SMTP_USER"

    CONF_SMTP_PASSWORD=$(prompt_value "SMTP password" "${default_pw:-}")
    record_change "INSIGHTS_SMTP_PASSWORD" "********"

    CONF_SMTP_MAIL_FROM=$(prompt_value "From address" "${default_from:-insights@securehst.com}")
    record_change "INSIGHTS_SMTP_MAIL_FROM" "$CONF_SMTP_MAIL_FROM"

    if prompt_yes_no "Use STARTTLS?" "${default_tls:-y}"; then
        CONF_SMTP_STARTTLS="true"
    else
        CONF_SMTP_STARTTLS="false"
    fi
    record_change "INSIGHTS_SMTP_STARTTLS" "$CONF_SMTP_STARTTLS"

    if prompt_yes_no "Use SSL?" "${default_ssl:-n}"; then
        CONF_SMTP_SSL="true"
    else
        CONF_SMTP_SSL="false"
    fi
    record_change "INSIGHTS_SMTP_SSL" "$CONF_SMTP_SSL"

    echo ""
    if prompt_yes_no "Enable rate limiting?" "n"; then
        CONF_RATELIMIT="true"
        record_change "INSIGHTS_RATELIMIT_ENABLED" "true"
    fi
}

# ---------------------------------------------------------------------------
# Tier 3 — Customization (opt-in)
# ---------------------------------------------------------------------------
configure_customization() {
    if ! prompt_yes_no "Customize branding, theme, and features?" "n"; then
        return
    fi

    # --- Branding ---
    if prompt_yes_no "  Configure branding (app name, logo text)?" "n"; then
        section "Branding"
        local default_name
        default_name=$(get_env_value "INSIGHTS_APP_NAME")
        CONF_APP_NAME=$(prompt_value "Application name" "${default_name:-Insights}")
        record_change "INSIGHTS_APP_NAME" "$CONF_APP_NAME"

        local default_right_text
        default_right_text=$(get_env_value "INSIGHTS_LOGO_RIGHT_TEXT")
        CONF_LOGO_RIGHT_TEXT=$(prompt_value "Text beside logo (leave empty to skip)" "${default_right_text:-}")
        if [ -n "$CONF_LOGO_RIGHT_TEXT" ]; then
            record_change "INSIGHTS_LOGO_RIGHT_TEXT" "$CONF_LOGO_RIGHT_TEXT"
        fi
    fi

    # --- Theme ---
    if prompt_yes_no "  Configure theme (primary color)?" "n"; then
        section "Theme"
        local default_primary
        default_primary=$(get_env_value "INSIGHTS_THEME_COLOR_PRIMARY")
        CONF_THEME_PRIMARY=$(prompt_value "Primary brand color (hex, e.g. #1a73e8)" "${default_primary:-}")
        if [ -n "$CONF_THEME_PRIMARY" ]; then
            record_change "INSIGHTS_THEME_COLOR_PRIMARY" "$CONF_THEME_PRIMARY"
        fi
    fi

    # --- Feature flags ---
    if prompt_yes_no "  Configure feature flags?" "n"; then
        section "Feature Flags"
        local features
        features="INSIGHTS_FEATURE_TAGGING|Tag system for organizing|false
INSIGHTS_FEATURE_EMBEDDED|Embedded dashboards (iframe)|false
INSIGHTS_FEATURE_SSH_TUNNELING|SSH tunnels for DB connections|false
INSIGHTS_FEATURE_TEMPLATE_PROCESSING|Jinja templates in SQL Lab|false"

        local OLD_IFS="$IFS"
        IFS="
"
        for line in $features; do
            IFS="$OLD_IFS"
            local feat_key feat_desc feat_default
            feat_key=$(printf '%s' "$line" | cut -d'|' -f1)
            feat_desc=$(printf '%s' "$line" | cut -d'|' -f2)
            feat_default=$(printf '%s' "$line" | cut -d'|' -f3)

            local current
            current=$(get_env_value "$feat_key")
            current="${current:-$feat_default}"

            local yn_default="n"
            [ "$current" = "true" ] && yn_default="y"

            if prompt_yes_no "  Enable ${feat_desc}?" "$yn_default"; then
                if [ -z "$CONF_FEATURE_CHANGES" ]; then
                    CONF_FEATURE_CHANGES="${feat_key}=true"
                else
                    CONF_FEATURE_CHANGES="${CONF_FEATURE_CHANGES}
${feat_key}=true"
                fi
                record_change "$feat_key" "true"
            else
                if [ -z "$CONF_FEATURE_CHANGES" ]; then
                    CONF_FEATURE_CHANGES="${feat_key}=false"
                else
                    CONF_FEATURE_CHANGES="${CONF_FEATURE_CHANGES}
${feat_key}=false"
                fi
                record_change "$feat_key" "false"
            fi
            IFS="
"
        done
        IFS="$OLD_IFS"
    fi

    # --- Navigation links ---
    if prompt_yes_no "  Configure navigation links?" "n"; then
        section "Navigation Links"
        local val
        val=$(prompt_value "Documentation URL (leave empty to skip)" "$(get_env_value "INSIGHTS_DOCUMENTATION_URL")")
        if [ -n "$val" ]; then
            if [ -z "$CONF_FEATURE_CHANGES" ]; then
                CONF_FEATURE_CHANGES="INSIGHTS_DOCUMENTATION_URL=${val}"
            else
                CONF_FEATURE_CHANGES="${CONF_FEATURE_CHANGES}
INSIGHTS_DOCUMENTATION_URL=${val}"
            fi
            record_change "INSIGHTS_DOCUMENTATION_URL" "$val"
        fi

        val=$(prompt_value "Bug report URL (leave empty to skip)" "$(get_env_value "INSIGHTS_BUG_REPORT_URL")")
        if [ -n "$val" ]; then
            CONF_FEATURE_CHANGES="${CONF_FEATURE_CHANGES}
INSIGHTS_BUG_REPORT_URL=${val}"
            record_change "INSIGHTS_BUG_REPORT_URL" "$val"
        fi
    fi

    # --- Integrations ---
    if prompt_yes_no "  Configure integrations (Mapbox, Slack)?" "n"; then
        section "Integrations"
        local val
        val=$(prompt_value "Mapbox API key (leave empty to skip)" "$(get_env_value "INSIGHTS_MAPBOX_API_KEY")")
        if [ -n "$val" ]; then
            CONF_FEATURE_CHANGES="${CONF_FEATURE_CHANGES}
INSIGHTS_MAPBOX_API_KEY=${val}"
            record_change "INSIGHTS_MAPBOX_API_KEY" "$val"
        fi

        val=$(prompt_value "Slack API token (leave empty to skip)" "$(get_env_value "INSIGHTS_SLACK_API_TOKEN")")
        if [ -n "$val" ]; then
            CONF_FEATURE_CHANGES="${CONF_FEATURE_CHANGES}
INSIGHTS_SLACK_API_TOKEN=${val}"
            record_change "INSIGHTS_SLACK_API_TOKEN" "********"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    section "Configuration Summary"

    if [ -z "$CHANGES" ]; then
        info "No changes to apply."
        exit 0
    fi

    printf '  %-40s %s\n' "${BOLD}Variable${RESET}" "${BOLD}Value${RESET}"
    printf '  %-40s %s\n' "────────────────────────────────────────" "──────────────────────"

    local OLD_IFS="$IFS"
    IFS="
"
    for line in $CHANGES; do
        IFS="$OLD_IFS"
        local key display
        key=$(printf '%s' "$line" | cut -d'|' -f1)
        display=$(printf '%s' "$line" | cut -d'|' -f2-)
        printf '  %-40s %s\n' "$key" "$display"
        IFS="
"
    done
    IFS="$OLD_IFS"

    echo ""
}

# ---------------------------------------------------------------------------
# Apply configuration
# ---------------------------------------------------------------------------
apply_configuration() {
    # Backup existing .env
    if [ -f "$ENV_FILE" ]; then
        local backup="${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$ENV_FILE" "$backup"
        info "Backed up existing .env to $(basename "$backup")"
    fi

    # Initialize .env from .env.example if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        info "Created .env from .env.example"
    fi

    # Strip any Windows line endings
    if grep -q $'\r' "$ENV_FILE" 2>/dev/null; then
        sed_inplace 's/\r$//' "$ENV_FILE"
    fi

    # Write essential values
    set_env_value "INSIGHTS_DOMAIN" "$CONF_DOMAIN"
    set_env_value "INSIGHTS_SECRET_KEY" "$CONF_SECRET_KEY"
    set_env_value "ADMIN_PASSWORD" "$CONF_ADMIN_PASSWORD"
    set_env_value "DATABASE_PASSWORD" "$CONF_DB_PASSWORD"

    if [ -n "$CONF_ACME_EMAIL" ]; then
        set_env_value "ACME_EMAIL" "$CONF_ACME_EMAIL"
    fi

    # SMTP
    [ -n "$CONF_SMTP_HOST" ]     && set_env_value "INSIGHTS_SMTP_HOST" "$CONF_SMTP_HOST"
    [ -n "$CONF_SMTP_PORT" ]     && set_env_value "INSIGHTS_SMTP_PORT" "$CONF_SMTP_PORT"
    [ -n "$CONF_SMTP_USER" ]     && set_env_value "INSIGHTS_SMTP_USER" "$CONF_SMTP_USER"
    [ -n "$CONF_SMTP_PASSWORD" ] && set_env_value "INSIGHTS_SMTP_PASSWORD" "$CONF_SMTP_PASSWORD"
    [ -n "$CONF_SMTP_MAIL_FROM" ] && set_env_value "INSIGHTS_SMTP_MAIL_FROM" "$CONF_SMTP_MAIL_FROM"
    [ -n "$CONF_SMTP_STARTTLS" ] && set_env_value "INSIGHTS_SMTP_STARTTLS" "$CONF_SMTP_STARTTLS"
    [ -n "$CONF_SMTP_SSL" ]      && set_env_value "INSIGHTS_SMTP_SSL" "$CONF_SMTP_SSL"

    # Rate limiting
    [ -n "$CONF_RATELIMIT" ] && set_env_value "INSIGHTS_RATELIMIT_ENABLED" "$CONF_RATELIMIT"

    # Branding
    [ -n "$CONF_APP_NAME" ]        && set_env_value "INSIGHTS_APP_NAME" "$CONF_APP_NAME"
    [ -n "$CONF_LOGO_RIGHT_TEXT" ] && set_env_value "INSIGHTS_LOGO_RIGHT_TEXT" "$CONF_LOGO_RIGHT_TEXT"

    # Theme
    [ -n "$CONF_THEME_PRIMARY" ] && set_env_value "INSIGHTS_THEME_COLOR_PRIMARY" "$CONF_THEME_PRIMARY"

    # Feature changes and other key=value pairs
    if [ -n "$CONF_FEATURE_CHANGES" ]; then
        local OLD_IFS="$IFS"
        IFS="
"
        for line in $CONF_FEATURE_CHANGES; do
            IFS="$OLD_IFS"
            local fkey fval
            fkey=$(printf '%s' "$line" | cut -d'=' -f1)
            fval=$(printf '%s' "$line" | cut -d'=' -f2-)
            set_env_value "$fkey" "$fval"
            IFS="
"
        done
        IFS="$OLD_IFS"
    fi

    success "Configuration written to .env"
}

# ---------------------------------------------------------------------------
# Post-setup
# ---------------------------------------------------------------------------
post_setup() {
    echo ""

    local url
    if is_local_domain "$CONF_DOMAIN"; then
        url="http://localhost"
    else
        url="https://${CONF_DOMAIN}"
    fi

    if [ "$NO_START" = "false" ]; then
        if prompt_yes_no "Start services now? (docker compose up -d)" "y"; then
            echo ""
            info "Starting services..."
            (cd "$SCRIPT_DIR" && docker compose up -d)
            echo ""
            success "Services started!"
            echo ""
            echo "  ${BOLD}Next steps:${RESET}"
            echo "    1. Watch initialization:  ${CYAN}docker compose logs -f superset-init${RESET}"
            echo "    2. Open:                  ${CYAN}${url}${RESET}"
            echo "    3. Login:                 ${CYAN}admin${RESET} / your chosen password"
            if ! is_local_domain "$CONF_DOMAIN"; then
                echo "    4. Ensure DNS points to this server:  ${CYAN}dig +short ${CONF_DOMAIN}${RESET}"
            fi
            echo ""
            return
        fi
    fi

    echo "  ${BOLD}Next steps:${RESET}"
    echo "    1. Start services:        ${CYAN}docker compose up -d${RESET}"
    echo "    2. Watch initialization:  ${CYAN}docker compose logs -f superset-init${RESET}"
    echo "    3. Open:                  ${CYAN}${url}${RESET}"
    echo "    4. Login:                 ${CYAN}admin${RESET} / your chosen password"
    if ! is_local_domain "$CONF_DOMAIN"; then
        echo "    5. Ensure DNS points to this server:  ${CYAN}dig +short ${CONF_DOMAIN}${RESET}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    color_init
    detect_os
    print_header
    check_prerequisites
    load_existing_env
    configure_essential

    if [ "$NON_INTERACTIVE" = "false" ]; then
        echo ""
        configure_production
        echo ""
        configure_customization
    fi

    print_summary

    if [ "$NON_INTERACTIVE" = "false" ]; then
        if ! prompt_yes_no "Apply this configuration?" "y"; then
            echo ""
            info "Setup cancelled. No changes were made."
            exit 0
        fi
    fi

    apply_configuration
    post_setup
}

main "$@"
