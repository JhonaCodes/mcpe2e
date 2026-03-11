// ─────────────────────────────────────────────────────────────────────────────
// McpEvents — Public facade for the E2E system
//
// Single entry point for the app to register widgets and for the HTTP
// server to execute events. Internally coordinates the registry, gesture
// simulator, and executor without external code needing to know about them.
//
// Internal architecture:
//
//   McpEvents (facade)
//     ├── McpWidgetRegistry   → maintains the id → (metadata, GlobalKey) map
//     ├── McpGestureSimulator → generates PointerEvents for GestureBinding
//     └── McpEventExecutor    → dispatches events to concrete implementations
//
// Full flow from the app to Claude:
//
//   App registers widget →  McpEvents.registerWidget(key)
//                               McpWidgetRegistry stores key + GlobalKey
//   Widget uses GlobalKey → key: McpEvents.instance.getGlobalKey('auth.login')
//                               Flutter associates the Element with the GlobalKey
//
//   Claude invokes tool   → mcpe2e_server receives JSON-RPC
//                               mcpe2e_server makes HTTP GET/POST
//                               McpEventServer receives HTTP request
//                               McpEventServer calls McpEvents.executeEvent()
//                               McpEventExecutor obtains context from Registry
//                               McpEventExecutor executes the gesture
//                               GestureBinding routes to the correct widget
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import '../core/mcp_widget_registry.dart';
import '../core/mcp_gesture_simulator.dart';
import '../core/mcp_event_executor.dart';
import 'mcp_event_type.dart';
import 'mcp_metadata_key.dart';

// ── Facade ────────────────────────────────────────────────────────────────────

/// Public entry point for the mcpe2e system.
///
/// Exposes system operations as a simple API without requiring the caller
/// to know about the Registry, Simulator, or Executor internally.
///
/// Typical usage in the app:
/// ```dart
/// // 1. Register widgets before mounting them
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
/// // 3. Start the server (in main() or in a debug initState)
/// if (kDebugMode) await McpEventServer.start();
/// ```
class McpEvents {
  McpEvents._();

  static final McpEvents instance = McpEvents._();

  // ── Internal components ──────────────────────────────────────────────────

  final _registry = McpWidgetRegistry.instance;
  final _simulator = McpGestureSimulator.instance;
  late final _executor = McpEventExecutor(_registry, _simulator);

  // ── Widget registration ──────────────────────────────────────────────────

  /// Registers a testable widget and creates its internal GlobalKey.
  ///
  /// Call before mounting the widget in the tree.
  /// The key is retrieved afterwards with [getGlobalKey].
  void registerWidget(McpMetadataKey key) => _registry.registerWidget(key);

  /// Removes a widget from the registry.
  ///
  /// Call in `dispose()` for dynamic widgets that are destroyed.
  void unregisterWidget(String id) => _registry.unregisterWidget(id);

  /// Returns true if the widget with [id] is registered.
  bool isRegistered(String id) => _registry.isRegistered(id);

  /// Returns the GlobalKey to assign to the widget in the tree.
  ///
  /// The key allows the executor to obtain the BuildContext and RenderBox
  /// of the widget when executing events on it.
  GlobalKey? getGlobalKey(String id) => _registry.getGlobalKey(id);

  /// Returns the BuildContext of the widget if it is mounted.
  BuildContext? getContext(String id) => _registry.getContext(id);

  /// Returns the registered metadata for a widget.
  McpMetadataKey? getWidgetMetadata(String id) =>
      _registry.getWidgetMetadata(id);

  // ── Queries ──────────────────────────────────────────────────────────────

  /// Lists the IDs of all registered widgets.
  List<String> getAllWidgetIds() => _registry.getAllWidgetIds();

  /// Lists the metadata of all registered widgets.
  List<McpMetadataKey> getAllWidgets() => _registry.getAllWidgets();

  // ── Serialization ────────────────────────────────────────────────────────

  /// Generates the context JSON consumed by the external MCP server.
  ///
  /// Contains screen, route, timestamp, and the list of widgets with capabilities.
  /// This JSON is what Claude sees when it calls `get_app_context`.
  Map<String, dynamic> toJson({String? screen, String? route}) =>
      _registry.toJson(screen: screen, route: route);

  // ── Event execution ──────────────────────────────────────────────────────

  /// Executes the [eventType] on the widget identified by [widgetKey].
  ///
  /// Returns true if the event succeeded, false if it failed.
  /// For assertions, returns true = assertion passed.
  ///
  /// See [McpEventType] for the full list of available events.
  Future<bool> executeEvent({
    required String widgetKey,
    required McpEventType eventType,
    McpEventParams? params,
  }) => _executor.executeEvent(
    widgetKey: widgetKey,
    eventType: eventType,
    params: params,
  );
}
