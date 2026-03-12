// ─────────────────────────────────────────────────────────────────────────────
// McpTreeInspector
//
// Walks the Flutter widget tree from the root (WidgetsBinding.rootElement)
// and extracts widgets with relevant data: texts, field values,
// button/checkbox/switch states, slider values, etc.
//
// Design:
//   - ZERO intrusion: does not add widgets to the tree. Same mechanism as Flutter
//     DevTools (recursive visitChildElements from the root).
//   - ZERO dependency on the registry (McpWidgetRegistry): works with any
//     widget, whether registered or not.
//   - Only works in debug/profile (where the element tree exists).
//   - In production (release), visitChildElements still works but debug
//     values may be absent.
//
// Included widgets (have data or state relevant for tests):
//   Text, RichText(*), TextField, TextFormField, ElevatedButton, TextButton,
//   OutlinedButton, FilledButton, IconButton, Checkbox, Switch, Radio, Slider,
//   Image, AppBar, AlertDialog, BottomSheet, SnackBar, DropdownButtonFormField,
//   CircularProgressIndicator, LinearProgressIndicator, RefreshProgressIndicator
//   (*) RichText is omitted if it is a direct descendant of Text (avoids duplicates)
//
// Loading widgets expose "loading": true so the MCP server knows
// it should wait before proceeding with the next action.
//
// Excluded widgets (layout without own data):
//   Padding, SizedBox, Spacer, Align, Center, Expanded, Flexible, Positioned,
//   Stack, Wrap, Container (without key), RepaintBoundary, AnimatedBuilder,
//   Material, Scaffold, InkWell, EditableText (internal to TextField)
//
// Flow:
//   inspect() → _walk(rootElement, depth=0, result=[]) →
//   visits each element → extracts data if it is an interesting widget →
//   continues recursion → returns flat list with depth
// ─────────────────────────────────────────────────────────────────────────────

// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../events/mcp_metadata_key.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Flutter widget tree inspector.
///
/// Reads the current tree state without adding any widgets.
/// Ideal for Claude to verify values, states, and on-screen contents.
///
/// Usage:
/// ```dart
/// final json = McpTreeInspector.inspect();
/// // json['widgets'] → list of all widgets with data
/// ```
class McpTreeInspector {
  McpTreeInspector._();

  /// Walks the entire tree and returns a JSON with all widgets
  /// that contain data relevant for testing.
  ///
  /// The JSON includes:
  /// - `timestamp`: when the snapshot was taken
  /// - `widget_count`: number of widgets found
  /// - `widgets`: list of entries, each with `type`, `depth`, and data
  ///   depending on the type (value, label, enabled, key, x, y, w, h)
  static Map<String, dynamic> inspect() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'widget_count': 0,
        'widgets': <Map<String, dynamic>>[],
        'error': 'rootElement not available',
      };
    }

    final result = <Map<String, dynamic>>[];
    _walk(root, 0, result);

    // Sanitize the entire result before returning: any NaN or Infinite double
    // (from positions, Slider.value/min/max, etc.) is converted to null
    // so that jsonEncode never fails due to non-serializable values.
    final sanitized = sanitizeList(result);

    return {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'widget_count': sanitized.length,
      'widgets': sanitized,
    };
  }

  // ── Tree walk ──────────────────────────────────────────────────────────────

  /// Walks the tree recursively.
  ///
  /// Extracts data from the widget if it is interesting and always continues
  /// recursion into children, except for "leaf" widgets whose internal
  /// information has already been captured (TextField, EditableText).
  /// [inOverlay] is propagated to all descendants of a modal container.
  static void _walk(
    Element element,
    int depth,
    List<Map<String, dynamic>> result, {
    bool inOverlay = false,
  }) {
    final widget = element.widget;

    // Detect entry into an overlay/dialog layer
    final enteringOverlay = !inOverlay && _isOverlayContainer(widget);
    final childInOverlay = inOverlay || enteringOverlay;

    // Extract data if it is a widget with relevant information.
    // try-catch: generic widgets (Radio<T>, PopupMenuButton<T>, etc.) can
    // throw TypeErrors due to Dart's function contravariance when accessed
    // via a bare `is` check that erases the type parameter to `dynamic`.
    Map<String, dynamic>? entry;
    try {
      entry = _extract(widget, element, depth, inOverlay: childInOverlay);
    } catch (_) {
      entry = null;
    }
    if (entry != null) result.add(entry);

    // Always continue recursion, except for nodes whose internal
    // info was already extracted (avoids duplicate entries)
    final skipChildren = widget is EditableText; // internal to TextField
    if (!skipChildren) {
      element.visitChildElements(
        (child) => _walk(child, depth + 1, result, inOverlay: childInOverlay),
      );
    }
  }

  /// Detects if a widget is the root of a modal/overlay layer.
  static bool _isOverlayContainer(Widget w) {
    if (w is AlertDialog ||
        w is Dialog ||
        w is SimpleDialog ||
        w is BottomSheet ||
        w is SnackBar) {
      return true;
    }
    // Private Flutter types — detect by runtime name
    final t = w.runtimeType.toString();
    return t == '_ModalScope' || t == '_ModalBarrier';
  }

  // ── Data extraction ────────────────────────────────────────────────────

  /// Returns a map with the widget's data, or null if it is not interesting.
  /// [inOverlay] indicates that this widget belongs to an active dialog/overlay.
  static Map<String, dynamic>? _extract(
    Widget widget,
    Element element,
    int depth, {
    bool inOverlay = false,
  }) {
    // Get position on screen (null if not mounted or no renderObject)
    final pos = _position(element);

    // Get MCP key or ValueKey<String> if it exists
    final mcpKey = widget.key is McpMetadataKey
        ? (widget.key as McpMetadataKey).id
        : widget.key is ValueKey<String>
        ? (widget.key as ValueKey<String>).value
        : null;

    // ── Text ──────────────────────────────────────────────────────────────
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText();
      if (value == null || value.isEmpty) return null;
      return _entry(
        'Text',
        depth,
        pos,
        mcpKey,
        extra: {'value': value},
        inOverlay: inOverlay,
      );
    }

    // RichText: only if not a direct child of a Text (avoids duplicates).
    // Since Text always creates RichText internally, we skip this case.
    if (widget is RichText) return null;

    // EditableText is internal to TextField — captured there
    if (widget is EditableText) return null;

    // ── Text fields ────────────────────────────────────────────────────
    if (widget is TextField) {
      final value = _findEditableTextValue(element);
      final hint = widget.decoration?.hintText;
      final enabled = widget.enabled ?? true;
      return _entry(
        'TextField',
        depth,
        pos,
        mcpKey,
        extra: {
          if (value != null && value.isNotEmpty) 'value': value,
          'hint': ?hint,
          'enabled': enabled,
          if (widget.autofocus) 'auto_focus': true,
        },
        inOverlay: inOverlay,
      );
    }

    // TextFormField: decoration is not directly accessible as a widget field
    // (it's passed to the internal TextField via the builder). The inner
    // TextField will be captured when the walk reaches it, so here we only
    // capture the key for registration purposes.
    if (widget is TextFormField) {
      if (mcpKey == null) return null; // no extra info vs inner TextField
      final value = _findEditableTextValue(element);
      // auto_focus is not directly accessible on TextFormField — it's read from
      // the internal TextField when the walk reaches it.
      return _entry(
        'TextFormField',
        depth,
        pos,
        mcpKey,
        extra: {if (value != null && value.isNotEmpty) 'value': value},
        inOverlay: inOverlay,
      );
    }

    // ── Buttons ────────────────────────────────────────────────────────────
    if (widget is ElevatedButton) {
      final label = _findTextInSubtree(element);
      final enabled = widget.onPressed != null;
      return _entry(
        'ElevatedButton',
        depth,
        pos,
        mcpKey,
        extra: {'label': ?label, 'enabled': enabled},
        inOverlay: inOverlay,
      );
    }

    if (widget is TextButton) {
      final label = _findTextInSubtree(element);
      final enabled = widget.onPressed != null;
      return _entry(
        'TextButton',
        depth,
        pos,
        mcpKey,
        extra: {'label': ?label, 'enabled': enabled},
        inOverlay: inOverlay,
      );
    }

    if (widget is OutlinedButton) {
      final label = _findTextInSubtree(element);
      final enabled = widget.onPressed != null;
      return _entry(
        'OutlinedButton',
        depth,
        pos,
        mcpKey,
        extra: {'label': ?label, 'enabled': enabled},
        inOverlay: inOverlay,
      );
    }

    if (widget is FilledButton) {
      final label = _findTextInSubtree(element);
      final enabled = widget.onPressed != null;
      return _entry(
        'FilledButton',
        depth,
        pos,
        mcpKey,
        extra: {'label': ?label, 'enabled': enabled},
        inOverlay: inOverlay,
      );
    }

    if (widget is IconButton) {
      final tooltip = widget.tooltip;
      final enabled = widget.onPressed != null;
      return _entry(
        'IconButton',
        depth,
        pos,
        mcpKey,
        extra: {'tooltip': ?tooltip, 'enabled': enabled},
        inOverlay: inOverlay,
      );
    }

    // ── Selection controls ─────────────────────────────────────────────
    if (widget is Checkbox) {
      return _entry(
        'Checkbox',
        depth,
        pos,
        mcpKey,
        extra: {'value': widget.value, 'enabled': widget.onChanged != null},
        inOverlay: inOverlay,
      );
    }

    if (widget is Switch) {
      return _entry(
        'Switch',
        depth,
        pos,
        mcpKey,
        extra: {'value': widget.value, 'enabled': widget.onChanged != null},
        inOverlay: inOverlay,
      );
    }

    if (widget is Radio) {
      // Radio<T> is generic — accessing onChanged after a bare `is Radio`
      // (which erases T to dynamic) can throw a TypeError due to function
      // contravariance. Wrap in try-catch.
      bool enabled;
      try {
        enabled = widget.onChanged != null;
      } catch (_) {
        enabled = true;
      }
      return _entry(
        'Radio',
        depth,
        pos,
        mcpKey,
        extra: {
          'value': widget.value?.toString(),
          'groupValue': widget.groupValue?.toString(),
          'selected': widget.value == widget.groupValue,
          'enabled': enabled,
        },
        inOverlay: inOverlay,
      );
    }

    // ── Slider ─────────────────────────────────────────────────────────────
    if (widget is Slider) {
      return _entry(
        'Slider',
        depth,
        pos,
        mcpKey,
        extra: {
          'value': widget.value,
          'min': widget.min,
          'max': widget.max,
          'enabled': widget.onChanged != null,
        },
        inOverlay: inOverlay,
      );
    }

    // ── PopupMenuButton ────────────────────────────────────────────────────
    // Frequently used in AppBar for dropdown menus (solutions, filters,
    // screen options). Without this block the LLM cannot see it in
    // INTERACTIVE and cannot open it.
    // PopupMenuButton<T> and DropdownButtonFormField<T> are generic —
    // property access can throw TypeError due to Dart's type erasure.
    if (widget is PopupMenuButton) {
      String? tooltip;
      bool enabled = true;
      try {
        tooltip = widget.tooltip;
        enabled = widget.enabled;
      } catch (_) {}
      return _entry(
        'PopupMenuButton',
        depth,
        pos,
        mcpKey,
        extra: {'tooltip': ?tooltip, 'enabled': enabled},
        inOverlay: inOverlay,
      );
    }

    // ── Dropdown ───────────────────────────────────────────────────────────
    if (widget is DropdownButtonFormField) {
      String? value;
      try {
        value = widget.initialValue?.toString();
      } catch (_) {}
      return _entry(
        'DropdownButtonFormField',
        depth,
        pos,
        mcpKey,
        extra: {'value': ?value},
        inOverlay: inOverlay,
      );
    }

    // ── Image ─────────────────────────────────────────────────────────────
    if (widget is Image) {
      final label = widget.semanticLabel;
      if (label == null && mcpKey == null) return null; // no useful info
      return _entry(
        'Image',
        depth,
        pos,
        mcpKey,
        extra: {'semanticLabel': ?label},
        inOverlay: inOverlay,
      );
    }

    // ── AppBar ─────────────────────────────────────────────────────────────
    if (widget is AppBar) {
      final titleText = widget.title is Text
          ? (widget.title as Text).data
          : _findTextInSubtree(element);
      return _entry(
        'AppBar',
        depth,
        pos,
        mcpKey,
        extra: {'title': ?titleText},
        inOverlay: inOverlay,
      );
    }

    // ── Dialogs / overlays ────────────────────────────────────────────────
    if (widget is AlertDialog) {
      final titleText = widget.title is Text
          ? (widget.title as Text).data
          : null;
      return _entry(
        'AlertDialog',
        depth,
        pos,
        mcpKey,
        extra: {'title': ?titleText, 'visible': true},
        inOverlay: true, // AlertDialog is always an overlay
      );
    }

    if (widget is BottomSheet) {
      return _entry(
        'BottomSheet',
        depth,
        pos,
        mcpKey,
        extra: {'visible': true},
        inOverlay: true, // BottomSheet is always an overlay
      );
    }

    if (widget is SnackBar) {
      final content = widget.content is Text
          ? (widget.content as Text).data
          : _findTextInSubtree(element);
      return _entry(
        'SnackBar',
        depth,
        pos,
        mcpKey,
        extra: {'content': ?content, 'visible': true},
        inOverlay: true, // SnackBar is always an overlay
      );
    }

    // ── Loading indicators ───────────────────────────────────────────────
    // "loading": true allows the MCP server to detect that the UI is busy
    // and wait before proceeding with the next action.
    if (widget is CircularProgressIndicator) {
      return _entry(
        'CircularProgressIndicator',
        depth,
        pos,
        mcpKey,
        extra: {'loading': true},
        inOverlay: inOverlay,
      );
    }

    if (widget is LinearProgressIndicator) {
      return _entry(
        'LinearProgressIndicator',
        depth,
        pos,
        mcpKey,
        extra: {'loading': true},
        inOverlay: inOverlay,
      );
    }

    if (widget is RefreshProgressIndicator) {
      return _entry(
        'RefreshProgressIndicator',
        depth,
        pos,
        mcpKey,
        extra: {'loading': true},
        inOverlay: inOverlay,
      );
    }

    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Builds a result entry with the standard fields.
  /// [inOverlay] = true adds `"overlay": true` to indicate that the widget
  /// belongs to an active dialog, BottomSheet, or AlertDialog.
  static Map<String, dynamic> _entry(
    String type,
    int depth,
    Map<String, double>? pos,
    String? key, {
    Map<String, dynamic> extra = const {},
    bool inOverlay = false,
  }) {
    return {
      'type': type,
      'depth': depth,
      'key': ?key,
      if (inOverlay) 'overlay': true,
      ...extra,
      ...?pos,
    };
  }

  /// Gets the position and size of the widget in screen coordinates.
  ///
  /// Returns null if the widget is not mounted, if layout has not completed,
  /// or if any coordinate is NaN / Infinite (can occur during transitions
  /// such as language changes where the tree rebuilds mid-frame).
  static Map<String, double>? _position(Element element) {
    try {
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.attached) return null;
      final offset = ro.localToGlobal(Offset.zero);
      final size = ro.size;
      final x = round(offset.dx);
      final y = round(offset.dy);
      final w = round(size.width);
      final h = round(size.height);
      // Discard if any coordinate is not a valid finite number.
      // Occurs when the RenderBox exists but layout has not yet finished.
      if (!x.isFinite || !y.isFinite || !w.isFinite || !h.isFinite) return null;
      return {'x': x, 'y': y, 'w': w, 'h': h};
    } catch (_) {
      return null;
    }
  }

  /// Finds the text of the first Text descendant of the element.
  ///
  /// Useful for extracting button labels without walking the entire subtree.
  static String? _findTextInSubtree(Element element) {
    String? found;
    void visit(Element el) {
      if (found != null) return;
      if (el.widget is Text) {
        found = (el.widget as Text).data;
        return;
      }
      el.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return found;
  }

  /// Finds the current text value in a TextField/TextFormField
  /// by locating the descendant EditableText and reading its controller.
  static String? _findEditableTextValue(Element element) {
    String? found;
    void visit(Element el) {
      if (found != null) return;
      if (el.widget is EditableText) {
        found = (el.widget as EditableText).controller.text;
        return;
      }
      el.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return found;
  }

  /// Rounds to 1 decimal place to reduce noise in coordinates.
  ///
  /// Propagates NaN/Infinite as-is — [_position] detects them with `.isFinite`
  /// before including the coordinates in the result.
  @visibleForTesting
  static double round(double v) {
    if (!v.isFinite) return v;
    return (v * 10).roundToDouble() / 10;
  }

  // ── JSON sanitization ─────────────────────────────────────────────────

  /// Recursively converts any non-finite double (NaN, Infinite) to null.
  ///
  /// Necessary because jsonEncode does not accept NaN or Infinite. NaN values
  /// can come from widget positions during mid-layout (transitions, language
  /// changes) or from widget properties like Slider.value/min/max when they
  /// are not yet properly initialized.
  ///
  /// Usage outside of tests is not recommended — call only through [inspect].
  @visibleForTesting
  static List<Map<String, dynamic>> sanitizeList(
    List<Map<String, dynamic>> list,
  ) => list.map(sanitizeMap).toList();

  @visibleForTesting
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) => MapEntry(key, sanitizeValue(value)));
  }

  @visibleForTesting
  static dynamic sanitizeValue(dynamic value) {
    if (value is double && !value.isFinite) return null;
    if (value is Map<String, dynamic>) return sanitizeMap(value);
    if (value is List) return value.map(sanitizeValue).toList();
    return value;
  }
}
