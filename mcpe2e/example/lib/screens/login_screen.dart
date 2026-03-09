import 'package:flutter/material.dart';
import '../testing/mcp_keys.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  bool get _canSubmit =>
      _emailController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty;

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
      _errorMessage = null;
    });

    // Simulate network call
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    // Accept any non-empty email with a password of 6+ chars
    if (_passwordController.text.length >= 6) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(email: _emailController.text),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Password must be at least 6 characters';
      });
    }
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
            const SizedBox(height: 24),
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            // Email field
            TextField(
              key: McpKeys.loginEmail,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Password field
            TextField(
              key: McpKeys.loginPassword,
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'At least 6 characters',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            // Error message (only visible on failure)
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  key: McpKeys.loginError,
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            const SizedBox(height: 24),

            // Login button — disabled until both fields are filled
            ElevatedButton(
              key: McpKeys.loginButton,
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
