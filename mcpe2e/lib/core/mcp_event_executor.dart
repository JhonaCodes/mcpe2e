// ignore_for_file: deprecated_member_use
// ─────────────────────────────────────────────────────────────────────────────
// McpEventExecutor
//
// MCP event execution engine on the Flutter widget tree.
//
// Receives a (widgetKey, McpEventType, McpEventParams) and dispatches the
// correct action: navigate the widget tree, read state, simulate gestures, or
// execute callbacks directly. Returns true on success, false on failure
// (widget not found, missing parameters, invalid state).
//
// Depends on:
//   - McpWidgetRegistry: to obtain BuildContext and RenderBox of the widget
//   - McpGestureSimulator: to generate physical pointer events
//
// General flow per event:
//   1. get context/renderBox from the registry
//   2. walk the widget tree if necessary (visitChildElements)
//   3. execute the action (gesture, callback, assertion)
//   4. wait for rebuild if applicable (Future.delayed)
//   5. return bool
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger_rs/logger_rs.dart';

import '../events/mcp_event_type.dart';
import 'mcp_widget_registry.dart';
import 'mcp_gesture_simulator.dart';

// ── Executor ──────────────────────────────────────────────────────────────────

/// Execution engine for the 25 MCP event types on the widget tree.
///
/// This is the only class that navigates the Flutter widget tree and executes
/// actions on it. All the logic for "how to do X in Flutter" lives here.
class McpEventExecutor {
  final McpWidgetRegistry _registry;
  final McpGestureSimulator _simulator;

  McpEventExecutor(this._registry, this._simulator);

  // ── Main dispatch ────────────────────────────────────────────────────

  /// Executes the [eventType] event on the widget identified by [widgetKey].
  ///
  /// Returns true if the event was executed successfully.
  /// Returns false if: the widget is not registered/mounted, parameters are
  /// missing, or the widget tree does not contain the expected element.
  ///
  /// Assertion events return the assertion result
  /// (true = assertion passed, false = assertion failed).
  Future<bool> executeEvent({
    required String widgetKey,
    required McpEventType eventType,
    McpEventParams? params,
  }) async {
    Log.i('[Executor] ⚡ $eventType → "$widgetKey"');
    return switch (eventType) {
      // ── Basic gestures ──────────────────────────────────────────────────
      McpEventType.tap => _tap(widgetKey),
      McpEventType.doubleTap => _doubleTap(widgetKey),
      McpEventType.longPress => _longPress(widgetKey, params),
      McpEventType.swipe => _swipe(widgetKey, params),
      McpEventType.drag => _drag(widgetKey, params),
      McpEventType.scroll => _scroll(widgetKey, params),
      McpEventType.pinch => _pinch(widgetKey, params),
      // ── Text and input ────────────────────────────────────────────────────
      McpEventType.textInput => _textInput(widgetKey, params),
      McpEventType.clearText => _clearText(widgetKey),
      McpEventType.selectDropdown => _selectDropdown(widgetKey, params),
      McpEventType.toggle => _toggle(widgetKey),
      McpEventType.setSliderValue => _setSliderValue(widgetKey, params),
      // ── Keyboard ─────────────────────────────────────────────────────────
      McpEventType.hideKeyboard => _hideKeyboard(),
      McpEventType.showKeyboard => _showKeyboard(widgetKey),
      // ── Navigation ───────────────────────────────────────────────────────
      McpEventType.pressBack => _pressBack(widgetKey),
      // ── Smart scroll ───────────────────────────────────────────────────
      McpEventType.scrollUntilVisible => _scrollUntilVisible(widgetKey, params),
      McpEventType.tapByLabel => _tapByLabel(params),
      McpEventType.tapAt => _tapAt(params),
      // ── Utilities ───────────────────────────────────────────────────────
      McpEventType.wait => _wait(params),
      // ── Assertions ───────────────────────────────────────────────────────
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

  /// Simple tap at the center of the widget.
  Future<bool> _tap(String key) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    _simulator.simulateTap(_simulator.centerOf(rb));
    return true;
  }

  /// Two taps separated by 100ms.
  Future<bool> _doubleTap(String key) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);
    final center = _simulator.centerOf(rb);
    _simulator.simulateTap(center);
    await Future.delayed(const Duration(milliseconds: 100));
    _simulator.simulateTap(center);
    return true;
  }

  /// Sustained tap for [params.duration] (default 500ms).
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

  /// Swipe in the [params.direction] direction (up/down/left/right).
  ///
  /// [params.distance] controls how many pixels to swipe (default 300).
  /// [params.duration] controls the speed (default 300ms).
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

  /// Drag from the widget to an absolute position [params.targetPosition]
  /// or a relative offset using [params.deltaX] / [params.deltaY].
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
      Log.i('[Executor] ❌ drag requires targetPosition or deltaX/deltaY');
      return false;
    }

    Log.i('[Executor] 🖱️  Drag → $target');
    _simulator.simulateSwipe(center, target, duration);
    return true;
  }

  /// Scroll via PointerScrollEvent (mouse/trackpad).
  ///
  /// For touch scrolling on mobile devices, use [_swipe].
  /// [params.direction] accepts 'up'/'down' (in addition to direct deltaX/deltaY).
  Future<bool> _scroll(String key, McpEventParams? params) async {
    final rb = _registry.getRenderBox(key);
    if (rb == null) return _notFound(key);

    // Allows specifying semantic direction in addition to numeric deltas
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

  /// Pinch/zoom — pending implementation.
  ///
  /// Requires simulating two simultaneous pointers, which GestureBinding supports
  /// but needs coordination of different pointer IDs.
  Future<bool> _pinch(String key, McpEventParams? params) async {
    Log.i('[Executor] ⚠️  Pinch not yet implemented (requires dual-pointer)');
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXTO E INPUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Types text into a TextField/TextFormField.
  ///
  /// Flow:
  /// 1. Walks the tree from the widget's context looking for TextField
  /// 2. Gets the TextEditingController
  /// 3. Clears if [params.clearFirst] is true
  /// 4. Assigns the value to the controller (including cursor at the end)
  /// 5. Calls onChanged() manually to trigger form validators
  /// 6. Taps the widget to focus (simulates the user touching the field)
  Future<bool> _textInput(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null || params?.text == null) {
      Log.i('[Executor] ❌ textInput: context or text not available for "$key"');
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
      Log.i('[Executor] ❌ TextEditingController not found in "$key"');
      return false;
    }

    if (params.clearFirst == true) controller!.clear();

    controller!.value = TextEditingValue(
      text: params.text!,
      selection: TextSelection.collapsed(offset: params.text!.length),
    );

    // Notify form validators
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

    // Tap to focus
    final rb = _registry.getRenderBox(key);
    if (rb != null) _simulator.simulateTap(_simulator.centerOf(rb));

    await Future.delayed(const Duration(milliseconds: 150));
    Log.i('[Executor] ✅ Text inserted: "${controller!.text}"');
    return true;
  }

  /// Clears the contents of a TextField without typing new text.
  ///
  /// Useful for resetting fields before an assertion or before typing.
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
    Log.i('[Executor] ✅ Field cleared: "$key"');
    return true;
  }

  /// Selects an option from a DropdownButtonFormField.
  ///
  /// Does not open the dropdown visually — calls onChanged() directly.
  /// For custom dropdowns (BottomSheet, overlay), use tap + tapByLabel.
  ///
  /// Selection by value: searches for exact match → contains → enum suffix
  /// Selection by index: 0-based, accesses the item directly
  Future<bool> _selectDropdown(String key, McpEventParams? params) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);
    if (params?.dropdownValue == null && params?.dropdownIndex == null) {
      Log.i(
        '[Executor] ❌ selectDropdown requires dropdownValue or dropdownIndex',
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
      Log.i('[Executor] ❌ DropdownButtonFormField not found in "$key"');
      return false;
    }

    Log.i('[Executor] 📋 Dropdown con ${items!.length} items');

    // Selection by index
    if (params!.dropdownIndex != null) {
      final idx = params.dropdownIndex!;
      if (idx < 0 || idx >= items!.length) {
        Log.i(
          '[Executor] ❌ Index $idx out of range (0..${items!.length - 1})',
        );
        return false;
      }
      onChanged!(items![idx].value);
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }

    // Selection by value (flexible matching)
    final search = params.dropdownValue!.toLowerCase();
    for (final item in items!) {
      final val = item.value.toString().toLowerCase();
      if (val == search ||
          val.contains(search) ||
          val.split('.').last == search) {
        Log.i('[Executor] ✅ Selecting: ${item.value}');
        onChanged!(item.value);
        await Future.delayed(const Duration(milliseconds: 300));
        return true;
      }
    }

    Log.i('[Executor] ❌ No matching value found for "$search"');
    return false;
  }

  /// Toggles a Checkbox, Switch, or Radio.
  ///
  /// For Checkbox/Switch: inverts the current value by calling onChanged(!current).
  /// For Radio: selects it (calls onChanged with its value).
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
      Log.i('[Executor] ❌ Checkbox/Switch/Radio not found in "$key"');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }

  /// Positions a Slider to the [params.sliderValue] value (0.0 – 1.0).
  ///
  /// Calculates the X position within the Slider track and simulates a tap there.
  /// 0.0 = left end, 1.0 = right end.
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

  /// Hides the virtual keyboard via the TextInput platform channel.
  Future<bool> _hideKeyboard() async {
    Log.i('[Executor] ⌨️↓ HideKeyboard');
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    return true;
  }

  /// Shows the keyboard by requesting focus on the widget's scope.
  Future<bool> _showKeyboard(String key) async {
    final context = _registry.getContext(key);
    if (context == null) return _notFound(key);
    Log.i('[Executor] ⌨️↑ ShowKeyboard');
    FocusScope.of(context).requestFocus();
    return true;
  }

  /// Navigates back using Navigator.pop().
  ///
  /// Attempts to pop from the nearest Navigator to the widget [key].
  /// If no Navigator is available or it cannot pop, uses SystemNavigator.pop()
  /// (equivalent to the physical Back button on Android).
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

  /// Scrolls the widget [key] until the widget [params.targetKey] is visible.
  ///
  /// Algorithm:
  /// 1. Checks if targetKey is already in the viewport
  /// 2. If not, emits a 200px PointerScrollEvent downward
  /// 3. Waits 150ms for the layout to update
  /// 4. Repeats up to [params.maxScrollAttempts] times (default 20)
  ///
  /// Returns true if the target became visible, false if attempts were exhausted.
  Future<bool> _scrollUntilVisible(String key, McpEventParams? params) async {
    final targetKey = params?.targetKey;
    if (targetKey == null) {
      Log.i('[Executor] ❌ scrollUntilVisible requires params.targetKey');
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

    Log.i('[Executor] ❌ "$targetKey" not visible after $maxAttempts attempts');
    return false;
  }

  /// Taps the widget whose internal text matches [params.label].
  ///
  /// Useful when the widget does not have a registered ID but has a visible Text().
  /// Searches all registered widgets for a child Text() that contains the label.
  /// Case-insensitive matching; accepts partial match (contains).
  Future<bool> _tapByLabel(McpEventParams? params) async {
    final label = params?.label;
    if (label == null) {
      Log.i('[Executor] ❌ tapByLabel requires params.label');
      return false;
    }

    Log.i('[Executor] 🏷️  TapByLabel "$label"');

    for (final entry in _registry.entries) {
      final context = _registry.getContext(entry.key);
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

    Log.i('[Executor] ❌ Widget with label "$label" not found');
    return false;
  }

  /// Tap at absolute screen coordinates [params.dx] / [params.dy].
  ///
  /// Does not require a registered widget — useful for cards, dynamic list items,
  /// or any widget without an ID. Coordinates are logical pixels from the
  /// top-left corner of the screen (same as the inspect_ui tree).
  Future<bool> _tapAt(McpEventParams? params) async {
    final x = params?.dx;
    final y = params?.dy;
    if (x == null || y == null) {
      Log.i('[Executor] ❌ tapAt requires params.dx and params.dy');
      return false;
    }
    final position = Offset(x, y);
    Log.i('[Executor] 👆 TapAt (${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})');
    _simulator.simulateTap(position);
    await Future.delayed(const Duration(milliseconds: 150));
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pauses execution for [params.duration] (default 500ms).
  Future<bool> _wait(McpEventParams? params) async {
    final duration = params?.duration ?? const Duration(milliseconds: 500);
    Log.i('[Executor] ⏳ Wait ${duration.inMilliseconds}ms');
    await Future.delayed(duration);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASERCIONES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Verifies that the widget is registered in the registry.
  ///
  /// Does not verify if it is mounted — only that it was registered.
  /// To verify if it is visible on screen, use [_assertVisible].
  Future<bool> _assertExists(String key) async {
    // isRegistered: was declared. getContext != null: is mounted on screen.
    final registered = _registry.isRegistered(key);
    final mounted = _registry.getContext(key) != null;
    final exists = registered || mounted;
    Log.i('[Executor] ✅ AssertExists "$key" = $exists (registered=$registered, mounted=$mounted)');
    return exists;
  }

  /// Verifies that the widget contains the expected text [params.expectedText].
  ///
  /// Searches for the first Text() widget in the child tree and compares its content.
  /// To verify the value of a TextField (not its label), use [_assertValue].
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

  /// Verifies that the widget is fully visible in the current viewport.
  ///
  /// "Visible" means that all four edges of the widget are within the
  /// screen bounds (not just that it exists or is mounted).
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

  /// Verifies that the widget is enabled (not disabled).
  ///
  /// Detects disabled state in: ElevatedButton, TextButton, OutlinedButton,
  /// IconButton (onPressed != null), TextField, TextFormField (.enabled),
  /// Checkbox, Switch, Radio, Slider (.onChanged != null),
  /// AbsorbPointer, IgnorePointer (absorbing/ignoring = false → enabled).
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

  /// Verifies that the widget is selected/activated.
  ///
  /// For Checkbox/Switch: returns the current boolean value.
  /// For Radio: returns true if groupValue == value.
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
      Log.i('[Executor] ❌ Checkbox/Switch/Radio not found in "$key"');
      return false;
    }
    Log.i('[Executor] ✅ AssertSelected "$key" = $selected');
    return selected!;
  }

  /// Verifies the TextEditingController value (not the visual label text).
  ///
  /// Uses [params.expectedText] as the expected value.
  /// Compares `controller.text` directly, useful for validating what was typed.
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
      Log.i('[Executor] ❌ Controller not found in "$key"');
      return false;
    }

    final matches = controller!.text == params!.expectedText;
    Log.i(
      '[Executor] ✅ AssertValue "$key": expected="${params.expectedText}", actual="${controller!.text}" → $matches',
    );
    return matches;
  }

  /// Verifies that the widget has exactly [params.expectedCount] visible children.
  ///
  /// Supports: Column, Row (counts static children), ListView (counts mounted elements).
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
      Log.i('[Executor] ❌ Could not count children in "$key"');
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

  /// Counts the direct children of a ListView Element.
  int _countChildren(Element el) {
    int count = 0;
    el.visitChildElements((_) => count++);
    return count;
  }

  /// Logs widget not found. Always returns false.
  bool _notFound(String key) {
    Log.i('[Executor] ❌ Widget not found or not mounted: "$key"');
    return false;
  }
}
