# mcpe2e_server installer for Windows
# Downloads the pre-compiled binary from the latest GitHub Release.
#
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.ps1 | iex
$ErrorActionPreference = "Stop"

$Repo = "JhonaCodes/mcpe2e"
$Asset = "mcpe2e_server.exe"
$BinaryName = "mcpe2e_server.exe"
$InstallDir = Join-Path $env:LOCALAPPDATA "mcpe2e"

# ── Resolve latest release tag ───────────────────────────────────────────────
Write-Host "Fetching latest release..."
$Release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
$Tag = $Release.tag_name

if (-not $Tag) {
    Write-Error "Could not determine latest release. Check: https://github.com/$Repo/releases"
    exit 1
}

$DownloadUrl = "https://github.com/$Repo/releases/download/$Tag/$Asset"

# ── Download and install ─────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$BinaryPath = Join-Path $InstallDir $BinaryName

Write-Host "Downloading $Asset ($Tag)..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinaryPath

Write-Host ""
Write-Host "Installed: $BinaryPath"
Write-Host ""

# ── PATH check ───────────────────────────────────────────────────────────────
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$InstallDir*") {
    Write-Host "NOTE: Adding $InstallDir to your PATH..."
    [Environment]::SetEnvironmentVariable("PATH", "$CurrentPath;$InstallDir", "User")
    Write-Host "Restart your terminal for PATH changes to take effect."
    Write-Host ""
}

# ── Register with Claude Code ─────────────────────────────────────────────────
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "Registering with Claude Code..."
    claude mcp add mcpe2e --command "$BinaryPath" --env TESTBRIDGE_URL=http://localhost:7778
    Write-Host ""
    Write-Host "✓ Done! mcpe2e is registered in Claude Code."
    Write-Host ""
    Write-Host "Connect your device:"
    Write-Host "  Android: adb forward tcp:7778 tcp:7777"
    Write-Host "  iOS:     iproxy 7778 7777"
} else {
    Write-Host "Claude Code CLI not found. Register manually:"
    Write-Host ""
    Write-Host "  claude mcp add mcpe2e --command `"$BinaryPath`" --env TESTBRIDGE_URL=http://localhost:7778"
    Write-Host ""
    Write-Host "Then connect your device:"
    Write-Host "  Android: adb forward tcp:7778 tcp:7777"
    Write-Host "  iOS:     iproxy 7778 7777"
    Write-Host "  Desktop: use TESTBRIDGE_URL=http://localhost:7777"
}
