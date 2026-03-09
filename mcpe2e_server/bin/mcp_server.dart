import 'dart:io';

import 'package:mcpe2e_server/protocol.dart';
import 'package:mcpe2e_server/setup.dart';

void main(List<String> args) async {
  if (args.isNotEmpty && args[0] == 'setup') {
    await runSetup();
    return;
  }
  final baseUrl = Platform.environment['TESTBRIDGE_URL'] ?? 'http://localhost:7777';
  final server = McpServer(baseUrl);
  await server.run();
}
