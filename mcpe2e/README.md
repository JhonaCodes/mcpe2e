# mcpe2e

Let Claude control a real Flutter app on a device — tap, type, scroll, assert — using MCP tools.

```
Claude → MCP → mcpe2e_server → HTTP → [your app on device] → real gestures
```

---

## How it works

There are two components:

| Component | What it does |
|-----------|-------------|
| **mcpe2e** *(this package)* | Runs inside your app. Starts an HTTP server on :7777 that executes real widget gestures. |
| **[mcpe2e_server](https://github.com/JhonaCodes/mcpe2e/tree/main/mcpe2e_server)** | Runs on your machine. Bridges Claude's MCP tools to HTTP calls to the app. |

---

## Step 1 — Install the MCP server (once, on your machine)

```bash
curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh | bash
```

This downloads the binary and registers it with Claude Code automatically. You only do this once.

---

## Step 2 — Add mcpe2e to your Flutter app

```yaml
# pubspec.yaml
dependencies:
  mcpe2e: ^0.3.0
```

> Must be in `dependencies`, not `dev_dependencies` — `McpMetadataKey` extends Flutter's `Key`
> and is used in widget tree code. The server never starts in release builds (production safe).

---

## Step 3 — Create a testing file

```dart
// lib/testing/mcp_testing.dart
import 'package:mcpe2e/mcpe2e.dart';
import 'package:flutter/foundation.dart';

// Define keys for each testable widget
const _loginButton = McpMetadataKey(
  id: 'auth.login_button',
  widgetType: McpWidgetType.button,
  description: 'Login button',
  screen: 'LoginScreen',
);
const _emailField = McpMetadataKey(
  id: 'auth.email_field',
  widgetType: McpWidgetType.textField,
  description: 'Email input',
  screen: 'LoginScreen',
);

// Map used by mcpKey() to look up keys by ID
const _keys = <String, McpMetadataKey>{
  'auth.login_button': _loginButton,
  'auth.email_field':  _emailField,
};

/// Call this from main() before runApp().
Future<void> initMcpTesting() async {
  if (!kDebugMode) return; // no-op in release
  McpEvents.instance
    ..registerWidget(_loginButton)
    ..registerWidget(_emailField);
  await McpEventServer.start(); // starts HTTP server on :7777
}

/// Returns the key in debug mode, null in release.
Key? mcpKey(String id) => kDebugMode ? _keys[id] : null;
```

---

## Step 4 — Initialize in main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMcpTesting();
  runApp(const MyApp());
}
```

---

## Step 5 — Assign keys to your widgets

`McpMetadataKey` extends Flutter's `Key` — use it directly:

```dart
// Direct
ElevatedButton(
  key: _loginButton,
  onPressed: _handleLogin,
  child: const Text('Login'),
)

// With fallback for release (when you have existing keys)
TextFormField(
  key: mcpKey('auth.email_field') ?? WidgetKeys.emailField,
)
```

---

## Step 6 — Run and connect

```bash
# Terminal 1 — run the app in debug
flutter run

# Terminal 2 — forward the port once the app is on screen
adb forward tcp:7778 tcp:7777      # Android
# iproxy 7778 7777                 # iOS
# Desktop: no setup needed (set TESTBRIDGE_URL=http://localhost:7777)
```

Verify the connection:
```bash
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}
```

---

## Step 7 — Ask Claude to test

With the app running and the port forwarded, use Claude's MCP tools:

```
get_app_context        → see registered widgets on the current screen
tap_widget             → tap a widget by ID
input_text             → type into a text field
assert_widget          → verify text or state
scroll_widget          → scroll a list
```

Example prompt to Claude:
> "Open the app, go to login, type 'user@example.com' in the email field and tap Login"

---

## Dynamic widgets (lists, cards)

Register widgets at runtime and unregister when disposed:

```dart
class _OrderCardState extends State<OrderCard> {
  late final McpMetadataKey _key;

  @override
  void initState() {
    super.initState();
    _key = McpMetadataKey(id: 'order.card.${widget.id}', widgetType: McpWidgetType.card);
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

## Widget ID convention

```
module.element[.variant]

auth.login_button       Button on login screen
auth.email_field        Email input on login screen
order.card.{uuid}       Dynamic card with runtime ID
modal.confirm.delete    Dialog/modal
```

---

## Event types

**Gestures**: `tap` · `doubleTap` · `longPress` · `swipe` · `drag` · `scroll`

**Input**: `textInput` · `clearText` · `selectDropdown` · `toggle` · `setSliderValue`

**Nav**: `hideKeyboard` · `pressBack` · `scrollUntilVisible` · `tapByLabel` · `wait`

**Assertions**: `assertExists` · `assertText` · `assertVisible` · `assertEnabled` · `assertValue` · `assertCount`

---

## Platform connectivity

| Platform | Command |
|----------|---------|
| Android | `adb forward tcp:7778 tcp:7777` |
| iOS | `iproxy 7778 7777` |
| Desktop | `TESTBRIDGE_URL=http://localhost:7777` (no forward needed) |

---

## Production safety

- Server never starts outside `kDebugMode` / `kProfileMode`
- `McpMetadataKey` is a plain `Key` subclass — zero overhead in release
- Screenshot returns `{"error":"not_available_in_release"}` in release builds

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `/ping` times out | App must be running in debug; check `adb forward` ran after app started |
| `adb forward` fails | Run `adb devices` — device must appear |
| Widget not found | Key must be registered AND widget must be visible on screen |
| Tap has no effect | Widget may be scrolled off-screen or `onPressed` is null |
