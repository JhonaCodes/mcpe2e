// ─────────────────────────────────────────────────────────────────────────────
// McpTreeInspector
//
// Recorre el widget tree de Flutter desde la raíz (WidgetsBinding.rootElement)
// y extrae los widgets con datos relevantes: textos, valores de campos,
// estados de botones/checkboxes/switches, valores de sliders, etc.
//
// Diseño:
//   - CERO intrusión: no agrega widgets al árbol. Mismo mecanismo que Flutter
//     DevTools (visitChildElements recursivo desde la raíz).
//   - CERO dependencia del registro (McpWidgetRegistry): funciona con cualquier
//     widget, esté o no registrado.
//   - Solo funciona en debug/profile (donde el árbol de elementos existe).
//   - En producción (release), visitChildElements sigue funcionando pero los
//     valores de debug podrían estar ausentes.
//
// Widgets incluidos (tienen datos o estado relevante para tests):
//   Text, RichText(*), TextField, TextFormField, ElevatedButton, TextButton,
//   OutlinedButton, FilledButton, IconButton, Checkbox, Switch, Radio, Slider,
//   Image, AppBar, AlertDialog, SnackBar, DropdownButtonFormField
//   (*) RichText omitido si es descendiente directo de Text (evita duplicados)
//
// Widgets excluidos (layout sin datos propios):
//   Padding, SizedBox, Spacer, Align, Center, Expanded, Flexible, Positioned,
//   Stack, Wrap, Container (sin key), RepaintBoundary, AnimatedBuilder,
//   Material, Scaffold, InkWell, EditableText (interno de TextField)
//
// Flujo:
//   inspect() → _walk(rootElement, depth=0, result=[]) →
//   visita cada element → extrae datos si es widget interesante →
//   continúa recursión → retorna flat list con depth
// ─────────────────────────────────────────────────────────────────────────────

// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../events/mcp_metadata_key.dart';

// ── API pública ────────────────────────────────────────────────────────────────

/// Inspector del árbol de widgets de Flutter.
///
/// Lee el estado actual del árbol sin agregar ningún widget.
/// Ideal para que Claude verifique valores, estados y contenidos en pantalla.
///
/// Uso:
/// ```dart
/// final json = McpTreeInspector.inspect();
/// // json['widgets'] → lista de todos los widgets con datos
/// ```
class McpTreeInspector {
  McpTreeInspector._();

  /// Recorre el árbol completo y retorna un JSON con todos los widgets
  /// que contienen datos relevantes para testing.
  ///
  /// El JSON incluye:
  /// - `timestamp`: cuándo se capturó
  /// - `widget_count`: cantidad de widgets encontrados
  /// - `widgets`: lista de entradas, cada una con `type`, `depth`, y datos
  ///   según el tipo (value, label, enabled, key, x, y, w, h)
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

    return {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'widget_count': result.length,
      'widgets': result,
    };
  }

  // ── Tree walk ──────────────────────────────────────────────────────────────

  /// Recorre el árbol recursivamente.
  ///
  /// Extrae datos del widget si es interesante y siempre continúa
  /// la recursión en los hijos, excepto para widgets "hoja" cuya
  /// información interna ya fue capturada (TextField, EditableText).
  static void _walk(
    Element element,
    int depth,
    List<Map<String, dynamic>> result,
  ) {
    final widget = element.widget;

    // Extraer datos si es un widget con información relevante
    final entry = _extract(widget, element, depth);
    if (entry != null) result.add(entry);

    // Siempre continuar recursión, excepto en nodos cuya info
    // interna ya extrajimos (evita entradas duplicadas)
    final skipChildren = widget is EditableText; // interno de TextField
    if (!skipChildren) {
      element.visitChildElements((child) => _walk(child, depth + 1, result));
    }
  }

  // ── Extracción de datos ────────────────────────────────────────────────────

  /// Retorna un mapa con los datos del widget, o null si no es interesante.
  static Map<String, dynamic>? _extract(
    Widget widget,
    Element element,
    int depth,
  ) {
    // Obtener posición en pantalla (null si no está montado o sin renderObject)
    final pos = _position(element);

    // Obtener key MCP o ValueKey<String> si existe
    final mcpKey = widget.key is McpMetadataKey
        ? (widget.key as McpMetadataKey).id
        : widget.key is ValueKey<String>
        ? (widget.key as ValueKey<String>).value
        : null;

    // ── Texto ──────────────────────────────────────────────────────────────
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText();
      if (value == null || value.isEmpty) return null;
      return _entry('Text', depth, pos, mcpKey, extra: {'value': value});
    }

    // RichText: solo si no es hijo directo de un Text (evita duplicados).
    // Como Text siempre crea RichText internamente, saltamos este caso.
    if (widget is RichText) return null;

    // EditableText es interno de TextField — capturado ahí
    if (widget is EditableText) return null;

    // ── Campos de texto ────────────────────────────────────────────────────
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
          if (hint != null) 'hint': hint,
          'enabled': enabled,
        },
      );
    }

    // TextFormField: decoration is not directly accessible as a widget field
    // (it's passed to the internal TextField via the builder). The inner
    // TextField will be captured when the walk reaches it, so here we only
    // capture the key for registration purposes.
    if (widget is TextFormField) {
      if (mcpKey == null) return null; // no extra info vs inner TextField
      final value = _findEditableTextValue(element);
      return _entry(
        'TextFormField',
        depth,
        pos,
        mcpKey,
        extra: {if (value != null && value.isNotEmpty) 'value': value},
      );
    }

    // ── Botones ────────────────────────────────────────────────────────────
    if (widget is ElevatedButton) {
      final label = _findTextInSubtree(element);
      final enabled = widget.onPressed != null;
      return _entry(
        'ElevatedButton',
        depth,
        pos,
        mcpKey,
        extra: {if (label != null) 'label': label, 'enabled': enabled},
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
        extra: {if (label != null) 'label': label, 'enabled': enabled},
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
        extra: {if (label != null) 'label': label, 'enabled': enabled},
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
        extra: {if (label != null) 'label': label, 'enabled': enabled},
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
        extra: {if (tooltip != null) 'tooltip': tooltip, 'enabled': enabled},
      );
    }

    // ── Controles de selección ─────────────────────────────────────────────
    if (widget is Checkbox) {
      return _entry(
        'Checkbox',
        depth,
        pos,
        mcpKey,
        extra: {'value': widget.value, 'enabled': widget.onChanged != null},
      );
    }

    if (widget is Switch) {
      return _entry(
        'Switch',
        depth,
        pos,
        mcpKey,
        extra: {'value': widget.value, 'enabled': widget.onChanged != null},
      );
    }

    if (widget is Radio) {
      return _entry(
        'Radio',
        depth,
        pos,
        mcpKey,
        extra: {
          'value': widget.value?.toString(),
          'groupValue': widget.groupValue?.toString(),
          'selected': widget.value == widget.groupValue,
          'enabled': widget.onChanged != null,
        },
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
      );
    }

    // ── Dropdown ───────────────────────────────────────────────────────────
    if (widget is DropdownButtonFormField) {
      return _entry(
        'DropdownButtonFormField',
        depth,
        pos,
        mcpKey,
        extra: {
          if (widget.initialValue != null)
            'value': widget.initialValue.toString(),
        },
      );
    }

    // ── Imagen ─────────────────────────────────────────────────────────────
    if (widget is Image) {
      final label = widget.semanticLabel;
      if (label == null && mcpKey == null) return null; // no info útil
      return _entry(
        'Image',
        depth,
        pos,
        mcpKey,
        extra: {if (label != null) 'semanticLabel': label},
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
        extra: {if (titleText != null) 'title': titleText},
      );
    }

    // ── Diálogos / overlays ────────────────────────────────────────────────
    if (widget is AlertDialog) {
      final titleText = widget.title is Text
          ? (widget.title as Text).data
          : null;
      return _entry(
        'AlertDialog',
        depth,
        pos,
        mcpKey,
        extra: {if (titleText != null) 'title': titleText, 'visible': true},
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
        extra: {if (content != null) 'content': content, 'visible': true},
      );
    }

    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Construye una entrada del resultado con los campos estándar.
  static Map<String, dynamic> _entry(
    String type,
    int depth,
    Map<String, double>? pos,
    String? key, {
    Map<String, dynamic> extra = const {},
  }) {
    return {
      'type': type,
      'depth': depth,
      if (key != null) 'key': key,
      ...extra,
      if (pos != null) ...pos,
    };
  }

  /// Obtiene la posición y tamaño del widget en coordenadas de pantalla.
  static Map<String, double>? _position(Element element) {
    try {
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.attached) return null;
      final offset = ro.localToGlobal(Offset.zero);
      final size = ro.size;
      return {
        'x': _round(offset.dx),
        'y': _round(offset.dy),
        'w': _round(size.width),
        'h': _round(size.height),
      };
    } catch (_) {
      return null;
    }
  }

  /// Busca el texto del primer Text descendiente del elemento.
  ///
  /// Útil para extraer el label de botones sin recorrer todo el subárbol.
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

  /// Busca el valor actual del texto en un TextField/TextFormField
  /// localizando el EditableText descendiente y leyendo su controller.
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

  /// Redondea a 1 decimal para reducir ruido en las coordenadas.
  static double _round(double v) => (v * 10).roundToDouble() / 10;
}
