import 'dart:io';

import 'package:mcpe2e_server/protocol.dart';

void main() async {
  final baseUrl = Platform.environment['TESTBRIDGE_URL'] ?? 'http://localhost:7777';
  final server = McpServer(baseUrl);
  await server.run();
}
