// ignore_for_file: deprecated_member_use
// ─────────────────────────────────────────────────────────────────────────────
// McpEventExecutor
//
// Motor de ejecución de eventos MCP sobre el árbol de widgets de Flutter.
//
// Recibe un (widgetKey, McpEventType, McpEventParams) y despacha la acción
// correcta: navegar el widget tree, leer estado, simular gestos o ejecutar
// callbacks directamente. Retorna true si tuvo éxito, false si algo falló
// (widget no encontrado, parámetros faltantes, estado inválido).
//
// Depende de:
//   - McpWidgetRegistry: para obtener BuildContext y RenderBox del widget
//   - McpGestureSimulator: para generar eventos de puntero físicos
//
// Flujo general por evento:
//   1. obtener context/renderBox del registry
//   2. caminar el widget tree si es necesario (visitChildElements)
//   3. ejecutar la acción (gesture, callback, assertion)
//   4. esperar rebuild si aplica (Future.delayed)
//   5. retornar bool
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger_rs/logger_rs.dart';

import '../events/mcp_event_type.dart';
import 'mcp_widget_registry.dart';
import 'mcp_gesture_simulator.dart';

// ── Executor ──────────────────────────────────────────────────────────────────

/// Motor de ejecución de los 25 tipos de eventos MCP sobre el widget tree.
///
/// Es la única clase que navega el árbol de widgets de Flutter y ejecuta
/// acciones sobre él. Toda la lógica de "cómo hacer X en Flutter" vive aquí.
class McpEventExecutor {
  final McpWidgetRegistry _registry;
  final McpGestureSimulator _simulator;

  McpEventExecutor(this._registry, this._simulator);

  // ── Despacho principal ────────────────────────────────────────────────────

  /// Ejecuta el evento [eventType] sobre el widget identificado por [widgetKey].
  ///
  /// Retorna true si el evento se ejecutó con éxito.
  /// Retorna false si: el widget no está registrado/montado, faltan parámetros,
  /// o el widget tree no contiene el elemento esperado.
  ///
  /// Los eventos de aserción retornan el resultado de la aserción
  /// (true = aserción cumplida, false = aserción fallida).
  Future<bool> executeEvent({
    required String widgetKey,
    required McpEventType eventType,
    McpEventParams? params,
  }) async {
    Log.i('[Executor] ⚡ $eventType → "$widgetKey"');
    return switch (eventType) {
      // ── Gestos básicos ──────────────────────────────────────────────────
      McpEventType.tap => _tap(widgetKey),
      McpEventType.doubleTap => _doubleTap(widgetKey),
      McpEventType.longPress => _longPress(widgetKey, params),
      McpEventType.swipe => _swipe(widgetKey, params),
      McpEventType.drag => _drag(widgetKey, params),
      McpEventType.scroll => _scroll(widgetKey, params),
      McpEventType.pinch => _pinch(widgetKey, params),
      // ── Texto e input ────────────────────────────────────────────────────
      McpEventType.textInput => _textInput(widgetKey, params),
      McpEventType.clearText => _clearText(widgetKey),
      McpEventType.selectDropdown => _selectDropdown(widgetKey, params),
      McpEventType.toggle => _toggle(widgetKey),
      McpEventType.setSliderValue => _setSliderValue(widgetKey, params),
      // ── Teclado ─────────────────────────────────────────────────────────
      McpEventType.hideKeyboard => _hideKeyboard(),
      McpEventType.showKeyboard => _showKeyboard(widgetKey),
      // ── Navegación ───────────────────────────────────────────────────────
      McpEventType.pressBack => _pressBack(widgetKey),
      // ── Scroll inteligente ───────────────────────────────────────────────
      McpEventType.scrollUntilVisible => _scrollUntilVisible(widgetKey, params),
      McpEventType.tapByLabel => _tapByLabel(params),
      // ── Utilidades ───────────────────────────────────────────────────────
      McpEventType.wait => _wait(params),
      // ── Aserciones ───────────────────────────────────────────────────────
      McpEventType.assertExists => _assertExists(widgetKey),
      McpEventType.assertText => _assertText(widgetKey, params),
      McpEventType.assertVisible => _assertVisible(widgetKey),
      McpEventType.assertEnabled => _assertEnabled(widgetKey),
      McpEventType.assertSelected => _assertSelected(widgetKey),
      McpEventType.assertValue => _assertValue(widgetKey, params),
      McpEventType.assertCount => _assertCount(widgetKey, params),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GESTOS BÁSICOS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tap simple en el centro del widget.
  Future<bool> _tap(String key) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    _simulator.simulateTap(_simulator.centerOf(rb));
    return true;
  }

  /// Dos taps separados por 100ms.
  Future<bool> _doubleTap(String key) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    final center = _simulator.centerOf(rb);
    _simulator.simulateTap(center);
    await Future.delayed(const Duration(milliseconds: 100));
    _simulator.simulateTap(center);
    return true;
  }

  /// Tap sostenido durante [params.duration] (default 500ms).
  Future<bool> _longPress(String key, McpEventParams? params) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    final center = _simulator.centerOf(rb);
    final duration = params?.duration ?? const Duration(milliseconds: 500);

    Log.i('[Executor] ⏱️  LongPress ${duration.inMilliseconds}ms');
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: center, pointer: 1),
    );
    await Future.delayed(duration);
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: center, pointer: 1),
    );
    return true;
  }

  /// Deslizamiento en dirección [params.direction] (up/down/left/right).
  ///
  /// [params.distance] controla cuántos píxeles se desplaza (default 300).
  /// [params.duration] controla la velocidad (default 300ms).
  Future<bool> _swipe(String key, McpEventParams? params) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    final center = _simulator.centerOf(rb);
    final distance = params?.distance ?? 300.0;
    final direction = params?.direction ?? 'up';
    final duration = params?.duration ?? const Duration(milliseconds: 300);

    final end = switch (direction) {
      'left' => center + Offset(-distance, 0),
      'right' => center + Offset(distance, 0),
      'up' => center + Offset(0, -distance),
      'down' => center + Offset(0, distance),
      _ => center + Offset(0, -distance),
    };

    Log.i('[Executor] 👉 Swipe $direction ${distance.toStringAsFixed(0)}px');
    _simulator.simulateSwipe(center, end, duration);
    return true;
  }

  /// Drag desde el widget hasta una posición absoluta [params.targetPosition]
  /// o un offset relativo usando [params.deltaX] / [params.deltaY].
  Future<bool> _drag(String key, McpEventParams? params) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    final center = _simulator.centerOf(rb);
    final duration = params?.duration ?? const Duration(milliseconds: 500);

    final Offset target;
    if (params?.targetPosition != null) {
      target = params!.targetPosition!;
    } else if (params?.deltaX != null || params?.deltaY != null) {
      target = center + Offset(params?.deltaX ?? 0, params?.deltaY ?? 0);
    } else {
      Log.i('[Executor] ❌ drag requiere targetPosition o deltaX/deltaY');
      return false;
    }

    Log.i('[Executor] 🖱️  Drag → $target');
    _simulator.simulateSwipe(center, target, duration);
    return true;
  }

  /// Scroll via PointerScrollEvent (mouse/trackpad).
  ///
  /// Para scroll táctil en dispositivos móviles, usa [_swipe].
  /// [params.direction] acepta 'up'/'down' (además de deltaX/deltaY directo).
  Future<bool> _scroll(String key, McpEventParams? params) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);

    // Permite especificar dirección semántica además de deltas numéricos
    final direction = params?.direction;
    final deltaY = direction == 'down'
        ? 200.0
        : direction == 'up'
        ? -200.0
        : (params?.deltaY ?? 0.0);
    final deltaX = direction == 'right'
        ? 200.0
        : direction == 'left'
        ? -200.0
        : (params?.deltaX ?? 0.0);

    _simulator.simulateScroll(
      _simulator.centerOf(rb),
      deltaX: deltaX,
      deltaY: deltaY,
    );
    return true;
  }

  /// Pinch/zoom — pendiente de implementación.
  ///
  /// Requiere simular dos pointers simultáneos, que GestureBinding admite
  /// pero necesita coordinación de IDs de pointer distintos.
  Future<bool> _pinch(String key, McpEventParams? params) async {
    Log.i('[Executor] ⚠️  Pinch no implementado aún (requiere dual-pointer)');
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXTO E INPUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Escribe texto en un TextField/TextFormField.
  ///
  /// Flujo:
  /// 1. Camina el tree desde el context del widget buscando TextField
  /// 2. Obtiene el TextEditingController
  /// 3. Limpia si [params.clearFirst] es true
  /// 4. Asigna el valor al controller (incluye cursor al final)
  /// 5. Llama onChanged() manualmente para activar form validators
  /// 6. Tap en el widget para enfocar (simula que el usuario tocó el campo)
  Future<bool> _textInput(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null || params?.text == null) {
      Log.i('[Executor] ❌ textInput: context o texto no disponible en "$key"');
      return false;
    }

    Log.i('[Executor] ⌨️  TextInput "${params!.text}" → "$key"');

    TextEditingController? controller;
    void findController(Element el) {
      if (controller != null) return;
      controller = switch (el.widget) {
        TextField w => w.controller,
        TextFormField w => w.controller,
        _ => null,
      };
      if (controller == null) el.visitChildElements(findController);
    }

    context.visitChildElements(findController);

    if (controller == null) {
      Log.i('[Executor] ❌ No se encontró TextEditingController en "$key"');
      return false;
    }

    if (params.clearFirst == true) controller!.clear();

    controller!.value = TextEditingValue(
      text: params.text!,
      selection: TextSelection.collapsed(offset: params.text!.length),
    );

    // Notificar a form validators
    void callOnChanged(Element el) {
      switch (el.widget) {
        case TextField w when w.onChanged != null:
          w.onChanged!(params.text!);
          return;
        case TextFormField w when w.onChanged != null:
          w.onChanged!(params.text!);
          return;
        default:
          el.visitChildElements(callOnChanged);
      }
    }

    context.visitChildElements(callOnChanged);

    // Tap para enfocar
    final rb = _registry.getRenderBox(key);
    if (rb != null) _simulator.simulateTap(_simulator.centerOf(rb));

    await Future.delayed(const Duration(milliseconds: 150));
    Log.i('[Executor] ✅ Texto insertado: "${controller!.text}"');
    return true;
  }

  /// Limpia el contenido de un TextField sin escribir texto nuevo.
  ///
  /// Útil para resetear campos antes de una aserción o antes de escribir.
  Future<bool> _clearText(String key) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);

    TextEditingController? controller;
    void find(Element el) {
      if (controller != null) return;
      controller = switch (el.widget) {
        TextField w => w.controller,
        TextFormField w => w.controller,
        _ => null,
      };
      if (controller == null) el.visitChildElements(find);
    }

    context.visitChildElements(find);

    if (controller == null) return _notFound('$key (TextEditingController)');

    controller!.clear();

    void notifyEmpty(Element el) {
      switch (el.widget) {
        case TextField w when w.onChanged != null:
          w.onChanged!('');
          return;
        case TextFormField w when w.onChanged != null:
          w.onChanged!('');
          return;
        default:
          el.visitChildElements(notifyEmpty);
      }
    }

    context.visitChildElements(notifyEmpty);

    await Future.delayed(const Duration(milliseconds: 100));
    Log.i('[Executor] ✅ Campo limpiado: "$key"');
    return true;
  }

  /// Selecciona una opción de un DropdownButtonFormField.
  ///
  /// No abre el dropdown visualmente — llama onChanged() directamente.
  /// Para dropdowns custom (BottomSheet, overlay), usa tap + tapByLabel.
  ///
  /// Selección por valor: busca coincidencia exacta → contains → sufijo enum
  /// Selección por índice: 0-based, accede directo al item
  Future<bool> _selectDropdown(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);
    if (params?.dropdownValue == null && params?.dropdownIndex == null) {
      Log.i(
        '[Executor] ❌ selectDropdown requiere dropdownValue o dropdownIndex',
      );
      return false;
    }

    dynamic dropdown;
    void Function(dynamic)? onChanged;
    List? items;

    void findDropdown(Element el) {
      if (dropdown != null) return;
      final w = el.widget;
      if (w.runtimeType.toString().startsWith('DropdownButtonFormField')) {
        dropdown = w;
        onChanged = (w as dynamic).onChanged;
        items = (w as dynamic).items?.toList();
        return;
      }
      el.visitChildElements(findDropdown);
    }

    context.visitChildElements(findDropdown);

    if (dropdown == null || onChanged == null || items == null) {
      Log.i('[Executor] ❌ DropdownButtonFormField no encontrado en "$key"');
      return false;
    }

    Log.i('[Executor] 📋 Dropdown con ${items!.length} items');

    // Selección por índice
    if (params!.dropdownIndex != null) {
      final idx = params.dropdownIndex!;
      if (idx < 0 || idx >= items!.length) {
        Log.i(
          '[Executor] ❌ Índice $idx fuera de rango (0..${items!.length - 1})',
        );
        return false;
      }
      onChanged!(items![idx].value);
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }

    // Selección por valor (coincidencia flexible)
    final search = params.dropdownValue!.toLowerCase();
    for (final item in items!) {
      final val = item.value.toString().toLowerCase();
      if (val == search ||
          val.contains(search) ||
          val.split('.').last == search) {
        Log.i('[Executor] ✅ Seleccionando: ${item.value}');
        onChanged!(item.value);
        await Future.delayed(const Duration(milliseconds: 300));
        return true;
      }
    }

    Log.i('[Executor] ❌ No se encontró valor que coincida con "$search"');
    return false;
  }

  /// Activa/desactiva un Checkbox, Switch o Radio.
  ///
  /// Para Checkbox/Switch: invierte el valor actual llamando onChanged(!current).
  /// Para Radio: lo selecciona (llama onChanged con su value).
  Future<bool> _toggle(String key) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);

    bool toggled = false;
    void findToggle(Element el) {
      if (toggled) return;
      switch (el.widget) {
        case Checkbox w when w.onChanged != null:
          w.onChanged!(!(w.value ?? false));
          toggled = true;
        case Switch w when w.onChanged != null:
          w.onChanged!(!w.value);
          toggled = true;
        case Radio w when w.onChanged != null:
          w.onChanged!(w.value);
          toggled = true;
        default:
          el.visitChildElements(findToggle);
      }
    }

    context.visitChildElements(findToggle);

    if (!toggled) {
      Log.i('[Executor] ❌ No se encontró Checkbox/Switch/Radio en "$key"');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  /// Posiciona un Slider al valor [params.sliderValue] (0.0 – 1.0).
  ///
  /// Calcula la posición X dentro del track del Slider y simula un tap ahí.
  /// 0.0 = extremo izquierdo, 1.0 = extremo derecho.
  Future<bool> _setSliderValue(String key, McpEventParams? params) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);

    final value = (params?.sliderValue ?? 0.5).clamp(0.0, 1.0);
    final origin = rb.localToGlobal(Offset.zero);
    final tapPos = Offset(
      origin.dx + rb.size.width * value,
      origin.dy + rb.size.height / 2,
    );

    Log.i('[Executor] 🎚️  Slider → ${(value * 100).toStringAsFixed(0)}%');
    _simulator.simulateTap(tapPos);
    await Future.delayed(const Duration(milliseconds: 150));
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TECLADO Y NAVEGACIÓN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Oculta el teclado virtual via el canal de plataforma TextInput.
  Future<bool> _hideKeyboard() async {
    Log.i('[Executor] ⌨️↓ HideKeyboard');
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    return true;
  }

  /// Muestra el teclado solicitando foco al scope del widget.
  Future<bool> _showKeyboard(String key) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);
    Log.i('[Executor] ⌨️↑ ShowKeyboard');
    FocusScope.of(context).requestFocus();
    return true;
  }

  /// Navega atrás usando Navigator.pop().
  ///
  /// Intenta pop desde el Navigator más cercano al widget [key].
  /// Si no hay Navigator disponible o no puede popear, usa SystemNavigator.pop()
  /// (equivale al botón físico Back en Android).
  Future<bool> _pressBack(String key) async {
    Log.i('[Executor] ◀️  PressBack');
    final context = _registry.getContext(key);
    if (context != null) {
      final nav = Navigator.maybeOf(context);
      if (nav != null && nav.canPop()) {
        nav.pop();
        return true;
      }
    }
    await SystemNavigator.pop();
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCROLL INTELIGENTE Y LABEL TAP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scrollea el widget [key] hasta que el widget [params.targetKey] sea visible.
  ///
  /// Algoritmo:
  /// 1. Verifica si targetKey ya está en viewport
  /// 2. Si no, emite PointerScrollEvent de 200px hacia abajo
  /// 3. Espera 150ms para que el layout se actualice
  /// 4. Repite hasta [params.maxScrollAttempts] veces (default 20)
  ///
  /// Retorna true si el target quedó visible, false si se agotaron los intentos.
  Future<bool> _scrollUntilVisible(String key, McpEventParams? params) async {
    final targetKey = params?.targetKey;
    if (targetKey == null) {
      Log.i('[Executor] ❌ scrollUntilVisible requiere params.targetKey');
      return false;
    }
    final scrollRb = _registry.getRenderBox(key);
    if (scrollRb == null) return _notFound(key);

    final maxAttempts = params?.maxScrollAttempts ?? 20;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenH = view.physicalSize.height / view.devicePixelRatio;
    final screenW = view.physicalSize.width / view.devicePixelRatio;

    Log.i(
      '[Executor] 📜➡️  ScrollUntilVisible "$targetKey" (max $maxAttempts)',
    );

    for (int i = 0; i < maxAttempts; i++) {
      final targetRb = _registry.getRenderBox(targetKey);
      if (targetRb != null) {
        final pos = targetRb.localToGlobal(Offset.zero);
        if (pos.dy >= 0 &&
            pos.dy + targetRb.size.height <= screenH &&
            pos.dx >= 0 &&
            pos.dx + targetRb.size.width <= screenW) {
          Log.i('[Executor] ✅ Visible tras $i scrolls');
          return true;
        }
      }
      _simulator.simulateScroll(_simulator.centerOf(scrollRb), deltaY: 200);
      await Future.delayed(const Duration(milliseconds: 150));
    }

    Log.i('[Executor] ❌ "$targetKey" no visible tras $maxAttempts intentos');
    return false;
  }

  /// Tapea el widget cuyo texto interno coincide con [params.label].
  ///
  /// Útil cuando el widget no tiene un ID registrado pero tiene un Text() visible.
  /// Busca en todos los widgets registrados un Text() hijo que contenga el label.
  /// Coincidencia case-insensitive; acepta match parcial (contains).
  Future<bool> _tapByLabel(McpEventParams? params) async {
    final label = params?.label;
    if (label == null) {
      Log.i('[Executor] ❌ tapByLabel requiere params.label');
      return false;
    }

    Log.i('[Executor] 🏷️  TapByLabel "$label"');

    for (final entry in _registry.entries) {
      final context = entry.value.globalKey.currentContext;
      if (context == null) continue;

      bool found = false;
      void findText(Element el) {
        if (found) return;
        if (el.widget case Text w) {
          final text = w.data ?? '';
          if (text.toLowerCase() == label.toLowerCase() ||
              text.toLowerCase().contains(label.toLowerCase())) {
            final rb = el.findRenderObject() as RenderBox?;
            if (rb != null) {
              _simulator.simulateTap(_simulator.centerOf(rb));
              found = true;
              return;
            }
          }
        }
        if (!found) el.visitChildElements(findText);
      }

      context.visitChildElements(findText);
      if (found) {
        await Future.delayed(const Duration(milliseconds: 150));
        Log.i('[Executor] ✅ Tap en label "$label"');
        return true;
      }
    }

    Log.i('[Executor] ❌ No se encontró widget con label "$label"');
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pausa la ejecución durante [params.duration] (default 500ms).
  Future<bool> _wait(McpEventParams? params) async {
    final duration = params?.duration ?? const Duration(milliseconds: 500);
    Log.i('[Executor] ⏳ Wait ${duration.inMilliseconds}ms');
    await Future.delayed(duration);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASERCIONES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Verifica que el widget está registrado en el registry.
  ///
  /// No verifica si está montado — solo que fue registrado.
  /// Para verificar si está visible en pantalla, usa [_assertVisible].
  Future<bool> _assertExists(String key) async {
    final exists = _registry.isRegistered(key);
    Log.i('[Executor] ✅ AssertExists "$key" = $exists');
    return exists;
  }

  /// Verifica que el widget contiene el texto esperado [params.expectedText].
  ///
  /// Busca el primer widget Text() en el árbol hijo y compara su contenido.
  /// Para verificar el valor de un TextField (no su label), usa [_assertValue].
  Future<bool> _assertText(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null || params?.expectedText == null) return false;

    Text? textWidget;
    void findText(Element el) {
      if (textWidget != null) return;
      if (el.widget is Text) {
        textWidget = el.widget as Text;
        return;
      }
      el.visitChildElements(findText);
    }

    context.visitChildElements(findText);

    if (textWidget == null) return false;
    final actual = textWidget!.data ?? '';
    final matches = actual == params!.expectedText;
    Log.i(
      '[Executor] ✅ AssertText: expected="${params.expectedText}", actual="$actual" → $matches',
    );
    return matches;
  }

  /// Verifica que el widget es completamente visible en el viewport actual.
  ///
  /// "Visible" significa que los cuatro bordes del widget están dentro de los
  /// límites de la pantalla (no solo que existe o está montado).
  Future<bool> _assertVisible(String key) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);

    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenH = view.physicalSize.height / view.devicePixelRatio;
    final screenW = view.physicalSize.width / view.devicePixelRatio;
    final pos = rb.localToGlobal(Offset.zero);

    final isVisible =
        pos.dy >= 0 &&
        pos.dy + rb.size.height <= screenH &&
        pos.dx >= 0 &&
        pos.dx + rb.size.width <= screenW;

    Log.i(
      '[Executor] 👁️  AssertVisible "$key" = $isVisible '
      '(y=${pos.dy.toStringAsFixed(0)}, h=${rb.size.height.toStringAsFixed(0)}, screen=${screenH.toStringAsFixed(0)})',
    );
    return isVisible;
  }

  /// Verifica que el widget está habilitado (no deshabilitado).
  ///
  /// Detecta deshabilitación en: ElevatedButton, TextButton, OutlinedButton,
  /// IconButton (onPressed != null), TextField, TextFormField (.enabled),
  /// Checkbox, Switch, Radio, Slider (.onChanged != null),
  /// AbsorbPointer, IgnorePointer (absorbing/ignoring = false → habilitado).
  Future<bool> _assertEnabled(String key) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);

    bool? enabled;
    void findEnabled(Element el) {
      if (enabled != null) return;
      enabled = switch (el.widget) {
        ElevatedButton w => w.onPressed != null,
        TextButton w => w.onPressed != null,
        OutlinedButton w => w.onPressed != null,
        IconButton w => w.onPressed != null,
        TextField w => w.enabled ?? true,
        TextFormField w => w.enabled != false,
        Checkbox w => w.onChanged != null,
        Switch w => w.onChanged != null,
        Radio w => w.onChanged != null,
        Slider w => w.onChanged != null,
        AbsorbPointer w => !w.absorbing,
        IgnorePointer w => !w.ignoring,
        _ => null,
      };
      if (enabled == null) el.visitChildElements(findEnabled);
    }

    context.visitChildElements(findEnabled);

    final result = enabled ?? true;
    Log.i('[Executor] ✅ AssertEnabled "$key" = $result');
    return result;
  }

  /// Verifica que el widget está seleccionado/activado.
  ///
  /// Para Checkbox/Switch: retorna el valor booleano actual.
  /// Para Radio: retorna true si groupValue == value.
  Future<bool> _assertSelected(String key) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);

    bool? selected;
    void findSelected(Element el) {
      if (selected != null) return;
      selected = switch (el.widget) {
        Checkbox w => w.value ?? false,
        Switch w => w.value,
        Radio w => w.groupValue == w.value,
        _ => null,
      };
      if (selected == null) el.visitChildElements(findSelected);
    }

    context.visitChildElements(findSelected);

    if (selected == null) {
      Log.i('[Executor] ❌ No se encontró Checkbox/Switch/Radio en "$key"');
      return false;
    }
    Log.i('[Executor] ✅ AssertSelected "$key" = $selected');
    return selected!;
  }

  /// Verifica el valor del TextEditingController (no el texto visual del label).
  ///
  /// Usa [params.expectedText] como valor esperado.
  /// Compara `controller.text` directo, útil para validar lo que se escribió.
  Future<bool> _assertValue(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null || params?.expectedText == null) return false;

    TextEditingController? controller;
    void find(Element el) {
      if (controller != null) return;
      controller = switch (el.widget) {
        TextField w => w.controller,
        TextFormField w => w.controller,
        _ => null,
      };
      if (controller == null) el.visitChildElements(find);
    }

    context.visitChildElements(find);

    if (controller == null) {
      Log.i('[Executor] ❌ No se encontró controller en "$key"');
      return false;
    }

    final matches = controller!.text == params!.expectedText;
    Log.i(
      '[Executor] ✅ AssertValue "$key": expected="${params.expectedText}", actual="${controller!.text}" → $matches',
    );
    return matches;
  }

  /// Verifica que el widget tiene exactamente [params.expectedCount] hijos visibles.
  ///
  /// Soporta: Column, Row (cuenta children estático), ListView (cuenta elements montados).
  Future<bool> _assertCount(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null || params?.expectedCount == null) return false;

    int? count;
    void findCount(Element el) {
      if (count != null) return;
      count = switch (el.widget) {
        Column w => w.children.length,
        Row w => w.children.length,
        ListView _ => _countChildren(el),
        _ => null,
      };
      if (count == null) el.visitChildElements(findCount);
    }

    context.visitChildElements(findCount);

    if (count == null) {
      Log.i('[Executor] ❌ No se pudo contar hijos en "$key"');
      return false;
    }

    final matches = count == params!.expectedCount;
    Log.i(
      '[Executor] ✅ AssertCount "$key": expected=${params.expectedCount}, actual=$count → $matches',
    );
    return matches;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS INTERNOS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cuenta los hijos directos de un Element de ListView.
  int _countChildren(Element el) {
    int count = 0;
    el.visitChildElements((_) => count++);
    return count;
  }

  /// Log de widget no encontrado. Siempre retorna false.
  bool _notFound(String key) {
    Log.i('[Executor] ❌ Widget no encontrado o no montado: "$key"');
    return false;
  }
}
