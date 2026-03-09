#!/usr/bin/env bash
# mcpe2e_server installer for macOS and Linux
# Downloads the correct pre-compiled binary from the latest GitHub Release.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh | bash
set -euo pipefail

REPO="JhonaCodes/mcpe2e"
BINARY_NAME="mcpe2e_server"
INSTALL_DIR="${HOME}/.local/bin"

# ── Detect platform ──────────────────────────────────────────────────────────
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

# ── Resolve latest release tag ───────────────────────────────────────────────
if command -v curl &>/dev/null; then
  FETCH() { curl -fsSL "$1"; }
elif command -v wget &>/dev/null; then
  FETCH() { wget -qO- "$1"; }
else
  echo "Error: curl or wget is required"
  exit 1
fi

echo "Fetching latest release..."
LATEST_TAG=$(FETCH "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [[ -z "$LATEST_TAG" ]]; then
  echo "Error: Could not determine latest release."
  echo "Check: https://github.com/${REPO}/releases"
  exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ASSET}"

# ── Download and install ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

echo "Downloading ${ASSET} (${LATEST_TAG})..."
FETCH "$DOWNLOAD_URL" > "${INSTALL_DIR}/${BINARY_NAME}"
chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

echo ""
echo "Installed: ${INSTALL_DIR}/${BINARY_NAME}"
echo ""

# ── PATH check ───────────────────────────────────────────────────────────────
if ! echo "$PATH" | grep -q "${INSTALL_DIR}"; then
  echo "NOTE: ${INSTALL_DIR} is not in your PATH."
  echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
  echo ""
  echo '  export PATH="$HOME/.local/bin:$PATH"'
  echo ""
fi

# ── MCP registration instructions ────────────────────────────────────────────
echo "Register with Claude Code:"
echo ""
echo "  claude mcp add mcpe2e \\"
echo "    --command ${INSTALL_DIR}/${BINARY_NAME} \\"
echo "    --env TESTBRIDGE_URL=http://localhost:7778"
echo ""
echo "Then connect your device:"
echo "  Android: adb forward tcp:7778 tcp:7777"
echo "  iOS:     iproxy 7778 7777"
echo "  Desktop: use TESTBRIDGE_URL=http://localhost:7777"
