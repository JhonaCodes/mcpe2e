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

## Core Loop — Always follow this order

1. inspect_ui         → get widget tree (x, y, w, h for every widget on screen)
2. Identify target    → by type, label, key, or position in the tree
3. Calculate center   → cx = x + w/2,  cy = y + h/2
4. Execute action     → tap_at(cx,cy) / input_text / scroll / assert
5. Verify result      → inspect_ui (state check) or capture_screenshot (visual check)

RULE: Never guess coordinates. Always read them from inspect_ui first.
RULE: Never skip step 1. Widget positions change after animations and navigation.

---

## Tool Decision Tree

### NEED TO SEE SCREEN?
  inspect_ui            → Full JSON tree: all widgets, coords, values, states.
                          Use this ALWAYS before any interaction.
  capture_screenshot    → PNG image. Use ONLY for visual/layout verification,
                          not as a substitute for inspect_ui.
  inspect_ui_compact    → Grouped summary (INTERACTIVE/TEXT/OTHER/OVERLAY/LOADING).
                          Use on simple screens when saving tokens matters.

### NEED TO TAP?
  Any widget on screen  → tap_at(cx, cy)                [PREFERRED]
  Widget with a key     → tap_widget(key)                [stable named access]
  Widget with text      → tap_by_label(label)            [find by visible text]
  Double tap            → double_tap_widget(key)
  Long press            → long_press_widget(key, duration_ms)
  AppBar dropdown       → tap PopupMenuButton → inspect_ui → tap item at coords

### NEED TO TYPE TEXT?

  OPTION 1 — Standard (normal fields):
    inspect_ui → note x,y of TextField
    input_text(x, y, text)
    The tool taps x,y to focus, then types via ADB.

  OPTION 2 — Skip focus tap (field already focused):
    input_text(x, y, text, skip_focus_tap: true)
    Use when inspect_ui shows "auto_focus": true on the field,
    or when a tap would close the keyboard.

  OPTION 3 — ADB fallback (dialogs / overlays blocking the tap):
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
  assert_text(key, text)       → visible text matches expected
  assert_visible(key)          → widget is in viewport
  assert_enabled(key)          → widget is enabled (not grayed out)
  assert_selected(key)         → checkbox/switch/radio is active
  assert_value(key, value)     → TextField controller value matches
  assert_count(key, count)     → list has exactly N children
  assert_exists(key)           → widget is registered

---

## Interaction Patterns

### FORM PATTERN

  1. inspect_ui → identify all required (*) fields and their coords
  2. Fill each field:
       Text field    → input_text(x, y, text)
       Dropdown      → tap_at(cx,cy) → inspect_ui → tap_at(item cx,cy)
       Date picker   → tap_at(field cx,cy) → capture_screenshot → tap day numbers
       Number +/-    → tap_at([+] cx,cy) repeatedly OR input_text(field cx,cy, value)
       Toggle/Switch → toggle_widget(key) or tap_at(cx,cy)
       Slider        → set_slider_value(key, 0.0–1.0)
  3. scroll_widget down to find the Submit/Save/Confirm button
  4. tap_at(button cx, cy)
  5. inspect_ui → verify form closed or success message appeared

### DIALOG / OVERLAY PATTERN

  When AlertDialog, BottomSheet, or Drawer is active:
  1. inspect_ui → widgets with "overlay": true have absolute screen coords
  2. Interact normally: tap_at(cx, cy) reaches overlay widgets
  3. Text input in dialog:
       tap_at(field cx, cy)   ← focus first
       run_command("adb -s SERIAL shell input text \"value\"")
  4. Close dialog: tap Cancel/Close button OR press_back

### APPBAR DROPDOWN (PopupMenuButton) PATTERN

  1. inspect_ui → find widget of type "PopupMenuButton"
  2. tap_at(PopupMenuButton cx, cy)    → dropdown opens
  3. inspect_ui → menu items appear with "overlay": true
  4. tap_at(item cx, cy)               → item selected, dropdown closes
  5. inspect_ui → verify new screen/state

### NAVIGATION PATTERN

  Back:           press_back
  AppBar menu:    tap PopupMenuButton → inspect_ui → tap item
  Bottom nav:     inspect_ui → find NavigationDestination/Tab → tap_at(cx,cy)
  Drawer:         inspect_ui → find DrawerButton → tap_at(cx,cy) → tap item

### CUSTOM / THIRD-PARTY WIDGET PATTERN

  Custom widgets (e.g. MultiSelectField, PxDropdown) appear in inspect_ui
  under the "OTHER" section with their type, label, and coords.

  1. inspect_ui → find widget in OTHER section
  2. tap_at(cx, cy) to open/activate it
  3. inspect_ui → new items appear (often as overlay)
  4. tap_at(item cx, cy) to select

---

## Error Recovery

### Tap had no effect
  → capture_screenshot to see current visual state
  → inspect_ui again (animation may have shifted coords)
  → retry tap_at with fresh coordinates

### Widget not found in inspect_ui
  → scroll_widget(key, 'down') then inspect_ui again
  → check OTHER section — custom widgets appear there
  → try capture_screenshot to see what's actually on screen

### input_text failed or text went to wrong field
  → use OPTION 3: tap_at to focus → adb shell input text
  → verify field has focus with capture_screenshot first

### Loading spinner visible (CircularProgressIndicator)
  → wait(2000) → inspect_ui again
  → tools auto-wait for idle but long network calls may need manual wait

### App closed unexpectedly
  → run_command("flutter run -d SERIAL --flavor <flavor>", background: true)
  → wait(5000) → inspect_ui to verify app is back

### Form submission failed
  → inspect_ui → look for error messages (Text widgets with red/error styling)
  → capture_screenshot for visual error state
  → fill missing required fields and retry

---

## Agent Task Format

When given a high-level task, decompose and execute as follows:

TASK: "Submit the checkout form"

PLAN:
  1. [NAVIGATE]  Go to Checkout screen via bottom nav or button
  2. [TAP]       Tap "Checkout" button
  3. [FORM]      Fill: name="John", email="john@example.com", quantity=2
  4. [SUBMIT]    Scroll down → tap "Confirm Order" button
  5. [VERIFY]    inspect_ui → confirm success screen appeared

EXECUTION RULES:
  - Execute Core Loop (inspect_ui → act → verify) at each step
  - Report the result of each step before proceeding to the next
  - If a step fails, apply Error Recovery before moving on
  - Never proceed to step N+1 without confirming step N succeeded

---

## Coordinate Quick Reference

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
1. inspect_ui → see something toward goal? YES → use key or coordinates
2. Widget has key? → key-based tool. Unique text? → tap_by_label. Else → coordinates
3. Form? → input_text for fields, tap_widget for buttons, toggle_widget for switches
4. Reached outcome? → assert + capture_screenshot → PASS. No? → keep going (max 15 steps → FAIL)

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

- inspect_ui: max 1 per checkpoint (screen start, post-navigation, final)
- Use key-based tools when keys exist — faster and more reliable
- tap_by_label: when text is unique on screen and no key exists
- capture_screenshot: only at test end or on FAIL
- scroll_until_visible: before tapping if widget might be off-screen
- Never inspect_ui after input_text — text input is synchronous

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

mcpe2e detects ANY Flutter Key in the widget tree via inspect_ui.
No special class required — ValueKey, GlobalKey, ObjectKey all work.

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

## McpMetadataKey

mcpe2e provides `McpMetadataKey` as a convenience — it carries extra metadata (widget type, description, screen, tags) beyond what ValueKey offers.

```dart
McpMetadataKey(
  'checkout.submit',
  widgetType: 'ElevatedButton',
  description: 'Confirm purchase button',
  screen: 'checkout',
  tags: ['critical', 'payment'],
)
```

### When to use ValueKey vs McpMetadataKey

| Use ValueKey when... | Use McpMetadataKey when... |
|----------------------|---------------------------|
| Project already has a keys class | Starting a new project |
| Just need stable tap/input/assert | Want get_app_context to return rich metadata |
| Key is shared with flutter_test | Want description/screen/tags for context |

If your project already uses `ValueKey<String>` with a naming convention, USE THOSE. Don't create parallel key systems.

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

## Keys vs Coordinates — When to Use Each

### Use keys when:
- Stable, repeatable tests (regression)
- Widget has a known key in the project
- Form fields, buttons, display values
- Tests must survive layout changes, themes, screen sizes

### Use coordinates when:
- Dynamic list items from API (unknown IDs at test time)
- Exploratory testing (no pre-planned keys)
- Widgets without keys (quick test, no code changes)
- Scroll position targets

### Why keys are better (when available):
- Survive screen size changes, orientation, rebuilds, theme changes
- Self-documenting: `tap_widget key:'auth.login_button'` vs `tap_at x:195 y:386`
- Overlays, dialogs, animations shift coordinates — keys always resolve
- Same keys work for `find.byKey()` in flutter_test AND `tap_widget` in mcpe2e

---

## Adding New Keys to a Project

When you need to test a widget that has no key:

1. Check the project's key class — does the key already exist?
2. If not, add it following the `module.element` pattern
3. Assign the key to the widget
4. Use the key string in mcpe2e tests

Example:
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
