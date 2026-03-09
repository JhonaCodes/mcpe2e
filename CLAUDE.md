# mcpe2e — AI-driven Flutter E2E Testing

Claude controls a real Flutter app on a device: tap, type, scroll, assert — using MCP tools.

## Architecture

```
Claude Code / Claude Desktop
    │
    │  MCP (JSON-RPC 2.0 / stdio)
    ▼
┌─────────────────────────────────┐
│  mcpe2e_server  (Dart)          │  MCP Server — 29 tools
│  Translates MCP tools → HTTP    │  Binary: bin/server.dart
│  Connects to the app via HTTP   │  TESTBRIDGE_URL=http://localhost:7778
└────────────────┬────────────────┘
                 │  HTTP REST
                 │  localhost:7778 → (forwarding) → device:7777
                 ▼
┌─────────────────────────────────┐
│  mcpe2e  (Dart / Flutter lib)   │  Runs INSIDE the Flutter app
│  HTTP server on :7777           │  Executes real gestures on the
│  25 event types                 │  live widget tree on the device
│  Zero-intrusion UI inspection   │
└─────────────────────────────────┘
```

## Two independent components

| Component | What it is | Protocol | Location |
|-----------|------------|----------|----------|
| **mcpe2e** | Flutter library — HTTP server embedded in the app | HTTP (receives commands) | `./mcpe2e/` |
| **mcpe2e_server** | MCP server — translates MCP tools to HTTP calls | MCP stdio + HTTP (sends commands) | `./mcpe2e_server/` |

> `mcpe2e` is **not** an MCP server. It is an HTTP server that runs inside the device and executes real gestures on the app's widget tree.

## Quick Start

### 1. Add mcpe2e to your Flutter app

```yaml
# pubspec.yaml (dev_dependencies)
dev_dependencies:
  mcpe2e:
    path: /path/to/mcpe2e
```

### 2. Register widgets and start the server

```dart
import 'package:mcpe2e/mcpe2e.dart';
import 'package:flutter/foundation.dart';

// McpMetadataKey extends Key — use it directly on the widget
const loginEmail = McpMetadataKey(
  id: 'auth.email_field',
  widgetType: McpWidgetType.textField,
  description: 'Email input on login screen',
  screen: 'LoginScreen',
);

const loginButton = McpMetadataKey(
  id: 'auth.login_button',
  widgetType: McpWidgetType.button,
  description: 'Login submit button',
  screen: 'LoginScreen',
);

void initE2E() {
  if (!kDebugMode && !kProfileMode) return;
  McpEvents.instance.registerWidget(loginEmail);
  McpEvents.instance.registerWidget(loginButton);
  McpEventServer.start(); // listens on :7777
}

// Use the key directly on the widget
ElevatedButton(
  key: loginButton,
  onPressed: _handleLogin,
  child: const Text('Login'),
)
```

### 3. Connect the device

```bash
# Android: ADB forward
adb forward tcp:7778 tcp:7777

# Verify
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}
```

### 4. Start mcpe2e_server and register with Claude

```bash
cd mcpe2e_server
dart compile exe bin/server.dart -o mcpe2e

# Register with Claude Code
claude mcp add mcpe2e \
  --command /path/to/mcpe2e_server/mcpe2e \
  --env TESTBRIDGE_URL=http://localhost:7778
```

### 5. Use from Claude

```
get_app_context          → see registered widgets on screen
inspect_ui               → see ALL widgets with values (no registration needed)
capture_screenshot       → view the screen as an image
tap_widget               → real tap on a widget
input_text               → type in a text field
assert_text              → verify visible text
```

## Platform connectivity

| Platform | Mechanism | Command |
|----------|-----------|---------|
| Android | ADB forward | `adb forward tcp:7778 tcp:7777` |
| iOS | iproxy | `iproxy 7778 7777` |
| Desktop (macOS/Linux/Win) | Direct localhost | No setup — use `TESTBRIDGE_URL=http://localhost:7777` |
| Web | Not supported | Flutter Web cannot open TCP sockets |

`McpConnectivity.setup()` configures forwarding automatically when `McpEventServer.start()` is called.

## MCP Tools (29 total)

### Context & inspection

| Tool | Description | HTTP |
|------|-------------|------|
| `get_app_context` | Registered widgets with metadata and capabilities | `GET /mcp/context` |
| `list_test_cases` | Alias for get_app_context | `GET /mcp/context` |
| `inspect_ui` | Full widget tree with values/states (no registration needed) | `GET /mcp/tree` |
| `capture_screenshot` | Current screen as PNG image (debug/profile only) | `GET /mcp/screenshot` |

### Gestures

| Tool | Description |
|------|-------------|
| `tap_widget` | Single tap |
| `double_tap_widget` | Double tap |
| `long_press_widget` | Long press |
| `swipe_widget` | Swipe (up/down/left/right) |
| `scroll_widget` | Scroll a list |
| `scroll_until_visible` | Scroll until a widget is visible |
| `drag_widget` | Drag by dx/dy pixel offset from center |
| `pinch_widget` | Pinch zoom (stub — not yet implemented) |
| `tap_by_label` | Tap by visible text label |

### Input

| Tool | Description |
|------|-------------|
| `input_text` | Type into a TextField |
| `clear_text` | Clear a TextField |
| `select_dropdown` | Select a DropdownButtonFormField option |
| `toggle_widget` | Toggle Checkbox / Switch / Radio |
| `set_slider_value` | Set Slider position (0.0–1.0) |

### Keyboard & navigation

| Tool | Description |
|------|-------------|
| `show_keyboard` | Show virtual keyboard (request focus) |
| `hide_keyboard` | Dismiss the virtual keyboard |
| `press_back` | Navigate back |
| `wait` | Pause execution (useful after animations) |

### Assertions

| Tool | Description |
|------|-------------|
| `assert_exists` | Widget is registered |
| `assert_text` | Visible text matches |
| `assert_visible` | Widget is visible in viewport |
| `assert_enabled` | Widget is enabled |
| `assert_selected` | Checkbox/Switch/Radio is active |
| `assert_value` | TextField controller value matches |
| `assert_count` | Column/Row/ListView has exactly N children |

## Widget ID convention

```
module.element[.variant]

auth.login_button           Login button
auth.email_field            Email input
order.form.price            Price field inside a form
order.card.{uuid}           Dynamic card with runtime ID
state.loading_indicator     Loading state indicator
screen.dashboard            Screen identifier
modal.confirm.delete        Modal / dialog
```

## HTTP Endpoints (mcpe2e Flutter library)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ping` | GET | Health check — `{"status":"ok","port":7777}` |
| `/mcp/context` | GET | Registered widgets with metadata |
| `/mcp/tree` | GET | Full widget tree (no registration needed) |
| `/mcp/screenshot` | GET | Screen as PNG base64 |
| `/action?key=...&type=...` | GET | Execute event via query params |
| `/event` | POST | Execute event via JSON body |
| `/widgets` | GET | List widget IDs (`?metadata=true` for full context) |

## Production safety

- `McpEventServer.start()` returns immediately if not in debug/profile mode
- `capture_screenshot` returns `{"error":"not_available_in_release"}` in release builds
- The server never starts unless explicitly called with `start()`

## Documentation

- `docs/integration-guide.md` — Step-by-step integration for any Flutter app
- `docs/test-flow-example.md` — Complete test walkthrough with Claude
- `mcpe2e/README.md` — Flutter library API reference
- `mcpe2e_server/` — MCP server (see `pubspec.yaml` and `bin/server.dart`)
