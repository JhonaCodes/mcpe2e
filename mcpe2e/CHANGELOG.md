# Changelog

## [0.3.0] - 2026-03-09

### Added
- `McpTreeInspector` — walks the full widget tree from `WidgetsBinding.rootElement` with zero intrusion. Extracts Text values, TextField content, button labels/enabled state, Checkbox/Switch/Radio values, Slider positions, AppBar titles, AlertDialog and SnackBar presence.
- `McpScreenCapture` — captures the current screen as PNG using Flutter's internal layer tree (`renderViews.first.debugLayer`). Zero widgets added to the tree. Returns `{"error":"not_available_in_release"}` gracefully in release mode.
- `GET /mcp/tree` endpoint — returns the full widget tree JSON via `McpTreeInspector`
- `GET /mcp/screenshot` endpoint — returns screen PNG as base64 JSON via `McpScreenCapture`
- Production guard in `McpEventServer.start()`: returns immediately if not in debug/profile mode

### Changed
- Startup log now includes `/mcp/tree` and `/mcp/screenshot` in the endpoints list
- `mcpe2e.dart` exports `McpTreeInspector` and `McpScreenCapture`

---

## [0.2.0] - 2026-03-09

### Added
- 11 new event types: `toggle`, `setSliderValue`, `pressBack`, `clearText`, `scrollUntilVisible`, `tapByLabel`, `assertVisible`, `assertEnabled`, `assertSelected`, `assertValue`, `assertCount` (total: 25)
- 5 new widget types: `checkbox`, `radio`, `switchWidget`, `slider`, `tab` (total: 14)
- New `McpEventParams` fields: `sliderValue`, `targetKey`, `maxScrollAttempts`, `label`, `expectedCount`
- `McpWidgetRegistry` — single source of truth for registered widget map (`core/mcp_widget_registry.dart`)
- `McpGestureSimulator` — low-level pointer simulation only (`core/mcp_gesture_simulator.dart`)
- `McpEventExecutor` — all 25 event implementations using Dart 3 switch expressions (`core/mcp_event_executor.dart`)
- `McpConnectivity` — platform detection and port forwarding (`platform/mcp_connectivity.dart`): ADB (Android), iproxy (iOS), direct (Desktop)
- `McpEvents` redesigned as a thin facade delegating to the 3 core classes

### Changed
- `McpEventServer` removes ADB forwarding code (moved to `McpConnectivity`)
- `McpEventServer._parseEventType` uses Dart 3 switch expression with camelCase + snake_case support
- `McpEvents.start()` calls `McpConnectivity.setup()` automatically
- All `if-else` chains replaced with modern Dart switch expressions

### Removed
- `event_bridge.dart` — redundant wrapper with no value

---

## [0.1.0] - 2026-03-09

### Added
- Initial release as `mcpe2e` (renamed from `e2e_mcp`)
- `McpMetadataKey` — extends `Key`, carries semantic metadata for MCP-testable widgets
- `McpWidgetType` enum (9 types)
- `McpEventType` enum (14 types)
- `McpEventParams` — typed parameters for all events
- `McpEvents` — singleton facade for widget registration and event execution
- `McpEventServer` — embedded HTTP server: `/ping`, `/mcp/context`, `/action`, `/event`, `/widgets`
- 14 event implementations via `GestureBinding.instance.handlePointerEvent`
- Android ADB forwarding support
