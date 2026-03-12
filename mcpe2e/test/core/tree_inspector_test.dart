// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcpe2e/core/mcp_tree_inspector.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Retorna la primera entrada del árbol inspeccionado que coincida con [type].
Map<String, dynamic>? _findByType(Map<String, dynamic> result, String type) {
  final widgets = result['widgets'] as List;
  for (final w in widgets) {
    if ((w as Map<String, dynamic>)['type'] == type) return w;
  }
  return null;
}

/// Retorna todas las entradas del árbol que coincidan con [type].
List<Map<String, dynamic>> _allByType(
  Map<String, dynamic> result,
  String type,
) {
  final widgets = result['widgets'] as List;
  return widgets
      .cast<Map<String, dynamic>>()
      .where((w) => w['type'] == type)
      .toList();
}

/// Wrapper mínimo para poder usar Scaffold + Material correctamente en tests.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Grupo A — round()
  // Pruebas puras (sin widget tree). Verifican que round() no distorsiona
  // valores normales y propaga NaN/Inf para que _position los detecte.
  // ══════════════════════════════════════════════════════════════════════════

  group('round()', () {
    test('A1: valor exacto sin decimales se preserva', () {
      expect(McpTreeInspector.round(5.0), equals(5.0));
    });

    test('A2: redondea hacia abajo al primer decimal', () {
      expect(McpTreeInspector.round(5.14), equals(5.1));
    });

    test('A3: redondea hacia arriba al primer decimal', () {
      expect(McpTreeInspector.round(5.15), equals(5.2));
    });

    test('A4: NaN se propaga sin modificar', () {
      final result = McpTreeInspector.round(double.nan);
      expect(result.isNaN, isTrue);
    });

    test('A5: Infinity positivo se propaga sin modificar', () {
      final result = McpTreeInspector.round(double.infinity);
      expect(result.isInfinite, isTrue);
      expect(result > 0, isTrue);
    });

    test('A6: Infinity negativo se propaga sin modificar', () {
      final result = McpTreeInspector.round(double.negativeInfinity);
      expect(result.isInfinite, isTrue);
      expect(result < 0, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Grupo B — sanitizeValue()
  // Pruebas puras (sin widget tree). El sanitizador debe:
  //   - convertir NaN / Infinite → null
  //   - dejar intactos todos los demás tipos (double, String, bool, int, null)
  //   - procesar Maps y Lists recursivamente
  // ══════════════════════════════════════════════════════════════════════════

  group('sanitizeValue()', () {
    test('B1: double.nan → null', () {
      expect(McpTreeInspector.sanitizeValue(double.nan), isNull);
    });

    test('B2: double.infinity → null', () {
      expect(McpTreeInspector.sanitizeValue(double.infinity), isNull);
    });

    test('B3: double.negativeInfinity → null', () {
      expect(McpTreeInspector.sanitizeValue(double.negativeInfinity), isNull);
    });

    test('B4: double finito no se modifica', () {
      expect(McpTreeInspector.sanitizeValue(42.5), equals(42.5));
    });

    test('B5: String no se modifica', () {
      expect(McpTreeInspector.sanitizeValue('hello'), equals('hello'));
    });

    test('B6: bool no se modifica', () {
      expect(McpTreeInspector.sanitizeValue(true), isTrue);
    });

    test('B7: int no se modifica', () {
      expect(McpTreeInspector.sanitizeValue(42), equals(42));
    });

    test('B8: null permanece null', () {
      expect(McpTreeInspector.sanitizeValue(null), isNull);
    });

    test('B9: Map con NaN convierte solo la clave afectada', () {
      final input = {'x': double.nan, 'y': 5.0};
      final result = McpTreeInspector.sanitizeValue(input) as Map;
      expect(result['x'], isNull);
      expect(result['y'], equals(5.0));
    });

    test('B10: List con NaN convierte solo los elementos afectados', () {
      final input = [double.nan, 1.0, 'ok'];
      final result = McpTreeInspector.sanitizeValue(input) as List;
      expect(result[0], isNull);
      expect(result[1], equals(1.0));
      expect(result[2], equals('ok'));
    });

    test('B11: Map anidado — NaN en nivel profundo se convierte a null', () {
      final input = {
        'a': {'b': double.nan},
      };
      final result = McpTreeInspector.sanitizeValue(input) as Map;
      final inner = result['a'] as Map;
      expect(inner['b'], isNull);
    });

    test(
      'B12: List de Maps — Infinity dentro de un Map se convierte a null',
      () {
        final input = [
          {'v': double.infinity},
        ];
        final result = McpTreeInspector.sanitizeValue(input) as List;
        final first = result[0] as Map;
        expect(first['v'], isNull);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Grupo C — inspect() estructura
  // Widget tests que crean árboles reales y verifican que inspect() extrae
  // los datos correctos para cada tipo de widget soportado.
  // ══════════════════════════════════════════════════════════════════════════

  group('inspect() — estructura', () {
    testWidgets('C1: tree vacío no produce widgets', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      final result = McpTreeInspector.inspect();
      final widgets = result['widgets'] as List;
      final relevant = widgets.cast<Map<String, dynamic>>().where((w) {
        const tracked = {
          'Text',
          'TextField',
          'ElevatedButton',
          'AppBar',
          'Checkbox',
          'Switch',
        };
        return tracked.contains(w['type']);
      }).toList();
      expect(relevant, isEmpty);
    });

    testWidgets('C2: resultado tiene las claves requeridas', (tester) async {
      await tester.pumpWidget(_wrap(const Text('X')));
      final result = McpTreeInspector.inspect();
      expect(result.containsKey('timestamp'), isTrue);
      expect(result.containsKey('widget_count'), isTrue);
      expect(result.containsKey('widgets'), isTrue);
    });

    testWidgets('C3: widget_count coincide con la longitud de widgets', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('Hello')));
      final result = McpTreeInspector.inspect();
      final widgets = result['widgets'] as List;
      expect(result['widget_count'], equals(widgets.length));
    });

    testWidgets('C4: Text con contenido aparece con su valor', (tester) async {
      await tester.pumpWidget(_wrap(const Text('Hola mundo')));
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'Text');
      expect(entry, isNotNull);
      expect(entry!['value'], equals('Hola mundo'));
    });

    testWidgets('C5: Text vacío no aparece en el resultado', (tester) async {
      await tester.pumpWidget(_wrap(const Text('')));
      final result = McpTreeInspector.inspect();
      final texts = _allByType(result, 'Text');
      final hasEmpty = texts.any(
        (t) => (t['value'] as String?)?.isEmpty == true,
      );
      expect(hasEmpty, isFalse);
    });

    testWidgets('C6: ElevatedButton con onPressed=null → enabled=false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(ElevatedButton(onPressed: null, child: const Text('Tap'))),
      );
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'ElevatedButton');
      expect(entry, isNotNull);
      expect(entry!['enabled'], isFalse);
    });

    testWidgets('C7: ElevatedButton con onPressed → enabled=true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(ElevatedButton(onPressed: () {}, child: const Text('Tap'))),
      );
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'ElevatedButton');
      expect(entry, isNotNull);
      expect(entry!['enabled'], isTrue);
    });

    testWidgets('C8: TextField con hintText aparece con hint correcto', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const TextField(decoration: InputDecoration(hintText: 'Email'))),
      );
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'TextField');
      expect(entry, isNotNull);
      expect(entry!['hint'], equals('Email'));
    });

    testWidgets('C9: AppBar con title extrae el texto del título', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Dashboard')),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'AppBar');
      expect(entry, isNotNull);
      expect(entry!['title'], equals('Dashboard'));
    });

    testWidgets('C10: Checkbox marcado aparece con value=true', (tester) async {
      await tester.pumpWidget(_wrap(Checkbox(value: true, onChanged: (_) {})));
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'Checkbox');
      expect(entry, isNotNull);
      expect(entry!['value'], isTrue);
    });

    testWidgets('C11: Switch apagado aparece con value=false', (tester) async {
      await tester.pumpWidget(_wrap(Switch(value: false, onChanged: (_) {})));
      final result = McpTreeInspector.inspect();
      final entry = _findByType(result, 'Switch');
      expect(entry, isNotNull);
      expect(entry!['value'], isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Grupo D — Regresión JSON / NaN  (crítico)
  //
  // D1 y D2: los tests directos del bug que bloqueó inspect_ui en Settings.
  //   jsonEncode(inspect()) NUNCA debe lanzar excepción, sin importar el
  //   estado del widget tree en ese momento.
  // D3, D4: el sanitizador no bloquea jsonEncode y no corrompe datos válidos.
  // ══════════════════════════════════════════════════════════════════════════

  group('Regresión JSON / NaN', () {
    testWidgets('D1: jsonEncode(inspect()) no lanza con tree simple', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const Text('ok')));
      final result = McpTreeInspector.inspect();
      expect(() => jsonEncode(result), returnsNormally);
    });

    testWidgets('D2: jsonEncode(inspect()) no lanza con tree complejo '
        '(AppBar + TextField + Button + Text)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: Column(
              children: [
                const TextField(
                  decoration: InputDecoration(hintText: 'Language'),
                ),
                ElevatedButton(onPressed: () {}, child: const Text('Save')),
                const Text('Current: EN'),
                Checkbox(value: true, onChanged: (_) {}),
                Switch(value: false, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final result = McpTreeInspector.inspect();
      expect(() => jsonEncode(result), returnsNormally);
    });

    test('D3: sanitizeList con NaN → jsonEncode no lanza', () {
      final input = [
        {'v': double.nan, 'label': 'test'},
        {'x': double.infinity, 'y': 5.0},
      ];
      final sanitized = McpTreeInspector.sanitizeList(input);
      expect(() => jsonEncode(sanitized), returnsNormally);
    });

    test('D4: sanitizeList preserva datos válidos intactos', () {
      final input = [
        {'v': 5.0, 's': 'text', 'b': true, 'i': 42},
      ];
      final result = McpTreeInspector.sanitizeList(input);
      final first = result.first;
      expect(first['v'], equals(5.0));
      expect(first['s'], equals('text'));
      expect(first['b'], isTrue);
      expect(first['i'], equals(42));
    });
  });
}
