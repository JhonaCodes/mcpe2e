# Changelog

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
