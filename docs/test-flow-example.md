# Test Flow Examples

Complete walkthroughs of AI-driven E2E test sessions using coordinate-based testing with `inspect_ui` + `tap_at`. No widget keys or registration required.

---

## Example 1: Login flow

### Scenario

Test that a user can log in with valid credentials and land on the dashboard.

### Step 1: Inspect the screen

```
AI calls: inspect_ui
```

Response:

```json
{
  "widget_count": 14,
  "widgets": [
    { "type": "AppBar", "title": "Login", "depth": 2 },
    { "type": "Text", "value": "Welcome back", "depth": 4, "x": 16, "y": 120, "w": 200, "h": 24 },
    { "type": "TextField", "hint": "Email", "enabled": true, "depth": 5, "x": 16, "y": 200, "w": 358, "h": 56 },
    { "type": "TextField", "hint": "Password", "enabled": true, "depth": 5, "x": 16, "y": 276, "w": 358, "h": 56 },
    { "type": "ElevatedButton", "label": "Login", "enabled": false, "depth": 6, "x": 20, "y": 360, "w": 350, "h": 52 },
    { "type": "Text", "value": "Forgot password?", "depth": 7, "x": 100, "y": 430, "w": 160, "h": 20 }
  ]
}
```

The AI can see the login button is disabled (`"enabled": false`). It must fill both fields first.

### Step 2: Type the email

```
AI calls: input_text
  key: "auth.email_field"
  text: "user@example.com"
```

### Step 3: Type the password

```
AI calls: input_text
  key: "auth.password_field"
  text: "secret123"
```

### Step 4: Inspect again to confirm the button is now enabled

```
AI calls: inspect_ui
```

Response (button entry only):

```json
{ "type": "ElevatedButton", "label": "Login", "enabled": true, "x": 20, "y": 360, "w": 350, "h": 52 }
```

### Step 5: Tap the login button using coordinates

```
AI calls: tap_at
  x: 195   ← 20 + 350/2
  y: 386   ← 360 + 52/2
```

### Step 6: Wait for navigation

```
AI calls: wait
  duration_ms: 2000
```

### Step 7: Verify the result

```
AI calls: inspect_ui
```

Response now contains `DashboardScreen` content — the login succeeded.

```
AI calls: capture_screenshot
```

The AI receives the PNG and can visually confirm the dashboard layout.

### Step 8: Assert a specific text on screen

```
AI calls: assert_text
  key: "dashboard.greeting"
  text: "Hello, user"
```

Or without a key, verify visually using `inspect_ui`:

```json
{ "type": "Text", "value": "Hello, user", "depth": 5, "x": 16, "y": 80 }
```

---

## Example 2: Dynamic list — tapping a card without keys

### Scenario

The app displays a list of orders. Each card is built dynamically from an API response and has no registered key. The AI must find and tap a specific card.

### Step 1: Inspect the screen

```
AI calls: inspect_ui
```

Response (excerpt):

```json
{
  "widget_count": 31,
  "widgets": [
    { "type": "AppBar", "title": "Orders", "depth": 2 },
    { "type": "Card", "depth": 4, "x": 12, "y": 100, "w": 370, "h": 90 },
    { "type": "Text", "value": "Order #1042", "depth": 6, "x": 24, "y": 115, "w": 180, "h": 22 },
    { "type": "Text", "value": "Pending", "depth": 6, "x": 280, "y": 115, "w": 80, "h": 22 },
    { "type": "Card", "depth": 4, "x": 12, "y": 202, "w": 370, "h": 90 },
    { "type": "Text", "value": "Order #1043", "depth": 6, "x": 24, "y": 217, "w": 180, "h": 22 },
    { "type": "Text", "value": "Shipped", "depth": 6, "x": 280, "y": 217, "w": 80, "h": 22 },
    { "type": "Card", "depth": 4, "x": 12, "y": 304, "w": 370, "h": 90 },
    { "type": "Text", "value": "Order #1044", "depth": 6, "x": 24, "y": 319, "w": 180, "h": 22 },
    { "type": "Text", "value": "Delivered", "depth": 6, "x": 280, "y": 319, "w": 80, "h": 22 }
  ]
}
```

### Step 2: Identify the target card and calculate its center

The AI wants to open "Order #1043". From `inspect_ui`:
- Card at `x: 12, y: 202, w: 370, h: 90`
- Center: `x = 12 + 370/2 = 197`, `y = 202 + 90/2 = 247`

### Step 3: Tap the card

```
AI calls: tap_at
  x: 197
  y: 247
```

### Step 4: Wait and verify navigation

```
AI calls: wait
  duration_ms: 1000

AI calls: inspect_ui
```

Response now shows the order detail screen with title "Order #1043".

No widget keys were registered. No code was changed in the app. The AI found the widget from the live tree and tapped it by coordinate.

---

## Example 3: Verifying a value on screen

### Scenario

After completing a checkout, verify that the order total displayed on screen matches the expected amount.

### Step 1: Inspect the confirmation screen

```
AI calls: inspect_ui
```

Response (excerpt):

```json
{
  "widget_count": 18,
  "widgets": [
    { "type": "AppBar", "title": "Order Confirmation", "depth": 2 },
    { "type": "Text", "value": "Subtotal", "depth": 5, "x": 16, "y": 200 },
    { "type": "Text", "value": "$142.00", "depth": 5, "x": 280, "y": 200 },
    { "type": "Text", "value": "Shipping", "depth": 5, "x": 16, "y": 232 },
    { "type": "Text", "value": "$8.00", "depth": 5, "x": 280, "y": 232 },
    { "type": "Text", "value": "Total", "depth": 5, "x": 16, "y": 280 },
    { "type": "Text", "value": "$150.00", "depth": 5, "x": 280, "y": 280, "w": 80, "h": 24 }
  ]
}
```

### Step 2: The AI reads the value directly from the widget tree

The `inspect_ui` response includes the exact string rendered by each `Text` widget. The AI finds `"$150.00"` next to `"Total"` and confirms it matches the expected value.

No assertion tool is needed — the value is already in the tree response. If a mismatch is found, the AI reports it with the exact observed value.

### Step 3: Take a screenshot for a visual record

```
AI calls: capture_screenshot
```

The screenshot and the tree data together provide a complete record of the screen state at that point in the test.

---

## Summary: coordinate-based workflow

Every test follows the same pattern:

```
inspect_ui
  → read widget type, label, x, y, w, h
  → calculate center: cx = x + w/2, cy = y + h/2

tap_at x: cx y: cy
  → real tap dispatched via GestureBinding

wait duration_ms: N
  → allow animations and navigation to settle

inspect_ui
  → verify new screen content or text values

capture_screenshot
  → visual confirmation
```

This works for any widget in the tree: buttons, cards, list items, tabs, chips, icons. No keys. No registration. No app code changes required.
