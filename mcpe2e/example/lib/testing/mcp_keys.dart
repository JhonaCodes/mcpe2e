import 'package:mcpe2e/mcpe2e.dart';

/// All MCP-testable widget keys for this example app.
///
/// Convention: `module.element[.variant]`
///
/// McpMetadataKey extends Flutter's Key, so each constant can be assigned
/// directly to a widget's `key` parameter — no extra wiring needed.
abstract class McpKeys {
  // ── Login screen ────────────────────────────────────────────────────────────

  static const loginEmail = McpMetadataKey(
    id: 'auth.email_field',
    widgetType: McpWidgetType.textField,
    description: 'Email input on login screen',
    screen: 'LoginScreen',
  );

  static const loginPassword = McpMetadataKey(
    id: 'auth.password_field',
    widgetType: McpWidgetType.textField,
    description: 'Password input on login screen',
    screen: 'LoginScreen',
  );

  static const loginButton = McpMetadataKey(
    id: 'auth.login_button',
    widgetType: McpWidgetType.button,
    description: 'Submit login credentials',
    screen: 'LoginScreen',
  );

  static const loginError = McpMetadataKey(
    id: 'auth.error_message',
    widgetType: McpWidgetType.text,
    description: 'Login error message',
    screen: 'LoginScreen',
  );

  // ── Dashboard screen ────────────────────────────────────────────────────────

  static const screenDashboard = McpMetadataKey(
    id: 'screen.dashboard',
    widgetType: McpWidgetType.container,
    description: 'Dashboard screen identifier',
    screen: 'DashboardScreen',
  );

  static const dashboardWelcome = McpMetadataKey(
    id: 'dashboard.welcome_text',
    widgetType: McpWidgetType.text,
    description: 'Welcome message on dashboard',
    screen: 'DashboardScreen',
  );

  static const dashboardSettingsButton = McpMetadataKey(
    id: 'dashboard.settings_button',
    widgetType: McpWidgetType.button,
    description: 'Navigate to settings',
    screen: 'DashboardScreen',
  );

  static const dashboardItemList = McpMetadataKey(
    id: 'dashboard.item_list',
    widgetType: McpWidgetType.list,
    description: 'Scrollable list of items',
    screen: 'DashboardScreen',
  );

  /// Dynamic key for each item in the list.
  static McpMetadataKey dashboardItem(int index) => McpMetadataKey(
    id: 'dashboard.item.$index',
    widgetType: McpWidgetType.card,
    description: 'List item at index $index',
    screen: 'DashboardScreen',
  );

  // ── Settings screen ─────────────────────────────────────────────────────────

  static const screenSettings = McpMetadataKey(
    id: 'screen.settings',
    widgetType: McpWidgetType.container,
    description: 'Settings screen identifier',
    screen: 'SettingsScreen',
  );

  static const settingsNotifications = McpMetadataKey(
    id: 'settings.notifications_switch',
    widgetType: McpWidgetType.switchWidget,
    description: 'Enable/disable push notifications',
    screen: 'SettingsScreen',
  );

  static const settingsDarkMode = McpMetadataKey(
    id: 'settings.dark_mode_checkbox',
    widgetType: McpWidgetType.checkbox,
    description: 'Enable/disable dark mode',
    screen: 'SettingsScreen',
  );

  static const settingsVolume = McpMetadataKey(
    id: 'settings.volume_slider',
    widgetType: McpWidgetType.slider,
    description: 'Volume level (0.0 to 1.0)',
    screen: 'SettingsScreen',
  );

  static const settingsLogoutButton = McpMetadataKey(
    id: 'settings.logout_button',
    widgetType: McpWidgetType.button,
    description: 'Log out of the app',
    screen: 'SettingsScreen',
  );
}
