// ── DeviceRegistry ────────────────────────────────────────────────────────────
// Manages one FlutterBridge per connected device.
// The "active" bridge is what all MCP tools communicate with.
//
// On startup, one default bridge is created from TESTBRIDGE_URL (backward compat).
// After calling list_devices, devices discovered via ADB are added here.
// select_device switches which bridge is "active".
// ─────────────────────────────────────────────────────────────────────────────

import 'tools.dart';

class DeviceRegistry {
  final Map<String, FlutterBridge> _devices = {};
  String? _activeSerial;

  // Constructed with the default TESTBRIDGE_URL bridge (backward compat)
  DeviceRegistry(String defaultUrl) {
    _devices['default'] = FlutterBridge(defaultUrl);
    _activeSerial = 'default';
  }

  // The bridge currently in use by all tools
  FlutterBridge get active => _devices[_activeSerial]!;

  // Register a discovered device
  void register(String serial, String localUrl) {
    _devices[serial] = FlutterBridge(localUrl);
  }

  // Switch active device. Returns false if serial unknown.
  bool select(String serial) {
    if (!_devices.containsKey(serial)) return false;
    _activeSerial = serial;
    return true;
  }

  String get activeSerial => _activeSerial ?? 'default';
  List<String> get serials => _devices.keys.toList();
}
