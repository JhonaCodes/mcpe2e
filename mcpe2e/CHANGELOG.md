# Changelog

## [0.3.4] - 2026-03-09

### Added
- `tapAt` event type — tap by absolute screen coordinates (logical pixels). No widget registration required. Useful for dynamic cards, list items, or any widget without an ID. Accepts `dx` (X) and `dy` (Y) params. Coordinates match the `x`/`y` values from `inspect_ui`.
- `McpEventParams.dx` and `McpEventParams.dy` fields for absolute coordinate taps.

---

## [0.3.1] - 2026-03-09

### Fixed
- `getRenderBox` ahora encuentra widgets que usan `McpMetadataKey` directamente como key (sin `getGlobalKey()`). Agrega fallback de element-tree walk: busca el primer elemento cuyo `widget.key.id` coincida, luego retorna su primer `RenderBox` descendiente. Fix para tap/swipe/scroll que fallaban cuando la app usa `const McpMetadataKey(...)` directo en widgets.

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
