// ─────────────────────────────────────────────────────────────────────────────
// McpWidgetRegistry
//
// Single source of truth for the testable widget registry.
// Maintains the mapping between the widget's semantic ID (e.g. "auth.login_button")
// and its internal GlobalKey, which allows obtaining the BuildContext and RenderBox
// at runtime to simulate gestures and read state.
//
// Does not execute gestures nor know about MCP events. Only manages the widget
// collection and delegates context retrieval to the Flutter widget tree.
//
// Flow:
//   App registers widget → Registry creates GlobalKey → Widget uses that key →
//   Flutter associates it with the mounted Element → Registry uses it to get context
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:logger_rs/logger_rs.dart';

import '../events/mcp_metadata_key.dart';

// ── Registry entry ───────────────────────────────────────────────────

/// Internal registry entry for a widget.
/// Combines semantic metadata with the physical Flutter GlobalKey.
typedef _WidgetEntry = ({McpMetadataKey metadata, GlobalKey globalKey});

// ── Registry ──────────────────────────────────────────────────────────────

/// Registry of testable widgets via MCP.
///
/// Every widget that wants to be controlled by Claude must register here
/// with an [McpMetadataKey] that defines its ID, type, and capabilities.
///
/// The registry creates an internal [GlobalKey] that must be assigned to the
/// widget in the Flutter tree so the executor can obtain its context.
class McpWidgetRegistry {
  McpWidgetRegistry._();

  static final McpWidgetRegistry instance = McpWidgetRegistry._();

  // Map of semantic ID → (metadata + GlobalKey)
  final Map<String, _WidgetEntry> _widgets = {};

  // ── Registration ────────────────────────────────────────────────────────────

  /// Registers a widget and creates its internal GlobalKey.
  ///
  /// Call this method before mounting the widget in the tree.
  /// The resulting key is obtained with [getGlobalKey] and assigned to the widget.
  ///
  /// If the ID already exists, it overwrites the previous registration.
  void registerWidget(McpMetadataKey key) {
    Log.i('[Registry] 📝 Registering: ${key.id} (${key.widgetType.name})');
    _widgets[key.id] = (
      metadata: key,
      globalKey: GlobalKey(debugLabel: 'MCP:${key.id}'),
    );
  }

  /// Removes a widget from the registry.
  ///
  /// Call in `dispose()` for dynamic widgets (e.g., list items).
  /// If not unregistered, the GlobalKey becomes orphaned but does not cause a crash.
  void unregisterWidget(String id) {
    Log.i('[Registry] 🗑️  Unregistering: $id');
    _widgets.remove(id);
  }

  // ── Lookup ──────────────────────────────────────────────────────────────

  /// Returns true if the widget with [id] is registered.
  bool isRegistered(String id) => _widgets.containsKey(id);

  /// Returns the internal GlobalKey to assign to the widget in the tree.
  ///
  /// Usage:
  /// ```dart
  /// ElevatedButton(
  ///   key: McpEvents.instance.getGlobalKey('auth.login_button'),
  ///   ...
  /// )
  /// ```
  GlobalKey? getGlobalKey(String id) => _widgets[id]?.globalKey;

  /// Returns the BuildContext of the mounted widget, or null if not on screen.
  ///
  /// The context only exists while the widget is mounted in the tree.
  /// If the widget was scrolled out of the viewport but is still mounted,
  /// the context exists but the widget may not be visible.
  ///
  /// Triple strategy:
  /// 1. Internal GlobalKey (original flow with getGlobalKey)
  /// 2. Element-tree walk searching for McpMetadataKey with that id (direct flow)
  /// 3. Element-tree walk searching for ValueKey<String> with matching value
  BuildContext? getContext(String id) {
    // Strategy 1: Internal GlobalKey
    final ctx = _widgets[id]?.globalKey.currentContext;
    if (ctx != null) return ctx;

    // Strategy 2 & 3: walk the tree searching for matching key
    BuildContext? found;
    void visit(Element el) {
      if (found != null) return;
      final key = el.widget.key;
      if (key is McpMetadataKey && key.id == id) {
        found = el;
        return;
      }
      if (key is ValueKey<String> && key.value == id) {
        found = el;
        return;
      }
      el.visitChildElements(visit);
    }
    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return found;
  }

  /// Returns the RenderBox of the widget, needed to calculate position and size.
  ///
  /// Triple strategy:
  /// 1. If the widget uses [getGlobalKey] as key → uses globalKey.currentContext
  /// 2. If the widget uses [McpMetadataKey] directly as key → walks the element tree
  /// 3. If the widget uses [ValueKey<String>] with matching value → walks the element tree
  RenderBox? getRenderBox(String id) {
    // Strategy 1: via getContext (covers GlobalKey, McpMetadataKey, and ValueKey)
    final context = getContext(id);
    if (context != null) {
      final rb = context.findRenderObject() as RenderBox?;
      if (rb != null) return rb;
    }

    // Strategy 2: deep search for first RenderBox in subtree
    RenderBox? found;

    void visitElement(Element el) {
      if (found != null) return;
      final key = el.widget.key;
      final matches = (key is McpMetadataKey && key.id == id) ||
          (key is ValueKey<String> && key.value == id);
      if (matches) {
        found = _firstRenderBox(el);
        return;
      }
      el.visitChildElements(visitElement);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visitElement);
    return found;
  }

  /// Returns the first [RenderBox] in the subtree of [el].
  RenderBox? _firstRenderBox(Element el) {
    final ro = el.renderObject;
    if (ro is RenderBox) return ro;
    RenderBox? found;
    el.visitChildElements((child) {
      if (found != null) return;
      found = _firstRenderBox(child);
    });
    return found;
  }

  /// Returns the metadata of a specific widget.
  McpMetadataKey? getWidgetMetadata(String id) => _widgets[id]?.metadata;

  // ── Queries ────────────────────────────────────────────────────────────

  /// Lists all registered widget IDs.
  List<String> getAllWidgetIds() => _widgets.keys.toList();

  /// Lists all registered widget metadata.
  ///
  /// Used by the HTTP server for the /mcp/context and /widgets endpoints.
  List<McpMetadataKey> getAllWidgets() =>
      _widgets.values.map((e) => e.metadata).toList();

  /// Returns the registry entries for iteration in the executor.
  Iterable<MapEntry<String, ({McpMetadataKey metadata, GlobalKey globalKey})>>
  get entries => _widgets.entries;

  // ── Serialization ────────────────────────────────────────────────────────

  /// Generates the context JSON consumed by the external MCP server.
  ///
  /// Formato:
  /// ```json
  /// {
  ///   "screen": "LoginScreen",
  ///   "route": "/login",
  ///   "timestamp": "...",
  ///   "widgets": [{ "key": "auth.login_button", "type": "ElevatedButton", ... }]
  /// }
  /// ```
  ///
  /// If [screen] is null, attempts to infer it from the first widget that has a defined screen.
  Map<String, dynamic> toJson({String? screen, String? route}) {
    final detectedScreen = screen ?? _detectCurrentScreen();
    return {
      'screen': detectedScreen,
      'route': route ?? '/${detectedScreen.toLowerCase()}',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'widgets': _widgets.values.map((e) => e.metadata.toJson()).toList(),
    };
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Infers the screen name from the registered widgets.
  /// Takes the screen from the first widget that has one defined.
  String _detectCurrentScreen() {
    for (final entry in _widgets.values) {
      if (entry.metadata.screen != null) return entry.metadata.screen!;
    }
    return 'UnknownScreen';
  }
}
