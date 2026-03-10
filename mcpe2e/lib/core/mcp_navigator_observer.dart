// ─────────────────────────────────────────────────────────────────────────────
// McpNavigatorObserver
//
// NavigatorObserver que captura el route actual para que get_app_context
// retorne la ruta real de la app en lugar del fallback "/unknownscreen".
//
// Integración (una línea):
//
//   MaterialApp / CupertinoApp:
//     navigatorObservers: [McpNavigatorObserver.instance]
//
//   GoRouter:
//     GoRouter(observers: [McpNavigatorObserver.instance])
//
// Sin registro: currentRoute retorna null y se usa el fallback derivado
// del screen name (comportamiento anterior — sin breaking change).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';

/// Observa los pushes/pops del Navigator y mantiene el route actual.
///
/// Singleton — usar [McpNavigatorObserver.instance].
///
/// Compatible con cualquier Navigator (MaterialApp, GoRouter, Navigator directo).
/// El nombre del route viene de [RouteSettings.name], que GoRouter y Navigator
/// populan automáticamente con el path (e.g. `/marketplace`, `/orders/detail`).
class McpNavigatorObserver extends NavigatorObserver {
  McpNavigatorObserver._();

  static final McpNavigatorObserver instance = McpNavigatorObserver._();

  String? _currentRoute;

  /// Ruta actual observada, o null si el observer no está registrado.
  ///
  /// Formato típico: `/marketplace`, `/orders/123`, `/settings`.
  String? get currentRoute => _currentRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  void _update(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) {
      _currentRoute = name;
    }
  }
}
