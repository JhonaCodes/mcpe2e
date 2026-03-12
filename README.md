# mcpe2e — AI-driven Flutter E2E Testing

[![version](https://img.shields.io/badge/version-2.2.0-blue)](https://github.com/JhonaCodes/mcpe2e/releases/tag/v2.2.0)
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

## How it works — three ways to find widgets

The agent resolves widgets in this priority order:

### 1. McpMetadataKey (recommended)

Register keys on your widgets for the most reliable, stable access. This is the **default and recommended approach** — it gives the agent named access to widgets, enables assertions, and survives layout changes.

```dart
ElevatedButton(
  key: const McpMetadataKey(id: 'auth.login_button', widgetType: McpWidgetType.button),
  onPressed: _login,
  child: const Text('Log in'),
)
```

```
AI calls: tap_widget  key: auth.login_button
AI calls: assert_enabled  key: auth.login_button
```

### 2. Existing Flutter keys (automatic)

If your app already uses `ValueKey<String>` or other Flutter keys, the agent picks them up automatically from `inspect_ui` — no changes needed. These appear in the tree with their key value:

```json
{ "type": "ElevatedButton", "key": "login_btn", "label": "Login", "x": 20, "y": 400 }
```

```
AI calls: tap_widget  key: login_btn
```

### 3. Coordinates (fallback)

When a widget has no key at all, the agent falls back to screen coordinates from `inspect_ui`. This requires no app code changes but is less stable across layout rebuilds.

```json
{ "type": "ElevatedButton", "label": "Login", "x": 20, "y": 400, "w": 350, "h": 52 }
```

```
Center: cx = 20 + 350/2 = 195,  cy = 400 + 52/2 = 426

AI calls: tap_at  x: 195  y: 426
AI calls: input_text  x: 16  y: 220  text: "user@example.com"
```

This works for **any widget** in the tree — buttons, cards, list items, tabs, dropdowns — without touching the app source code.

---

## Quick Start

### Step 1 — Add mcpe2e to your Flutter app

```yaml
# pubspec.yaml
dev_dependencies:
  mcpe2e: ^2.2.0
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

With the app running and the agent connected, a typical test looks like this:

**With McpMetadataKey (recommended):**

```
1. inspect_ui                                        → see all widgets
2. input_text  key: auth.email_field  text: "user@example.com"
3. input_text  key: auth.password_field  text: "secret123"
4. tap_widget  key: auth.login_button
5. wait  duration_ms: 1500
6. assert_text  key: dashboard.greeting  text: "Hello, user"
```

**Without keys (coordinate fallback):**

```
1. inspect_ui
   → Agent sees: TextField "Email" at (16, 220), ElevatedButton "Login" at (20, 400, 350x52)
2. input_text  x: 16  y: 220  text: "user@example.com"
3. input_text  x: 16  y: 296  text: "secret123"
4. tap_at  x: 195  y: 426                           → center of Login button
5. wait  duration_ms: 1500
6. inspect_ui                                        → verify new screen content
```

Both approaches work. Keys give stability and enable assertions; coordinates require no app changes.

---

## Available Tools (34)

> Most tools use `key` — a `McpMetadataKey` id or existing Flutter key. See [Widget Keys](#widget-keys-mcpmetadatakey).
> When no key is available, use coordinate-based tools (`tap_at`, `tap_by_label`, `input_text(x, y)`) as fallback.

### Multi-device

| Tool | Parameters | Description |
|------|-----------|-------------|
| `list_devices` | — | Discover all connected Android devices/emulators, auto-forward ports, ping each one |
| `select_device` | `serial` | Switch the active device by serial. All subsequent tools target the selected device |
| `run_command` | `command`, `working_dir?`, `background?` | Run any shell command (`flutter run`, `adb`, etc.) |

### Context and Inspection

| Tool | Parameters | Description |
|------|-----------|-------------|
| `get_app_context` | — | Registered widgets with metadata and capabilities |
| `list_test_cases` | — | Alias for `get_app_context` |
| `inspect_ui` | — | Full widget tree with values, states, and screen coordinates — **no registration needed** |
| `inspect_ui_compact` | — | Grouped summary (INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING) — saves tokens on simple screens |
| `capture_screenshot` | — | Current screen as PNG image — the agent sees it directly |

### Gestures

| Tool | Parameters | Key | Description |
|------|-----------|-----|-------------|
| `tap_widget` | `key` | Required | Tap a widget by key — **recommended** |
| `double_tap_widget` | `key` | Required | Double tap |
| `long_press_widget` | `key`, `duration_ms?` | Required | Long press |
| `swipe_widget` | `key`, `direction`, `distance?` | Required | Swipe in a direction |
| `scroll_widget` | `key`, `direction` | Required | Scroll a scrollable widget |
| `scroll_until_visible` | `key`, `target_key`, `max_attempts?` | Required | Scroll until a target widget is visible |
| `drag_widget` | `key`, `dx`, `dy`, `duration_ms?` | Required | Drag by pixel offset from center |
| `pinch_widget` | `key`, `scale` | Required | Pinch zoom |
| `tap_at` | `x`, `y` | — | Tap at screen coordinates (fallback when no key available) |
| `tap_by_label` | `label` | — | Tap by visible text content (e.g. `"Login"`, `"Submit"`) |

### Input

| Tool | Parameters | Key | Description |
|------|-----------|-----|-------------|
| `input_text` | `key`, `text`, `clear_first?` | Required | Type into a TextField by key — **recommended** |
| `input_text` | `x`, `y`, `text`, `clear_first?`, `skip_focus_tap?` | — | Type into a TextField by coordinates (fallback) |
| `clear_text` | `key` | Required | Clear a TextField |
| `select_dropdown` | `key`, `value` or `index` | Required | Select a dropdown option |
| `toggle_widget` | `key` | Required | Toggle a Checkbox, Switch, or Radio |
| `set_slider_value` | `key`, `value` (0.0–1.0) | Required | Set a Slider position |

### Keyboard and Navigation

| Tool | Parameters | Description |
|------|-----------|-------------|
| `show_keyboard` | `key` | Request focus and show virtual keyboard |
| `hide_keyboard` | — | Dismiss the virtual keyboard |
| `press_back` | — | Navigate back — auto-taps the AppBar back button if visible, falls back to system Back event |
| `wait` | `duration_ms` | Pause execution (useful after animations or network calls) |

### Assertions (require registered keys)

| Tool | Parameters | Description |
|------|-----------|-------------|
| `assert_exists` | `key` | Widget is in the tree |
| `assert_text` | `key`, `text` | Visible text matches expected value |
| `assert_visible` | `key` | Widget is visible in the viewport |
| `assert_enabled` | `key` | Widget is enabled |
| `assert_selected` | `key` | Checkbox, Switch, or Radio is active |
| `assert_value` | `key`, `value` | TextField controller value matches |
| `assert_count` | `key`, `count` | List or column has exactly N children |

> **Without keys**, the agent can still verify values by reading the `inspect_ui` response directly — every Text widget's content, every button's enabled state, and every checkbox's checked state are included in the tree. However, for formal test assertions, register a `McpMetadataKey` on the widget.

---

## Widget Keys (McpMetadataKey)

`McpMetadataKey` is the **recommended** way to identify widgets. Registering keys gives:

- **Stable named access** — survives layout changes and screen rebuilds
- **Assertions** — `assert_text`, `assert_enabled`, `assert_selected`, etc. require a key
- **Reliable overlay interaction** — dialogs, bottom sheets, drawers shift during animation; keys bypass that
- **Faster lookup** — direct access instead of tree walk

If your app already uses `ValueKey<String>`, the agent picks those up automatically from `inspect_ui` — no changes needed.

If a widget has no key at all, the agent falls back to coordinate-based tools (`tap_at`, `input_text(x, y)`). This works but is less stable.

### How to add a key

Assign a `McpMetadataKey` as the widget's `key:`. Both `id` and `widgetType` are required:

```dart
import 'package:mcpe2e/mcpe2e.dart';

// Button
ElevatedButton(
  key: const McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
  ),
  onPressed: _login,
  child: const Text('Log in'),
)

// Text field
TextField(
  key: const McpMetadataKey(
    id: 'auth.email_field',
    widgetType: McpWidgetType.textField,
  ),
  controller: _emailController,
)

// Checkbox
Checkbox(
  key: const McpMetadataKey(
    id: 'settings.dark_mode',
    widgetType: McpWidgetType.checkbox,
  ),
  value: _darkMode,
  onChanged: _toggle,
)

// List (for assert_count)
ListView(
  key: const McpMetadataKey(
    id: 'order.list',
    widgetType: McpWidgetType.list,
  ),
  children: _items.map(_buildItem).toList(),
)
```

Once a key is assigned, the widget appears in `inspect_ui` with a `"key"` field. The agent can then use key-based tools:

```
tap_widget     key: auth.login_button
input_text     key: auth.email_field    text: "user@example.com"
assert_text    key: auth.email_field    text: "user@example.com"
assert_enabled key: auth.login_button
assert_count   key: order.list          count: 5
```

### McpWidgetType values

`widgetType` describes the widget kind and determines its available capabilities:

`button` · `textField` · `text` · `list` · `card` · `image` · `container` · `dropdown` · `checkbox` · `radio` · `switchWidget` · `slider` · `tab` · `custom`

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

### Resolution priority

The agent resolves widgets in this order:

| Priority | Method | When to use |
|----------|--------|-------------|
| 1st | **McpMetadataKey** | Default for all testable widgets. Enables assertions, stable across rebuilds |
| 2nd | **Existing Flutter key** (`ValueKey<String>`, etc.) | App already has keys — no changes needed |
| 3rd | **Coordinates** (`tap_at`, `input_text(x, y)`) | Fallback for widgets without any key — dynamic lists, third-party widgets, quick exploration |

### When each approach fits

| Scenario | Approach |
|----------|----------|
| Any widget you control | `McpMetadataKey` — register it once, use it everywhere |
| App already has `ValueKey` on widgets | Use them as-is — the agent sees them in `inspect_ui` |
| Assertions (`assert_text`, `assert_enabled`, etc.) | Key **required** — assertions only work with keys |
| Dialog / bottom sheet / drawer / snackbar | Key **strongly recommended** — overlay coordinates shift during animation |
| Dynamic list items from API | `order.card.{id}` with runtime ID, or coordinates as fallback |
| Third-party widgets you can't modify | Coordinates via `inspect_ui` → `tap_at` |
| Quick one-off exploration | Coordinates — fast, no code changes |

### Recommended: add keys to overlaid widgets

Dialogs, bottom sheets, drawers, and snackbars are rendered in a separate overlay layer. Their coordinates can shift during the open animation, making `tap_at` less reliable. Adding a `McpMetadataKey` to these surfaces lets the agent use `tap_widget` instead of chasing coordinates.

```dart
// Confirmation dialog actions
AlertDialog(
  title: const Text('Delete item?'),
  actions: [
    TextButton(
      key: const McpMetadataKey(
        id: 'modal.confirm.cancel',
        widgetType: McpWidgetType.button,
      ),
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel'),
    ),
    ElevatedButton(
      key: const McpMetadataKey(
        id: 'modal.confirm.ok',
        widgetType: McpWidgetType.button,
      ),
      onPressed: _delete,
      child: const Text('Delete'),
    ),
  ],
)

// Bottom sheet action button
showModalBottomSheet(
  context: context,
  builder: (_) => ElevatedButton(
    key: const McpMetadataKey(
      id: 'sheet.checkout.submit',
      widgetType: McpWidgetType.button,
    ),
    onPressed: _submit,
    child: const Text('Confirm'),
  ),
);
```

Without keys, the agent can still interact with overlay widgets using `tap_at` after calling `inspect_ui` — but it may need a `wait` to let the animation finish, and coordinates may shift between runs.

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
