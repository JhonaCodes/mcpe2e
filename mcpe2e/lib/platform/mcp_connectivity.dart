// ─────────────────────────────────────────────────────────────────────────────
// McpConnectivity
//
// Resolves how the external MCP server (mcpe2e_server) reaches the HTTP server
// running inside the Flutter app, depending on the platform.
//
// The problem: the app runs on a device/simulator and listens on :7777.
// The MCP server runs on the developer's PC. These two worlds need to
// communicate, and the way to do it varies by platform.
//
// Platform → connectivity mechanism:
//
//   Android   → ADB port forward: localhost:7778 tunnel → device:7777
//               Command: adb forward tcp:7778 tcp:7777
//               TESTBRIDGE_URL = http://localhost:7778
//
//   iOS       → iproxy (libimobiledevice): localhost:7778 → device:7777
//               Command: iproxy 7778 7777
//               TESTBRIDGE_URL = http://localhost:7778
//               (manual alternative: connect by WiFi IP directly)
//
//   Desktop   → No forwarding: app and MCP server on the same machine
//               TESTBRIDGE_URL = http://localhost:7777
//
//   Web       → Not supported: Flutter Web cannot open TCP sockets.
//               The HTTP server cannot run in a browser.
//               Future alternative: WebSocket bridge with service worker.
//
// Flow:
//   McpEventServer.start() calls McpConnectivity.setup(port) →
//   McpConnectivity detects platform → attempts to configure forwarding →
//   Logs instructions for TESTBRIDGE_URL
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger_rs/logger_rs.dart';

// ── Connectivity model ────────────────────────────────────────────────────────

/// Connectivity information for the current platform.
///
/// Indicates how TESTBRIDGE_URL should be configured in mcpe2e_server and what
/// command to run on the developer's PC (if applicable).
class McpConnectivityInfo {
  /// Name of the detected platform.
  final String platform;

  /// URL where the HTTP server listens inside the app.
  final String appUrl;

  /// URL to use in TESTBRIDGE_URL when starting mcpe2e_server.
  final String mcpServerUrl;

  /// Command to run on the PC to configure forwarding (or empty if not applicable).
  final String connectCommand;

  /// Whether the platform supports the MCP flow.
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

/// Configures connectivity between the app and the MCP server based on the platform.
class McpConnectivity {
  McpConnectivity._();

  /// Configures port forwarding for the current platform and returns
  /// connectivity information for logs/debug.
  ///
  /// [appPort] is the port where the HTTP server listens inside the app.
  /// [forwardPort] is the local port on the dev's PC (Android/iOS only).
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

  /// Runs `adb forward` to create the TCP tunnel.
  ///
  /// Requires the device to be connected via USB with USB debugging
  /// enabled and `adb` to be in the system PATH.
  static Future<McpConnectivityInfo> _setupAndroid(
    int appPort,
    int fwPort,
  ) async {
    Log.i(
      '[Connectivity] 📱 Android: attempting ADB forward tcp:$fwPort → tcp:$appPort',
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
          '[Connectivity] ⚠️  ADB forward failed (may already be configured): ${result.stderr}',
        );
      }
    } catch (e) {
      Log.i('[Connectivity] ⚠️  adb not available in PATH: $e');
    }

    return McpConnectivityInfo(
      platform: 'Android',
      appUrl: 'http://0.0.0.0:$appPort (on the device)',
      mcpServerUrl: 'http://localhost:$fwPort',
      connectCommand: 'adb forward tcp:$fwPort tcp:$appPort',
      isSupported: true,
    );
  }

  // ── iOS ───────────────────────────────────────────────────────────────────

  /// Attempts `iproxy` (libimobiledevice) for iOS.
  ///
  /// If iproxy is not installed, logs instructions for connecting via WiFi.
  /// Install: `brew install libimobiledevice`
  static Future<McpConnectivityInfo> _setupIOS(int appPort, int fwPort) async {
    Log.i('[Connectivity] 🍎 iOS: attempting iproxy $fwPort:$appPort');

    try {
      // iproxy corre en background, no esperamos resultado
      await Process.start('iproxy', ['$fwPort', '$appPort']);
      Log.i(
        '[Connectivity] ✅ iproxy started: localhost:$fwPort → device:$appPort',
      );
    } catch (e) {
      Log.i(
        '[Connectivity] ⚠️  iproxy not available. Use the device IP directly.',
      );
      Log.i('[Connectivity]    Install: brew install libimobiledevice');
      Log.i(
        '[Connectivity]    Alternative: TESTBRIDGE_URL=http://<device-ip>:$appPort',
      );
    }

    return McpConnectivityInfo(
      platform: 'iOS',
      appUrl: 'http://0.0.0.0:$appPort (on the device)',
      mcpServerUrl: 'http://localhost:$fwPort',
      connectCommand: 'iproxy $fwPort $appPort',
      isSupported: true,
    );
  }

  // ── Desktop ───────────────────────────────────────────────────────────────

  /// On desktop, the app and the MCP server run on the same machine.
  /// No forwarding needed — point directly to localhost.
  static McpConnectivityInfo _desktopInfo(int appPort) {
    Log.i('[Connectivity] 🖥️  Desktop: no forwarding needed');
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

  /// Flutter Web does not support TCP sockets — the HTTP server cannot run
  /// in a browser context.
  static McpConnectivityInfo _webInfo(int appPort) {
    Log.i('[Connectivity] 🌐 Web: not supported.');
    Log.i('[Connectivity]    Flutter Web cannot open TCP sockets.');
    Log.i('[Connectivity]    Future alternative: WebSocket bridge.');

    return McpConnectivityInfo(
      platform: 'Web',
      appUrl: 'N/A (Web not supported)',
      mcpServerUrl: 'N/A',
      connectCommand: '',
      isSupported: false,
    );
  }

  // ── Unknown platform ─────────────────────────────────────────────────────

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
