# mcpe2e_server installer for Windows
# Downloads the pre-compiled binary and registers it with:
#   Claude Code, Claude Desktop, Codex CLI (OpenAI), Gemini CLI
#
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo           = "JhonaCodes/mcpe2e"
$Asset          = "mcpe2e_server.exe"
$BinaryName     = "mcpe2e_server.exe"
$InstallDir     = Join-Path $env:LOCALAPPDATA "mcpe2e"
$TestbridgeUrl  = "http://localhost:7778"

# ── Resolve latest release ────────────────────────────────────────────────────
Write-Host "Fetching latest release..."
$Release    = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
$Tag        = $Release.tag_name

if (-not $Tag) {
    Write-Error "Could not determine latest release. Check: https://github.com/$Repo/releases"
    exit 1
}

$DownloadUrl = "https://github.com/$Repo/releases/download/$Tag/$Asset"

# ── Download and install ──────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$BinaryPath = Join-Path $InstallDir $BinaryName

Write-Host "Downloading $Asset ($Tag)..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinaryPath

Write-Host ""
Write-Host "Installed: $BinaryPath"

# ── PATH check ────────────────────────────────────────────────────────────────
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$InstallDir*") {
    Write-Host ""
    Write-Host "NOTE: Adding $InstallDir to PATH..."
    [Environment]::SetEnvironmentVariable("PATH", "$CurrentPath;$InstallDir", "User")
    Write-Host "Restart your terminal for PATH changes to take effect."
}

# ── Helper: merge mcpe2e into JSON config ────────────────────────────────────
function Register-JsonConfig {
    param([string]$ConfigFile, [string]$Label)
    $dir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $cfg = @{}
    if (Test-Path $ConfigFile) {
        try { $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json -AsHashtable }
        catch { $cfg = @{} }
    }
    if (-not $cfg.ContainsKey('mcpServers')) { $cfg['mcpServers'] = @{} }
    $cfg['mcpServers']['mcpe2e'] = @{
        command = $BinaryPath
        args    = @()
        env     = @{ TESTBRIDGE_URL = $TestbridgeUrl }
    }
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8
    Write-Host "  $([char]0x2713) ${Label}: ${ConfigFile}"
}

# ── Register with all tools ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Registering MCP server..."
Write-Host ""

# Claude Code
if (Get-Command claude -ErrorAction SilentlyContinue) {
    claude mcp remove mcpe2e 2>$null
    claude mcp add mcpe2e -e "TESTBRIDGE_URL=$TestbridgeUrl" -- $BinaryPath
    Write-Host "  $([char]0x2713) Claude Code"
} else {
    Write-Host "  - Claude Code: not found"
}

# Claude Desktop
$ClaudeDesktop = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
if ((Test-Path $ClaudeDesktop) -or (Test-Path (Split-Path $ClaudeDesktop -Parent))) {
    Register-JsonConfig $ClaudeDesktop "Claude Desktop"
} else {
    Write-Host "  - Claude Desktop: not found"
}

# Codex CLI (OpenAI)
$CodexConfig = Join-Path $env:USERPROFILE ".codex\config.toml"
if ((Get-Command codex -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".codex"))) {
    # TOML — simple append/replace approach
    $tomlPath = $CodexConfig
    $content  = if (Test-Path $tomlPath) { Get-Content $tomlPath -Raw } else { "" }
    $content  = [regex]::Replace($content, '\[mcp_servers\.mcpe2e\][^\[]*', '', 'Singleline').TrimEnd()
    $entry    = "`n`n[mcp_servers.mcpe2e]`ncommand = `"$BinaryPath`"`nenv = { TESTBRIDGE_URL = `"$TestbridgeUrl`" }`n"
    ($content + $entry) | Set-Content $tomlPath -Encoding UTF8
    Write-Host "  $([char]0x2713) Codex CLI: $tomlPath"
} else {
    Write-Host "  - Codex CLI: not found"
}

# Gemini CLI (Google)
$GeminiConfig = Join-Path $env:USERPROFILE ".gemini\settings.json"
if ((Get-Command gemini -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".gemini"))) {
    Register-JsonConfig $GeminiConfig "Gemini CLI"
} else {
    Write-Host "  - Gemini CLI: not found"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "────────────────────────────────────────────────────────────────"
Write-Host "Next steps:"
Write-Host ""
Write-Host "  1. Start your Flutter app in debug mode"
Write-Host "  2. Connect your device:"
Write-Host "       Android : adb forward tcp:7778 tcp:7777"
Write-Host "       iOS     : iproxy 7778 7777"
Write-Host "       Desktop : set TESTBRIDGE_URL=http://localhost:7777"
Write-Host "  3. Ask Claude / Codex / Gemini: inspect_ui"
Write-Host "────────────────────────────────────────────────────────────────"
