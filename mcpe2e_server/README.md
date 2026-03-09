# mcpe2e_server

MCP server that translates Claude tool calls to HTTP commands for Flutter E2E testing.

Part of the [mcpe2e](https://github.com/JhonaCodes/mcpe2e) ecosystem.

```
Claude → MCP (stdio) → mcpe2e_server → HTTP → mcpe2e (in-app) → real gestures
```

> **mcpe2e_server** is the MCP side: it speaks JSON-RPC 2.0 over stdio to Claude and
> sends HTTP requests to the `mcpe2e` Flutter library running inside your app.

---

## Quick Start

### 1. Install the binary

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.ps1 | iex
```

**Manual download** — pick the binary for your platform from [GitHub Releases](https://github.com/JhonaCodes/mcpe2e/releases/latest):

| Platform | Binary |
|---|---|
| macOS Apple Silicon (M1/M2/M3/M4) | `mcpe2e_server-macos-arm64` |
| macOS Intel | `mcpe2e_server-macos-x86_64` |
| Linux x86_64 | `mcpe2e_server-linux-x86_64` |
| Windows x86_64 | `mcpe2e_server.exe` |

Make the binary executable on macOS/Linux:
```bash
chmod +x mcpe2e_server-macos-arm64
```

### 2. Register with Claude Code

```bash
# macOS / Linux (after install.sh)
claude mcp add mcpe2e \
  --command ~/.local/bin/mcpe2e_server \
  --env TESTBRIDGE_URL=http://localhost:7778

# Windows (after install.ps1)
claude mcp add mcpe2e --command "$env:LOCALAPPDATA\mcpe2e\mcpe2e_server.exe" --env TESTBRIDGE_URL=http://localhost:7778
```

**Claude Desktop** — add to `claude_desktop_config.json`:

macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "mcpe2e": {
      "command": "/Users/you/.local/bin/mcpe2e_server",
      "env": {
        "TESTBRIDGE_URL": "http://localhost:7778"
      }
    }
  }
}
```

### 3. Connect to the app

```bash
# Android (ADB forward: device port 7777 → localhost 7778)
adb forward tcp:7778 tcp:7777

# iOS (iproxy — install via: brew install usbmuxd)
iproxy 7778 7777

# Desktop app running on the same machine — no forwarding needed
# Use TESTBRIDGE_URL=http://localhost:7777
```

### 4. Verify the connection

```bash
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}
```

Claude can now control your Flutter app.

---

## TESTBRIDGE_URL

Tells `mcpe2e_server` where the in-app HTTP server is reachable from your machine.

| Scenario | Value |
|---|---|
| Android via ADB forward | `http://localhost:7778` |
| iOS via iproxy | `http://localhost:7778` |
| Desktop app (same machine) | `http://localhost:7777` |
| Custom port | `http://localhost:<port>` |

Default if not set: `http://localhost:7777`

---

## Available Tools (29)

### Context & inspection

| Tool | Description |
|---|---|
| `get_app_context` | Registered widgets with metadata and capabilities |
| `list_test_cases` | Alias for get_app_context |
| `inspect_ui` | Full widget tree with values/states — no registration needed |
| `capture_screenshot` | Current screen as PNG image (debug/profile only) |

### Gestures

| Tool | Parameters | Description |
|---|---|---|
| `tap_widget` | `key` | Single tap |
| `double_tap_widget` | `key` | Double tap |
| `long_press_widget` | `key`, `duration_ms?` | Long press (default 500ms) |
| `swipe_widget` | `key`, `direction`, `distance?` | Swipe in a direction |
| `scroll_widget` | `key`, `direction` | Scroll a list |
| `scroll_until_visible` | `key`, `target_key`, `max_attempts?` | Scroll until a widget is visible |
| `drag_widget` | `key`, `dx`, `dy`, `duration_ms?` | Drag by pixel offset from center |
| `pinch_widget` | `key`, `scale` | Pinch zoom (stub — not yet implemented) |
| `tap_by_label` | `label` | Tap by visible text label |

### Input

| Tool | Parameters | Description |
|---|---|---|
| `input_text` | `key`, `text`, `clear_first?` | Type into a TextField |
| `clear_text` | `key` | Clear a TextField |
| `select_dropdown` | `key`, `value` or `index` | Select a DropdownButtonFormField option |
| `toggle_widget` | `key` | Toggle Checkbox / Switch / Radio |
| `set_slider_value` | `key`, `value` (0.0–1.0) | Set Slider position |

### Keyboard & navigation

| Tool | Parameters | Description |
|---|---|---|
| `show_keyboard` | `key` | Show virtual keyboard (request focus) |
| `hide_keyboard` | — | Dismiss virtual keyboard |
| `press_back` | `key` | Navigate back |
| `wait` | `duration_ms` | Pause execution |

### Assertions

| Tool | Parameters | Description |
|---|---|---|
| `assert_exists` | `key` | Widget is registered |
| `assert_text` | `key`, `text` | Visible text matches exactly |
| `assert_visible` | `key` | Widget is fully visible in viewport |
| `assert_enabled` | `key` | Widget is enabled |
| `assert_selected` | `key` | Checkbox/Switch/Radio is active |
| `assert_value` | `key`, `value` | TextField controller value matches |
| `assert_count` | `key`, `count` | Column/Row/ListView has exactly N children |

---

## Secondary Install: dart pub global

If you have the Dart SDK installed:

```bash
dart pub global activate mcpe2e_server
# adds mcpe2e_server to PATH automatically
mcpe2e_server  # run directly
```

---

## Build from Source

```bash
git clone https://github.com/JhonaCodes/mcpe2e
cd mcpe2e/mcpe2e_server
dart pub get
dart compile exe bin/mcp_server.dart -o mcpe2e_server
```

Requires Dart SDK ≥ 3.5.0. Download at [dart.dev/get-dart](https://dart.dev/get-dart).

---

## Full Integration Guide

See [docs/integration-guide.md](../docs/integration-guide.md) for step-by-step
instructions on adding `mcpe2e` to any Flutter app and running your first test.
