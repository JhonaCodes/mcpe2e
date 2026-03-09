#!/usr/bin/env bash
# mcpe2e_server installer for macOS and Linux
# Downloads the binary, cleans old installs, and asks which AI agents to register.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh -o /tmp/mcpe2e_install.sh && bash /tmp/mcpe2e_install.sh

set -euo pipefail

REPO="JhonaCodes/mcpe2e"
BINARY_NAME="mcpe2e_server"
INSTALL_DIR="${HOME}/.local/bin"
TESTBRIDGE_URL="http://localhost:7778"

# ── Detect platform ───────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}/${ARCH}" in
  Darwin/arm64)  ASSET="mcpe2e_server-macos-arm64"  ;;
  Darwin/x86_64) ASSET="mcpe2e_server-macos-x86_64" ;;
  Linux/x86_64)  ASSET="mcpe2e_server-linux-x86_64" ;;
  *)
    echo "Unsupported platform: ${OS}/${ARCH}"
    echo "Build from source: cd mcpe2e_server && dart compile exe bin/mcp_server.dart -o mcpe2e_server"
    exit 1
    ;;
esac

# ── HTTP client ───────────────────────────────────────────────────────────────
if command -v curl &>/dev/null; then
  FETCH() { curl -fsSL "$1"; }
elif command -v wget &>/dev/null; then
  FETCH() { wget -qO- "$1"; }
else
  echo "Error: curl or wget is required"
  exit 1
fi

# ── Detect Python ─────────────────────────────────────────────────────────────
if command -v python3 &>/dev/null; then
  PY="python3"
elif command -v python &>/dev/null; then
  PY="python"
else
  PY=""
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Clean up old installs
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  mcpe2e installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "[ 1/3 ] Cleaning up old installs..."

# Remove old binary
if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
  rm -f "${INSTALL_DIR}/${BINARY_NAME}"
  echo "  ✓ Removed old binary: ${INSTALL_DIR}/${BINARY_NAME}"
fi

# Remove from Claude Code
if command -v claude &>/dev/null; then
  claude mcp remove mcpe2e 2>/dev/null && echo "  ✓ Removed from Claude Code" || true
fi

# Remove from Claude Desktop
if [[ "$OS" == "Darwin" ]]; then
  CLAUDE_DESKTOP="${HOME}/Library/Application Support/Claude/claude_desktop_config.json"
else
  CLAUDE_DESKTOP="${HOME}/.config/claude/claude_desktop_config.json"
fi
if [[ -f "$CLAUDE_DESKTOP" ]] && [[ -n "$PY" ]]; then
  $PY - "$CLAUDE_DESKTOP" <<'PYEOF'
import json, sys, os
path = sys.argv[1]
if not os.path.exists(path): sys.exit(0)
try:
    cfg = json.loads(open(path).read())
    if cfg.get('mcpServers', {}).pop('mcpe2e', None) is not None:
        open(path, 'w').write(json.dumps(cfg, indent=2) + '\n')
        print('  ✓ Removed from Claude Desktop')
except Exception:
    pass
PYEOF
fi

# Remove from Codex CLI
CODEX_TOML="${HOME}/.codex/config.toml"
if [[ -f "$CODEX_TOML" ]] && [[ -n "$PY" ]]; then
  $PY - "$CODEX_TOML" <<'PYEOF'
import sys, os, re
path = sys.argv[1]
if not os.path.exists(path): sys.exit(0)
content = open(path).read()
new = re.sub(r'\[mcp_servers\.mcpe2e\][^\[]*', '', content, flags=re.DOTALL).rstrip('\n') + '\n'
if new != content:
    open(path, 'w').write(new)
    print('  ✓ Removed from Codex CLI')
PYEOF
fi

# Remove from Gemini CLI
GEMINI_CONFIG="${HOME}/.gemini/settings.json"
if [[ -f "$GEMINI_CONFIG" ]] && [[ -n "$PY" ]]; then
  $PY - "$GEMINI_CONFIG" <<'PYEOF'
import json, sys, os
path = sys.argv[1]
if not os.path.exists(path): sys.exit(0)
try:
    cfg = json.loads(open(path).read())
    if cfg.get('mcpServers', {}).pop('mcpe2e', None) is not None:
        open(path, 'w').write(json.dumps(cfg, indent=2) + '\n')
        print('  ✓ Removed from Gemini CLI')
except Exception:
    pass
PYEOF
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Download and install fresh binary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ 2/3 ] Installing binary..."

echo "  Fetching latest release..."
LATEST_TAG=$(FETCH "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [[ -z "$LATEST_TAG" ]]; then
  echo "  Error: Could not fetch latest release from GitHub."
  exit 1
fi

mkdir -p "$INSTALL_DIR"
echo "  Downloading ${ASSET} (${LATEST_TAG})..."
FETCH "https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ASSET}" \
  > "${INSTALL_DIR}/${BINARY_NAME}"
chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

BINARY_PATH="${INSTALL_DIR}/${BINARY_NAME}"
echo "  ✓ ${BINARY_PATH}"

if ! echo "$PATH" | grep -q "${INSTALL_DIR}"; then
  echo ""
  echo "  NOTE: ${INSTALL_DIR} is not in PATH. Add to ~/.zshrc or ~/.bashrc:"
  echo '    export PATH="$HOME/.local/bin:$PATH"'
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Ask which agents to register
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ 3/3 ] Select AI agents to register:"
echo ""

# Detect which tools are present
declare -A AVAILABLE
command -v claude  &>/dev/null                           && AVAILABLE[claude_code]="✓" || AVAILABLE[claude_code]="✗ (not installed)"
[[ -f "$CLAUDE_DESKTOP" || -d "$(dirname "$CLAUDE_DESKTOP")" ]] && AVAILABLE[claude_desktop]="✓" || AVAILABLE[claude_desktop]="✗ (not installed)"
{ command -v codex &>/dev/null || [[ -d "${HOME}/.codex" ]]; }  && AVAILABLE[codex]="✓"         || AVAILABLE[codex]="✗ (not installed)"
{ command -v gemini &>/dev/null || [[ -d "${HOME}/.gemini" ]]; } && AVAILABLE[gemini]="✓"        || AVAILABLE[gemini]="✗ (not installed)"

echo "  [1] Claude Code    ${AVAILABLE[claude_code]}"
echo "  [2] Claude Desktop ${AVAILABLE[claude_desktop]}"
echo "  [3] Codex CLI      ${AVAILABLE[codex]}"
echo "  [4] Gemini CLI     ${AVAILABLE[gemini]}"
echo "  [a] All of the above"
echo ""
read -rp "  Enter choices (e.g. 1 3 4 or a): " CHOICES

# Normalize input
CHOICES="${CHOICES,,}"

register_all=false
[[ "$CHOICES" == *"a"* ]] && register_all=true

register_claude_code=false
register_claude_desktop=false
register_codex=false
register_gemini=false

if $register_all; then
  register_claude_code=true
  register_claude_desktop=true
  register_codex=true
  register_gemini=true
else
  [[ "$CHOICES" == *"1"* ]] && register_claude_code=true
  [[ "$CHOICES" == *"2"* ]] && register_claude_desktop=true
  [[ "$CHOICES" == *"3"* ]] && register_codex=true
  [[ "$CHOICES" == *"4"* ]] && register_gemini=true
fi

echo ""

# ── Register: Claude Code ─────────────────────────────────────────────────────
if $register_claude_code; then
  if command -v claude &>/dev/null; then
    claude mcp add mcpe2e -e TESTBRIDGE_URL="${TESTBRIDGE_URL}" -- "$BINARY_PATH"
    echo "  ✓ Claude Code"
  else
    echo "  ✗ Claude Code: CLI not found — install from https://claude.ai/download"
  fi
fi

# ── Register: Claude Desktop ──────────────────────────────────────────────────
if $register_claude_desktop; then
  if [[ -n "$PY" ]]; then
    mkdir -p "$(dirname "$CLAUDE_DESKTOP")"
    $PY - "$CLAUDE_DESKTOP" "$BINARY_PATH" "$TESTBRIDGE_URL" <<'PYEOF'
import json, sys, os
path, binary, url = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {}
if os.path.exists(path):
    try: cfg = json.loads(open(path).read())
    except Exception: cfg = {}
cfg.setdefault('mcpServers', {})['mcpe2e'] = {'command': binary, 'args': [], 'env': {'TESTBRIDGE_URL': url}}
open(path, 'w').write(json.dumps(cfg, indent=2) + '\n')
PYEOF
    echo "  ✓ Claude Desktop: ${CLAUDE_DESKTOP}"
  else
    echo "  ✗ Claude Desktop: Python not found"
  fi
fi

# ── Register: Codex CLI ───────────────────────────────────────────────────────
if $register_codex; then
  if [[ -n "$PY" ]]; then
    mkdir -p "${HOME}/.codex"
    $PY - "$CODEX_TOML" "$BINARY_PATH" "$TESTBRIDGE_URL" <<'PYEOF'
import sys, os, re
path, binary, url = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(path).read() if os.path.exists(path) else ''
content = re.sub(r'\[mcp_servers\.mcpe2e\][^\[]*', '', content, flags=re.DOTALL).rstrip('\n')
entry = f'\n\n[mcp_servers.mcpe2e]\ncommand = "{binary}"\nenv = {{ TESTBRIDGE_URL = "{url}" }}\n'
open(path, 'w').write(content + entry)
PYEOF
    echo "  ✓ Codex CLI: ${CODEX_TOML}"
  else
    echo "  ✗ Codex CLI: Python not found"
  fi
fi

# ── Register: Gemini CLI ──────────────────────────────────────────────────────
if $register_gemini; then
  if [[ -n "$PY" ]]; then
    mkdir -p "${HOME}/.gemini"
    $PY - "$GEMINI_CONFIG" "$BINARY_PATH" "$TESTBRIDGE_URL" <<'PYEOF'
import json, sys, os
path, binary, url = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {}
if os.path.exists(path):
    try: cfg = json.loads(open(path).read())
    except Exception: cfg = {}
cfg.setdefault('mcpServers', {})['mcpe2e'] = {'command': binary, 'args': [], 'env': {'TESTBRIDGE_URL': url}}
open(path, 'w').write(json.dumps(cfg, indent=2) + '\n')
PYEOF
    echo "  ✓ Gemini CLI: ${GEMINI_CONFIG}"
  else
    echo "  ✗ Gemini CLI: Python not found"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Done! Next steps:"
echo ""
echo "  Android / emulator"
echo "    1. Tell your AI agent:"
echo '         run_command command:"flutter run" working_dir:"/path/to/app" background:true'
echo "    2. Wait ~15s, then:"
echo "         list_devices       ← auto port-forwarding (finds a free port automatically)"
echo "         select_device      ← if multiple devices"
echo "         inspect_ui         ← start testing"
echo ""
echo "  iOS"
echo "    1. Start app manually (debug mode)"
echo "    2. Forward a free local port to the app:"
echo "         iproxy <free_port> 7777"
echo "    3. Set TESTBRIDGE_URL=http://localhost:<free_port> in your agent config"
echo "    4. Ask your AI agent: inspect_ui"
echo ""
echo "  Desktop (macOS / Linux / Windows)"
echo "    1. Start app manually (debug mode)"
echo "       The app picks a free port automatically — check its output for the URL."
echo "    2. Set TESTBRIDGE_URL=<url_from_app_output> in your agent config"
echo "    3. Ask your AI agent: inspect_ui"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
