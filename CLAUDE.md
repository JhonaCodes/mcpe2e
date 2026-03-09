# E2E MCP — AI-driven Flutter E2E Testing

Claude controla una app Flutter real en un dispositivo: toca, escribe, scrollea, verifica — usando MCP tools.

## Arquitectura

```
Claude Code / Claude Desktop
    │
    │  MCP (JSON-RPC 2.0 / stdio)
    ▼
┌─────────────────────────────────┐
│  mcpe2e_server  (Dart)          │  MCP Server — 27 tools
│  Traduce MCP tools → HTTP       │  Binario: bin/server.dart
│  Habla con la app via HTTP      │  TESTBRIDGE_URL=http://localhost:7778
└────────────────┬────────────────┘
                 │  HTTP REST
                 │  localhost:7778 → (forwarding) → device:7777
                 ▼
┌─────────────────────────────────┐
│  mcpe2e  (Dart / Flutter lib)   │  Corre DENTRO de la app Flutter
│  Servidor HTTP en :7777         │  Ejecuta gestos reales en el árbol
│  25 tipos de evento             │  de widgets del dispositivo
│  Inspección del UI sin intrusión│
└─────────────────────────────────┘
```

## Dos componentes independientes

| Componente | Qué es | Protocolo | Ubicación |
|------------|--------|-----------|-----------|
| **mcpe2e** | Flutter library — HTTP server embebido en la app | HTTP (recibe) | `./mcpe2e/` |
| **mcpe2e_server** | MCP server — traduce tools MCP a llamadas HTTP | MCP stdio + HTTP (envía) | `./mcpe2e_server/` |

> `mcpe2e` **no es** un MCP server. Es un servidor HTTP que corre dentro del dispositivo y ejecuta gestos reales sobre los widgets de la app.

## Quick Start

### 1. Agregar mcpe2e a tu app Flutter

```yaml
# pubspec.yaml (dev_dependencies)
dev_dependencies:
  mcpe2e:
    path: /ruta/a/mcpe2e
```

### 2. Registrar widgets e iniciar el servidor

```dart
import 'package:mcpe2e/mcpe2e.dart';
import 'package:flutter/foundation.dart';

// Definir keys (McpMetadataKey extiende Key — úsala directamente en el widget)
const loginEmail = McpMetadataKey(
  id: 'auth.email_field',
  widgetType: McpWidgetType.textField,
  description: 'Email input on login screen',
  screen: 'LoginScreen',
);

const loginButton = McpMetadataKey(
  id: 'auth.login_button',
  widgetType: McpWidgetType.button,
  description: 'Login submit button',
  screen: 'LoginScreen',
);

// Registrar y arrancar (solo en debug/profile)
void initE2E() {
  if (!kDebugMode && !kProfileMode) return;
  McpEvents.instance.registerWidget(loginEmail);
  McpEvents.instance.registerWidget(loginButton);
  McpEventServer.start(); // escucha en :7777
}

// Usar la key directamente en el widget
ElevatedButton(
  key: loginButton,          // McpMetadataKey extends Key
  onPressed: _handleLogin,
  child: const Text('Login'),
)

TextField(
  key: loginEmail,
  controller: _emailController,
)
```

### 3. Conectar el dispositivo

```bash
# Android: ADB forward
adb forward tcp:7778 tcp:7777

# Verificar
curl http://localhost:7778/ping
# → {"status":"ok","port":7777}
```

### 4. Iniciar mcpe2e_server y registrarlo en Claude

```bash
cd mcpe2e_server
dart compile exe bin/server.dart -o mcpe2e

# Registrar con Claude Code
claude mcp add mcpe2e \
  --command /ruta/a/mcpe2e_server/mcpe2e \
  --env TESTBRIDGE_URL=http://localhost:7778
```

### 5. Usar desde Claude

Claude puede llamar MCP tools directamente:
- `get_app_context` → ver widgets registrados en pantalla
- `inspect_ui` → ver TODOS los widgets con valores (sin registro previo)
- `capture_screenshot` → ver la pantalla como imagen
- `tap_widget key=auth.login_button` → tap real en el botón
- `input_text key=auth.email_field text=user@test.com` → escribir en el campo
- `assert_text key=auth.error text="Email inválido"` → verificar texto

## Conectividad por plataforma

| Plataforma | Mecanismo | Comando |
|------------|-----------|---------|
| Android | ADB forward | `adb forward tcp:7778 tcp:7777` |
| iOS | iproxy | `iproxy 7778 7777` |
| Desktop (macOS/Linux/Win) | Directo | sin forwarding — `TESTBRIDGE_URL=http://localhost:7777` |
| Web | No soportado | Flutter Web no puede abrir sockets TCP |

> `McpConnectivity.setup()` configura el forwarding automáticamente al iniciar `McpEventServer.start()`.

## MCP Tools (27 total)

### Contexto e inspección

| Tool | Descripción | HTTP |
|------|-------------|------|
| `get_app_context` | Widgets registrados con metadata y capabilities | `GET /mcp/context` |
| `list_test_cases` | Alias de get_app_context | `GET /mcp/context` |
| `inspect_ui` | Árbol completo de widgets con valores/estados (sin registro) | `GET /mcp/tree` |
| `capture_screenshot` | Pantalla actual como imagen PNG (debug/profile only) | `GET /mcp/screenshot` |

### Gestos

| Tool | Descripción |
|------|-------------|
| `tap_widget` | Tap simple |
| `double_tap_widget` | Doble tap |
| `long_press_widget` | Tap sostenido |
| `swipe_widget` | Deslizamiento (up/down/left/right) |
| `scroll_widget` | Scroll en lista |
| `scroll_until_visible` | Scroll hasta que un widget sea visible |
| `tap_by_label` | Tap buscando por texto visible |

### Input

| Tool | Descripción |
|------|-------------|
| `input_text` | Escribir en TextField |
| `clear_text` | Limpiar TextField |
| `select_dropdown` | Seleccionar opción de DropdownButtonFormField |
| `toggle_widget` | Checkbox / Switch / Radio |
| `set_slider_value` | Posicionar Slider (0.0–1.0) |

### Teclado y navegación

| Tool | Descripción |
|------|-------------|
| `hide_keyboard` | Cerrar teclado virtual |
| `press_back` | Navegar atrás |
| `wait` | Pausa (útil post-animación) |

### Aserciones

| Tool | Descripción |
|------|-------------|
| `assert_exists` | Widget registrado existe |
| `assert_text` | Texto visible coincide |
| `assert_visible` | Widget visible en viewport |
| `assert_enabled` | Widget habilitado |
| `assert_selected` | Checkbox/Switch/Radio activo |
| `assert_value` | Valor del controller de un TextField |
| `assert_count` | Cantidad de hijos de Column/Row/ListView |

## Convención de IDs

```
module.elemento[.variante]

auth.login_button           Botón de login
auth.email_field            Campo email
order.form.price            Campo precio en formulario
order.card.{uuid}           Card dinámico con ID
state.loading_indicator     Indicador de carga
screen.dashboard            Identificador de pantalla
modal.confirm.delete        Modal/diálogo
```

## Endpoints HTTP (mcpe2e Flutter lib)

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/ping` | GET | Health check — `{"status":"ok","port":7777}` |
| `/mcp/context` | GET | Widgets registrados con metadata |
| `/mcp/tree` | GET | Árbol completo (sin registro) |
| `/mcp/screenshot` | GET | Pantalla como PNG base64 |
| `/action?key=...&type=...` | GET | Ejecutar evento con query params |
| `/event` | POST | Ejecutar evento con JSON body |
| `/widgets` | GET | Lista de IDs (`?metadata=true` para full) |

## Seguridad en producción

- `McpEventServer.start()` retorna inmediatamente si no estamos en debug/profile
- `capture_screenshot` retorna `{"error":"not_available_in_release"}` en release
- El servidor nunca inicia a menos que se llame explícitamente a `start()`

## Documentación detallada

- `docs/integration-guide.md` — Integración paso a paso en cualquier app Flutter
- `docs/test-flow-example.md` — Walkthrough completo de un test con Claude
- `mcpe2e/README.md` — API reference de la Flutter library
- `mcpe2e_server/` — MCP server (ver pubspec.yaml y bin/server.dart)
