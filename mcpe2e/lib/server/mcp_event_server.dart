// ─────────────────────────────────────────────────────────────────────────────
// McpEventServer
//
// Servidor HTTP embebido en la app Flutter. Es la interfaz de red entre el
// servidor MCP externo (mcpe2e_server) y el sistema de ejecución de eventos.
//
// Responsabilidad: únicamente enrutar requests HTTP a McpEvents.
// No ejecuta gestos, no maneja conectividad de plataforma, no conoce MCP.
//
// Endpoints:
//
//   GET  /ping                  Health check — confirma que el server está vivo
//   GET  /mcp/context           Contexto completo: screen + todos los widgets
//   GET  /action?key=...        Ejecuta evento con parámetros en URL
//   POST /event                 Ejecuta evento con JSON body
//   GET  /widgets               Lista widgets registrados
//
// Conectividad por plataforma (configurada por McpConnectivity, no aquí):
//
//   Android  → ADB forward localhost:7778 → device:7777
//   iOS      → iproxy localhost:7778 → device:7777
//   Desktop  → localhost:7777 directo (sin forwarding)
//   Web      → no soportado
//
// Para iniciar:
//   if (kDebugMode) await McpEventServer.start();
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logger_rs/logger_rs.dart';

import '../core/mcp_screen_capture.dart';
import '../core/mcp_tree_inspector.dart';
import '../events/mcp_events_core.dart';
import '../events/mcp_event_type.dart';
import '../platform/mcp_connectivity.dart';

// ── Server ────────────────────────────────────────────────────────────────────

/// Servidor HTTP que expone la API de E2E testing al servidor MCP externo.
///
/// Corre dentro de la app en modo debug. Escucha en :7777 por defecto.
/// McpConnectivity configura el forwarding de plataforma al arrancar.
class McpEventServer {
  static HttpServer? _server;
  static bool _isRunning = false;

  /// Puerto donde escucha el HTTP server dentro de la app (default 7777).
  static int port = 7777;

  /// Host de bind. 0.0.0.0 permite acceso desde ADB forward e iproxy.
  static String host = '0.0.0.0';

  /// Puerto local en la PC del dev para el forwarding (default port + 1).
  static int forwardPort = 7778;

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  /// Inicia el servidor HTTP y configura la conectividad de plataforma.
  ///
  /// Si ya está corriendo, no hace nada.
  /// Loggea los endpoints disponibles y cómo configurar TESTBRIDGE_URL.
  static Future<void> start({
    int? customPort,
    String? customHost,
    int? customForwardPort,
  }) async {
    Log.init(level: Level.SEVERE);

    // Guard de producción: el server no debe correr en release builds.
    // En release, los mecanismos de inspección (debugLayer, visitChildElements
    // para debug info) no están disponibles o retornan datos incompletos.
    if (!kDebugMode && !kProfileMode) {
      Log.i('[Server] ⚠️  McpEventServer no debe correr en producción. Abortando.');
      return;
    }

    if (_isRunning) {
      Log.i('[Server] Ya corriendo en http://$host:$port');
      return;
    }

    if (customPort != null) port = customPort;
    if (customHost != null) host = customHost;
    if (customForwardPort != null) forwardPort = customForwardPort;

    try {
      _server = await HttpServer.bind(host, port, shared: true);
      _isRunning = true;

      // Configurar conectividad de plataforma (ADB forward, iproxy, etc.)
      final connectivity = await McpConnectivity.setup(
        appPort: port,
        forwardPort: forwardPort,
      );

      _logStartup(connectivity);

      _server!.listen(_handleRequest, onError: (e) {
        Log.i('[Server] Error: $e');
      });
    } catch (e) {
      Log.i('[Server] ❌ No se pudo iniciar: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// Detiene el servidor HTTP.
  static Future<void> stop() async {
    if (!_isRunning || _server == null) return;
    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
    Log.i('[Server] 🛑 Detenido');
  }

  // ── Routing ───────────────────────────────────────────────────────────────

  /// Enruta cada request al handler correspondiente.
  static Future<void> _handleRequest(HttpRequest request) async {
    Log.i('[Server] ${request.method} ${request.uri.path}');
    try {
      switch (request.uri.path) {
        case '/ping':           _handlePing(request);
        case '/mcp/context':    _handleMcpContext(request);
        case '/mcp/tree':       _handleTree(request);
        case '/mcp/screenshot': await _handleScreenshot(request);
        case '/action':         await _handleAction(request);
        case '/event':          await _handleEvent(request);
        case '/widgets':        _handleWidgets(request);
        default:                _send(request, 404, 'text/plain', 'Endpoint no encontrado');
      }
    } catch (e) {
      Log.i('[Server] Error procesando request: $e');
      _send(request, 500, 'text/plain', 'Error interno: $e');
    }
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  /// GET /ping — Health check básico.
  ///
  /// El servidor MCP externo llama este endpoint para verificar que la app
  /// está viva antes de ejecutar comandos.
  /// Responde: {"status":"ok","port":7777}
  static void _handlePing(HttpRequest req) {
    _sendJson(req, {'status': 'ok', 'port': port});
  }

  /// GET /mcp/context — Contexto completo de la app.
  ///
  /// Retorna todos los widgets registrados con su metadata y capabilities.
  /// Claude llama este endpoint primero para saber qué hay en pantalla.
  ///
  /// Respuesta:
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
    _sendJson(req, McpEvents.instance.toJson());
  }

  /// GET /mcp/tree — Árbol de widgets con datos de la pantalla actual.
  ///
  /// Recorre el widget tree completo desde la raíz y retorna todos los widgets
  /// con datos relevantes: textos, valores de campos, estados de botones,
  /// checkboxes, switches, sliders, etc.
  ///
  /// No requiere que los widgets estén registrados en McpWidgetRegistry.
  /// Funciona con cualquier widget de la app.
  ///
  /// Respuesta:
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

  /// GET /mcp/screenshot — Captura la pantalla como PNG en base64.
  ///
  /// Usa el layer tree interno de Flutter: cero widgets extras en el árbol.
  /// Solo disponible en debug/profile; retorna error en release.
  ///
  /// Respuesta (éxito):
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
  /// Respuesta (release mode):
  /// ```json
  /// { "error": "not_available_in_release" }
  /// ```
  static Future<void> _handleScreenshot(HttpRequest req) async {
    _sendJson(req, await McpScreenCapture.capture());
  }

  /// GET /action?key=...&type=...&[params] — Ejecuta evento con params en URL.
  ///
  /// Parámetros obligatorios:
  ///   key   — ID del widget (e.g. "auth.login_button")
  ///   type  — tipo de evento (default "tap")
  ///
  /// Parámetros opcionales (según el tipo de evento):
  ///   text, duration, distance, direction, deltaX, deltaY, clearFirst,
  ///   expectedText, scale, dropdownValue, dropdownIndex, sliderValue,
  ///   targetKey, maxScrollAttempts, label, expectedCount
  ///
  /// Ejemplos:
  ///   GET /action?key=auth.login_button
  ///   GET /action?key=auth.email_field&type=textinput&text=user@test.com
  ///   GET /action?key=filter.active&type=toggle
  ///   GET /action?key=price_slider&type=setslidervalue&sliderValue=0.5
  static Future<void> _handleAction(HttpRequest req) async {
    final params = req.uri.queryParameters;
    final key = params['key'];

    if (key == null) {
      _send(req, 400, 'text/plain', 'Parámetro "key" requerido');
      return;
    }

    final typeStr = params['type'] ?? 'tap';
    final eventType = _parseEventType(typeStr);
    if (eventType == null) {
      _send(req, 400, 'text/plain', 'Tipo de evento inválido: $typeStr');
      return;
    }

    final eventParams = params.length > 1 ? _parseUrlParams(params) : null;

    final success = await McpEvents.instance.executeEvent(
      widgetKey: key,
      eventType: eventType,
      params: eventParams,
    );

    _send(req, 200, 'text/plain',
        success ? 'OK: $typeStr en "$key"' : 'Error: $typeStr en "$key" falló');
  }

  /// POST /event — Ejecuta evento con JSON body.
  ///
  /// Body esperado:
  /// ```json
  /// {
  ///   "key": "auth.login_button",
  ///   "type": "tap",
  ///   "params": { "text": "hello", "clearFirst": true }
  /// }
  /// ```
  ///
  /// Responde:
  /// ```json
  /// { "success": true, "widgetKey": "...", "eventType": "tap" }
  /// ```
  static Future<void> _handleEvent(HttpRequest req) async {
    if (req.method != 'POST') {
      _send(req, 405, 'text/plain', 'Método no permitido. Usa POST.');
      return;
    }

    final body = await utf8.decoder.bind(req).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final key = json['key'] as String?;
    final typeStr = json['type'] as String?;
    if (key == null || typeStr == null) {
      _send(req, 400, 'text/plain', 'Body requiere "key" y "type"');
      return;
    }

    final eventType = _parseEventType(typeStr);
    if (eventType == null) {
      _send(req, 400, 'text/plain', 'Tipo inválido: $typeStr');
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

    _sendJson(req, {'success': success, 'widgetKey': key, 'eventType': typeStr});
  }

  /// GET /widgets — Lista los widgets registrados.
  ///
  /// Sin parámetros: retorna solo los IDs.
  /// Con ?metadata=true: retorna contexto completo (igual que /mcp/context).
  static void _handleWidgets(HttpRequest req) {
    final full = req.uri.queryParameters['metadata'] == 'true';
    if (full) {
      _sendJson(req, McpEvents.instance.toJson());
    } else {
      _sendJson(req, {'widgets': McpEvents.instance.getAllWidgetIds()});
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Convierte el string del tipo de evento a [McpEventType].
  ///
  /// Acepta camelCase y snake_case indistintamente.
  static McpEventType? _parseEventType(String type) {
    return switch (type.toLowerCase()) {
      'tap'                              => McpEventType.tap,
      'doubletap' || 'double_tap'        => McpEventType.doubleTap,
      'longpress' || 'long_press'        => McpEventType.longPress,
      'swipe'                            => McpEventType.swipe,
      'drag'                             => McpEventType.drag,
      'scroll'                           => McpEventType.scroll,
      'pinch'                            => McpEventType.pinch,
      'textinput' || 'text_input'        => McpEventType.textInput,
      'cleartext' || 'clear_text'        => McpEventType.clearText,
      'selectdropdown' || 'select_dropdown' => McpEventType.selectDropdown,
      'toggle'                           => McpEventType.toggle,
      'setslidervalue' || 'set_slider_value' => McpEventType.setSliderValue,
      'hidekeyboard' || 'hide_keyboard'  => McpEventType.hideKeyboard,
      'showkeyboard' || 'show_keyboard'  => McpEventType.showKeyboard,
      'pressback' || 'press_back'        => McpEventType.pressBack,
      'scrolluntilvisible' || 'scroll_until_visible' => McpEventType.scrollUntilVisible,
      'tapbylabel' || 'tap_by_label'     => McpEventType.tapByLabel,
      'wait'                             => McpEventType.wait,
      'assertexists' || 'assert_exists'  => McpEventType.assertExists,
      'asserttext' || 'assert_text'      => McpEventType.assertText,
      'assertvisible' || 'assert_visible' => McpEventType.assertVisible,
      'assertenabled' || 'assert_enabled' => McpEventType.assertEnabled,
      'assertselected' || 'assert_selected' => McpEventType.assertSelected,
      'assertvalue' || 'assert_value'    => McpEventType.assertValue,
      'assertcount' || 'assert_count'    => McpEventType.assertCount,
      _                                  => null,
    };
  }

  /// Convierte los query parameters de URL a [McpEventParams].
  static McpEventParams _parseUrlParams(Map<String, String> p) {
    return McpEventParams(
      text:             p['text'],
      duration:         p['duration']    != null ? Duration(milliseconds: int.parse(p['duration']!)) : null,
      distance:         p['distance']    != null ? double.parse(p['distance']!) : null,
      direction:        p['direction'],
      deltaX:           p['deltaX']      != null ? double.parse(p['deltaX']!) : null,
      deltaY:           p['deltaY']      != null ? double.parse(p['deltaY']!) : null,
      clearFirst:       p['clearFirst'] == 'true',
      expectedText:     p['expectedText'],
      scale:            p['scale']       != null ? double.parse(p['scale']!) : null,
      dropdownValue:    p['dropdownValue'],
      dropdownIndex:    p['dropdownIndex']    != null ? int.parse(p['dropdownIndex']!) : null,
      sliderValue:      p['sliderValue']      != null ? double.parse(p['sliderValue']!) : null,
      targetKey:        p['targetKey'],
      maxScrollAttempts: p['maxScrollAttempts'] != null ? int.parse(p['maxScrollAttempts']!) : null,
      label:            p['label'],
      expectedCount:    p['expectedCount']    != null ? int.parse(p['expectedCount']!) : null,
    );
  }

  // ── Helpers de respuesta ──────────────────────────────────────────────────

  static void _sendJson(HttpRequest req, Map<String, dynamic> body) {
    _send(req, 200, 'application/json', jsonEncode(body));
  }

  static void _send(HttpRequest req, int status, String contentType, String body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.parse(contentType)
      ..write(body)
      ..close();
  }

  // ── Startup log ───────────────────────────────────────────────────────────

  static void _logStartup(McpConnectivityInfo info) {
    Log.d('');
    Log.d('╔══════════════════════════════════════════════════╗');
    Log.d('║           mcpe2e HTTP Server iniciado            ║');
    Log.d('╠══════════════════════════════════════════════════╣');
    Log.d('║ Plataforma : ${info.platform.padRight(35)}║');
    Log.d('║ App URL    : http://$host:$port${' ' * (27 - '$host:$port'.length)}║');
    Log.d('╠══════════════════════════════════════════════════╣');
    Log.d('║ Endpoints disponibles:                           ║');
    Log.d('║   GET  /ping                                     ║');
    Log.d('║   GET  /mcp/context                              ║');
    Log.d('║   GET  /mcp/tree                                 ║');
    Log.d('║   GET  /mcp/screenshot                           ║');
    Log.d('║   GET  /action?key=...&type=...                  ║');
    Log.d('║   POST /event                                    ║');
    Log.d('║   GET  /widgets                                  ║');
    Log.d('╠══════════════════════════════════════════════════╣');
    if (info.connectCommand.isNotEmpty) {
      Log.d('║ En tu PC, ejecuta:                               ║');
      Log.d('║   ${info.connectCommand.padRight(48)}║');
    }
    Log.d('║ Luego inicia mcpe2e_server con:                  ║');
    Log.d('║   TESTBRIDGE_URL=${info.mcpServerUrl}${' ' * (32 - info.mcpServerUrl.length)}║');
    Log.d('╚══════════════════════════════════════════════════╝');
    Log.d('');
  }
}
