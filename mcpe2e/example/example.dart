// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mcpe2e/mcpe2e.dart';

// ── Widget keys ───────────────────────────────────────────────────────────────
//
// McpMetadataKey extends Flutter's Key — assign it directly to any widget.
// Convention: module.element[.variant]

const _emailField = McpMetadataKey(
  id: 'auth.email_field',
  widgetType: McpWidgetType.textField,
  description: 'Email input',
  screen: 'LoginScreen',
);

const _passwordField = McpMetadataKey(
  id: 'auth.password_field',
  widgetType: McpWidgetType.textField,
  description: 'Password input',
  screen: 'LoginScreen',
);

const _loginButton = McpMetadataKey(
  id: 'auth.login_button',
  widgetType: McpWidgetType.button,
  description: 'Submit login — disabled until both fields are filled',
  screen: 'LoginScreen',
);

const _rememberMe = McpMetadataKey(
  id: 'auth.remember_me',
  widgetType: McpWidgetType.checkbox,
  description: 'Remember me checkbox',
  screen: 'LoginScreen',
);

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register widgets and start the HTTP server (debug/profile only).
  // McpEventServer.start() is a no-op in release builds.
  if (kDebugMode || kProfileMode) {
    McpEvents.instance
      ..registerWidget(_emailField)
      ..registerWidget(_passwordField)
      ..registerWidget(_loginButton)
      ..registerWidget(_rememberMe);

    await McpEventServer.start();
    // The startup log prints the TESTBRIDGE_URL to use with mcpe2e_server.
  }

  runApp(const ExampleApp());
}

// ── App ───────────────────────────────────────────────────────────────────────

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

// ── Login screen ──────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMeChecked = false;
  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    if (_passwordController.text.length >= 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Welcome, ${_emailController.text}')),
      );
    } else {
      setState(() => _error = 'Password must be at least 6 characters');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email — key: McpMetadataKey, addressable as 'auth.email_field'
            TextField(
              key: _emailField,
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Password
            TextField(
              key: _passwordField,
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            // Remember me checkbox
            Row(
              children: [
                Checkbox(
                  key: _rememberMe,
                  value: _rememberMeChecked,
                  onChanged: (v) =>
                      setState(() => _rememberMeChecked = v ?? false),
                ),
                const Text('Remember me'),
              ],
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            // Login button — disabled until both fields are filled
            // Claude can detect this state via inspect_ui or assert_enabled
            ElevatedButton(
              key: _loginButton,
              onPressed: (_canSubmit && !_isLoading) ? _handleLogin : null,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
