# Test Flow Example

Complete walkthrough of an AI-driven E2E test session using Claude + mcpe2e.

## Scenario: Test the login flow

---

### Tools available to Claude (27 total)

```
Contexto:   get_app_context · list_test_cases · inspect_ui · capture_screenshot
Gestos:     tap_widget · double_tap_widget · long_press_widget · swipe_widget
            scroll_widget · scroll_until_visible · tap_by_label
Input:      input_text · clear_text · select_dropdown · toggle_widget · set_slider_value
Teclado:    hide_keyboard · press_back · wait
Aserciones: assert_exists · assert_text · assert_visible · assert_enabled
            assert_selected · assert_value · assert_count
```

---

### Step 1: Claude inspects the UI

Before doing anything, Claude inspects what's on screen. Two options:

**Option A — Registered widgets only** (faster, less tokens):
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

**Option B — Full widget tree** (zero registration needed, more complete):
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

> `inspect_ui` found that the login button is **disabled** (`enabled: false`). Claude knows it needs to fill the fields first.

---

### Step 2: Claude types the email

```
Claude calls: input_text
  key: "auth.email_field"
  text: "test@example.com"
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

### Step 4: Claude verifies button is now enabled

```
Claude calls: inspect_ui
```

Now the button entry shows `"enabled": true` — the form validation passed.

Or using a targeted assertion:
```
Claude calls: assert_enabled
  key: "auth.login_button"
```
Response: `{"success":true,"widgetKey":"auth.login_button","eventType":"assertEnabled"}`

---

### Step 5: Claude taps login

```
Claude calls: tap_widget
  key: "auth.login_button"
```

The Flutter library:
1. Finds widget by key
2. Gets `RenderBox` and calculates center
3. Dispatches `PointerDownEvent` + `PointerUpEvent` via `GestureBinding`

---

### Step 6: Claude waits for navigation

```
Claude calls: wait
  duration_ms: 2000
```

---

### Step 7: Claude verifies navigation

```
Claude calls: inspect_ui
```

Response now shows different widgets — `DashboardScreen` content.

Or assert the screen identifier:
```
Claude calls: assert_exists
  key: "screen.dashboard"
```

---

### Step 8: Claude takes a screenshot (optional)

When layout verification is needed (not just data values):

```
Claude calls: capture_screenshot
```

Claude receives the PNG image and can visually confirm the dashboard layout, colors, and arrangement.

---

## Full conversation transcript

```
User: "Test the login flow with test@example.com / secret123"

Claude: Checking what's on screen...
→ inspect_ui
→ "Login screen. Email field (empty), password field (empty),
   login button (disabled — needs input first)."

Claude: Filling email...
→ input_text(key=auth.email_field, text=test@example.com)

Claude: Filling password...
→ input_text(key=auth.password_field, text=secret123)

Claude: Verifying button is enabled now...
→ assert_enabled(key=auth.login_button)
→ "Button is enabled. Tapping..."

→ tap_widget(key=auth.login_button)
→ wait(duration_ms=2000)

Claude: Verifying login result...
→ inspect_ui
→ "Now on DashboardScreen. Login flow passed."
```

---

## Error scenario: wrong value on screen

```
User: "Verify the order total is $150.00"

Claude:
→ inspect_ui
→ Found: { "type": "Text", "value": "Total: $149.99", "depth": 8 }
→ "Total shows $149.99, not $150.00. Value mismatch detected."
```

> `inspect_ui` directly reads the `Text` widget value from the live widget tree — no selectors, no OCR, exact string match.

---

## Error scenario: form validation

```
User: "Test login with an invalid email"

Claude:
→ input_text(key=auth.email_field, text=not-an-email)
→ tap_widget(key=auth.login_button)
→ wait(duration_ms=500)
→ inspect_ui
→ Found: { "type": "Text", "value": "Please enter a valid email", "depth": 9 }
→ "Validation error shown correctly. Test passed."
```

---

## Dropdown selection example

```
User: "Select 'Express' in the shipping dropdown"

Claude:
→ get_app_context   (to find the dropdown key)
→ select_dropdown(key=order.shipping_type, value=Express)
→ inspect_ui        (verify selection applied)
```

---

## Scroll and interact example

```
User: "Tap the 'Cancel' button in the order list — it's the third item"

Claude:
→ scroll_until_visible(key=order.list, target_key=order.card.3)
→ tap_widget(key=order.card.3.cancel_button)
→ wait(duration_ms=1000)
→ assert_exists(key=modal.confirm.cancel)   (confirm dialog appeared)
```
