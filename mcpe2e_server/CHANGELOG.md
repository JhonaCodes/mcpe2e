# Changelog

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
