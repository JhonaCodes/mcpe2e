// ─────────────────────────────────────────────────────────────────────────────
// tools.dart — MCP tools that Claude can invoke
//
// Defines the 25 available tools and translates them to HTTP calls
// against the embedded server in the Flutter app (McpEventServer).
//
// Flow per tool:
//   Claude calls tool → protocol.dart extracts name and args →
//   callTool() translates to HTTP GET/POST → FlutterBridge sends it →
//   McpEventServer in the app executes the event → returns result
//
// Base URL: TESTBRIDGE_URL (e.g. http://localhost:7778 with ADB forward,
//           or http://localhost:7777 on desktop)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'device_registry.dart';

// ── ADB path resolution ───────────────────────────────────────────────────────
// The MCP binary runs in a clean environment without the user's shell PATH.
// Search common Android SDK locations before falling back to bare 'adb'.

String findAdb() {
  final home = Platform.environment['HOME'] ?? '';

  // 1. Explicit SDK env vars
  for (final envKey in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final base = Platform.environment[envKey];
    if (base != null && base.isNotEmpty) {
      final candidate = '$base/platform-tools/adb';
      if (File(candidate).existsSync()) return candidate;
    }
  }

  // 2. Common macOS / Linux locations
  final candidates = [
    '$home/Library/Android/sdk/platform-tools/adb', // macOS default
    '$home/Android/Sdk/platform-tools/adb',         // Linux default
    '/usr/local/share/android-sdk/platform-tools/adb',
    '/opt/android-sdk/platform-tools/adb',
    '/usr/local/bin/adb',
    '/opt/homebrew/bin/adb',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  // 3. Try 'which adb' as last resort
  try {
    final which = Process.runSync('which', ['adb']);
    if (which.exitCode == 0) return (which.stdout as String).trim();
  } catch (_) {}

  return 'adb'; // will fail with a clear ProcessException
}

// ── HTTP Bridge ───────────────────────────────────────────────────────────────

/// HTTP client to the embedded server in the Flutter app.
///
/// [baseUrl] points to where McpEventServer listens.
/// On Android: http://localhost:7778 (ADB forward device:7777)
/// On desktop: http://localhost:7777 (no forwarding)
class FlutterBridge {
  final String baseUrl;
  final http.Client _client = http.Client();

  FlutterBridge(this.baseUrl);

  /// GET [path] → returns response body as String (forcing UTF-8).
  Future<String> get(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    return response.body;
  }

  /// POST [path] with JSON [body] → returns response body as String (forcing UTF-8).
  Future<String> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return response.body;
  }
}

// ── Auto-fallback helper ──────────────────────────────────────────────────────

/// Executes [action] using the registered key. If Flutter returns an error,
/// looks up the widget by its [key] field in the live tree and taps at its
/// center as a fallback.
///
/// Applies to: toggle_widget, tap_widget, double_tap_widget,
///             long_press_widget, show_keyboard.
Future<List<Map<String, dynamic>>> _withCoordFallback({
  required String key,
  required Future<String> Function() action,
  required FlutterBridge bridge,
}) async {
  final result = await action();
  // Success path — return immediately
  if (!result.contains('Error:') && !result.toLowerCase().contains('failed')) {
    return [{'type': 'text', 'text': result}];
  }
  // Fallback: find widget by key in live tree, tap its center
  try {
    final tree = await bridge.get('/mcp/tree');
    final treeData = jsonDecode(tree) as Map<String, dynamic>;
    final widgets =
        (treeData['widgets'] as List? ?? []).cast<Map<String, dynamic>>();
    final w = widgets.firstWhere((w) => w['key'] == key, orElse: () => {});
    if (w.isNotEmpty) {
      final cx = (w['x'] as num) + (w['w'] as num) / 2;
      final cy = (w['y'] as num) + (w['h'] as num) / 2;
      final tap =
          await bridge.get('/action?key=_&type=tapat&dx=$cx&dy=$cy');
      return [
        {
          'type': 'text',
          'text':
              'fallback_tap(${cx.toStringAsFixed(1)},${cy.toStringAsFixed(1)}): $tap',
        }
      ];
    }
  } catch (_) {}
  return [{'type': 'text', 'text': result}]; // original error if nothing worked
}

// ── Loading-aware wait helper ─────────────────────────────────────────────────

/// Waits until there are no visible loading indicators in the tree.
///
/// Strategy:
///   1. Checks the tree immediately (zero overhead on screens without loading).
///   2. If loading, re-checks every [pollMs] ms until [timeoutMs].
///   3. Returns null if idle, or a timeout message if loading did not disappear.
///
/// Detects: CircularProgressIndicator, LinearProgressIndicator,
///          RefreshProgressIndicator, and any widget with "loading": true.
Future<String?> _waitForIdle(
  FlutterBridge bridge, {
  int pollMs = 300,
  int timeoutMs = 10000,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  var firstCheck = true;

  while (DateTime.now().isBefore(deadline)) {
    try {
      final tree = await bridge.get('/mcp/tree');
      final data = jsonDecode(tree) as Map<String, dynamic>;
      final widgets =
          (data['widgets'] as List? ?? []).cast<Map<String, dynamic>>();
      final isLoading = widgets.any((w) => w['loading'] as bool? ?? false);
      if (!isLoading) return null; // idle — no loading
    } catch (_) {
      return null; // cannot check → assume idle
    }

    if (firstCheck) {
      firstCheck = false;
      // First time loading was found: short wait before the first poll
      await Future.delayed(const Duration(milliseconds: 150));
    } else {
      await Future.delayed(Duration(milliseconds: pollMs));
    }
  }
  return 'loading_timeout_${timeoutMs}ms';
}

/// Executes [action], then waits for the UI to become idle (no loading).
/// If there is a loading timeout, appends a warning to the result.
Future<List<Map<String, dynamic>>> _thenWaitIdle(
  Future<List<Map<String, dynamic>>> action,
  FlutterBridge bridge,
) async {
  final result = await action;
  final warn = await _waitForIdle(bridge);
  if (warn == null) return result;
  return [
    ...result,
    {'type': 'text', 'text': 'warn: UI still loading after ${warn.replaceAll('loading_timeout_', '')} — consider adding a wait.'},
  ];
}

// ── Tool definitions ─────────────────────────────────────────────────────────

/// The 25 MCP tools that Claude can invoke.
///
/// Each entry follows the MCP JSON-Schema for tool definitions.
final List<Map<String, dynamic>> toolDefinitions = [

  // ── Context ────────────────────────────────────────────────────────────────

  {
    'name': 'get_app_context',
    'description':
        'Gets the current app state: active screen and widgets that have '
        'a registered McpMetadataKey ("key" field present). '
        'Use it to discover which keys are active BEFORE running key-based tools. '
        'To see ALL widgets with x/y coordinates, use inspect_ui. '
        'Recommended flow: get_app_context (discover available keys) → '
        'inspect_ui (coordinates for any widget) → actions. '
        'TIP: Request the "mcpe2e_expert" prompt for the complete agent protocol.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'list_test_cases',
    'description': 'Alias of get_app_context. Lists widgets registered with McpMetadataKey.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },

  // ── Basic gestures ─────────────────────────────────────────────────────────

  {
    'name': 'tap_widget',
    'description': 'Single tap on a widget. Equivalent to a user touch.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID (e.g. "auth.login_button")'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'double_tap_widget',
    'description': 'Double tap on a widget. Useful for zoom or other double-tap actions.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'long_press_widget',
    'description': 'Long press. Triggers context menus and hold actions.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID'},
        'duration_ms': {'type': 'integer', 'description': 'Duration in ms (default: 500)'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'swipe_widget',
    'description': 'Swipe on a widget. Useful for swipe-to-delete, carousels, etc.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID'},
        'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
        'distance': {'type': 'number', 'description': 'Distance in px (default: 300)'},
      },
      'required': ['key', 'direction'],
    },
  },
  {
    'name': 'scroll_widget',
    'description':
        'Scroll a scrollable widget (ListView, SingleChildScrollView, etc.). '
        'key is optional — if omitted, scrolls the active scrollable widget on screen. '
        'amount/distance: pixels to scroll (default: 300).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Scrollable widget ID (optional)'},
        'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
        'amount': {'type': 'number', 'description': 'Pixels to scroll (alias of distance, default: 300)'},
        'distance': {'type': 'number', 'description': 'Pixels to scroll (default: 300)'},
      },
      'required': ['direction'],
    },
  },
  {
    'name': 'tap_at',
    'description':
        'Tap at absolute screen coordinates (logical pixels). '
        'FALLBACK — prefer tap_widget(key) when the widget has a key. '
        'Use tap_at for widgets without a key: dynamic cards, list items, third-party widgets. '
        'Get coordinates from inspect_ui (x, y, w, h fields). '
        'Coordinates are top-left corner; to tap center: x + w/2, y + h/2.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'number', 'description': 'X coordinate in logical pixels'},
        'y': {'type': 'number', 'description': 'Y coordinate in logical pixels'},
      },
      'required': ['x', 'y'],
    },
  },
  {
    'name': 'tap_by_label',
    'description':
        'Tap on a widget by searching for its visible text. '
        'Useful when the widget has no registered ID but has recognizable text '
        '(e.g. custom dropdown options, menu items).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'label': {'type': 'string', 'description': 'Visible text of the widget to tap'},
      },
      'required': ['label'],
    },
  },

  // ── Input ──────────────────────────────────────────────────────────────────

  {
    'name': 'input_text',
    'description':
        'Types text into a TextField or TextFormField. Three options in priority order:\n\n'
        'OPTION 1 — input_text with key (recommended):\n'
        '  input_text(key, text) — use when the field has a "key" in inspect_ui.\n'
        '  Fastest and most stable. Works with McpMetadataKey or ValueKey.\n\n'
        'OPTION 2 — input_text with coordinates (fallback):\n'
        '  inspect_ui → get x/y of the field → input_text(x, y, text)\n'
        '  Taps at (x,y) to focus the field, then types via ADB.\n'
        '  If the field already has focus (auto_focus: true in inspect_ui), use skip_focus_tap: true\n'
        '  to avoid dismissing the keyboard with the tap.\n\n'
        'OPTION 3 — run_command with ADB (last resort for dialogs/overlays):\n'
        '  When input_text fails in a dialog or the tap does not reach the correct field,\n'
        '  use run_command with: adb shell input text "your_text"\n'
        '  Requires the field to already be focused (tap it first with tap_at).\n'
        '  Useful for: auth codes, PIN fields, AlertDialog/BottomSheet inputs.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'number', 'description': 'X coordinate of the field (from inspect_ui)'},
        'y': {'type': 'number', 'description': 'Y coordinate of the field (from inspect_ui)'},
        'key': {'type': 'string', 'description': 'Field ID (only if it has a "key" field in inspect_ui)'},
        'text': {'type': 'string', 'description': 'Text to type'},
        'clear_first': {'type': 'boolean', 'description': 'Clear field before typing (default: false)'},
        'skip_focus_tap': {
          'type': 'boolean',
          'description':
              'Skip the focus tap before typing (default: false). '
              'Use true when the field has "auto_focus": true in inspect_ui, '
              'or when the field is already focused and you do not want to dismiss the keyboard.',
        },
      },
      'required': ['text'],
    },
  },
  {
    'name': 'clear_text',
    'description': 'Clears the content of a TextField without typing new text.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID of the field to clear'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'select_dropdown',
    'description':
        'Selects an option from a standard DropdownButtonFormField. '
        'For custom dropdowns (BottomSheet, overlay), use tap_widget + tap_by_label.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Dropdown ID'},
        'value': {'type': 'string', 'description': 'Value to select (or partial enum string)'},
        'index': {'type': 'integer', 'description': '0-based index (alternative to value)'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'toggle_widget',
    'description':
        'Toggles a Checkbox, Switch, or Radio button on or off. '
        'Key mode (recommended): provide key from inspect_ui. '
        'Coordinate mode (fallback for dialogs/overlays): provide x/y '
        'from inspect_ui — simulates a real tap. '
        'If x/y are present, coordinates are used even if key is also provided.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'number', 'description': 'X coordinate of the control (from inspect_ui) — PREFERRED'},
        'y': {'type': 'number', 'description': 'Y coordinate of the control (from inspect_ui) — PREFERRED'},
        'key': {'type': 'string', 'description': 'Widget ID (if it has a "key" field in inspect_ui)'},
      },
      'required': [],
    },
  },
  {
    'name': 'set_slider_value',
    'description':
        'Sets a Slider to a relative value between 0.0 (minimum) and 1.0 (maximum).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Slider ID'},
        'value': {'type': 'number', 'description': 'Value between 0.0 and 1.0 (e.g. 0.5 = midpoint)'},
      },
      'required': ['key', 'value'],
    },
  },

  // ── Keyboard and navigation ────────────────────────────────────────────────

  {
    'name': 'hide_keyboard',
    'description': 'Hides the virtual keyboard.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'press_back',
    'description':
        'Sends the OS Back event (Android physical button / iOS gesture). '
        'WARNING: If the current screen is the app root screen (home/root), '
        'this event CLOSES the application. '
        'BEFORE calling press_back, call inspect_ui and look for: '
        '(1) a BackButton, ArrowBackButton, or IconButton widget with tooltip "Back", '
        '(2) the AppBar leading button — use tap_at with its coordinates instead. '
        'Use press_back ONLY when there is no visible back button on screen '
        'or when you want to close a dialog/overlay with the system gesture.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Any widget ID (optional)'},
      },
      'required': [],
    },
  },
  {
    'name': 'scroll_until_visible',
    'description':
        'Scrolls a container widget until the target widget is visible on screen. '
        'Use this when you need to interact with a widget that is off-viewport.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Scrollable widget ID (ListView, etc.)'},
        'target_key': {'type': 'string', 'description': 'ID of the widget that should become visible'},
        'max_attempts': {'type': 'integer', 'description': 'Maximum scroll attempts (default: 20)'},
      },
      'required': ['key', 'target_key'],
    },
  },

  // ── Utilities ──────────────────────────────────────────────────────────────

  {
    'name': 'wait',
    'description': 'Waits for a duration before continuing. Useful after animations or transitions.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'duration_ms': {'type': 'integer', 'description': 'Wait time in milliseconds'},
      },
      'required': ['duration_ms'],
    },
  },

  // ── Assertions ─────────────────────────────────────────────────────────────

  {
    'name': 'assert_exists',
    'description': 'Verifies that the widget is registered. Does not require it to be visible.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID to verify'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_text',
    'description': 'Verifies that the visible text of a widget matches the expected value.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID'},
        'text': {'type': 'string', 'description': 'Expected text (exact match)'},
      },
      'required': ['key', 'text'],
    },
  },
  {
    'name': 'assert_visible',
    'description':
        'Verifies that the widget is fully visible in the current viewport. '
        'Fails if the widget is off-screen or obscured.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_enabled',
    'description': 'Verifies that the widget is enabled (not disabled).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID (Button, TextField, Checkbox, etc.)'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_selected',
    'description': 'Verifies that a Checkbox, Switch, or Radio is selected/checked.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Checkbox, Switch, or Radio ID'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_value',
    'description':
        'Verifies the value of a TextField\'s TextEditingController. '
        'Unlike assert_text, this checks the internal field value, not the label.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'TextField ID'},
        'value': {'type': 'string', 'description': 'Expected value in the controller'},
      },
      'required': ['key', 'value'],
    },
  },
  {
    'name': 'assert_count',
    'description': 'Verifies that a Column, Row, or ListView has exactly N children.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Container widget ID'},
        'count': {'type': 'integer', 'description': 'Expected number of children'},
      },
      'required': ['key', 'count'],
    },
  },

  // ── Drag, pinch, show keyboard ─────────────────────────────────────────────

  {
    'name': 'drag_widget',
    'description':
        'Drags a widget by a relative pixel offset from its center. '
        'dx > 0 = right, dx < 0 = left, dy > 0 = down, dy < 0 = up. '
        'Useful for drag-to-reorder, pull-to-refresh, and custom drag targets.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID to drag from'},
        'dx': {'type': 'number', 'description': 'Horizontal pixel offset (positive = right)'},
        'dy': {'type': 'number', 'description': 'Vertical pixel offset (positive = down)'},
        'duration_ms': {'type': 'integer', 'description': 'Drag duration in ms (default: 500)'},
      },
      'required': ['key', 'dx', 'dy'],
    },
  },
  {
    'name': 'pinch_widget',
    'description':
        'Pinch zoom gesture on a widget. scale > 1.0 zooms in (spread), scale < 1.0 zooms out (pinch). '
        'Note: pinch requires dual-pointer simulation — not yet implemented on the Flutter side; '
        'this will return false until implemented.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID to pinch'},
        'scale': {'type': 'number', 'description': 'Scale factor (e.g. 2.0 = double size, 0.5 = half)'},
      },
      'required': ['key', 'scale'],
    },
  },
  {
    'name': 'show_keyboard',
    'description':
        'Requests focus on a widget to show the virtual keyboard. '
        'Use before input_text if the keyboard is not appearing automatically. '
        'Pair with hide_keyboard to dismiss it after input.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID of the focusable field'},
      },
      'required': ['key'],
    },
  },

  // ── UI inspection ──────────────────────────────────────────────────────────

  {
    'name': 'inspect_ui',
    'description':
        'Traverses the full widget tree and returns ALL widgets with: '
        'visible text, x/y/w/h (coordinates in logical pixels), type, state. '
        'Widgets with McpMetadataKey also have a "key" field — '
        'that field indicates the widget can be used with key-based tools (assert_*, tap_widget, etc.). '
        'No "key" field: use coordinates → tap_at, input_text with x/y. '
        'With "key" field: you can use either coordinates or the key. '
        'ALWAYS call inspect_ui before input_text to get the x/y coordinates of the field. '
        'Widgets inside dialogs, BottomSheets, or AlertDialogs have "overlay": true — '
        'identify which widgets belong to the active dialog. '
        'TextFields with "auto_focus": true already have focus when they appear — '
        'use input_text with skip_focus_tap: true to avoid dismissing the keyboard. '
        'CircularProgressIndicator, LinearProgressIndicator, and RefreshProgressIndicator '
        'have "loading": true — if present, the UI is busy; '
        'action tools automatically wait until they disappear.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'inspect_ui_compact',
    'description':
        'Compact version of inspect_ui: groups widgets into sections '
        'INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING with pre-calculated centers. '
        'Use this when the screen is simple and you want to save tokens. '
        'For complex screens or custom (third-party) widgets, use inspect_ui '
        'to get the full JSON with all widgets and exact coordinates.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'capture_screenshot',
    'description':
        'Captures the current screen as a PNG image. '
        'Use for: detecting visual issues, broken layout, incorrect colors, '
        'or general visual verification. '
        'On Android uses ADB screencap (always available, debug and release). '
        'On desktop uses the Flutter layer tree (debug/profile only). '
        'To verify data values, prefer inspect_ui (more token-efficient).',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },

  // ── Command execution ──────────────────────────────────────────────────────

  {
    'name': 'run_command',
    'description':
        'Run any shell command, optionally in a working directory. '
        'Supports any CLI tool: flutter run, flutter build, dart pub get, adb, etc. '
        'Use background:true for long-running processes (e.g. flutter run) — returns '
        'immediately with the PID. Use background:false (default) to wait and capture '
        'stdout/stderr — suitable for finite commands (build, pub get, analyze, etc.). '
        'Supports pipes, &&, and shell features via sh -c. '
        'ADB text input fallback (for dialogs/overlays where input_text tap fails): '
        'tap_at to focus field first, then: '
        'adb -s <serial> shell input text "your_text" '
        'Useful for: auth codes, PIN fields, AlertDialog inputs. '
        'Find device serial with: adb devices. '
        'Examples: '
        '"flutter run -d emulator-5554 --flavor dev" (background:true), '
        '"flutter pub get" (background:false), '
        '"adb -s SERIAL shell input text \\"2222\\"" (text input fallback).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'Shell command to execute. Supports pipes, &&, env vars, quotes.',
        },
        'working_dir': {
          'type': 'string',
          'description': 'Absolute path to run the command in (e.g. Flutter project root).',
        },
        'background': {
          'type': 'boolean',
          'description':
              'Run detached in background (default: false). '
              'Set true for long-running processes like flutter run. '
              'Set false to wait and capture output.',
        },
      },
      'required': ['command'],
    },
  },

  // ── Multi-device ───────────────────────────────────────────────────────────

  {
    'name': 'list_devices',
    'description': 'Discover connected Android devices and emulators via ADB. '
        'Automatically sets up port forwarding for each device and checks '
        'whether mcpe2e is running. Returns the list with their serial IDs, status, '
        'and the active screen name when available. '
        'Call this first when testing on multiple devices.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'select_device',
    'description': 'Switch the active target device. All subsequent tool calls '
        '(tap, input, assert, etc.) will be directed to this device. '
        'Use list_devices first to see available device IDs.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'device_id': {
          'type': 'string',
          'description': 'Device serial from list_devices (e.g. "emulator-5554")',
        },
      },
      'required': ['device_id'],
    },
  },
];

// ── Tool implementation ──────────────────────────────────────────────────────

/// Executes the tool [name] with the arguments [args] via HTTP to the app.
///
/// Returns an MCP content array:
/// - Text: `[{"type":"text","text":"..."}]`
/// - Image: `[{"type":"image","data":"<base64>","mimeType":"image/png"}]`
///
/// Translates each tool to the corresponding HTTP call:
/// - Simple gestures → GET /action?key=...&type=...
/// - Assertions → POST /event with JSON
/// - wait → local Future.delayed (no HTTP)
/// - inspect_ui → GET /mcp/tree (JSON text)
/// - capture_screenshot → GET /mcp/screenshot (PNG image)
///
/// The function is NOT async: each switch branch returns a
/// Future<List<...>> directly to maintain type consistency in the switch expression.
Future<List<Map<String, dynamic>>> callTool(
    DeviceRegistry registry, String name, Map<String, dynamic> args) {
  final bridge = registry.active; // all 29 existing cases use this — zero changes needed below

  // Helper: wrap text in MCP content array
  List<Map<String, dynamic>> t(String s) => [{'type': 'text', 'text': s}];

  // Helper: wrap image in MCP content array
  List<Map<String, dynamic>> img(String base64) =>
      [{'type': 'image', 'data': base64, 'mimeType': 'image/png'}];

  // Helper: encode key for URL
  String k(String key) => Uri.encodeQueryComponent(key);

  return switch (name) {

    // ── Context ──────────────────────────────────────────────────────────────
    'get_app_context' || 'list_test_cases' => () async {
      final ctx = await bridge.get('/mcp/context');
      final data = jsonDecode(ctx) as Map<String, dynamic>;
      // If screen is unknown (no McpMetadataKey on root), enrich with AppBar
      // title from the live widget tree so the LLM always has a screen name.
      final screen = (data['screen'] as String?) ?? '';
      if (screen.toLowerCase().contains('unknown') || screen.isEmpty) {
        try {
          final tree = await bridge.get('/mcp/tree');
          final treeData = jsonDecode(tree) as Map<String, dynamic>;
          final widgets =
              (treeData['widgets'] as List? ?? []).cast<Map<String, dynamic>>();
          final appBar =
              widgets.where((w) => w['type'] == 'AppBar').firstOrNull;
          final title = appBar?['title'] as String?;
          if (title != null) {
            data['screen'] = title;
            data['note'] =
                'Screen inferred from AppBar. Register McpMetadataKey on '
                'the root widget for stable screen IDs.';
          }
        } catch (_) {}
      }
      return t(jsonEncode(data));
    }(),

    // ── Basic gestures ────────────────────────────────────────────────────────
    'tap_widget' =>
      _thenWaitIdle(
        _withCoordFallback(
          key: args['key'] as String,
          action: () => bridge.get('/action?key=${k(args['key'] as String)}'),
          bridge: bridge,
        ),
        bridge,
      ),

    'double_tap_widget' =>
      _thenWaitIdle(
        _withCoordFallback(
          key: args['key'] as String,
          action: () =>
              bridge.get('/action?key=${k(args['key'] as String)}&type=doubletap'),
          bridge: bridge,
        ),
        bridge,
      ),

    'long_press_widget' => () {
        final ms = _toIntOpt(args['duration_ms']) ?? 500;
        return _thenWaitIdle(
          _withCoordFallback(
            key: args['key'] as String,
            action: () => bridge.get(
                '/action?key=${k(args['key'] as String)}&type=longpress&duration=$ms'),
            bridge: bridge,
          ),
          bridge,
        );
      }(),

    'swipe_widget' => () {
        final key = k(args['key'] as String);
        final dir = args['direction'] as String;
        final dist = _toNumOpt(args['distance']);
        final q = dist != null ? '&distance=$dist' : '';
        return bridge.get('/action?key=$key&type=swipe&direction=$dir$q').then(t);
      }(),

    'scroll_widget' => () async {
        final dir = args['direction'] as String;
        final rawKey = args['key'] as String?;
        // accept both 'amount' and 'distance' as aliases
        final dist = (_toNumOpt(args['amount']) ?? _toNumOpt(args['distance']) ?? 300).toDouble();

        // No key → ADB swipe directly (no registered widget needed)
        if (rawKey == null || rawKey.isEmpty) {
          // Standard portrait screen center — swipe from/to based on direction
          // "down" = content scrolls down = finger swipes up (start low, end high)
          const cx = 540.0;
          const cy = 960.0;
          double x1 = cx, y1 = cy, x2 = cx, y2 = cy;
          switch (dir) {
            case 'down':  y1 = cy + dist / 2; y2 = cy - dist / 2;
            case 'up':    y1 = cy - dist / 2; y2 = cy + dist / 2;
            case 'right': x1 = cx + dist / 2; x2 = cx - dist / 2;
            case 'left':  x1 = cx - dist / 2; x2 = cx + dist / 2;
          }
          final adb = findAdb();
          final serial = registry.activeSerial;
          final base = serial == 'default' ? <String>[] : ['-s', serial];
          final r = Process.runSync(
              adb, [...base, 'shell', 'input', 'swipe',
                '${x1.round()}', '${y1.round()}',
                '${x2.round()}', '${y2.round()}', '600']);
          return t(jsonEncode({
            'ok': r.exitCode == 0,
            'method': 'adb_swipe',
            'direction': dir,
            'distance': dist,
            if (r.exitCode != 0) 'stderr': r.stderr,
          }));
        }

        // Key provided → try Flutter bridge
        final q = '&distance=$dist';
        return _thenWaitIdle(
          bridge.get('/action?key=${k(rawKey)}&type=scroll&direction=$dir$q').then(t),
          bridge,
        );
      }(),

    'tap_at' => () {
        final x = _toNum(args['x']);
        final y = _toNum(args['y']);
        return _thenWaitIdle(
          bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y').then(t),
          bridge,
        );
      }(),

    'tap_by_label' => () {
        final label = Uri.encodeQueryComponent(args['label'] as String);
        return _thenWaitIdle(
          bridge.get('/action?key=_&type=tapbylabel&label=$label').then(t),
          bridge,
        );
      }(),

    // ── Input ─────────────────────────────────────────────────────────────────
    'input_text' => () async {
        final text = args['text'] as String;
        final clear = args['clear_first'] as bool? ?? false;
        final x = _toNumOpt(args['x']);
        final y = _toNumOpt(args['y']);
        final key = args['key'] as String?;

        // Coordinate-based (preferred): tap to focus + ADB to type
        if (x != null && y != null) {
          final skipTap = args['skip_focus_tap'] as bool? ?? false;

          if (!skipTap) {
            // Focus field by tapping at coordinates
            await bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y');
            await Future.delayed(const Duration(milliseconds: 300));
          }

          if (clear) {
            // KEYCODE_DEL repeated — avoids coordinate-shift from triple-tap
            final adb = findAdb();
            final serial = registry.activeSerial;
            final base = serial == 'default' ? <String>[] : ['-s', serial];
            for (int i = 0; i < 8; i++) {
              Process.runSync(
                  adb, [...base, 'shell', 'input', 'keyevent', 'KEYCODE_DEL']);
            }
            await Future.delayed(const Duration(milliseconds: 200));
          }

          final adb = findAdb();
          final serial = registry.activeSerial;
          final base = serial == 'default' ? <String>[] : ['-s', serial];
          final result =
              Process.runSync(adb, [...base, 'shell', 'input', 'text', text]);
          if (result.exitCode != 0) {
            return t('Error: ADB input text failed. ${result.stderr}');
          }
          return await _thenWaitIdle(
            Future.value(t(jsonEncode({
              'ok': true,
              'method': 'coordinates',
              'x': x,
              'y': y,
              if (skipTap) 'skipped_focus_tap': true,
            }))),
            bridge,
          );
        }

        // Key-based fallback (only when widget has McpMetadataKey)
        if (key == null || key.isEmpty) {
          return t('Error: provide x/y coordinates (from inspect_ui) or a registered key.');
        }
        final encodedText = Uri.encodeQueryComponent(text);
        final clearParam = clear ? '&clearFirst=true' : '';
        return _thenWaitIdle(
          bridge
              .get('/action?key=${k(key)}&type=textinput&text=$encodedText$clearParam')
              .then(t),
          bridge,
        );
      }(),

    'clear_text' =>
      bridge.get('/action?key=${k(args['key'])}&type=cleartext').then(t),

    'select_dropdown' => () {
        final key = k(args['key'] as String);
        if (args.containsKey('index')) {
          return bridge.get('/action?key=$key&type=selectdropdown&dropdownIndex=${args['index']}').then(t);
        }
        final val = Uri.encodeQueryComponent(args['value'] as String? ?? '');
        return bridge.get('/action?key=$key&type=selectdropdown&dropdownValue=$val').then(t);
      }(),

    'toggle_widget' => () async {
        final x = _toNumOpt(args['x']);
        final y = _toNumOpt(args['y']);
        final key = args['key'] as String?;

        // Coordinate mode (preferred — real pointer event triggers gestures natively)
        if (x != null && y != null) {
          return _thenWaitIdle(
            bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y').then(
                (r) => [{'type': 'text', 'text': r}]),
            bridge,
          );
        }

        // Key mode with auto-fallback
        if (key == null || key.isEmpty) {
          return [
            {
              'type': 'text',
              'text': 'Error: provide x/y coordinates or a registered key.',
            }
          ];
        }
        return _thenWaitIdle(
          _withCoordFallback(
            key: key,
            action: () => bridge.get('/action?key=${k(key)}&type=toggle'),
            bridge: bridge,
          ),
          bridge,
        );
      }(),

    'set_slider_value' => () {
        final val = _toNum(args['value']);
        return bridge.get('/action?key=${k(args['key'])}&type=setslidervalue&sliderValue=$val').then(t);
      }(),

    // ── Keyboard and navigation ───────────────────────────────────────────────
    'hide_keyboard' =>
      bridge.get('/action?key=_keyboard&type=hidekeyboard').then(t),

    'press_back' => () async {
        // Smart back: prefer tapping the AppBar leading/back button over
        // the system back event, which closes the app on the root screen.
        try {
          final tree = await bridge.get('/mcp/tree');
          final data = jsonDecode(tree) as Map<String, dynamic>;
          final widgets = (data['widgets'] as List? ?? []).cast<Map<String, dynamic>>();

          // Look for a visible back button in the AppBar area (y < 120 logical px)
          final backWidget = widgets.firstWhere(
            (w) {
              final type    = (w['type'] as String?) ?? '';
              final tooltip = ((w['tooltip'] as String?) ?? '').toLowerCase();
              final label   = ((w['label']   as String?) ?? '').toLowerCase();
              final y       = (w['y'] as num?) ?? 9999;
              final isBackType = type == 'BackButton' ||
                  type == 'ArrowBackButton' ||
                  (type == 'IconButton' && (tooltip.contains('back') || tooltip.contains('atrás') || label.contains('back')));
              return isBackType && y < 200;
            },
            orElse: () => <String, dynamic>{},
          );

          if (backWidget.isNotEmpty) {
            // Tap the visual back button instead of the system event
            final xVal = backWidget['x'] as num?;
            final yVal = backWidget['y'] as num?;
            if (xVal == null || yVal == null) throw Exception('missing coords');
            final x  = xVal.toDouble();
            final y  = yVal.toDouble();
            final w  = (backWidget['w'] as num?)?.toDouble() ?? 48;
            final h  = (backWidget['h'] as num?)?.toDouble() ?? 48;
            final cx = (x + w / 2).round();
            final cy = (y + h / 2).round();
            return _thenWaitIdle(
              bridge.post('/action', {'type': 'tapAt', 'dx': cx, 'dy': cy}).then(t),
              bridge,
            );
          }
        } catch (_) {
          // Fall through to system back on any error
        }

        final key = args['key'] as String? ?? '_';
        return _thenWaitIdle(
          bridge.get('/action?key=${k(key)}&type=pressback').then(t),
          bridge,
        );
      }(),

    'scroll_until_visible' => () {
        final key = k(args['key'] as String);
        final target = Uri.encodeQueryComponent(args['target_key'] as String);
        final maxA = _toIntOpt(args['max_attempts']) ?? 20;
        return bridge.get('/action?key=$key&type=scrolluntilvisible&targetKey=$target&maxScrollAttempts=$maxA').then(t);
      }(),

    // ── Utilities ─────────────────────────────────────────────────────────────
    'wait' => () async {
        final ms = _toInt(args['duration_ms']);
        await Future.delayed(Duration(milliseconds: ms));
        return t(jsonEncode({'ok': true, 'waited_ms': ms}));
      }(),

    // ── Assertions ────────────────────────────────────────────────────────────
    'assert_exists' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertExists', 'params': {}}).then(t),

    'assert_text' =>
      bridge.post('/event', {
        'key': args['key'],
        'type': 'assertText',
        'params': {'expectedText': args['text']},
      }).then(t),

    'assert_visible' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertVisible', 'params': {}}).then(t),

    'assert_enabled' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertEnabled', 'params': {}}).then(t),

    'assert_selected' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertSelected', 'params': {}}).then(t),

    'assert_value' =>
      bridge.post('/event', {
        'key': args['key'],
        'type': 'assertValue',
        'params': {'expectedText': args['value']},
      }).then(t),

    'assert_count' =>
      bridge.post('/event', {
        'key': args['key'],
        'type': 'assertCount',
        'params': {'expectedCount': args['count']},
      }).then(t),

    // ── Drag, pinch, show keyboard ────────────────────────────────────────────
    'drag_widget' => () {
        final ms = _toIntOpt(args['duration_ms']) ?? 500;
        final dx = _toNum(args['dx']);
        final dy = _toNum(args['dy']);
        return bridge.get(
          '/action?key=${k(args['key'])}&type=drag&deltaX=$dx&deltaY=$dy&duration=$ms',
        ).then(t);
      }(),

    'pinch_widget' => () {
        final scale = _toNum(args['scale']);
        return bridge.get(
          '/action?key=${k(args['key'])}&type=pinch&scale=$scale',
        ).then(t);
      }(),

    'show_keyboard' =>
      _withCoordFallback(
        key: args['key'] as String,
        action: () =>
            bridge.get('/action?key=${k(args['key'] as String)}&type=showkeyboard'),
        bridge: bridge,
      ),

    // ── UI inspection ────────────────────────────────────────────────────────
    // Returns raw JSON widget tree — full fidelity, all widget types visible.
    'inspect_ui' =>
      bridge.get('/mcp/tree').then((raw) => t(raw)),

    // Compact grouped summary: INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING.
    // Token-efficient for simple screens; use inspect_ui for custom/third-party widgets.
    'inspect_ui_compact' =>
      bridge.get('/mcp/tree').then((raw) => t(_compactTree(raw))),

    'capture_screenshot' => () async {
        // ── Android: ADB screencap (primary — reliable in debug and release) ──
        // adb exec-out screencap -p → raw PNG bytes to stdout (no shell encoding)
        final adb = findAdb();
        final serial = registry.activeSerial;
        final base = serial == 'default' ? <String>[] : ['-s', serial];
        final adbResult = Process.runSync(
          adb,
          [...base, 'exec-out', 'screencap', '-p'],
          stdoutEncoding: null, // null = List<int>, avoids UTF-8 corruption of binary
        );
        if (adbResult.exitCode == 0) {
          final bytes = adbResult.stdout as List<int>;
          // Verify PNG magic bytes (89 50 4E 47) to confirm valid output
          if (bytes.length > 4 &&
              bytes[0] == 0x89 && bytes[1] == 0x50 &&
              bytes[2] == 0x4E && bytes[3] == 0x47) {
            return img(base64Encode(bytes));
          }
        }

        // ── Desktop fallback: Flutter layer tree (debug/profile only) ──
        try {
          final raw = await bridge.get('/mcp/screenshot');
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json.containsKey('error')) return t('Error: ${json['error']}');
          return img(json['base64'] as String);
        } catch (e) {
          return t('Error: screenshot failed. ADB not available and Flutter capture failed: $e');
        }
      }(),

    // ── Command execution ─────────────────────────────────────────────────────
    'run_command' => () async {
      final command = args['command'] as String? ?? '';
      final workingDir = args['working_dir'] as String?;
      final background = args['background'] as bool? ?? false;

      if (command.isEmpty) return t('Error: command is required');

      if (background) {
        // Detached — does not block MCP, suitable for flutter run
        final process = await Process.start(
          'sh', ['-c', command],
          workingDirectory: workingDir,
          mode: ProcessStartMode.detached,
        );
        return t(jsonEncode({
          'ok': true,
          'pid': process.pid,
          'command': command,
          if (workingDir != null) 'working_dir': workingDir,
          'background': true,
          'note': 'Process started in background. '
              'Call list_devices in ~15s to verify the app is ready.',
        }));
      } else {
        // Foreground — waits and captures output
        final result = await Process.run(
          'sh', ['-c', command],
          workingDirectory: workingDir,
        );
        return t(jsonEncode({
          'exit_code': result.exitCode,
          if ((result.stdout as String).isNotEmpty) 'stdout': result.stdout,
          if ((result.stderr as String).isNotEmpty) 'stderr': result.stderr,
        }));
      }
    }(),

    // ── Multi-device ──────────────────────────────────────────────────────────
    'list_devices' => () async {
      final adb = findAdb();
      final result = Process.runSync(adb, ['devices']);
      if (result.exitCode != 0) {
        return t('Error: adb not found. Tried PATH and common SDK locations. '
            'Set ANDROID_HOME or install Android SDK platform-tools.');
      }

      final lines = (result.stdout as String)
          .split('\n')
          .skip(1) // skip "List of devices attached"
          .where((l) => l.trim().isNotEmpty && l.contains('\t'))
          .toList();

      if (lines.isEmpty) {
        return t('No devices connected. Connect a device or start an emulator.');
      }

      // Find next free local port starting from [base], skipping occupied ones.
      Future<int> nextFreePort(int base) async {
        var p = base;
        while (p < 65535) {
          try {
            final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
            await s.close();
            return p; // port was free
          } catch (_) {
            p++; // port occupied, try next
          }
        }
        throw Exception('No free ports available above $base');
      }

      final devices = <Map<String, dynamic>>[];
      int nextPort = 7778;

      for (final line in lines) {
        final serial = line.split('\t').first.trim();
        final state = line.split('\t').last.trim(); // "device" | "offline"

        if (state != 'device') {
          devices.add({'serial': serial, 'status': 'offline'});
          continue;
        }

        // Find a free local port before forwarding
        final port = await nextFreePort(nextPort);
        nextPort = port + 1; // next device starts above this one

        // Forward port
        Process.runSync(adb, ['-s', serial, 'forward', 'tcp:$port', 'tcp:7777']);
        final url = 'http://localhost:$port';

        // Ping — confirm mcpe2e is running
        String status = 'mcpe2e_not_running';
        String? screen;
        try {
          final client = http.Client();
          final resp = await client
              .get(Uri.parse('$url/ping'))
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) {
            status = 'ready';
            registry.register(serial, url);
            // Bonus: read active screen from app context
            try {
              final ctx = await client
                  .get(Uri.parse('$url/mcp/context'))
                  .timeout(const Duration(seconds: 2));
              final ctxJson = jsonDecode(ctx.body) as Map<String, dynamic>;
              screen = ctxJson['screen'] as String?;
            } catch (_) {}
          }
          client.close();
        } catch (_) {}

        devices.add({
          'serial': serial,
          'port': port,
          'url': url,
          'status': status,
          if (screen != null) 'screen': screen,
        });
      }

      // Auto-select first ready device if active is still 'default'
      if (registry.activeSerial == 'default') {
        final first = devices.firstWhere(
          (d) => d['status'] == 'ready',
          orElse: () => {},
        );
        if (first.isNotEmpty) registry.select(first['serial'] as String);
      }

      return t(jsonEncode({'devices': devices, 'active': registry.activeSerial}));
    }(),

    'select_device' => () async {
      final id = args['device_id'] as String? ?? '';
      if (id.isEmpty) return t('Error: device_id is required');
      final ok = registry.select(id);
      if (!ok) return t('Error: device "$id" not found. Call list_devices first.');
      return t(jsonEncode({
        'ok': true,
        'active_device': id,
        'url': registry.active.baseUrl,
      }));
    }(),

    _ => Future.error(Exception('Unknown tool: $name')),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// _compactTree — compact format for inspect_ui
//
// Transforms the flat widget tree JSON into actionable text for the LLM.
// Reduces ~90% of tokens compared to the verbose original JSON.
//
// Output structure:
//   Screen: <AppBar title> (<N> widgets)
//
//   INTERACTIVE:          ← buttons, fields, toggles, sliders, dropdowns
//     Type  label  →  tap_at(cx, cy)   [disabled] [overlay]
//
//   TEXT:                 ← visible non-interactive text
//     "value"
//
//   OVERLAY [depth: N]:   ← active dialogs and bottom sheets
//     AlertDialog  "title"
//     ElevatedButton "OK"  →  tap_at(cx, cy)  [overlay]
//
//   LOADING: none | CircularProgressIndicator
//
// The depth field is preserved ONLY for overlay widgets, where it indicates the
// dialog layer and helps the LLM distinguish dialog elements from screen elements.
// For normal widgets, depth is noise and is omitted.
// ─────────────────────────────────────────────────────────────────────────────

String _compactTree(String rawJson) {
  try {
    final data = jsonDecode(rawJson) as Map<String, dynamic>;
    final all =
        (data['widgets'] as List? ?? []).cast<Map<String, dynamic>>();

    if (all.isEmpty) return 'Screen: empty (0 widgets)';

    // ── Screen name: AppBar title → first Text at depth ≤ 3 → "unknown"
    final appBar = all.where((w) => w['type'] == 'AppBar').firstOrNull;
    String screen = appBar?['title'] as String? ?? '';
    if (screen.isEmpty) {
      final shallow = all.where((w) =>
          w['type'] == 'Text' &&
          (w['depth'] as int? ?? 99) <= 3 &&
          (w['value'] as String? ?? '').isNotEmpty);
      screen = shallow.isNotEmpty
          ? shallow.first['value'] as String
          : 'unknown';
    }

    // ── Separate: main, overlay, loading
    final main    = <Map<String, dynamic>>[];
    final overlay = <Map<String, dynamic>>[];
    final loading = <Map<String, dynamic>>[];

    for (final w in all) {
      if (w['type'] == 'AppBar') continue; // already in header
      if (w['loading'] as bool? ?? false) { loading.add(w); continue; }
      if (w['overlay'] as bool? ?? false) { overlay.add(w); continue; }
      main.add(w);
    }

    // ── Build output: flat, one line per widget
    final buf = StringBuffer();
    buf.writeln('Screen: $screen (${all.length} widgets)');

    for (final w in main) {
      buf.writeln(_compactLine(w));
    }

    if (overlay.isNotEmpty) {
      buf.writeln('---overlay---');
      for (final w in overlay) {
        buf.writeln(_compactLine(w));
      }
    }

    buf.write('---loading--- ');
    buf.writeln(loading.isEmpty
        ? 'none'
        : loading.map((w) => w['type'] as String).join(', '));

    return buf.toString().trimRight();
  } catch (_) {
    return rawJson;
  }
}

/// Formats a single widget as a compact one-liner.
///
/// Format: `  Type  label  →  tap_at(cx, cy)  [disabled]  [auto_focus]`
String _compactLine(Map<String, dynamic> w) {
  final type    = w['type'] as String;
  final enabled = w['enabled'] as bool? ?? true;
  final label   = _widgetLabel(w);
  final center  = _centerCoords(w);
  final key     = w['key'] as String?;

  final parts = StringBuffer('  $type');
  if (key != null && key.isNotEmpty) parts.write('  key:"$key"');
  if (label.isNotEmpty) parts.write('  $label');
  if (center != null)   parts.write('  →  tap_at$center');
  if (!enabled)         parts.write('  [disabled]');
  if (w['auto_focus'] as bool? ?? false) parts.write('  [auto_focus]');
  return parts.toString();
}

/// Returns a short human-readable label for the widget's content/state.
String _widgetLabel(Map<String, dynamic> w) {
  final type = w['type'] as String;
  switch (type) {
    case 'TextField':
    case 'TextFormField':
      final val  = w['value'] as String?;
      final hint = w['hint']  as String?;
      if (val != null && val.isNotEmpty) return 'value:"$val"';
      if (hint != null && hint.isNotEmpty) return 'hint:"$hint"';
      return '';
    case 'Checkbox':
    case 'Switch':
      return (w['value'] as bool? ?? false) ? '☑' : '☐';
    case 'Radio':
      return (w['selected'] as bool? ?? false) ? '◉' : '○';
    case 'Slider':
      return 'value=${w['value']}  [${w['min']}..${w['max']}]';
    case 'DropdownButtonFormField':
      final val = w['value'] as String?;
      return val != null && val.isNotEmpty ? '"$val"' : '';
    case 'Text':
      final val = w['value'] as String?;
      return val != null && val.isNotEmpty ? '"$val"' : '';
    case 'IconButton':
    case 'PopupMenuButton':
      final tip = w['tooltip'] as String?;
      return tip != null ? '[$tip]' : '';
    case 'AlertDialog':
      final title = w['title'] as String?;
      return title != null && title.isNotEmpty ? '"$title"' : '';
    case 'BottomSheet':
      return '';
    case 'SnackBar':
      final content = w['content'] as String?;
      return content != null && content.isNotEmpty ? '"$content"' : '';
    case 'Image':
      final sem = w['semanticLabel'] as String?;
      return sem != null && sem.isNotEmpty ? '[$sem]' : '';
    default:
      final label = w['label'] as String?;
      return label != null && label.isNotEmpty ? '"$label"' : '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numeric coercion helpers
//
// The LLM occasionally serialises numbers as JSON strings (e.g. "263.8").
// These helpers accept both num and String so every numeric arg is safe.
// ─────────────────────────────────────────────────────────────────────────────

/// Coerces a value from MCP args to [num].
/// Accepts both numeric values and string representations.
num _toNum(dynamic v) => v is num ? v : num.parse(v.toString());

/// Same but returns null when [v] is null.
num? _toNumOpt(dynamic v) => v == null ? null : _toNum(v);

/// Coerces to [int] (rounds if the value is a double or decimal string).
int _toInt(dynamic v) => _toNum(v).round();

/// Same but returns null when [v] is null.
int? _toIntOpt(dynamic v) => v == null ? null : _toInt(v);

/// Calculates the center of a widget from its x/y/w/h fields.
/// Returns `(cx, cy)` as a string, or null if coordinates are missing.
String? _centerCoords(Map<String, dynamic> w) {
  final x  = w['x']  as num?;
  final y  = w['y']  as num?;
  final ww = w['w']  as num?;
  final h  = w['h']  as num?;
  if (x == null || y == null || ww == null || h == null) return null;
  final cx = (x + ww / 2).toStringAsFixed(1);
  final cy = (y + h  / 2).toStringAsFixed(1);
  return '($cx, $cy)';
}
