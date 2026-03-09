// ─────────────────────────────────────────────────────────────────────────────
// McpWidgetRegistry
//
// Única fuente de verdad del registro de widgets testables.
// Mantiene el mapa entre el ID semántico del widget (e.g. "auth.login_button")
// y su GlobalKey interna, que permite obtener el BuildContext y RenderBox en
// tiempo de ejecución para simular gestos y leer estado.
//
// No ejecuta gestos ni conoce eventos MCP. Solo administra la colección de
// widgets y delega la obtención de contexto al árbol de widgets de Flutter.
//
// Flujo:
//   App registra widget → Registry crea GlobalKey → Widget usa esa key →
//   Flutter la asocia al Element montado → Registry la usa para obtener context
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:logger_rs/logger_rs.dart';

import '../events/mcp_metadata_key.dart';

// ── Entrada del registro ───────────────────────────────────────────────────

/// Entrada interna del registro para un widget.
/// Combina la metadata semántica con la GlobalKey física de Flutter.
typedef _WidgetEntry = ({McpMetadataKey metadata, GlobalKey globalKey});

// ── Registry ──────────────────────────────────────────────────────────────

/// Registro de widgets testables via MCP.
///
/// Cada widget que quiera ser controlado por Claude debe registrarse aquí
/// con un [McpMetadataKey] que define su ID, tipo y capabilities.
///
/// El registro crea una [GlobalKey] interna que debe asignarse al widget
/// en el árbol de Flutter para que el executor pueda obtener su context.
class McpWidgetRegistry {
  McpWidgetRegistry._();

  static final McpWidgetRegistry instance = McpWidgetRegistry._();

  // Mapa de ID semántico → (metadata + GlobalKey)
  final Map<String, _WidgetEntry> _widgets = {};

  // ── Registro ────────────────────────────────────────────────────────────

  /// Registra un widget y crea su GlobalKey interna.
  ///
  /// Llama a este método antes de montar el widget en el árbol.
  /// La key resultante se obtiene con [getGlobalKey] y se asigna al widget.
  ///
  /// Si el ID ya existe, sobrescribe el registro anterior.
  void registerWidget(McpMetadataKey key) {
    Log.i('[Registry] 📝 Registrando: ${key.id} (${key.widgetType.name})');
    _widgets[key.id] = (
      metadata: key,
      globalKey: GlobalKey(debugLabel: 'MCP:${key.id}'),
    );
  }

  /// Elimina un widget del registro.
  ///
  /// Llama en `dispose()` para widgets dinámicos (ej: items de lista).
  /// Si no se desregistra, la GlobalKey queda huérfana pero no causa crash.
  void unregisterWidget(String id) {
    Log.i('[Registry] 🗑️  Desregistrando: $id');
    _widgets.remove(id);
  }

  // ── Lookup ──────────────────────────────────────────────────────────────

  /// Retorna true si el widget con [id] está registrado.
  bool isRegistered(String id) => _widgets.containsKey(id);

  /// Retorna la GlobalKey interna para asignar al widget en el árbol.
  ///
  /// Uso:
  /// ```dart
  /// ElevatedButton(
  ///   key: McpEvents.instance.getGlobalKey('auth.login_button'),
  ///   ...
  /// )
  /// ```
  GlobalKey? getGlobalKey(String id) => _widgets[id]?.globalKey;

  /// Retorna el BuildContext del widget montado, o null si no está en pantalla.
  ///
  /// El contexto solo existe mientras el widget esté montado en el árbol.
  /// Si el widget fue desplazado fuera del viewport pero sigue montado,
  /// el contexto existe pero el widget puede no ser visible.
  BuildContext? getContext(String id) => _widgets[id]?.globalKey.currentContext;

  /// Retorna el RenderBox del widget, necesario para calcular posición y tamaño.
  ///
  /// Estrategia dual:
  /// 1. Si el widget usa [getGlobalKey] como key → usa globalKey.currentContext
  /// 2. Si el widget usa [McpMetadataKey] directo como key → camina el element
  ///    tree buscando el primer elemento cuyo widget.key tenga el mismo id,
  ///    luego retorna su primer RenderBox descendiente.
  RenderBox? getRenderBox(String id) {
    // Estrategia 1: GlobalKey interna (flujo original)
    final context = getContext(id);
    if (context != null) {
      final rb = context.findRenderObject() as RenderBox?;
      if (rb != null) return rb;
    }

    // Estrategia 2: McpMetadataKey usado directamente en el árbol
    RenderBox? found;

    void visitElement(Element el) {
      if (found != null) return;
      final key = el.widget.key;
      if (key is McpMetadataKey && key.id == id) {
        found = _firstRenderBox(el);
        return;
      }
      el.visitChildElements(visitElement);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visitElement);
    return found;
  }

  /// Retorna el primer [RenderBox] en el subárbol de [el].
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

  /// Retorna la metadata de un widget específico.
  McpMetadataKey? getWidgetMetadata(String id) => _widgets[id]?.metadata;

  // ── Consultas ────────────────────────────────────────────────────────────

  /// Lista todos los IDs de widgets registrados.
  List<String> getAllWidgetIds() => _widgets.keys.toList();

  /// Lista toda la metadata de widgets registrados.
  ///
  /// Usado por el HTTP server para el endpoint /mcp/context y /widgets.
  List<McpMetadataKey> getAllWidgets() =>
      _widgets.values.map((e) => e.metadata).toList();

  /// Retorna los entries del registro para iteración en el executor.
  Iterable<MapEntry<String, ({McpMetadataKey metadata, GlobalKey globalKey})>>
  get entries => _widgets.entries;

  // ── Serialización ────────────────────────────────────────────────────────

  /// Genera el JSON de contexto consumido por el servidor MCP externo.
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
  /// Si [screen] es null, intenta inferirlo del primer widget que tenga screen definido.
  Map<String, dynamic> toJson({String? screen, String? route}) {
    final detectedScreen = screen ?? _detectCurrentScreen();
    return {
      'screen': detectedScreen,
      'route': route ?? '/${detectedScreen.toLowerCase()}',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'widgets': _widgets.values.map((e) => e.metadata.toJson()).toList(),
    };
  }

  // ── Internos ─────────────────────────────────────────────────────────────

  /// Infiere el nombre del screen desde los widgets registrados.
  /// Toma el screen del primer widget que tenga uno definido.
  String _detectCurrentScreen() {
    for (final entry in _widgets.values) {
      if (entry.metadata.screen != null) return entry.metadata.screen!;
    }
    return 'UnknownScreen';
  }
}
