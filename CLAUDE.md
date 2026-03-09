# mcpe2e — AI-driven Flutter E2E Testing

Claude controls a real Flutter app on a device: tap, type, scroll, assert — using MCP tools.

## Architecture

```
Claude Code / Claude Desktop / Codex CLI / Gemini CLI
    │
    │  MCP (JSON-RPC 2.0 / stdio)
    ▼
┌─────────────────────────────────┐
│  mcpe2e_server  (Dart)          │  MCP Server — 29 tools
│  Translates MCP tools → HTTP    │  Installed in ~/.local/bin/
│  Binary: bin/mcp_server.dart    │  TESTBRIDGE_URL=http://localhost:7778
└────────────────┬────────────────┘
                 │  HTTP REST
                 │  localhost:7778 → (ADB/iproxy) → device:7777
                 ▼
┌─────────────────────────────────┐
│  mcpe2e  (Dart / Flutter lib)   │  Runs INSIDE the Flutter app
│  HTTP server on :7777           │  Executes real gestures on the
│  29 event types                 │  live widget tree on the device
│  Full widget tree inspection    │
└─────────────────────────────────┘
```

## Two independent components

| Component | What it is | Location |
|-----------|------------|----------|
| **mcpe2e** | Flutter library — HTTP server embedded in the app | `./mcpe2e/` |
| **mcpe2e_server** | MCP server binary — translates MCP tools to HTTP calls | `./mcpe2e_server/` |

`mcpe2e` is **not** an MCP server. It is an HTTP server that runs inside the device and executes real gestures on the app's widget tree.

## Primary testing approach: coordinate-based

No widget registration required.

1. Call `inspect_ui` — returns the full widget tree with `x`, `y`, `w`, `h` for every element.
2. Call `tap_at x: <cx> y: <cy>` — taps at those screen coordinates.

```
inspect_ui → { "type": "ElevatedButton", "label": "Login", "x": 20, "y": 400, "w": 350, "h": 52 }
tap_at     → x = 20 + 350/2 = 195, y = 400 + 52/2 = 426
```

Named widget keys (`McpMetadataKey`) are optional. Use them when you want stable named access to specific widgets across multiple tests.

## Minimal Flutter integration

```dart
// main.dart
import 'package:flutter/foundation.dart';
import 'package:mcpe2e/mcpe2e.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) await McpEventServer.start();
  runApp(const MyApp());
}
```

`McpEventServer.start()` is a no-op in release builds. No other changes to the app are required.

## Install mcpe2e_server

After adding `mcpe2e` to `dev_dependencies` and running `flutter pub get`:

```bash
dart run mcpe2e:setup
```

Downloads the binary to `~/.local/bin/mcpe2e_server` and opens the agent registration TUI.

To change registrations later:

```bash
mcpe2e_server setup
```

Interactive ANSI menu — toggle Claude Code, Claude Desktop, Codex CLI, Gemini CLI.

## Connect the device

```bash
# Android
adb forward tcp:7778 tcp:7777

# iOS (requires: brew install usbmuxd)
iproxy 7778 7777

# Desktop — no forwarding needed
# Set TESTBRIDGE_URL=http://localhost:7777 in the agent config
```

Verify:

```bash
curl http://localhost:7778/ping
# {"status":"ok","port":7777}
```

## MCP Tools (29 total)

**Context:** `get_app_context`, `list_test_cases`, `inspect_ui`, `capture_screenshot`

**Gestures:** `tap_widget`, `tap_at`, `double_tap_widget`, `long_press_widget`, `swipe_widget`, `scroll_widget`, `scroll_until_visible`, `drag_widget`, `pinch_widget`, `tap_by_label`

**Input:** `input_text`, `clear_text`, `select_dropdown`, `toggle_widget`, `set_slider_value`

**Keyboard/Navigation:** `show_keyboard`, `hide_keyboard`, `press_back`, `wait`

**Assertions:** `assert_exists`, `assert_text`, `assert_visible`, `assert_enabled`, `assert_selected`, `assert_value`, `assert_count`

## Platform connectivity

| Platform | Command | URL |
|----------|---------|-----|
| Android | `adb forward tcp:7778 tcp:7777` | `http://localhost:7778` |
| iOS | `iproxy 7778 7777` | `http://localhost:7778` |
| macOS/Linux/Windows desktop | — | `http://localhost:7777` |
| Web | not supported | — |

`TESTBRIDGE_URL` env var tells `mcpe2e_server` where the app is reachable. Default: `http://localhost:7778`.

## Build from source

```bash
cd mcpe2e_server
dart pub get
dart compile exe bin/mcp_server.dart -o ~/.local/bin/mcpe2e_server
```

Requires Dart SDK >= 3.5.0.

## Documentation

| File | Description |
|------|-------------|
| `README.md` | Overview, quick start, all 29 tools |
| `mcpe2e/README.md` | Flutter library API reference, HTTP endpoints |
| `mcpe2e_server/README.md` | MCP server setup, agent management, tool reference |
| `docs/integration-guide.md` | Step-by-step integration for any Flutter app |
| `docs/test-flow-example.md` | Complete test walkthroughs with coordinate-based approach |
