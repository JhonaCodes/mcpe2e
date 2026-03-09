import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mcpe2e/mcpe2e.dart';

import 'screens/login_screen.dart';
import 'testing/mcp_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the mcpe2e HTTP server in debug and profile builds.
  // In release mode McpEventServer.start() is a no-op (safe to call anyway).
  await _initE2E();

  runApp(const ExampleApp());
}

/// Registers all static widget keys and starts the HTTP server.
///
/// The server listens on port 7777 and automatically configures
/// platform-specific forwarding (ADB on Android, iproxy on iOS).
/// On desktop it binds directly to localhost:7777 — no forwarding needed.
Future<void> _initE2E() async {
  if (!kDebugMode && !kProfileMode) return;

  final mcp = McpEvents.instance;

  // Register static keys (dynamic keys are registered in their widget's initState)
  mcp.registerWidget(McpKeys.loginEmail);
  mcp.registerWidget(McpKeys.loginPassword);
  mcp.registerWidget(McpKeys.loginButton);
  mcp.registerWidget(McpKeys.loginError);
  mcp.registerWidget(McpKeys.screenDashboard);
  mcp.registerWidget(McpKeys.dashboardWelcome);
  mcp.registerWidget(McpKeys.dashboardSettingsButton);
  mcp.registerWidget(McpKeys.dashboardItemList);
  mcp.registerWidget(McpKeys.screenSettings);
  mcp.registerWidget(McpKeys.settingsNotifications);
  mcp.registerWidget(McpKeys.settingsDarkMode);
  mcp.registerWidget(McpKeys.settingsVolume);
  mcp.registerWidget(McpKeys.settingsLogoutButton);

  await McpEventServer.start();
  // After start, the log output shows:
  //   App URL    : http://0.0.0.0:7777
  //   TESTBRIDGE_URL=http://localhost:7778   ← use this with mcpe2e_server
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mcpe2e Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
