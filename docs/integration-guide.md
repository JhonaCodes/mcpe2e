# Integration Guide — mcpe2e in any Flutter app

Step-by-step guide to add AI-driven E2E testing to an existing Flutter app.

## Prerequisites

- Flutter app running in debug or profile mode
- [mcpe2e_server](../mcpe2e_server) compiled and registered with Claude
- For Android: ADB installed and device connected
- For iOS: iproxy installed (`brew install usbmuxd`)
- For Desktop: nothing extra needed

---

## Step 1: Add dependency

```yaml
# pubspec.yaml
dev_dependencies:
  mcpe2e:
    path: /path/to/mcpe2e
```

```bash
flutter pub get
```

---

## Step 2: Define widget keys

Create a central file with all testable widget keys. `McpMetadataKey` extends Flutter's `Key` — use it directly as the widget key, no extra wiring needed.

```dart
// lib/testing/mcp_keys.dart
import 'package:mcpe2e/mcpe2e.dart';

abstract class McpKeys {
  // Auth screen
  static const loginEmail = McpMetadataKey(
    id: 'auth.email_field',
    widgetType: McpWidgetType.textField,
    description: 'Email input on login screen',
    screen: 'LoginScreen',
  );

  static const loginPassword = McpMetadataKey(
    id: 'auth.password_field',
    widgetType: McpWidgetType.textField,
    description: 'Password input on login screen',
    screen: 'LoginScreen',
  );

  static const loginButton = McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
    description: 'Login submit button',
    screen: 'LoginScreen',
  );

  // Home screen
  static const itemList = McpMetadataKey(
    id: 'home.item_list',
    widgetType: McpWidgetType.list,
    description: 'Main scrollable list',
    screen: 'HomeScreen',
  );

  // Dynamic keys — create one per item ID
  static McpMetadataKey itemCard(String id) => McpMetadataKey(
    id: 'home.card.$id',
    widgetType: McpWidgetType.card,
    screen: 'HomeScreen',
  );
}
```

**ID convention:** `module.element[.variant]`
```
auth.login_button       Static widget
order.card.{uuid}       Dynamic widget with runtime ID
state.loading           State indicator (for assert_visible)
screen.dashboard        Screen identifier (for navigation assert)
```

---

## Step 3: Use keys in widgets

```dart
import 'testing/mcp_keys.dart';

// Static key — const, use directly
TextField(
  key: McpKeys.loginEmail,
  controller: _emailController,
  decoration: const InputDecoration(hintText: 'Email'),
)

ElevatedButton(
  key: McpKeys.loginButton,
  onPressed: _isLoading ? null : _handleLogin, // null = disabled
  child: const Text('Login'),
)

// Checkbox
Checkbox(
  key: const McpMetadataKey(id: 'settings.remember_me', widgetType: McpWidgetType.checkbox),
  value: _rememberMe,
  onChanged: (v) => setState(() => _rememberMe = v ?? false),
)
```

---

## Step 4: Register and start the server

```dart
// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mcpe2e/mcpe2e.dart';
import 'testing/mcp_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only in debug/profile — the server blocks in release automatically
  if (kDebugMode || kProfileMode) {
    _initE2E();
  }

  runApp(const MyApp());
}

void _initE2E() {
  final mcp = McpEvents.instance;
  mcp.registerWidget(McpKeys.loginEmail);
  mcp.registerWidget(McpKeys.loginPassword);
  mcp.registerWidget(McpKeys.loginButton);
  mcp.registerWidget(McpKeys.itemList);
  // Add more static keys here

  McpEventServer.start();
  // Automatically configures ADB forward (Android), iproxy (iOS), or
  // direct localhost (Desktop). Logs the TESTBRIDGE_URL to use.
}
```

---

## Step 5: Dynamic widgets

Register and unregister dynamic widgets in the widget lifecycle:

```dart
class ItemCard extends StatefulWidget {
  final String itemId;
  const ItemCard({required this.itemId, super.key});

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  late final McpMetadataKey _mcpKey;

  @override
  void initState() {
    super.initState();
    _mcpKey = McpKeys.itemCard(widget.itemId);
    McpEvents.instance.registerWidget(_mcpKey);
  }

  @override
  void dispose() {
    McpEvents.instance.unregisterWidget(_mcpKey.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: _mcpKey,
      child: ListTile(title: Text('Item ${widget.itemId}')),
    );
  }
}
```

---

## Step 6: Connect and verify

```bash
# Terminal 1: Run the Flutter app
flutter run -d <device_id>
# The server starts on :7777 and logs the TESTBRIDGE_URL

# Terminal 2: Verify (the ADB forward may already be set up automatically)
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}

curl http://localhost:7778/mcp/context
# → {"screen":"LoginScreen","widgets":[...]}

# Inspect the full UI (no registration needed)
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

Now Claude can call `tap_widget`, `input_text`, `inspect_ui`, `capture_screenshot`, etc.

---

## Bridging apps that already use ValueKey\<String\>

If your app already uses `ValueKey<String>` consistently, you don't need to change widget code. Register the corresponding McpMetadataKeys with matching IDs:

```dart
void _bridgeExistingKeys() {
  final mcp = McpEvents.instance;
  // The HTTP server looks up widgets by key string,
  // so 'auth.login_button' will find ValueKey('auth.login_button')
  mcp.registerWidget(const McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
  ));
}
```

Alternatively, use `inspect_ui` — it finds **all** widgets (with or without McpMetadataKey) and returns their current values, requiring no registration at all.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `/ping` not responding | App must be in debug/profile; check firewall on port 7777 |
| ADB forward fails | Run `adb devices` — device must be listed |
| Widget not found | Key must be registered AND widget mounted (on screen) |
| Tap has no effect | `onPressed` might be null (disabled), or widget is off-screen |
| Text input fails | Widget must wrap a `TextField` or `TextFormField` |
| Screenshot error | Only available in debug/profile — returns error JSON in release |
| inspect_ui is empty | App might not have rendered the first frame yet; try after `wait` |
