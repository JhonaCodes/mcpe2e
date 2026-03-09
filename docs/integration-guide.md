# Integration Guide

Step-by-step guide to add `mcpe2e` to any existing Flutter app and run your first AI-driven E2E test.

---

## Prerequisites

- Flutter app running in **debug or profile mode**
- Device connected via USB or simulator running
- **Android**: ADB installed and device authorized (`adb devices`)
- **iOS**: `iproxy` installed (`brew install usbmuxd`)
- **Desktop**: nothing extra — the server binds directly to localhost

---

## Step 1: Add the Flutter dependency

Add `mcpe2e` as a dev dependency in your app's `pubspec.yaml`:

```yaml
dev_dependencies:
  mcpe2e:
    git:
      url: https://github.com/JhonaCodes/mcpe2e.git
      ref: v1.0.7
      path: mcpe2e
```

```bash
flutter pub get
```

---

## Step 2: Install mcpe2e_server and register your AI agents

```bash
dart run mcpe2e:setup
```

This command downloads the `mcpe2e_server` binary for your platform, installs it to `~/.local/bin/`, and opens the agent registration menu. Select which AI agents you want to enable (Claude Code, Claude Desktop, Codex CLI, Gemini CLI) and confirm.

That's all. The agent is now configured.

To change registrations later:

```bash
mcpe2e_server setup
```

---

## Step 3: Start the server in main.dart

The minimum integration is two lines: import the package and start the server in debug mode.

```dart
import 'package:mcpe2e/mcpe2e.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) await McpEventServer.start();
  runApp(const MyApp());
}
```

`McpEventServer.start()` is a no-op in release builds, so there is no risk of accidentally shipping it. The guard on `kDebugMode` makes the intent explicit.

The server listens on port **7777** inside the device.

---

## Step 4: Connect the device

Forward the device port to your machine so `mcpe2e_server` can reach it:

```bash
# Android
adb forward tcp:7778 tcp:7777

# iOS
iproxy 7778 7777

# Desktop app running on the same machine — no forwarding needed
# Use TESTBRIDGE_URL=http://localhost:7777
```

---

## Step 5: Verify the connection

```bash
# Health check
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}

# Full widget tree — no registration needed
curl http://localhost:7778/mcp/tree
# → {"widget_count":14,"widgets":[{"type":"Text","value":"Login",...},...]}
```

If `/ping` responds, the AI agent can now reach your app.

---

## Step 6: Run your first test

The recommended approach is **coordinate-based**: use `inspect_ui` to find a widget's position on screen, then use `tap_at` to tap it. No widget keys or registration required.

### Example: tap the login button

**Inspect the screen first:**

```
AI calls: inspect_ui
```

Response (excerpt):

```json
{
  "widget_count": 12,
  "widgets": [
    { "type": "TextField", "hint": "Email", "x": 16, "y": 220, "w": 358, "h": 56 },
    { "type": "TextField", "hint": "Password", "x": 16, "y": 296, "w": 358, "h": 56 },
    { "type": "ElevatedButton", "label": "Login", "x": 20, "y": 400, "w": 353, "h": 56 }
  ]
}
```

**Type in the fields and tap the button:**

```
AI calls: input_text
  key: "auth.email_field"
  text: "user@example.com"

AI calls: input_text
  key: "auth.password_field"
  text: "secret123"

AI calls: tap_at
  x: 196   ← 20 + 353/2
  y: 428   ← 400 + 56/2

AI calls: wait
  duration_ms: 2000

AI calls: capture_screenshot
```

The AI receives the screenshot and can visually confirm the result, or call `inspect_ui` again to check the new screen content.

---

## Optional: register keys for frequently tested widgets

If some widgets are tested repeatedly, you can register them with a `McpMetadataKey` so the AI can find them by name via `tap_widget` or `assert_exists` without needing to inspect coordinates each time.

```dart
import 'package:mcpe2e/mcpe2e.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    McpEvents.instance.registerWidget(const McpMetadataKey(
      id: 'auth.login_button',
      widgetType: McpWidgetType.button,
      description: 'Login submit button',
      screen: 'LoginScreen',
    ));
    McpEvents.instance.registerWidget(const McpMetadataKey(
      id: 'auth.email_field',
      widgetType: McpWidgetType.textField,
      description: 'Email input on login screen',
      screen: 'LoginScreen',
    ));
    await McpEventServer.start();
  }

  runApp(const MyApp());
}
```

Then assign the key directly to the widget:

```dart
ElevatedButton(
  key: const McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
  ),
  onPressed: _handleLogin,
  child: const Text('Login'),
)
```

Registered widgets appear in `get_app_context` and can be used with `tap_widget`, `assert_exists`, `assert_text`, and all other key-based tools.

**ID convention:** `module.element[.variant]`

```
auth.login_button      Static widget
auth.email_field       Text field
home.card.{uuid}       Dynamic widget with runtime ID
state.loading          Loading indicator
screen.dashboard       Screen identifier
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `/ping` returns connection refused | App must be in debug or profile mode. Check that `McpEventServer.start()` was called. |
| ADB forward fails | Run `adb devices` — device must be listed and authorized. |
| `inspect_ui` returns empty or very few widgets | App may not have rendered its first frame yet. Call `wait` first. |
| `tap_at` taps the wrong element | Recalculate center: `x = widget.x + widget.w / 2`, `y = widget.y + widget.h / 2`. |
| `input_text` has no effect | The widget must contain a `TextField` or `TextFormField` descendant. |
| Screenshot returns error | Only available in debug/profile builds. Returns `{"error":"not_available_in_release"}` in release. |
| Widget not found by key | The widget must be registered AND currently mounted in the tree (on screen). |
