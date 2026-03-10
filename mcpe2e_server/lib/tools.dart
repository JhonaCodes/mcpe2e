// ─────────────────────────────────────────────────────────────────────────────
// tools.dart — Herramientas MCP que Claude puede invocar
//
// Define las 25 herramientas disponibles y las traduce a llamadas HTTP
// contra el servidor embebido en la app Flutter (McpEventServer).
//
// Flujo por herramienta:
//   Claude llama tool → protocol.dart extrae nombre y args →
//   callTool() traduce a HTTP GET/POST → FlutterBridge lo envía →
//   McpEventServer en la app ejecuta el evento → retorna resultado
//
// URL base: TESTBRIDGE_URL (e.g. http://localhost:7778 con ADB forward,
//           o http://localhost:7777 en desktop)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'device_registry.dart';

// ── ADB path resolution ───────────────────────────────────────────────────────
// The MCP binary runs in a clean environment without the user's shell PATH.
// Search common Android SDK locations before falling back to bare 'adb'.

String findAdb() {
  final home = Platform.environment['HOME'] ?? '';

  // 1. Explicit SDK env vars
  for (final envKey in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final base = Platform.environment[envKey];
    if (base != null && base.isNotEmpty) {
      final candidate = '$base/platform-tools/adb';
      if (File(candidate).existsSync()) return candidate;
    }
  }

  // 2. Common macOS / Linux locations
  final candidates = [
    '$home/Library/Android/sdk/platform-tools/adb', // macOS default
    '$home/Android/Sdk/platform-tools/adb',         // Linux default
    '/usr/local/share/android-sdk/platform-tools/adb',
    '/opt/android-sdk/platform-tools/adb',
    '/usr/local/bin/adb',
    '/opt/homebrew/bin/adb',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  // 3. Try 'which adb' as last resort
  try {
    final which = Process.runSync('which', ['adb']);
    if (which.exitCode == 0) return (which.stdout as String).trim();
  } catch (_) {}

  return 'adb'; // will fail with a clear ProcessException
}

// ── HTTP Bridge ───────────────────────────────────────────────────────────────

/// Cliente HTTP hacia el servidor embebido en la app Flutter.
///
/// [baseUrl] apunta a donde el McpEventServer escucha.
/// En Android: http://localhost:7778 (ADB forward device:7777)
/// En desktop: http://localhost:7777 (sin forwarding)
class FlutterBridge {
  final String baseUrl;
  final http.Client _client = http.Client();

  FlutterBridge(this.baseUrl);

  /// GET [path] → retorna response body como String (forzando UTF-8).
  Future<String> get(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    return response.body;
  }

  /// POST [path] con JSON [body] → retorna response body como String (forzando UTF-8).
  Future<String> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return response.body;
  }
}

// ── Auto-fallback helper ──────────────────────────────────────────────────────

/// Ejecuta [action] usando el key registrado. Si Flutter devuelve un error,
/// busca el widget por su campo [key] en el árbol vivo y hace tap_at en su
/// centro como fallback.
///
/// Aplica a: toggle_widget, tap_widget, double_tap_widget,
///           long_press_widget, show_keyboard.
Future<List<Map<String, dynamic>>> _withCoordFallback({
  required String key,
  required Future<String> Function() action,
  required FlutterBridge bridge,
}) async {
  final result = await action();
  // Success path — return immediately
  if (!result.contains('Error:') && !result.toLowerCase().contains('falló')) {
    return [{'type': 'text', 'text': result}];
  }
  // Fallback: find widget by key in live tree, tap its center
  try {
    final tree = await bridge.get('/mcp/tree');
    final treeData = jsonDecode(tree) as Map<String, dynamic>;
    final widgets =
        (treeData['widgets'] as List? ?? []).cast<Map<String, dynamic>>();
    final w = widgets.firstWhere((w) => w['key'] == key, orElse: () => {});
    if (w.isNotEmpty) {
      final cx = (w['x'] as num) + (w['w'] as num) / 2;
      final cy = (w['y'] as num) + (w['h'] as num) / 2;
      final tap =
          await bridge.get('/action?key=_&type=tapat&dx=$cx&dy=$cy');
      return [
        {
          'type': 'text',
          'text':
              'fallback_tap(${cx.toStringAsFixed(1)},${cy.toStringAsFixed(1)}): $tap',
        }
      ];
    }
  } catch (_) {}
  return [{'type': 'text', 'text': result}]; // original error if nothing worked
}

// ── Loading-aware wait helper ─────────────────────────────────────────────────

/// Espera a que no haya ningún indicador de carga visible en el árbol.
///
/// Estrategia:
///   1. Chequea el árbol inmediatamente (cero overhead en pantallas sin loading).
///   2. Si hay loading, re-chequea cada [pollMs] ms hasta [timeoutMs].
///   3. Retorna null si quedó idle, o un mensaje de timeout si el loading no desapareció.
///
/// Detecta: CircularProgressIndicator, LinearProgressIndicator,
///          RefreshProgressIndicator, y cualquier widget con "loading": true.
Future<String?> _waitForIdle(
  FlutterBridge bridge, {
  int pollMs = 300,
  int timeoutMs = 10000,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  var firstCheck = true;

  while (DateTime.now().isBefore(deadline)) {
    try {
      final tree = await bridge.get('/mcp/tree');
      final data = jsonDecode(tree) as Map<String, dynamic>;
      final widgets =
          (data['widgets'] as List? ?? []).cast<Map<String, dynamic>>();
      final isLoading = widgets.any((w) => w['loading'] as bool? ?? false);
      if (!isLoading) return null; // idle — sin carga
    } catch (_) {
      return null; // no se puede checar → asumir idle
    }

    if (firstCheck) {
      firstCheck = false;
      // Primera vez que encontró loading: espera corta antes del primer poll
      await Future.delayed(const Duration(milliseconds: 150));
    } else {
      await Future.delayed(Duration(milliseconds: pollMs));
    }
  }
  return 'loading_timeout_${timeoutMs}ms';
}

/// Ejecuta [action], luego espera a que el UI quede idle (sin loading).
/// Si hay timeout de loading, agrega una advertencia al resultado.
Future<List<Map<String, dynamic>>> _thenWaitIdle(
  Future<List<Map<String, dynamic>>> action,
  FlutterBridge bridge,
) async {
  final result = await action;
  final warn = await _waitForIdle(bridge);
  if (warn == null) return result;
  return [
    ...result,
    {'type': 'text', 'text': 'warn: UI still loading after ${warn.replaceAll('loading_timeout_', '')} — consider adding a wait.'},
  ];
}

// ── Definiciones de herramientas ──────────────────────────────────────────────

/// Las 25 herramientas MCP que Claude puede invocar.
///
/// Cada entrada sigue el esquema JSON-Schema de MCP para tool definitions.
final List<Map<String, dynamic>> toolDefinitions = [

  // ── Contexto ───────────────────────────────────────────────────────────────

  {
    'name': 'get_app_context',
    'description':
        'Obtiene el estado actual de la app: pantalla activa y widgets que tienen '
        'McpMetadataKey registrada (campo "key" presente). '
        'Úsalo para descubrir qué keys están activas ANTES de ejecutar herramientas key-based. '
        'Para ver TODOS los widgets con coordenadas x/y, usa inspect_ui. '
        'Flujo recomendado: get_app_context (saber qué keys hay) → '
        'inspect_ui (coordenadas de cualquier widget) → acciones.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'list_test_cases',
    'description': 'Alias de get_app_context. Lista los widgets registrados con McpMetadataKey.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },

  // ── Gestos básicos ─────────────────────────────────────────────────────────

  {
    'name': 'tap_widget',
    'description': 'Tap simple en un widget. Equivale a un toque del usuario.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget (e.g. "auth.login_button")'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'double_tap_widget',
    'description': 'Doble tap en un widget. Útil para zoom u otras acciones de doble toque.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'long_press_widget',
    'description': 'Tap sostenido. Activa menús contextuales y acciones de hold.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget'},
        'duration_ms': {'type': 'integer', 'description': 'Duración en ms (default: 500)'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'swipe_widget',
    'description': 'Deslizamiento sobre un widget. Útil para swipe-to-delete, carousels, etc.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget'},
        'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
        'distance': {'type': 'number', 'description': 'Distancia en px (default: 300)'},
      },
      'required': ['key', 'direction'],
    },
  },
  {
    'name': 'scroll_widget',
    'description':
        'Scroll de un widget scrollable (ListView, SingleChildScrollView, etc.). '
        'key es opcional — si se omite, el scroll se aplica al widget scrollable activo en pantalla. '
        'amount/distance: píxeles a desplazar (default: 300).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget scrollable (opcional)'},
        'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
        'amount': {'type': 'number', 'description': 'Píxeles a desplazar (alias de distance, default: 300)'},
        'distance': {'type': 'number', 'description': 'Píxeles a desplazar (default: 300)'},
      },
      'required': ['direction'],
    },
  },
  {
    'name': 'tap_at',
    'description':
        'Tap en coordenadas absolutas de pantalla (logical pixels). '
        'Útil para widgets sin ID registrado: cards dinámicas, items de lista, etc. '
        'Obtén las coordenadas con inspect_ui (campos x, y del nodo) o capture_screenshot. '
        'Las coordenadas corresponden a la esquina superior izquierda del widget; '
        'para tapear el centro suma width/2 y height/2.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'number', 'description': 'Coordenada X en logical pixels'},
        'y': {'type': 'number', 'description': 'Coordenada Y en logical pixels'},
      },
      'required': ['x', 'y'],
    },
  },
  {
    'name': 'tap_by_label',
    'description':
        'Tap en un widget buscándolo por su texto visible. '
        'Útil cuando el widget no tiene ID registrado pero tiene texto reconocible '
        '(e.g. opciones de un dropdown custom, items de menú).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'label': {'type': 'string', 'description': 'Texto visible del widget a tapear'},
      },
      'required': ['label'],
    },
  },

  // ── Input ──────────────────────────────────────────────────────────────────

  {
    'name': 'input_text',
    'description':
        'Escribe texto en un TextField o TextFormField. '
        'Modo coordenadas (PREFERIDO, siempre disponible): proporciona x/y del campo '
        'obtenidos de inspect_ui — enfoca el campo por coordenadas y usa ADB para escribir. '
        'Modo key (solo si el widget tiene campo "key" en inspect_ui): proporciona key. '
        'Si se dan x/y, se usan las coordenadas aunque también se pase key. '
        'Flujo: inspect_ui → toma x/y del campo → input_text x: ... y: ... text: "..." '
        'IMPORTANTE: si inspect_ui muestra "auto_focus": true en el campo, '
        'usa skip_focus_tap: true — el teclado ya está abierto y tap_at lo cerraría.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'number', 'description': 'Coordenada X del campo (de inspect_ui) — PREFERIDO'},
        'y': {'type': 'number', 'description': 'Coordenada Y del campo (de inspect_ui) — PREFERIDO'},
        'key': {'type': 'string', 'description': 'ID del campo (solo si tiene campo "key" en inspect_ui)'},
        'text': {'type': 'string', 'description': 'Texto a escribir'},
        'clear_first': {'type': 'boolean', 'description': 'Limpiar campo antes de escribir (default: false)'},
        'skip_focus_tap': {
          'type': 'boolean',
          'description':
              'Omitir el tap de foco antes de escribir (default: false). '
              'Usar true cuando el campo tiene autoFocus: true (visible como "auto_focus": true en inspect_ui) — '
              'el teclado ya está abierto; hacer tap primero lo cerraría.',
        },
      },
      'required': ['text'],
    },
  },
  {
    'name': 'clear_text',
    'description': 'Limpia el contenido de un TextField sin escribir texto nuevo.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del campo a limpiar'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'select_dropdown',
    'description':
        'Selecciona una opción de un DropdownButtonFormField estándar. '
        'Para dropdowns custom (BottomSheet, overlay), usa tap_widget + tap_by_label.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del dropdown'},
        'value': {'type': 'string', 'description': 'Valor a seleccionar (o parte del string del enum)'},
        'index': {'type': 'integer', 'description': 'Índice 0-based (alternativa a value)'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'toggle_widget',
    'description':
        'Activa o desactiva un Checkbox, Switch o Radio button. '
        'Modo coordenadas (PREFERIDO para dialogs/overlays): proporciona x/y '
        'del control (de inspect_ui) — simula tap real que activa gestos del widget. '
        'Modo key: solo si tiene campo "key" en inspect_ui. '
        'Si x/y presentes, se usan las coordenadas aunque también haya key.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'x': {'type': 'number', 'description': 'Coordenada X del control (de inspect_ui) — PREFERIDO'},
        'y': {'type': 'number', 'description': 'Coordenada Y del control (de inspect_ui) — PREFERIDO'},
        'key': {'type': 'string', 'description': 'ID del widget (si tiene campo "key" en inspect_ui)'},
      },
      'required': [],
    },
  },
  {
    'name': 'set_slider_value',
    'description':
        'Posiciona un Slider a un valor relativo entre 0.0 (mínimo) y 1.0 (máximo).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del Slider'},
        'value': {'type': 'number', 'description': 'Valor entre 0.0 y 1.0 (ej: 0.5 = mitad)'},
      },
      'required': ['key', 'value'],
    },
  },

  // ── Teclado y navegación ───────────────────────────────────────────────────

  {
    'name': 'hide_keyboard',
    'description': 'Oculta el teclado virtual.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'press_back',
    'description':
        'Envía el evento Back del sistema operativo (botón físico de Android / gesto de iOS). '
        'ADVERTENCIA: Si la pantalla actual es la pantalla raíz de la app (home/root), '
        'este evento CIERRA la aplicación. '
        'ANTES de llamar press_back, llama inspect_ui y busca: '
        '(1) un widget de tipo BackButton, ArrowBackButton, o IconButton con tooltip "Back", '
        '(2) el botón leading del AppBar — usa tap_at con sus coordenadas en su lugar. '
        'Usa press_back SOLO cuando no haya botón de back visible en la pantalla '
        'o cuando quieras cerrar un diálogo/overlay con el gesto del sistema.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID de cualquier widget (opcional)'},
      },
      'required': [],
    },
  },
  {
    'name': 'scroll_until_visible',
    'description':
        'Scrollea un widget contenedor hasta que el widget objetivo sea visible en pantalla. '
        'Usa esto cuando necesitas interactuar con un widget que está fuera del viewport.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget scrollable (ListView, etc.)'},
        'target_key': {'type': 'string', 'description': 'ID del widget que debe quedar visible'},
        'max_attempts': {'type': 'integer', 'description': 'Máximo de intentos de scroll (default: 20)'},
      },
      'required': ['key', 'target_key'],
    },
  },

  // ── Utilidades ─────────────────────────────────────────────────────────────

  {
    'name': 'wait',
    'description': 'Espera un tiempo antes de continuar. Útil después de animaciones o transiciones.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'duration_ms': {'type': 'integer', 'description': 'Tiempo de espera en milisegundos'},
      },
      'required': ['duration_ms'],
    },
  },

  // ── Aserciones ─────────────────────────────────────────────────────────────

  {
    'name': 'assert_exists',
    'description': 'Verifica que el widget está registrado. No requiere que esté visible.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget a verificar'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_text',
    'description': 'Verifica que el texto visible de un widget coincide con el esperado.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget'},
        'text': {'type': 'string', 'description': 'Texto esperado (match exacto)'},
      },
      'required': ['key', 'text'],
    },
  },
  {
    'name': 'assert_visible',
    'description':
        'Verifica que el widget está completamente visible en el viewport actual. '
        'Falla si el widget está off-screen o tapado.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_enabled',
    'description': 'Verifica que el widget está habilitado (no disabled).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget (Button, TextField, Checkbox, etc.)'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_selected',
    'description': 'Verifica que un Checkbox, Switch o Radio está seleccionado/activado.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del Checkbox, Switch o Radio'},
      },
      'required': ['key'],
    },
  },
  {
    'name': 'assert_value',
    'description':
        'Verifica el valor del TextEditingController de un TextField. '
        'A diferencia de assert_text, verifica el valor interno del campo, no el label.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del TextField'},
        'value': {'type': 'string', 'description': 'Valor esperado en el controller'},
      },
      'required': ['key', 'value'],
    },
  },
  {
    'name': 'assert_count',
    'description': 'Verifica que un Column, Row o ListView tiene exactamente N hijos.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget contenedor'},
        'count': {'type': 'integer', 'description': 'Cantidad esperada de hijos'},
      },
      'required': ['key', 'count'],
    },
  },

  // ── Drag, pinch, show keyboard ─────────────────────────────────────────────

  {
    'name': 'drag_widget',
    'description':
        'Drags a widget by a relative pixel offset from its center. '
        'dx > 0 = right, dx < 0 = left, dy > 0 = down, dy < 0 = up. '
        'Useful for drag-to-reorder, pull-to-refresh, and custom drag targets.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID to drag from'},
        'dx': {'type': 'number', 'description': 'Horizontal pixel offset (positive = right)'},
        'dy': {'type': 'number', 'description': 'Vertical pixel offset (positive = down)'},
        'duration_ms': {'type': 'integer', 'description': 'Drag duration in ms (default: 500)'},
      },
      'required': ['key', 'dx', 'dy'],
    },
  },
  {
    'name': 'pinch_widget',
    'description':
        'Pinch zoom gesture on a widget. scale > 1.0 zooms in (spread), scale < 1.0 zooms out (pinch). '
        'Note: pinch requires dual-pointer simulation — not yet implemented on the Flutter side; '
        'this will return false until implemented.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID to pinch'},
        'scale': {'type': 'number', 'description': 'Scale factor (e.g. 2.0 = double size, 0.5 = half)'},
      },
      'required': ['key', 'scale'],
    },
  },
  {
    'name': 'show_keyboard',
    'description':
        'Requests focus on a widget to show the virtual keyboard. '
        'Use before input_text if the keyboard is not appearing automatically. '
        'Pair with hide_keyboard to dismiss it after input.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'Widget ID of the focusable field'},
      },
      'required': ['key'],
    },
  },

  // ── Inspección del UI ──────────────────────────────────────────────────────

  {
    'name': 'inspect_ui',
    'description':
        'Recorre el widget tree completo y retorna TODOS los widgets con: '
        'texto visible, x/y/w/h (coordenadas en logical pixels), tipo, estado. '
        'Widgets con McpMetadataKey tienen además un campo "key" — '
        'ese campo indica que la herramienta puede usarse con key-based tools (assert_*, tap_widget, etc.). '
        'Sin campo "key": usa coordenadas → tap_at, input_text con x/y. '
        'Con campo "key": puedes usar tanto coordenadas como el key. '
        'SIEMPRE llama inspect_ui antes de input_text para obtener las coordenadas x/y del campo. '
        'Widgets dentro de dialogs, BottomSheets o AlertDialogs tienen "overlay": true — '
        'identifica qué widgets pertenecen al diálogo activo. '
        'TextFields con "auto_focus": true ya tienen el foco al aparecer — '
        'usa input_text con skip_focus_tap: true para no interrumpir el teclado. '
        'CircularProgressIndicator, LinearProgressIndicator y RefreshProgressIndicator '
        'tienen "loading": true — si aparecen, la UI está ocupada; '
        'las herramientas de acción esperan automáticamente hasta que desaparezcan.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'inspect_ui_compact',
    'description':
        'Versión compacta de inspect_ui: agrupa los widgets en secciones '
        'INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING con centros pre-calculados. '
        'Usa esto cuando la pantalla es simple y quieres ahorrar tokens. '
        'Para pantallas complejas o widgets custom (third-party), usa inspect_ui '
        'para obtener el JSON completo con todos los widgets y coordenadas exactas.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'capture_screenshot',
    'description':
        'Captura la pantalla actual como imagen PNG. '
        'Usar para: detectar problemas visuales, layout roto, colores incorrectos '
        'o verificación visual general. '
        'En Android usa ADB screencap (siempre disponible, debug y release). '
        'En desktop usa el layer tree de Flutter (solo debug/profile). '
        'Para verificar valores de datos, prefer inspect_ui (más eficiente en tokens).',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },

  // ── Ejecución de comandos ──────────────────────────────────────────────────

  {
    'name': 'run_command',
    'description':
        'Run any shell command, optionally in a working directory. '
        'Supports any CLI tool: flutter run, flutter build, dart pub get, adb, etc. '
        'Use background:true for long-running processes (e.g. flutter run) — returns '
        'immediately with the PID. Use background:false (default) to wait and capture '
        'stdout/stderr — suitable for finite commands (build, pub get, analyze, etc.). '
        'Supports pipes, &&, and shell features via sh -c. '
        'Examples: '
        '"flutter run -d emulator-5554 --flavor dev" (background:true), '
        '"flutter pub get" (background:false), '
        '"dart analyze" (background:false).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'Shell command to execute. Supports pipes, &&, env vars, quotes.',
        },
        'working_dir': {
          'type': 'string',
          'description': 'Absolute path to run the command in (e.g. Flutter project root).',
        },
        'background': {
          'type': 'boolean',
          'description':
              'Run detached in background (default: false). '
              'Set true for long-running processes like flutter run. '
              'Set false to wait and capture output.',
        },
      },
      'required': ['command'],
    },
  },

  // ── Multi-device ───────────────────────────────────────────────────────────

  {
    'name': 'list_devices',
    'description': 'Discover connected Android devices and emulators via ADB. '
        'Automatically sets up port forwarding for each device and checks '
        'whether mcpe2e is running. Returns the list with their serial IDs, status, '
        'and the active screen name when available. '
        'Call this first when testing on multiple devices.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'select_device',
    'description': 'Switch the active target device. All subsequent tool calls '
        '(tap, input, assert, etc.) will be directed to this device. '
        'Use list_devices first to see available device IDs.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'device_id': {
          'type': 'string',
          'description': 'Device serial from list_devices (e.g. "emulator-5554")',
        },
      },
      'required': ['device_id'],
    },
  },
];

// ── Implementación de herramientas ────────────────────────────────────────────

/// Ejecuta la herramienta [name] con los argumentos [args] via HTTP a la app.
///
/// Retorna un MCP content array:
/// - Texto: `[{"type":"text","text":"..."}]`
/// - Imagen: `[{"type":"image","data":"<base64>","mimeType":"image/png"}]`
///
/// Traduce cada tool a la llamada HTTP correspondiente:
/// - Gestos simples → GET /action?key=...&type=...
/// - Aserciones → POST /event con JSON
/// - wait → Future.delayed local (sin HTTP)
/// - inspect_ui → GET /mcp/tree (texto JSON)
/// - capture_screenshot → GET /mcp/screenshot (imagen PNG)
///
/// La función NO es async: cada rama del switch retorna directamente un
/// Future<List<...>> para mantener consistencia de tipos en el switch expression.
Future<List<Map<String, dynamic>>> callTool(
    DeviceRegistry registry, String name, Map<String, dynamic> args) {
  final bridge = registry.active; // all 29 existing cases use this — zero changes needed below

  // Helper: envolver texto en MCP content array
  List<Map<String, dynamic>> t(String s) => [{'type': 'text', 'text': s}];

  // Helper: envolver imagen en MCP content array
  List<Map<String, dynamic>> img(String base64) =>
      [{'type': 'image', 'data': base64, 'mimeType': 'image/png'}];

  // Helper: encode key para URL
  String k(String key) => Uri.encodeQueryComponent(key);

  return switch (name) {

    // ── Contexto ─────────────────────────────────────────────────────────────
    'get_app_context' || 'list_test_cases' => () async {
      final ctx = await bridge.get('/mcp/context');
      final data = jsonDecode(ctx) as Map<String, dynamic>;
      // If screen is unknown (no McpMetadataKey on root), enrich with AppBar
      // title from the live widget tree so the LLM always has a screen name.
      final screen = (data['screen'] as String?) ?? '';
      if (screen.toLowerCase().contains('unknown') || screen.isEmpty) {
        try {
          final tree = await bridge.get('/mcp/tree');
          final treeData = jsonDecode(tree) as Map<String, dynamic>;
          final widgets =
              (treeData['widgets'] as List? ?? []).cast<Map<String, dynamic>>();
          final appBar =
              widgets.where((w) => w['type'] == 'AppBar').firstOrNull;
          final title = appBar?['title'] as String?;
          if (title != null) {
            data['screen'] = title;
            data['note'] =
                'Screen inferred from AppBar. Register McpMetadataKey on '
                'the root widget for stable screen IDs.';
          }
        } catch (_) {}
      }
      return t(jsonEncode(data));
    }(),

    // ── Gestos básicos ────────────────────────────────────────────────────────
    'tap_widget' =>
      _thenWaitIdle(
        _withCoordFallback(
          key: args['key'] as String,
          action: () => bridge.get('/action?key=${k(args['key'] as String)}'),
          bridge: bridge,
        ),
        bridge,
      ),

    'double_tap_widget' =>
      _thenWaitIdle(
        _withCoordFallback(
          key: args['key'] as String,
          action: () =>
              bridge.get('/action?key=${k(args['key'] as String)}&type=doubletap'),
          bridge: bridge,
        ),
        bridge,
      ),

    'long_press_widget' => () {
        final ms = _toIntOpt(args['duration_ms']) ?? 500;
        return _thenWaitIdle(
          _withCoordFallback(
            key: args['key'] as String,
            action: () => bridge.get(
                '/action?key=${k(args['key'] as String)}&type=longpress&duration=$ms'),
            bridge: bridge,
          ),
          bridge,
        );
      }(),

    'swipe_widget' => () {
        final key = k(args['key'] as String);
        final dir = args['direction'] as String;
        final dist = _toNumOpt(args['distance']);
        final q = dist != null ? '&distance=$dist' : '';
        return bridge.get('/action?key=$key&type=swipe&direction=$dir$q').then(t);
      }(),

    'scroll_widget' => () async {
        final dir = args['direction'] as String;
        final rawKey = args['key'] as String?;
        // accept both 'amount' and 'distance' as aliases
        final dist = (_toNumOpt(args['amount']) ?? _toNumOpt(args['distance']) ?? 300).toDouble();

        // No key → ADB swipe directly (no registered widget needed)
        if (rawKey == null || rawKey.isEmpty) {
          // Standard portrait screen center — swipe from/to based on direction
          // "down" = content scrolls down = finger swipes up (start low, end high)
          const cx = 540.0;
          const cy = 960.0;
          double x1 = cx, y1 = cy, x2 = cx, y2 = cy;
          switch (dir) {
            case 'down':  y1 = cy + dist / 2; y2 = cy - dist / 2;
            case 'up':    y1 = cy - dist / 2; y2 = cy + dist / 2;
            case 'right': x1 = cx + dist / 2; x2 = cx - dist / 2;
            case 'left':  x1 = cx - dist / 2; x2 = cx + dist / 2;
          }
          final adb = findAdb();
          final serial = registry.activeSerial;
          final base = serial == 'default' ? <String>[] : ['-s', serial];
          final r = Process.runSync(
              adb, [...base, 'shell', 'input', 'swipe',
                '${x1.round()}', '${y1.round()}',
                '${x2.round()}', '${y2.round()}', '600']);
          return t(jsonEncode({
            'ok': r.exitCode == 0,
            'method': 'adb_swipe',
            'direction': dir,
            'distance': dist,
            if (r.exitCode != 0) 'stderr': r.stderr,
          }));
        }

        // Key provided → try Flutter bridge
        final q = '&distance=$dist';
        return _thenWaitIdle(
          bridge.get('/action?key=${k(rawKey)}&type=scroll&direction=$dir$q').then(t),
          bridge,
        );
      }(),

    'tap_at' => () {
        final x = _toNum(args['x']);
        final y = _toNum(args['y']);
        return _thenWaitIdle(
          bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y').then(t),
          bridge,
        );
      }(),

    'tap_by_label' => () {
        final label = Uri.encodeQueryComponent(args['label'] as String);
        return _thenWaitIdle(
          bridge.get('/action?key=_&type=tapbylabel&label=$label').then(t),
          bridge,
        );
      }(),

    // ── Input ─────────────────────────────────────────────────────────────────
    'input_text' => () async {
        final text = args['text'] as String;
        final clear = args['clear_first'] as bool? ?? false;
        final x = args['x'] as num?;
        final y = args['y'] as num?;
        final key = args['key'] as String?;

        // Coordinate-based (preferred): tap to focus + ADB to type
        if (x != null && y != null) {
          final skipTap = args['skip_focus_tap'] as bool? ?? false;

          if (!skipTap) {
            // Focus field by tapping at coordinates
            await bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y');
            await Future.delayed(const Duration(milliseconds: 300));
          }

          if (clear) {
            // KEYCODE_DEL repeated — avoids coordinate-shift from triple-tap
            final adb = findAdb();
            final serial = registry.activeSerial;
            final base = serial == 'default' ? <String>[] : ['-s', serial];
            for (int i = 0; i < 8; i++) {
              Process.runSync(
                  adb, [...base, 'shell', 'input', 'keyevent', 'KEYCODE_DEL']);
            }
            await Future.delayed(const Duration(milliseconds: 200));
          }

          final adb = findAdb();
          final serial = registry.activeSerial;
          final base = serial == 'default' ? <String>[] : ['-s', serial];
          final result =
              Process.runSync(adb, [...base, 'shell', 'input', 'text', text]);
          if (result.exitCode != 0) {
            return t('Error: ADB input text failed. ${result.stderr}');
          }
          return await _thenWaitIdle(
            Future.value(t(jsonEncode({
              'ok': true,
              'method': 'coordinates',
              'x': x,
              'y': y,
              if (skipTap) 'skipped_focus_tap': true,
            }))),
            bridge,
          );
        }

        // Key-based fallback (only when widget has McpMetadataKey)
        if (key == null || key.isEmpty) {
          return t('Error: provide x/y coordinates (from inspect_ui) or a registered key.');
        }
        final encodedText = Uri.encodeQueryComponent(text);
        final clearParam = clear ? '&clearFirst=true' : '';
        return _thenWaitIdle(
          bridge
              .get('/action?key=${k(key)}&type=textinput&text=$encodedText$clearParam')
              .then(t),
          bridge,
        );
      }(),

    'clear_text' =>
      bridge.get('/action?key=${k(args['key'])}&type=cleartext').then(t),

    'select_dropdown' => () {
        final key = k(args['key'] as String);
        if (args.containsKey('index')) {
          return bridge.get('/action?key=$key&type=selectdropdown&dropdownIndex=${args['index']}').then(t);
        }
        final val = Uri.encodeQueryComponent(args['value'] as String? ?? '');
        return bridge.get('/action?key=$key&type=selectdropdown&dropdownValue=$val').then(t);
      }(),

    'toggle_widget' => () async {
        final x = args['x'] as num?;
        final y = args['y'] as num?;
        final key = args['key'] as String?;

        // Coordinate mode (preferred — real pointer event triggers gestures natively)
        if (x != null && y != null) {
          return _thenWaitIdle(
            bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y').then(
                (r) => [{'type': 'text', 'text': r}]),
            bridge,
          );
        }

        // Key mode with auto-fallback
        if (key == null || key.isEmpty) {
          return [
            {
              'type': 'text',
              'text': 'Error: provide x/y coordinates or a registered key.',
            }
          ];
        }
        return _thenWaitIdle(
          _withCoordFallback(
            key: key,
            action: () => bridge.get('/action?key=${k(key)}&type=toggle'),
            bridge: bridge,
          ),
          bridge,
        );
      }(),

    'set_slider_value' => () {
        final val = _toNum(args['value']);
        return bridge.get('/action?key=${k(args['key'])}&type=setslidervalue&sliderValue=$val').then(t);
      }(),

    // ── Teclado y navegación ──────────────────────────────────────────────────
    'hide_keyboard' =>
      bridge.get('/action?key=_keyboard&type=hidekeyboard').then(t),

    'press_back' => () async {
        // Smart back: prefer tapping the AppBar leading/back button over
        // the system back event, which closes the app on the root screen.
        try {
          final tree = await bridge.get('/mcp/tree');
          final data = jsonDecode(tree) as Map<String, dynamic>;
          final widgets = (data['widgets'] as List? ?? []).cast<Map<String, dynamic>>();

          // Look for a visible back button in the AppBar area (y < 120 logical px)
          final backWidget = widgets.firstWhere(
            (w) {
              final type    = (w['type'] as String?) ?? '';
              final tooltip = ((w['tooltip'] as String?) ?? '').toLowerCase();
              final label   = ((w['label']   as String?) ?? '').toLowerCase();
              final y       = (w['y'] as num?) ?? 9999;
              final isBackType = type == 'BackButton' ||
                  type == 'ArrowBackButton' ||
                  (type == 'IconButton' && (tooltip.contains('back') || tooltip.contains('atrás') || label.contains('back')));
              return isBackType && y < 200;
            },
            orElse: () => <String, dynamic>{},
          );

          if (backWidget.isNotEmpty) {
            // Tap the visual back button instead of the system event
            final x  = (backWidget['x'] as num).toDouble();
            final y  = (backWidget['y'] as num).toDouble();
            final w  = (backWidget['w'] as num?)?.toDouble() ?? 48;
            final h  = (backWidget['h'] as num?)?.toDouble() ?? 48;
            final cx = (x + w / 2).round();
            final cy = (y + h / 2).round();
            return _thenWaitIdle(
              bridge.post('/action', {'type': 'tapAt', 'dx': cx, 'dy': cy}).then(t),
              bridge,
            );
          }
        } catch (_) {
          // Fall through to system back on any error
        }

        final key = args['key'] as String? ?? '_';
        return _thenWaitIdle(
          bridge.get('/action?key=${k(key)}&type=pressback').then(t),
          bridge,
        );
      }(),

    'scroll_until_visible' => () {
        final key = k(args['key'] as String);
        final target = Uri.encodeQueryComponent(args['target_key'] as String);
        final maxA = _toIntOpt(args['max_attempts']) ?? 20;
        return bridge.get('/action?key=$key&type=scrolluntilvisible&targetKey=$target&maxScrollAttempts=$maxA').then(t);
      }(),

    // ── Utilidades ────────────────────────────────────────────────────────────
    'wait' => () async {
        final ms = _toInt(args['duration_ms']);
        await Future.delayed(Duration(milliseconds: ms));
        return t(jsonEncode({'ok': true, 'waited_ms': ms}));
      }(),

    // ── Aserciones ────────────────────────────────────────────────────────────
    'assert_exists' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertExists', 'params': {}}).then(t),

    'assert_text' =>
      bridge.post('/event', {
        'key': args['key'],
        'type': 'assertText',
        'params': {'expectedText': args['text']},
      }).then(t),

    'assert_visible' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertVisible', 'params': {}}).then(t),

    'assert_enabled' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertEnabled', 'params': {}}).then(t),

    'assert_selected' =>
      bridge.post('/event', {'key': args['key'], 'type': 'assertSelected', 'params': {}}).then(t),

    'assert_value' =>
      bridge.post('/event', {
        'key': args['key'],
        'type': 'assertValue',
        'params': {'expectedText': args['value']},
      }).then(t),

    'assert_count' =>
      bridge.post('/event', {
        'key': args['key'],
        'type': 'assertCount',
        'params': {'expectedCount': args['count']},
      }).then(t),

    // ── Drag, pinch, show keyboard ────────────────────────────────────────────
    'drag_widget' => () {
        final ms = _toIntOpt(args['duration_ms']) ?? 500;
        final dx = _toNum(args['dx']);
        final dy = _toNum(args['dy']);
        return bridge.get(
          '/action?key=${k(args['key'])}&type=drag&deltaX=$dx&deltaY=$dy&duration=$ms',
        ).then(t);
      }(),

    'pinch_widget' => () {
        final scale = _toNum(args['scale']);
        return bridge.get(
          '/action?key=${k(args['key'])}&type=pinch&scale=$scale',
        ).then(t);
      }(),

    'show_keyboard' =>
      _withCoordFallback(
        key: args['key'] as String,
        action: () =>
            bridge.get('/action?key=${k(args['key'] as String)}&type=showkeyboard'),
        bridge: bridge,
      ),

    // ── Inspección del UI ──────────────────────────────────────────────────────
    // Returns raw JSON widget tree — full fidelity, all widget types visible.
    'inspect_ui' =>
      bridge.get('/mcp/tree').then((raw) => t(raw)),

    // Compact grouped summary: INTERACTIVE / TEXT / OTHER / OVERLAY / LOADING.
    // Token-efficient for simple screens; use inspect_ui for custom/third-party widgets.
    'inspect_ui_compact' =>
      bridge.get('/mcp/tree').then((raw) => t(_compactTree(raw))),

    'capture_screenshot' => () async {
        // ── Android: ADB screencap (primary — reliable in debug and release) ──
        // adb exec-out screencap -p → raw PNG bytes to stdout (no shell encoding)
        final adb = findAdb();
        final serial = registry.activeSerial;
        final base = serial == 'default' ? <String>[] : ['-s', serial];
        final adbResult = Process.runSync(
          adb,
          [...base, 'exec-out', 'screencap', '-p'],
          stdoutEncoding: null, // null = List<int>, avoids UTF-8 corruption of binary
        );
        if (adbResult.exitCode == 0) {
          final bytes = adbResult.stdout as List<int>;
          // Verify PNG magic bytes (89 50 4E 47) to confirm valid output
          if (bytes.length > 4 &&
              bytes[0] == 0x89 && bytes[1] == 0x50 &&
              bytes[2] == 0x4E && bytes[3] == 0x47) {
            return img(base64Encode(bytes));
          }
        }

        // ── Desktop fallback: Flutter layer tree (debug/profile only) ──
        try {
          final raw = await bridge.get('/mcp/screenshot');
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json.containsKey('error')) return t('Error: ${json['error']}');
          return img(json['base64'] as String);
        } catch (e) {
          return t('Error: screenshot failed. ADB not available and Flutter capture failed: $e');
        }
      }(),

    // ── Ejecución de comandos ─────────────────────────────────────────────────
    'run_command' => () async {
      final command = args['command'] as String? ?? '';
      final workingDir = args['working_dir'] as String?;
      final background = args['background'] as bool? ?? false;

      if (command.isEmpty) return t('Error: command is required');

      if (background) {
        // Detached — does not block MCP, suitable for flutter run
        final process = await Process.start(
          'sh', ['-c', command],
          workingDirectory: workingDir,
          mode: ProcessStartMode.detached,
        );
        return t(jsonEncode({
          'ok': true,
          'pid': process.pid,
          'command': command,
          if (workingDir != null) 'working_dir': workingDir,
          'background': true,
          'note': 'Process started in background. '
              'Call list_devices in ~15s to verify the app is ready.',
        }));
      } else {
        // Foreground — waits and captures output
        final result = await Process.run(
          'sh', ['-c', command],
          workingDirectory: workingDir,
        );
        return t(jsonEncode({
          'exit_code': result.exitCode,
          if ((result.stdout as String).isNotEmpty) 'stdout': result.stdout,
          if ((result.stderr as String).isNotEmpty) 'stderr': result.stderr,
        }));
      }
    }(),

    // ── Multi-device ──────────────────────────────────────────────────────────
    'list_devices' => () async {
      final adb = findAdb();
      final result = Process.runSync(adb, ['devices']);
      if (result.exitCode != 0) {
        return t('Error: adb not found. Tried PATH and common SDK locations. '
            'Set ANDROID_HOME or install Android SDK platform-tools.');
      }

      final lines = (result.stdout as String)
          .split('\n')
          .skip(1) // skip "List of devices attached"
          .where((l) => l.trim().isNotEmpty && l.contains('\t'))
          .toList();

      if (lines.isEmpty) {
        return t('No devices connected. Connect a device or start an emulator.');
      }

      // Find next free local port starting from [base], skipping occupied ones.
      Future<int> nextFreePort(int base) async {
        var p = base;
        while (p < 65535) {
          try {
            final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
            await s.close();
            return p; // port was free
          } catch (_) {
            p++; // port occupied, try next
          }
        }
        throw Exception('No free ports available above $base');
      }

      final devices = <Map<String, dynamic>>[];
      int nextPort = 7778;

      for (final line in lines) {
        final serial = line.split('\t').first.trim();
        final state = line.split('\t').last.trim(); // "device" | "offline"

        if (state != 'device') {
          devices.add({'serial': serial, 'status': 'offline'});
          continue;
        }

        // Find a free local port before forwarding
        final port = await nextFreePort(nextPort);
        nextPort = port + 1; // next device starts above this one

        // Forward port
        Process.runSync(adb, ['-s', serial, 'forward', 'tcp:$port', 'tcp:7777']);
        final url = 'http://localhost:$port';

        // Ping — confirm mcpe2e is running
        String status = 'mcpe2e_not_running';
        String? screen;
        try {
          final client = http.Client();
          final resp = await client
              .get(Uri.parse('$url/ping'))
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) {
            status = 'ready';
            registry.register(serial, url);
            // Bonus: read active screen from app context
            try {
              final ctx = await client
                  .get(Uri.parse('$url/mcp/context'))
                  .timeout(const Duration(seconds: 2));
              final ctxJson = jsonDecode(ctx.body) as Map<String, dynamic>;
              screen = ctxJson['screen'] as String?;
            } catch (_) {}
          }
          client.close();
        } catch (_) {}

        devices.add({
          'serial': serial,
          'port': port,
          'url': url,
          'status': status,
          if (screen != null) 'screen': screen,
        });
      }

      // Auto-select first ready device if active is still 'default'
      if (registry.activeSerial == 'default') {
        final first = devices.firstWhere(
          (d) => d['status'] == 'ready',
          orElse: () => {},
        );
        if (first.isNotEmpty) registry.select(first['serial'] as String);
      }

      return t(jsonEncode({'devices': devices, 'active': registry.activeSerial}));
    }(),

    'select_device' => () async {
      final id = args['device_id'] as String? ?? '';
      if (id.isEmpty) return t('Error: device_id is required');
      final ok = registry.select(id);
      if (!ok) return t('Error: device "$id" not found. Call list_devices first.');
      return t(jsonEncode({
        'ok': true,
        'active_device': id,
        'url': registry.active.baseUrl,
      }));
    }(),

    _ => Future.error(Exception('Herramienta desconocida: $name')),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// _compactTree — formato compacto para inspect_ui
//
// Transforma el JSON plano del árbol de widgets en texto accionable para el LLM.
// Reduce ~90% los tokens respecto al JSON verboso original.
//
// Estructura del output:
//   Screen: <AppBar title> (<N> widgets)
//
//   INTERACTIVE:          ← botones, campos, toggles, sliders, dropdowns
//     Type  label  →  tap_at(cx, cy)   [disabled] [overlay]
//
//   TEXT:                 ← texto visible no interactivo
//     "value"
//
//   OVERLAY [depth: N]:   ← diálogos y bottom sheets activos
//     AlertDialog  "título"
//     ElevatedButton "OK"  →  tap_at(cx, cy)  [overlay]
//
//   LOADING: none | CircularProgressIndicator
//
// El campo depth se preserva SOLO para widgets overlay, donde indica la capa
// del diálogo y ayuda al LLM a distinguir elementos del diálogo vs pantalla.
// Para widgets normales, depth es ruido y se omite.
// ─────────────────────────────────────────────────────────────────────────────

String _compactTree(String rawJson) {
  try {
    final data = jsonDecode(rawJson) as Map<String, dynamic>;
    final all =
        (data['widgets'] as List? ?? []).cast<Map<String, dynamic>>();

    if (all.isEmpty) return 'Screen: empty (0 widgets)';

    // AppBar title → screen name
    final appBar = all.where((w) => w['type'] == 'AppBar').firstOrNull;
    final screen = appBar?['title'] as String? ?? 'unknown';

    const interactiveTypes = {
      // Buttons
      'ElevatedButton', 'TextButton', 'OutlinedButton', 'FilledButton',
      'FilledButton.tonal', 'FloatingActionButton', 'FloatingActionButton.extended',
      'IconButton', 'BackButton', 'CloseButton', 'DrawerButton',
      'CupertinoButton',
      // Text input
      'TextField', 'TextFormField', 'CupertinoTextField', 'SearchBar',
      'SearchAnchor',
      // Toggles
      'Checkbox', 'CheckboxListTile', 'Switch', 'SwitchListTile',
      'Radio', 'RadioListTile', 'CupertinoSwitch',
      // Sliders / pickers
      'Slider', 'RangeSlider', 'CupertinoSlider',
      'DatePicker', 'TimePicker', 'CupertinoDatePicker', 'CupertinoTimerPicker',
      // Dropdowns / menus
      'DropdownButton', 'DropdownButtonFormField', 'DropdownMenu',
      'PopupMenuButton', 'MenuAnchor', 'SubmenuButton', 'MenuItemButton',
      // Chips (interactive variants)
      'ActionChip', 'FilterChip', 'ChoiceChip', 'InputChip', 'Chip',
      // List items (tappable)
      'ListTile', 'ExpansionTile',
      // Navigation tabs / steps
      'Tab', 'BottomNavigationBarItem', 'NavigationDestination',
      'Step', 'Stepper',
      // Segmented
      'SegmentedButton', 'CupertinoSegmentedControl',
      'CupertinoSlidingSegmentedControl',
    };

    final mainInteractive = <Map<String, dynamic>>[];
    final mainText        = <Map<String, dynamic>>[];
    final overlayNodes    = <Map<String, dynamic>>[];  // dialogs + their children
    final loading         = <Map<String, dynamic>>[];
    final otherWidgets    = <Map<String, dynamic>>[];  // custom/third-party widgets

    // Types that are structural noise (containers, layout, rendering) — not shown in OTHER.
    // Anything NOT in this set and NOT in interactiveTypes / Text / AppBar / loading
    // will appear in the OTHER section so the LLM can see custom/third-party widgets.
    const structuralTypes = {
      // ── Layout multi-child ────────────────────────────────────────────────
      'Column', 'Row', 'Stack', 'Flex', 'Wrap', 'Flow', 'Table',
      'IndexedStack', 'CustomMultiChildLayout', 'OverflowBar',
      // ── Layout single-child ───────────────────────────────────────────────
      'Container', 'SizedBox', 'Padding', 'Align', 'Center',
      'Expanded', 'Flexible', 'Spacer', 'Positioned', 'PositionedDirectional',
      'ConstrainedBox', 'UnconstrainedBox', 'OverflowBox', 'SizedOverflowBox',
      'FractionallySizedBox', 'LimitedBox', 'AspectRatio', 'FittedBox',
      'Baseline', 'IntrinsicHeight', 'IntrinsicWidth',
      'CustomSingleChildLayout', 'Offstage', 'PhysicalModel',
      'Transform', 'RotatedBox', 'FractionalTranslation',
      // ── Scroll ────────────────────────────────────────────────────────────
      'SingleChildScrollView', 'CustomScrollView', 'NestedScrollView',
      'PageView', 'Scrollable', 'ScrollView', 'PrimaryScrollController',
      'ScrollConfiguration', 'ScrollNotificationObserver',
      'RawScrollbar', 'Scrollbar',
      // ── Slivers ───────────────────────────────────────────────────────────
      'SliverList', 'SliverGrid', 'SliverAppBar', 'SliverToBoxAdapter',
      'SliverFillRemaining', 'SliverPadding', 'SliverFixedExtentList',
      'SliverPrototypeExtentList', 'SliverAnimatedList', 'SliverAnimatedGrid',
      'SliverFillViewport', 'SliverPersistentHeader',
      'SliverOverlapAbsorber', 'SliverOverlapInjector',
      'SliverLayoutBuilder', 'CupertinoSliverNavigationBar',
      // ── Animation ─────────────────────────────────────────────────────────
      'AnimatedContainer', 'AnimatedOpacity', 'AnimatedAlign',
      'AnimatedCrossFade', 'AnimatedDefaultTextStyle',
      'AnimatedList', 'AnimatedGrid', 'AnimatedPositioned',
      'AnimatedPositionedDirectional', 'AnimatedSize', 'AnimatedSwitcher',
      'AnimatedPhysicalModel', 'AnimatedTheme', 'AnimatedBuilder',
      'AnimatedWidget', 'TweenAnimationBuilder',
      'DecoratedBoxTransition', 'FadeTransition', 'PositionedTransition',
      'RotationTransition', 'ScaleTransition', 'SizeTransition', 'SlideTransition',
      // ── Clip / Paint ──────────────────────────────────────────────────────
      'ClipRect', 'ClipRRect', 'ClipOval', 'ClipPath',
      'DecoratedBox', 'ColoredBox', 'CustomPaint',
      'BackdropFilter', 'ShaderMask',
      // ── Opacity / Visibility ──────────────────────────────────────────────
      'Opacity', 'Visibility',
      // ── Interaction wrappers (not buttons) ────────────────────────────────
      'GestureDetector', 'InkWell', 'InkResponse', 'MouseRegion',
      'RawGestureDetector', 'Listener', 'AbsorbPointer', 'IgnorePointer',
      'Focus', 'FocusScope', 'FocusTraversalGroup',
      'Actions', 'Shortcuts', 'KeyboardListener', 'RawKeyboardListener',
      'TapRegion', 'TextFieldTapRegion',
      // ── Navigation / Routing ──────────────────────────────────────────────
      'Navigator', 'Overlay', 'WillPopScope', 'PopScope',
      // ── Semantics ─────────────────────────────────────────────────────────
      'Semantics', 'MergeSemantics', 'ExcludeSemantics',
      'BlockSemantics', 'IndexedSemantics',
      // ── State / Lifecycle / DI ────────────────────────────────────────────
      'Builder', 'StatefulBuilder', 'LayoutBuilder', 'OrientationBuilder',
      'FutureBuilder', 'StreamBuilder', 'ValueListenableBuilder',
      'NotificationListener', 'MediaQuery', 'Theme', 'DefaultTextStyle',
      'Directionality', 'Localizations', 'DefaultAssetBundle',
      'DefaultSelectionStyle',
      // ── Scaffold / Navigation shell ───────────────────────────────────────
      'Scaffold', 'SafeArea', 'Material', 'Ink',
      'BottomAppBar', 'BottomNavigationBar', 'NavigationBar',
      'NavigationDrawer', 'NavigationRail', 'Drawer', 'DrawerHeader',
      'TabBar', 'TabBarView', 'DefaultTabController',
      'CupertinoTabBar', 'CupertinoTabScaffold', 'CupertinoPageScaffold',
      'CupertinoNavigationBar',
      // ── Pure visual / non-interactive ────────────────────────────────────
      'Icon', 'Image', 'RawImage', 'Placeholder', 'CircleAvatar',
      'Divider', 'VerticalDivider', 'Badge',
      'RepaintBoundary', 'Hero', 'Tooltip', 'Banner',
      'InteractiveViewer', 'MagnificationGesture',
      // ── Misc ─────────────────────────────────────────────────────────────
      'KeyedSubtree', 'ColorScheme', 'SelectionArea',
      'AutofillGroup', 'RestorationScope', 'UnmanagedRestorationScope',
      'ScrollPositionWithSingleContext',
    };

    for (final w in all) {
      final type      = w['type'] as String;
      final isOverlay = w['overlay'] as bool? ?? false;
      final isLoading = w['loading'] as bool? ?? false;

      if (isLoading) { loading.add(w); continue; }
      if (type == 'AppBar') continue; // shown in header

      if (isOverlay) {
        overlayNodes.add(w);
      } else if (interactiveTypes.contains(type)) {
        mainInteractive.add(w);
      } else if (type == 'Text') {
        mainText.add(w);
      } else if (!structuralTypes.contains(type)) {
        // Custom / third-party widgets — include if they have coordinates
        final hasCoords = w['x'] != null && w['y'] != null;
        if (hasCoords) otherWidgets.add(w);
      }
    }

    final buf = StringBuffer();
    buf.writeln('Screen: $screen (${all.length} widgets)');

    // ── INTERACTIVE ──────────────────────────────────────────────────────────
    if (mainInteractive.isNotEmpty) {
      buf.writeln();
      buf.writeln('INTERACTIVE:');
      for (final w in mainInteractive) {
        buf.writeln(_widgetLine(w, showDepth: false));
      }
    }

    // ── TEXT ─────────────────────────────────────────────────────────────────
    final textValues = mainText
        .map((w) => w['value'] as String? ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    if (textValues.isNotEmpty) {
      buf.writeln();
      buf.writeln('TEXT:');
      for (final v in textValues) {
        buf.writeln('  "$v"');
      }
    }

    // ── OVERLAY ──────────────────────────────────────────────────────────────
    if (overlayNodes.isNotEmpty) {
      // Find the minimum depth of the overlay section (dialog container depth)
      final depths = overlayNodes
          .map((w) => w['depth'] as int? ?? 0)
          .toList()..sort();
      final baseDepth = depths.first;
      buf.writeln();
      buf.writeln('OVERLAY [depth: $baseDepth]:');
      for (final w in overlayNodes) {
        final type = w['type'] as String;
        // Show container widgets (AlertDialog, BottomSheet, SnackBar)
        if (type == 'AlertDialog' || type == 'BottomSheet' || type == 'SnackBar') {
          final title = w['title'] as String? ?? w['content'] as String? ?? '';
          buf.writeln('  $type${title.isNotEmpty ? "  \"$title\"" : ""}');
        } else if (interactiveTypes.contains(type)) {
          buf.writeln(_widgetLine(w, showDepth: true));
        } else if (type == 'Text') {
          final val = w['value'] as String? ?? '';
          if (val.isNotEmpty) buf.writeln('  Text  "$val"');
        }
      }
    }

    // ── OTHER (custom / third-party widgets) ─────────────────────────────────
    if (otherWidgets.isNotEmpty) {
      buf.writeln();
      buf.writeln('OTHER (custom widgets — use tap_at with coordinates):');
      for (final w in otherWidgets) {
        final type   = w['type'] as String;
        final center = _centerCoords(w);
        final key    = w['key'] as String?;
        final label  = w['label'] as String? ?? w['value'] as String? ?? w['hint'] as String?;
        final parts  = StringBuffer('  $type');
        if (key != null && key.isNotEmpty)     parts.write('  key:"$key"');
        if (label != null && label.isNotEmpty) parts.write('  "$label"');
        if (center != null) parts.write('  →  tap_at$center');
        buf.writeln(parts.toString());
      }
    }

    // ── LOADING ──────────────────────────────────────────────────────────────
    buf.writeln();
    buf.write('LOADING: ');
    buf.writeln(
      loading.isEmpty
          ? 'none'
          : loading.map((w) => w['type'] as String).join(', '),
    );

    return buf.toString().trimRight();
  } catch (_) {
    return rawJson; // fallback: raw JSON on any parse error
  }
}

/// Formats a single widget as a compact one-liner.
///
/// Format: `  Type  label  →  tap_at(cx, cy)  [disabled]  [depth:N]`
String _widgetLine(Map<String, dynamic> w, {required bool showDepth}) {
  final type    = w['type'] as String;
  final enabled = w['enabled'] as bool? ?? true;
  final depth   = w['depth'] as int?;
  final label   = _widgetLabel(w);
  final center  = _centerCoords(w);

  final parts = StringBuffer('  $type');
  if (label.isNotEmpty) parts.write('  $label');
  if (center != null)   parts.write('  →  tap_at$center');
  if (!enabled)         parts.write('  [disabled]');
  if (showDepth && depth != null) parts.write('  [depth:$depth]');
  return parts.toString();
}

/// Returns a short human-readable label for the widget's content/state.
String _widgetLabel(Map<String, dynamic> w) {
  final type = w['type'] as String;
  switch (type) {
    case 'TextField':
    case 'TextFormField':
      final val  = w['value'] as String?;
      final hint = w['hint']  as String?;
      if (val != null && val.isNotEmpty) return 'value:"$val"';
      if (hint != null && hint.isNotEmpty) return 'hint:"$hint"';
      return '';
    case 'Checkbox':
    case 'Switch':
      return (w['value'] as bool? ?? false) ? '☑' : '☐';
    case 'Radio':
      return (w['selected'] as bool? ?? false) ? '◉' : '○';
    case 'Slider':
      return 'value=${w['value']}  [${w['min']}..${w['max']}]';
    case 'DropdownButtonFormField':
      final val = w['value'] as String?;
      return val != null && val.isNotEmpty ? '"$val"' : '';
    case 'IconButton':
    case 'PopupMenuButton':
      final tip = w['tooltip'] as String?;
      return tip != null ? '[$tip]' : '';
    default:
      final label = w['label'] as String?;
      return label != null && label.isNotEmpty ? '"$label"' : '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numeric coercion helpers
//
// The LLM occasionally serialises numbers as JSON strings (e.g. "263.8").
// These helpers accept both num and String so every numeric arg is safe.
// ─────────────────────────────────────────────────────────────────────────────

/// Coerces a value from MCP args to [num].
/// Accepts both numeric values and string representations.
num _toNum(dynamic v) => v is num ? v : num.parse(v.toString());

/// Same but returns null when [v] is null.
num? _toNumOpt(dynamic v) => v == null ? null : _toNum(v);

/// Coerces to [int] (rounds if the value is a double or decimal string).
int _toInt(dynamic v) => _toNum(v).round();

/// Same but returns null when [v] is null.
int? _toIntOpt(dynamic v) => v == null ? null : _toInt(v);

/// Calculates the center of a widget from its x/y/w/h fields.
/// Returns `(cx, cy)` as a string, or null if coordinates are missing.
String? _centerCoords(Map<String, dynamic> w) {
  final x  = w['x']  as num?;
  final y  = w['y']  as num?;
  final ww = w['w']  as num?;
  final h  = w['h']  as num?;
  if (x == null || y == null || ww == null || h == null) return null;
  final cx = (x + ww / 2).toStringAsFixed(1);
  final cy = (y + h  / 2).toStringAsFixed(1);
  return '($cx, $cy)';
}
