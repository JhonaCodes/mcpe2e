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
    return utf8.decode(response.bodyBytes);
  }

  /// POST [path] con JSON [body] → retorna response body como String (forzando UTF-8).
  Future<String> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return utf8.decode(response.bodyBytes);
  }
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
        'Obtiene el estado actual de la app: pantalla activa y todos los widgets '
        'registrados con sus IDs, tipos y acciones disponibles (capabilities). '
        'Llama esto primero para saber qué hay en pantalla antes de ejecutar acciones.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'list_test_cases',
    'description': 'Alias de get_app_context. Lista los widgets registrados en la app.',
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
    'description': 'Scroll de un widget scrollable (ListView, SingleChildScrollView, etc.).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del widget scrollable'},
        'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
      },
      'required': ['key', 'direction'],
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
    'description': 'Escribe texto en un TextField o TextFormField.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del campo de texto'},
        'text': {'type': 'string', 'description': 'Texto a escribir'},
        'clear_first': {'type': 'boolean', 'description': 'Limpiar campo antes de escribir (default: false)'},
      },
      'required': ['key', 'text'],
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
    'description': 'Activa o desactiva un Checkbox, Switch o Radio button.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID del Checkbox, Switch o Radio'},
      },
      'required': ['key'],
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
        'Navega atrás en el stack de navegación. '
        'Equivale al botón Back de Android o al gesto de back de iOS.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'ID de cualquier widget en la pantalla actual'},
      },
      'required': ['key'],
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
        'Recorre el widget tree completo de la app y retorna todos los widgets '
        'con datos: textos visibles, valores de campos, estados de botones, '
        'checkboxes, switches, slider values, etc. '
        'No requiere widgets registrados — funciona con cualquier widget. '
        'Usar para: verificar valores en pantalla, detectar estados incorrectos, '
        'identificar qué hay visible antes de ejecutar acciones.',
    'inputSchema': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'capture_screenshot',
    'description':
        'Captura la pantalla actual como imagen PNG. '
        'Usar para: detectar problemas visuales, layout roto, colores incorrectos '
        'o verificación visual general. '
        'Solo disponible en debug/profile mode (retorna error en release). '
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
    'get_app_context' || 'list_test_cases' =>
      bridge.get('/mcp/context').then(t),

    // ── Gestos básicos ────────────────────────────────────────────────────────
    'tap_widget' =>
      bridge.get('/action?key=${k(args['key'])}').then(t),

    'double_tap_widget' =>
      bridge.get('/action?key=${k(args['key'])}&type=doubletap').then(t),

    'long_press_widget' => () {
        final ms = args['duration_ms'] as int? ?? 500;
        return bridge.get('/action?key=${k(args['key'])}&type=longpress&duration=$ms').then(t);
      }(),

    'swipe_widget' => () {
        final key = k(args['key'] as String);
        final dir = args['direction'] as String;
        final dist = args['distance'] as num?;
        final q = dist != null ? '&distance=$dist' : '';
        return bridge.get('/action?key=$key&type=swipe&direction=$dir$q').then(t);
      }(),

    'scroll_widget' => () {
        final dir = args['direction'] as String;
        return bridge.get('/action?key=${k(args['key'])}&type=scroll&direction=$dir').then(t);
      }(),

    'tap_at' => () {
        final x = args['x'] as num;
        final y = args['y'] as num;
        return bridge.get('/action?key=_&type=tapat&dx=$x&dy=$y').then(t);
      }(),

    'tap_by_label' => () {
        final label = Uri.encodeQueryComponent(args['label'] as String);
        return bridge.get('/action?key=_&type=tapbylabel&label=$label').then(t);
      }(),

    // ── Input ─────────────────────────────────────────────────────────────────
    'input_text' => () {
        final text = Uri.encodeQueryComponent(args['text'] as String);
        final clear = (args['clear_first'] as bool? ?? false) ? '&clearFirst=true' : '';
        return bridge.get('/action?key=${k(args['key'])}&type=textinput&text=$text$clear').then(t);
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

    'toggle_widget' =>
      bridge.get('/action?key=${k(args['key'])}&type=toggle').then(t),

    'set_slider_value' => () {
        final val = args['value'] as num;
        return bridge.get('/action?key=${k(args['key'])}&type=setslidervalue&sliderValue=$val').then(t);
      }(),

    // ── Teclado y navegación ──────────────────────────────────────────────────
    'hide_keyboard' =>
      bridge.get('/action?key=_keyboard&type=hidekeyboard').then(t),

    'press_back' =>
      bridge.get('/action?key=${k(args['key'])}&type=pressback').then(t),

    'scroll_until_visible' => () {
        final key = k(args['key'] as String);
        final target = Uri.encodeQueryComponent(args['target_key'] as String);
        final maxA = args['max_attempts'] as int? ?? 20;
        return bridge.get('/action?key=$key&type=scrolluntilvisible&targetKey=$target&maxScrollAttempts=$maxA').then(t);
      }(),

    // ── Utilidades ────────────────────────────────────────────────────────────
    'wait' => () async {
        final ms = args['duration_ms'] as int;
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
        final ms = args['duration_ms'] as int? ?? 500;
        final dx = args['dx'] as num;
        final dy = args['dy'] as num;
        return bridge.get(
          '/action?key=${k(args['key'])}&type=drag&deltaX=$dx&deltaY=$dy&duration=$ms',
        ).then(t);
      }(),

    'pinch_widget' => () {
        final scale = args['scale'] as num;
        return bridge.get(
          '/action?key=${k(args['key'])}&type=pinch&scale=$scale',
        ).then(t);
      }(),

    'show_keyboard' =>
      bridge.get('/action?key=${k(args['key'])}&type=showkeyboard').then(t),

    // ── Inspección del UI ──────────────────────────────────────────────────────
    'inspect_ui' =>
      bridge.get('/mcp/tree').then(t),

    'capture_screenshot' => () async {
        final raw = await bridge.get('/mcp/screenshot');
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json.containsKey('error')) return t('Error: ${json['error']}');
        return img(json['base64'] as String);
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
      final result = Process.runSync('adb', ['devices']);
      if (result.exitCode != 0) {
        return t('Error: adb not found. Install Android SDK platform-tools.');
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
        Process.runSync('adb', ['-s', serial, 'forward', 'tcp:$port', 'tcp:7777']);
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
