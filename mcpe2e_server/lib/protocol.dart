import 'dart:convert';
import 'dart:io';

import 'tools.dart';

class McpServer {
  final FlutterBridge bridge;

  McpServer(String baseUrl) : bridge = FlutterBridge(baseUrl);

  Future<void> run() async {
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
            'serverInfo': {'name': 'dart-mcpe2e', 'version': '1.0.0'},
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
          final result = await callTool(bridge, toolName, args);
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
