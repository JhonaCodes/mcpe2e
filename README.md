# mcpe2e — AI-driven Flutter E2E Testing

[![version](https://img.shields.io/badge/version-2.1.0-blue)](https://github.com/JhonaCodes/mcpe2e/releases/tag/v2.1.0)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

mcpe2e lets an AI agent (Claude, Codex, Gemini) control a real Flutter app running on a device or simulator. The agent calls MCP tools — tap, type, scroll, assert — and those commands reach the live widget tree as real pointer events.

No UI modifications needed. No test doubles. The app runs as-is.

---

## Architecture

```
User → AI Agent (Claude / Codex / Gemini)
              |
              |  MCP  (JSON-RPC 2.0 / stdio)
              v
      mcpe2e_server  (Dart binary)           installed in ~/.local/bin/
      Translates MCP tool calls → HTTP
      Exposes workflow skill via MCP Prompts
              |
              |  HTTP  localhost:7778
              |  (ADB forward / iproxy / direct)
              v
      mcpe2e  (Flutter library)              dev_dependency in the app
      HTTP server embedded inside the app
      Executes real pointer events via GestureBinding
              |
              v
      Flutter app on device / simulator
```

Two independent components:

| Component | What it is | Where it runs |
|-----------|------------|---------------|
| `mcpe2e` | Flutter library — HTTP server embedded in the app | Inside the device |
| `mcpe2e_server` | MCP server binary — bridges AI tools to HTTP | Developer's machine |

`mcpe2e` is **not** an MCP server. It is a lightweight HTTP server that lives inside the running app and executes gestures on the live widget tree.

---

## Zero-config approach

The primary testing workflow requires no widget registration:

1. Call `inspect_ui` — returns the full widget tree with coordinates (`x`, `y`, `w`, `h`) for every element.
2. Calculate center: `cx = x + w/2`, `cy = y + h/2`.
3. Call `tap_at x: <cx> y: <cy>` — taps at those coordinates.

No `McpMetadataKey`, no widget registry, no wrappers needed.

---

## Quick Start

### Step 1 — Add mcpe2e to your Flutter app

```yaml
# pubspec.yaml
dev_dependencies:
  mcpe2e:
    git:
      url: https://github.com/JhonaCodes/mcpe2e.git
      path: mcpe2e
      ref: v2.1.0
```

```bash
flutter pub get
```

### Step 2 — Install the MCP server and register your AI agents

```bash
dart run mcpe2e:setup
```

This single command:
1. Downloads the `mcpe2e_server` binary for your platform to `~/.local/bin/`
2. Opens an interactive menu to register it with your AI agents (Claude Code, Claude Desktop, Codex CLI, Gemini CLI)

To change agent registrations at any time:

```bash
mcpe2e_server setup
```

### Step 3 — Start the server in main.dart

```dart
import 'package:flutter/foundation.dart';
import 'package:mcpe2e/mcpe2e.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) await McpEventServer.start();
  runApp(const MyApp());
}
```

The server starts on port `7777` and is a no-op in release builds.

### Step 4 — Run the app

```bash
flutter run
```

`mcpe2e_server` automatically runs `adb forward` for every connected Android device when it starts — no manual port forwarding needed. For iOS, run `iproxy 7778 7777` once.

Verify the connection:

```bash
curl http://localhost:7778/ping
# {"status":"ok","port":7777}
```

### Step 5 — Load the workflow skill (optional but recommended)

Before starting any task, the AI agent can request the built-in workflow guide:

```
prompts/get { "name": "mcpe2e_workflow" }
```

This delivers a complete interaction guide — core loop, tool decision tree, patterns for forms/dialogs/navigation, error recovery, and agent protocol. Any MCP-compatible client (Claude, Gemini, Codex) can use it.

### Step 6 — Run your first test

With the app running, ask the AI agent:

```
inspect_ui
```

The agent receives the full widget tree with coordinates. Then:

```
tap_at x: 195 y: 420
```

Or by widget key if the widget has one registered:

```
tap_widget key: auth.login_button
```

---

## Available Tools (34)

### Multi-device

| Tool | Description |
|------|-------------|
| `list_devices` | Discover all connected Android devices/emulators, auto-forward ports, ping each one |
| `select_device` | Switch the active device by serial. All subsequent tools target the selected device |
| `run_command` | Run any shell command (`flutter run`, `adb`, etc.) with optional `working_dir` and `background` mode |

### Context and Inspection

| Tool | Description |
|------|-------------|
| `get_app_context` | Registered widgets with metadata and capabilities |
| `list_test_cases` | Alias for `get_app_context` |
| `inspect_ui` | Full widget tree with values, states, and screen coordinates — no registration needed |
| `inspect_ui_compact` | Grouped summary (INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING) — use on simple screens to save tokens |
| `capture_screenshot` | Current screen as PNG image — the agent sees it directly |

### Gestures

| Tool | Key parameters | Description |
|------|---------------|-------------|
| `tap_widget` | `key` | Single tap on a registered widget |
| `tap_at` | `x`, `y` | Tap at absolute screen coordinates |
| `double_tap_widget` | `key` | Double tap |
| `long_press_widget` | `key`, `duration_ms?` | Long press |
| `swipe_widget` | `key`, `direction`, `distance?` | Swipe in a direction |
| `scroll_widget` | `key`, `direction` | Scroll a scrollable widget |
| `scroll_until_visible` | `key`, `target_key`, `max_attempts?` | Scroll until a widget is visible |
| `drag_widget` | `key`, `dx`, `dy`, `duration_ms?` | Drag by pixel offset from center |
| `pinch_widget` | `key`, `scale` | Pinch zoom |
| `tap_by_label` | `label` | Tap by visible text content |

### Input

| Tool | Key parameters | Description |
|------|---------------|-------------|
| `input_text` | `x`, `y`, `text`, `clear_first?`, `skip_focus_tap?` | Type into a TextField. Use `x`/`y` from `inspect_ui` (preferred) or `key` |
| `clear_text` | `key` | Clear a TextField |
| `select_dropdown` | `key`, `value` or `index` | Select a dropdown option |
| `toggle_widget` | `key` | Toggle a Checkbox, Switch, or Radio |
| `set_slider_value` | `key`, `value` (0.0–1.0) | Set a Slider position |

### Keyboard and Navigation

| Tool | Key parameters | Description |
|------|---------------|-------------|
| `show_keyboard` | `key` | Request focus and show virtual keyboard |
| `hide_keyboard` | — | Dismiss the virtual keyboard |
| `press_back` | — | Navigate back — auto-taps the AppBar back button if visible, falls back to system Back event |
| `wait` | `duration_ms` | Pause execution (useful after animations or network calls) |

### Assertions

| Tool | Key parameters | Description |
|------|---------------|-------------|
| `assert_exists` | `key` | Widget is registered |
| `assert_text` | `key`, `text` | Visible text matches expected value |
| `assert_visible` | `key` | Widget is visible in the viewport |
| `assert_enabled` | `key` | Widget is enabled |
| `assert_selected` | `key` | Checkbox, Switch, or Radio is active |
| `assert_value` | `key`, `value` | TextField controller value matches |
| `assert_count` | `key`, `count` | List or column has exactly N children |

---

## Widget Keys (McpMetadataKey)

Widget keys are **optional**. The coordinate-based approach (`inspect_ui` → `tap_at`) works for any widget without touching the app code.

Keys give stable named access to specific widgets — useful for assertions and test scripts that run repeatedly.

### How to register a widget key

```dart
import 'package:mcpe2e/mcpe2e.dart';

// Button
ElevatedButton(
  key: const McpMetadataKey(id: 'auth.login_button'),
  onPressed: _login,
  child: const Text('Log in'),
)

// Text field
TextField(
  key: const McpMetadataKey(id: 'auth.email_field'),
  controller: _emailController,
)

// Checkbox
Checkbox(
  key: const McpMetadataKey(id: 'settings.dark_mode'),
  value: _darkMode,
  onChanged: _toggle,
)

// List (for assert_count)
ListView(
  key: const McpMetadataKey(id: 'order.list'),
  children: _items.map(_buildItem).toList(),
)
```

Once registered, the widget appears in `inspect_ui` with a `"key"` field. You can then use key-based tools:

```
tap_widget     key: auth.login_button
input_text     key: auth.email_field    text: "user@example.com"
assert_text    key: auth.email_field    text: "user@example.com"
assert_enabled key: auth.login_button
assert_count   key: order.list         count: 5
```

### Key naming convention

Follow the `module.element[.variant]` pattern:

```
auth.login_button          Login button on the auth screen
auth.email_field           Email input on the auth screen
profile.avatar             User avatar image
order.list                 The orders list
order.card.{id}            A dynamic card identified at runtime
settings.dark_mode         Dark mode toggle
modal.confirm.delete       Confirmation dialog
sheet.address.submit       Submit button inside a bottom sheet
nav.drawer                 Navigation drawer
snackbar.undo              Undo action in a snackbar
```

### When to use keys vs coordinates

| Situation | Recommendation |
|-----------|---------------|
| One-off task or exploration | Coordinates (`inspect_ui` → `tap_at`) |
| Repeated test script | Key — more stable across screen rebuilds |
| Dialog / bottom sheet / drawer | Key recommended — overlay coords shift during open animation |
| Dynamic list items | Coordinates or `order.card.{id}` with runtime ID |
| Assertions in CI | Key — decoupled from layout |

### Recommended: add keys to overlaid widgets

The coordinate-based approach works for most of the app. However, we recommend adding `McpMetadataKey` to widgets that appear as layers on top of the main screen — dialogs, bottom sheets, drawers, and snackbars. Their coordinates can shift during the open animation, making `tap_at` less reliable.

```dart
// Confirmation dialog
AlertDialog(
  key: const McpMetadataKey(id: 'modal.confirm.delete'),
  title: const Text('Delete item?'),
  actions: [
    TextButton(
      key: const McpMetadataKey(id: 'modal.confirm.cancel'),
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel'),
    ),
    ElevatedButton(
      key: const McpMetadataKey(id: 'modal.confirm.ok'),
      onPressed: _delete,
      child: const Text('Delete'),
    ),
  ],
)

// Bottom sheet action button
showModalBottomSheet(
  context: context,
  builder: (_) => ElevatedButton(
    key: const McpMetadataKey(id: 'sheet.checkout.submit'),
    onPressed: _submit,
    child: const Text('Confirm'),
  ),
);

// Navigation drawer
Drawer(
  key: const McpMetadataKey(id: 'nav.drawer'),
  child: ...,
)

// Snackbar action
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    action: SnackBarAction(
      key: const McpMetadataKey(id: 'snackbar.undo'),
      label: 'Undo',
      onPressed: _undo,
    ),
  ),
);
```

This is a suggestion, not a requirement. The agent can still interact with these widgets using `tap_at` and coordinates from `inspect_ui`.

---

## Route Tracking (McpNavigatorObserver)

`get_app_context` reports the current route. For accurate route names, register the observer:

```dart
// With MaterialApp
MaterialApp(
  navigatorObservers: [McpNavigatorObserver.instance],
  ...
)

// With GoRouter
GoRouter(
  observers: [McpNavigatorObserver.instance],
  ...
)
```

Without it, the route falls back to a value derived from the screen name.

---

## Text Input in Dialogs

When a dialog or overlay blocks the focus tap, use the ADB fallback:

```
// 1. Focus the field
tap_at x: <field cx> y: <field cy>

// 2. Type via ADB (run_command)
run_command: adb -s <SERIAL> shell input text "your_text"

// Get the serial from:
run_command: adb devices
```

This works for auth codes, PINs, and any `TextField` inside an `AlertDialog` or `BottomSheet`.

---

## Managing Agents

```bash
mcpe2e_server setup
```

Interactive menu to enable or disable individual agents (Claude Code, Claude Desktop, Codex CLI, Gemini CLI) without reinstalling.

---

## Platform Connectivity

| Platform | Mechanism | Setup |
|----------|-----------|-------|
| Android | ADB forward (automatic) | None — `mcpe2e_server` handles it on startup |
| iOS | iproxy | `iproxy 7778 7777` |
| macOS / Linux / Windows desktop | Direct localhost | Set `TESTBRIDGE_URL=http://localhost:7777` |
| Web | Not supported | Flutter Web cannot open TCP sockets |

`TESTBRIDGE_URL` tells `mcpe2e_server` where to reach the app. Default: `http://localhost:7778`.

---

## Repository Structure

```
mcpe2e/              Flutter library — add to your app as dev_dependency
mcpe2e_server/       MCP server binary — install once on your machine
docs/                Integration guides and examples
CLAUDE.md            Architecture reference for Claude Code context
```

---

## Documentation

| File | Description |
|------|-------------|
| `mcpe2e/README.md` | Flutter library reference (endpoints, API, production safety) |
| `mcpe2e_server/README.md` | MCP server setup, configuration, and tool reference |
| `docs/integration-guide.md` | Step-by-step integration for any Flutter app |
| `docs/test-flow-example.md` | Complete test walkthrough |
| `docs/writing-tests.md` | Script mode and goal mode test formats, templates |
| `CLAUDE.md` | Architecture reference for Claude Code context |

---

## Building from Source

```bash
git clone https://github.com/JhonaCodes/mcpe2e
cd mcpe2e/mcpe2e_server
dart pub get
dart compile exe bin/mcp_server.dart -o mcpe2e_server
```

Requires Dart SDK >= 3.5.0. Precompiled binaries for macOS (arm64, x86_64), Linux (x86_64), and Windows (x86_64) are available on every [GitHub Release](https://github.com/JhonaCodes/mcpe2e/releases).
