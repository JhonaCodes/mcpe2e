import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'device_registry.dart';
import 'skill.dart';
import 'tools.dart';
import 'version.dart';

class McpServer {
  final DeviceRegistry registry;

  McpServer(String baseUrl) : registry = DeviceRegistry(baseUrl);

  Future<void> run() async {
    // ── Step 1: Synchronous ADB forward ──────────────────────────────────────
    // Runs immediately before the stdin loop so the very first tool call
    // already has a working bridge — no manual "adb forward" needed.
    // Fast (~50ms): just enumerates devices and sets up forwarding.
    // Does NOT require the Flutter app to be running yet.
    _autoForwardAdb(registry);

    // ── Step 2: Device watcher — detects new devices while server runs ────────
    // Polls every 5s. Forwards and registers any device that appears after startup.
    _startDeviceWatcher(registry);

    // ── Step 3: Full device registration (non-blocking) ──────────────────────
    // Pings each device to confirm mcpe2e is running and reads the active
    // screen name. Runs in background — doesn't delay the first tool call.
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

  void _autoForwardAdb(DeviceRegistry registry) {
    try {
      final adb = findAdb();
      final result = Process.runSync(adb, ['devices']);
      if (result.exitCode != 0) {
        stderr.writeln('[mcpe2e] ADB not found — install Android SDK platform-tools');
        return;
      }
      final lines = (result.stdout as String)
          .split('\n')
          .skip(1)
          .where((l) => l.contains('\tdevice'))
          .toList();

      if (lines.isEmpty) return; // no devices — silent, watcher will retry

      int port = 7778;
      for (final line in lines) {
        final serial = line.split('\t').first.trim();
        final fwd = Process.runSync(adb, ['-s', serial, 'forward', 'tcp:$port', 'tcp:7777']);
        if (fwd.exitCode == 0) {
          registry.register(serial, 'http://localhost:$port');
          stderr.writeln('[mcpe2e] ✓ $serial → localhost:$port');
        } else {
          stderr.writeln('[mcpe2e] ✗ forward failed for $serial: ${fwd.stderr}');
        }
        port++;
      }
    } catch (e) {
      stderr.writeln('[mcpe2e] ADB error: $e');
    }
  }

  void _startDeviceWatcher(DeviceRegistry registry) {
    Timer.periodic(const Duration(seconds: 5), (_) {
      try {
        final adb = findAdb();
        final result = Process.runSync(adb, ['devices']);
        if (result.exitCode != 0) return;

        final lines = (result.stdout as String)
            .split('\n')
            .skip(1)
            .where((l) => l.contains('\tdevice'))
            .toList();

        final usedPorts = registry.allUrls
            .map((url) => Uri.parse(url).port)
            .toSet();
        int port = 7778;

        for (final line in lines) {
          final serial = line.split('\t').first.trim();
          if (registry.isRegistered(serial)) continue; // already forwarded

          while (usedPorts.contains(port)) port++;

          final fwd = Process.runSync(adb, ['-s', serial, 'forward', 'tcp:$port', 'tcp:7777']);
          if (fwd.exitCode == 0) {
            registry.register(serial, 'http://localhost:$port');
            usedPorts.add(port);
            stderr.writeln('[mcpe2e] ✓ new device $serial → localhost:$port');
          }
          port++;
        }
      } catch (_) {}
    });
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
            'capabilities': {'tools': {}, 'prompts': {}},
            'serverInfo': {'name': kServerName, 'version': kServerVersion},
          },
        };

      case 'tools/list':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {'tools': toolDefinitions},
        };

      case 'prompts/list':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'prompts': [
              {
                'name': 'mcpe2e_expert',
                'description':
                    '⭐ START HERE — Complete mcpe2e expert guide. Covers: widget resolution priority '
                    '(keys > coordinates > screenshot), all 34 tools, agent protocol, interaction patterns, '
                    'how to write SCRIPT/GOAL tests, widget key conventions, performance rules, and error recovery. '
                    'Request this prompt BEFORE your first E2E interaction.',
                'arguments': [],
              },
              {
                'name': 'mcpe2e_workflow',
                'description':
                    'Agent protocol only: core loop, tool decision tree, interaction patterns, error recovery. '
                    'Use mcpe2e_expert instead for the full guide.',
                'arguments': [],
              },
              {
                'name': 'mcpe2e_writing_tests',
                'description':
                    'Test writing only: SCRIPT vs GOAL modes, templates, timing heuristics. '
                    'Use mcpe2e_expert instead for the full guide.',
                'arguments': [],
              },
              {
                'name': 'mcpe2e_widget_keys',
                'description':
                    'Widget keys only: McpMetadataKey, naming convention, keys vs coordinates. '
                    'Use mcpe2e_expert instead for the full guide.',
                'arguments': [],
              },
            ],
          },
        };

      case 'prompts/get':
        final promptName =
            (req['params'] as Map<String, dynamic>?)?['name'] as String? ?? '';
        final (String desc, String content) = switch (promptName) {
          'mcpe2e_expert' => (
            'mcpe2e Expert E2E Testing Guide — complete reference for AI agents',
            kMcpe2eExpertSkill,
          ),
          'mcpe2e_workflow' => (
            'mcpe2e Flutter E2E workflow guide and agent protocol',
            kMcpe2eWorkflowSkill,
          ),
          'mcpe2e_writing_tests' => (
            'How to write E2E tests: SCRIPT vs GOAL modes, templates, timing',
            kMcpe2eWritingTestsSkill,
          ),
          'mcpe2e_widget_keys' => (
            'Widget key convention: naming, McpMetadataKey, keys vs coordinates',
            kMcpe2eWidgetKeysSkill,
          ),
          _ => ('', ''),
        };
        if (content.isEmpty) {
          return {
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32602, 'message': 'Prompt not found: $promptName'},
          };
        }
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'description': desc,
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': content},
              },
            ],
          },
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
              'content': result, // result is already List<Map<String,dynamic>>
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
