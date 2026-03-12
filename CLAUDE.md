# mcpe2e — AI-driven Flutter E2E Testing

Claude controls a real Flutter app on a device: tap, type, scroll, assert — using MCP tools.

## Architecture

```
Claude Code / Claude Desktop / Codex CLI / Gemini CLI
    │
    │  MCP (JSON-RPC 2.0 / stdio)
    ▼
┌─────────────────────────────────┐
│  mcpe2e_server  (Dart)          │  MCP Server — 34 tools
│  Translates MCP tools → HTTP    │  Installed in ~/.local/bin/
│  Binary: bin/mcp_server.dart    │  TESTBRIDGE_URL=http://localhost:7778
└────────────────┬────────────────┘
                 │  HTTP REST
                 │  localhost:7778 → (ADB/iproxy) → device:7777
                 ▼
┌─────────────────────────────────┐
│  mcpe2e  (Dart / Flutter lib)   │  Runs INSIDE the Flutter app
│  HTTP server on :7777           │  Executes real gestures on the
│  34 event types                 │  live widget tree on the device
│  Full widget tree inspection    │
└─────────────────────────────────┘
```

## Two independent components

| Component | What it is | Location |
|-----------|------------|----------|
| **mcpe2e** | Flutter library — HTTP server embedded in the app | `./mcpe2e/` |
| **mcpe2e_server** | MCP server binary — translates MCP tools to HTTP calls | `./mcpe2e_server/` |

`mcpe2e` is **not** an MCP server. It is an HTTP server that runs inside the device and executes real gestures on the app's widget tree.

## Widget resolution priority

The agent resolves widgets in this order:

1. **McpMetadataKey** (recommended) — register keys on widgets for stable, named access. Enables assertions (`assert_text`, `assert_enabled`, etc.).
2. **Existing Flutter keys** (`ValueKey<String>`) — picked up automatically from `inspect_ui`.
3. **Coordinates** (fallback) — `inspect_ui` returns `x`, `y`, `w`, `h` for every element. Use `tap_at` / `input_text(x, y)` when no key is available.

```
McpMetadataKey → tap_widget key: auth.login_button        (recommended)
ValueKey       → tap_widget key: login_btn                (automatic)
Coordinates    → tap_at x: 195 y: 426                     (fallback)
```

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

Android port forwarding is automatic — `mcpe2e_server` runs `adb forward` for every connected device at startup. No manual step needed.

```bash
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

## MCP Tools (34 total)

**Multi-device:** `list_devices`, `select_device`, `run_command`

**Context:** `get_app_context`, `list_test_cases`, `inspect_ui`, `inspect_ui_compact`, `capture_screenshot`

**Gestures:** `tap_widget`, `tap_at`, `double_tap_widget`, `long_press_widget`, `swipe_widget`, `scroll_widget`, `scroll_until_visible`, `drag_widget`, `pinch_widget`, `tap_by_label`

**Input:** `input_text`, `clear_text`, `select_dropdown`, `toggle_widget`, `set_slider_value`

**Keyboard/Navigation:** `show_keyboard`, `hide_keyboard`, `press_back`, `wait`

**Assertions:** `assert_exists`, `assert_text`, `assert_visible`, `assert_enabled`, `assert_selected`, `assert_value`, `assert_count`

## Platform connectivity

| Platform | Command | URL |
|----------|---------|-----|
| Android | Automatic (ADB forward on startup) | `http://localhost:7778` |
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
| `README.md` | Overview, quick start, all 34 tools |
| `mcpe2e/README.md` | Flutter library API reference, HTTP endpoints |
| `mcpe2e_server/README.md` | MCP server setup, agent management, tool reference |
| `docs/integration-guide.md` | Step-by-step integration for any Flutter app |
| `docs/test-flow-example.md` | Complete test walkthroughs with coordinate-based approach |
| `docs/writing-tests.md` | Script mode and goal mode test formats, templates |
