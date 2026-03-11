/// mcpe2e — Flutter E2E Testing Library for MCP
///
/// Library that runs inside the Flutter app and exposes an HTTP server
/// so that Claude (via mcpe2e_server) can control real widgets:
/// taps, inputs, swipes, assertions, and more.
///
/// ## Architecture
///
/// ```
/// Claude → mcpe2e_server (MCP) → HTTP → McpEventServer (esta lib) →
///          McpEvents → McpEventExecutor → widgets reales en la app
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:mcpe2e/mcpe2e.dart';
/// import 'package:flutter/foundation.dart';
///
/// // 1. Register widgets (before mounting them)
/// McpEvents.instance.registerWidget(const McpMetadataKey(
///   id: 'auth.login_button',
///   widgetType: McpWidgetType.button,
///   description: 'Main login button',
///   screen: 'LoginScreen',
/// ));
///
/// // 2. Use the key in the widget
/// ElevatedButton(
///   key: McpEvents.instance.getGlobalKey('auth.login_button'),
///   onPressed: _handleLogin,
///   child: const Text('Sign in'),
/// )
///
/// // 3. Start the HTTP server only in debug
/// if (kDebugMode) await McpEventServer.start();
/// ```
///
/// ## ID Convention
///
/// IDs follow the pattern: `module.element[.variant]`
/// ```
/// auth.login_button       → login button
/// auth.email_field        → email field
/// order.form.price        → price field inside form
/// screen.dashboard        → screen identifier (for assertions)
/// state.loading_indicator → loading indicator (for assert_visible)
/// ```
library;

// ── Event model ───────────────────────────────────────────────────────────────
// Event types (tap, swipe, toggle, assertVisible, etc.) and their parameters.
export 'events/mcp_event_type.dart';

// ── Widget metadata ───────────────────────────────────────────────────────────
// McpMetadataKey (the key you assign to the widget) and McpWidgetType (type enum).
export 'events/mcp_metadata_key.dart';

// ── Public facade ─────────────────────────────────────────────────────────────
// McpEvents: entry point for registering widgets and executing events.
export 'events/mcp_events_core.dart';

// ── Platform connectivity ─────────────────────────────────────────────────────
// McpConnectivity: detects platform and configures ADB forward / iproxy / desktop.
export 'platform/mcp_connectivity.dart';

// ── HTTP server ───────────────────────────────────────────────────────────────
// McpEventServer: exposes the HTTP endpoints consumed by mcpe2e_server.
export 'server/mcp_event_server.dart';

// ── UI inspection ─────────────────────────────────────────────────────────────
// McpTreeInspector: walks the widget tree and extracts data non-intrusively.
// McpScreenCapture: captures the screen via internal layer tree (debug/profile).
export 'core/mcp_tree_inspector.dart';
export 'core/mcp_screen_capture.dart';

// ── Navigation observer ───────────────────────────────────────────────────────
// McpNavigatorObserver: captures the active route for get_app_context.
// Register in MaterialApp(navigatorObservers:) or GoRouter(observers:).
export 'core/mcp_navigator_observer.dart';
