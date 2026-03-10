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
