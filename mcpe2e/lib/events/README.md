# 🎯 Sistema de Eventos MCP

Sistema estandarizado de eventos para E2E testing en Flutter.

## 📐 Arquitectura

```
McpEventType (enum)
    ├─ tap
    ├─ longPress
    ├─ textInput
    ├─ swipe
    ├─ scroll
    ├─ hideKeyboard
    ├─ showKeyboard
    ├─ wait
    ├─ assertExists
    ├─ assertText
    ├─ doubleTap
    ├─ drag
    └─ pinch

McpEvents (singleton)
    └─ Switch exhaustivo sobre McpEventType
    └─ Registro centralizado de widgets
```

## 🚀 Uso Básico

### 1. Registrar Widgets

```dart
class _MyWidgetState extends State<MyWidget> {
  final _buttonKey = GlobalKey();
  final _textFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // Registrar widgets con McpEvents
    McpEvents.instance.registerWidget('my_button', _buttonKey);
    McpEvents.instance.registerWidget('my_textfield', _textFieldKey);
  }

  @override
  void dispose() {
    McpEvents.instance.unregisterWidget('my_button');
    McpEvents.instance.unregisterWidget('my_textfield');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(key: _textFieldKey),
        ElevatedButton(key: _buttonKey, onPressed: () {}),
      ],
    );
  }
}
```

### 2. Ejecutar Eventos

```dart
final mcpEvents = McpEvents.instance;

// Tap simple
await mcpEvents.executeEvent(
  widgetKey: 'my_button',
  eventType: McpEventType.tap,
);

// Long press
await mcpEvents.executeEvent(
  widgetKey: 'my_button',
  eventType: McpEventType.longPress,
  params: McpEventParams(duration: Duration(seconds: 2)),
);

// Escribir texto
await mcpEvents.executeEvent(
  widgetKey: 'my_textfield',
  eventType: McpEventType.textInput,
  params: McpEventParams(text: 'Hello World', clearFirst: true),
);

// Swipe
await mcpEvents.executeEvent(
  widgetKey: 'my_list',
  eventType: McpEventType.swipe,
  params: McpEventParams(direction: 'up', distance: 200),
);

// Ocultar teclado
await mcpEvents.executeEvent(
  widgetKey: '', // No necesita key
  eventType: McpEventType.hideKeyboard,
);

// Esperar
await mcpEvents.executeEvent(
  widgetKey: '',
  eventType: McpEventType.wait,
  params: McpEventParams(duration: Duration(seconds: 1)),
);

// Assert
await mcpEvents.executeEvent(
  widgetKey: 'my_button',
  eventType: McpEventType.assertExists,
);
await mcpEvents.executeEvent(
  widgetKey: 'my_text',
  eventType: McpEventType.assertText,
  params: McpEventParams(expectedText: 'Expected'),
);
```

## 📊 Eventos Disponibles

### TapEvent
Simula un tap simple en un widget.

```dart
TapEvent('widget_key')
```

### LongPressEvent
Simula un tap sostenido.

```dart
LongPressEvent(
  'widget_key',
  duration: Duration(milliseconds: 500), // Opcional
)
```

### TextInputEvent
Escribe texto en un TextField.

```dart
TextInputEvent(
  'textfield_key',
  'Texto a escribir',
  clearFirst: true, // Opcional: limpiar antes
)
```

### SwipeEvent
Simula un deslizamiento.

```dart
SwipeEvent(
  'widget_key',
  SwipeDirection.left, // left, right, up, down
  distance: 300.0,     // Opcional: distancia en pixels
  duration: Duration(milliseconds: 300), // Opcional
)
```

### ScrollEvent
Simula scroll con deltas específicos.

```dart
ScrollEvent(
  'scrollable_key',
  deltaX: 0.0,
  deltaY: -100.0, // Scroll hacia arriba
)
```

### HideKeyboardEvent
Oculta el teclado.

```dart
HideKeyboardEvent()
```

### ShowKeyboardEvent
Muestra el teclado enfocando un widget.

```dart
ShowKeyboardEvent('textfield_key')
```

### WaitEvent
Espera un tiempo específico.

```dart
WaitEvent(Duration(seconds: 2))
```

### AssertExistsEvent
Verifica que un widget existe.

```dart
AssertExistsEvent('widget_key')
```

### AssertTextEvent
Verifica el texto de un widget.

```dart
AssertTextEvent('text_widget_key', 'Expected text')
```

## 🔄 Integración con HTTP Server

El sistema se integra automáticamente con el CommandServer:

```bash
# Tap en un botón
curl "http://localhost:7778/action?key=my_button"

# Próximamente: eventos más complejos vía JSON
curl -X POST "http://localhost:7778/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"text_input","key":"my_textfield","text":"Hello"}'
```

## 🎯 Pattern Matching

Gracias a las sealed classes, el switch es exhaustivo y type-safe:

```dart
Future<bool> executeEvent(McpEvent event) async {
  return switch (event) {
    TapEvent() => _executeTap(event),
    LongPressEvent() => _executeLongPress(event),
    TextInputEvent() => _executeTextInput(event),
    // ... el compilador te obliga a cubrir TODOS los casos
  };
}
```

## 🧪 Testing

```dart
void main() {
  testWidgets('Tap button test', (tester) async {
    await tester.pumpWidget(MyApp());

    final executor = McpEventsExecutor.instance;

    // Ejecutar tap
    final success = await executor.executeEvent(TapEvent('my_button'));
    expect(success, true);

    await tester.pump();
    // Verificar resultado...
  });
}
```

## 🔧 Extensión

Para agregar un nuevo evento:

1. Agregar el evento a `McpEvent` (sealed class)
2. Implementar el handler en `McpEventsExecutor`
3. El compilador te obligará a actualizar el switch

```dart
// 1. En mcp_event.dart
class DoubleTapEvent extends McpEvent {
  final String widgetKey;
  const DoubleTapEvent(this.widgetKey);
}

// 2. En mcp_events_executor.dart
Future<bool> executeEvent(McpEvent event) async {
  return switch (event) {
    // ... otros eventos
    DoubleTapEvent() => _executeDoubleTap(event), // OBLIGATORIO
  };
}

Future<bool> _executeDoubleTap(DoubleTapEvent event) async {
  // Implementación...
}
```

## 📝 Ventajas

✅ **Type-safe**: El compilador valida todos los casos
✅ **Exhaustivo**: No puedes olvidar ningún evento
✅ **Extensible**: Fácil agregar nuevos eventos
✅ **Testeable**: Cada evento se puede probar individualmente
✅ **Documentado**: Los tipos son autoexplicativos
✅ **Performante**: Pattern matching es muy eficiente

## 🔐 Seguridad

⚠️ **IMPORTANTE**: Este sistema solo debe usarse en modo DEBUG.

El CommandServer ya tiene esta restricción:
```dart
if (kDebugMode) {
  await CommandServer.start();
}
```