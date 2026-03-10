# mcpe2e — Writing Tests for LLMs

This guide defines the standard format for writing mcpe2e tests. It covers two modes
that address different testing needs, plus templates, timing heuristics, and efficiency rules.

---

## Section 1 — Two Test Modes

```
SCRIPT MODE  → the dev defines the exact steps, the LLM executes them
GOAL MODE    → the dev defines the objective, the LLM navigates and adapts the steps
```

| | Script | Goal |
|-|--------|------|
| Who defines the steps | The dev | The LLM (live, in real time) |
| How it verifies | Predefined assertion list | What it observes vs. what the dev described |
| When to use | Known flows, regression testing | Business logic, feature validation |

**Key distinction:** in goal mode, the dev does NOT specify steps. The LLM determines them
by observing each `inspect_ui` result — like a human tester exploring the app. Only the
objective and expected outcome are given.

---

## Section 2 — SCRIPT Format

```
## TEST: <module>.<screen>.<scenario>
**Mode:** script
**Screen:** <Starting screen>
**Flow:** <One-line description of the scenario>
**Preconditions:** <Initial app state>

### Steps
1. <tool> → <params> → Expected: <result>
2. ...

### Assertions
- <field/state>: <expected value>
```

### ID Convention

IDs follow `module.screen.scenario`:

```
auth.login.happy_path
auth.login.wrong_password
orders.list.tap_pending_order
orders.detail.verify_total
procurement.bid.create_and_verify_supplier_field
```

### Example

```markdown
## TEST: auth.login.happy_path
**Mode:** script
**Screen:** Login Screen
**Flow:** User enters valid credentials and lands on the dashboard.
**Preconditions:** App on Login screen, no session active.

### Steps
1. inspect_ui → Expected: TextField(hint="Email"), TextField(hint="Password"), ElevatedButton(enabled=false)
2. input_text  key: auth.email_field  text: "user@example.com"
3. input_text  key: auth.password_field  text: "secret123"
4. inspect_ui → Expected: ElevatedButton(enabled=true)
   Widget: { x:20, y:500, w:350, h:52 } → Center: x=20+350/2=195, y=500+52/2=526
5. tap_at  x:195  y:526
6. wait  duration_ms: 1500
7. inspect_ui → Expected: AppBar.title = "Dashboard"
8. capture_screenshot

### Assertions
- Step 4: Login button enabled = true
- Step 7: AppBar.title = "Dashboard"
```

---

## Section 3 — GOAL Format

```
## TEST: <module>.<feature>.<objective>
**Mode:** goal
**Goal:** <What the LLM must achieve — in business terms>
**Starting Point:** <Initial screen or app state>
**Expected Outcome:** <What must be visible/true at the end>

### Execution Journal
[The LLM fills this section while executing — documents what it observes and decides]
Step 1: inspect_ui → I see: [list of relevant widgets]
Step 2: I decide to navigate to X because I see Y → tap_at / tap_by_label
...
Step N: inspect_ui → verify Expected Outcome → PASS / FAIL: <detail>

### Result
PASS | FAIL — <final observation>
```

### Complete Example

```markdown
## TEST: procurement.bid.create_and_verify_supplier_field
**Mode:** goal
**Goal:** Create a bid of type "Procurement" and verify that the "Supplier" field
          appears in the form (business rule: only Procurement-type bids show that field).
**Starting Point:** Main dashboard
**Expected Outcome:** "Supplier" field visible in the bid form after selecting
                      type "Procurement".

### Execution Journal
Step 1: inspect_ui → I see "New Bid" button in AppBar
Step 2: tap_by_label "New Bid" → wait 1000ms
Step 3: inspect_ui → I see form with Dropdown "Bid Type"
        Widget: { x:16, y:200, w:358, h:52 } → Center: 195, 226
Step 4: tap_at x:195 y:226 → wait 500ms → I see dropdown options
Step 5: tap_by_label "Procurement" → wait 300ms
Step 6: inspect_ui → searching for "Supplier" field
        Result: TextField(hint="Supplier", x:16, y:280) ← present ✓
Step 7: capture_screenshot

### Result
PASS — "Supplier" field appears after selecting type "Procurement".
       Text visible: "Supplier", enabled: true, y:280.
```

---

## Section 4 — Decision Tree (for GOAL mode)

When the LLM doesn't know what to do next, follow this order:

```
1. inspect_ui → do I see something that leads me toward the goal?
     YES → navigate (tap_by_label if unique text, tap_at with coordinates if not)
     NO  → is there a menu / nav / tab to explore?
           YES → tap tab or nav item → inspect_ui
           NO  → scroll_widget down → inspect_ui

2. Does the widget I need have unique text on screen?
     YES → tap_by_label (more efficient)
     NO  → inspect_ui → calculate center → tap_at

3. Do I need to fill a form?
     - input_text for TextFields
     - tap_at for dropdowns (then tap_by_label on the option)
     - toggle_widget for Checkbox / Switch

4. Have I reached the Expected Outcome?
     YES → inspect_ui to confirm → capture_screenshot → PASS
     NO  → keep exploring (max 15 steps before reporting FAIL)
```

---

## Section 5 — Timing Heuristics

| Previous action | Recommended `wait` |
|-----------------|-------------------|
| Button tap (same screen) | 300–500ms |
| Navigation between screens | 1000–1500ms |
| Dropdown selection | 300ms |
| API call / list loading | 2000–3000ms |
| Animation / transition | 600–800ms |
| Dialog / Bottom sheet | 500ms |
| Text input | 0ms (synchronous) |

**Loading rule:** if `inspect_ui` shows a CircularProgressIndicator or Shimmer:

```
wait 1000ms → inspect_ui → if still loading: wait 2000ms → inspect_ui
Maximum 3 attempts. If still loading → FAIL: "Loading did not finish in 5s"
```

---

## Section 6 — Coordinate Calculation (always document inline)

Always show the calculation inline. Never use magic numbers:

```
Widget: { x: 20, y: 360, w: 350, h: 52 }
Center: x = 20 + 350/2 = 195,  y = 360 + 52/2 = 386
→ tap_at x: 195  y: 386
```

This makes the test readable and debuggable when coordinates change between runs.

---

## Section 7 — Ready-to-Use SCRIPT Templates

### Template A — Form + navigation (happy path)

```markdown
## TEST: <module>.<screen>.happy_path
**Mode:** script
**Screen:** <Screen>
**Flow:** User fills the form with valid data and navigates to the result.
**Preconditions:** App in debug mode, initial screen visible.

### Steps
1. inspect_ui → Expected: TextField(<field1>), TextField(<field2>), ElevatedButton(enabled=false)
2. input_text  key: <field1>  text: "<value>"
3. input_text  key: <field2>  text: "<value>"
4. inspect_ui → Expected: ElevatedButton(enabled=true)
   Widget: { x:?, y:?, w:?, h:? } → Center: x=?+?/2=?, y=?+?/2=?
5. tap_at  x:?  y:?
6. wait  duration_ms: 1500
7. inspect_ui → Expected: AppBar.title = "<Destination screen>"
8. capture_screenshot

### Assertions
- Step 4: button enabled = true
- Step 7: AppBar.title = "<Destination screen>"
```

### Template B — Dynamic list (no widget keys)

```markdown
## TEST: <module>.<screen>.tap_item
**Mode:** script
**Screen:** <ListScreen>
**Flow:** User taps a list item and navigates to the detail.
**Preconditions:** List loaded with at least 1 item.

### Steps
1. inspect_ui → identify Card/ListTile with Text.value = "<item text>"
   Card: { x:?, y:?, w:?, h:? } → Center: x=?+?/2=?, y=?+?/2=?
2. tap_at  x:?  y:?
3. wait  duration_ms: 1000
4. inspect_ui → Expected: AppBar.title = "<detail title>"
5. capture_screenshot

### Assertions
- AppBar.title = "<detail title>"
```

### Template C — Value verification on screen

```markdown
## TEST: <module>.<screen>.verify_<field>
**Mode:** script
**Screen:** <Screen>
**Flow:** Verify that <field> shows the correct value.
**Preconditions:** <Prior app state>.

### Steps
1. inspect_ui → read Text.value next to Text.value = "<label>"

### Assertions
- Text next to "<label>": "<expected value>"
```

### Template D — Error path

```markdown
## TEST: <module>.<screen>.<error_case>
**Mode:** script
**Screen:** <Screen>
**Flow:** User submits invalid data — the system shows an error and does not navigate.
**Preconditions:** App on initial screen.

### Steps
1. input_text  key: <field>  text: "<invalid value>"
   Button widget: { x:?, y:?, w:?, h:? } → Center: x=?, y=?
2. tap_at  x:?  y:?
3. wait  duration_ms: 500
4. inspect_ui → Expected: Text.value = "<error message>", AppBar.title = "<same screen>"
5. capture_screenshot

### Assertions
- AppBar.title is still "<current screen>" (did not navigate)
- Error text visible: "<message>"
```

---

## Section 8 — Efficiency Rules

- `inspect_ui`: maximum 1 per checkpoint (screen start, post-navigation, final verification)
- `tap_by_label`: use when the text is unique on screen — avoids inspect + coordinate calculation
- `capture_screenshot`: only at the end of a test or when there is a visual FAIL
- `scroll_until_visible`: before tapping if the widget might be outside the viewport
- Do not call `inspect_ui` after `input_text` — text input is synchronous

---

## Section 9 — Organizing Multiple Tests per Screen

Recommended order within a screen's test suite:

```
1. happy_path         ← main flow works end-to-end
2. validation_empty   ← empty / required fields
3. validation_format  ← invalid format (email, number, date)
4. error_api          ← failed API response
5. <business_rule>    ← specific business rule (GOAL mode)
6. edge_empty_list    ← empty list, zero state
```

This order moves from the most common case to the most specific, making it easier to
identify regressions: if `happy_path` fails, skip the rest until it is fixed.

---

## Section 10 — Suggested: widget keys for overlaid surfaces

The coordinate-based approach (`inspect_ui` → `tap_at`) works for the entire app without
any widget registration. However, for widgets that appear as a layer on top of the main
screen — dialogs, bottom sheets, drawers, and snackbars — we suggest adding a
`McpMetadataKey`. These surfaces are rendered in a separate overlay entry; their
coordinates can shift during animations, making coordinate-based taps less reliable.

With a key, the LLM uses `tap_widget key: "modal.confirm.submit"` instead of calculating
and chasing coordinates through `inspect_ui` while the overlay is animating in.

**Where to add keys (suggestion only — not required):**

| Surface | Example key |
|---------|-------------|
| Confirmation dialog action | `modal.confirm.submit`, `modal.confirm.cancel` |
| Bottom sheet primary action | `sheet.<module>.submit` |
| Navigation drawer | `nav.drawer` |
| Snackbar action | `snackbar.undo`, `snackbar.retry` |
| Tooltip / Popover trigger | `tooltip.<name>` |

```dart
// Bottom sheet submit button
ElevatedButton(
  key: const McpMetadataKey(id: 'sheet.bid.submit'),
  onPressed: _submitBid,
  child: const Text('Place Bid'),
)

// AlertDialog confirm action
TextButton(
  key: const McpMetadataKey(id: 'modal.confirm.delete'),
  onPressed: _confirmDelete,
  child: const Text('Delete'),
)
```

For the main screen body (lists, forms, cards) coordinate-based interaction is preferred
since those widgets are stable in the viewport and keys would add unnecessary noise to the
widget tree.
