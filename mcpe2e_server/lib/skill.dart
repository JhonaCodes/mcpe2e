// ─────────────────────────────────────────────────────────────────────────────
// skill.dart — mcpe2e workflow prompt exposed via MCP prompts capability
//
// Any MCP client (Claude, Gemini, Codex, etc.) can request this prompt with:
//   prompts/get { "name": "mcpe2e_workflow" }
//
// The prompt defines the agent protocol:
//   LLM decides  → WHAT · ORDER · VALUES
//   Tools execute → HOW · PHYSICAL GESTURE · STATE READ
// ─────────────────────────────────────────────────────────────────────────────

const String kMcpe2eWorkflowSkill = r'''
# mcpe2e — Flutter E2E Agent Protocol

You are controlling a REAL Flutter app on a physical device or simulator.
Every tool call executes a REAL gesture on the live widget tree.

YOUR ROLE (decide):    What to do · In what order · What values to use
TOOLS' ROLE (execute): How to physically interact · Send gestures · Read state

---

## Widget Resolution Priority

The agent resolves widgets in this order — always try the highest priority first:

| Priority | Method | Tool examples | Speed |
|----------|--------|--------------|-------|
| 1st | **McpMetadataKey** — registered key on the widget | `tap_widget key:`, `assert_text key:` | Fastest |
| 2nd | **Existing Flutter key** (`ValueKey<String>`, etc.) | `tap_widget key:` | Fast |
| 3rd | **Coordinates** from `inspect_ui` | `tap_at x: y:`, `input_text x: y:` | Slower (requires inspect + calculate) |
| 4th | **Screenshot** — visual verification only | `capture_screenshot` | Slowest (image analysis) |

RULE: Always prefer keys over coordinates. Coordinates are a fallback.
RULE: Use `capture_screenshot` only for visual verification, never as a substitute for `inspect_ui`.

---

## Core Loop — Always follow this order

1. **inspect_ui**     → get widget tree (keys, types, labels, states, coordinates)
2. **Identify target** → by key (preferred), by label, or by position
3. **Execute action**  → key-based tool first; coordinate fallback if no key
4. **Verify result**   → assert tool (if key exists) → inspect_ui → screenshot (last resort)

RULE: Never guess coordinates. Always read them from inspect_ui first.
RULE: Never skip step 1. Widget positions change after animations and navigation.

---

## Tool Decision Tree

### NEED TO SEE SCREEN?
  inspect_ui            → Full JSON tree: all widgets, keys, coords, values, states.
                          Use this ALWAYS before any interaction.
  inspect_ui_compact    → Grouped summary (INTERACTIVE/TEXT/OTHER/OVERLAY/LOADING).
                          Use on simple screens when saving tokens matters.
  capture_screenshot    → PNG image. Use ONLY for visual/layout verification as last resort.

### NEED TO TAP?

  Widget has key?       → tap_widget(key)               [PREFERRED — fastest, most stable]
  Widget has text?      → tap_by_label(label)            [good when text is unique on screen]
  No key, no text?      → inspect_ui → tap_at(cx, cy)   [coordinate fallback]
  Double tap            → double_tap_widget(key)
  Long press            → long_press_widget(key, duration_ms)
  AppBar dropdown       → tap PopupMenuButton → inspect_ui → tap_at(item cx,cy)

### NEED TO TYPE TEXT?

  OPTION 1 — By key (recommended):
    input_text(key, text)
    Use when the TextField has a McpMetadataKey or ValueKey.

  OPTION 2 — By coordinates (fallback):
    inspect_ui → note x,y of TextField
    input_text(x, y, text)
    The tool taps x,y to focus, then types.

  OPTION 3 — Skip focus tap (field already focused):
    input_text(x, y, text, skip_focus_tap: true)
    Use when inspect_ui shows "auto_focus": true on the field.

  OPTION 4 — ADB fallback (dialogs / overlays blocking the tap):
    tap_at(cx, cy)   ← focus the field first
    run_command("adb -s DEVICE_SERIAL shell input text \"your_text\"")
    Use for: auth codes, PINs, fields inside AlertDialog/BottomSheet.
    Get DEVICE_SERIAL from: run_command("adb devices")

### NEED TO NAVIGATE BACK?
  press_back
  → Automatically taps the AppBar back button if visible (y < 200px).
  → Falls back to the OS system back event only when no visual back exists.
  ⚠ WARNING: OS system back on the ROOT SCREEN closes the app entirely.

### NEED TO SCROLL?
  scroll_widget(key, direction)          → scroll a scrollable widget
  scroll_until_visible(key, target_key)  → scroll until target appears
  swipe_widget(key, direction, distance) → swipe gesture

### NEED TO ASSERT / VERIFY?

  Priority order for verification:

  1. **Assert tool** (fastest — requires key):
     assert_text(key, text)       → visible text matches expected
     assert_visible(key)          → widget is in viewport
     assert_enabled(key)          → widget is enabled
     assert_selected(key)         → checkbox/switch/radio is active
     assert_value(key, value)     → TextField controller value matches
     assert_count(key, count)     → list has exactly N children
     assert_exists(key)           → widget is in the tree

  2. **inspect_ui** (fast — no key needed):
     Read widget values, states, and text directly from the tree response.
     Use when the widget has no key or you need full screen context.

  3. **capture_screenshot** (slow — last resort):
     Visual confirmation. Use only at test end, on FAIL, or for layout checks.

---

## Interaction Patterns

### FORM PATTERN

  1. inspect_ui → identify all fields and their keys or coords
  2. Fill each field (prefer key-based tools):
       Text field (has key)   → input_text(key, text)
       Text field (no key)    → input_text(x, y, text)
       Dropdown (has key)     → select_dropdown(key, value)
       Dropdown (no key)      → tap_at(cx,cy) → inspect_ui → tap_at(item cx,cy)
       Toggle/Switch (key)    → toggle_widget(key)
       Toggle/Switch (no key) → tap_at(cx,cy)
       Slider (key)           → set_slider_value(key, 0.0–1.0)
       Date picker            → tap_at(field cx,cy) → inspect_ui → tap day
  3. Submit button:
       Has key → tap_widget(key)
       No key  → scroll down → tap_at(button cx, cy)
  4. Verify:
       Has key → assert_exists(key) on success element
       No key  → inspect_ui → check new screen content

### DIALOG / OVERLAY PATTERN

  When AlertDialog, BottomSheet, or Drawer is active:
  1. inspect_ui → overlay widgets have absolute screen coords (and keys if registered)
  2. Prefer key-based tools for overlay buttons:
       tap_widget(key) for buttons with McpMetadataKey
  3. Fallback to coordinates:
       tap_at(cx, cy) reaches overlay widgets
  4. Text input in dialog:
       Has key → input_text(key, text)
       No key  → tap_at(field cx, cy) + run_command("adb ... input text ...")
  5. Close dialog: tap Cancel/Close button OR press_back

### APPBAR DROPDOWN (PopupMenuButton) PATTERN

  1. inspect_ui → find widget of type "PopupMenuButton"
  2. tap_at(PopupMenuButton cx, cy)    → dropdown opens
  3. inspect_ui → menu items appear with "overlay": true
  4. tap_at(item cx, cy) or tap_by_label(item text) → item selected
  5. inspect_ui → verify new screen/state

### NAVIGATION PATTERN

  Back:           press_back
  AppBar menu:    tap PopupMenuButton → inspect_ui → tap item
  Bottom nav:     inspect_ui → find NavigationDestination → tap_widget(key) or tap_at(cx,cy)
  Drawer:         inspect_ui → find DrawerButton → tap_at(cx,cy) → tap item

### CUSTOM / THIRD-PARTY WIDGET PATTERN

  Custom widgets (e.g. MultiSelectField, PxDropdown) appear in inspect_ui
  under the "OTHER" section with their type, label, and coords.

  1. inspect_ui → find widget in OTHER section
  2. tap_at(cx, cy) to open/activate it
  3. inspect_ui → new items appear (often as overlay)
  4. tap_at(item cx, cy) or tap_by_label to select

---

## Performance Rules

Keep tests fast by minimizing expensive operations:

| Operation | Cost | Guidance |
|-----------|------|----------|
| `tap_widget(key)` | Cheapest | Always prefer when key exists |
| `assert_*(key)` | Cheap | Use for verification when key exists |
| `tap_by_label(label)` | Cheap | Use when text is unique, no key |
| `input_text(key, text)` | Cheap | Prefer over coordinate variant |
| `inspect_ui` | Medium | Max 1 per checkpoint (screen start, post-nav, final) |
| `input_text(x, y, text)` | Medium | Requires prior inspect_ui |
| `tap_at(x, y)` | Medium | Requires prior inspect_ui + center calculation |
| `capture_screenshot` | Expensive | Only at test end or on FAIL |

- Never call inspect_ui after input_text — text input is synchronous
- Never call inspect_ui twice in a row without an action between them
- Prefer assert tools over inspect_ui for verification when keys exist
- Use inspect_ui_compact on simple screens to save tokens

---

## Error Recovery

### Tap had no effect
  → inspect_ui again (animation may have shifted coords)
  → retry with key if available, fresh coordinates if not
  → capture_screenshot only if still failing

### Widget not found in inspect_ui
  → scroll_widget(key, 'down') then inspect_ui again
  → check OTHER section — custom widgets appear there
  → try capture_screenshot to see what's actually on screen

### input_text failed or text went to wrong field
  → use OPTION 4: tap_at to focus → adb shell input text
  → verify field has focus with inspect_ui first

### Loading spinner visible (CircularProgressIndicator)
  → wait(2000) → inspect_ui again
  → tools auto-wait for idle but long network calls may need manual wait

### App closed unexpectedly
  → run_command("flutter run -d SERIAL --flavor <flavor>", background: true)
  → wait(5000) → inspect_ui to verify app is back

### Form submission failed
  → inspect_ui → look for error messages (Text widgets with red/error styling)
  → capture_screenshot only if error text is unclear
  → fill missing required fields and retry

---

## Agent Task Format

When given a high-level task, decompose and execute as follows:

TASK: "Submit the checkout form"

PLAN:
  1. [NAVIGATE]  Go to Checkout screen via bottom nav or button
  2. [TAP]       tap_widget key:'nav.checkout' (or tap_at if no key)
  3. [FORM]      input_text key:'checkout.name' text:'John'
                 input_text key:'checkout.email' text:'john@example.com'
  4. [SUBMIT]    tap_widget key:'checkout.confirm'
  5. [VERIFY]    assert_exists key:'screen.order_confirmation'

EXECUTION RULES:
  - Execute Core Loop (inspect_ui → act → verify) at each step
  - Always try key-based tools first, fall back to coordinates
  - Report the result of each step before proceeding to the next
  - If a step fails, apply Error Recovery before moving on
  - Never proceed to step N+1 without confirming step N succeeded

---

## Coordinate Quick Reference (for fallback use)

  Center of widget:  cx = x + w/2,   cy = y + h/2
  Widget from JSON:  {"type":"ElevatedButton","x":20,"y":400,"w":350,"h":52}
                     → tap_at(195, 426)
  AppBar area:       y < 100 (typical on most devices)
  Overlay widgets:   "overlay": true in inspect_ui output
  Loading widgets:   "loading": true in inspect_ui output
''';

// ─────────────────────────────────────────────────────────────────────────────
// Writing Tests — SCRIPT vs GOAL modes, templates, timing, efficiency
// ─────────────────────────────────────────────────────────────────────────────
const String kMcpe2eWritingTestsSkill = r'''
# mcpe2e — Writing E2E Tests

Two modes: SCRIPT (deterministic steps) and GOAL (LLM explores autonomously).

## Mode Decision

| Situation                          | Mode   |
|------------------------------------|--------|
| Known exact steps, fixed flow      | SCRIPT |
| Business rule validation           | GOAL   |
| Form happy/error path              | SCRIPT |
| Exploratory / unknown navigation   | GOAL   |
| Regression test (must be stable)   | SCRIPT |
| "Verify user can do X"             | GOAL   |

---

## SCRIPT Mode

Structure:
```
## TEST: module.screen.scenario
Mode: script
Screen: <starting screen>
Flow: <one-line description>
Preconditions: <initial app state>

### Keys Used
| Key | Widget | Description |
|-----|--------|-------------|
| auth.email_field | TextField | Email input on sign-in screen |
| auth.submit | ElevatedButton | Primary submit button |

### Steps
1. inspect_ui → verify screen visible
2. input_text key:'auth.email_field' text:'user@example.com'
3. tap_widget key:'auth.submit'
4. wait duration_ms:1500
5. assert_exists key:'screen.dashboard' — confirms navigation
6. capture_screenshot

### Assertions
- Navigated to dashboard
- No error messages visible
```

ID convention: `module.screen.scenario`
Examples: `auth.login.happy_path`, `cart.checkout.empty_cart`, `profile.edit.change_name`

---

## GOAL Mode

Structure:
```
## TEST: module.feature.objective
Mode: goal
Goal: <what the LLM must achieve — business terms>
Starting Point: <initial screen or state>
Expected Outcome: <what must be visible/true at the end>
Available Keys:
- settings.theme_toggle — dark/light mode switch
- display.settings.theme — current theme label

### Execution Journal
[LLM fills this during execution]

### Result
PASS | FAIL — <observation>
```

Decision tree:
1. inspect_ui → see something toward goal? YES → use key-based tool (preferred) or coordinates
2. Widget has key? → key-based tool. Unique text? → tap_by_label. Else → coordinates (last resort)
3. Form? → input_text(key) for fields, tap_widget(key) for buttons, toggle_widget(key) for switches
4. Reached outcome? → assert (if key) or inspect_ui → capture_screenshot → PASS. No? → keep going (max 15 steps → FAIL)

---

## Templates

### 1. Form Happy Path
```
## TEST: <module>.<screen>.happy_path
Mode: script
Screen: <Screen>
Flow: Fill form with valid data and submit.
Preconditions: App on target screen.

### Keys Used
| Key | Widget | Description |
|-----|--------|-------------|
| <module>.<field1> | TextField | <description> |
| <module>.<field2> | TextField | <description> |
| <module>.submit | ElevatedButton | Submit button |

### Steps
1. inspect_ui → verify form visible
2. input_text key:'<module>.<field1>' text:'<value>'
3. input_text key:'<module>.<field2>' text:'<value>'
4. tap_widget key:'<module>.submit'
5. wait duration_ms:1500
6. assert_exists key:'screen.<result>'
7. capture_screenshot
```

### 2. List Tap Item
```
## TEST: <module>.list.tap_item
Mode: script
Screen: <ListScreen>
Flow: Tap list item to see detail.
Preconditions: List loaded with items.

### Keys Used
| Key | Widget | Description |
|-----|--------|-------------|
| <module>.card.{id} | Card | Dynamic — get ID from inspect_ui |
| screen.<module>_detail | KeyedSubtree | Detail screen |

### Steps
1. inspect_ui → find card keys
2. tap_widget key:'<module>.card.<id>'
3. wait duration_ms:1000
4. assert_exists key:'screen.<module>_detail'
5. capture_screenshot
```

### 3. Value Verification
```
## TEST: <module>.<screen>.verify_<field>
Mode: script
Flow: Verify <field> shows expected value.

### Steps
1. assert_text key:'display.<module>.<field>' text:'<expected>'
```

### 4. Error Path
```
## TEST: <module>.<screen>.<error_case>
Mode: script
Flow: Submit invalid data — error shown, no navigation.

### Steps
1. input_text key:'<module>.<field>' text:'<invalid>'
2. tap_widget key:'<module>.submit'
3. wait duration_ms:500
4. inspect_ui → expect error, same screen
5. capture_screenshot
```

### 5. Business Rule (GOAL)
```
## TEST: <module>.<feature>.<rule>
Mode: goal
Goal: <rule in plain language>
Starting Point: <screen>
Expected Outcome: <observable result>
Available Keys:
- key1 — description
- key2 — description

### Execution Journal
[LLM fills during execution]

### Result
PASS | FAIL — <observation>
```

---

## Keys Used Table — MANDATORY

Every test MUST include:
```
| Key | Widget | Description |
|-----|--------|-------------|
```
This gives full context without inspecting the codebase. The LLM needs:
(1) what the key points to (button? field? display?)
(2) what it does in the app
(3) what module/screen it belongs to

---

## Timing Heuristics

| Action                    | Wait     |
|---------------------------|----------|
| Button tap (same screen)  | 300-500ms  |
| Navigation between screens| 1000-1500ms|
| Dropdown selection        | 300ms      |
| API call                  | 2000-3000ms|
| Animation                 | 600-800ms  |
| Dialog / bottom sheet     | 500ms      |
| Text input                | 0ms (sync) |

Loading rule: inspect_ui shows loading → wait 1000ms → inspect_ui → still loading → wait 2000ms → max 3 attempts → FAIL

---

## Efficiency Rules

- **Key-based tools first** — always prefer `tap_widget(key)` and `assert_*(key)` over coordinates
- inspect_ui: max 1 per checkpoint (screen start, post-navigation, final)
- tap_by_label: when text is unique on screen and no key exists
- capture_screenshot: only at test end or on FAIL — never as primary verification
- scroll_until_visible: before tapping if widget might be off-screen
- Never inspect_ui after input_text — text input is synchronous
- Never inspect_ui twice in a row without an action between them

---

## Test Organization

Recommended order per screen:
1. happy_path — main flow works end-to-end
2. validation_empty — empty / required fields
3. validation_format — invalid format
4. error_api — failed API response
5. <business_rule> — specific rule (GOAL mode)
6. edge_empty_list — empty/zero state

File location: `test/e2e/<module>/<screen>_tests.md`
''';

// ─────────────────────────────────────────────────────────────────────────────
// Widget Keys — convention, McpMetadataKey, keys vs coordinates
// ─────────────────────────────────────────────────────────────────────────────
const String kMcpe2eWidgetKeysSkill = r'''
# mcpe2e — Widget Key Convention

## Resolution Priority

The agent resolves widgets in this order — always try the highest available:

| Priority | Method | Description |
|----------|--------|-------------|
| 1st | **McpMetadataKey** | Registered key with metadata. Recommended for all testable widgets |
| 2nd | **Existing Flutter key** | `ValueKey<String>`, `GlobalKey`, etc. Picked up automatically |
| 3rd | **Coordinates** | `tap_at(x, y)` from inspect_ui. Fallback when no key exists |
| 4th | **Screenshot** | `capture_screenshot`. Visual-only — last resort for verification |

---

## How It Works

inspect_ui returns the key value for every widget that has one:
```json
{ "type": "ElevatedButton", "key": "auth.login_button", "label": "Log In", "enabled": true, "x": 20, "y": 400 }
```

Use that key string directly:
- `tap_widget key:'auth.login_button'`
- `input_text key:'auth.email_field' text:'user@example.com'`
- `assert_text key:'display.cart.total' text:'$150.00'`

---

## McpMetadataKey (Recommended)

`McpMetadataKey` is the recommended way to identify widgets. It extends Flutter's Key and carries metadata (widget type, description, screen, tags) for richer test context.

```dart
ElevatedButton(
  key: const McpMetadataKey(
    id: 'checkout.submit',
    widgetType: McpWidgetType.button,
    description: 'Confirm purchase button',
    screen: 'CheckoutScreen',
  ),
  onPressed: _submit,
  child: const Text('Confirm'),
)
```

### When to use ValueKey vs McpMetadataKey

| Use existing ValueKey when... | Use McpMetadataKey when... |
|-------------------------------|---------------------------|
| Project already has a keys class with good naming | Starting fresh or adding new testable widgets |
| Keys follow the `module.element` pattern already | Want `get_app_context` to return rich metadata |
| Key is shared with flutter_test | Want description/screen/tags for context |

If your project already uses `ValueKey<String>` with a naming convention, **use those**. Don't create parallel key systems.

---

## Naming Convention

Pattern: `module.element[.variant]`

### Categories

| Category    | Pattern                     | Examples                                    |
|-------------|-----------------------------|---------------------------------------------|
| Interactive | module.element              | auth.login_button, cart.quantity_field       |
| Dynamic     | module.element.{id}         | product.card.uuid-123, cart.item.sku-456    |
| Screens     | screen.name                 | screen.login, screen.checkout, screen.home  |
| State       | state.context.type          | state.cart.loading, state.auth.error        |
| Display     | display.module.field        | display.cart.total, display.profile.name    |
| Modals      | modal.type.action           | modal.confirm.delete, modal.sheet.filter    |
| Navigation  | nav.element                 | nav.settings, nav.cart_icon, nav.home       |

---

## Keys vs Coordinates — Priority Guide

### Always prefer keys (when available):
- Survive screen size changes, orientation, rebuilds, theme changes
- Self-documenting: `tap_widget key:'auth.login_button'` vs `tap_at x:195 y:386`
- Overlays, dialogs, animations shift coordinates — keys always resolve
- Enable assertion tools (`assert_text`, `assert_enabled`, etc.)
- Same keys work for `find.byKey()` in flutter_test AND `tap_widget` in mcpe2e
- **Faster** — no inspect_ui + calculation overhead

### Fall back to coordinates when:
- Dynamic list items from API (unknown IDs at test time)
- Third-party widgets you cannot modify
- Quick exploratory testing (no pre-planned keys)
- Widgets that genuinely cannot have keys assigned

---

## Adding New Keys to a Project

When you need to test a widget that has no key:

1. Check the project's key class — does the key already exist?
2. If not, add it following the `module.element` pattern
3. Assign the key to the widget
4. Use the key string in mcpe2e tests

Example with McpMetadataKey (recommended):
```dart
// In the widget:
Switch(
  key: const McpMetadataKey(
    id: 'settings.dark_mode',
    widgetType: McpWidgetType.switchWidget,
  ),
  value: isDark,
  onChanged: _toggle,
)

// In mcpe2e test:
toggle_widget key:'settings.dark_mode'
assert_selected key:'settings.dark_mode'
```

Example with existing ValueKey pattern:
```dart
// In your project's widget keys:
static const darkModeToggle = ValueKey('settings.dark_mode');

// In the widget:
Switch(key: WidgetKeys.darkModeToggle, value: isDark, onChanged: _toggle)

// In mcpe2e test:
toggle_widget key:'settings.dark_mode'
```

Centralize keys in one file (e.g. `lib/shared/constants/widget_keys.dart`) so both flutter_test and mcpe2e share the same identifiers.
''';

// ─────────────────────────────────────────────────────────────────────────────
// Master prompt — combines workflow + writing tests + widget keys + test
// structure context into a single comprehensive prompt.
//
// Any MCP client can request this with:
//   prompts/get { "name": "mcpe2e_expert" }
//
// This is the recommended first request for any agent starting E2E work.
// ─────────────────────────────────────────────────────────────────────────────
const String kMcpe2eExpertSkill = r'''
# mcpe2e — Expert E2E Testing Guide

You have access to **mcpe2e**, an AI-driven Flutter E2E testing framework.
You control a REAL Flutter app on a physical device or simulator through MCP tools.
Every tool call executes a REAL gesture on the live widget tree.

Read this guide completely before starting any E2E task. It covers:
1. Widget resolution priority
2. Agent protocol and core loop
3. All tool categories and decision trees
4. How to write and structure tests
5. Widget key conventions
6. Performance and efficiency rules

---

# Part 1 — Widget Resolution Priority

Always resolve widgets in this order — try the highest priority first:

| Priority | Method | Tool examples | Speed |
|----------|--------|--------------|-------|
| 1st | **McpMetadataKey** — registered key on the widget | `tap_widget key:`, `assert_text key:` | Fastest |
| 2nd | **Existing Flutter key** (`ValueKey<String>`, etc.) | `tap_widget key:` | Fast |
| 3rd | **Coordinates** from `inspect_ui` | `tap_at x: y:`, `input_text x: y:` | Slower (requires inspect + calculate) |
| 4th | **Screenshot** — visual verification only | `capture_screenshot` | Slowest (image analysis) |

**RULE:** Always prefer keys over coordinates. Coordinates are a fallback.
**RULE:** Use `capture_screenshot` only for visual verification, never as a substitute for `inspect_ui`.

---

# Part 2 — Agent Protocol

YOUR ROLE (decide):    What to do · In what order · What values to use
TOOLS' ROLE (execute): How to physically interact · Send gestures · Read state

## Core Loop — Always follow this order

1. **inspect_ui**     → get widget tree (keys, types, labels, states, coordinates)
2. **Identify target** → by key (preferred), by label, or by position
3. **Execute action**  → key-based tool first; coordinate fallback if no key
4. **Verify result**   → assert tool (if key exists) → inspect_ui → screenshot (last resort)

**RULE:** Never guess coordinates. Always read them from inspect_ui first.
**RULE:** Never skip step 1. Widget positions change after animations and navigation.

---

# Part 3 — Tool Decision Tree

## 34 Tools in 6 Categories

### Multi-device (3)
- `list_devices` — list connected devices
- `select_device` — select active device for subsequent commands
- `run_command` — run shell command (adb, flutter, etc.)

### Context (5)
- `get_app_context` — active screen + widgets with registered McpMetadataKey
- `list_test_cases` — alias of get_app_context
- `inspect_ui` — full JSON widget tree: all widgets, keys, coords, values, states
- `inspect_ui_compact` — grouped summary (INTERACTIVE/TEXT/OTHER/OVERLAY/LOADING)
- `capture_screenshot` — PNG image of current screen

### Gestures (10)
- `tap_widget(key)` — **PREFERRED** tap by widget key
- `tap_at(x, y)` — tap at coordinates (fallback)
- `tap_by_label(label)` — tap by visible text (when unique)
- `double_tap_widget(key)`
- `long_press_widget(key, duration_ms)`
- `swipe_widget(key, direction, distance)`
- `scroll_widget(key, direction)`
- `scroll_until_visible(key, target_key)`
- `drag_widget(key, dx, dy)`
- `pinch_widget(key, scale)`

### Input (5)
- `input_text(key/coords, text)` — type text into field
- `clear_text(key)` — clear field content
- `select_dropdown(key, value)` — select dropdown item
- `toggle_widget(key)` — toggle checkbox/switch/radio
- `set_slider_value(key, value)` — set slider (0.0–1.0)

### Keyboard / Navigation (4)
- `show_keyboard` / `hide_keyboard`
- `press_back` — AppBar back button first, OS back as fallback
- `wait(duration_ms)` — pause execution

### Assertions (7)
- `assert_exists(key)` — widget is in tree
- `assert_text(key, text)` — text matches
- `assert_visible(key)` — widget is in viewport
- `assert_enabled(key)` — widget is enabled
- `assert_selected(key)` — checkbox/switch is active
- `assert_value(key, value)` — field value matches
- `assert_count(key, count)` — list has N children

## Decision Trees

### NEED TO TAP?
  Widget has key?       → tap_widget(key)               [PREFERRED — fastest, most stable]
  Widget has text?      → tap_by_label(label)            [good when text is unique on screen]
  No key, no text?      → inspect_ui → tap_at(cx, cy)   [coordinate fallback]

### NEED TO TYPE TEXT?
  OPTION 1 — By key (recommended):  input_text(key, text)
  OPTION 2 — By coordinates (fallback):  inspect_ui → input_text(x, y, text)
  OPTION 3 — ADB fallback (dialogs blocking):  tap_at(cx,cy) → run_command("adb ... input text ...")

### NEED TO NAVIGATE BACK?
  press_back → taps AppBar back button if visible (y < 200px), falls back to OS back.
  ⚠ OS back on ROOT SCREEN closes the app.

### NEED TO SCROLL?
  scroll_widget(key, direction) → scroll a scrollable widget
  scroll_until_visible(key, target_key) → scroll until target appears

### NEED TO VERIFY?
  1. **Assert tool** (fastest, requires key): assert_text, assert_visible, assert_enabled, etc.
  2. **inspect_ui** (no key needed): read values from tree response
  3. **capture_screenshot** (slow, last resort): visual confirmation

---

# Part 4 — Interaction Patterns

### FORM PATTERN
  1. inspect_ui → identify fields and their keys or coords
  2. Fill each field (prefer key-based):
       Text field (has key)   → input_text(key, text)
       Text field (no key)    → input_text(x, y, text)
       Dropdown (has key)     → select_dropdown(key, value)
       Dropdown (no key)      → tap_at(cx,cy) → inspect_ui → tap_at(item cx,cy)
       Toggle/Switch (key)    → toggle_widget(key)
       Slider (key)           → set_slider_value(key, 0.0–1.0)
  3. Submit: tap_widget(key) or tap_at(button cx, cy)
  4. Verify: assert_exists(key) or inspect_ui

### DIALOG / OVERLAY PATTERN
  1. inspect_ui → overlay widgets have absolute coords (and keys if registered)
  2. Prefer tap_widget(key) for overlay buttons
  3. Fallback: tap_at(cx, cy) reaches overlay widgets
  4. Text input in dialog: input_text(key, text) or tap_at + adb input text
  5. Close: tap Cancel/Close or press_back

### NAVIGATION PATTERN
  Back:        press_back
  Bottom nav:  tap_widget(key) or inspect_ui → tap_at(cx,cy)
  Drawer:      inspect_ui → tap DrawerButton → tap item
  AppBar menu: tap PopupMenuButton → inspect_ui → tap item

---

# Part 5 — Writing Tests

## Two Modes

| Situation                          | Mode   |
|------------------------------------|--------|
| Known exact steps, fixed flow      | SCRIPT |
| Business rule validation           | GOAL   |
| Form happy/error path              | SCRIPT |
| Exploratory / unknown navigation   | GOAL   |
| Regression test (must be stable)   | SCRIPT |
| "Verify user can do X"            | GOAL   |

## SCRIPT Mode Template

```
## TEST: module.screen.scenario
Mode: script
Screen: <starting screen>
Flow: <one-line description>
Preconditions: <initial app state>

### Keys Used
| Key | Widget | Description |
|-----|--------|-------------|
| auth.email_field | TextField | Email input |
| auth.submit | ElevatedButton | Submit button |

### Steps
1. inspect_ui → verify screen visible
2. input_text key:'auth.email_field' text:'user@example.com'
3. tap_widget key:'auth.submit'
4. wait duration_ms:1500
5. assert_exists key:'screen.dashboard'
6. capture_screenshot

### Assertions
- Navigated to dashboard
- No error messages visible
```

## GOAL Mode Template

```
## TEST: module.feature.objective
Mode: goal
Goal: <what the LLM must achieve — business terms>
Starting Point: <initial screen or state>
Expected Outcome: <what must be visible/true at the end>
Available Keys:
- key1 — description
- key2 — description

### Execution Journal
[LLM fills this during execution]

### Result
PASS | FAIL — <observation>
```

## GOAL Mode Decision Tree

1. inspect_ui → see something toward goal? → use key-based tool (preferred) or coordinates
2. Widget has key? → key-based tool. Unique text? → tap_by_label. Else → coordinates
3. Form? → input_text(key), tap_widget(key), toggle_widget(key)
4. Reached outcome? → assert or inspect_ui → capture_screenshot → PASS. Max 15 steps → FAIL

## ID Convention

Pattern: `module.screen.scenario`
Examples: `auth.login.happy_path`, `cart.checkout.empty_cart`, `orders.detail.verify_total`

## Keys Used Table — MANDATORY

Every test MUST include a Keys Used table:
```
| Key | Widget | Description |
|-----|--------|-------------|
```
This gives full context without inspecting the codebase.

## Common Templates

### Form Happy Path
1. inspect_ui → verify form
2. input_text key → each field
3. tap_widget key → submit
4. wait → assert_exists key → capture_screenshot

### List Tap Item
1. inspect_ui → find card keys
2. tap_widget key → card
3. wait → assert_exists key → detail screen

### Value Verification
1. assert_text key:'display.module.field' text:'expected'

### Error Path
1. input_text key → invalid data
2. tap_widget key → submit
3. wait → inspect_ui → expect error, same screen
4. capture_screenshot

---

# Part 6 — Widget Key Convention

## McpMetadataKey (Recommended)

```dart
ElevatedButton(
  key: const McpMetadataKey(
    id: 'checkout.submit',
    widgetType: McpWidgetType.button,
    description: 'Confirm purchase button',
    screen: 'CheckoutScreen',
  ),
  onPressed: _submit,
  child: const Text('Confirm'),
)
```

## Naming Convention

Pattern: `module.element[.variant]`

| Category    | Pattern               | Examples                                    |
|-------------|-----------------------|---------------------------------------------|
| Interactive | module.element        | auth.login_button, cart.quantity_field       |
| Dynamic     | module.element.{id}   | product.card.uuid-123, cart.item.sku-456    |
| Screens     | screen.name           | screen.login, screen.checkout               |
| State       | state.context.type    | state.cart.loading, state.auth.error        |
| Display     | display.module.field  | display.cart.total, display.profile.name    |
| Modals      | modal.type.action     | modal.confirm.delete, modal.sheet.filter    |
| Navigation  | nav.element           | nav.settings, nav.cart_icon                 |

## When to use ValueKey vs McpMetadataKey

| Use existing ValueKey when... | Use McpMetadataKey when... |
|-------------------------------|---------------------------|
| Project already has good key naming | Starting fresh or adding new widgets |
| Keys follow `module.element` pattern | Want rich metadata from `get_app_context` |
| Key is shared with flutter_test | Want description/screen/tags |

---

# Part 7 — Performance & Efficiency

| Operation | Cost | Guidance |
|-----------|------|----------|
| `tap_widget(key)` | Cheapest | Always prefer when key exists |
| `assert_*(key)` | Cheap | Use for verification when key exists |
| `tap_by_label(label)` | Cheap | Use when text is unique, no key |
| `input_text(key, text)` | Cheap | Prefer over coordinate variant |
| `inspect_ui` | Medium | Max 1 per checkpoint |
| `tap_at(x, y)` | Medium | Requires prior inspect_ui |
| `capture_screenshot` | Expensive | Only at test end or on FAIL |

### Timing Heuristics

| Action                    | Wait        |
|---------------------------|-------------|
| Button tap (same screen)  | 300-500ms   |
| Navigation between screens| 1000-1500ms |
| Dropdown selection        | 300ms       |
| API call / list loading   | 2000-3000ms |
| Animation / transition    | 600-800ms   |
| Dialog / bottom sheet     | 500ms       |
| Text input                | 0ms (sync)  |

Loading rule: inspect_ui shows loading → wait 1000ms → inspect_ui → still loading → wait 2000ms → max 3 attempts → FAIL

### Efficiency Rules

- **Key-based tools first** — always `tap_widget(key)` and `assert_*(key)` over coordinates
- inspect_ui: max 1 per checkpoint (screen start, post-navigation, final)
- capture_screenshot: only at test end or on FAIL
- Never inspect_ui after input_text — text input is synchronous
- Never inspect_ui twice in a row without an action between them

---

# Part 8 — Error Recovery

| Problem | Solution |
|---------|----------|
| Tap had no effect | inspect_ui again (animation shifted coords), retry with key or fresh coords |
| Widget not found | scroll_widget(key, 'down') → inspect_ui, check OTHER section |
| input_text failed | tap_at to focus → adb shell input text |
| Loading spinner | wait(2000) → inspect_ui, max 3 attempts → FAIL |
| App closed | run_command("flutter run -d SERIAL") → wait(5000) → inspect_ui |
| Form error | inspect_ui → look for error Text widgets → fill missing fields → retry |

---

# Part 9 — Test Organization

Recommended order per screen:
1. `happy_path` — main flow works
2. `validation_empty` — required fields
3. `validation_format` — invalid format
4. `error_api` — failed API
5. `<business_rule>` — specific rule (GOAL mode)
6. `edge_empty_list` — zero state

File location: `test/e2e/<module>/<screen>_tests.md`

---

# Part 10 — Coordinate Quick Reference (fallback)

  Center of widget: `cx = x + w/2`, `cy = y + h/2`
  Widget from JSON: `{"type":"ElevatedButton","x":20,"y":400,"w":350,"h":52}` → `tap_at(195, 426)`
  Always document the calculation inline for debuggability.

---

# Quick Start Checklist

Before your first interaction with the app:
1. Call `get_app_context` — discover registered keys and active screen
2. Call `inspect_ui` — see the full widget tree
3. Identify targets by key (preferred), label, or coordinates
4. Execute actions using the appropriate tools
5. Verify with assert tools (key) or inspect_ui (no key)
6. Screenshot only at the end or on failure
''';
