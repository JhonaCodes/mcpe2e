// ─────────────────────────────────────────────────────────────────────────────
// McpConnectivity
//
// Resuelve cómo el servidor MCP externo (mcpe2e_server) llega al servidor HTTP
// que corre dentro de la app Flutter, dependiendo de la plataforma.
//
// El problema: la app corre en un dispositivo/simulador y escucha en :7777.
// El servidor MCP corre en la PC del desarrollador. Hay que hacer que esos
// dos mundos se comuniquen, y la forma de hacerlo varía por plataforma.
//
// Plataforma → mecanismo de conectividad:
//
//   Android   → ADB port forward: localhost:7778 túnel → dispositivo:7777
//               Comando: adb forward tcp:7778 tcp:7777
//               TESTBRIDGE_URL = http://localhost:7778
//
//   iOS       → iproxy (libimobiledevice): localhost:7778 → dispositivo:7777
//               Comando: iproxy 7778 7777
//               TESTBRIDGE_URL = http://localhost:7778
//               (alternativa manual: conectar por IP WiFi directamente)
//
//   Desktop   → Sin forwarding: app y MCP server en la misma máquina
//               TESTBRIDGE_URL = http://localhost:7777
//
//   Web       → No soportado: Flutter Web no puede abrir sockets TCP.
//               El HTTP server no puede correr en un browser.
//               Alternativa futura: WebSocket bridge con service worker.
//
// Flujo:
//   McpEventServer.start() llama McpConnectivity.setup(port) →
//   McpConnectivity detecta plataforma → intenta configurar forwarding →
//   Loggea instrucciones para TESTBRIDGE_URL
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger_rs/logger_rs.dart';

// ── Modelo de conectividad ────────────────────────────────────────────────────

/// Información de conectividad para la plataforma actual.
///
/// Indica cómo debe configurarse TESTBRIDGE_URL en mcpe2e_server y qué
/// comando correr en la PC del desarrollador (si aplica).
class McpConnectivityInfo {
  /// Nombre de la plataforma detectada.
  final String platform;

  /// URL donde escucha el HTTP server dentro de la app.
  final String appUrl;

  /// URL que debe usarse en TESTBRIDGE_URL al iniciar mcpe2e_server.
  final String mcpServerUrl;

  /// Comando a ejecutar en la PC para configurar el forwarding (o vacío si no aplica).
  final String connectCommand;

  /// Si la plataforma soporta el flujo MCP.
  final bool isSupported;

  const McpConnectivityInfo({
    required this.platform,
    required this.appUrl,
    required this.mcpServerUrl,
    required this.connectCommand,
    required this.isSupported,
  });
}

// ── McpConnectivity ───────────────────────────────────────────────────────────

/// Configura la conectividad entre la app y el servidor MCP según la plataforma.
class McpConnectivity {
  McpConnectivity._();

  /// Configura el forwarding de puertos para la plataforma actual y retorna
  /// información de conectividad para logs/debug.
  ///
  /// [appPort] es el puerto donde escucha el HTTP server dentro de la app.
  /// [forwardPort] es el puerto local en la PC del dev (solo Android/iOS).
  static Future<McpConnectivityInfo> setup({
    required int appPort,
    int? forwardPort,
  }) async {
    final fwPort = forwardPort ?? (appPort + 1);

    if (kIsWeb) return _webInfo(appPort);

    if (Platform.isAndroid) return _setupAndroid(appPort, fwPort);
    if (Platform.isIOS) return _setupIOS(appPort, fwPort);
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return _desktopInfo(appPort);
    }

    return _unknownInfo(appPort);
  }

  // ── Android ───────────────────────────────────────────────────────────────

  /// Ejecuta `adb forward` para crear el túnel TCP.
  ///
  /// Requiere que el dispositivo esté conectado por USB con depuración USB
  /// activada y que `adb` esté en el PATH del sistema.
  static Future<McpConnectivityInfo> _setupAndroid(
    int appPort,
    int fwPort,
  ) async {
    Log.i(
      '[Connectivity] 📱 Android: intentando ADB forward tcp:$fwPort → tcp:$appPort',
    );

    try {
      final result = await Process.run('adb', [
        'forward',
        'tcp:$fwPort',
        'tcp:$appPort',
      ]);
      if (result.exitCode == 0) {
        Log.i(
          '[Connectivity] ✅ ADB forward OK: localhost:$fwPort → device:$appPort',
        );
      } else {
        Log.i(
          '[Connectivity] ⚠️  ADB forward falló (puede estar ya configurado): ${result.stderr}',
        );
      }
    } catch (e) {
      Log.i('[Connectivity] ⚠️  adb no disponible en PATH: $e');
    }

    return McpConnectivityInfo(
      platform: 'Android',
      appUrl: 'http://0.0.0.0:$appPort (en el dispositivo)',
      mcpServerUrl: 'http://localhost:$fwPort',
      connectCommand: 'adb forward tcp:$fwPort tcp:$appPort',
      isSupported: true,
    );
  }

  // ── iOS ───────────────────────────────────────────────────────────────────

  /// Intenta `iproxy` (libimobiledevice) para iOS.
  ///
  /// Si iproxy no está instalado, loggea instrucciones para conectar por WiFi.
  /// Instalar: `brew install libimobiledevice`
  static Future<McpConnectivityInfo> _setupIOS(int appPort, int fwPort) async {
    Log.i('[Connectivity] 🍎 iOS: intentando iproxy $fwPort:$appPort');

    try {
      // iproxy corre en background, no esperamos resultado
      await Process.start('iproxy', ['$fwPort', '$appPort']);
      Log.i(
        '[Connectivity] ✅ iproxy iniciado: localhost:$fwPort → device:$appPort',
      );
    } catch (e) {
      Log.i(
        '[Connectivity] ⚠️  iproxy no disponible. Usa la IP del dispositivo directamente.',
      );
      Log.i('[Connectivity]    Instalar: brew install libimobiledevice');
      Log.i(
        '[Connectivity]    Alternativa: TESTBRIDGE_URL=http://<device-ip>:$appPort',
      );
    }

    return McpConnectivityInfo(
      platform: 'iOS',
      appUrl: 'http://0.0.0.0:$appPort (en el dispositivo)',
      mcpServerUrl: 'http://localhost:$fwPort',
      connectCommand: 'iproxy $fwPort $appPort',
      isSupported: true,
    );
  }

  // ── Desktop ───────────────────────────────────────────────────────────────

  /// En desktop, la app y el servidor MCP corren en la misma máquina.
  /// No se necesita forwarding — apuntar directamente a localhost.
  static McpConnectivityInfo _desktopInfo(int appPort) {
    Log.i('[Connectivity] 🖥️  Desktop: sin forwarding necesario');
    Log.i('[Connectivity]    TESTBRIDGE_URL=http://localhost:$appPort');

    return McpConnectivityInfo(
      platform: 'Desktop',
      appUrl: 'http://localhost:$appPort',
      mcpServerUrl: 'http://localhost:$appPort',
      connectCommand: '',
      isSupported: true,
    );
  }

  // ── Web ───────────────────────────────────────────────────────────────────

  /// Flutter Web no soporta sockets TCP — el HTTP server no puede correr
  /// en el contexto de un browser.
  static McpConnectivityInfo _webInfo(int appPort) {
    Log.i('[Connectivity] 🌐 Web: no soportado.');
    Log.i('[Connectivity]    Flutter Web no puede abrir sockets TCP.');
    Log.i('[Connectivity]    Alternativa futura: WebSocket bridge.');

    return McpConnectivityInfo(
      platform: 'Web',
      appUrl: 'N/A (Web no soportado)',
      mcpServerUrl: 'N/A',
      connectCommand: '',
      isSupported: false,
    );
  }

  // ── Plataforma desconocida ────────────────────────────────────────────────

  static McpConnectivityInfo _unknownInfo(int appPort) {
    return McpConnectivityInfo(
      platform: 'Unknown',
      appUrl: 'http://0.0.0.0:$appPort',
      mcpServerUrl: 'http://localhost:$appPort',
      connectCommand: '',
      isSupported: true,
    );
  }
}
