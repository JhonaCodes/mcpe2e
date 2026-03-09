# Integration Guide

Step-by-step guide to add mcpe2e to any existing Flutter app.

## Prerequisites

- Flutter app running in debug or profile mode
- [mcpe2e_server](../mcpe2e_server) compiled and registered with Claude
- **Android**: ADB installed, device connected via USB
- **iOS**: `iproxy` installed (`brew install usbmuxd`)
- **Desktop**: nothing extra — server binds directly to localhost

---

## Step 1: Add the dependency

```yaml
# pubspec.yaml
dev_dependencies:
  mcpe2e:
    path: /path/to/mcpe2e   # or use a pub.dev version once published
```

```bash
flutter pub get
```

---

## Step 2: Define your widget keys

Create a central file for all testable widget keys. `McpMetadataKey` extends Flutter's `Key` — assign it directly to the widget's `key` parameter.

```dart
// lib/testing/mcp_keys.dart
import 'package:mcpe2e/mcpe2e.dart';

abstract class McpKeys {
  static const loginEmail = McpMetadataKey(
    id: 'auth.email_field',
    widgetType: McpWidgetType.textField,
    description: 'Email input on login screen',
    screen: 'LoginScreen',
  );

  static const loginButton = McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
    description: 'Submit login credentials',
    screen: 'LoginScreen',
  );

  static const itemList = McpMetadataKey(
    id: 'home.item_list',
    widgetType: McpWidgetType.list,
    description: 'Main scrollable list',
    screen: 'HomeScreen',
  );

  // Dynamic key — create one per runtime ID
  static McpMetadataKey itemCard(String id) => McpMetadataKey(
    id: 'home.card.$id',
    widgetType: McpWidgetType.card,
    screen: 'HomeScreen',
  );
}
```

**ID convention:** `module.element[.variant]`

```
auth.login_button        Static widget
home.card.{uuid}         Dynamic widget with runtime ID
state.loading            State indicator (use with assert_visible)
screen.dashboard         Screen identifier (use with assert_exists after navigation)
```

---

## Step 3: Assign keys to widgets

```dart
import 'testing/mcp_keys.dart';

// McpMetadataKey extends Key — assign directly
TextField(
  key: McpKeys.loginEmail,
  controller: _emailController,
  decoration: const InputDecoration(hintText: 'Email'),
)

ElevatedButton(
  key: McpKeys.loginButton,
  onPressed: _isLoading ? null : _handleLogin,  // null = disabled
  child: const Text('Login'),
)

Checkbox(
  key: const McpMetadataKey(
    id: 'settings.remember_me',
    widgetType: McpWidgetType.checkbox,
  ),
  value: _rememberMe,
  onChanged: (v) => setState(() => _rememberMe = v ?? false),
)
```

---

## Step 4: Register widgets and start the server

```dart
// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mcpe2e/mcpe2e.dart';
import 'testing/mcp_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initE2E();
  runApp(const MyApp());
}

void _initE2E() {
  // McpEventServer.start() is already a no-op in release builds,
  // but the guard makes intent explicit.
  if (!kDebugMode && !kProfileMode) return;

  final mcp = McpEvents.instance;
  mcp.registerWidget(McpKeys.loginEmail);
  mcp.registerWidget(McpKeys.loginButton);
  mcp.registerWidget(McpKeys.itemList);

  McpEventServer.start();
  // Automatically configures ADB forward (Android), iproxy (iOS),
  // or direct localhost (Desktop). Logs the TESTBRIDGE_URL.
}
```

---

## Step 5: Handle dynamic widgets

Register in `initState`, unregister in `dispose`:

```dart
class ItemCard extends StatefulWidget {
  final String itemId;
  const ItemCard({required this.itemId, super.key});

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  late final McpMetadataKey _key;

  @override
  void initState() {
    super.initState();
    _key = McpKeys.itemCard(widget.itemId);
    McpEvents.instance.registerWidget(_key);
  }

  @override
  void dispose() {
    McpEvents.instance.unregisterWidget(_key.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: _key,
      child: ListTile(title: Text('Item ${widget.itemId}')),
    );
  }
}
```

---

## Step 6: Verify connectivity

```bash
# Android
adb forward tcp:7778 tcp:7777

# iOS
iproxy 7778 7777

# Verify
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}

curl http://localhost:7778/mcp/context
# → {"screen":"LoginScreen","widgets":[...]}

# Inspect the full UI — no registration needed
curl http://localhost:7778/mcp/tree
# → {"widget_count":14,"widgets":[{"type":"Text","value":"Login",...},...]}
```

---

## Step 7: Register mcpe2e_server with Claude

```bash
# Compile the MCP server
cd mcpe2e_server
dart compile exe bin/server.dart -o mcpe2e

# Register with Claude Code
claude mcp add mcpe2e \
  --command /path/to/mcpe2e_server/mcpe2e \
  --env TESTBRIDGE_URL=http://localhost:7778
```

Claude can now call `tap_widget`, `input_text`, `inspect_ui`, `capture_screenshot`, and 23 more tools.

---

## Bridging apps that already use ValueKey\<String\>

If your app already uses `ValueKey<String>` consistently, no widget code changes are needed. Register matching `McpMetadataKey` instances with the same ID strings:

```dart
void _bridgeExistingKeys() {
  // The HTTP server matches widgets by key string, so 'auth.login_button'
  // will find any widget with ValueKey('auth.login_button') already in the tree.
  McpEvents.instance.registerWidget(const McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
  ));
}
```

Alternatively, use `inspect_ui` — it traverses the full widget tree and returns values for **all** widgets (Text, TextField, Button, Checkbox, etc.) regardless of whether they are registered.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `/ping` not responding | App must be in debug or profile mode; check port 7777 is not blocked |
| ADB forward fails | `adb devices` — device must be listed and authorized |
| Widget not found by key | Key must be registered AND the widget must be mounted on screen |
| Tap has no effect | `onPressed` may be null (disabled), or widget is off-screen |
| Text input fails | Widget must wrap a `TextField` or `TextFormField` |
| Screenshot returns error | Only available in debug/profile; returns `{"error":"not_available_in_release"}` in release |
| `inspect_ui` returns empty | App may not have rendered its first frame yet; call `wait` first |
