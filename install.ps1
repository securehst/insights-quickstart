# =============================================================================
# SecureHST Insights — One-Command Installer (Windows / PowerShell)
# =============================================================================
# Downloads and bootstraps SecureHST Insights on Windows.
# Checks for prerequisites (git, Docker Desktop), offers to install any
# that are missing, clones the repository, and launches the setup wizard
# via Git Bash.
#
# Usage:
#   irm https://raw.githubusercontent.com/securehst/insights-quickstart/main/install.ps1 | iex
#
# Or download and run directly:
#   .\install.ps1 [-InstallDir <path>]
# =============================================================================

param(
    [string]$InstallDir = ".\insights"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Print helpers
# ---------------------------------------------------------------------------
function Write-Info    { param([string]$Msg) Write-Host "[info] " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Success { param([string]$Msg) Write-Host "  ✓ " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param([string]$Msg) Write-Host "[warn] " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err     { param([string]$Msg) Write-Host "[error] " -ForegroundColor Red -NoNewline; Write-Host $Msg }

function Ask-YesNo {
    param(
        [string]$Prompt,
        [string]$Default = "y"
    )
    $hint = if ($Default -eq "y") { "Y/n" } else { "y/N" }
    $answer = Read-Host "$Prompt [$hint]"
    $answer = $answer.Trim().ToLower()

    switch ($answer) {
        "y"     { return $true }
        "yes"   { return $true }
        "n"     { return $false }
        "no"    { return $false }
        ""      { return ($Default -eq "y") }
        default { return ($Default -eq "y") }
    }
}

# ---------------------------------------------------------------------------
# Welcome banner
# ---------------------------------------------------------------------------
function Show-Banner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "  ║     SecureHST Insights — Quick Installer     ║" -ForegroundColor Blue
    Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  This installer will check for prerequisites, clone the"
    Write-Host "  repository, and launch the interactive setup wizard."
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Refresh PATH from registry (picks up new installs without restarting shell)
# ---------------------------------------------------------------------------
function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"
}

# ---------------------------------------------------------------------------
# Prerequisite: git
# ---------------------------------------------------------------------------
function Check-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $ver = (git --version) -replace "git version ", ""
        Write-Success "git found ($ver)"
        return
    }

    Write-Warn "git is not installed."

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (Ask-YesNo "  Install Git via winget?" "y") {
            Write-Info "Running: winget install Git.Git --accept-package-agreements --accept-source-agreements"
            winget install Git.Git --accept-package-agreements --accept-source-agreements

            Refresh-Path

            if (Get-Command git -ErrorAction SilentlyContinue) {
                Write-Success "git installed"
                return
            }

            # winget may install to a path not yet in this session
            $gitPaths = @(
                "$env:ProgramFiles\Git\cmd",
                "${env:ProgramFiles(x86)}\Git\cmd",
                "$env:LOCALAPPDATA\Programs\Git\cmd"
            )
            foreach ($p in $gitPaths) {
                if (Test-Path "$p\git.exe") {
                    $env:Path += ";$p"
                    Write-Success "git installed (found at $p)"
                    return
                }
            }
        }
    }

    Write-Err "git is required. Please install it and re-run."
    Write-Host "  Download from: https://git-scm.com/download/win"
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: Docker Desktop
# ---------------------------------------------------------------------------
function Check-Docker {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $ver = (docker --version) -replace "Docker version ", "" -replace ",.*", ""
        Write-Success "Docker found ($ver)"
        return
    }

    Write-Warn "Docker is not installed."

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (Ask-YesNo "  Install Docker Desktop via winget?" "y") {
            Write-Info "Running: winget install Docker.DockerDesktop --accept-package-agreements --accept-source-agreements"
            winget install Docker.DockerDesktop --accept-package-agreements --accept-source-agreements

            Refresh-Path

            if (Get-Command docker -ErrorAction SilentlyContinue) {
                Write-Success "Docker Desktop installed"
                Write-Warn "A system restart may be required for Docker to work correctly."
                Write-Warn "If Docker fails to start, restart your computer and re-run this installer."
                return
            }

            # Check common install paths
            $dockerPaths = @(
                "$env:ProgramFiles\Docker\Docker\resources\bin"
            )
            foreach ($p in $dockerPaths) {
                if (Test-Path "$p\docker.exe") {
                    $env:Path += ";$p"
                    Write-Success "Docker Desktop installed (found at $p)"
                    Write-Warn "A system restart may be required."
                    return
                }
            }

            Write-Warn "Docker was installed but may require a restart."
            Write-Host "  Please restart your computer, then re-run this installer."
            exit 0
        }
    }

    Write-Err "Docker Desktop is required. Please install it and re-run."
    Write-Host "  Download from: https://www.docker.com/products/docker-desktop/"
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: Docker daemon running
# ---------------------------------------------------------------------------
function Check-DockerRunning {
    try {
        $null = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker daemon is running"
            return
        }
    } catch { }

    Write-Warn "Docker daemon is not running."

    if (Ask-YesNo "  Start Docker Desktop?" "y") {
        Write-Info "Starting Docker Desktop..."
        Start-Process "Docker Desktop" -ErrorAction SilentlyContinue

        Write-Info "Waiting for Docker daemon to start..."
        $waited = 0
        while ($waited -lt 90) {
            Start-Sleep -Seconds 3
            $waited += 3
            try {
                $null = docker info 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Docker daemon is running"
                    return
                }
            } catch { }
            Write-Host "." -NoNewline
        }
        Write-Host ""
    }

    Write-Err "Please start Docker Desktop and re-run this installer."
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: Docker Compose v2
# ---------------------------------------------------------------------------
function Check-DockerCompose {
    try {
        $null = docker compose version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $ver = (docker compose version --short 2>$null)
            Write-Success "Docker Compose v2 found ($ver)"
            return
        }
    } catch { }

    Write-Warn "Docker Compose v2 not found."
    Write-Host "  Docker Compose v2 is included with Docker Desktop."
    Write-Host "  Please ensure Docker Desktop is up to date."
    Write-Err "Docker Compose v2 is required."
    exit 1
}

# ---------------------------------------------------------------------------
# Clone or update repository
# ---------------------------------------------------------------------------
function Clone-OrUpdate {
    if (Test-Path $InstallDir) {
        if (Test-Path "$InstallDir\.git") {
            Write-Info "Directory '$InstallDir' already exists with a git repo."
            if (Ask-YesNo "  Pull latest changes?" "y") {
                Write-Info "Running git pull..."
                Push-Location $InstallDir
                try {
                    git pull --ff-only
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warn "Fast-forward pull failed. You may need to resolve conflicts manually."
                        Write-Warn "Continuing with existing checkout."
                    }
                } finally {
                    Pop-Location
                }
            } else {
                Write-Info "Using existing checkout as-is."
            }
            return
        } else {
            Write-Err "Directory '$InstallDir' exists but is not a git repository."
            Write-Host "  Please remove it or choose a different directory and re-run."
            exit 1
        }
    }

    Write-Info "Cloning repository into '$InstallDir'..."
    git clone $REPO_URL $InstallDir
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to clone repository."
        exit 1
    }
    Write-Success "Repository cloned"
}

# ---------------------------------------------------------------------------
# Find Git Bash
# ---------------------------------------------------------------------------
function Find-GitBash {
    # Try to locate bash.exe relative to git.exe
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitDir = Split-Path (Split-Path $gitCmd.Source -Parent) -Parent
        $bashPath = Join-Path $gitDir "bin\bash.exe"
        if (Test-Path $bashPath) {
            return $bashPath
        }
    }

    # Check common install locations
    $commonPaths = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    return $null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {
    Show-Banner

    Write-Host "── Checking prerequisites ──" -ForegroundColor White
    Write-Host ""

    Check-Git
    Check-Docker
    Check-DockerRunning
    Check-DockerCompose

    Write-Host ""
    Write-Host "── Repository setup ──" -ForegroundColor White
    Write-Host ""

    Clone-OrUpdate

    Write-Host ""
    Write-Success "All prerequisites met. Launching setup wizard..."
    Write-Host ""

    # Find Git Bash and hand off to setup.sh
    $bash = Find-GitBash
    if ($bash) {
        $resolvedDir = (Resolve-Path $InstallDir).Path
        # Convert Windows path to Git Bash format (C:\foo\bar -> /c/foo/bar)
        $bashDir = $resolvedDir -replace "\\", "/" -replace "^([A-Za-z]):", '/$1'
        $bashDir = $bashDir.Substring(0, 1) + $bashDir.Substring(1, 1).ToLower() + $bashDir.Substring(2)
        Write-Info "Launching setup wizard via Git Bash..."
        & $bash -c "cd '$bashDir' && bash setup.sh"
    } else {
        Write-Warn "Git Bash not found. Please run the setup wizard manually:"
        Write-Host ""
        Write-Host "  Option 1 (Git Bash):" -ForegroundColor Cyan
        Write-Host "    Open Git Bash, then run:"
        Write-Host "    cd $InstallDir && bash setup.sh"
        Write-Host ""
        Write-Host "  Option 2 (WSL):" -ForegroundColor Cyan
        Write-Host "    wsl -e bash -c 'cd $(wsl wslpath -u \"$((Resolve-Path $InstallDir).Path)\") && bash setup.sh'"
        Write-Host ""
    }
}

Main
