# mcpe2e Example App

Minimal Flutter app demonstrating full mcpe2e integration: login flow, dashboard with a dynamic list, and a settings screen with Switch, Checkbox, and Slider.

## Structure

```
example/
├── lib/
│   ├── main.dart                    # App entry point + mcpe2e setup
│   ├── screens/
│   │   ├── login_screen.dart        # Email + password + login button
│   │   ├── dashboard_screen.dart    # Welcome text + dynamic item list
│   │   └── settings_screen.dart    # Switch, Checkbox, Slider, logout
│   └── testing/
│       └── mcp_keys.dart           # All McpMetadataKey constants
└── pubspec.yaml
```

## Running the example

```bash
cd example
flutter pub get
flutter run -d <device_id>
```

The app starts the HTTP server on `:7777` and logs the `TESTBRIDGE_URL` to the console.

## Connecting from mcpe2e_server

```bash
# Android
adb forward tcp:7778 tcp:7777
export TESTBRIDGE_URL=http://localhost:7778

# iOS
iproxy 7778 7777
export TESTBRIDGE_URL=http://localhost:7778

# Desktop
export TESTBRIDGE_URL=http://localhost:7777

# Verify
curl $TESTBRIDGE_URL/ping
# → {"status":"ok","port":7777}
```

## Registered widget IDs

| ID | Screen | Type | Description |
|----|--------|------|-------------|
| `auth.email_field` | LoginScreen | TextField | Email input |
| `auth.password_field` | LoginScreen | TextField | Password input |
| `auth.login_button` | LoginScreen | ElevatedButton | Submit (disabled until fields filled) |
| `auth.error_message` | LoginScreen | Text | Error message on invalid login |
| `screen.dashboard` | DashboardScreen | Container | Screen identifier |
| `dashboard.welcome_text` | DashboardScreen | Text | Welcome message |
| `dashboard.settings_button` | DashboardScreen | IconButton | Navigate to settings |
| `dashboard.item_list` | DashboardScreen | ListView | Scrollable list |
| `dashboard.item.{0..14}` | DashboardScreen | Card | Dynamic item cards |
| `screen.settings` | SettingsScreen | Container | Screen identifier |
| `settings.notifications_switch` | SettingsScreen | Switch | Enable notifications |
| `settings.dark_mode_checkbox` | SettingsScreen | Checkbox | Enable dark mode |
| `settings.volume_slider` | SettingsScreen | Slider | Volume (0.0–1.0) |
| `settings.logout_button` | SettingsScreen | ElevatedButton | Log out |

## Example test flow with Claude

Once the MCP server is running and registered with Claude Code, you can drive the app with natural language:

```
User: "Test the login flow with user@test.com and password123"

Claude:
  → inspect_ui
  → "Login screen. Email field (empty), password field (empty), login button (disabled)."
  → input_text(key=auth.email_field, text=user@test.com)
  → input_text(key=auth.password_field, text=password123)
  → assert_enabled(key=auth.login_button)
  → tap_widget(key=auth.login_button)
  → wait(duration_ms=1500)
  → assert_exists(key=screen.dashboard)
  → "Login successful. Now on DashboardScreen."
```

```
User: "Check if the volume slider is at 50%"

Claude:
  → inspect_ui
  → Found: {"type":"Slider","value":0.5,"min":0.0,"max":1.0,"key":"settings.volume_slider"}
  → "Volume slider is at 0.5 (50%). Correct."
```

```
User: "Set the volume to 75% and verify dark mode is off"

Claude:
  → set_slider_value(key=settings.volume_slider, value=0.75)
  → inspect_ui
  → Found Slider value=0.75 ✓
  → Found Checkbox value=false (dark mode) ✓
  → "Volume set to 75%. Dark mode is off."
```
