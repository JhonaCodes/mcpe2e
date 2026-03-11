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
//   Image, AppBar, AlertDialog, BottomSheet, SnackBar, DropdownButtonFormField,
//   CircularProgressIndicator, LinearProgressIndicator, RefreshProgressIndicator
//   (*) RichText omitido si es descendiente directo de Text (evita duplicados)
//
// Loading widgets exponen "loading": true para que el servidor MCP sepa
// que debe esperar antes de continuar con la siguiente acción.
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
import 'package:flutter/foundation.dart';
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

    // Sanitizar TODO el resultado antes de retornar: cualquier double NaN o
    // Infinite (de posiciones, Slider.value/min/max, etc.) se convierte en null
    // para que jsonEncode nunca falle por valores no serializables.
    final sanitized = sanitizeList(result);

    return {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'widget_count': sanitized.length,
      'widgets': sanitized,
    };
  }

  // ── Tree walk ──────────────────────────────────────────────────────────────

  /// Recorre el árbol recursivamente.
  ///
  /// Extrae datos del widget si es interesante y siempre continúa
  /// la recursión en los hijos, excepto para widgets "hoja" cuya
  /// información interna ya fue capturada (TextField, EditableText).
  /// [inOverlay] se propaga a todos los descendientes de un contenedor modal.
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

    // Extraer datos si es un widget con información relevante.
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

    // Siempre continuar recursión, excepto en nodos cuya info
    // interna ya extrajimos (evita entradas duplicadas)
    final skipChildren = widget is EditableText; // interno de TextField
    if (!skipChildren) {
      element.visitChildElements(
        (child) => _walk(child, depth + 1, result, inOverlay: childInOverlay),
      );
    }
  }

  /// Detecta si un widget es la raíz de una capa modal/overlay.
  static bool _isOverlayContainer(Widget w) {
    if (w is AlertDialog || w is Dialog || w is SimpleDialog ||
        w is BottomSheet || w is SnackBar) {
      return true;
    }
    // Private Flutter types — detect by runtime name
    final t = w.runtimeType.toString();
    return t == '_ModalScope' || t == '_ModalBarrier';
  }

  // ── Extracción de datos ────────────────────────────────────────────────────

  /// Retorna un mapa con los datos del widget, o null si no es interesante.
  /// [inOverlay] indica que este widget pertenece a un diálogo/overlay activo.
  static Map<String, dynamic>? _extract(
    Widget widget,
    Element element,
    int depth, {
    bool inOverlay = false,
  }) {
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
      return _entry('Text', depth, pos, mcpKey,
          extra: {'value': value}, inOverlay: inOverlay);
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

    // ── Botones ────────────────────────────────────────────────────────────
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

    // ── Controles de selección ─────────────────────────────────────────────
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
      try { enabled = widget.onChanged != null; } catch (_) { enabled = true; }
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
    // Usado frecuentemente en AppBar para menús desplegables (soluciones,
    // filtros, opciones de pantalla). Sin este bloque el LLM no lo ve en
    // INTERACTIVE y no puede abrirlo.
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
        extra: {
          'tooltip': ?tooltip,
          'enabled': enabled,
        },
        inOverlay: inOverlay,
      );
    }

    // ── Dropdown ───────────────────────────────────────────────────────────
    if (widget is DropdownButtonFormField) {
      String? value;
      try { value = widget.initialValue?.toString(); } catch (_) {}
      return _entry(
        'DropdownButtonFormField',
        depth,
        pos,
        mcpKey,
        extra: {'value': ?value},
        inOverlay: inOverlay,
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
        extra: {'semanticLabel': ?label},
        inOverlay: inOverlay,
      );
    }

    // ── AppBar ─────────────────────────────────────────────────────────────
    if (widget is AppBar) {
      final titleText = widget.title is Text
          ? (widget.title as Text).data
          : _findTextInSubtree(element);
      return _entry('AppBar', depth, pos, mcpKey,
          extra: {'title': ?titleText}, inOverlay: inOverlay);
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
        extra: {'title': ?titleText, 'visible': true},
        inOverlay: true,  // AlertDialog is always an overlay
      );
    }

    if (widget is BottomSheet) {
      return _entry(
        'BottomSheet',
        depth,
        pos,
        mcpKey,
        extra: {'visible': true},
        inOverlay: true,  // BottomSheet is always an overlay
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
        inOverlay: true,  // SnackBar is always an overlay
      );
    }

    // ── Indicadores de carga ───────────────────────────────────────────────
    // "loading": true permite al servidor MCP detectar que la UI está ocupada
    // y esperar antes de continuar con la siguiente acción.
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

  /// Construye una entrada del resultado con los campos estándar.
  /// [inOverlay] = true añade `"overlay": true` para indicar que el widget
  /// pertenece a un diálogo, BottomSheet o AlertDialog activo.
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

  /// Obtiene la posición y tamaño del widget en coordenadas de pantalla.
  ///
  /// Retorna null si el widget no está montado, si el layout no se ha completado,
  /// o si alguna coordenada es NaN / Infinite (puede ocurrir durante transiciones
  /// como cambios de idioma donde el árbol se reconstruye mid-frame).
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
      // Descartar si alguna coordenada no es un número finito válido.
      // Ocurre cuando el RenderBox existe pero el layout aún no terminó.
      if (!x.isFinite || !y.isFinite || !w.isFinite || !h.isFinite) return null;
      return {'x': x, 'y': y, 'w': w, 'h': h};
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
  ///
  /// Propaga NaN/Infinite tal cual — [_position] los detecta con `.isFinite`
  /// antes de incluir las coordenadas en el resultado.
  @visibleForTesting
  static double round(double v) {
    if (!v.isFinite) return v;
    return (v * 10).roundToDouble() / 10;
  }

  // ── Sanitización para JSON ─────────────────────────────────────────────────

  /// Convierte recursivamente cualquier double no finito (NaN, Infinite) en null.
  ///
  /// Necesario porque jsonEncode no acepta NaN ni Infinite. Los NaN pueden venir
  /// de posiciones de widgets mid-layout (transiciones, cambios de idioma) o de
  /// propiedades de widgets como Slider.value/min/max cuando aún no están
  /// inicializados correctamente.
  ///
  /// Uso fuera de tests no recomendado — llamar solo a través de [inspect].
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
