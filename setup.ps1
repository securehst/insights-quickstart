# =============================================================================
# SecureHST Insights — Windows Setup (PowerShell → WSL)
# =============================================================================
# This script delegates to setup.sh via WSL. Docker Desktop on Windows
# requires WSL, so it should already be available.
#
# Usage: .\setup.ps1 [options]
#   All arguments are forwarded to setup.sh
# =============================================================================

$ErrorActionPreference = "Stop"

# Check WSL is available
try {
    $null = Get-Command wsl -ErrorAction Stop
} catch {
    Write-Host "Error: WSL is not installed." -ForegroundColor Red
    Write-Host "Docker Desktop for Windows requires WSL. Install it with:" -ForegroundColor Yellow
    Write-Host "  wsl --install" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Convert the script directory to a WSL path
$WinDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WslDir = wsl wslpath -u ($WinDir -replace '\\', '/')

# Forward all arguments to setup.sh in WSL
$ArgString = ($args | ForEach-Object { "'$_'" }) -join " "
$Command = "cd '$WslDir' && bash setup.sh $ArgString"

Write-Host "Running setup via WSL..." -ForegroundColor Cyan
wsl bash -c $Command
$ExitCode = $LASTEXITCODE

Write-Host ""
if ($ExitCode -eq 0) {
    Write-Host "Setup complete." -ForegroundColor Green
} else {
    Write-Host "Setup exited with code $ExitCode." -ForegroundColor Red
}

Read-Host "Press Enter to close"
exit $ExitCode
