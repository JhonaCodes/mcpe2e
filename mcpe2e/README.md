# mcpe2e — Flutter Library

[![version](https://img.shields.io/badge/version-1.1.6-blue)](https://github.com/JhonaCodes/mcpe2e/releases/tag/v1.1.6)

mcpe2e is a Flutter library that embeds a lightweight HTTP server inside your app. When an AI agent (Claude, Codex, Gemini) calls an MCP tool, `mcpe2e_server` translates it to an HTTP request that reaches this server, which then executes the corresponding gesture or assertion on the live widget tree.

This library runs **inside the app on the device**. It is the receiving end of the testing pipeline.

```
mcpe2e_server (on your machine)
      |
      |  HTTP  localhost:7778 → device:7777
      v
mcpe2e (this library, inside the app)
      |
      v
Real pointer events via GestureBinding
```

---

## Installation

Add as a `dev_dependency`:

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

Then install the MCP server and register your AI agents:

```bash
dart run mcpe2e:setup
```

This downloads `mcpe2e_server` to `~/.local/bin/` and opens an interactive menu to register it with Claude Code, Claude Desktop, Codex CLI, or Gemini CLI.

This is a `dev_dependency` because the server is only active in debug builds and the library has no effect in release.

---

## Minimal Setup

```dart
import 'package:flutter/foundation.dart';
import 'package:mcpe2e/mcpe2e.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) await McpEventServer.start();
  runApp(const MyApp());
}
```

`McpEventServer.start()` starts the HTTP server on port `7777`. In release builds it is a no-op — the guard is built into the library, but an explicit `kDebugMode` check makes the intent clear.

The server stops automatically when the app closes via `WidgetsBindingObserver`. No manual cleanup needed.

---

## HTTP Endpoints

The library exposes these endpoints on `localhost:7777`:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ping` | GET | Health check. Returns `{"status":"ok","port":7777}` |
| `/mcp/context` | GET | Registered widgets with their metadata |
| `/mcp/tree` | GET | Full widget tree — values, states, coordinates |
| `/mcp/screenshot` | GET | Current screen as PNG (base64 encoded) |
| `/action` | GET | Execute an event via query params (`?key=...&type=...`) |
| `/event` | POST | Execute an event via JSON body |
| `/widgets` | GET | List registered widget IDs. Accepts `?metadata=true` for full context |

### /mcp/tree response

`GET /mcp/tree` returns the full widget tree without any widget registration. For each element it includes:

- Widget type and text content (Text, TextField, Button, AppBar, etc.)
- Interactive state (enabled, checked, selected, slider value)
- Screen coordinates: `x`, `y`, `w`, `h` in logical pixels
- Presence of Dialogs and SnackBars

Use the `x` and `y` values with `tap_at` to interact with any element without registration.

### /mcp/screenshot response

`GET /mcp/screenshot` captures the screen using Flutter's internal layer tree. Returns:

```json
{ "screenshot": "<base64 PNG>" }
```

Returns `{"error":"not_available_in_release"}` in release builds.

---

## Zero-config Testing (Primary Approach)

The recommended workflow does not require widget registration:

```
inspect_ui   →  receives full widget tree with x, y, w, h for every element
tap_at x: 195 y: 420   →  taps at those coordinates
```

This works for any widget, including dynamic list items, generated cards, and widgets without keys.

---

## Optional: Named Widget Keys

For scenarios where you want stable named access to specific widgets, use `McpMetadataKey`. It extends Flutter's `Key` and can be assigned to any widget directly.

```dart
import 'package:mcpe2e/mcpe2e.dart';

const loginButton = McpMetadataKey(
  id: 'auth.login_button',
  widgetType: McpWidgetType.button,
  description: 'Login submit button',
  screen: 'LoginScreen',
);

const emailField = McpMetadataKey(
  id: 'auth.email_field',
  widgetType: McpWidgetType.textField,
  description: 'Email input',
  screen: 'LoginScreen',
);
```

Register them before starting the server:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    McpEvents.instance
      ..registerWidget(loginButton)
      ..registerWidget(emailField);
    await McpEventServer.start();
  }
  runApp(const MyApp());
}
```

Assign directly to widgets:

```dart
ElevatedButton(
  key: loginButton,
  onPressed: _handleLogin,
  child: const Text('Login'),
)

TextFormField(key: emailField)
```

Registered widgets appear in `get_app_context` and can be targeted by ID in all gesture and assertion tools (`tap_widget`, `input_text`, `assert_text`, etc.).

### Dynamic widgets

For list items or cards generated at runtime, register and unregister in the widget's state lifecycle:

```dart
class _OrderCardState extends State<OrderCard> {
  late final McpMetadataKey _key;

  @override
  void initState() {
    super.initState();
    _key = McpMetadataKey(
      id: 'order.card.${widget.id}',
      widgetType: McpWidgetType.card,
    );
    McpEvents.instance.registerWidget(_key);
  }

  @override
  void dispose() {
    McpEvents.instance.unregisterWidget(_key.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(key: _key, child: Text(widget.id));
}
```

---

## Widget ID Convention

```
module.element[.variant]

auth.login_button          Login button
auth.email_field           Email input
order.form.price           Price field inside an order form
order.card.{uuid}          Dynamic card identified at runtime
settings.dark_mode         Dark mode toggle
modal.confirm.delete       Confirmation dialog
```

---

## Production Safety

- `McpEventServer.start()` exits immediately if not in debug or profile mode.
- `GET /mcp/screenshot` returns `{"error":"not_available_in_release"}` in release builds.
- `McpMetadataKey` is a plain `Key` subclass — zero overhead in release.
- The server never starts unless `start()` is explicitly called.

---

## Platform Connectivity

The library listens on port `7777` on the device. The `mcpe2e_server` on your machine connects to it via port `7778` after forwarding is set up.

| Platform | Command |
|----------|---------|
| Android | Automatic — `mcpe2e_server` runs `adb forward` on startup |
| iOS | `iproxy 7778 7777` (requires `brew install usbmuxd`) |
| Desktop | No forwarding — set `TESTBRIDGE_URL=http://localhost:7777` |

`McpConnectivity.setup()` runs automatically inside `McpEventServer.start()` and configures platform-specific forwarding where applicable. On Android, `mcpe2e_server` also handles `adb forward` automatically at startup.

Verify the connection after forwarding:

```bash
curl http://localhost:7778/ping
# {"status":"ok","port":7777}
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `/ping` times out | Confirm the app is running in debug mode. `mcpe2e_server` auto-runs `adb forward` — if it fails, check `adb devices`. |
| `adb forward` fails | Run `adb devices` — the device must be listed. |
| Widget not found by key | The key must be registered and the widget must be in the current visible tree. |
| Tap has no effect | The widget may be scrolled off-screen or its `onPressed` is null. Use `inspect_ui` to verify coordinates. |
| Screenshot not available | Only works in debug or profile mode. |
