# Changelog

## [2.2.0] - 2026-03-13

### Added
- **`mcpe2e_expert` master prompt**: single comprehensive prompt that combines the full agent
  protocol, test writing guide, and widget key conventions into one request. Agents call
  `prompts/get { "name": "mcpe2e_expert" }` once and receive the complete reference —
  widget resolution priority, all 34 tools with decision trees, SCRIPT/GOAL test modes,
  McpMetadataKey naming convention, performance rules, timing heuristics, and error recovery.
- `get_app_context` tool description now hints agents to request the `mcpe2e_expert` prompt.

### Changed
- `prompts/list` now returns `mcpe2e_expert` as the first and primary prompt. The three
  individual prompts (`mcpe2e_workflow`, `mcpe2e_writing_tests`, `mcpe2e_widget_keys`) remain
  available but their descriptions now redirect to `mcpe2e_expert` for the full guide.
- Standardized all documentation to English across READMEs, CLAUDE.md, integration guide,
  test flow examples, and writing tests guide.
- All documentation now reflects the correct widget resolution priority:
  McpMetadataKey (1st) → existing Flutter keys (2nd) → coordinates (fallback) → screenshot (last resort).
- Tool descriptions updated: `tap_at` marked as fallback, `input_text` prioritizes key-based usage,
  `toggle_widget` recommends key mode first.
- All McpMetadataKey examples in docs include required `widgetType` parameter.
- Dependency examples changed from git-based to pub.dev `^2.1.2` format.

---

## [2.1.2] - 2026-03-11

### Added
- `mcpe2e` widget lookup now accepts plain `ValueKey<String>` in addition to
  `McpMetadataKey` and internal `GlobalKey` resolution. This makes `inspect_ui`,
  tap and geometry-driven actions work on apps that already expose conventional
  Flutter keys without requiring MCP-specific key wrappers.

---

## [2.1.0] - 2026-03-10

### Added
- **MCP Prompts capability**: `mcpe2e_server` now exposes the `prompts` capability
  and responds to `prompts/list` and `prompts/get` per the MCP 2024-11-05 spec.
- **`mcpe2e_workflow` prompt**: a universal Flutter E2E workflow guide and agent
  protocol available to any MCP client (Claude, Gemini, Codex, etc.).
  Request it with `prompts/get { "name": "mcpe2e_workflow" }`.
  Covers:
  - Role definition (LLM decides WHAT, tools execute HOW)
  - Core Loop: inspect_ui → identify → center coords → act → verify
  - Tool Decision Tree for every interaction type
  - Patterns: Form, Dialog/Overlay, AppBar dropdown, Custom widgets, Navigation
  - Error Recovery for all common failure scenarios
  - Agent Task Format with generic examples
- `lib/skill.dart` — new file containing `kMcpe2eWorkflowSkill` constant.

---

## [2.0.5] - 2026-03-10

### Changed
- `input_text` description now documents both available options explicitly:
  - **Option 1** (standard): `input_text(x, y, text)` — taps to focus then types via ADB.
    Use `skip_focus_tap: true` when field already has focus (auto_focus or dialog auto-focus).
  - **Option 2** (overlay fallback): `run_command` with `adb shell input text "text"` —
    use when a dialog/overlay blocks the focus tap. Tap the field first with `tap_at`,
    then send text via ADB directly. Works for auth codes, PINs, AlertDialog fields.
- `run_command` description updated with ADB text input fallback example and usage pattern.

---

## [2.0.4] - 2026-03-10

### Fixed
- `input_text` and `toggle_widget` no longer crash with
  `type 'String' is not a subtype of type 'num?'` when the LLM passes
  `x`/`y` coordinates as JSON strings (e.g. `"191"` instead of `191`).
  Applied `_toNumOpt` to all remaining `args['x'] as num?` casts.
  Zero direct `as num` / `as int` casts from args remain in the codebase.

---

## [2.0.3] - 2026-03-10

### Fixed
- `press_back` no longer closes the app when the LLM calls it on the root screen.
  Before sending the system Back event, the tool inspects the live widget tree and
  looks for a `BackButton`, `ArrowBackButton`, or `IconButton` with tooltip "Back"/"Atrás"
  in the AppBar area (y < 200 px). If found, it taps the visual button instead of
  firing the OS back event. Falls through to the system event only when no visual
  back button exists (e.g. closing a dialog with no Cancel button).

### Changed
- `press_back` description updated with explicit warning: the system back event closes
  the app on the root screen. The description now instructs the LLM to inspect_ui first
  and prefer tapping the AppBar back button via tap_at.

---

## [2.0.2] - 2026-03-10

### Changed
- `inspect_ui` reverted to raw JSON output — full widget tree with all types, coordinates,
  values and states. Custom and third-party widgets are fully visible again.
  This was the original behavior that worked reliably for LLM navigation.

### Added
- `inspect_ui_compact` — new dedicated tool for the token-efficient grouped format
  (INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING). Use on simple screens to save tokens;
  use `inspect_ui` whenever custom/third-party widgets are present.

---

## [2.0.1] - 2026-03-10

### Added
- `OTHER` section in `inspect_ui` compact output: custom and third-party widgets that are not
  in the known type set (e.g. `MultiSelectField`, `CustomDropdown`, any third-party widget)
  now appear with their type, key, label, and `tap_at(cx, cy)` coordinates instead of being
  silently dropped. The LLM can now find and interact with any widget in the tree.
- Comprehensive `structuralTypes` exclusion list (~90 Flutter built-in layout/render/scaffold
  widget types) — Column, Row, Stack, Container, Scaffold, Sliver*, Animated*, Clip*, etc.
  are filtered as structural noise. Everything else with coordinates is shown.
- Expanded `interactiveTypes` set: added FloatingActionButton, CupertinoButton, SearchBar,
  DropdownButton, DropdownMenu, MenuAnchor, ActionChip, FilterChip, ChoiceChip, InputChip,
  ListTile, ExpansionTile, SegmentedButton, Stepper and Cupertino equivalents.

---

## [2.0.0] - 2026-03-10

### Fixed
- All numeric args (`x`, `y`, `dx`, `dy`, `scale`, `value`, `duration_ms`,
  `distance`, `max_attempts`) now accept both `num` and `String` via `_toNum`
  helpers. Fixes `type 'String' is not a subtype of type 'num'` crash.

### Added
- `PopupMenuButton` added to `interactiveTypes` in compact `inspect_ui` output.

---

## [1.1.9] - 2026-03-10

### Changed
- Version sync with mcpe2e v1.1.9 — docs overlay keys recommendation.

---

## [1.1.8] - 2026-03-10

### Changed
- Version sync with mcpe2e v1.1.8 — `McpNavigatorObserver` for real route tracking.

---

## [1.1.7] - 2026-03-10

### Changed
- Version sync with mcpe2e v1.1.7 — NaN fix in `inspect_ui` + regression tests.

---

## [1.1.6] - 2026-03-10

### Added
- Auto ADB port forwarding on startup: `mcpe2e_server` runs `adb forward tcp:<port> tcp:7777`
  for every connected device before the first tool call. No manual `adb forward` needed.
- Device watcher: polls `adb devices` every 5 seconds and auto-forwards any device that
  connects after server startup. New device appears in `list_devices` within ≤5s.
- Dynamic port allocation: first device gets :7778, second :7779, etc.

### Changed
- `capture_screenshot`: ADB screencap (`adb exec-out screencap -p`) is now the primary path
  on Android — works in both debug and release builds. Flutter layer tree is the desktop
  fallback (debug/profile only).
- `DeviceRegistry`: added `isRegistered(serial)` and `allUrls` helpers for device watcher logic.

---

## [1.1.5] - 2026-03-10

### Added
- OpenCode agent support in `setup` TUI: toggle registration for OpenCode alongside
  Claude Code, Claude Desktop, Codex CLI, and Gemini CLI.

---

## [1.1.4] - 2026-03-10

### Added
- Dialog interaction: `tap_widget` and `tap_at` now work on AlertDialog, BottomSheet,
  and other overlay widgets that were previously unreachable.
- Coordinate-based gestures: `swipe_widget`, `drag_widget`, and `long_press_widget` now
  accept `x`/`y` coordinate params as an alternative to widget keys.
- Loading-aware `wait`: polls `inspect_ui` until no loading indicators are visible.

---

## [1.1.2] - 2026-03-10

### Fixed
- `inspect_ui` and all GET/POST calls now force UTF-8 decoding via `utf8.decode(response.bodyBytes)`
  instead of `response.body`. Dart's http package defaults to Latin-1 when Content-Type has no
  charset, causing `FormatException: Unexpected extension byte` on any non-ASCII text in the
  widget tree (special characters, accented letters, etc.).

---

## [1.1.1] - 2026-03-10

### Fixed
- `mcpe2e_server setup`: Claude Code registration now uses `--scope user` so the server
  is added to `~/.claude.json` (global) instead of a local `.mcp.json`. Previously the
  TUI always showed Claude Code as "disabled" even after enabling it.
- `install.sh`: same fix applied to the `claude mcp add` call.

---

## [1.1.0] - 2026-03-10

### Added
- `list_devices` tool — discovers all connected Android devices/emulators via ADB, sets up
  port forwarding automatically (starting at :7778), pings each device to verify mcpe2e is running,
  and returns serial, port, url, status, and the active screen name when available.
  Auto-selects the first ready device if none was previously selected.
- `select_device` tool — switches the active target device by serial ID. All subsequent tool
  calls (tap, input, assert, inspect_ui, etc.) are directed to the selected device.
- `DeviceRegistry` — internal class managing one `FlutterBridge` per device with an "active"
  pointer. All 29 existing tools are unchanged; they transparently use `registry.active`.
- `run_command` tool — run any shell command (flutter run, flutter build, dart pub get, adb, etc.)
  with optional `working_dir` and `background` mode. Background=true runs detached (for long-running
  processes like `flutter run`); background=false waits and returns stdout/stderr. Supports pipes,
  `&&`, and all shell features via `sh -c`.

### Changed
- `McpServer` now holds a `DeviceRegistry` instead of a single `FlutterBridge` (backward compat:
  `TESTBRIDGE_URL` is registered as serial `'default'` and used until `list_devices` is called).
- `callTool` signature updated to accept `DeviceRegistry` instead of `FlutterBridge`.

---

## [1.0.8] - 2026-03-10

### Changed
- Removed macos-x86_64 from CI matrix (macos-13 runner consistently hangs)

---

## [1.0.7] - 2026-03-10

### Added
- `tap_at` tool — tap by absolute screen coordinates (x, y). No widget key required.
  Pair with `inspect_ui` to get coordinates: inspect → read x/y/w/h → calculate center → tap_at.
- `setup` subcommand — interactive ANSI CLI to manage AI agent registrations.
  Run: `mcpe2e_server setup`
  Supports: Claude Code, Claude Desktop, Codex CLI (OpenAI), Gemini CLI (Google).
  Shows current status per agent with toggle, enable-all, disable-all options.

### Changed
- Version unified to 1.0.7 across Flutter lib, MCP server, and GitHub tags.
- install.sh now cleans previous installs before downloading, then asks interactively
  which AI agents to register. Run with:
  `curl -fsSL https://raw.githubusercontent.com/JhonaCodes/mcpe2e/main/mcpe2e_server/install.sh -o /tmp/mcpe2e_install.sh && bash /tmp/mcpe2e_install.sh`
- install.ps1 updated with same multi-agent registration support for Windows.

---

## [1.0.0] - 2026-03-09

### Added
- Initial release: 25 tools covering tap, input, scroll, assertions, keyboard, navigation.
- `inspect_ui`: full widget tree traversal with values and states. No registration needed.
- `capture_screenshot`: real PNG via Flutter layer tree.
- Multi-platform support: Android (ADB forward), iOS (iproxy), Desktop (direct localhost).
- Interactive install script for macOS/Linux and PowerShell script for Windows.
- Automatic agent registration for Claude Code during install.
