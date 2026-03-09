// ─────────────────────────────────────────────────────────────────────────────
// McpEvents — Fachada pública del sistema E2E
//
// Punto de entrada único para que la app registre widgets y para que el HTTP
// server ejecute eventos. Coordina internamente el registry, el simulador de
// gestos y el executor sin que el código externo necesite conocerlos.
//
// Arquitectura interna:
//
//   McpEvents (fachada)
//     ├── McpWidgetRegistry   → mantiene el mapa id → (metadata, GlobalKey)
//     ├── McpGestureSimulator → genera PointerEvents para GestureBinding
//     └── McpEventExecutor    → despacha eventos a implementaciones concretas
//
// Flujo completo desde la app hasta Claude:
//
//   App registra widget  →  McpEvents.registerWidget(key)
//                               McpWidgetRegistry guarda key + GlobalKey
//   Widget usa GlobalKey →  key: McpEvents.instance.getGlobalKey('auth.login')
//                               Flutter asocia el Element al GlobalKey
//
//   Claude invoca tool   →  mcpe2e_server recibe JSON-RPC
//                               mcpe2e_server hace HTTP GET/POST
//                               McpEventServer recibe request HTTP
//                               McpEventServer llama McpEvents.executeEvent()
//                               McpEventExecutor obtiene context del Registry
//                               McpEventExecutor ejecuta el gesto
//                               GestureBinding enruta al widget correcto
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import '../core/mcp_widget_registry.dart';
import '../core/mcp_gesture_simulator.dart';
import '../core/mcp_event_executor.dart';
import 'mcp_event_type.dart';
import 'mcp_metadata_key.dart';

// ── Fachada ───────────────────────────────────────────────────────────────────

/// Punto de entrada público del sistema mcpe2e.
///
/// Expone las operaciones del sistema como API simple sin que el llamador
/// necesite conocer el Registry, Simulator o Executor internamente.
///
/// Uso típico en la app:
/// ```dart
/// // 1. Registrar widgets antes de montarlos
/// McpEvents.instance.registerWidget(const McpMetadataKey(
///   id: 'auth.login_button',
///   widgetType: McpWidgetType.button,
///   description: 'Botón principal de login',
///   screen: 'LoginScreen',
/// ));
///
/// // 2. Usar la key en el widget
/// ElevatedButton(
///   key: McpEvents.instance.getGlobalKey('auth.login_button'),
///   onPressed: _handleLogin,
///   child: const Text('Ingresar'),
/// )
///
/// // 3. Iniciar el servidor (en main() o en un initState de debug)
/// if (kDebugMode) await McpEventServer.start();
/// ```
class McpEvents {
  McpEvents._();

  static final McpEvents instance = McpEvents._();

  // ── Componentes internos ──────────────────────────────────────────────────

  final _registry = McpWidgetRegistry.instance;
  final _simulator = McpGestureSimulator.instance;
  late final _executor = McpEventExecutor(_registry, _simulator);

  // ── Registro de widgets ───────────────────────────────────────────────────

  /// Registra un widget testable y crea su GlobalKey interna.
  ///
  /// Llamar antes de montar el widget en el árbol.
  /// La key se obtiene después con [getGlobalKey].
  void registerWidget(McpMetadataKey key) => _registry.registerWidget(key);

  /// Elimina un widget del registro.
  ///
  /// Llamar en `dispose()` para widgets dinámicos que se destruyen.
  void unregisterWidget(String id) => _registry.unregisterWidget(id);

  /// Retorna true si el widget con [id] está registrado.
  bool isRegistered(String id) => _registry.isRegistered(id);

  /// Retorna la GlobalKey para asignar al widget en el árbol.
  ///
  /// La key permite que el executor obtenga el BuildContext y RenderBox
  /// del widget cuando ejecute eventos sobre él.
  GlobalKey? getGlobalKey(String id) => _registry.getGlobalKey(id);

  /// Retorna el BuildContext del widget si está montado.
  BuildContext? getContext(String id) => _registry.getContext(id);

  /// Retorna la metadata registrada para un widget.
  McpMetadataKey? getWidgetMetadata(String id) =>
      _registry.getWidgetMetadata(id);

  // ── Consultas ─────────────────────────────────────────────────────────────

  /// Lista los IDs de todos los widgets registrados.
  List<String> getAllWidgetIds() => _registry.getAllWidgetIds();

  /// Lista la metadata de todos los widgets registrados.
  List<McpMetadataKey> getAllWidgets() => _registry.getAllWidgets();

  // ── Serialización ─────────────────────────────────────────────────────────

  /// Genera el JSON de contexto consumido por el servidor MCP externo.
  ///
  /// Contiene screen, route, timestamp y la lista de widgets con capabilities.
  /// Este JSON es lo que Claude ve cuando llama a `get_app_context`.
  Map<String, dynamic> toJson({String? screen, String? route}) =>
      _registry.toJson(screen: screen, route: route);

  // ── Ejecución de eventos ──────────────────────────────────────────────────

  /// Ejecuta el [eventType] sobre el widget identificado por [widgetKey].
  ///
  /// Retorna true si el evento tuvo éxito, false si falló.
  /// Para aserciones, retorna true = aserción cumplida.
  ///
  /// Ver [McpEventType] para la lista completa de eventos disponibles.
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
