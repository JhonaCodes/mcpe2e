# Test Flow Example

Complete walkthrough of an AI-driven E2E test session using Claude + mcpe2e.

## Scenario: Test the login flow

---

### Tools available to Claude (27 total)

```
Context:     get_app_context · list_test_cases · inspect_ui · capture_screenshot
Gestures:    tap_widget · double_tap_widget · long_press_widget · swipe_widget
             scroll_widget · scroll_until_visible · tap_by_label
Input:       input_text · clear_text · select_dropdown · toggle_widget · set_slider_value
Keyboard:    hide_keyboard · press_back · wait
Assertions:  assert_exists · assert_text · assert_visible · assert_enabled
             assert_selected · assert_value · assert_count
```

---

### Step 1: Claude inspects the UI

Before acting, Claude inspects what is on screen. Two options:

**Option A — Registered widgets only** (faster, fewer tokens):
```
Claude calls: get_app_context
```
Response:
```json
{
  "screen": "LoginScreen",
  "route": "/login",
  "timestamp": "2026-03-09T10:00:00Z",
  "widgets": [
    {
      "key": "auth.email_field",
      "type": "TextField",
      "description": "Email input",
      "capabilities": ["tap", "text_input", "clear", "assert_exists", "assert_text"]
    },
    {
      "key": "auth.login_button",
      "type": "ElevatedButton",
      "description": "Login submit",
      "capabilities": ["tap", "long_press", "double_tap", "assert_exists", "assert_text"]
    }
  ]
}
```

**Option B — Full widget tree** (no registration needed, most complete):
```
Claude calls: inspect_ui
```
Response:
```json
{
  "timestamp": "2026-03-09T10:00:00Z",
  "widget_count": 18,
  "widgets": [
    { "type": "AppBar", "title": "Login", "depth": 3 },
    { "type": "Text", "value": "Welcome back", "depth": 5, "x": 16.0, "y": 120.0 },
    { "type": "TextField", "hint": "Email", "enabled": true, "depth": 6,
      "key": "auth.email_field", "x": 16.0, "y": 200.0 },
    { "type": "TextField", "hint": "Password", "enabled": true, "depth": 6,
      "key": "auth.password_field", "x": 16.0, "y": 280.0 },
    { "type": "ElevatedButton", "label": "Login", "enabled": false, "depth": 7,
      "key": "auth.login_button" },
    { "type": "Text", "value": "Forgot password?", "depth": 8 }
  ]
}
```

> `inspect_ui` found that the login button is **disabled** (`enabled: false`). Claude knows it must fill both fields first.

---

### Step 2: Claude types the email

```
Claude calls: input_text
  key: "auth.email_field"
  text: "user@example.com"
```

The Flutter library:
1. Finds the widget by key `auth.email_field`
2. Locates the `EditableText` descendant via `visitChildElements`
3. Updates the `TextEditingController` value
4. Dispatches focus events

---

### Step 3: Claude types the password

```
Claude calls: input_text
  key: "auth.password_field"
  text: "secret123"
```

---

### Step 4: Claude verifies the button is now enabled

```
Claude calls: assert_enabled
  key: "auth.login_button"
```

Response: `{"success":true,"widgetKey":"auth.login_button","eventType":"assertEnabled"}`

Or using `inspect_ui` again — the button entry now shows `"enabled": true`.

---

### Step 5: Claude taps the login button

```
Claude calls: tap_widget
  key: "auth.login_button"
```

The Flutter library:
1. Finds the widget by key
2. Gets its `RenderBox` and calculates the center point
3. Dispatches `PointerDownEvent` + `PointerUpEvent` via `GestureBinding`

---

### Step 6: Claude waits for navigation

```
Claude calls: wait
  duration_ms: 2000
```

---

### Step 7: Claude verifies the navigation result

```
Claude calls: inspect_ui
```

The response now shows `DashboardScreen` content — the login succeeded.

Or using a targeted assertion on the screen identifier:
```
Claude calls: assert_exists
  key: "screen.dashboard"
```

---

### Step 8: Claude takes a screenshot (optional visual check)

```
Claude calls: capture_screenshot
```

Claude receives the PNG image and can visually confirm the dashboard layout.

---

## Full conversation example

```
User: "Test the login flow with user@example.com and password secret123"

Claude: Checking what's on screen...
  → inspect_ui
  → "Login screen. Email field (empty), password field (empty),
     login button (disabled — needs both fields filled)."

Claude: Typing email...
  → input_text(key=auth.email_field, text=user@example.com)

Claude: Typing password...
  → input_text(key=auth.password_field, text=secret123)

Claude: Checking the button is enabled...
  → assert_enabled(key=auth.login_button)
  → "Button is enabled. Tapping..."

  → tap_widget(key=auth.login_button)
  → wait(duration_ms=2000)

Claude: Verifying the result...
  → inspect_ui
  → "Now on DashboardScreen. Login flow passed."
```

---

## Verifying data values on screen

```
User: "Verify the order total is $150.00"

Claude:
  → inspect_ui
  → Found: { "type": "Text", "value": "Total: $149.99", "depth": 8 }
  → "Total shows $149.99, not $150.00. Value mismatch detected."
```

> `inspect_ui` reads the exact `Text` widget value from the live widget tree — no selectors, no OCR, exact string.

---

## Form validation scenario

```
User: "Test login with an invalid password"

Claude:
  → input_text(key=auth.email_field, text=user@example.com)
  → input_text(key=auth.password_field, text=abc)   ← only 3 chars
  → tap_widget(key=auth.login_button)
  → wait(duration_ms=500)
  → inspect_ui
  → Found: { "type": "Text", "value": "Password must be at least 6 characters", "key": "auth.error_message" }
  → "Validation error shown correctly. Test passed."
```

---

## Dropdown selection

```
User: "Select 'Express' in the shipping dropdown"

Claude:
  → get_app_context          (find the dropdown key)
  → select_dropdown(key=order.shipping_type, value=Express)
  → inspect_ui               (verify selection applied)
```

---

## Scroll and interact

```
User: "Tap the Cancel button on the third item in the list"

Claude:
  → scroll_until_visible(key=order.list, target_key=order.item.2)
  → tap_widget(key=order.item.2.cancel_button)
  → wait(duration_ms=1000)
  → assert_exists(key=modal.confirm.cancel)   ← confirm dialog appeared
```

---

## Settings interaction

```
User: "Set volume to 75% and verify notifications are enabled"

Claude:
  → set_slider_value(key=settings.volume_slider, value=0.75)
  → inspect_ui
  → Found: { "type": "Slider", "value": 0.75, "key": "settings.volume_slider" } ✓
  → Found: { "type": "Switch", "value": true, "key": "settings.notifications_switch" } ✓
  → "Volume is at 75%. Notifications are enabled."
```
