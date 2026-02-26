#!/usr/bin/env bash
# =============================================================================
# Test Suite for setup.sh
# =============================================================================
# Self-contained bash test harness. Creates temp directories, runs setup.sh
# with various flags, and asserts expected values in the resulting .env.
#
# Usage: bash tests/test_setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_SH="${PROJECT_DIR}/setup.sh"
ENV_EXAMPLE="${PROJECT_DIR}/.env.example"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=""

# Temp directory for test artifacts
TEST_TMP="${SCRIPT_DIR}/tmp"

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
setup_test_dir() {
    local name="$1"
    local dir="${TEST_TMP}/${name}"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp "$ENV_EXAMPLE" "$dir/.env.example"
    printf '%s' "$dir"
}

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  \033[31m✗\033[0m %s\n' "$description"
        printf '    expected: "%s"\n' "$expected"
        printf '    actual:   "%s"\n' "$actual"
        FAIL_MESSAGES="${FAIL_MESSAGES}  FAIL: ${description}\n"
    fi
}

assert_not_eq() {
    local description="$1"
    local unexpected="$2"
    local actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$unexpected" != "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  \033[31m✗\033[0m %s\n' "$description"
        printf '    should NOT be: "%s"\n' "$unexpected"
        FAIL_MESSAGES="${FAIL_MESSAGES}  FAIL: ${description}\n"
    fi
}

assert_match() {
    local description="$1"
    local pattern="$2"
    local actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$actual" | grep -qE "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  \033[31m✗\033[0m %s\n' "$description"
        printf '    pattern: "%s"\n' "$pattern"
        printf '    actual:  "%s"\n' "$actual"
        FAIL_MESSAGES="${FAIL_MESSAGES}  FAIL: ${description}\n"
    fi
}

assert_file_exists() {
    local description="$1"
    local filepath="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$filepath" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[32m✓\033[0m %s\n' "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  \033[31m✗\033[0m %s\n' "$description"
        printf '    file not found: "%s"\n' "$filepath"
        FAIL_MESSAGES="${FAIL_MESSAGES}  FAIL: ${description}\n"
    fi
}

# Read a value from an env file
read_env() {
    local key="$1"
    local file="$2"
    grep "^${key}=" "$file" 2>/dev/null | head -1 | sed "s/^${key}=//" | tr -d '\r'
}

# ---------------------------------------------------------------------------
# Source setup.sh functions for unit testing
# We need to extract functions without running main()
# ---------------------------------------------------------------------------
FUNCTIONS_SOURCED=false
source_setup_functions() {
    if [ "$FUNCTIONS_SOURCED" = "true" ]; then
        return
    fi
    # Extract everything except the final main "$@" call and top-level variable
    # assignments that set paths. We'll define those ourselves.
    eval "$(sed -e 's/^main "\$@"$//' \
                -e 's/^SCRIPT_DIR=.*$//' \
                -e 's/^ENV_EXAMPLE=.*$//' \
                -e 's/^ENV_FILE=.*$//' \
                "$SETUP_SH")"
    # Restore our own paths
    SCRIPT_DIR="$PROJECT_DIR"
    ENV_EXAMPLE="${PROJECT_DIR}/.env.example"
    ENV_FILE="${PROJECT_DIR}/.env"
    # Set defaults needed by sourced functions
    NO_COLOR=true
    NON_INTERACTIVE=true
    color_init
    detect_os
    FUNCTIONS_SOURCED=true
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_set_env_value_uncommented() {
    printf '\n\033[1m[test_set_env_value_uncommented]\033[0m\n'
    local dir
    dir=$(setup_test_dir "set_env_uncommented")
    cp "$ENV_EXAMPLE" "$dir/.env"
    local file="$dir/.env"

    source_setup_functions
    ENV_FILE="$file"

    set_env_value "INSIGHTS_SECRET_KEY" "my_new_secret" "$file"
    local val
    val=$(read_env "INSIGHTS_SECRET_KEY" "$file")
    assert_eq "Updates uncommented key" "my_new_secret" "$val"
}

test_set_env_value_commented() {
    printf '\n\033[1m[test_set_env_value_commented]\033[0m\n'
    local dir
    dir=$(setup_test_dir "set_env_commented")
    cp "$ENV_EXAMPLE" "$dir/.env"
    local file="$dir/.env"

    source_setup_functions
    ENV_FILE="$file"

    set_env_value "ACME_EMAIL" "test@example.com" "$file"
    local val
    val=$(read_env "ACME_EMAIL" "$file")
    assert_eq "Uncomments and sets commented key" "test@example.com" "$val"
}

test_set_env_value_missing() {
    printf '\n\033[1m[test_set_env_value_missing]\033[0m\n'
    local dir
    dir=$(setup_test_dir "set_env_missing")
    cp "$ENV_EXAMPLE" "$dir/.env"
    local file="$dir/.env"

    source_setup_functions
    ENV_FILE="$file"

    set_env_value "BRAND_NEW_KEY" "brand_new_value" "$file"
    local val
    val=$(read_env "BRAND_NEW_KEY" "$file")
    assert_eq "Appends missing key" "brand_new_value" "$val"
}

test_set_env_value_special_chars() {
    printf '\n\033[1m[test_set_env_value_special_chars]\033[0m\n'
    local dir
    dir=$(setup_test_dir "set_env_special")
    cp "$ENV_EXAMPLE" "$dir/.env"
    local file="$dir/.env"

    source_setup_functions
    ENV_FILE="$file"

    # Test with hex color (contains #)
    set_env_value "INSIGHTS_THEME_COLOR_PRIMARY" "#1a73e8" "$file"
    local val
    val=$(read_env "INSIGHTS_THEME_COLOR_PRIMARY" "$file")
    assert_eq "Handles hex color value" "#1a73e8" "$val"

    # Test with URL (contains / and :)
    set_env_value "INSIGHTS_DOCUMENTATION_URL" "https://docs.example.com/help" "$file"
    val=$(read_env "INSIGHTS_DOCUMENTATION_URL" "$file")
    assert_eq "Handles URL value" "https://docs.example.com/help" "$val"

    # Test with value containing =
    set_env_value "BRAND_NEW_KEY" "key=value=pair" "$file"
    val=$(grep "^BRAND_NEW_KEY=" "$file" | head -1 | sed 's/^BRAND_NEW_KEY=//' | tr -d '\r')
    assert_eq "Handles value with equals signs" "key=value=pair" "$val"
}

test_validate_domain() {
    printf '\n\033[1m[test_validate_domain]\033[0m\n'
    source_setup_functions

    validate_domain "localhost" && assert_eq "localhost is valid" "0" "0" || assert_eq "localhost is valid" "0" "1"
    validate_domain "127.0.0.1" && assert_eq "127.0.0.1 is valid" "0" "0" || assert_eq "127.0.0.1 is valid" "0" "1"
    validate_domain "insights.example.com" && assert_eq "FQDN is valid" "0" "0" || assert_eq "FQDN is valid" "0" "1"
    validate_domain "my-app.local" && assert_eq "*.local is valid" "0" "0" || assert_eq "*.local is valid" "0" "1"
    validate_domain "" && assert_eq "empty is invalid" "0" "1" || assert_eq "empty is invalid" "0" "0"
}

test_validate_email() {
    printf '\n\033[1m[test_validate_email]\033[0m\n'
    source_setup_functions

    validate_email "user@example.com" && assert_eq "valid email accepted" "0" "0" || assert_eq "valid email accepted" "0" "1"
    validate_email "admin@sub.domain.co" && assert_eq "subdomain email accepted" "0" "0" || assert_eq "subdomain email accepted" "0" "1"
    validate_email "" && assert_eq "empty email rejected" "0" "1" || assert_eq "empty email rejected" "0" "0"
    validate_email "notanemail" && assert_eq "no-@ rejected" "0" "1" || assert_eq "no-@ rejected" "0" "0"
}

test_validate_password() {
    printf '\n\033[1m[test_validate_password]\033[0m\n'
    source_setup_functions

    validate_password "12345678" && assert_eq "8 chars accepted" "0" "0" || assert_eq "8 chars accepted" "0" "1"
    validate_password "longpassword123" && assert_eq "long password accepted" "0" "0" || assert_eq "long password accepted" "0" "1"
    validate_password "short" && assert_eq "5 chars rejected" "0" "1" || assert_eq "5 chars rejected" "0" "0"
    validate_password "" && assert_eq "empty rejected" "0" "1" || assert_eq "empty rejected" "0" "0"
}

test_is_local_domain() {
    printf '\n\033[1m[test_is_local_domain]\033[0m\n'
    source_setup_functions

    is_local_domain "localhost" && assert_eq "localhost is local" "0" "0" || assert_eq "localhost is local" "0" "1"
    is_local_domain "127.0.0.1" && assert_eq "127.0.0.1 is local" "0" "0" || assert_eq "127.0.0.1 is local" "0" "1"
    is_local_domain "app.localhost" && assert_eq "*.localhost is local" "0" "0" || assert_eq "*.localhost is local" "0" "1"
    is_local_domain "dev.local" && assert_eq "*.local is local" "0" "0" || assert_eq "*.local is local" "0" "1"
    is_local_domain "" && assert_eq "empty is local" "0" "0" || assert_eq "empty is local" "0" "1"
    is_local_domain "insights.example.com" && assert_eq "FQDN is not local" "0" "1" || assert_eq "FQDN is not local" "0" "0"
}

test_generate_secret() {
    printf '\n\033[1m[test_generate_secret]\033[0m\n'
    source_setup_functions

    local secret
    secret=$(generate_secret 42)
    assert_not_eq "Secret is not empty" "" "$secret"
    # Should be alphanumeric + base64 chars (no /, +, =)
    if printf '%s' "$secret" | grep -qE '[/+=]'; then
        assert_eq "Secret has no /, +, = chars" "clean" "has_special"
    else
        assert_eq "Secret has no /, +, = chars" "clean" "clean"
    fi
    local len=${#secret}
    if [ "$len" -ge 20 ]; then
        assert_eq "Secret is long enough" "true" "true"
    else
        assert_eq "Secret is long enough (got $len)" "true" "false"
    fi
}

test_non_interactive_generates_secrets() {
    printf '\n\033[1m[test_non_interactive_generates_secrets]\033[0m\n'
    local dir
    dir=$(setup_test_dir "non_interactive")

    # Run setup.sh --non-interactive with a copy of .env.example as our working dir
    # We need to trick setup.sh into using our temp dir
    cp "$SETUP_SH" "$dir/setup.sh"
    chmod +x "$dir/setup.sh"

    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color 2>&1) || true

    local file="$dir/.env"
    assert_file_exists ".env was created" "$file"

    local secret
    secret=$(read_env "INSIGHTS_SECRET_KEY" "$file")
    assert_not_eq "Secret key is not placeholder" "CHANGE_ME_TO_A_RANDOM_SECRET" "$secret"
    assert_not_eq "Secret key is not empty" "" "$secret"

    local admin_pw
    admin_pw=$(read_env "ADMIN_PASSWORD" "$file")
    assert_not_eq "Admin password is not 'admin'" "admin" "$admin_pw"
    assert_not_eq "Admin password is not empty" "" "$admin_pw"

    local db_pw
    db_pw=$(read_env "DATABASE_PASSWORD" "$file")
    assert_not_eq "DB password is not 'superset'" "superset" "$db_pw"
    assert_not_eq "DB password is not empty" "" "$db_pw"

    local domain
    domain=$(read_env "INSIGHTS_DOMAIN" "$file")
    assert_eq "Domain defaults to localhost" "localhost" "$domain"
}

test_non_interactive_with_domain_flag() {
    printf '\n\033[1m[test_non_interactive_with_domain_flag]\033[0m\n'
    local dir
    dir=$(setup_test_dir "domain_flag")
    cp "$SETUP_SH" "$dir/setup.sh"
    chmod +x "$dir/setup.sh"

    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color --domain insights.example.com --acme-email admin@example.com 2>&1) || true

    local file="$dir/.env"
    assert_file_exists ".env was created" "$file"

    local domain
    domain=$(read_env "INSIGHTS_DOMAIN" "$file")
    assert_eq "Domain flag sets domain" "insights.example.com" "$domain"

    local email
    email=$(read_env "ACME_EMAIL" "$file")
    assert_eq "ACME email flag sets email" "admin@example.com" "$email"
}

test_idempotent_preserves_secrets() {
    printf '\n\033[1m[test_idempotent_preserves_secrets]\033[0m\n'
    local dir
    dir=$(setup_test_dir "idempotent")
    cp "$SETUP_SH" "$dir/setup.sh"
    chmod +x "$dir/setup.sh"

    # First run
    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color 2>&1) || true

    local file="$dir/.env"
    local first_secret first_db_pw
    first_secret=$(read_env "INSIGHTS_SECRET_KEY" "$file")
    first_db_pw=$(read_env "DATABASE_PASSWORD" "$file")

    # Second run
    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color 2>&1) || true

    local second_secret second_db_pw
    second_secret=$(read_env "INSIGHTS_SECRET_KEY" "$file")
    second_db_pw=$(read_env "DATABASE_PASSWORD" "$file")

    assert_eq "Secret key preserved on re-run" "$first_secret" "$second_secret"
    assert_eq "DB password preserved on re-run" "$first_db_pw" "$second_db_pw"
}

test_backup_created_on_rerun() {
    printf '\n\033[1m[test_backup_created_on_rerun]\033[0m\n'
    local dir
    dir=$(setup_test_dir "backup")
    cp "$SETUP_SH" "$dir/setup.sh"
    chmod +x "$dir/setup.sh"

    # First run
    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color 2>&1) || true

    # Second run (should create backup)
    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color 2>&1) || true

    local backup_count
    backup_count=$(find "$dir" -name ".env.backup.*" 2>/dev/null | wc -l | tr -d ' ')
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$backup_count" -ge 1 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[32m✓\033[0m Backup created on re-run (%s found)\n' "$backup_count"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  \033[31m✗\033[0m Backup created on re-run (0 found)\n'
        FAIL_MESSAGES="${FAIL_MESSAGES}  FAIL: Backup created on re-run\n"
    fi
}

test_admin_password_flag() {
    printf '\n\033[1m[test_admin_password_flag]\033[0m\n'
    local dir
    dir=$(setup_test_dir "admin_pw_flag")
    cp "$SETUP_SH" "$dir/setup.sh"
    chmod +x "$dir/setup.sh"

    (cd "$dir" && bash setup.sh --non-interactive --no-start --no-color --admin-password "MySecureP@ss123" 2>&1) || true

    local file="$dir/.env"
    local pw
    pw=$(read_env "ADMIN_PASSWORD" "$file")
    assert_eq "Admin password flag sets password" "MySecureP@ss123" "$pw"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
main() {
    printf '\033[1m\nSecureHST Insights — Setup Wizard Tests\n\033[0m\n'
    printf '========================================\n'

    # Clean up temp dir
    rm -rf "$TEST_TMP"
    mkdir -p "$TEST_TMP"

    # Unit tests (source functions directly)
    test_set_env_value_uncommented
    test_set_env_value_commented
    test_set_env_value_missing
    test_set_env_value_special_chars
    test_validate_domain
    test_validate_email
    test_validate_password
    test_is_local_domain
    test_generate_secret

    # Integration tests (run setup.sh as subprocess)
    test_non_interactive_generates_secrets
    test_non_interactive_with_domain_flag
    test_idempotent_preserves_secrets
    test_backup_created_on_rerun
    test_admin_password_flag

    # Summary
    printf '\n========================================\n'
    printf '\033[1mResults: %d tests, %d passed, %d failed\033[0m\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf '\n\033[31mFailures:\033[0m\n'
        printf '%b' "$FAIL_MESSAGES"
        printf '\n'

        # Clean up
        rm -rf "$TEST_TMP"
        exit 1
    fi

    printf '\n\033[32mAll tests passed!\033[0m\n\n'

    # Clean up
    rm -rf "$TEST_TMP"
    exit 0
}

main "$@"
