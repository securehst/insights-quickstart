#!/usr/bin/env bash
# =============================================================================
# SecureHST Insights — One-Command Installer
# =============================================================================
# Downloads and bootstraps SecureHST Insights on Linux and macOS.
# Checks for prerequisites (git, Docker, Docker Compose), offers to install
# any that are missing, clones the repository, and launches the setup wizard.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/securehst/insights-quickstart/main/install.sh | bash
#
# Or download and run directly:
#   bash install.sh [--install-dir <path>]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
REPO_URL="https://github.com/securehst/insights-quickstart.git"
DEFAULT_INSTALL_DIR="./insights"
INSTALL_DIR=""

# ---------------------------------------------------------------------------
# Color support
# ---------------------------------------------------------------------------
BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" CYAN=""
color_init() {
    # When piped from curl, stdout is not a tty but /dev/tty may be available
    if [ -t 1 ] || [ -t 2 ]; then
        local ncolors
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

info()    { echo "${BLUE}[info]${RESET} $*"; }
success() { echo "${GREEN}  ✓${RESET} $*"; }
warn()    { echo "${YELLOW}[warn]${RESET} $*"; }
error()   { echo "${RED}[error]${RESET} $*"; }

# ---------------------------------------------------------------------------
# OS / distro detection
# ---------------------------------------------------------------------------
OS=""
DISTRO=""
PKG_MANAGER=""

detect_os() {
    case "$(uname -s)" in
        Darwin*)  OS="macos" ;;
        Linux*)   OS="linux" ;;
        *)        OS="unknown" ;;
    esac

    if [ "$OS" = "linux" ] && [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${ID:-unknown}"

        case "$DISTRO" in
            ubuntu|debian|raspbian|pop|linuxmint|elementary|zorin)
                PKG_MANAGER="apt" ;;
            fedora)
                PKG_MANAGER="dnf" ;;
            centos|rhel|rocky|alma|ol)
                if command -v dnf >/dev/null 2>&1; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi ;;
            arch|manjaro|endeavouros)
                PKG_MANAGER="pacman" ;;
            opensuse*|sles)
                PKG_MANAGER="zypper" ;;
            alpine)
                PKG_MANAGER="apk" ;;
            *)
                PKG_MANAGER="" ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# Interactive prompt helper (works when piped from curl)
# ---------------------------------------------------------------------------
ask() {
    local prompt="$1"
    local default="$2"
    local answer

    local hint
    if [ "$default" = "y" ]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    printf '%s [%s]: ' "$prompt" "$hint" >&2
    if [ -t 0 ]; then
        read -r answer
    else
        # stdin is a pipe (curl | bash), read from tty
        read -r answer < /dev/tty || true
    fi

    answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
    case "$answer" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        "")
            [ "$default" = "y" ] && return 0 || return 1 ;;
        *)
            [ "$default" = "y" ] && return 0 || return 1 ;;
    esac
}

ask_value() {
    local prompt="$1"
    local default="$2"
    local answer

    if [ -n "$default" ]; then
        printf '%s [%s]: ' "$prompt" "$default" >&2
    else
        printf '%s: ' "$prompt" >&2
    fi

    if [ -t 0 ]; then
        read -r answer
    else
        read -r answer < /dev/tty || true
    fi

    answer=$(printf '%s' "$answer" | tr -d '\r')
    if [ -z "$answer" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$answer"
    fi
}

# ---------------------------------------------------------------------------
# Welcome banner
# ---------------------------------------------------------------------------
print_banner() {
    echo ""
    echo "${BOLD}${BLUE}  ╔═══════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${BLUE}  ║     SecureHST Insights — Quick Installer     ║${RESET}"
    echo "${BOLD}${BLUE}  ╚═══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo "  This installer will check for prerequisites, clone the"
    echo "  repository, and launch the interactive setup wizard."
    echo ""
}

# ---------------------------------------------------------------------------
# Prerequisite: git
# ---------------------------------------------------------------------------
check_git() {
    if command -v git >/dev/null 2>&1; then
        success "git found ($(git --version | head -1))"
        return 0
    fi

    warn "git is not installed."

    if [ "$OS" = "macos" ]; then
        if ask "  Install git via Xcode Command Line Tools?" "y"; then
            info "Running xcode-select --install (a dialog may appear)..."
            xcode-select --install 2>/dev/null || true

            # Poll until git becomes available (Xcode installer is async)
            info "Waiting for installation to complete..."
            local waited=0
            while ! command -v git >/dev/null 2>&1; do
                sleep 5
                waited=$((waited + 5))
                if [ "$waited" -ge 300 ]; then
                    error "Timed out waiting for git. Please install Xcode Command Line Tools and re-run."
                    exit 1
                fi
            done
            success "git installed"
            return 0
        fi
    elif [ "$OS" = "linux" ] && [ -n "$PKG_MANAGER" ]; then
        if ask "  Install git via $PKG_MANAGER?" "y"; then
            install_package "git"
            if command -v git >/dev/null 2>&1; then
                success "git installed"
                return 0
            fi
        fi
    fi

    error "git is required. Please install it and re-run."
    echo "  macOS:  xcode-select --install"
    echo "  Ubuntu: sudo apt install git"
    echo "  Fedora: sudo dnf install git"
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: Docker
# ---------------------------------------------------------------------------
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        success "Docker found ($(docker --version | head -1))"
        return 0
    fi

    warn "Docker is not installed."

    if [ "$OS" = "macos" ]; then
        if command -v brew >/dev/null 2>&1; then
            if ask "  Install Docker Desktop via Homebrew?" "y"; then
                info "Running: brew install --cask docker"
                brew install --cask docker
                if command -v docker >/dev/null 2>&1; then
                    success "Docker installed"
                    return 0
                fi
                # Docker Desktop may need to be opened first
                info "Opening Docker Desktop..."
                open -a Docker 2>/dev/null || true
                wait_for_command "docker" 60
                success "Docker installed"
                return 0
            fi
        fi

        error "Docker Desktop is required on macOS."
        echo "  Install from: https://www.docker.com/products/docker-desktop/"
        exit 1
    fi

    if [ "$OS" = "linux" ]; then
        if ask "  Install Docker via get.docker.com convenience script?" "y"; then
            info "Downloading and running Docker install script..."
            curl -fsSL https://get.docker.com | sh

            # Add current user to docker group
            if [ "$(id -u)" -ne 0 ] && ! groups | grep -q docker; then
                info "Adding $USER to the docker group..."
                sudo usermod -aG docker "$USER" 2>/dev/null || true
                warn "You may need to log out and back in for group changes to take effect."
                warn "For now, Docker commands may require sudo."
            fi

            if command -v docker >/dev/null 2>&1; then
                success "Docker installed"
                return 0
            fi
        fi

        error "Docker is required. Please install it and re-run."
        echo "  Install: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi

    error "Docker is required. Please install Docker and re-run."
    echo "  https://www.docker.com/products/docker-desktop/"
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: Docker daemon running
# ---------------------------------------------------------------------------
check_docker_running() {
    if docker info >/dev/null 2>&1; then
        success "Docker daemon is running"
        return 0
    fi

    warn "Docker daemon is not running."

    if [ "$OS" = "macos" ]; then
        if ask "  Start Docker Desktop?" "y"; then
            info "Opening Docker Desktop..."
            open -a Docker 2>/dev/null || true

            info "Waiting for Docker daemon to start..."
            local waited=0
            while ! docker info >/dev/null 2>&1; do
                sleep 3
                waited=$((waited + 3))
                if [ "$waited" -ge 90 ]; then
                    error "Timed out waiting for Docker daemon. Please start Docker Desktop and re-run."
                    exit 1
                fi
                printf '.' >&2
            done
            echo "" >&2
            success "Docker daemon is running"
            return 0
        fi
    fi

    if [ "$OS" = "linux" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            if ask "  Start Docker daemon via systemctl?" "y"; then
                sudo systemctl start docker
                sleep 2
                if docker info >/dev/null 2>&1; then
                    success "Docker daemon is running"
                    return 0
                fi
            fi
        fi
    fi

    error "Please start the Docker daemon and re-run."
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: Docker Compose v2
# ---------------------------------------------------------------------------
check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        success "Docker Compose v2 found ($(docker compose version --short 2>/dev/null || echo 'ok'))"
        return 0
    fi

    warn "Docker Compose v2 not found (need 'docker compose' — no hyphen)."

    if [ "$OS" = "linux" ] && [ -n "$PKG_MANAGER" ]; then
        if ask "  Install docker-compose-plugin?" "y"; then
            install_package "docker-compose-plugin"
            if docker compose version >/dev/null 2>&1; then
                success "Docker Compose v2 installed"
                return 0
            fi
        fi
    fi

    if [ "$OS" = "macos" ]; then
        echo "  Docker Compose v2 is included with Docker Desktop."
        echo "  Please ensure Docker Desktop is up to date."
    fi

    error "Docker Compose v2 is required. Please install it and re-run."
    echo "  https://docs.docker.com/compose/install/"
    exit 1
}

# ---------------------------------------------------------------------------
# Package install helper (Linux)
# ---------------------------------------------------------------------------
install_package() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
            ;;
        dnf)
            sudo dnf install -y -q "$pkg"
            ;;
        yum)
            sudo yum install -y -q "$pkg"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "$pkg"
            ;;
        zypper)
            sudo zypper install -y "$pkg"
            ;;
        apk)
            sudo apk add --no-cache "$pkg"
            ;;
        *)
            error "No supported package manager found. Please install '$pkg' manually."
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Wait for a command to become available
# ---------------------------------------------------------------------------
wait_for_command() {
    local cmd="$1"
    local timeout="${2:-60}"
    local waited=0
    while ! command -v "$cmd" >/dev/null 2>&1; do
        sleep 3
        waited=$((waited + 3))
        if [ "$waited" -ge "$timeout" ]; then
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Clone or update repository
# ---------------------------------------------------------------------------
clone_or_update() {
    INSTALL_DIR=$(ask_value "Install directory" "$DEFAULT_INSTALL_DIR")

    if [ -d "$INSTALL_DIR" ]; then
        if [ -d "$INSTALL_DIR/.git" ]; then
            info "Directory '$INSTALL_DIR' already exists with a git repo."
            if ask "  Pull latest changes?" "y"; then
                info "Running git pull..."
                git -C "$INSTALL_DIR" pull --ff-only || {
                    warn "Fast-forward pull failed. You may need to resolve conflicts manually."
                    warn "Continuing with existing checkout."
                }
            else
                info "Using existing checkout as-is."
            fi
            return 0
        else
            error "Directory '$INSTALL_DIR' exists but is not a git repository."
            echo "  Please remove it or choose a different directory and re-run."
            exit 1
        fi
    fi

    info "Cloning repository into '$INSTALL_DIR'..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    success "Repository cloned"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --install-dir)
                shift
                [ $# -eq 0 ] && { error "--install-dir requires a value"; exit 1; }
                DEFAULT_INSTALL_DIR="$1"
                ;;
            --help|-h)
                echo "Usage: bash install.sh [--install-dir <path>]"
                echo ""
                echo "Options:"
                echo "  --install-dir <path>  Directory to clone into (default: ./insights)"
                echo "  --help, -h            Show this help"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    color_init
    detect_os
    print_banner

    if [ "$OS" = "unknown" ]; then
        error "Unsupported operating system: $(uname -s)"
        echo "  This installer supports Linux and macOS."
        echo "  For Windows, use the PowerShell installer:"
        echo "  irm https://raw.githubusercontent.com/securehst/insights-quickstart/main/install.ps1 | iex"
        exit 1
    fi

    echo "${BOLD}── Checking prerequisites ──${RESET}"
    echo ""

    check_git
    check_docker
    check_docker_running
    check_docker_compose

    echo ""
    echo "${BOLD}── Repository setup ──${RESET}"
    echo ""

    clone_or_update

    echo ""
    success "All prerequisites met. Launching setup wizard..."
    echo ""

    # Hand off to setup.sh (exec replaces this process)
    cd "$INSTALL_DIR"
    exec bash setup.sh
}

main "$@"
