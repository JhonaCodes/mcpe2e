# mcpe2e

Flutter library for AI-driven E2E testing. Embeds an HTTP server in your app so that [mcpe2e_server](../mcpe2e_server) (the MCP server) can control real widgets — tap, type, scroll, assert — from Claude or any MCP client.

## What it does

`mcpe2e` is the **device-side component**: it runs inside your Flutter app, exposes an HTTP server on port 7777, and executes real gestures on the live widget tree.

```
Claude → MCP → mcpe2e_server → HTTP → [mcpe2e running inside your app] → real gestures
```

It does **not** implement MCP. It speaks plain HTTP.

## Features

- **25 event types**: tap, doubleTap, longPress, swipe, scroll, textInput, clearText, selectDropdown, toggle, setSliderValue, hideKeyboard, pressBack, scrollUntilVisible, tapByLabel, wait + 7 assert types
- **Widget registry**: register widgets with `McpMetadataKey` to make them addressable by ID
- **UI inspection**: `McpTreeInspector` walks the full widget tree with zero intrusion — reads Text values, TextField content, button states, checkbox values, slider positions
- **Screenshot**: `McpScreenCapture` captures the screen via Flutter's internal layer tree (zero widgets added, debug/profile only)
- **Platform connectivity**: auto-configures ADB forward (Android), iproxy (iOS), direct localhost (Desktop)
- **Production safe**: server never starts unless explicitly called; screenshot fails gracefully in release

## Installation

```yaml
# pubspec.yaml
dev_dependencies:
  mcpe2e:
    path: /path/to/mcpe2e
```

## Quick Start

### 1. Define testable widgets

```dart
// lib/testing/mcp_keys.dart
import 'package:mcpe2e/mcpe2e.dart';

// McpMetadataKey extends Key — use it directly as the widget key
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
```

### 2. Register and start

```dart
import 'package:flutter/foundation.dart';
import 'package:mcpe2e/mcpe2e.dart';

void initE2E() {
  if (!kDebugMode && !kProfileMode) return;

  McpEvents.instance.registerWidget(loginEmail);
  McpEvents.instance.registerWidget(loginButton);

  McpEventServer.start(); // binds :7777, sets up ADB forward automatically
}
```

Call `initE2E()` after `WidgetsFlutterBinding.ensureInitialized()`.

### 3. Use keys in widgets

```dart
// McpMetadataKey extends Key — pass it directly
TextField(
  key: loginEmail,
  controller: _emailController,
)

ElevatedButton(
  key: loginButton,
  onPressed: _handleLogin,
  child: const Text('Login'),
)
```

### 4. Dynamic widgets (lists, cards)

Register/unregister in the widget lifecycle:

```dart
class OrderCard extends StatefulWidget {
  final String orderId;
  const OrderCard({required this.orderId, super.key});

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  late final McpMetadataKey _key;

  @override
  void initState() {
    super.initState();
    _key = McpMetadataKey(
      id: 'order.card.${widget.orderId}',
      widgetType: McpWidgetType.card,
      screen: 'OrdersScreen',
    );
    McpEvents.instance.registerWidget(_key);
  }

  @override
  void dispose() {
    McpEvents.instance.unregisterWidget(_key.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(key: _key, child: Text('Order ${widget.orderId}'));
  }
}
```

## HTTP Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ping` | GET | Health check — `{"status":"ok","port":7777}` |
| `/mcp/context` | GET | Registered widgets with metadata and capabilities |
| `/mcp/tree` | GET | Full widget tree with values/states (no registration needed) |
| `/mcp/screenshot` | GET | Current screen as PNG base64 (debug/profile only) |
| `/action?key=...&type=...` | GET | Execute event via query params |
| `/event` | POST | Execute event via JSON body |
| `/widgets` | GET | List widget IDs (`?metadata=true` for full context) |

### /mcp/tree response example

```json
{
  "timestamp": "2026-03-09T10:00:00Z",
  "widget_count": 12,
  "widgets": [
    { "type": "Text", "value": "Total: $0.00", "depth": 6, "x": 16.0, "y": 400.0, "w": 150.0, "h": 20.0 },
    { "type": "TextField", "value": "user@test.com", "hint": "Email", "enabled": true, "depth": 5, "key": "auth.email_field" },
    { "type": "ElevatedButton", "label": "Login", "enabled": true, "depth": 5, "key": "auth.login_button" },
    { "type": "Checkbox", "value": false, "enabled": true, "depth": 7 }
  ]
}
```

### /action examples

```bash
# Tap
curl "http://localhost:7778/action?key=auth.login_button"

# Type text
curl "http://localhost:7778/action?key=auth.email_field&type=textinput&text=user@test.com"

# Scroll list down
curl "http://localhost:7778/action?key=home.item_list&type=scroll&direction=down"

# Toggle checkbox
curl "http://localhost:7778/action?key=settings.notifications&type=toggle"
```

### /event POST example

```bash
curl -X POST http://localhost:7778/event \
  -H 'Content-Type: application/json' \
  -d '{"key":"auth.login_button","type":"assertEnabled","params":{}}'
```

## Event Types (25)

**Gestures**: `tap` · `doubleTap` · `longPress` · `swipe` · `drag` · `scroll` · `pinch`

**Input**: `textInput` · `clearText` · `selectDropdown` · `toggle` · `setSliderValue`

**Keyboard & Nav**: `hideKeyboard` · `showKeyboard` · `pressBack` · `scrollUntilVisible` · `tapByLabel` · `wait`

**Assertions**: `assertExists` · `assertText` · `assertVisible` · `assertEnabled` · `assertSelected` · `assertValue` · `assertCount`

## Widget Types (14)

`button` · `textField` · `text` · `list` · `card` · `image` · `container` · `dropdown` · `checkbox` · `radio` · `switchWidget` · `slider` · `tab` · `custom`

## Widget ID Convention

```
module.element[.variant]

auth.login_button           Static — login button
auth.email_field            Static — email input
order.card.{uuid}           Dynamic — card with ID
state.loading_indicator     State — loading indicator
screen.dashboard            Screen identifier
modal.confirm.delete        Modal/dialog
```

## Platform Connectivity

| Platform | Mechanism | Setup |
|----------|-----------|-------|
| Android | ADB forward | Auto: `adb forward tcp:7778 tcp:7777` |
| iOS | iproxy | Auto: `iproxy 7778 7777` |
| Desktop | Direct localhost | No setup — use `TESTBRIDGE_URL=http://localhost:7777` |
| Web | Not supported | Flutter Web cannot open TCP sockets |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `/ping` not responding | App must be in debug/profile mode; check port 7777 is not blocked |
| ADB forward fails | `adb devices` — verify device is connected |
| Widget not found by key | Key must be registered AND widget must be mounted on screen |
| Tap has no effect | Widget may be behind another widget, off-screen, or `onPressed` is null |
| Screenshot returns error | Only available in debug/profile; returns `{"error":"not_available_in_release"}` in release |
| inspect_ui returns empty | Ensure app has finished rendering its first frame |
