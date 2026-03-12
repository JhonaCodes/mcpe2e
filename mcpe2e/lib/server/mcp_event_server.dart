// ─────────────────────────────────────────────────────────────────────────────
// McpEventServer
//
// HTTP server embedded in the Flutter app. It is the network interface between
// the external MCP server (mcpe2e_server) and the event execution system.
//
// Responsibility: only route HTTP requests to McpEvents.
// Does not execute gestures, does not handle platform connectivity, does not know MCP.
//
// Endpoints:
//
//   GET  /ping                  Health check — confirms the server is alive
//   GET  /mcp/context           Full context: screen + all widgets
//   GET  /action?key=...        Executes event with URL parameters
//   POST /event                 Executes event with JSON body
//   GET  /widgets               Lists registered widgets
//
// Platform connectivity (configured by McpConnectivity, not here):
//
//   Android  → ADB forward localhost:7778 → device:7777
//   iOS      → iproxy localhost:7778 → device:7777
//   Desktop  → localhost:7777 direct (no forwarding)
//   Web      → not supported
//
// Usage:
//   await McpEventServer.start();   // call once in main()
//   // server stops automatically when the app closes
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logger_rs/logger_rs.dart';

import '../core/mcp_navigator_observer.dart';
import '../core/mcp_screen_capture.dart';
import '../core/mcp_tree_inspector.dart';
import '../events/mcp_events_core.dart';
import '../events/mcp_event_type.dart';
import '../platform/mcp_connectivity.dart';

// ── Lifecycle observer ────────────────────────────────────────────────────────

/// Observes the app lifecycle and stops the HTTP server when the app closes.
class _McpLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      McpEventServer.stop();
    }
  }
}

// ── Server ────────────────────────────────────────────────────────────────────

/// HTTP server that exposes the E2E testing API to the external MCP server.
///
/// Runs inside the app in debug/profile mode. Listens on :7777 by default.
/// Automatically stops when the app is closed (AppLifecycleState.detached).
/// McpConnectivity configures platform forwarding on startup.
class McpEventServer {
  static HttpServer? _server;
  static bool _isRunning = false;
  static final _observer = _McpLifecycleObserver();

  /// Port where the HTTP server listens inside the app (default 7777).
  static int port = 7777;

  /// Bind host. 0.0.0.0 allows access from ADB forward and iproxy.
  static String host = '0.0.0.0';

  /// Local port on the dev's PC for forwarding (default port + 1).
  static int forwardPort = 7778;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Starts the HTTP server and configures platform connectivity.
  ///
  /// If already running, does nothing.
  /// Logs available endpoints and how to configure TESTBRIDGE_URL.
  static Future<void> start({
    int? customPort,
    String? customHost,
    int? customForwardPort,
  }) async {
    Log.init(level: Level.SEVERE);

    // Production guard: the server must not run in release builds.
    // In release, inspection mechanisms (debugLayer, visitChildElements
    // for debug info) are not available or return incomplete data.
    if (!kDebugMode && !kProfileMode) {
      Log.i(
        '[Server] ⚠️  McpEventServer must not run in production. Aborting.',
      );
      return;
    }

    if (_isRunning) {
      Log.i('[Server] Already running at http://$host:$port');
      return;
    }

    if (customPort != null) port = customPort;
    if (customHost != null) host = customHost;
    if (customForwardPort != null) forwardPort = customForwardPort;

    try {
      _server = await HttpServer.bind(host, port, shared: true);
      _isRunning = true;

      // Register lifecycle observer — auto-stops when the app closes
      WidgetsBinding.instance.addObserver(_observer);

      // Configure platform connectivity (ADB forward, iproxy, etc.)
      final connectivity = await McpConnectivity.setup(
        appPort: port,
        forwardPort: forwardPort,
      );

      _logStartup(connectivity);

      _server!.listen(
        _handleRequest,
        onError: (e) {
          Log.i('[Server] Error: $e');
        },
      );
    } catch (e) {
      Log.i('[Server] ❌ Failed to start: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// Stops the HTTP server and removes the lifecycle observer.
  static Future<void> stop() async {
    if (!_isRunning || _server == null) return;
    WidgetsBinding.instance.removeObserver(_observer);
    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
    Log.i('[Server] 🛑 Stopped');
  }

  // ── Routing ───────────────────────────────────────────────────────────────

  /// Routes each request to the corresponding handler.
  static Future<void> _handleRequest(HttpRequest request) async {
    Log.i('[Server] ${request.method} ${request.uri.path}');
    try {
      switch (request.uri.path) {
        case '/ping':
          _handlePing(request);
        case '/mcp/context':
          _handleMcpContext(request);
        case '/mcp/tree':
          _handleTree(request);
        case '/mcp/screenshot':
          await _handleScreenshot(request);
        case '/action':
          await _handleAction(request);
        case '/event':
          await _handleEvent(request);
        case '/widgets':
          _handleWidgets(request);
        default:
          _send(request, 404, 'text/plain', 'Endpoint not found');
      }
    } catch (e) {
      Log.i('[Server] Error processing request: $e');
      _send(request, 500, 'text/plain', 'Internal error: $e');
    }
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  /// GET /ping — Basic health check.
  ///
  /// The external MCP server calls this endpoint to verify that the app
  /// is alive before executing commands.
  /// Responds: {"status":"ok","port":7777}
  static void _handlePing(HttpRequest req) {
    _sendJson(req, {'status': 'ok', 'port': port});
  }

  /// GET /mcp/context — Full app context.
  ///
  /// Returns all registered widgets with their metadata and capabilities.
  /// Claude calls this endpoint first to know what is on screen.
  ///
  /// Response:
  /// ```json
  /// {
  ///   "screen": "LoginScreen",
  ///   "route": "/login",
  ///   "timestamp": "...",
  ///   "widgets": [
  ///     { "key": "auth.email_field", "type": "TextField", "capabilities": [...] }
  ///   ]
  /// }
  /// ```
  static void _handleMcpContext(HttpRequest req) {
    _sendJson(
      req,
      McpEvents.instance.toJson(
        route: McpNavigatorObserver.instance.currentRoute,
      ),
    );
  }

  /// GET /mcp/tree — Widget tree with data from the current screen.
  ///
  /// Walks the full widget tree from the root and returns all widgets
  /// with relevant data: texts, field values, button states,
  /// checkboxes, switches, sliders, etc.
  ///
  /// Does not require widgets to be registered in McpWidgetRegistry.
  /// Works with any widget in the app.
  ///
  /// Response:
  /// ```json
  /// {
  ///   "timestamp": "...",
  ///   "widget_count": 18,
  ///   "widgets": [
  ///     { "type": "Text", "value": "Total: $0.00", "depth": 6,
  ///       "x": 16.0, "y": 400.0, "w": 150.0, "h": 20.0 },
  ///     { "type": "TextField", "value": "user@test.com",
  ///       "hint": "Email", "enabled": true, "depth": 5,
  ///       "key": "auth.email_field" }
  ///   ]
  /// }
  /// ```
  static void _handleTree(HttpRequest req) {
    _sendJson(req, McpTreeInspector.inspect());
  }

  /// GET /mcp/screenshot — Captures the screen as PNG in base64.
  ///
  /// Uses Flutter's internal layer tree: zero extra widgets in the tree.
  /// Only available in debug/profile; returns error in release.
  ///
  /// Response (success):
  /// ```json
  /// {
  ///   "format": "png",
  ///   "width": 393,
  ///   "height": 852,
  ///   "pixel_ratio": 3.0,
  ///   "base64": "iVBORw0KGgoAAAANSUhEUgAA..."
  /// }
  /// ```
  ///
  /// Response (release mode):
  /// ```json
  /// { "error": "not_available_in_release" }
  /// ```
  static Future<void> _handleScreenshot(HttpRequest req) async {
    _sendJson(req, await McpScreenCapture.capture());
  }

  /// GET /action?key=...&type=...&[params] — Executes event with URL params.
  ///
  /// Required parameters:
  ///   key   — widget ID (e.g. "auth.login_button")
  ///   type  — event type (default "tap")
  ///
  /// Optional parameters (depending on event type):
  ///   text, duration, distance, direction, deltaX, deltaY, clearFirst,
  ///   expectedText, scale, dropdownValue, dropdownIndex, sliderValue,
  ///   targetKey, maxScrollAttempts, label, expectedCount
  ///
  /// Examples:
  ///   GET /action?key=auth.login_button
  ///   GET /action?key=auth.email_field&type=textinput&text=user@test.com
  ///   GET /action?key=filter.active&type=toggle
  ///   GET /action?key=price_slider&type=setslidervalue&sliderValue=0.5
  static Future<void> _handleAction(HttpRequest req) async {
    final params = req.uri.queryParameters;
    final key = params['key'];

    if (key == null) {
      _send(req, 400, 'text/plain', 'Parameter "key" required');
      return;
    }

    final typeStr = params['type'] ?? 'tap';
    final eventType = _parseEventType(typeStr);
    if (eventType == null) {
      _send(req, 400, 'text/plain', 'Invalid event type: $typeStr');
      return;
    }

    final eventParams = params.length > 1 ? _parseUrlParams(params) : null;

    final success = await McpEvents.instance.executeEvent(
      widgetKey: key,
      eventType: eventType,
      params: eventParams,
    );

    _send(
      req,
      200,
      'text/plain',
      success ? 'OK: $typeStr on "$key"' : 'Error: $typeStr on "$key" failed',
    );
  }

  /// POST /event — Executes event with JSON body.
  ///
  /// Expected body:
  /// ```json
  /// {
  ///   "key": "auth.login_button",
  ///   "type": "tap",
  ///   "params": { "text": "hello", "clearFirst": true }
  /// }
  /// ```
  ///
  /// Responds:
  /// ```json
  /// { "success": true, "widgetKey": "...", "eventType": "tap" }
  /// ```
  static Future<void> _handleEvent(HttpRequest req) async {
    if (req.method != 'POST') {
      _send(req, 405, 'text/plain', 'Method not allowed. Use POST.');
      return;
    }

    final body = await utf8.decoder.bind(req).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final key = json['key'] as String?;
    final typeStr = json['type'] as String?;
    if (key == null || typeStr == null) {
      _send(req, 400, 'text/plain', 'Body requires "key" and "type"');
      return;
    }

    final eventType = _parseEventType(typeStr);
    if (eventType == null) {
      _send(req, 400, 'text/plain', 'Invalid type: $typeStr');
      return;
    }

    final params = json['params'] != null
        ? McpEventParams.fromJson(json['params'] as Map<String, dynamic>)
        : null;

    final success = await McpEvents.instance.executeEvent(
      widgetKey: key,
      eventType: eventType,
      params: params,
    );

    _sendJson(req, {
      'success': success,
      'widgetKey': key,
      'eventType': typeStr,
    });
  }

  /// GET /widgets — Lists registered widgets.
  ///
  /// Without parameters: returns only IDs.
  /// With ?metadata=true: returns full context (same as /mcp/context).
  static void _handleWidgets(HttpRequest req) {
    final full = req.uri.queryParameters['metadata'] == 'true';
    if (full) {
      _sendJson(req, McpEvents.instance.toJson());
    } else {
      _sendJson(req, {'widgets': McpEvents.instance.getAllWidgetIds()});
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Converts the event type string to [McpEventType].
  ///
  /// Accepts both camelCase and snake_case.
  static McpEventType? _parseEventType(String type) {
    return switch (type.toLowerCase()) {
      'tap' => McpEventType.tap,
      'doubletap' || 'double_tap' => McpEventType.doubleTap,
      'longpress' || 'long_press' => McpEventType.longPress,
      'swipe' => McpEventType.swipe,
      'drag' => McpEventType.drag,
      'scroll' => McpEventType.scroll,
      'pinch' => McpEventType.pinch,
      'textinput' || 'text_input' => McpEventType.textInput,
      'cleartext' || 'clear_text' => McpEventType.clearText,
      'selectdropdown' || 'select_dropdown' => McpEventType.selectDropdown,
      'toggle' => McpEventType.toggle,
      'setslidervalue' || 'set_slider_value' => McpEventType.setSliderValue,
      'hidekeyboard' || 'hide_keyboard' => McpEventType.hideKeyboard,
      'showkeyboard' || 'show_keyboard' => McpEventType.showKeyboard,
      'pressback' || 'press_back' => McpEventType.pressBack,
      'scrolluntilvisible' ||
      'scroll_until_visible' => McpEventType.scrollUntilVisible,
      'tapbylabel' || 'tap_by_label' => McpEventType.tapByLabel,
      'tapat' || 'tap_at' => McpEventType.tapAt,
      'wait' => McpEventType.wait,
      'assertexists' || 'assert_exists' => McpEventType.assertExists,
      'asserttext' || 'assert_text' => McpEventType.assertText,
      'assertvisible' || 'assert_visible' => McpEventType.assertVisible,
      'assertenabled' || 'assert_enabled' => McpEventType.assertEnabled,
      'assertselected' || 'assert_selected' => McpEventType.assertSelected,
      'assertvalue' || 'assert_value' => McpEventType.assertValue,
      'assertcount' || 'assert_count' => McpEventType.assertCount,
      _ => null,
    };
  }

  /// Converts URL query parameters to [McpEventParams].
  static McpEventParams _parseUrlParams(Map<String, String> p) {
    return McpEventParams(
      text: p['text'],
      duration: p['duration'] != null
          ? Duration(milliseconds: int.parse(p['duration']!))
          : null,
      distance: p['distance'] != null ? double.parse(p['distance']!) : null,
      direction: p['direction'],
      deltaX: p['deltaX'] != null ? double.parse(p['deltaX']!) : null,
      deltaY: p['deltaY'] != null ? double.parse(p['deltaY']!) : null,
      clearFirst: p['clearFirst'] == 'true',
      expectedText: p['expectedText'],
      scale: p['scale'] != null ? double.parse(p['scale']!) : null,
      dropdownValue: p['dropdownValue'],
      dropdownIndex: p['dropdownIndex'] != null
          ? int.parse(p['dropdownIndex']!)
          : null,
      sliderValue: p['sliderValue'] != null
          ? double.parse(p['sliderValue']!)
          : null,
      targetKey: p['targetKey'],
      maxScrollAttempts: p['maxScrollAttempts'] != null
          ? int.parse(p['maxScrollAttempts']!)
          : null,
      label: p['label'],
      expectedCount: p['expectedCount'] != null
          ? int.parse(p['expectedCount']!)
          : null,
      dx: p['dx'] != null ? double.parse(p['dx']!) : null,
      dy: p['dy'] != null ? double.parse(p['dy']!) : null,
    );
  }

  // ── Response helpers ─────────────────────────────────────────────────────

  static void _sendJson(HttpRequest req, Map<String, dynamic> body) {
    _send(req, 200, 'application/json', jsonEncode(body));
  }

  static void _send(
    HttpRequest req,
    int status,
    String contentType,
    String body,
  ) {
    final bytes = utf8.encode(body); // always UTF-8, never Latin-1
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.parse('$contentType; charset=utf-8')
      ..headers.contentLength = bytes.length
      ..add(bytes);
    req.response.close();
  }

  // ── Startup log ───────────────────────────────────────────────────────────

  static void _logStartup(McpConnectivityInfo info) {
    Log.d('');
    Log.d('╔══════════════════════════════════════════════════╗');
    Log.d('║           mcpe2e HTTP Server started            ║');
    Log.d('╠══════════════════════════════════════════════════╣');
    Log.d('║ Platform : ${info.platform.padRight(35)}║');
    Log.d(
      '║ App URL    : http://$host:$port${' ' * (27 - '$host:$port'.length)}║',
    );
    Log.d('╠══════════════════════════════════════════════════╣');
    Log.d('║ Endpoints:                           ║');
    Log.d('║   GET  /ping                                     ║');
    Log.d('║   GET  /mcp/context                              ║');
    Log.d('║   GET  /mcp/tree                                 ║');
    Log.d('║   GET  /mcp/screenshot                           ║');
    Log.d('║   GET  /action?key=...&type=...                  ║');
    Log.d('║   POST /event                                    ║');
    Log.d('║   GET  /widgets                                  ║');
    Log.d('╠══════════════════════════════════════════════════╣');
    if (info.connectCommand.isNotEmpty) {
      Log.d('║ On your PC, run:                                  ║');
      Log.d('║   ${info.connectCommand.padRight(48)}║');
    }
    Log.d('║ Then start mcpe2e_server with:                   ║');
    Log.d(
      '║   TESTBRIDGE_URL=${info.mcpServerUrl}${' ' * (32 - info.mcpServerUrl.length)}║',
    );
    Log.d('╚══════════════════════════════════════════════════╝');
    Log.d('');
  }
}
