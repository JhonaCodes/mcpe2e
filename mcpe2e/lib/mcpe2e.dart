/// mcpe2e — Flutter E2E Testing Library for MCP
///
/// Librería que corre dentro de la app Flutter y expone un servidor HTTP
/// para que Claude (via mcpe2e_server) pueda controlar widgets reales:
/// taps, inputs, swipes, aserciones y más.
///
/// ## Arquitectura
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
/// // 1. Registrar widgets (antes de montarlos)
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
/// // 3. Iniciar el servidor HTTP solo en debug
/// if (kDebugMode) await McpEventServer.start();
/// ```
///
/// ## Convención de IDs
///
/// Los IDs siguen el patrón: `modulo.elemento[.variante]`
/// ```
/// auth.login_button       → botón de login
/// auth.email_field        → campo de email
/// order.form.price        → campo precio dentro de formulario
/// screen.dashboard        → identificador de pantalla (para aserciones)
/// state.loading_indicator → indicador de carga (para assert_visible)
/// ```
library;

// ── Modelo de eventos ─────────────────────────────────────────────────────────
// Tipos de eventos (tap, swipe, toggle, assertVisible, etc.) y sus parámetros.
export 'events/mcp_event_type.dart';

// ── Metadata de widgets ───────────────────────────────────────────────────────
// McpMetadataKey (la key que asignas al widget) y McpWidgetType (enum de tipos).
export 'events/mcp_metadata_key.dart';

// ── Fachada pública ───────────────────────────────────────────────────────────
// McpEvents: punto de entrada para registrar widgets y ejecutar eventos.
export 'events/mcp_events_core.dart';

// ── Conectividad de plataforma ────────────────────────────────────────────────
// McpConnectivity: detecta plataforma y configura ADB forward / iproxy / desktop.
export 'platform/mcp_connectivity.dart';

// ── Servidor HTTP ─────────────────────────────────────────────────────────────
// McpEventServer: expone los endpoints HTTP que consume mcpe2e_server.
export 'server/mcp_event_server.dart';

// ── Inspección del UI ─────────────────────────────────────────────────────────
// McpTreeInspector: recorre el widget tree y extrae datos sin intrusión.
// McpScreenCapture: captura la pantalla via layer tree interno (debug/profile).
export 'core/mcp_tree_inspector.dart';
export 'core/mcp_screen_capture.dart';

// ── Observador de navegación ──────────────────────────────────────────────────
// McpNavigatorObserver: captura el route activo para get_app_context.
// Registrar en MaterialApp(navigatorObservers:) o GoRouter(observers:).
export 'core/mcp_navigator_observer.dart';
