# mcpe2e — AI-driven Flutter E2E Testing

Let Claude control a real Flutter app on a device: tap, type, scroll, assert — all through natural language.

```
Claude Code / Claude Desktop
    │
    │  MCP (JSON-RPC 2.0 / stdio)
    ▼
┌─────────────────────────────────────┐
│  mcpe2e_server  (Dart CLI)          │  MCP Server — 29 tools
│  Translates MCP tool calls → HTTP   │  Installed once on developer's machine
└────────────────┬────────────────────┘
                 │  HTTP  localhost:7778
                 │  (ADB forward / iproxy / direct)
                 ▼
┌─────────────────────────────────────┐
│  mcpe2e  (Flutter library)          │  Runs INSIDE the app on the device
│  HTTP server on :7777               │  Executes real gestures on the
│  29 event types                     │  live widget tree
│  Zero-intrusion UI inspection       │
└─────────────────────────────────────┘
```

> **Important distinction:**
> - `mcpe2e` is a **Flutter library** — added to your app as a `dev_dependency`
> - `mcpe2e_server` is a **CLI tool** — installed once on your machine, registered with Claude

---

## Repository Structure

```
mcpe2e/                 Flutter library — add to your app
mcpe2e_server/          Dart CLI/MCP server — install on your machine
docs/                   Integration guides and examples
CLAUDE.md               Architecture reference for Claude
.github/workflows/      CI — builds mcpe2e_server binaries for all platforms
```

---

## Quick Start

### Step 1 — Add mcpe2e to your Flutter app

```yaml
# pubspec.yaml
dev_dependencies:
  mcpe2e:
    git:
      url: https://github.com/JhonaCodes/mcpe2e
      path: mcpe2e
```

### Step 2 — Initialize the server in your app

```dart
import 'package:flutter/foundation.dart';
import 'package:mcpe2e/mcpe2e.dart';

// Define keys for your widgets
const loginButton = McpMetadataKey(
  id: 'auth.login_button',
  widgetType: McpWidgetType.button,
  description: 'Login submit button',
  screen: 'LoginScreen',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register widgets and start the HTTP server (debug/profile only)
  if (kDebugMode || kProfileMode) {
    McpEvents.instance.registerWidget(loginButton);
    await McpEventServer.start(); // listens on :7777
  }

  runApp(const MyApp());
}

// Assign the key directly to the widget
ElevatedButton(
  key: loginButton,
  onPressed: _handleLogin,
  child: const Text('Login'),
)
```

The server **starts automatically** when the app launches and **stops automatically** when the app closes.

### Step 3 — Install mcpe2e_server on your machine

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.ps1 | iex
```

**Manual download** — pick your platform from [Releases](https://github.com/JhonaCodes/mcpe2e/releases/latest):

| Platform | Binary |
|---|---|
| macOS Apple Silicon (M1/M2/M3/M4) | `mcpe2e_server-macos-arm64` |
| macOS Intel | `mcpe2e_server-macos-x86_64` |
| Linux x86_64 | `mcpe2e_server-linux-x86_64` |
| Windows x86_64 | `mcpe2e_server.exe` |

### Step 4 — Connect the device

```bash
# Android — forward device port 7777 to localhost 7778
adb forward tcp:7778 tcp:7777

# iOS — requires usbmuxd (brew install usbmuxd)
iproxy 7778 7777

# Desktop — no forwarding needed, use port 7777 directly
```

Verify the connection:
```bash
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}
```

### Step 5 — Register with Claude

**Claude Code**
```bash
claude mcp add mcpe2e \
  --command ~/.local/bin/mcpe2e_server \
  --env TESTBRIDGE_URL=http://localhost:7778
```

**Claude Desktop** — add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "mcpe2e": {
      "command": "/Users/you/.local/bin/mcpe2e_server",
      "env": { "TESTBRIDGE_URL": "http://localhost:7778" }
    }
  }
}
```

Now tell Claude: *"tap the login button"*, *"type 'hello' in the email field"*, *"verify the error message says..."*

---

## Available Tools (29)

### Context & Inspection
| Tool | Description |
|---|---|
| `get_app_context` | Registered widgets with metadata and capabilities |
| `list_test_cases` | Alias for get_app_context |
| `inspect_ui` | **Full widget tree** with values/states — no registration needed |
| `capture_screenshot` | **Current screen as image** — Claude sees it directly |

### Gestures
| Tool | Parameters | Description |
|---|---|---|
| `tap_widget` | `key` | Single tap |
| `double_tap_widget` | `key` | Double tap |
| `long_press_widget` | `key`, `duration_ms?` | Long press |
| `swipe_widget` | `key`, `direction`, `distance?` | Swipe in a direction |
| `scroll_widget` | `key`, `direction` | Scroll a list |
| `scroll_until_visible` | `key`, `target_key`, `max_attempts?` | Scroll until widget is visible |
| `drag_widget` | `key`, `dx`, `dy`, `duration_ms?` | Drag by pixel offset |
| `pinch_widget` | `key`, `scale` | Pinch zoom *(stub — not yet implemented)* |
| `tap_by_label` | `label` | Tap by visible text |

### Input
| Tool | Parameters | Description |
|---|---|---|
| `input_text` | `key`, `text`, `clear_first?` | Type into a TextField |
| `clear_text` | `key` | Clear a TextField |
| `select_dropdown` | `key`, `value` or `index` | Select dropdown option |
| `toggle_widget` | `key` | Toggle Checkbox / Switch / Radio |
| `set_slider_value` | `key`, `value` (0.0–1.0) | Set Slider position |

### Keyboard & Navigation
| Tool | Parameters | Description |
|---|---|---|
| `show_keyboard` | `key` | Show virtual keyboard |
| `hide_keyboard` | — | Dismiss virtual keyboard |
| `press_back` | `key` | Navigate back |
| `wait` | `duration_ms` | Pause execution |

### Assertions
| Tool | Parameters | Description |
|---|---|---|
| `assert_exists` | `key` | Widget is registered |
| `assert_text` | `key`, `text` | Visible text matches |
| `assert_visible` | `key` | Widget is fully visible |
| `assert_enabled` | `key` | Widget is enabled |
| `assert_selected` | `key` | Checkbox/Switch/Radio is active |
| `assert_value` | `key`, `value` | TextField value matches |
| `assert_count` | `key`, `count` | List has exactly N children |

---

## Widget ID Convention

```
module.element[.variant]

auth.login_button         Login button
auth.email_field          Email text field
order.form.price          Price field inside an order form
order.card.{uuid}         Dynamic card identified at runtime
settings.dark_mode        Dark mode toggle
```

---

## Key Concepts

### McpMetadataKey
Extends Flutter's `Key` — assign it directly to any widget. No wrapper widgets needed.

```dart
const myKey = McpMetadataKey(
  id: 'module.element',          // unique ID used by Claude
  widgetType: McpWidgetType.button,
  description: 'What this widget does',
  screen: 'ScreenName',
);

// Use it like any Flutter Key:
ElevatedButton(key: myKey, ...)
```

### inspect_ui — zero-registration inspection
Claude can see ALL widgets on screen without any registration:
```
inspect_ui → returns every Text, TextField, Button, Checkbox, Switch,
             Slider, AppBar, Dialog, SnackBar with their current values,
             states, and screen coordinates
```

### capture_screenshot — visual verification
Claude receives a real PNG screenshot and can describe what it sees. Only works in debug/profile mode.

### Auto lifecycle
The HTTP server starts with `McpEventServer.start()` and stops automatically when the app is closed via `WidgetsBindingObserver`. No manual cleanup needed.

### Production safety
- `McpEventServer.start()` is a no-op in release builds
- `capture_screenshot` returns `{"error":"not_available_in_release"}` in release
- The server never starts unless explicitly called

---

## TESTBRIDGE_URL

| Scenario | Value |
|---|---|
| Android via ADB forward | `http://localhost:7778` |
| iOS via iproxy | `http://localhost:7778` |
| Desktop (same machine) | `http://localhost:7777` |

---

## Documentation

| File | Description |
|---|---|
| `mcpe2e/README.md` | Flutter library API reference |
| `mcpe2e_server/README.md` | MCP server setup and tool reference |
| `docs/integration-guide.md` | Step-by-step integration for any Flutter app |
| `docs/test-flow-example.md` | Complete test walkthrough with Claude |
| `CLAUDE.md` | Architecture reference (for Claude Code context) |

---

## Building mcpe2e_server from Source

```bash
git clone https://github.com/JhonaCodes/mcpe2e
cd mcpe2e/mcpe2e_server
dart pub get
dart compile exe bin/mcp_server.dart -o mcpe2e_server
```

Requires Dart SDK ≥ 3.5.0.

Pre-compiled binaries for all platforms are available on every [GitHub Release](https://github.com/JhonaCodes/mcpe2e/releases).
