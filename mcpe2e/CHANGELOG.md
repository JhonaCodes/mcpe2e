# Changelog

## [2.0.5] - 2026-03-10

### Changed
- Version bump to 2.0.5 (sync with mcpe2e_server v2.0.5 — input_text dual-option docs, run_command ADB fallback).

---

## [2.0.4] - 2026-03-10

### Changed
- Version bump to 2.0.4 (sync with mcpe2e_server v2.0.4 — input_text/toggle_widget string coord fix).

---

## [2.0.3] - 2026-03-10

### Changed
- Version bump to 2.0.3 (sync with mcpe2e_server v2.0.3 — smart press_back avoids closing app).

---

## [2.0.2] - 2026-03-10

### Changed
- Version bump to 2.0.2 (sync with mcpe2e_server v2.0.2 — inspect_ui reverted to raw JSON, inspect_ui_compact added as separate tool).

---

## [2.0.1] - 2026-03-10

### Changed
- Version bump to 2.0.1 (sync with mcpe2e_server v2.0.1 — OTHER section in inspect_ui, comprehensive widget type coverage).

---

## [2.0.0] - 2026-03-10

### Fixed
- `tap_at`, `drag_widget`, `swipe_widget`, `scroll_widget`, `set_slider_value`,
  `long_press_widget`, `pinch_widget`, `wait` and `scroll_until_visible` no longer
  crash with `type 'String' is not a subtype of type 'num'` when the LLM passes
  numeric arguments as JSON strings (e.g. `"263.8"` instead of `263.8`).
  New `_toNum`/`_toInt` helpers coerce both String and num transparently.

### Added
- `PopupMenuButton` now appears in `inspect_ui` output under INTERACTIVE with its
  tooltip and center coordinates. Previously invisible to the LLM — it could not
  open AppBar dropdowns without guessing coordinates.

---

## [1.1.9] - 2026-03-10

### Added
- `docs/writing-tests.md` Section 10: recommends adding `McpMetadataKey`
  to dialogs, bottom sheets, drawers and snackbars. Coordinates on animated
  overlay surfaces can shift during the open animation; a key avoids that.
- `README.md` "Recommended: add keys to overlaid widgets" subsection with
  code examples and the explicit note that it is a suggestion, not a requirement.

---

## [1.1.8] - 2026-03-10

### Added
- `McpNavigatorObserver` — singleton `NavigatorObserver` que captura el route
  activo del Navigator y lo expone en `get_app_context` como `route` real.
  Registrar con una línea:
  - `MaterialApp(navigatorObservers: [McpNavigatorObserver.instance])`
  - `GoRouter(observers: [McpNavigatorObserver.instance])`
  Sin registro: comportamiento anterior (fallback a `/unknownscreen`).

### Changed
- `GET /mcp/context` ahora pasa `McpNavigatorObserver.instance.currentRoute`
  al `toJson()`, reemplazando el route derivado mecánicamente del screen name.
- `mcpe2e.dart` exporta `McpNavigatorObserver`.

---

## [1.1.7] - 2026-03-10

### Fixed
- `inspect_ui` no longer crashes with `Converting object to an encodable object failed: NaN`
  during UI transitions (language change, settings screens, mid-layout rebuilds).
- `_position()` now discards widget coordinates that are not finite — if a `RenderBox` exists
  but layout has not completed, the widget appears in the tree without `x/y/w/h` instead of
  crashing the JSON encoder.
- Added recursive JSON sanitizer (`sanitizeList/Map/Value`) applied to the full `inspect()`
  output before returning — catches any non-finite double from any source (Slider.value,
  partial transforms, etc.) and converts it to `null` so `jsonEncode` always succeeds.

### Added
- 33 regression tests for `McpTreeInspector` (`test/core/tree_inspector_test.dart`):
  - Group A (6): `round()` — rounding precision + NaN/Inf propagation.
  - Group B (12): `sanitizeValue()` — all types, nested Maps and Lists.
  - Group C (11): `inspect()` — widget extraction for Text, TextField, ElevatedButton,
    AppBar, Checkbox, Switch; empty tree; structural consistency.
  - Group D (4): JSON regression — `jsonEncode(inspect())` must never throw.
- `docs/writing-tests.md` — LLM guide for writing script-mode and goal-mode tests,
  including templates, timing heuristics, decision tree, and coordinate calculation rules.

### Changed
- Internal sanitize helpers and `round()` exposed as `@visibleForTesting` static methods
  for direct unit testing without requiring a widget tree.

---

## [1.1.6] - 2026-03-10

### Changed
- Version bump to 1.1.6 (sync with mcpe2e_server v1.1.6 — auto ADB forwarding + device watcher).

---

## [1.1.5] - 2026-03-10

### Changed
- Version bump to 1.1.5 (sync with mcpe2e_server v1.1.5 — OpenCode agent support).

---

## [1.1.4] - 2026-03-10

### Changed
- Version bump to 1.1.4 (sync with mcpe2e_server v1.1.4 — dialog interaction, coordinate
  gestures, loading-aware wait).

---

## [1.1.2] - 2026-03-10

### Changed
- Version bump to 1.1.2 (sync with mcpe2e_server v1.1.2 — UTF-8 decode fix).

---

## [1.1.1] - 2026-03-10

### Changed
- Version bump to 1.1.1 (sync with mcpe2e_server v1.1.1 — Claude Code scope fix).

---

## [1.1.0] - 2026-03-10

### Changed
- Version bump to 1.1.0 (sync with mcpe2e_server v1.1.0 — multi-device support release).

---

## [1.0.8] - 2026-03-10

### Changed
- Version bump to 1.0.8

---

## [1.0.7] - 2026-03-10

### Added
- `dart run mcpe2e:setup` — one-command setup: downloads `mcpe2e_server` binary for your platform and opens the interactive agent registration menu. No curl, no manual binary install. Run after `flutter pub get`.

### Changed
- Version unified to 1.0.7 across all components (Flutter lib, MCP server, GitHub tags)
- Primary testing approach is now coordinate-based: `inspect_ui` returns the full widget tree with `x`/`y`/`w`/`h` coordinates; `tap_at` taps by absolute position without requiring widget registration
- Minimal Flutter integration reduced to two lines in `main.dart`: import + `if (kDebugMode) await McpEventServer.start()`
- `McpMetadataKey` and widget registration are now optional — coordinate-based testing requires zero app changes beyond starting the server

---

## [1.0.0] - [1.0.6]

Internal development iterations (see git log)

---

## [0.3.4] - 2026-03-09

### Added
- `tapAt` event type — tap by absolute screen coordinates (logical pixels). No widget registration required. Useful for dynamic cards, list items, or any widget without an ID. Accepts `dx` (X) and `dy` (Y) params. Coordinates match the `x`/`y` values from `inspect_ui`.
- `McpEventParams.dx` and `McpEventParams.dy` fields for absolute coordinate taps.

---

## [0.3.1] - 2026-03-09

### Fixed
- `getRenderBox` now finds widgets that use `McpMetadataKey` directly as a key (without `getGlobalKey()`). Added fallback element-tree walk: finds the first element whose `widget.key.id` matches, then returns its first `RenderBox` descendant. Fix for tap/swipe/scroll that failed when the app uses `const McpMetadataKey(...)` directly on widgets.

---

## [0.3.0] - 2026-03-09

### Added
- `McpTreeInspector` — walks the full widget tree from `WidgetsBinding.rootElement` with zero intrusion. Reads Text values, TextField content, button labels/enabled state, Checkbox/Switch/Radio checked state, Slider current value, AppBar titles, AlertDialog and SnackBar presence. No widget registration required.
- `McpScreenCapture` — captures the current screen as PNG using Flutter's internal layer tree (`renderViews.first.debugLayer`). Zero widgets added to the tree. Returns `{"error":"not_available_in_release"}` gracefully in release builds.
- `GET /mcp/tree` endpoint — returns the full widget tree JSON via `McpTreeInspector`
- `GET /mcp/screenshot` endpoint — returns the screen as PNG base64 via `McpScreenCapture`
- Production guard in `McpEventServer.start()`: exits immediately if not in debug or profile mode
- `mcpe2e.dart` exports `McpTreeInspector` and `McpScreenCapture`

---

## [0.2.0] - 2026-03-09

### Added
- 11 new event types: `toggle`, `setSliderValue`, `pressBack`, `clearText`, `scrollUntilVisible`, `tapByLabel`, `assertVisible`, `assertEnabled`, `assertSelected`, `assertValue`, `assertCount` (total: 25 event types)
- 5 new widget types: `checkbox`, `radio`, `switchWidget`, `slider`, `tab` (total: 14 widget types)
- New `McpEventParams` fields: `sliderValue`, `targetKey`, `maxScrollAttempts`, `label`, `expectedCount`
- `McpWidgetRegistry` — single source of truth for the registered widget map (`core/mcp_widget_registry.dart`)
- `McpGestureSimulator` — low-level pointer simulation isolated to its own class (`core/mcp_gesture_simulator.dart`)
- `McpEventExecutor` — all 25 event implementations using Dart 3 switch expressions (`core/mcp_event_executor.dart`)
- `McpConnectivity` — platform detection and automatic port forwarding (`platform/mcp_connectivity.dart`): ADB forward (Android), iproxy (iOS), direct localhost (Desktop), unsupported (Web)
- `McpEvents` redesigned as a thin facade delegating to the three core classes

### Changed
- `McpEventServer` no longer handles ADB forwarding — moved to `McpConnectivity`
- `McpEventServer._parseEventType` uses Dart 3 switch expression, accepts both camelCase and snake_case
- `McpEventServer.start()` calls `McpConnectivity.setup()` automatically on startup
- All `if-else` chains replaced with Dart 3 switch expressions

### Removed
- `event_bridge.dart` — redundant wrapper removed

---

## [0.1.0] - 2026-03-09

### Added
- Initial release as `mcpe2e` (renamed from `e2e_mcp`)
- `McpMetadataKey` — extends Flutter's `Key`, carries semantic metadata for MCP-testable widgets
- `McpWidgetType` enum (9 types: button, textField, text, list, card, image, container, dropdown, custom)
- `McpEventType` enum (14 types: tap, doubleTap, longPress, swipe, drag, scroll, pinch, textInput, selectDropdown, hideKeyboard, showKeyboard, wait, assertExists, assertText)
- `McpEventParams` — typed event parameters
- `McpEvents` — singleton facade for widget registration and event execution
- `McpEventServer` — embedded HTTP server with endpoints: `/ping`, `/mcp/context`, `/action`, `/event`, `/widgets`
- 14 event implementations via `GestureBinding.instance.handlePointerEvent`
- Android ADB forwarding support
