# mcpe2e_server

Dart binary that acts as an MCP (Model Context Protocol) server. It receives tool calls from AI agents via stdio and translates them into HTTP requests sent to the `mcpe2e` Flutter library running inside your app on a real device or simulator.

```
AI Agent (Claude / Codex / Gemini)
        │  MCP stdio
        ▼
mcpe2e_server  (this binary, ~/.local/bin/)
        │  HTTP localhost:7778
        ▼
mcpe2e  (Flutter dev_dependency inside your app)
        │  GestureBinding
        ▼
Flutter app on real device / simulator
```

Version: **1.0.7**

---

## Install

The recommended way is from the Flutter package — no separate download needed:

```bash
dart run mcpe2e:setup
```

This downloads the binary for your platform, installs it to `~/.local/bin/`, and opens the agent registration menu.

### Alternative: direct download

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh \
  -o /tmp/mcpe2e_install.sh && bash /tmp/mcpe2e_install.sh
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.ps1 | iex
```

---

## Agent Management

After install, run the `setup` subcommand at any time to enable or disable agent registrations:

```bash
mcpe2e_server setup
```

This opens an interactive ANSI menu showing the current registration status of each supported agent. You can toggle agents individually, enable all, or disable all.

### Supported Agents

| Agent | Provider | Config File | Format |
|---|---|---|---|
| Claude Code | Anthropic | `~/.claude.json` | JSON (scope: user) |
| Claude Desktop | Anthropic | `~/Library/Application Support/Claude/claude_desktop_config.json` | JSON |
| Codex CLI | OpenAI | `~/.codex/config.toml` | TOML |
| Gemini CLI | Google | `~/.gemini/settings.json` | JSON |

---

## TESTBRIDGE_URL

This environment variable tells `mcpe2e_server` where the in-app HTTP server is reachable from your machine. You must forward the device port to localhost before running tests.

| Platform | Forward Command | URL |
|---|---|---|
| Android | `adb forward tcp:7778 tcp:7777` | `http://localhost:7778` |
| iOS | `iproxy 7778 7777` | `http://localhost:7778` |
| Desktop (direct) | none | `http://localhost:7777` |

```bash
# Override if your setup uses a different port
export TESTBRIDGE_URL=http://localhost:7778
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `TESTBRIDGE_URL` | `http://localhost:7778` | Base URL of the in-app HTTP server |
| `MCPE2E_TIMEOUT_MS` | `5000` | Default timeout in milliseconds for tool calls |

---

## MCP Tools (29 total)

### Context

| Tool | Description |
|---|---|
| `get_app_context` | Returns registered widgets with metadata and capabilities |
| `list_test_cases` | Lists all registered test cases in the app |
| `inspect_ui` | Full widget tree with types, labels, values, states, and coordinates |
| `capture_screenshot` | Returns a real PNG screenshot via the Flutter layer tree |

### Gestures

| Tool | Parameters | Description |
|---|---|---|
| `tap_widget` | `key` | Tap a widget by its registered key |
| `tap_at` | `x`, `y` | Tap at absolute screen coordinates. No widget key required |
| `double_tap_widget` | `key` | Double-tap a widget by key |
| `long_press_widget` | `key`, `duration_ms?` | Long-press a widget (default 500ms) |
| `swipe_widget` | `key`, `direction`, `distance?` | Swipe on a widget in a given direction |
| `scroll_widget` | `key`, `direction` | Scroll a scrollable widget |
| `scroll_until_visible` | `key`, `target_key`, `max_attempts?` | Scroll until a target widget is visible |
| `drag_widget` | `key`, `dx`, `dy`, `duration_ms?` | Drag a widget by a pixel offset from its center |
| `pinch_widget` | `key`, `scale` | Pinch (zoom) a widget |
| `tap_by_label` | `label` | Tap the first widget matching a text label |

### Input

| Tool | Parameters | Description |
|---|---|---|
| `input_text` | `key`, `text`, `clear_first?` | Type text into a TextField |
| `clear_text` | `key` | Clear the text content of a widget |
| `select_dropdown` | `key`, `value` or `index` | Select an option from a dropdown widget |
| `toggle_widget` | `key` | Toggle a Checkbox or Switch |
| `set_slider_value` | `key`, `value` (0.0–1.0) | Set the value of a Slider widget |

### Keyboard and Navigation

| Tool | Parameters | Description |
|---|---|---|
| `hide_keyboard` | — | Dismiss the software keyboard |
| `show_keyboard` | `key` | Show the software keyboard (request focus) |
| `press_back` | — | Simulate the Android back button |
| `wait` | `duration_ms` | Wait for a given number of milliseconds |

### Assertions

| Tool | Parameters | Description |
|---|---|---|
| `assert_exists` | `key` | Assert that a widget with the given key exists in the tree |
| `assert_text` | `key`, `text` | Assert that a widget displays the expected text |
| `assert_visible` | `key` | Assert that a widget is visible on screen |
| `assert_enabled` | `key` | Assert that a widget is enabled (not disabled) |
| `assert_selected` | `key` | Assert that a widget is selected (checkbox, radio, tab) |
| `assert_value` | `key`, `value` | Assert the semantic value of a widget |
| `assert_count` | `key`, `count` | Assert the number of widgets matching a key or type |

---

## Coordinate-based testing with tap_at

`tap_at` is the primary approach for tapping widgets without needing a registered key. Use `inspect_ui` first to get the widget's position and size, then calculate the center and call `tap_at`.

```
inspect_ui response:
  { "type": "ElevatedButton", "label": "Login", "x": 20, "y": 400, "w": 353, "h": 56 }

tap_at:
  x = 20 + 353/2 = 196
  y = 400 + 56/2 = 428
```

This approach works on any widget in the tree, including dynamic lists, cards without keys, and third-party components.

---

## Build from Source

Requires Dart SDK >= 3.0.

```bash
git clone https://github.com/JhonaCodes/mcpe2e
cd mcpe2e/mcpe2e_server
dart pub get
dart compile exe bin/mcp_server.dart -o ~/.local/bin/mcpe2e_server
```

---

## Links

- Flutter library: [mcpe2e](https://github.com/JhonaCodes/mcpe2e/tree/main/mcpe2e)
- Integration guide: [docs/integration-guide.md](../docs/integration-guide.md)
- Test flow examples: [docs/test-flow-example.md](../docs/test-flow-example.md)
- Changelog: [CHANGELOG.md](./CHANGELOG.md)
