import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'device_registry.dart';
import 'tools.dart';
import 'version.dart';

class McpServer {
  final DeviceRegistry registry;

  McpServer(String baseUrl) : registry = DeviceRegistry(baseUrl);

  Future<void> run() async {
    // Auto-discover connected Android devices on startup (non-blocking).
    // Sets up ADB port-forwarding automatically — no manual setup needed.
    unawaited(callTool(registry, 'list_devices', {}).catchError((_) => <Map<String, dynamic>>[]));

    await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      Map<String, dynamic> request;
      try {
        request = jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final response = await _handle(request);
      if (response != null) {
        stdout.writeln(jsonEncode(response));
      }
    }
  }

  Future<Map<String, dynamic>?> _handle(Map<String, dynamic> req) async {
    final id = req['id'];
    final method = req['method'] as String?;

    if (method == null) return null;

    // Notifications don't get responses
    if (method.startsWith('notifications/')) return null;

    switch (method) {
      case 'initialize':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': kServerName, 'version': kServerVersion},
          },
        };

      case 'tools/list':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {'tools': toolDefinitions},
        };

      case 'tools/call':
        final params = req['params'] as Map<String, dynamic>? ?? {};
        final toolName = params['name'] as String? ?? '';
        final args = params['arguments'] as Map<String, dynamic>? ?? {};

        try {
          final result = await callTool(registry, toolName, args);
          return {
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'content': result, // result ya es List<Map<String,dynamic>>
            },
          };
        } catch (e) {
          return {
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'content': [
                {'type': 'text', 'text': 'Error: $e'}
              ],
              'isError': true,
            },
          };
        }

      default:
        return {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32601, 'message': 'Method not found: $method'},
        };
    }
  }
}
