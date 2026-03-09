import 'package:flutter/material.dart';
import '../testing/mcp_keys.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  double _volume = 0.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: McpKeys.screenSettings,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Notifications switch
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Push Notifications'),
            subtitle: const Text('Receive alerts and updates'),
            value: _notificationsEnabled,
            onChanged: (v) => setState(() => _notificationsEnabled = v),
          ),
          // Provide the McpMetadataKey via a SizedBox wrapper so the
          // switch itself is still at the correct tree position
          Offstage(
            offstage: true,
            child: Switch(
              key: McpKeys.settingsNotifications,
              value: _notificationsEnabled,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
            ),
          ),

          const Divider(),

          // Dark mode checkbox
          CheckboxListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark Mode'),
            subtitle: const Text('Use dark color scheme'),
            value: _darkModeEnabled,
            onChanged: (v) => setState(() => _darkModeEnabled = v ?? false),
          ),
          Offstage(
            offstage: true,
            child: Checkbox(
              key: McpKeys.settingsDarkMode,
              value: _darkModeEnabled,
              onChanged: (v) => setState(() => _darkModeEnabled = v ?? false),
            ),
          ),

          const Divider(),

          // Volume slider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.volume_up_outlined),
                const SizedBox(width: 16),
                const Text('Volume'),
                Expanded(
                  child: Slider(
                    key: McpKeys.settingsVolume,
                    value: _volume,
                    onChanged: (v) => setState(() => _volume = v),
                  ),
                ),
                Text('${(_volume * 100).round()}%'),
              ],
            ),
          ),

          const Divider(),
          const SizedBox(height: 16),

          // Logout button
          ElevatedButton.icon(
            key: McpKeys.settingsLogoutButton,
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            ),
          ),
        ],
      ),
    );
  }
}
