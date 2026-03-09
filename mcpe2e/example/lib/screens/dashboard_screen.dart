import 'package:flutter/material.dart';
import 'package:mcpe2e/mcpe2e.dart';
import '../testing/mcp_keys.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String email;

  const DashboardScreen({required this.email, super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Register dynamic item keys on init, unregister on dispose
  final List<McpMetadataKey> _itemKeys = [];

  static const _itemCount = 15;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _itemCount; i++) {
      final key = McpKeys.dashboardItem(i);
      _itemKeys.add(key);
      McpEvents.instance.registerWidget(key);
    }
  }

  @override
  void dispose() {
    for (final key in _itemKeys) {
      McpEvents.instance.unregisterWidget(key.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: McpKeys.screenDashboard,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            key: McpKeys.dashboardSettingsButton,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              key: McpKeys.dashboardWelcome,
              'Welcome, ${widget.email}',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: McpKeys.dashboardItemList,
              itemCount: _itemCount,
              itemBuilder: (context, index) {
                return Card(
                  key: _itemKeys[index],
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    title: Text('Item ${index + 1}'),
                    subtitle: Text('Description for item ${index + 1}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
