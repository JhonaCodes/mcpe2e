# mcpe2e — AI-driven Flutter E2E Testing

[![version](https://img.shields.io/badge/version-1.1.6-blue)](https://github.com/JhonaCodes/mcpe2e/releases/tag/v1.1.6)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

mcpe2e lets an AI agent (Claude, Codex, Gemini) control a real Flutter app running on a device or simulator. The agent calls MCP tools in natural language — tap, type, scroll, assert — and those commands reach the live widget tree as real pointer events.

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
              |
              |  HTTP  localhost:7778
              |  (ADB forward / iproxy / direct)
              v
      mcpe2e  (Flutter library)              dev_dependency in the app
      HTTP server embedded inside the app
      Executes real pointer events via GestureBinding
              |
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
2. Call `tap_at x: <x> y: <y>` — taps at those absolute screen coordinates.

No `McpMetadataKey`, no widget registry, no test wrappers. Widget keys are optional and available when you want named access.

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
      ref: v1.1.6
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

`mcpe2e_server` automatically runs `adb forward` for every connected Android device when it starts — no manual port forwarding needed. For iOS, run `iproxy 7778 7777` once before starting the server (automatic iOS forwarding is not yet supported).

Verify the connection:

```bash
curl http://localhost:7778/ping
# {"status":"ok","port":7777}
```

### Step 5 — Run your first test

With the app running, ask the AI agent:

```
inspect_ui
```

The agent receives the full widget tree with coordinates. Then:

```
tap_at x: 195 y: 420
```

Or by widget key if registered:

```
tap_widget key: auth.login_button
```

---

## Available Tools (32)

### Multi-device

| Tool | Description |
|------|-------------|
| `list_devices` | Discover all connected Android devices/emulators, auto-forward ports, ping each one, return status and active screen |
| `select_device` | Switch the active device by serial. All subsequent tools target the selected device |
| `run_command` | Run any shell command (`flutter run`, `adb`, etc.) with optional `working_dir` and `background` mode |

### Context and Inspection

| Tool | Description |
|------|-------------|
| `get_app_context` | Registered widgets with metadata and capabilities |
| `list_test_cases` | Alias for `get_app_context` |
| `inspect_ui` | Full widget tree with values, states, and screen coordinates — no registration needed |
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
| `input_text` | `key`, `text`, `clear_first?` | Type into a TextField |
| `clear_text` | `key` | Clear a TextField |
| `select_dropdown` | `key`, `value` or `index` | Select a dropdown option |
| `toggle_widget` | `key` | Toggle a Checkbox, Switch, or Radio |
| `set_slider_value` | `key`, `value` (0.0–1.0) | Set a Slider position |

### Keyboard and Navigation

| Tool | Key parameters | Description |
|------|---------------|-------------|
| `show_keyboard` | `key` | Request focus and show virtual keyboard |
| `hide_keyboard` | — | Dismiss the virtual keyboard |
| `press_back` | — | Navigate back |
| `wait` | `duration_ms` | Pause execution (useful after animations) |

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

## Widget ID Convention

When using named widget keys, follow the `module.element[.variant]` pattern:

```
auth.login_button          Login button
auth.email_field           Email input
order.form.price           Price field inside an order form
order.card.{uuid}          Dynamic card identified at runtime
settings.dark_mode         Dark mode toggle
modal.confirm.delete       Confirmation dialog
```

---

## Managing Agents

The installer registers agents interactively. To change which agents have access to mcpe2e tools:

```bash
mcpe2e_server setup
```

This opens an interactive menu to enable or disable individual agents (Claude Code, Claude Desktop, Codex CLI, Gemini CLI) without reinstalling.

---

## Platform Connectivity

| Platform | Mechanism | Setup command |
|----------|-----------|---------------|
| Android | ADB forward (automatic) | None — mcpe2e_server handles it on startup |
| iOS | iproxy | `iproxy 7778 7777` |
| macOS / Linux / Windows desktop | Direct localhost | Set `TESTBRIDGE_URL=http://localhost:7777` |
| Web | Not supported | Flutter Web cannot open TCP sockets |

The `TESTBRIDGE_URL` environment variable tells `mcpe2e_server` where to find the app. Default is `http://localhost:7778`.

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
| `docs/test-flow-example.md` | Complete test walkthrough with Claude |
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
